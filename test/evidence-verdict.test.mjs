import test from 'node:test';
import assert from 'node:assert/strict';
import { computeVerdict } from '../lib/verdict.js';
const session = { minPasses: 2, maxPasses: 6, unitLabel: 'module' };
const m = { pass: 3, coverage: 1, ungraded: [], units: { enumerated: 3 }, thrash: 0,
  stall: 2, novelty: 0, churn: 0, confidenceFloor: 0, voices: 4 };
test('quiet uncertainty escalates rather than becoming a completed review', () => {
  const v = computeVerdict({ session, metrics: { ...m, confidenceFloor: 0.1 } });
  assert.equal(v.verdict, 'escalate'); assert.equal(v.reason, 'low-confidence');
});
test('a quiet pass without perspectives has not earned convergence', () => {
  const v = computeVerdict({ session, metrics: { ...m, voices: 1 } });
  assert.equal(v.verdict, 'escalate'); assert.equal(v.reason, 'insufficient-perspectives');
});
test('unresolved uncertainty can stop at budget, but cannot be called converged', () => {
  const v = computeVerdict({ session, metrics: { ...m, pass: 6, confidenceFloor: 1 } });
  assert.equal(v.verdict, 'stop'); assert.equal(v.reason, 'budget');
});
test('both quiet passes need adequate review coverage and confidence', () => {
  const metrics = { ...m, stall: 0, churn: .05, novelty: 0 };
  const prior = { ...metrics, pass: 2, voices: 1 };
  assert.notEqual(computeVerdict({ session, metrics, priorMetrics: [prior] }).reason, 'converged');
  prior.voices = 4;
  assert.equal(computeVerdict({ session, metrics, priorMetrics: [prior] }).reason, 'converged');
});
test('coverage still blocks every budget or uncertainty escape', () => {
  const v = computeVerdict({ session, metrics: { ...m, pass: 6, confidenceFloor: 1, coverage: .99, ungraded: ['missing'] } });
  assert.equal(v.verdict, 'blocked');
});

test('two fully reviewed zero-delta passes earn convergence, not a generic stall stop', () => {
  const v = computeVerdict({ session, metrics: m, priorMetrics: [{ ...m, pass: 2, stall: 1 }] });
  assert.equal(v.reason, 'converged');
});
