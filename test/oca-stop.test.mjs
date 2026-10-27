import test from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { randomBytes } from 'node:crypto';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

test('real OCA bridge records stopped versus converged truthfully in an isolated schema', async (t) => {
  const schema = `ponder_test_${randomBytes(6).toString('hex')}`;
  const dsn = process.env.OCA_TEST_DATABASE_URL || 'postgres://localhost/oneiro';
  const sql = text => execFileSync('psql', [dsn, '-w', '-X', '-qAt', '-v', 'ON_ERROR_STOP=1', '-c', text], { encoding: 'utf8', timeout: 5000 });
  try {
    sql('SELECT 1');
  } catch {
    t.skip(`OCA database not reachable at ${dsn}; set OCA_TEST_DATABASE_URL to run live Postgres test`);
    return;
  }
  const scratch = mkdtempSync(join(tmpdir(), 'ponder-stop-'));
  const old = { mode: process.env.PONDER_OCA, dsn: process.env.PONDER_OCA_DSN, options: process.env.PGOPTIONS };
  try {
    sql(`CREATE SCHEMA ${schema};
      CREATE TABLE ${schema}.episodic_memory (id SERIAL, event_type TEXT, content TEXT, actual_outcome TEXT, surprise_magnitude FLOAT8, importance_score FLOAT8, emotional_valence FLOAT8, consolidation_status TEXT);
      CREATE TABLE ${schema}.hypotheses (id SERIAL, status TEXT, tested_at TIMESTAMPTZ, model_update TEXT, domain TEXT);
      CREATE TABLE ${schema}.cognitive_events (id SERIAL, event_type TEXT, source_layer TEXT, target_layer TEXT, priority FLOAT8, payload JSONB);`);
    process.env.PONDER_OCA = 'on'; process.env.PONDER_OCA_DSN = dsn;
    process.env.PGOPTIONS = `-c search_path=${schema},public`;
    const bridge = await import('../oca/bridge.js');
    const base = { subject: '[isolated verification]', lens: 'tests', currentPass: 3, project: scratch, dir: scratch };
    const stopped = await bridge.recordConverged({ ...base, slug: schema + '-stop', status: 'stopped' }, 'Budget exhausted, not convergence');
    const converged = await bridge.recordConverged({ ...base, slug: schema + '-converged', status: 'converged' }, 'Two complete stable reviews');
    assert.ok(stopped?.episodeId); assert.ok(converged?.episodeId);
    assert.equal(sql(`SELECT event_type FROM ${schema}.episodic_memory ORDER BY id`).trim(), 'ponder_stopped\nponder_converged');
  } finally {
    for (const [key, val] of [['PONDER_OCA', old.mode], ['PONDER_OCA_DSN', old.dsn], ['PGOPTIONS', old.options]]) {
      if (val === undefined) delete process.env[key]; else process.env[key] = val;
    }
    sql(`DROP SCHEMA IF EXISTS ${schema} CASCADE`);
    rmSync(scratch, { recursive: true, force: true });
  }
});
