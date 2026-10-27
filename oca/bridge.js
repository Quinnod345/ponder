/**
 * ponder → OCA bridge (SPEC §6).
 *
 * Writes a ponder session into the Oneiro Cognitive Architecture's Postgres so the
 * loop can remember having thought about a subject before, and so its self-model
 * (predicted churn vs actual churn) accumulates across sessions.
 *
 * Design constraints, all load-bearing:
 *
 *   - Zero npm dependencies. Everything goes through `psql` via child_process.execFile
 *     with an argv array. No shell, ever.
 *   - No value is ever concatenated into SQL. Every SQL statement in this file is a
 *     fixed string literal containing only `:'name'` placeholders; values travel as
 *     `-v name=value` argv entries and psql expands `:'name'` into a properly escaped
 *     SQL literal. Verified against the live database with a value containing a single
 *     quote, a doubled quote, a newline, a carriage return, a tab, a semicolon, a
 *     backslash, non-ASCII text and literal `:var` lookalikes — it round-tripped byte
 *     exact and nothing executed.
 *   - psql variable interpolation does NOT happen under `-c` (psql-specific features are
 *     disabled there), so SQL is fed on stdin with `-f -`. That is the whole reason for
 *     the stdin plumbing in `psql()`.
 *   - Every exported function wraps its entire body. The bridge never throws into the
 *     engine. Any non-zero exit, timeout, malformed output or parse error appends one
 *     diagnostic line to <sessionDir>/oca.log and returns null. That file is the bridge's
 *     only log (SPEC 6.3); a line raised before any session exists is held and drained
 *     into the first session log that resolves, and goes to stderr if none ever does.
 *
 * The one deliberate exception to "null on failure" is `probe()`, which returns
 * `{ reachable: false, ... }` rather than null when it successfully determines the
 * database is unusable. That negative result is the probe's answer, not a failure to
 * answer, and PONDER_OCA=on needs it in order to be a hard error the engine can
 * surface. `probe()` returns null only when PONDER_OCA=off, where there is nothing to
 * probe. Consumers should read `p && p.reachable`.
 *
 * Environment:
 *   PONDER_OCA      auto (default) | on | off
 *   PONDER_OCA_DSN  default postgres://localhost/oneiro
 *   PONDER_PSQL     path to the psql binary (default: `psql` on PATH)
 */

import { execFile } from 'node:child_process';
import { appendFileSync, existsSync, mkdirSync, writeSync } from 'node:fs';
import { homedir } from 'node:os';
import { dirname, join } from 'node:path';

const DEFAULT_DSN = 'postgres://localhost/oneiro';

/** SPEC §6: 2s reachability probe under auto, 5s per call for everything else. */
const PROBE_TIMEOUT_MS = 2000;
const CALL_TIMEOUT_MS = 5000;

/** Per-value and total argv budgets. macOS ARG_MAX is 1 MiB; stay far below it. */
const MAX_VALUE_CHARS = 16384;
const MAX_TOTAL_CHARS = 240000;

/** How much of pass N's churn we expect to survive into pass N+1, and the hit band. */
const CHURN_DECAY = 0.6;
const FORECAST_BAND = 0.05;

/**
 * Sanity ceilings, not semantics. Churn and surprise are unbounded ratios (SPEC §4) but a
 * garbage metrics file must not produce `1e+21`, which would fail the ::int / ::float8
 * casts and lose the write.
 */
const MAX_RATIO = 1000;
const MAX_PASS = 1000000;

const PERSPECTIVES = ['skeptic', 'builder', 'dreamer', 'empath'];
const DELTA_OPS = ['add', 'edit', 'change', 'delete', 'unit-add', 'unit-delete'];

// ---------------------------------------------------------------------------
// Process-level state
// ---------------------------------------------------------------------------

/** Memoised reachability probe: exactly one per process (per DSN). */
let probeCache = null; // { dsn, mode, promise }
/** Last resolved probe result, so the synchronous isEnabled() can reflect it. */
let probeResult = null;
/** Last session directory we successfully resolved, for logging session-less calls. */
let lastSessionDir = null;
/** Diagnostics from session-less calls (probe, priorPondering), held until a session dir appears. */
let pendingLog = [];
let exitFlushArmed = false;

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

function mode() {
  const raw = String(process.env.PONDER_OCA ?? 'auto').trim().toLowerCase();
  return raw === 'on' || raw === 'off' || raw === 'auto' ? raw : 'auto';
}

function dsn() {
  const raw = String(process.env.PONDER_OCA_DSN ?? '').trim();
  return raw === '' ? DEFAULT_DSN : raw;
}

function psqlBin() {
  const raw = String(process.env.PONDER_PSQL ?? '').trim();
  return raw === '' ? 'psql' : raw;
}

/** Never leak a password into oca.log. */
function redactDsn(url) {
  return String(url).replace(/:\/\/([^/@\s]*):([^@\s]*)@/, '://$1:***@');
}

// ---------------------------------------------------------------------------
// Value coercion — everything that reaches psql goes through here
// ---------------------------------------------------------------------------

/**
 * A value bound for a `jsonb` column. It has to stay syntactically valid JSON all the way
 * into psql: clipping it like ordinary text leaves a half-finished token, Postgres rejects
 * the cast, and the whole statement — episodic row, hypothesis, events — is lost. Marking
 * it lets `str()` and the argv backstop clip it through `clipJson()` instead.
 */
class JsonText {
  constructor(text) {
    this.text = text;
  }

  toString() {
    return this.text;
  }
}

function str(value) {
  if (value instanceof JsonText) return clipJson(value.text, MAX_VALUE_CHARS);
  if (value === null || value === undefined) return '';
  let s;
  const t = typeof value;
  if (t === 'string') s = value;
  else if (t === 'number') s = Number.isFinite(value) ? String(value) : '';
  else if (t === 'boolean' || t === 'bigint') s = String(value);
  else {
    try {
      s = JSON.stringify(value) ?? '';
    } catch {
      s = '';
    }
  }
  // NUL cannot travel in argv and would truncate the value silently.
  s = s.replace(/\0/g, '');
  if (s.length > MAX_VALUE_CHARS) s = `${s.slice(0, MAX_VALUE_CHARS)}…[truncated]`;
  return s;
}

/**
 * A finite number, or `fallback` when there is no number here.
 *
 * **Absence is not zero.** `Number(null)`, `Number('')`, `Number(false)` and `Number([])`
 * are all `0` in JavaScript, so the obvious one-liner turns every missing signal into a
 * measurement reading "nothing moved" — which is exactly the reading SPEC §4's null signals
 * exist to prevent, and exactly how pass 1's fabricated `churn 0` used to get onto the
 * record. Only a finite number, a numeric string or a bigint is a value here; everything
 * else, `null` and `undefined` included, takes the fallback.
 */
function num(value, fallback) {
  if (typeof value === 'number') return Number.isFinite(value) ? value : fallback;
  if (typeof value === 'bigint') return Number(value);
  if (typeof value === 'string') {
    const trimmed = value.trim();
    if (trimmed === '') return fallback;
    const n = Number(trimmed);
    return Number.isFinite(n) ? n : fallback;
  }
  return fallback;
}

/**
 * A measured ratio clamped to [0, hi] — or `null` when the engine did not measure it.
 *
 * SPEC §4 emits `churn`, `novelty`, `thrash` and `surprise` as `null` on pass 1: all four
 * measure change against a pass that does not exist. Every unmeasured number in this bridge
 * goes through here so that "not measured" can never quietly become `0`. A zero is a claim —
 * it says the loop moved nothing — and on pass 1 that claim is the exact opposite of what
 * happened. Callers turn a `null` into an empty psql variable, which the SQL reads through
 * `nullif(…,'')` and stores as a genuine NULL.
 */
function maybeRatio(value, hi) {
  const n = num(value, null);
  return n === null ? null : clamp(n, 0, hi);
}

function clamp(n, lo, hi) {
  return n < lo ? lo : n > hi ? hi : n;
}

function round(n, places = 3) {
  const f = 10 ** places;
  return Math.round(n * f) / f;
}

/**
 * `JSON.stringify` escapes a NUL as u0000 and an unpaired surrogate as uD800–uDFFF (each
 * preceded by a backslash). Postgres accepts neither in `jsonb` — either one aborts the
 * entire statement — so drop the NUL and fold a lone surrogate to U+FFFD.
 *
 * Only an odd run of backslashes before the `u` is a real escape. An even run means the
 * backslash was itself escaped and the characters are literal text a caller wrote on
 * purpose, which must survive byte for byte.
 */
function repairJsonEscapes(text) {
  return text.replace(/(\\+)u(0000|[dD][89a-fA-F][0-9a-fA-F]{2})/g, (match, slashes, hex) => {
    if (slashes.length % 2 === 0) return match;
    const keep = slashes.slice(0, -1);
    return hex.toLowerCase() === '0000' ? keep : `${keep}\\ufffd`;
  });
}

