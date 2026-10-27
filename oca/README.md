# The OCA bridge

`oca/bridge.js` writes a ponder session into the Oneiro Cognitive Architecture's Postgres
so that two things become possible:

1. **Cross-session memory.** `ponder start` asks OCA whether this subject has been
   pondered before, and prints what it finds as **Prior pondering**. The loop remembers
   having thought about the UI last month.
2. **A self-model.** Every pass forecasts what the *next* pass will churn, and the next
   pass scores that forecast. Surprise falling across a session — and across sessions —
   is the loop learning how it converges.

The bridge is optional in the strongest sense: with OCA down, ponder loses those two
things and nothing else. Every command still runs, every file is still written, every
verdict is still computed.

It has zero npm dependencies. It shells out to `psql`.

---

## Wiring

The engine imports the whole module:

```js
import * as oca from '../oca/bridge.js';
```

| Export | Called at | Returns |
|---|---|---|
| `isEnabled()` | anywhere (synchronous) | `boolean` — is the bridge switched on for this process |
| `probe()` | `start`, `doctor` | `{ reachable, dsn, note, mode, schema, missing, ms, fatal }` or `null` |
| `priorPondering(subject)` | `start` | array of prior episodes, or `null` |
| `recordStart(session)` | `start` | `{ id, episodeId, sessionRef }` or `null` |
| `recordPass(session, passNo, metrics, predict)` | `judge` | ids, the closed forecast's verdict, and `lock` / `closeNote` / `openNote` saying what the hypothesis lifecycle did — or `null` |
| `recordDeliberation(session, passNo, deliberation[, summary])` | `deliberate` | `{ deliberationId, eventId, voices }` or `null` |
| `resolveDeliberation(session, deliberationId, summary)` | `judge` | `{ deliberationId, resolved }` or `null` |
| `recordObservation(session, type, description, evidence, severity, intervention)` | metacognize | `{ observationId, eventId }` or `null` |
| `recordConverged(session, summary)` | `decide stop` | `{ episodeId, eventId, expiredHypotheses }` or `null` |
| `recordApply(session, summary)` | `apply` (not `--dry-run`) | `{ id, episodeId }` or `null` |
| `openObservations(session)` | `judge` | array of open observations, or `null` |

Everything except `isEnabled()` is `async`. **Nothing here ever throws.** Every failure —
non-zero exit, timeout, missing binary, unparseable output — is logged and returns `null`.

`probe()` is the one function that reports a negative result as an object rather than as
`null`, because `PONDER_OCA=on` needs to be able to fail loudly:

- `PONDER_OCA=off` → `probe()` returns `null`. There is nothing to probe.
- otherwise → an object. Read `p && p.reachable`. When `p.fatal` is `true` (mode `on`,
  OCA unusable), the engine should exit non-zero and say why: that is the hard-coupling
  mode, for CI.

---

## Configuration

| Variable | Default | Meaning |
|---|---|---|
| `PONDER_OCA` | `auto` | `auto` \| `on` \| `off` |
| `PONDER_OCA_DSN` | `postgres://localhost/oneiro` | any libpq connection string |
| `PONDER_PSQL` | `psql` | path to the psql binary, if it is not on `PATH` |

**`auto`** — one reachability probe per process, 2s budget, memoised. If OCA is not there,
the bridge disables itself for the rest of the process and every later call returns `null`
immediately without spawning anything. Never fatal.

**`on`** — same probe, 5s budget. An unreachable or schema-incomplete OCA comes back as
`{ reachable: false, fatal: true }` and the engine turns that into a hard error. Use this
when the OCA write is the point, not a bonus.

**`off`** — every export is an immediate no-op returning `null`. No process is spawned, no
log file is written, no probe is attempted. Verified: every export called back to back
returns in under a millisecond, with zero `psql` processes created.

### Turning it off

```sh
PONDER_OCA=off ponder judge          # one command
export PONDER_OCA=off                # this shell
```

Or put it in the project's env. There is no config file and no state to unwind — the
bridge reads the variable on every call, so flipping it mid-session is safe.

