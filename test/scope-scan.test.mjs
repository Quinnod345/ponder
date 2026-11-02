import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFileSync, spawnSync } from 'node:child_process';

const CLI = path.resolve(new URL('../lib/cli.js', import.meta.url).pathname);

function runPonder(args, { cwd, env = {} } = {}) {
  return spawnSync(process.execPath, [CLI, ...args], {
    cwd,
    env: { ...process.env, PONDER_OCA: 'off', ...env },
    encoding: 'utf8',
  });
}

const tmpRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'ponder-scope-scan-'));
try {
  // Create a sample project with 3 routes under src/routes/
  const projDir = path.join(tmpRoot, 'proj');
  fs.mkdirSync(path.join(projDir, 'src', 'routes'), { recursive: true });
  fs.writeFileSync(path.join(projDir, 'package.json'), '{"name":"sample"}\n');
  fs.writeFileSync(path.join(projDir, 'src', 'routes', 'auth.js'), 'export const auth = 1;\n');
  fs.writeFileSync(path.join(projDir, 'src', 'routes', 'billing.js'), 'export const billing = 2;\n');
  fs.writeFileSync(path.join(projDir, 'src', 'routes', 'admin.js'), 'export const admin = 3;\n');
  execFileSync('git', ['init', '-q'], { cwd: projDir });

  // 1. Partial units.json with --scan and --strict-scope MUST fail with exit code 2
  let res = runPonder(['start', 'Audit routes', '--lens', 'architecture', '--slug', 'strict-check', '--json'], { cwd: projDir });
  assert.equal(res.status, 0, res.stderr);
  res = runPonder(['predict', '--churn', '0.5', '--claim', 'initial pass', '--session', 'strict-check', '--json'], { cwd: projDir });
  assert.equal(res.status, 0, res.stderr);

  const partialFile = path.join(tmpRoot, 'partial.json');
  fs.writeFileSync(
    partialFile,
    JSON.stringify([
      { id: 'auth', label: 'auth route', path: 'src/routes/auth.js' },
      { id: 'billing', label: 'billing route', path: 'src/routes/billing.js' },
    ]),
  );

  res = runPonder(
    ['units', '--file', partialFile, '--scan', 'src/routes', '--strict-scope', '--session', 'strict-check', '--json'],
    { cwd: projDir },
  );
  assert.equal(res.status, 2, 'strict-scope should reject partial inventory with exit code 2');
  const errJson = JSON.parse(res.stdout);
  assert.match(String(errJson.error && errJson.error.message ? errJson.error.message : errJson.error), /survey omitted 1 file/);

  // 2. Direct disk seeding via --scan src/routes enumerates all 3 routes deterministically
  res = runPonder(['units', '--scan', 'src/routes', '--session', 'strict-check', '--json'], { cwd: projDir });
  assert.equal(res.status, 0, res.stderr);
  const scanJson = JSON.parse(res.stdout);
  assert.equal(scanJson.units, 3);
  assert.equal(scanJson.withPath, 3);
  assert.deepEqual(scanJson.unenumeratedFiles, []);

  // 3. Reconciles cleanly via ponder verify
  res = runPonder(['verify', '--session', 'strict-check', '--json'], { cwd: projDir });
  assert.equal(res.status, 0, res.stderr);
  const verifyJson = JSON.parse(res.stdout);
  assert.equal(verifyJson.ok, true);

  // 4. Test --lens security, units --diff, deliberate with notes, and report --format pr-comment|sarif
  execFileSync('git', ['config', 'user.email', 'test@example.com'], { cwd: projDir });
  execFileSync('git', ['config', 'user.name', 'Test User'], { cwd: projDir });
  execFileSync('git', ['add', 'package.json', 'src/routes/auth.js'], { cwd: projDir });
  execFileSync('git', ['commit', '-qm', 'base commit'], { cwd: projDir });
  // Modify auth.js so git diff HEAD shows auth.js + untracked billing.js/admin.js
  fs.writeFileSync(path.join(projDir, 'src', 'routes', 'auth.js'), 'export const auth = 2;\n');

  res = runPonder(['start', 'Security diff review', '--lens', 'security', '--slug', 'sec-diff', '--json'], { cwd: projDir });
  assert.equal(res.status, 0, res.stderr);
  res = runPonder(['predict', '--churn', '0.5', '--claim', 'diff pass', '--session', 'sec-diff', '--json'], { cwd: projDir });
  assert.equal(res.status, 0, res.stderr);

  res = runPonder(['units', '--diff', '--session', 'sec-diff', '--json'], { cwd: projDir });
  assert.equal(res.status, 0, res.stderr);
  const diffUnitsJson = JSON.parse(res.stdout);
  assert.equal(diffUnitsJson.units, 3);

  const findingsFile = path.join(tmpRoot, 'sec-findings.json');
  fs.writeFileSync(
    findingsFile,
    JSON.stringify([
      { unit: 'u1', title: 'Admin route missing auth check', dimension: 'auth-and-authz', score: 2, severity: 'must', confidence: 0.9, effort: 's', evidence: ['src/routes/admin.js:1'], recommendation: 'Require admin role middleware.' },
      { unit: 'u2', title: 'Auth token verified properly', dimension: 'trust-boundaries', score: 4, severity: 'note', confidence: 0.9, effort: 'xs', evidence: ['src/routes/auth.js:1'] },
      { unit: 'u3', title: 'Billing input validated', dimension: 'input-validation', score: 4, severity: 'note', confidence: 0.9, effort: 'xs', evidence: ['src/routes/billing.js:1'] },
    ]),
  );
  res = runPonder(['grade', '--file', findingsFile, '--session', 'sec-diff', '--json'], { cwd: projDir });
  assert.equal(res.status, 0, res.stderr);

  const delibFile = path.join(tmpRoot, 'sec-delib.json');
  fs.writeFileSync(
    delibFile,
    JSON.stringify({
      skeptic: { confidence: 0.9, notes: 'Admin route finding verified against source.' },
      builder: { confidence: 0.9, notes: 'Add role guard to admin.js.' },
      dreamer: { confidence: 0.85, notes: 'All 3 diff files covered.' },
      empath: { confidence: 0.9, notes: 'Prevents unauthorized admin access.' },
    }),
  );
  res = runPonder(['deliberate', '--file', delibFile, '--session', 'sec-diff', '--json'], { cwd: projDir });
  assert.equal(res.status, 0, res.stderr);

  const prCommentPath = path.join(tmpRoot, 'pr-comment.md');
  res = runPonder(['report', '--format', 'pr-comment', '--out', prCommentPath, '--session', 'sec-diff', '--json'], { cwd: projDir });
  assert.equal(res.status, 0, res.stderr);
  const prComment = fs.readFileSync(prCommentPath, 'utf8');
  assert.match(prComment, /## Ponder Review: Security diff review/);
  assert.match(prComment, /Admin route missing auth check/);

  const sarifPath = path.join(tmpRoot, 'report.sarif.json');
  res = runPonder(['report', '--format', 'sarif', '--out', sarifPath, '--session', 'sec-diff', '--json'], { cwd: projDir });
  assert.equal(res.status, 0, res.stderr);
  const sarif = JSON.parse(fs.readFileSync(sarifPath, 'utf8'));
  assert.equal(sarif.version, '2.1.0');
  assert.equal(sarif.runs[0].tool.driver.name, 'Ponder');
  assert.equal(sarif.runs[0].results.length, 3);
  assert.equal(sarif.runs[0].results[0].level, 'error');
  assert.equal(sarif.runs[0].results[0].locations[0].physicalLocation.artifactLocation.uri, 'src/routes/admin.js');

  // 5. Test --lens code and agent-ergonomic schema aliases (name/files, summary, text/array notes)
  res = runPonder(['start', 'Code ergonomics review', '--lens', 'code', '--slug', 'code-ergo', '--json'], { cwd: projDir });
  assert.equal(res.status, 0, res.stderr);
  res = runPonder(['predict', '--churn', '0.2', '--claim', 'alias pass', '--session', 'code-ergo', '--json'], { cwd: projDir });
  assert.equal(res.status, 0, res.stderr);

  const aliasUnitsFile = path.join(tmpRoot, 'alias-units.json');
  fs.writeFileSync(
    aliasUnitsFile,
    JSON.stringify([{ name: 'route.auth', files: ['src/routes/auth.js'] }]),
  );
  res = runPonder(['units', '--file', aliasUnitsFile, '--session', 'code-ergo', '--json'], { cwd: projDir });
  assert.equal(res.status, 0, res.stderr);

  const aliasFindingsFile = path.join(tmpRoot, 'alias-findings.json');
  fs.writeFileSync(
    aliasFindingsFile,
    JSON.stringify([
      {
        unit: 'route.auth',
        summary: 'Auth constant is exported cleanly',
        dimension: 'correctness',
        score: 5,
        severity: 'note',
        confidence: 0.95,
        evidence: ['src/routes/auth.js:1'],
      },
    ]),
  );
  res = runPonder(['grade', '--file', aliasFindingsFile, '--session', 'code-ergo', '--json'], { cwd: projDir });
  assert.equal(res.status, 0, res.stderr);

  const aliasDelibFile = path.join(tmpRoot, 'alias-delib.json');
  fs.writeFileSync(
    aliasDelibFile,
    JSON.stringify({
      skeptic: [{ note: 'Verified export against source line 1.' }],
      builder: { text: 'No code changes needed.' },
      dreamer: { summary: 'All units covered.' },
      empath: { note: 'Clear API surface.' },
    }),
  );
  res = runPonder(['deliberate', '--file', aliasDelibFile, '--session', 'code-ergo', '--json'], { cwd: projDir });
  assert.equal(res.status, 0, res.stderr);

  // 6. Test Claude Code Mod (hooks/register.mjs) against active .ponder session
  const { register } = await import('../hooks/register.mjs');
  const handlers = [];
  register((event, matcherOrFn, maybeFn) => {
    if (typeof matcherOrFn === 'function') {
      handlers.push({ event, matcher: {}, fn: matcherOrFn });
    } else {
      handlers.push({ event, matcher: matcherOrFn || {}, fn: maybeFn });
    }
  });
  let lastStatus = null;
  const registeredCommands = [];
  const mockEngine = {
    session: { root: async () => projDir },
    fs: {
      exists: async (p) => fs.existsSync(p),
      list: async (p) => fs.readdirSync(p),
      read: async (p) => fs.readFileSync(p, 'utf8'),
    },
    command: {
      register: async (cmd) => registeredCommands.push(cmd),
    },
    ui: {
      status: (s) => {
        lastStatus = s;
      },
    },
  };
  const startHandler = handlers.find((h) => h.event === 'session.start');
  assert.ok(startHandler, 'session.start hook registered');
  await startHandler.fn(mockEngine, {}, async () => ({}));
  assert.equal(registeredCommands.length, 1);
  assert.equal(registeredCommands[0].name, 'ponder-status');
  assert.ok(lastStatus && lastStatus.includes('ponder (code-ergo)'), `Expected status line, got: ${lastStatus}`);
  assert.ok(lastStatus.includes('1/1 units'), `Expected 1/1 units in status line, got: ${lastStatus}`);

  const cmdHandler = handlers.find((h) => h.event === 'command.run' && h.matcher.command === 'ponder-status');
  assert.ok(cmdHandler, 'command.run{command=ponder-status} hook registered');
  const cardRes = await cmdHandler.fn(mockEngine, {});
  assert.ok(cardRes.text.includes('coverage  1/1 units (100%)'), `Expected coverage in card, got: ${cardRes.text}`);

  // 7. Test units --files, letter grades, and delta --none / object wrappers
  res = runPonder(['start', 'Test units --files and delta --none', '--lens', 'code', '--slug', 'ergo-plus', '--json'], { cwd: projDir });
  assert.equal(res.status, 0, res.stderr);

  res = runPonder(['predict', '--churn', '0.2', '--claim', 'initial pass', '--session', 'ergo-plus', '--json'], { cwd: projDir });
  assert.equal(res.status, 0, res.stderr);

  res = runPonder(['units', '--files', 'src/routes/auth.js', 'src/routes/admin.js', '--session', 'ergo-plus', '--json'], { cwd: projDir });
  assert.equal(res.status, 0, res.stderr);
  const filesUnits = JSON.parse(res.stdout);
  assert.equal(filesUnits.units, 2);
  assert.deepEqual(filesUnits.ids, ['u1', 'u2']);

  const letterGradeFile = path.join(tmpRoot, 'letter-grades.json');
  fs.writeFileSync(
    letterGradeFile,
    JSON.stringify([
      { unit: 'src/routes/auth.js', dimension: 'correctness', score: 'A', summary: 'Auth checked via path reference.' },
      { unit: 'src.routes.admin.js', dimension: 'correctness', grade: 'B', summary: 'Admin checked via dotted slug reference.' },
    ]),
  );
  res = runPonder(['grade', '--file', letterGradeFile, '--session', 'ergo-plus', '--json'], { cwd: projDir });
  assert.equal(res.status, 0, res.stderr);
  const letterGraded = JSON.parse(res.stdout);
  assert.equal(letterGraded.seeded, 2);

  res = runPonder(['deliberate', '--skip', '--why', 'Testing delta --none in pass 1', '--session', 'ergo-plus', '--json'], { cwd: projDir });
  assert.equal(res.status, 0, res.stderr);

  // Test delta --none flag in pass 1 revise phase
  res = runPonder(['delta', '--none', '--why', 'All findings confirmed', '--session', 'ergo-plus', '--json'], { cwd: projDir });
  assert.equal(res.status, 0, res.stderr);
  const noneDelta = JSON.parse(res.stdout);
  assert.equal(noneDelta.applied, 0);
  assert.equal(noneDelta.coverage, 1);

  res = runPonder(['judge', '--session', 'ergo-plus', '--json'], { cwd: projDir });
  assert.equal(res.status, 0, res.stderr);
  res = runPonder(['decide', 'continue', '--why', 'Proceed to pass 2 delta test', '--session', 'ergo-plus', '--json'], { cwd: projDir });
  assert.equal(res.status, 0, res.stderr);
  res = runPonder(['predict', '--churn', '0', '--claim', 'Zero churn pass 2', '--session', 'ergo-plus', '--json'], { cwd: projDir });
  assert.equal(res.status, 0, res.stderr);
  res = runPonder(['deliberate', '--skip', '--why', 'Testing quiet object delta in pass 2', '--session', 'ergo-plus', '--json'], { cwd: projDir });
  assert.equal(res.status, 0, res.stderr);

  // Test delta with {"added":[],"retracted":[],"modified":[]} in pass 2 revise phase
  const quietObjFile = path.join(tmpRoot, 'quiet-delta.json');
  fs.writeFileSync(quietObjFile, JSON.stringify({ added: [], retracted: [], modified: [] }));
  res = runPonder(['delta', '--file', quietObjFile, '--session', 'ergo-plus', '--json'], { cwd: projDir });
  assert.equal(res.status, 0, res.stderr);
  const quietDelta = JSON.parse(res.stdout);
  assert.equal(quietDelta.applied, 0);
  assert.equal(quietDelta.coverage, 1);

  // 8. Test global --dir and --project flags from an external working directory
  res = runPonder(['judge', '--session', 'ergo-plus', '--dir', projDir, '--json'], { cwd: os.tmpdir() });
  assert.equal(res.status, 0, res.stderr);
  res = runPonder(['status', '--session', 'ergo-plus', '--project', projDir, '--json'], { cwd: os.tmpdir() });
  assert.equal(res.status, 0, res.stderr);
  res = runPonder(['list', '--dir', projDir, '--json'], { cwd: os.tmpdir() });
  assert.equal(res.status, 0, res.stderr);
  const listDirJson = JSON.parse(res.stdout);
  assert.ok(listDirJson.sessions.some((s) => s.slug === 'ergo-plus'), 'list --dir should find ergo-plus session');

  // 9. Test agent alias ergonomics: --surprise/--rationale, doc.units per-dimension scores, voices[].position, --reason
  res = runPonder(['start', 'Agent alias ergonomics test', '--lens', 'code', '--slug', 'alias-ergo', '--dir', projDir, '--json'], { cwd: os.tmpdir() });
  assert.equal(res.status, 0, res.stderr);
  res = runPonder(['predict', '--surprise', '0.1', '--confidence', '0.9', '--rationale', 'Expect clean files', '--session', 'alias-ergo', '--dir', projDir, '--json'], { cwd: os.tmpdir() });
  assert.equal(res.status, 0, res.stderr);
  res = runPonder(['units', '--files', 'src/index.js', '--session', 'alias-ergo', '--dir', projDir, '--json'], { cwd: os.tmpdir() });
  assert.equal(res.status, 0, res.stderr);
  const unitGradesFile = path.join(tmpRoot, 'unit-grades.json');
  fs.writeFileSync(
    unitGradesFile,
    JSON.stringify({
      units: {
        'src/index.js': {
          scores: { correctness: 5, 'error-handling': 4, maintainability: 5 },
          note: 'Clean entrypoint with minor error-handling note',
        },
      },
      findings: [],
    }),
  );
  res = runPonder(['grade', '--file', unitGradesFile, '--pass', '1', '--session', 'alias-ergo', '--dir', projDir, '--json'], { cwd: os.tmpdir() });
  assert.equal(res.status, 0, res.stderr);
  const unitGradesJson = JSON.parse(res.stdout);
  assert.equal(unitGradesJson.coverage, 1);
  assert.equal(unitGradesJson.seeded, 1);

  const posDelibFile = path.join(tmpRoot, 'pos-delib.json');
  fs.writeFileSync(
    posDelibFile,
    JSON.stringify({
      pass: 1,
      voices: [
        { voice: 'skeptic', position: 'Verified src/index.js. VOTE: DONE.' },
        { voice: 'builder', position: 'No changes needed. VOTE: DONE.' },
        { voice: 'dreamer', position: 'Scope complete. VOTE: DONE.' },
        { voice: 'empath', position: 'Clear output. VOTE: DONE.' },
      ],
    }),
  );
  res = runPonder(['deliberate', '--file', posDelibFile, '--pass', '1', '--session', 'alias-ergo', '--dir', projDir, '--json'], { cwd: os.tmpdir() });
  assert.equal(res.status, 0, res.stderr);
  res = runPonder(['delta', '--none', '--reason', 'No revisions needed on pass 1', '--pass', '1', '--session', 'alias-ergo', '--dir', projDir, '--json'], { cwd: os.tmpdir() });
  assert.equal(res.status, 0, res.stderr);
  res = runPonder(['judge', '--pass', '1', '--session', 'alias-ergo', '--dir', projDir, '--json'], { cwd: os.tmpdir() });
  assert.equal(res.status, 0, res.stderr);
  res = runPonder(['decide', 'continue', '--reason', 'Advance to pass 2', '--pass', '1', '--session', 'alias-ergo', '--dir', projDir, '--json'], { cwd: os.tmpdir() });
  assert.equal(res.status, 0, res.stderr);

  console.log('scope-scan.test.mjs: all assertions passed');
} finally {
  fs.rmSync(tmpRoot, { recursive: true, force: true });
}