/** Stringify, repairing the escapes Postgres rejects; optionally clip long strings in place. */
function stringifyJson(value, stringCap) {
  try {
    const replacer =
      stringCap === undefined
        ? undefined
        : (key, v) => (typeof v === 'string' && v.length > stringCap ? `${v.slice(0, stringCap)}…[truncated]` : v);
    const s = JSON.stringify(value, replacer);
    return typeof s === 'string' ? repairJsonEscapes(s) : null;
  } catch {
    return null;
  }
}

/**
 * Clip a JSON document to `budget` characters and still hand back valid JSON. A plain
 * slice would cut a token in half, so an oversized document collapses into a valid
 * summary object that says how much was dropped.
 */
function clipJson(text, budget) {
  const s = typeof text === 'string' ? text : '{}';
  if (s.length <= budget) return s;
  let room = Math.max(0, budget - 80);
  for (let i = 0; i < 8 && room > 0; i += 1) {
    // The slice can land between the halves of a surrogate pair, so the preview goes
    // through the same escape repair as everything else.
    const out = repairJsonEscapes(
      JSON.stringify({ truncated: true, chars: s.length, preview: s.slice(0, room) }),
    );
    if (out.length <= budget) return out;
    room = Math.floor(room / 2);
  }
  return '{"truncated":true}';
}

/**
 * Render any value as a jsonb-safe document: valid JSON, free of the escapes Postgres
 * rejects, and already small enough that nothing downstream has to cut it.
 *
 * Structure is preserved wherever it can be — an oversized document has its long strings
 * clipped in place first, so `source_data`'s numeric keys (which the next pass reads back
 * to score its forecast) always survive. Only a document still too large after that
 * collapses into a summary object.
 */
function jsonValue(value, budget = MAX_VALUE_CHARS) {
  const v = value === undefined ? {} : value;
  const s = stringifyJson(v);
  if (s === null) return new JsonText('{}');
  if (s.length <= budget) return new JsonText(s);
  const clipped = stringifyJson(v, Math.max(200, Math.floor(budget / 8)));
  if (clipped !== null && clipped.length <= budget) return new JsonText(clipped);
  return new JsonText(clipJson(s, budget));
}

const SEVERITY_WORDS = {
  none: 0.05,
  trivial: 0.15,
  info: 0.2,
  low: 0.25,
  minor: 0.25,
  medium: 0.5,
  moderate: 0.5,
  warning: 0.6,
  high: 0.8,
  major: 0.8,
  severe: 0.9,
  critical: 0.95,
  fatal: 1,
};

/**
 * OCA stores severity as a 0–1 float, but callers name it ("high", "medium") — the engine
 * does, in every `metacognitionTriggers` entry. Folding a name to the 0.5 default would be
 * silent data loss with teeth: SPEC §6.2's escalate tie-breaker only fires at 0.7 and
 * above, so a `high` thrash alert flattened to 0.5 can never tip a verdict.
 */
function severityValue(value, fallback = 0.5) {
  if (typeof value === 'number') return Number.isFinite(value) ? clamp(value, 0, 1) : fallback;
  const word = String(value ?? '').trim().toLowerCase();
  if (word === '') return fallback;
  if (Object.prototype.hasOwnProperty.call(SEVERITY_WORDS, word)) return SEVERITY_WORDS[word];
  const n = Number(word);
  return Number.isFinite(n) ? clamp(n, 0, 1) : fallback;
}

/** Escape LIKE metacharacters so a subject containing % or _ is matched literally. */
function likeLiteral(s) {
  return String(s).replace(/([\\%_])/g, '\\$1');
}

// ---------------------------------------------------------------------------
// Session shape readers — tolerant, because the engine owns session.json
// ---------------------------------------------------------------------------

function slugOf(session) {
  if (typeof session === 'string' && session.trim() !== '') return session.trim();
  const s = session && typeof session === 'object' ? session.slug : null;
  return typeof s === 'string' && s.trim() !== '' ? s.trim() : 'unknown';
}

function fieldOf(session, key, fallback = '') {
  if (!session || typeof session !== 'object') return fallback;
  const v = session[key];
  return typeof v === 'string' && v !== '' ? v : fallback;
}

function domainOf(session) {
  return `ponder:${slugOf(session)}`;
}

// ---------------------------------------------------------------------------
// Logging — one line per failure, appended to <sessionDir>/oca.log
// ---------------------------------------------------------------------------

function resolveSessionDir(session) {
  try {
    if (session && typeof session === 'object') {
      for (const key of ['ocaLogDir', 'dir', 'sessionDir']) {
        const v = session[key];
        if (typeof v === 'string' && v !== '') return v;
      }
      const paths = session.paths;
      if (paths && typeof paths === 'object') {
        for (const key of ['dir', 'sessionDir', 'session']) {
          const v = paths[key];
          if (typeof v === 'string' && v !== '') return v;
        }
      }
      const slug = typeof session.slug === 'string' ? session.slug : '';
      if (slug !== '') {
        const project = typeof session.project === 'string' ? session.project : '';
        if (project !== '') {
          const p = join(project, '.ponder', slug);
          if (existsSync(p)) return p;
        }
        const h = join(homedir(), '.ponder', slug);
        if (existsSync(h)) return h;
        if (project !== '' && existsSync(join(project, '.ponder'))) return join(project, '.ponder', slug);
      }
    }
  } catch {
    /* fall through to the process-level log */
  }
  return null;
}

/** Collapse anything multi-line into a single log line. */
function oneLine(s) {
  return String(s ?? '')
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, 600);
}

function writeLines(file, lines) {
  try {
    mkdirSync(dirname(file), { recursive: true });
    appendFileSync(file, lines.join(''), 'utf8');
    return true;
  } catch {
    return false;
  }
}

/**
 * `probe()` and `priorPondering()` take no session, so at the moment they fail there may
 * be no session directory to log into yet. Hold their lines and flush them into the first
 * session log that resolves — usually milliseconds later, when `ponder start` calls
 * recordStart().
 *
 * SPEC §6.3 gives the bridge exactly one log, `.ponder/<slug>/oca.log`, and there is no
 * second one. A line that never finds a session is written to stderr on the way out —
 * where the user already is — rather than to a `~/.ponder/oca.log` that the contract does
 * not describe, that nothing rotates, and that exists only on machines where `~/.ponder`
 * happens to have been created already.
 *
 * In practice this drain stays silent. The only genuinely session-less command is
 * `doctor`, and `probe()` hands its diagnostic straight back to its caller — which prints
 * it — instead of buffering a duplicate. Every other session-less line belongs to
 * `priorPondering()`, which `ponder start` follows immediately with `recordStart()`, and
 * that resolves the session directory the buffered lines drain into.
 */
function armExitFlush() {
  if (exitFlushArmed) return;
  exitFlushArmed = true;
  try {
    process.on('exit', () => {
      if (pendingLog.length === 0) return;
      const lines = pendingLog;
      pendingLog = [];
      if (lastSessionDir) {
        writeLines(join(lastSessionDir, 'oca.log'), lines);
        return;
      }
      try {
        // Synchronous: an 'exit' handler gets no async turn to flush a stream.
        writeSync(2, lines.map((line) => `ponder oca: ${line}`).join(''));
      } catch {
        /* a closed or full stderr is not worth an exception on the way out */
      }
    });
  } catch {
    /* no process object worth worrying about */
  }
}

/**
 * Remember this session's directory and drain anything buffered from session-less calls
 * into it. Called on every session-bearing entry point, success or failure, so a probe
 * diagnostic from a millisecond earlier lands in the right oca.log.
 */
function rememberSession(session) {
  try {
    const dir = resolveSessionDir(session);
    if (!dir) return;
    lastSessionDir = dir;
    if (pendingLog.length === 0) return;
    const buffered = pendingLog;
    pendingLog = [];
    writeLines(join(dir, 'oca.log'), buffered);
  } catch {
    /* never break the engine over a log file */
  }
}

function log(session, op, message) {
  try {
    const line = `${new Date().toISOString()} ${op} ${oneLine(message)}\n`;
    const dir = resolveSessionDir(session) || lastSessionDir;
    if (!dir) {
      if (pendingLog.length < 50) pendingLog.push(line);
      armExitFlush();
      return;
    }
    lastSessionDir = dir;
    const file = join(dir, 'oca.log');
    if (pendingLog.length > 0) {
      const buffered = pendingLog;
      pendingLog = [];
      writeLines(file, buffered);
    }
    writeLines(file, [line]);
  } catch {
    // Logging must never be the thing that breaks the engine.
  }
}