### Pointing it somewhere else

```sh
PONDER_OCA_DSN=postgres://user:pw@host:5432/oneiro ponder start "the UI" --lens ui
```

The probe checks more than TCP reachability: it confirms all five tables ponder writes to
actually exist. A live Postgres that is not an OCA database comes back
`reachable: false` with `missing: [...]` rather than accepting a session and then failing
every insert.

---

## What ponder writes, where

Everything a session writes is keyed by its slug. Two keys do all the work:

- `domain` / `target_layer` = `ponder:<slug>`
- `episodic_memory.content` always begins `ponder <phase> [<slug>] subject="<subject>" …`

### `episodic_memory` — the session timeline

| Phase | `event_type` | Notable columns |
|---|---|---|
| `start` | `ponder_start` | `content` = slug, subject, lens, project, pass budget. `importance_score` 0.7 |
| `judge`, once per pass | `ponder_pass` | `prediction` = the pass's predicted churn + claim; `actual_outcome` = actual churn, per-op delta counts, every convergence signal; `surprise_magnitude` = `metrics.surprise` |
| `decide stop` | `ponder_converged` if converged, otherwise `ponder_stopped` | `actual_outcome` = the final counts; `importance_score` 0.8 |
| `apply`, without `--dry-run` | `ponder_applied` | `actual_outcome` = what the plan covers; `importance_score` 0.75 |

`content` carries the subject verbatim. That is deliberate — it is what
`priorPondering()` greps on a later session. `ponder_applied` is deliberately outside the
pair `priorPondering()` searches: an apply is not a pondering to resume from. The string also
carries a literal `mode=deliberate`; ponder has one mode, so that field is a constant rather
than a setting, and the bridge writes it whether or not the session file mentions one.

Churn and surprise go in as the engine computed them, from pass 2 on. Churn is revising
deltas ÷ live findings (SPEC §4), so a pass that rewrites more than it keeps reports a churn
above 1 and it is stored that way — rounding it down to 1 would score the next pass's
forecast against a number the loop never produced. Only the *prediction* is bounded to 0–1,
because `ponder predict --churn` is.

**Pass 1 has no churn, and the row says so.** SPEC §4 emits `churn`, `novelty`, `thrash` and
`surprise` as `null` on pass 1, because all four measure change against a pass that does not
exist. The bridge carries those nulls all the way to the column instead of coercing them:

- `surprise_magnitude` is **NULL**, not `0.0`.
- `actual_outcome` reads `actual churn — (no previous pass to churn against)`, followed by
  the delta counts and only the signals that were actually measured. A null signal is absent
  from that line rather than printed as `churn=0`.
- `prediction` still carries the agent's pass-1 predicted churn and claim — SPEC §4 records
  that on pass 1 and scores it from pass 2 — and lands as NULL if there was nothing to record.
- **No forecast hypothesis is opened.** See the next section.

Across ponder's whole timeline `surprise_magnitude` is non-null exactly when a surprise was
measured, so `ponder_start`, `ponder_converged` and `ponder_applied` are written NULL too
rather than taking the column's `0.0` default. A zero there would read as "went exactly as
predicted", which nobody scored.

### `hypotheses` — the surprise mechanic

This is the two-phase table, and it is the reason the bridge exists at all.

**The series starts at pass 2.** The forecast is a decay of the current pass's churn, and
SPEC §4 gives pass 1 no churn, so pass 1 has no basis for a forecast and opens none. The
first row in a session's ledger is therefore made in pass 2 and is about pass 3, and every
point in the series is a real prediction scored against a real outcome.

