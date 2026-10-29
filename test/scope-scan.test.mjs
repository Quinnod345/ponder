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

  console.log('scope-scan.test.mjs: all assertions passed');
} finally {
  fs.rmSync(tmpRoot, { recursive: true, force: true });
}