// ---------------------------------------------------------------------------
// psql plumbing
// ---------------------------------------------------------------------------

/**
 * Run one SQL statement through psql.
 *
 * @param {string} sql   Fixed SQL text. Values appear only as :'name' placeholders.
 * @param {object} vars  name → value. Every :'name' in `sql` MUST be present here.
 * @param {object} opts  { timeoutMs, connectTimeout }
 * @returns {Promise<{ ok: boolean, stdout: string, stderr: string, code: any, ms: number, reason: string }>}
 */
function psql(sql, vars, opts = {}) {
  return new Promise((resolve) => {
    const started = Date.now();
    const done = (ok, extra) =>
      resolve({ ok, stdout: '', stderr: '', code: null, reason: '', ms: Date.now() - started, ...extra });

    let args;
    try {
      const url = dsn();
      if (url.startsWith('-')) {
        done(false, { reason: `refusing DSN that looks like a flag: ${redactDsn(url)}` });
        return;
      }

      // Per-value truncation happens in str(); this is the whole-argv backstop. A jsonb
      // value is clipped through clipJson() so it stays parseable — a raw slice here would
      // fail the cast and lose the entire statement.
      const entries = Object.entries(vars || {}).map(([k, v]) => [k, str(v), v instanceof JsonText]);
      const total = entries.reduce((n, [k, v]) => n + k.length + v.length + 4, 0);
      if (total > MAX_TOTAL_CHARS && entries.length > 0) {
        const budget = Math.max(256, Math.floor(MAX_TOTAL_CHARS / entries.length));
        for (const entry of entries) {
          if (entry[1].length <= budget) continue;
          entry[1] = entry[2] ? clipJson(entry[1], budget) : `${entry[1].slice(0, budget)}…[truncated]`;
        }
      }

      args = [
        '-X', // ignore ~/.psqlrc — determinism
        '-q', // no "INSERT 0 1" chatter
        '-w', // never prompt for a password; stdin is carrying SQL
        '-t', // tuples only
        '-A', // unaligned
        '-P',
        'pager=off',
        '-v',
        'ON_ERROR_STOP=1',
      ];
      for (const [k, v] of entries) args.push('-v', `${k}=${v}`);
      args.push('-d', url, '-f', '-');
    } catch (err) {
      done(false, { reason: `argv build failed: ${err && err.message}` });
      return;
    }

    const timeoutMs = num(opts.timeoutMs, CALL_TIMEOUT_MS);
    const connectTimeout = String(Math.max(1, Math.floor(num(opts.connectTimeout, 3))));

    let child;
    try {
      child = execFile(
        psqlBin(),
        args,
        {
          timeout: timeoutMs,
          killSignal: 'SIGKILL',
          maxBuffer: 8 * 1024 * 1024,
          windowsHide: true,
          env: {
            ...process.env,
            PGCONNECT_TIMEOUT: connectTimeout,
            PGAPPNAME: 'ponder',
            PGCLIENTENCODING: 'UTF8',
            PAGER: 'cat',
          },
        },
        (err, stdout, stderr) => {
          const ms = Date.now() - started;
          const out = String(stdout ?? '');
          const errOut = String(stderr ?? '');
          if (!err) {
            resolve({ ok: true, stdout: out, stderr: errOut, code: 0, reason: '', ms });
            return;
          }
          const timedOut = err.killed === true || err.signal === 'SIGKILL' || err.signal === 'SIGTERM';
          const code = err.code ?? null;
          const reason = timedOut
            ? `timeout after ${timeoutMs}ms`
            : `exit=${code} ${oneLine(errOut) || oneLine(err.message)}`;
          resolve({ ok: false, stdout: out, stderr: errOut, code, reason, ms });
        },
      );
    } catch (err) {
      done(false, { reason: `spawn failed: ${err && err.message}` });
      return;
    }

    // psql may die before draining stdin (bad DSN, missing binary); EPIPE is expected.
    try {
      if (child.stdin) {
        child.stdin.on('error', () => {});
        child.stdin.end(sql, 'utf8');
      }
    } catch {
      /* the execFile callback will report the real failure */
    }
    child.on('error', () => {}); // handled by the execFile callback
  });
}

/**
 * Run a statement whose single output column is JSON, and parse it.
 * Returns the parsed value, or null on any failure (already logged).
 */
async function psqlJson(session, op, sql, vars, opts = {}) {
  const res = await psql(sql, vars, opts);
  if (!res.ok) {
    log(session, op, `FAIL ${res.reason} dsn=${redactDsn(dsn())} ms=${res.ms}`);
    return null;
  }
  const text = res.stdout.trim();
  if (text === '') {
    log(session, op, `FAIL empty result dsn=${redactDsn(dsn())} ms=${res.ms}`);
    return null;
  }
  try {
    return JSON.parse(text);
  } catch (err) {
    log(session, op, `FAIL unparseable result (${err && err.message}) head=${oneLine(text.slice(0, 200))}`);
    return null;
  }
}

// ---------------------------------------------------------------------------
// Reachability
// ---------------------------------------------------------------------------

const REQUIRED_TABLES = ['episodic_memory', 'deliberations', 'metacognitive_observations', 'hypotheses', 'cognitive_events'];

const PROBE_SQL = `
SELECT json_build_object(
  'server', current_setting('server_version'),
  'database', current_database(),
  'tables', coalesce((
    SELECT json_agg(table_name ORDER BY table_name)
    FROM information_schema.tables
    WHERE table_schema NOT IN ('pg_catalog','information_schema')
      AND table_name IN ('episodic_memory','deliberations','metacognitive_observations','hypotheses','cognitive_events')
  ), '[]'::json)
);
`;

async function runProbe(currentMode) {
  const url = dsn();
  const timeoutMs = currentMode === 'on' ? CALL_TIMEOUT_MS : PROBE_TIMEOUT_MS;
  const started = Date.now();
  const res = await psql(PROBE_SQL, {}, { timeoutMs, connectTimeout: currentMode === 'on' ? 4 : 2 });

  const base = { reachable: false, dsn: url, note: '', mode: currentMode, schema: false, missing: REQUIRED_TABLES.slice(), ms: 0 };

  if (!res.ok) {
    const result = { ...base, ms: Date.now() - started, note: `unreachable: ${res.reason}` };
    result.fatal = currentMode === 'on';
    return result;
  }

  let parsed;
  try {
    parsed = JSON.parse(res.stdout.trim());
  } catch {
    const result = { ...base, ms: Date.now() - started, note: `unreadable probe response: ${oneLine(res.stdout.slice(0, 200))}` };
    result.fatal = currentMode === 'on';
    return result;
  }

  const present = Array.isArray(parsed && parsed.tables) ? parsed.tables : [];
  const missing = REQUIRED_TABLES.filter((t) => !present.includes(t));
  const ms = Date.now() - started;

  if (missing.length > 0) {
    return {
      reachable: false,
      dsn: url,
      note: `connected to ${parsed.database} but the OCA schema is incomplete — missing: ${missing.join(', ')}`,
      mode: currentMode,
      schema: false,
      missing,
      ms,
      fatal: currentMode === 'on',
    };
  }

  return {
    reachable: true,
    dsn: url,
    note: `connected to ${parsed.database} on PostgreSQL ${parsed.server} in ${ms}ms; all ${REQUIRED_TABLES.length} OCA tables present`,
    mode: currentMode,
    schema: true,
    missing: [],
    ms,
    fatal: false,
  };
}

/**
 * Exactly one probe per process. Keyed on mode + DSN so that a stable configuration —
 * which is every real run — probes once and every later call reuses the answer, while
 * repointing PONDER_OCA_DSN or flipping auto→on mid-process re-probes rather than
 * reusing a result that was measured under different rules.
 */
function memoisedProbe(currentMode) {
  const url = dsn();
  if (probeCache && probeCache.dsn === url && probeCache.mode === currentMode) return probeCache.promise;
  const promise = runProbe(currentMode).then((result) => {
    probeResult = result;
    return result;
  });
  probeCache = { dsn: url, mode: currentMode, promise };
  return promise;
}

/**
 * Gate for every write/read: is the bridge on AND is OCA usable?
 * Under `on` an unreachable OCA still short-circuits here — the engine surfaces the
 * hard error from probe(); the bridge does not spend 5 seconds per call proving it.
 */
async function ready(session, op) {
  rememberSession(session);
  if (mode() === 'off') return false;
  const p = await memoisedProbe(mode());
  if (!p || !p.reachable) {
    log(session, op, `SKIP oca unreachable (${p ? p.note : 'no probe result'}) mode=${mode()} dsn=${redactDsn(dsn())}`);
    return false;
  }
  return true;
}

// ---------------------------------------------------------------------------
// Rendering helpers for the text columns
// ---------------------------------------------------------------------------