> This used to be otherwise, and it mattered. `recordPass()` coerced pass 1's null churn to
> `0`, so pass 1 opened a forecast of `churn 0.000` for pass 2 — a prediction nothing
> supported — which pass 2 then refuted at whatever pass 2 actually churned. On the real
> 228-screen run that put a spurious `0.162` at the head of a series whose real content was
> `0.065 → 0.019`, and the README told you to ignore row 1. Telling a reader to skip a row is
> not a fix: a series with a fabricated first point is a series people will misread the
> moment they plot it.
>
> The alternative considered was to keep pass 1's hypothesis but anchor it on the agent's own
> stated prediction. That is not available at the moment it would be needed — `ponder predict`
> for pass 2 runs *after* pass 1's `judge` — and it collapses into the same implementation:
> the first forecast that can exist is the one pass 2 opens. So the choice is between a
> fabricated point and no point, and no point wins. The cost is one fewer row per session and
> a ledger that starts one pass later; the gain is that every number in it is real.

**Pass N (N ≥ 2), at `judge`, opens a forecast about pass N+1.** The model is that a
converging loop decays: pass N+1 moves about 60% of what pass N moved. So pass N writes

- `domain` = `ponder:<slug>`
- `claim` = "ponder `<slug>` is converging on `<subject>`: each pass moves less than the
  last, so pass N+1 churns about `<forecast>`"
- `prediction` = "Pass N+1 … moves churn `<forecast>` (±0.05); pass N churn was `<churn>`"
- `confidence` = `0.75 − surprise(pass N)`, clamped to [0.05, 0.95] — the loop trusts its
  own forecast less right after it has been surprised. With no surprise measurement (the
  agent recorded no predicted churn, so `metrics.surprise` is null) it opens at a flat
  `0.5` instead: an unmeasured surprise buys no confidence, the way a surprise of zero would.
- `status` = `pending`
- `source_data` = `{ slug, lens, subject, pass, for_pass, forecast_churn, band, pass_churn, predicted_churn, surprise, decay }`
  — every numeric key is either a real measurement or JSON `null`, never a stand-in `0`

**Pass N+1, at `judge`, closes it.** The same `recordPass()` call that opens N+1's forecast
first `UPDATE`s the pending row from pass N — the same row, not a second insert — setting

- `actual_outcome` = "pass N+1 churn `<churn>` (add=… edit=… change=… delete=…)"
- `surprise_magnitude` = `|forecast − actual|`, computed in SQL from the forecast stored
  in `source_data`
- `status` = `confirmed` when that lands inside the ±0.05 band, `refuted` otherwise
- `confidence_delta` = `band − surprise`: positive when the model held, negative when it
  did not
- `model_update` = a sentence naming both numbers and saying whether the churn-decay model
  held or missed
- `tested_at` = now

From pass 3 on, a pass therefore both settles the previous claim and stakes a new one, in a
single statement, in a single transaction. Pass 2 only stakes one — there is nothing behind
it to settle — and pass 1 does neither. `decide stop` expires any forecast still pending, so
a finished session never leaves an untestable hypothesis in OCA's pending queue; the last row
of a finished ledger is normally `expired` for exactly that reason.

Only OCA's existing status vocabulary is used: `pending`, `confirmed`, `refuted`,
`expired`.

#### One close per forecast, even under concurrency

Two ponder processes can be judging the same slug at the same moment — two agents, two
worktrees, or one `judge` run twice. They share a domain, so they share the pending
forecast, and the close has to arbitrate between them. Three guards do it, each covering
something the others do not:

- **A per-domain advisory lock.** The statement opens with
  `pg_try_advisory_xact_lock(1347439940, hashtext(domain))` — namespaced under a
  ponder-only first argument so it cannot collide with another OCA subsystem, and held only
  for the statement's own transaction. It is a *try*, never a wait: a process that does not
  get it skips the hypothesis lifecycle entirely rather than blocking and risking the 5s
  call timeout, which would cost it the episodic row too.
- **`FOR UPDATE SKIP LOCKED` on the claim.** The pending row is claimed by the database,
  not by convention: `... WHERE status = 'pending' … ORDER BY created_at DESC LIMIT 1 FOR
  UPDATE SKIP LOCKED`. Exactly one transaction can hold it. Anyone who finds it locked gets
  no row and closes nothing. This holds against any writer, including one that knows nothing
  about the advisory lock.
