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

  console.log('scope-scan.test.mjs: all assertions passed');
} finally {
  fs.rmSync(tmpRoot, { recursive: true, force: true });
}