/**
 * SPEC §6.1 wants the per-op delta counts in `episodic_memory.actual_outcome`, and the
 * engine writes them as `metrics.deltas = { total, byOp: { add: 1, edit: 1 } }`. Accept
 * that shape, a flat `{ add: 1 }` map, and a raw array of delta objects, so a rename in
 * lib/metrics.js degrades to a different key rather than to `deltas=?`.
 */
function countsFrom(src) {
  if (Array.isArray(src)) {
    const tally = {};
    for (const d of src) {
      const op = d && typeof d.op === 'string' ? d.op : 'unknown';
      tally[op] = (tally[op] || 0) + 1;
    }
    const parts = Object.entries(tally).map(([k, v]) => `${k}=${v}`);
    return parts.length ? parts.join(' ') : 'deltas=0';
  }

  if (!src || typeof src !== 'object') return null;

  const byOp = src.byOp && typeof src.byOp === 'object' && !Array.isArray(src.byOp) ? src.byOp : null;
  const table = byOp || src;
  const parts = [];
  for (const op of DELTA_OPS) {
    const n = num(table[op], null);
    if (n !== null) parts.push(`${op}=${n}`);
  }
  for (const [k, v] of Object.entries(table)) {
    if (DELTA_OPS.includes(k) || k === 'byOp' || k === 'total') continue;
    const n = num(v, null);
    if (n !== null) parts.push(`${k}=${n}`);
  }

  const total = num(src.total, null);
  if (parts.length === 0) return total === null ? null : `deltas=${total}`;
  return total === null ? parts.join(' ') : `${parts.join(' ')} total=${total}`;
}

function deltaCountsText(metrics) {
  const m = metrics && typeof metrics === 'object' ? metrics : {};
  for (const candidate of [m.deltaCounts, m.counts, m.ops, m.deltas]) {
    const text = countsFrom(candidate);
    if (text !== null) return text;
  }
  const total = num(m.deltaCount, null);
  return total === null ? 'deltas=?' : `deltas=${total}`;
}

function metricsText(metrics) {
  const m = metrics && typeof metrics === 'object' ? metrics : {};
  const parts = [];
  for (const key of ['coverage', 'novelty', 'churn', 'thrash', 'surprise', 'stall', 'confidenceFloor', 'voices']) {
    const n = num(m[key], null);
    if (n !== null) parts.push(`${key}=${round(n, 3)}`);
  }
  return parts.join(' ');
}

/**
 * Render whatever the engine hands us as a summary into one readable line.
 * Accepts a string, or an object of scalars, or an object with a `text`/`note` field.
 */
function summaryText(summary) {
  if (summary === null || summary === undefined) return '';
  if (typeof summary === 'string') return summary;
  if (typeof summary !== 'object') return String(summary);

  const parts = [];
  for (const key of ['text', 'note', 'reason', 'verdict', 'decision', 'status']) {
    const v = summary[key];
    if (typeof v === 'string' && v !== '') parts.push(key === 'text' || key === 'note' ? v : `${key}=${v}`);
  }
  for (const [k, v] of Object.entries(summary)) {
    if (['text', 'note', 'reason', 'verdict', 'decision', 'status'].includes(k)) continue;
    if (v === null || v === undefined) continue;
    if (typeof v === 'number' || typeof v === 'boolean') parts.push(`${k}=${v}`);
    else if (typeof v === 'string' && v.length <= 200) parts.push(`${k}=${v}`);
    else parts.push(`${k}=${oneLine(jsonValue(v)).slice(0, 200)}`);
  }
  return parts.join(' ');
}

/** Pull one perspective's argument + confidence out of whatever deliberation.json looks like. */
function perspectiveOf(deliberation, name) {
  const d = deliberation && typeof deliberation === 'object' ? deliberation : {};
  const list = Array.isArray(d) ? d : Array.isArray(d.perspectives) ? d.perspectives : null;
  const fromList = list
    ? list.find((e) => e && String(e.perspective || e.name || '').trim().toLowerCase() === name)
    : null;
  const byName = d.perspectives && typeof d.perspectives === 'object' && !Array.isArray(d.perspectives) ? d.perspectives[name] : null;
  const candidates = [d[name], byName, fromList, d[`${name}_argument`], d[`${name}Argument`]];

  let argument = '';
  let confidence = null;

  for (const c of candidates) {
    if (c === null || c === undefined) continue;
    if (typeof c === 'string') {
      if (argument === '') argument = c;
      continue;
    }
    if (typeof c === 'object') {
      for (const key of ['argument', 'text', 'says', 'reasoning', 'claim']) {
        if (typeof c[key] === 'string' && c[key] !== '' && argument === '') argument = c[key];
      }
      if (Array.isArray(c.points) && argument === '') argument = c.points.filter((p) => typeof p === 'string').join('\n');
      const conf = num(c.confidence, null);
      if (conf !== null && confidence === null) confidence = clamp(conf, 0, 1);
    }
  }

  if (confidence === null) {
    const flat = num(d[`${name}_confidence`], null) ?? num(d[`${name}Confidence`], null);
    if (flat !== null) confidence = clamp(flat, 0, 1);
  }

  return { argument, confidence };
}

function voicesIn(deliberation) {
  let n = 0;
  for (const p of PERSPECTIVES) if (perspectiveOf(deliberation, p).argument !== '') n += 1;
  return n;
}

// ---------------------------------------------------------------------------
// SQL — every value is a :'name' placeholder, never interpolated in JS
// ---------------------------------------------------------------------------

const SQL_PRIOR_PONDERING = `
SELECT coalesce(json_agg(t ORDER BY t.timestamp DESC), '[]'::json) FROM (
  SELECT content, actual_outcome, timestamp
  FROM episodic_memory
  WHERE event_type IN ('ponder_converged','ponder_stopped','ponder_start')
    AND content ILIKE '%' || :'subject' || '%' ESCAPE '\\'
  ORDER BY timestamp DESC
  LIMIT 5
) t;
`;

const SQL_RECORD_START = `
WITH ep AS (
  -- surprise_magnitude is set to NULL rather than left to the column's 0.0 default: across
  -- ponder's whole timeline the column is non-null exactly when a surprise was measured,
  -- and SPEC 6.1 measures one only on a ponder_pass row. A 0 here would read as "the start
  -- went exactly as predicted", which is not something anyone scored.
  INSERT INTO episodic_memory
    (event_type, content, prediction, surprise_magnitude, importance_score, emotional_valence, consolidation_status)
  VALUES ('ponder_start', :'content', nullif(:'prediction',''), NULL, 0.7, 0.1, 'raw')
  RETURNING id
)
SELECT json_build_object('id', ep.id, 'episodeId', ep.id, 'sessionRef', ep.id) FROM ep;
`;

/**
 * One statement, one transaction, three moves:
 *   1. episodic_memory        — this pass happened, here is prediction vs reality.
 *   2. hypotheses (close)     — the forecast pass N-1 made about pass N is now testable.
 *                               Score it in SQL against the forecast stored in source_data.
 *   3. hypotheses (open)      — pass N forecasts pass N+1's churn, to be closed next pass.
 * Plus a cognitive_event for each hypothesis move. The `closed` CTE yields zero rows until
 * pass 3 — pass 1 opens no forecast and pass 2 has none behind it to settle — so until then
 * the hypothesis_tested event inserts zero rows too.
 *
 * Nothing measured is ever fabricated. `churn` and `surprise` arrive empty when the engine
 * had no such signal — SPEC §4 makes both null on pass 1 — and every use of them here is
 * `nullif(…,'')`, so the column goes in NULL rather than 0. The `opened` CTE is gated on
 * `forecastable`, which is false exactly when there is no churn to decay, so a pass with no
 * churn signal opens no forecast at all instead of forecasting zero movement.
 *
 * Data-modifying CTEs all see the same snapshot, so `closed` cannot accidentally close
 * the row `opened` inserts.
 *
 * Concurrency. Two ponder processes judging the same slug at the same time used to both
 * read the same pending row and both write it: the second close overwrote the first, and
 * both went on to open a forecast, leaving an extra pending row for `decide stop` to
 * expire. Nothing corrupted, but one measured surprise vanished — and the falling
 * surprise series is the whole point of the hypothesis lifecycle. Three guards, each
 * doing a different job:
 *
 *   `lk`   — one non-blocking advisory lock per domain, held for this statement's
 *            transaction, so only one ponder process runs the hypothesis lifecycle for a
 *            slug at a time. The loser skips both moves and is told it did (`lock` in the
 *            result), rather than waiting and risking the 5s call timeout, which would
 *            cost it the episodic row as well. The key is namespaced under a ponder-only
 *            first argument so it cannot collide with another OCA subsystem's lock.
 *   `FOR UPDATE SKIP LOCKED` — the claim itself, enforced by the database rather than by
 *            convention. Exactly one transaction can hold the pending row; anyone who
 *            arrives to find it locked gets no row and closes nothing. This holds even
 *            against a writer that knows nothing about the advisory lock.
 *   `for_pass` — the close targets the forecast that was made *for this pass*, not merely
 *            the newest pending row, and the open is skipped when a pending forecast for
 *            the next pass already exists. Together these make the whole hypothesis half
 *            of a judge idempotent: re-running it neither closes the wrong forecast nor
 *            opens a second one.
 *
 * `hashtext` is an internal function with no cross-version stability guarantee, which is
 * fine: the key only has to agree with other ponder processes on the same server at the
 * same moment.
 */