- **`for_pass` scoping.** The close targets the forecast made *for this pass*, not merely
  the newest pending row, and the open is skipped when a pending forecast for the next pass
  already exists. `for_pass` is compared as text and never cast, and `forecast_churn` and
  `band` are shape-checked against a numeric pattern before either is cast, so a
  `source_data` written by something other than ponder can neither abort the statement with
  an invalid literal nor be scored against a forecast quietly `coalesce`d to `0`.

Together they make the hypothesis half of a `judge` idempotent. Running `judge` twice on
one pass closes one forecast and opens one forecast, not two of each; and it can no longer
close the forecast it just opened, which is what an unscoped "newest pending row" would
have done on the second run.

`recordPass()` says which of those happened rather than returning a bare `null` that could
mean anything:

| field | values | means |
|---|---|---|
| `lock` | `held`, `contended` | whether this process ran the hypothesis lifecycle at all |
| `closeNote` | `closed`, `nothing-pending`, `contended` | why `closedHypothesisId` is or is not set |
| `openNote` | `opened`, `no-churn-signal`, `already-forecast`, `contended` | why `hypothesisId` is or is not set |

`no-churn-signal` is pass 1 declining to forecast, and it is the only one of the four that is
routine — it happens once per session, by design. `forecastChurn` comes back `null` exactly
then. `contended`, `already-forecast` and `no-churn-signal` each also append a line to
`oca.log`. The episodic row is written in every case — only the hypothesis half can decline.

What this protects is the surprise series. Before the guards, both processes closed the same
row and the second `UPDATE` overwrote the first: one measured `surprise_magnitude` was lost,
and both went on to open a forecast, leaving an orphan pending row for `decide stop` to
expire. Nothing corrupted, and nothing complained — the series just quietly lost a point,
which is the one thing the whole table exists to record.

### `deliberations` — one row per deliberating pass

`skeptic_argument` / `skeptic_confidence` and the same for `builder`, `dreamer`, `empath`;
`resolution` = the pass's delta summary; `resolution_method` = `ponder-pass`;
`decision` = "ponder `<slug>` pass N: revise the finding set for …"; `stakes` from the
deliberation file or `medium`.

A perspective that did not speak is stored as `NULL`, not as an empty string, so
`count(skeptic_argument)` is an honest voice count — and it is the same count the engine's
`voices` signal reports, since `voices` counts the perspectives that argued rather than the
ones that emitted a delta.

**This row is written in two phases**, because SPEC 6.1 puts it at `deliberate` but also
asks it to carry a `resolution` that does not exist until `revise` has run:

1. `ponder deliberate` calls `recordDeliberation` with no `summary`. The row is inserted
   with the four arguments and confidences; `resolution` and `completed_at` stay `NULL`.
   The new id is remembered on the session at `session.oca.deliberations[pass]`.
2. `ponder judge` calls `resolveDeliberation` with the pass's delta summary. That fills in
   `resolution` and stamps `completed_at`.

So an open row — `resolution IS NULL` — is a pass that deliberated but has not been judged
yet, which is a useful thing to be able to query. The `UPDATE` is guarded on
`resolution_method = 'ponder-pass'` and `resolution IS NULL`, so it can only ever close a
row ponder opened, and re-running `judge` cannot rewrite a resolution already on the record.

If there is no open row to close — the OCA was unreachable at `deliberate`, or the session
predates the two-phase write — `judge` falls back to inserting the row complete. A late
complete row beats no row at all.

### `metacognitive_observations` — what the loop noticed about itself

`target_layer` = `ponder:<slug>`, `observation_type` ∈ `stuck_state`, `perseveration`,
`thrash`, `low_confidence`, `deliberation_skipped`, plus `description`, `evidence`
(jsonb — pass any JSON-serialisable value), `severity` and `recommended_intervention`.

`severity` is stored as a 0–1 float, and it is load-bearing: `ponder judge` only lets an
open observation tip an otherwise-`continue` into `escalate` at 0.7 and above. Callers may
pass the number or a name, which is mapped onto the same scale — the engine names them:

| name | value | name | value |
|---|---|---|---|
| `none` | 0.05 | `warning` | 0.6 |
| `trivial` | 0.15 | `high` / `major` | 0.8 |
| `info` | 0.2 | `severe` | 0.9 |
| `low` / `minor` | 0.25 | `critical` | 0.95 |
| `medium` / `moderate` | 0.5 | `fatal` | 1.0 |

A numeric string parses. Anything else falls back to 0.5.

`openObservations()` reads back the rows for this session where
`intervention_applied = false`, severity-ordered. `ponder judge` folds their severity into
the advice as a tie-breaker toward `escalate`.

### `cognitive_events` — the OCA event stream

`source_layer` = `ponder`, `target_layer` = `ponder:<slug>`. `event_type` is a Postgres
enum and the bridge only ever uses labels that already exist:

| Written at | `event_type` |
|---|---|
| `judge`, when a forecast is opened | `hypothesis_formed` |
| `judge`, when the previous forecast is closed | `hypothesis_tested` (priority scales with surprise) |
| `deliberate` | `deliberation_result` |
| metacognize | `metacognition_alert` (priority = severity) |
| `decide stop` | `reasoning_trace_created` |

**A payload never carries an empty key.** `deliberation_result` fires at `deliberate`, one
phase before the pass's delta summary exists, so its payload has **no `resolution` key at
all** rather than a `"resolution": ""` — an empty string in a payload reads as "there was no
resolution", which is false. The key appears only on the `judge` fallback path, where a
summary is supplied and the row is written complete in one shot. Follow `deliberation_id` for
the resolution in every other case: the `deliberations` row is the authority, and it gets its
resolution at `judge`. The event itself is left immutable — a `deliberation_result` says a
deliberation was held at pass N, and rewriting a past event to backfill a field it did not
have at the time would be worse than not having the field.

---

## Reading a ponder session back out of OCA

All of these run as-is. Set the slug once at the top.

```sh
psql postgres://localhost/oneiro
```

```sql
\set slug 'ui-2026-08-24'
```

### Which sessions are in here?

```sql
SELECT substring(content from '\[([^\]]+)\]')                   AS slug,
       min(timestamp)                                           AS started,
       max(timestamp)                                           AS last_touched,
       count(*) FILTER (WHERE event_type = 'ponder_pass')        AS passes,
       bool_or(event_type = 'ponder_converged')                  AS converged,
       bool_or(event_type = 'ponder_applied')                    AS applied
FROM episodic_memory
WHERE event_type IN ('ponder_start', 'ponder_pass', 'ponder_converged', 'ponder_stopped', 'ponder_applied')
GROUP BY 1
ORDER BY started DESC;
```

### The whole session, in order

```sql
SELECT timestamp, event_type, prediction, actual_outcome, surprise_magnitude, content
FROM episodic_memory
WHERE event_type IN ('ponder_start', 'ponder_pass', 'ponder_converged', 'ponder_stopped', 'ponder_applied')
  AND content LIKE '%[' || :'slug' || ']%'
ORDER BY timestamp;
```

### The prediction ledger — did the loop model itself?

```sql
SELECT (source_data->>'pass')::int                    AS forecast_made_in_pass,
       (source_data->>'for_pass')::int                AS about_pass,
       (source_data->>'forecast_churn')::float8       AS forecast,
       confidence,
       status,
       surprise_magnitude,
       confidence_delta,
       model_update
FROM hypotheses
WHERE domain = 'ponder:' || :'slug'
ORDER BY created_at;
```

Read the `surprise_magnitude` column top to bottom. Falling is the whole point, and every row
is real — `forecast_made_in_pass` starts at 2, and the last row of a finished session is
`expired` because `decide stop` came before the pass that would have tested it.

### How well does ponder model itself, across every session?