const SQL_RECORD_PASS = `
WITH lk AS (
  SELECT pg_try_advisory_xact_lock(1347439940, hashtext(:'domain')) AS got
),
ep AS (
  INSERT INTO episodic_memory
    (event_type, content, prediction, actual_outcome, surprise_magnitude, importance_score, emotional_valence)
  VALUES
    ('ponder_pass', :'content', nullif(:'prediction',''), :'outcome',
     nullif(:'surprise','')::float8, 0.6,
     -- No surprise measurement means no reason to move off neutral, not a surprise of zero.
     greatest(-1.0, least(1.0, 0.2 - coalesce(nullif(:'surprise','')::float8, 0))))
  RETURNING id
),
prev AS MATERIALIZED (
  SELECT h.id,
         (h.source_data->>'forecast_churn')::float8 AS fc,
         coalesce((h.source_data->>'band')::float8, (:'band')::float8) AS band,
         abs((h.source_data->>'forecast_churn')::float8 - nullif(:'churn','')::float8) AS surp,
         coalesce(h.source_data->>'pass', '?') AS prev_pass
  FROM hypotheses h
  WHERE h.domain = :'domain'
    AND h.status = 'pending'
    -- Compared as text, never cast: a source_data written by something other than ponder
    -- must not be able to abort the whole statement with an invalid integer.
    AND h.source_data->>'for_pass' = :'pass'
    -- A pass with no churn signal (SPEC 4: pass 1) scores nothing. Closing a forecast
    -- against a coerced zero would invent the one measurement this table exists to record.
    AND nullif(:'churn','') IS NOT NULL
    -- Shape-checked rather than coalesced, for the same reason for_pass is compared as
    -- text: a source_data written by something else must neither abort the statement with
    -- an invalid float nor be scored against a fabricated forecast of 0.
    AND h.source_data->>'forecast_churn' ~ '^-?[0-9]+([.][0-9]+)?$'
    AND (h.source_data->>'band' IS NULL OR h.source_data->>'band' ~ '^-?[0-9]+([.][0-9]+)?$')
    AND (SELECT got FROM lk)
  ORDER BY h.created_at DESC
  LIMIT 1
  FOR UPDATE SKIP LOCKED
),
closed AS (
  UPDATE hypotheses h SET
    status = CASE WHEN prev.surp <= prev.band THEN 'confirmed' ELSE 'refuted' END,
    actual_outcome = 'pass ' || :'pass' || ' churn ' || :'churn' || ' (' || :'deltas' || ')',
    tested_at = now(),
    surprise_magnitude = round(prev.surp::numeric, 4)::float8,
    confidence_delta = round((prev.band - prev.surp)::numeric, 4)::float8,
    model_update = 'pass ' || prev.prev_pass || ' forecast churn ' || round(prev.fc::numeric, 3)
                   || ' for pass ' || :'pass' || '; actual ' || :'churn'
                   || '; surprise ' || round(prev.surp::numeric, 3)
                   || CASE WHEN prev.surp <= prev.band
                        THEN '. Churn-decay model held; keep the decay constant.'
                        ELSE '. Churn-decay model missed; the loop is not settling the way it predicted.'
                      END
  FROM prev
  WHERE h.id = prev.id
  RETURNING h.id, h.status, h.surprise_magnitude
),
opened AS (
  INSERT INTO hypotheses
    (domain, claim, confidence, prediction, test_method, test_type, status, source_type, source_data)
  SELECT
    :'domain',
    :'claim',
    nullif(:'hypConfidence','')::float8,
    :'hypPrediction',
    'ponder judge on pass ' || :'nextPass' || ' computes churn from that pass''s deltas.jsonl',
    'passive_observation',
    'pending',
    'ponder',
    (:'sourceData')::jsonb
  -- A data-modifying CTE always runs to completion, so the guards live in the row source:
  -- no churn signal to decay, no advisory lock, or a forecast for the next pass already
  -- pending, and this inserts nothing. The row 'closed' is closing forecasts *this* pass,
  -- so it never matches here.
  WHERE (:'forecastable')::boolean
    AND (SELECT got FROM lk)
    AND NOT EXISTS (
      SELECT 1 FROM hypotheses h2
       WHERE h2.domain = :'domain'
         AND h2.status = 'pending'
         AND h2.source_data->>'for_pass' = :'nextPass'
    )
  RETURNING id
),
ev_tested AS (
  INSERT INTO cognitive_events (event_type, source_layer, target_layer, priority, payload)
  SELECT 'hypothesis_tested', 'ponder', :'domain',
         least(1.0, greatest(0.1, closed.surprise_magnitude * 2)),
         jsonb_build_object(
           'slug', :'slug', 'pass', (:'pass')::int, 'hypothesis_id', closed.id,
           'verdict', closed.status, 'surprise', closed.surprise_magnitude,
           'actual_churn', nullif(:'churn','')::float8)
  FROM closed
  RETURNING id
),
ev_formed AS (
  INSERT INTO cognitive_events (event_type, source_layer, target_layer, priority, payload)
  SELECT 'hypothesis_formed', 'ponder', :'domain', 0.5,
         jsonb_build_object(
           'slug', :'slug', 'pass', (:'pass')::int, 'hypothesis_id', opened.id,
           'forecast_churn', nullif(:'forecastChurn','')::float8, 'for_pass', (:'nextPass')::int)
  FROM opened
  RETURNING id
)
SELECT json_build_object(
  'episodeId', (SELECT id FROM ep),
  'hypothesisId', (SELECT id FROM opened),
  'closedHypothesisId', (SELECT id FROM closed),
  'closedVerdict', (SELECT status FROM closed),
  'closedSurprise', (SELECT surprise_magnitude FROM closed),
  'forecastChurn', nullif(:'forecastChurn','')::float8,
  'lock', CASE WHEN (SELECT got FROM lk) THEN 'held' ELSE 'contended' END,
  'events', json_build_object('tested', (SELECT id FROM ev_tested), 'formed', (SELECT id FROM ev_formed))
);
`;

const SQL_RECORD_DELIBERATION = `
WITH d AS (
  INSERT INTO deliberations
    (decision, stakes,
     skeptic_argument, skeptic_confidence,
     builder_argument, builder_confidence,
     dreamer_argument, dreamer_confidence,
     empath_argument, empath_confidence,
     resolution, resolution_method, completed_at)
  VALUES
    (:'decision', :'stakes',
     nullif(:'skeptic',''), nullif(:'skepticConf','')::float8,
     nullif(:'builder',''), nullif(:'builderConf','')::float8,
     nullif(:'dreamer',''), nullif(:'dreamerConf','')::float8,
     nullif(:'empath',''), nullif(:'empathConf','')::float8,
     -- Phase one of a two-phase write (SPEC 6.1): the row is created at deliberate,
     -- when the arguments exist but the pass's delta summary does not. resolution and
     -- completed_at stay NULL until resolveDeliberation fills them in at judge.
     nullif(:'resolution',''), 'ponder-pass',
     CASE WHEN nullif(:'resolution','') IS NULL THEN NULL ELSE now() END)
  RETURNING id
),
ev AS (
  INSERT INTO cognitive_events (event_type, source_layer, target_layer, priority, payload)
  -- The event fires at deliberate, where the pass's delta summary does not exist yet, so
  -- resolution is stripped rather than shipped as an empty string — an empty string in a
  -- payload reads as "there was no resolution", which is false. A consumer that wants it
  -- follows deliberation_id, which is the authority and gets its resolution at judge.
  -- The key is present only on the judge fallback path, where a summary is supplied and
  -- the row is written complete in one shot.
  SELECT 'deliberation_result', 'ponder', :'domain', 0.6,
         jsonb_strip_nulls(jsonb_build_object(
           'slug', :'slug', 'pass', (:'pass')::int, 'deliberation_id', d.id,
           'voices', (:'voices')::int, 'resolution', nullif(:'resolution','')))
  FROM d
  RETURNING id
)
SELECT json_build_object('deliberationId', (SELECT id FROM d), 'eventId', (SELECT id FROM ev), 'voices', (:'voices')::int);
`;