```sql
SELECT domain,
       count(*) FILTER (WHERE status = 'confirmed')      AS held,
       count(*) FILTER (WHERE status = 'refuted')        AS missed,
       round(avg(surprise_magnitude)::numeric, 3)        AS mean_surprise
FROM hypotheses
WHERE domain LIKE 'ponder:%' AND tested_at IS NOT NULL
GROUP BY domain
ORDER BY mean_surprise;
```

### The four perspectives, pass by pass

```sql
SELECT started_at, decision, stakes,
       skeptic_confidence, builder_confidence, dreamer_confidence, empath_confidence,
       (skeptic_argument IS NOT NULL)::int + (builder_argument IS NOT NULL)::int
     + (dreamer_argument IS NOT NULL)::int + (empath_argument IS NOT NULL)::int AS voices,
       resolution
FROM deliberations
WHERE resolution_method = 'ponder-pass'
  AND decision LIKE 'ponder ' || :'slug' || ' pass%'
ORDER BY started_at;
```

Swap the confidence columns for `skeptic_argument, builder_argument, dreamer_argument,
empath_argument` to read the actual arguments.

### What the loop noticed about itself

```sql
SELECT timestamp, observation_type, severity, description,
       recommended_intervention, intervention_applied, evidence
FROM metacognitive_observations
WHERE target_layer = 'ponder:' || :'slug'
ORDER BY severity DESC, timestamp DESC;
```

### The event stream

```sql
SELECT timestamp, event_type, priority, payload
FROM cognitive_events
WHERE source_layer = 'ponder' AND target_layer = 'ponder:' || :'slug'
ORDER BY timestamp;
```

### Prior pondering — what `ponder start` sees

This is the query the bridge itself runs, with the subject as a parameter:

```sql
\set subject 'the UI'

SELECT content, actual_outcome, timestamp
FROM episodic_memory
WHERE event_type IN ('ponder_converged', 'ponder_stopped', 'ponder_start')
  AND content ILIKE '%' || :'subject' || '%'
ORDER BY timestamp DESC
LIMIT 5;
```

The bridge escapes `%` and `_` in the subject before it gets here, so a subject like
`"50% width"` matches literally instead of matching everything.

### Deleting a session's OCA rows

Ponder never deletes from OCA. If you want a session gone:

```sql
BEGIN;
DELETE FROM cognitive_events
  WHERE source_layer = 'ponder' AND target_layer = 'ponder:' || :'slug';
DELETE FROM metacognitive_observations
  WHERE target_layer = 'ponder:' || :'slug';
DELETE FROM hypotheses
  WHERE domain = 'ponder:' || :'slug';
DELETE FROM deliberations
  WHERE resolution_method = 'ponder-pass' AND decision LIKE 'ponder ' || :'slug' || ' pass%';
DELETE FROM episodic_memory
  WHERE event_type IN ('ponder_start', 'ponder_pass', 'ponder_converged', 'ponder_stopped', 'ponder_applied')
    AND content LIKE '%[' || :'slug' || ']%';
COMMIT;
```

---

## What degrades when OCA is down

Nothing in the engine. Every command runs, every file under `.ponder/<slug>/` is written,
every convergence signal is computed from the local ledger, every verdict rule in SPEC §4.1
still fires. `coverage < 1.0` still blocks `stop`. The bridge is not on the critical path
for a single one of those.

What you actually lose:

| Function | With OCA down | Consequence |
|---|---|---|
| `probe()` | `{ reachable: false, note }` | `ponder doctor` reports why |
| `priorPondering()` | `null` | `ponder start` prints no **Prior pondering** section. The session starts cold — it cannot pick up where the last one on this subject left off. |
| `recordStart()` | `null` | `session.oca.sessionRef` stays unset. No future session can find this one. |
| `recordPass()` | `null` | No forecast is opened and none is closed. The surprise ledger has a hole; `metrics.surprise` is still computed locally per pass from `predict.json` (from pass 2 — pass 1 has no churn to score against), so the pass's *own* surprise is intact — what is lost is the cross-pass forecast chain and the long-run self-model. |
| `recordDeliberation()` | `null` | The four arguments live only in `passes/NN/deliberation.json`. Nothing queryable across sessions. |
| `recordObservation()` | `null` | The observation is still in the session's own files; it just does not reach OCA's metacognition stream. |
| `openObservations()` | `null` | `ponder judge` loses its escalate tie-breaker and falls back to the SPEC §4.1 rules alone. That changes advice only in the narrow case where an open high-severity observation would have tipped a `continue` into an `escalate`. |
| `recordConverged()` | `null` | The session leaves no trace in cross-session memory. |
| `recordApply()` | `null` | `apply-plan.md` is still written and the session is still marked `applied`; OCA just has no record that the plan was handed over. |

Under `PONDER_OCA=auto` all of that is silent apart from `oca.log`. Under
`PONDER_OCA=on` the engine refuses to run instead.

Precisely: every command that would write an OCA row exits non-zero rather than dropping it
— `start`, `deliberate` (including `--skip`), `judge`, `decide stop`, and a committed
`apply`. Commands that write no row are untouched and keep working against a dead database:
`status`, `list`, `report`, `predict`, `units`, `grade`, `delta`, `decide continue`,
`abort`, and `apply --dry-run`. `doctor` also keeps working — it reports the unreachable
OCA as a problem, which is the whole reason you would run it.

That split is the point of the mode. Coupling means "never silently lose a row", not "make
the tool unusable while the database is restarting".

---

## `oca.log`

Every failure appends exactly one line to `<sessionDir>/oca.log`:

```
2026-08-24T15:35:52.627Z recordStart FAIL exit=2 psql: error: connection to server was lost dsn=postgres://localhost/oneiro ms=8
2026-08-24T15:36:17.374Z recordPass FAIL timeout after 5000ms dsn=postgres://localhost/oneiro ms=5005
2026-08-24T15:34:59.540Z probe DISABLED unreachable: exit=2 psql: error: connection refused dsn=postgres://127.0.0.1:1/nope mode=auto
2026-08-24T15:34:59.545Z openObservations SKIP oca unreachable (…) mode=auto dsn=postgres://localhost/oneiro
```

`FAIL` = the call was attempted and failed. `SKIP` = the memoised probe already said OCA is
unusable, so nothing was attempted. `DISABLED` / `FATAL` = the probe's own verdict.
Passwords in the DSN are masked. Multi-line psql errors are collapsed to one line.

A fully successful run writes **nothing** — an empty or absent `oca.log` means the bridge
had no complaints.

### There is no second log

SPEC §6.3 puts the bridge's log at `.ponder/<slug>/oca.log`, and that is the only file the
bridge writes. Nothing is written to `$HOME`, and nothing needs rotating.

`probe()` and `priorPondering()` take no session, so when they fail there may not be a
session directory yet. Their lines are buffered — capped at 50 — and flushed into the first
session log that resolves, usually milliseconds later when `recordStart()` runs. That is why
`ponder start` against a dead database still leaves a complete record in the session's own
log: both the probe's verdict and every subsequent `SKIP`.

A line that never finds a session goes to **stderr** on the way out, where the user already
is. In practice that drain stays silent, because the only genuinely session-less command is
`doctor` and `probe()` no longer buffers a line at all when no session log exists. It does
not need to: `probe()` hands its `note` straight back to its caller, and every caller shows
it — `doctor` and `start` print the reason, and under `PONDER_OCA=on` the engine raises it
as the hard error. Writing it again would only duplicate, into a file the user has to know
to look for, what is already on their screen.

This replaced a session-less `~/.ponder/oca.log`. That file was outside the contract, only
appeared on machines where `~/.ponder` happened to exist already, held nothing but probe
lines the user had just been shown, and grew forever because nothing rotated it. Documenting
it and adding rotation would have meant defending a second log location that SPEC §6.3 does
not describe; deleting it left `.ponder/<slug>/oca.log` as the whole truth.

---

## Safety