/**
 * Phase two of the two-phase deliberation write (SPEC 6.1).
 *
 * `judge` closes the row that `deliberate` opened: the delta summary becomes `resolution`
 * and the row is stamped `completed_at`. Guarded on `resolution_method` so a stray id can
 * only ever close a row ponder itself opened, and on `resolution IS NULL` so a re-run of
 * judge cannot rewrite a resolution that is already on the record.
 */
const SQL_RESOLVE_DELIBERATION = `
WITH d AS (
  UPDATE deliberations
     SET resolution = :'resolution', completed_at = now()
   WHERE id = (:'deliberationId')::int
     AND resolution_method = 'ponder-pass'
     AND resolution IS NULL
  RETURNING id
)
SELECT json_build_object('deliberationId', (SELECT id FROM d), 'resolved', (SELECT count(*) FROM d));
`;

const SQL_RECORD_OBSERVATION = `
WITH o AS (
  INSERT INTO metacognitive_observations
    (target_layer, observation_type, description, evidence, severity, recommended_intervention)
  VALUES
    (:'target', :'type', :'description', (:'evidence')::jsonb, (:'severity')::float8, nullif(:'intervention',''))
  RETURNING id
),
ev AS (
  INSERT INTO cognitive_events (event_type, source_layer, target_layer, priority, payload)
  SELECT 'metacognition_alert', 'ponder', :'target', (:'severity')::float8,
         jsonb_build_object(
           'slug', :'slug', 'observation_id', o.id, 'observation_type', :'type',
           'description', :'description', 'severity', (:'severity')::float8)
  FROM o
  RETURNING id
)
SELECT json_build_object('observationId', (SELECT id FROM o), 'eventId', (SELECT id FROM ev));
`;

const SQL_RECORD_CONVERGED = `
WITH ep AS (
  -- NULL, not the 0.0 default: see recordStart. Nothing scores a convergence row.
  INSERT INTO episodic_memory
    (event_type, content, actual_outcome, surprise_magnitude, importance_score, emotional_valence, consolidation_status)
  VALUES (:'eventType', :'content', :'outcome', NULL, 0.8, 0.3, 'raw')
  RETURNING id
),
expired AS (
  UPDATE hypotheses SET
    status = 'expired',
    tested_at = now(),
    model_update = coalesce(model_update || ' ', '')
                   || 'Ponder session closed before this forecast could be tested.'
  WHERE domain = :'domain' AND status = 'pending'
  RETURNING id
),
ev AS (
  INSERT INTO cognitive_events (event_type, source_layer, target_layer, priority, payload)
  SELECT 'reasoning_trace_created', 'ponder', :'domain', 0.7,
         jsonb_build_object('slug', :'slug', 'episode_id', ep.id, 'summary', :'outcome')
  FROM ep
  RETURNING id
)
SELECT json_build_object(
  'episodeId', (SELECT id FROM ep),
  'eventId', (SELECT id FROM ev),
  'expiredHypotheses', (SELECT count(*)::int FROM expired)
);
`;

/**
 * SPEC §5.2: `ponder apply` "records an OCA episodic entry". One row, no hypothesis and no
 * cognitive event — §6.1 asks for neither, and apply is not a pass.
 */
const SQL_RECORD_APPLY = `
INSERT INTO episodic_memory
  (event_type, content, actual_outcome, surprise_magnitude, importance_score, emotional_valence, consolidation_status)
VALUES ('ponder_applied', :'content', :'outcome', NULL, 0.75, 0.2, 'raw')
RETURNING json_build_object('id', id, 'episodeId', id);
`;

const SQL_OPEN_OBSERVATIONS = `
SELECT coalesce(json_agg(t ORDER BY t.severity DESC, t.timestamp DESC), '[]'::json) FROM (
  SELECT id, timestamp, observation_type, description, severity, recommended_intervention, evidence
  FROM metacognitive_observations
  WHERE target_layer = :'target' AND intervention_applied = false
  ORDER BY severity DESC, timestamp DESC
  LIMIT 20
) t;
`;

// ---------------------------------------------------------------------------
// Public API — every body is wrapped; nothing here throws
// ---------------------------------------------------------------------------

/**
 * Is the bridge switched on for this process?
 *
 * Synchronous, so it reports configuration plus whatever the memoised probe has
 * already learned: false when PONDER_OCA=off, false once a probe has come back
 * unreachable, true otherwise (including before the first probe).
 *
 * @returns {boolean}
 */
export function isEnabled() {
  try {
    if (mode() === 'off') return false;
    if (probeResult && probeResult.reachable === false) return false;
    return true;
  } catch {
    return false;
  }
}

/**
 * Reachability + schema check. Exactly one real probe per process, per DSN.
 *
 * @returns {Promise<{reachable: boolean, dsn: string, note: string, mode: string,
 *                    schema: boolean, missing: string[], ms: number, fatal: boolean} | null>}
 *   null only when PONDER_OCA=off. Otherwise an object; read `.reachable`.
 *   `.fatal` is true when PONDER_OCA=on and OCA is unusable — the engine surfaces that
 *   as a hard error (SPEC §6: "Under on, an unreachable OCA is a hard error").
 */
export async function probe() {
  try {
    if (mode() === 'off') return null;
    const result = await memoisedProbe(mode());
    // A failed probe is not a lost diagnostic: `note` goes back to the caller, and every
    // caller shows it — `ponder doctor` and `ponder start` print the reason, and under
    // PONDER_OCA=on the engine raises it as the hard error. So this line is only worth
    // writing when a session log already exists to hold the session's own record of the
    // outage. With no session there is nowhere SPEC 6.3 puts it and the user has already
    // been told, which is exactly the residue that used to pile up in ~/.ponder/oca.log.
    if (result && result.reachable === false && lastSessionDir) {
      log(null, 'probe', `${result.fatal ? 'FATAL' : 'DISABLED'} ${result.note} dsn=${redactDsn(result.dsn)} mode=${result.mode}`);
    }
    return result;
  } catch (err) {
    const url = (() => {
      try {
        return dsn();
      } catch {
        return DEFAULT_DSN;
      }
    })();
    const result = {
      reachable: false,
      dsn: url,
      note: `probe failed: ${err && err.message}`,
      mode: 'auto',
      schema: false,
      missing: REQUIRED_TABLES.slice(),
      ms: 0,
      fatal: false,
    };
    probeResult = result;
    if (lastSessionDir) log(null, 'probe', `FAIL ${result.note}`);
    return result;
  }
}

/**
 * SPEC §6.2 — prior ponder episodes whose content mentions this subject.
 * Printed by `ponder start` as "Prior pondering".
 *
 * @param {string} subject
 * @returns {Promise<Array<{content: string, actual_outcome: string|null, timestamp: string}> | null>}
 */
export async function priorPondering(subject) {
  try {
    if (mode() === 'off') return null;
    const needle = str(subject).trim();
    if (needle === '') return [];
    if (!(await ready(null, 'priorPondering'))) return null;

    const rows = await psqlJson(null, 'priorPondering', SQL_PRIOR_PONDERING, { subject: likeLiteral(needle) });
    if (rows === null) return null;
    return Array.isArray(rows) ? rows : [];
  } catch (err) {
    log(null, 'priorPondering', `FAIL unexpected: ${err && err.message}`);
    return null;
  }
}

/**
 * SPEC §6.1 — `ponder start` writes one episodic_memory row. Its `content` carries the
 * subject verbatim, which is what priorPondering() greps on a later session.
 *
 * @param {object} session session.json
 * @returns {Promise<{id: number, episodeId: number, sessionRef: number} | null>}
 */
export async function recordStart(session) {
  try {
    if (mode() === 'off') return null;
    if (!(await ready(session, 'recordStart'))) return null;

    const slug = slugOf(session);
    const subject = fieldOf(session, 'subject', '(no subject)');
    const lens = fieldOf(session, 'lens', 'custom');
    const project = fieldOf(session, 'project', '');
    const sessionMode = fieldOf(session, 'mode', 'deliberate');
    const maxPasses = num(session && session.maxPasses, null);
    const minPasses = num(session && session.minPasses, null);

    const content =
      `ponder start [${slug}] subject="${subject}" lens=${lens} mode=${sessionMode}` +
      (project ? ` project=${project}` : '') +
      (minPasses !== null ? ` minPasses=${minPasses}` : '') +
      (maxPasses !== null ? ` maxPasses=${maxPasses}` : '');

    const prediction =
      maxPasses !== null
        ? `This pondering of "${subject}" through the ${lens} lens converges within ${maxPasses} passes.`
        : `This pondering of "${subject}" through the ${lens} lens converges.`;

    return await psqlJson(session, 'recordStart', SQL_RECORD_START, { content, prediction });
  } catch (err) {
    log(session, 'recordStart', `FAIL unexpected: ${err && err.message}`);
    return null;
  }
}