**No value is ever concatenated into SQL.** Every SQL statement in `bridge.js` is a fixed
string constant containing only `:'name'` placeholders. Values travel as separate
`-v name=value` entries in the `execFile` argv, and psql expands `:'name'` into a properly
escaped SQL literal. There is no shell anywhere in the path.

psql does *not* perform variable interpolation under `-c` — psql-specific features are
disabled there — so the SQL is fed on stdin with `-f -`. That is the only reason the stdin
plumbing exists.

Verified against the live database: a subject containing a single quote, a doubled quote, a
newline, a carriage return, a tab, a semicolon, a backslash, non-ASCII text, `DROP TABLE
hypotheses;`, `'; DELETE FROM episodic_memory; --`, a psql meta-command `\!`, and literal
`:notavar` / `:'alsonot'` lookalikes was inserted, read back byte-exact, and deleted.
Nothing executed; every table was intact afterwards.

Other guarantees:

- **5 second timeout per call**, 2 seconds for the `auto` probe, enforced with `SIGKILL`.
  `PGCONNECT_TIMEOUT` is set below the call budget so a black-hole host cannot outlast it.
- **`-w`** — psql never prompts for a password. Without it a password prompt would eat the
  SQL arriving on stdin.
- **`-X`** — `~/.psqlrc` is ignored, so a developer's psql settings cannot change what
  ponder writes.
- **`ON_ERROR_STOP=1`** — any SQL error is a non-zero exit, which becomes a logged `null`
  rather than a silent partial write.
- Values are stripped of NUL bytes (which cannot travel in argv) and truncated at 16 KB
  each, with a 240 KB total argv budget, well below `ARG_MAX`.
- **Values bound for a `jsonb` column are never cut like text.** `source_data` and
  `evidence` are clipped as JSON: long strings are shortened in place so the document keeps
  its shape and its keys — `source_data.forecast_churn` in particular, which the next pass
  reads back to score the forecast — and only a document still oversized after that
  collapses to `{"truncated":true,"chars":N,"preview":"…"}`. A raw slice would leave a
  half-finished token, Postgres would reject the cast, and the entire statement (episodic
  row, hypothesis, events) would be lost rather than shortened.
- `JSON.stringify` escapes a NUL as `\u0000` and an unpaired surrogate as `\uD800`–`\uDFFF`.
  Postgres rejects both in `jsonb`, so the NUL is dropped and a lone surrogate is folded to
  U+FFFD before the value leaves the bridge. A backslash a caller wrote on purpose is left
  alone — only an odd run of backslashes before the `u` is a real escape.
- Every multi-table write is a **single statement** built from data-modifying CTEs, so it
  is one transaction. A pass either records fully or not at all — there is no state where
  the episodic row landed but the hypothesis did not.
- **The pending forecast is claimed, not merely selected.** A per-domain
  `pg_try_advisory_xact_lock` plus `FOR UPDATE SKIP LOCKED` means two processes judging one
  slug produce exactly one close and one new forecast, and the loser is told it lost. See
  *One close per forecast, even under concurrency* above. The lock is transaction-scoped, so
  a process that crashes mid-statement releases it; nothing can be left held.
- **A null is never coerced into a number.** `Number(null)`, `Number('')`, `Number(false)`
  and `Number([])` are all `0` in JavaScript, so the bridge's `num()` rejects every one of
  them and takes its fallback instead. An unmeasured signal travels as an empty psql variable
  and every use of it in SQL is `nullif(…,'')`, so it lands as a genuine NULL. This is not a
  stylistic preference: a `0` in a churn or surprise column is a claim that the loop moved
  nothing, and writing that where nothing was measured is how the pass-1 forecast came to
  corrupt the head of the surprise series.
- **A `source_data` written by something other than ponder cannot poison a close.**
  `for_pass` is compared as text and never cast, and `forecast_churn` and `band` are
  shape-checked against a numeric pattern before either is cast — so a foreign row can
  neither abort the statement with an invalid float nor be scored against a forecast
  `coalesce`d to `0`.
- A DSN beginning with `-` is refused rather than handed to psql as a flag.