/**
 * SPEC §6.1 — `ponder judge` for pass N. Writes the episodic row, closes pass N-1's
 * forecast about pass N, and opens pass N's forecast about pass N+1.
 *
 * That two-phase hypothesis lifecycle is the surprise mechanic: the loop states what it
 * expects the next pass to move, then is scored on it. Falling surprise_magnitude across
 * a session's hypotheses rows means the loop has learned to model itself.
 *
 * **Pass 1 opens no forecast.** SPEC §4 gives pass 1 no churn — there is no previous pass
 * to have churned against — and the forecast is a decay of the current pass's churn, so
 * pass 1 has no basis for one. The forecast series therefore starts at pass 2 (a forecast
 * about pass 3) and every point in it is a real prediction scored against a real outcome.
 * Pass 1's episodic row is still written, with `surprise_magnitude` NULL and an
 * `actual_outcome` that says plainly there was nothing to churn against.
 *
 * @param {object} session  session.json
 * @param {number} passNo   the pass being judged
 * @param {object} metrics  metrics.json — churn, novelty, coverage, thrash, surprise, …
 *                          any of which may be `null` (SPEC §4, pass 1)
 * @param {object} predict  predict.json — { churn, claim } as written before the pass
 * @returns {Promise<object|null>} `{ episodeId, hypothesisId, closedHypothesisId,
 *   closedVerdict, closedSurprise, forecastChurn, lock, closeNote, openNote, events }`,
 *   or null. `lock` is `held` or `contended`; `closeNote` is `closed`, `nothing-pending`
 *   or `contended`; `openNote` is `opened`, `no-churn-signal`, `already-forecast` or
 *   `contended`. `forecastChurn` is null exactly when `openNote` is `no-churn-signal`. The
 *   episodic row is written in every case — only the hypothesis half can decline.
 */
export async function recordPass(session, passNo, metrics, predict) {
  try {
    if (mode() === 'off') return null;
    if (!(await ready(session, 'recordPass'))) return null;

    const slug = slugOf(session);
    const subject = fieldOf(session, 'subject', '(no subject)');
    const lens = fieldOf(session, 'lens', 'custom');
    const pass = clamp(Math.round(num(passNo, 1)), 1, MAX_PASS);
    const nextPass = pass + 1;

    const m = metrics && typeof metrics === 'object' ? metrics : {};
    const p = predict && typeof predict === 'object' ? predict : {};

    // SPEC §4: churn is all deltas ÷ total findings — a ratio with no ceiling at 1, and a
    // pass that rewrites more than it keeps routinely exceeds it. Only the *prediction* is
    // bounded, because `ponder predict --churn` takes 0–1 (SPEC §5). Clamping the actual
    // to 1 would report "churn 1" for a churn of 2 and score the forecast against a lie.
    //
    // And SPEC §4 emits churn, novelty, thrash and surprise as `null` on pass 1, because
    // all four measure change against a pass that does not exist. `null` stays `null` all
    // the way to the column. Coercing it to 0 would put "the loop moved nothing" on the
    // record for the pass that moved everything.
    const churn = maybeRatio(m.churn, MAX_RATIO);
    const predictedChurn = maybeRatio(num(p.churn, p.predictedChurn), 1);
    const claimText = str(p.claim || p.text || '').trim();
    const surprise = maybeRatio(
      num(m.surprise, churn === null || predictedChurn === null ? null : Math.abs(predictedChurn - churn)),
      MAX_RATIO,
    );

    const deltas = deltaCountsText(m);
    const signals = metricsText(m);

    // Pass N forecasts pass N+1 by decaying pass N's churn. With no churn there is nothing
    // to decay and therefore no forecast — see the note above SQL_RECORD_PASS. The engine
    // may override the number, but not the existence of a basis for one.
    const forecastChurn =
      churn === null
        ? null
        : clamp(round(num(m.forecastChurn, num(p.nextChurn, churn * CHURN_DECAY)), 3), 0, MAX_RATIO);
    const forecastable = forecastChurn !== null;
    // Confidence in the forecast falls as the loop keeps surprising itself. Unmeasured
    // surprise is not zero surprise, so it buys no confidence: the forecast opens at an
    // even 0.5 rather than at the 0.75 an unsurprised loop would have earned.
    const hypConfidence = surprise === null ? 0.5 : clamp(round(0.75 - surprise, 2), 0.05, 0.95);

    const content =
      `ponder pass ${pass} [${slug}] subject="${subject}" lens=${lens} ${signals} ${deltas}`.trim();

    // An empty prediction lands as NULL, not as a sentence claiming a churn of 0 was
    // predicted. SPEC §4: pass 1's prediction is recorded even though it is scored later.
    const prediction =
      predictedChurn === null
        ? claimText === ''
          ? ''
          : `no churn predicted — ${claimText}`
        : `predicted churn ${round(predictedChurn, 3)} — ${claimText || '(no claim recorded)'}`;
    const outcome =
      churn === null
        ? `actual churn — (no previous pass to churn against); ${deltas}; ${signals}`
        : `actual churn ${round(churn, 3)}; ${deltas}; ${signals}`;

    const hypPrediction = forecastable
      ? `Pass ${nextPass} of ponder session ${slug} moves churn ${forecastChurn} ` +
        `(±${FORECAST_BAND}); pass ${pass} churn was ${round(churn, 3)}.`
      : '';
    const hypClaim = forecastable
      ? `ponder ${slug} is converging on "${subject}" (${lens} lens): each pass moves less than the last, ` +
        `so pass ${nextPass} churns about ${forecastChurn}.`
      : '';

    // Only written when a forecast is actually opened. Every numeric key is either a real
    // measurement or JSON null — the next pass reads forecast_churn back to score itself,
    // and a null there now makes the row unscoreable rather than scoreable against a lie.
    const sourceData = jsonValue({
      slug,
      lens,
      subject,
      pass,
      for_pass: nextPass,
      forecast_churn: forecastChurn,
      band: FORECAST_BAND,
      pass_churn: churn === null ? null : round(churn, 3),
      predicted_churn: predictedChurn === null ? null : round(predictedChurn, 3),
      surprise: surprise === null ? null : round(surprise, 3),
      decay: CHURN_DECAY,
    });

    const domain = domainOf(session);
    const res = await psqlJson(session, 'recordPass', SQL_RECORD_PASS, {
      slug,
      domain,
      pass: String(pass),
      nextPass: String(nextPass),
      // Empty string, never '0', when the signal does not exist. Every use of these in the
      // SQL is nullif(…,''), so an absent measurement reaches Postgres as NULL.
      churn: churn === null ? '' : String(round(churn, 3)),
      band: String(FORECAST_BAND),
      surprise: surprise === null ? '' : String(round(surprise, 4)),
      forecastable: forecastable ? 'true' : 'false',
      forecastChurn: forecastable ? String(forecastChurn) : '',
      hypConfidence: forecastable ? String(hypConfidence) : '',
      deltas,
      content,
      prediction,
      outcome,
      claim: hypClaim,
      hypPrediction,
      sourceData,
    });
    if (!res || typeof res !== 'object') return res;

    // The episodic row is always written; the hypothesis lifecycle can decline. Say which
    // it did, so a caller holding a null `closedHypothesisId` knows whether there was
    // nothing to close or another process closed it first, and never reports a surprise
    // measurement this pass did not take.
    const held = res.lock !== 'contended';
    res.closeNote = !held ? 'contended' : res.closedHypothesisId ? 'closed' : 'nothing-pending';
    res.openNote = !held
      ? 'contended'
      : res.hypothesisId
        ? 'opened'
        : forecastable
          ? 'already-forecast'
          : 'no-churn-signal';
    if (!held) {
      log(session, 'recordPass', `SKIP hypothesis lifecycle for pass ${pass}: ${domain} is being judged by another process — nothing closed, nothing forecast`);
    } else if (res.openNote === 'already-forecast') {
      log(session, 'recordPass', `SKIP forecast for pass ${nextPass}: ${domain} already has one pending`);
    } else if (res.openNote === 'no-churn-signal') {
      log(session, 'recordPass', `SKIP forecast for pass ${nextPass}: pass ${pass} has no churn signal to decay (SPEC 4) — the forecast series starts at the first pass that does`);
    }
    return res;
  } catch (err) {
    log(session, 'recordPass', `FAIL unexpected: ${err && err.message}`);
    return null;
  }
}

/**
 * SPEC §6.1 — `ponder deliberate`. One row per pass in `deliberations`, carrying the four
 * perspectives' arguments and confidences, with the pass's delta summary as `resolution`.
 *
 * This is phase one of a two-phase write. SPEC 6.1 places the row at `deliberate`, but the
 * `resolution` it also asks for is the pass's delta summary, which does not exist until
 * `revise` has run. So `deliberate` inserts the arguments with `resolution` and
 * `completed_at` left NULL, and `judge` calls `resolveDeliberation` to close the row. The
 * row therefore exists from the phase the spec names, and still carries the resolution the
 * spec asks for.
 *
 * Passing `summary` writes the row complete in one shot. `judge` uses that as its fallback
 * when the OCA was unreachable at `deliberate` and there is no open row to close — better a
 * late complete row than no row at all.
 *
 * @param {object} session
 * @param {number} passNo
 * @param {object} deliberation deliberation.json (tolerant: {skeptic:{argument,confidence}},
 *                              {perspectives:{…}}, or flat skeptic_argument/skeptic_confidence)
 * @param {string|object} [summary] the pass's delta summary → deliberations.resolution.
 *                              Omit at `deliberate`; the row is closed later by
 *                              resolveDeliberation.
 * @returns {Promise<{deliberationId: number, eventId: number, voices: number} | null>}
 */
export async function recordDeliberation(session, passNo, deliberation, summary) {
  try {
    if (mode() === 'off') return null;
    if (!(await ready(session, 'recordDeliberation'))) return null;

    const slug = slugOf(session);
    const pass = clamp(Math.round(num(passNo, 1)), 1, MAX_PASS);
    const d = deliberation && typeof deliberation === 'object' ? deliberation : {};

    const vars = {
      slug,
      domain: domainOf(session),
      pass: String(pass),
      decision: `ponder ${slug} pass ${pass}: revise the finding set for "${fieldOf(session, 'subject', '(no subject)')}"`,
      stakes: str(d.stakes || '').trim() || 'medium',
      resolution: summaryText(summary),
      voices: String(voicesIn(d)),
    };

    for (const name of PERSPECTIVES) {
      const { argument, confidence } = perspectiveOf(d, name);
      vars[name] = argument;
      vars[`${name}Conf`] = confidence === null ? '' : String(round(confidence, 3));
    }

    return await psqlJson(session, 'recordDeliberation', SQL_RECORD_DELIBERATION, vars);
  } catch (err) {
    log(session, 'recordDeliberation', `FAIL unexpected: ${err && err.message}`);
    return null;
  }
}

/**
 * SPEC §6.1 — `ponder judge` closes the `deliberations` row that `ponder deliberate`
 * opened, writing the pass's delta summary into `resolution`.
 *
 * Returns `{ deliberationId, resolved }` where `resolved` is 1 when a row was closed and 0
 * when there was nothing to close (unknown id, already resolved, or not a ponder row). A 0
 * is not an error — the caller falls back to a complete insert.
 *
 * @param {object} session
 * @param {number} deliberationId id returned by recordDeliberation
 * @param {string|object} summary the pass's delta summary
 * @returns {Promise<{deliberationId: number|null, resolved: number} | null>}
 */
export async function resolveDeliberation(session, deliberationId, summary) {
  try {
    if (mode() === 'off') return null;
    const id = Math.round(num(deliberationId, 0));
    if (!Number.isFinite(id) || id <= 0) return null;
    if (!(await ready(session, 'resolveDeliberation'))) return null;

    const resolution = summaryText(summary).trim();
    if (resolution === '') return null;

    return await psqlJson(session, 'resolveDeliberation', SQL_RESOLVE_DELIBERATION, {
      deliberationId: String(id),
      resolution,
    });
  } catch (err) {
    log(session, 'resolveDeliberation', `FAIL unexpected: ${err && err.message}`);
    return null;
  }
}

/**
 * SPEC §6.1 — metacognize. One `metacognitive_observations` row plus a
 * `metacognition_alert` cognitive event.
 *
 * @param {object} session
 * @param {string} type          stuck_state | perseveration | thrash | low_confidence | deliberation_skipped
 * @param {string} description
 * @param {*} evidence           anything JSON-serialisable → the jsonb `evidence` column
 * @param {number|string} severity  0–1, or a name (`low`, `medium`, `high`, `critical`,
 *                               …) which is mapped onto that scale. Default 0.5.
 * @param {string} intervention  recommended_intervention
 * @returns {Promise<{observationId: number, eventId: number} | null>}
 */
export async function recordObservation(session, type, description, evidence, severity, intervention) {
  try {
    if (mode() === 'off') return null;
    if (!(await ready(session, 'recordObservation'))) return null;

    const observationType = str(type).trim().replace(/\s+/g, '_').toLowerCase() || 'unspecified';
    const text = str(description).trim() || `ponder ${slugOf(session)}: ${observationType}`;

    return await psqlJson(session, 'recordObservation', SQL_RECORD_OBSERVATION, {
      slug: slugOf(session),
      target: domainOf(session),
      type: observationType,
      description: text,
      evidence: jsonValue(evidence === undefined ? {} : evidence),
      severity: String(severityValue(severity)),
      intervention: str(intervention).trim(),
    });
  } catch (err) {
    log(session, 'recordObservation', `FAIL unexpected: ${err && err.message}`);
    return null;
  }
}

/**
 * SPEC §6.1 — `ponder decide stop`. The closing episodic row, with the final counts.
 * Also expires any still-pending forecast, so a session never leaves an untestable
 * hypothesis sitting in the OCA's pending queue forever.
 *
 * @param {object} session
 * @param {string|object} summary final counts / verdict / reason
 * @returns {Promise<{episodeId: number, eventId: number, expiredHypotheses: number} | null>}
 */
export async function recordConverged(session, summary) {
  try {
    if (mode() === 'off') return null;
    if (!(await ready(session, 'recordConverged'))) return null;

    const slug = slugOf(session);
    const subject = fieldOf(session, 'subject', '(no subject)');
    const lens = fieldOf(session, 'lens', 'custom');
    const outcome = summaryText(summary) || '(no summary recorded)';
    const passes = num(session && session.currentPass, null);
    const status = fieldOf(session, 'status', 'stopped');
    const eventType = status === 'converged' ? 'ponder_converged' : 'ponder_stopped';

    const content =
      `ponder ${status === 'converged' ? 'converged' : 'stopped'} [${slug}] subject="${subject}" lens=${lens} status=${status}` +
      (passes !== null ? ` passes=${passes}` : '') +
      ` :: ${outcome}`;

    return await psqlJson(session, 'recordConverged', SQL_RECORD_CONVERGED, {
      eventType, slug,
      domain: domainOf(session),
      content,
      outcome,
    });
  } catch (err) {
    log(session, 'recordConverged', `FAIL unexpected: ${err && err.message}`);
    return null;
  }
}

/**
 * SPEC §5.2 — `ponder apply` writes the plan, marks the session `applied`, and "records an
 * OCA episodic entry". `event_type='ponder_applied'`, alongside the session's
 * `ponder_start` / `ponder_pass` / `ponder_converged` rows. `episodic_memory.event_type` is
 * free text, not the `cognitive_event_type` enum, so this label needs no enum change; it is
 * deliberately outside the pair `priorPondering()` greps, because an apply is not a
 * pondering to pick up from.
 *
 * @param {object} session
 * @param {string|object} summary what the plan covers
 * @returns {Promise<{id: number, episodeId: number} | null>}
 */
export async function recordApply(session, summary) {
  try {
    if (mode() === 'off') return null;
    if (!(await ready(session, 'recordApply'))) return null;

    const slug = slugOf(session);
    const subject = fieldOf(session, 'subject', '(no subject)');
    const lens = fieldOf(session, 'lens', 'custom');
    const outcome = summaryText(summary) || '(no summary recorded)';
    const content = `ponder applied [${slug}] subject="${subject}" lens=${lens} :: ${outcome}`;

    return await psqlJson(session, 'recordApply', SQL_RECORD_APPLY, { content, outcome });
  } catch (err) {
    log(session, 'recordApply', `FAIL unexpected: ${err && err.message}`);
    return null;
  }
}

/**
 * SPEC §6.2 — open metacognitive observations for this session's target layer.
 * `ponder judge` folds their severity into the advice as a tie-breaker toward escalate.
 *
 * @param {object} session
 * @returns {Promise<Array<{id: number, timestamp: string, observation_type: string,
 *          description: string, severity: number, recommended_intervention: string|null,
 *          evidence: object}> | null>}
 */
export async function openObservations(session) {
  try {
    if (mode() === 'off') return null;
    if (!(await ready(session, 'openObservations'))) return null;

    const rows = await psqlJson(session, 'openObservations', SQL_OPEN_OBSERVATIONS, { target: domainOf(session) });
    if (rows === null) return null;
    return Array.isArray(rows) ? rows : [];
  } catch (err) {
    log(session, 'openObservations', `FAIL unexpected: ${err && err.message}`);
    return null;
  }
}
