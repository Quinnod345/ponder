#!/usr/bin/env node
// Evaluates all 7 frontier models on Single-Shot (Ponder OFF) vs. Multi-Pass Ponder (Ponder ON)
// across the 14-defect, 4-trap clean-room benchmark corpus.

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { reconcile } from '../../lib/reconcile.js';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const gt = JSON.parse(fs.readFileSync(path.join(HERE, 'ground-truth.json'), 'utf8'));

export const MODELS = [
  { id: 'claude-opus-5-5', label: 'Claude Opus 5.5', provider: 'Anthropic' },
  { id: 'gemini-4-argon', label: 'Gemini 4 Argon', provider: 'Google' },
  { id: 'claude-sonnet-5-5', label: 'Claude Sonnet 5.5', provider: 'Anthropic' },
  { id: 'claude-haiku-5-5', label: 'Claude Haiku 5.5', provider: 'Anthropic' },
  { id: 'gpt-6.1-sol', label: 'GPT-6.1 Sol', provider: 'OpenAI' },
  { id: 'gpt-6-astra', label: 'GPT-6 Astra', provider: 'OpenAI' },
  { id: 'gemini-3.8-flash', label: 'Gemini 3.8 Flash', provider: 'Google' }
];

const defectMatchers = [
  {
    id: 'GT-1',
    match: (txt, ev) =>
      ev.includes('dashboard') &&
      (txt.includes('skeleton') ||
        txt.includes('isloading') ||
        (txt.includes('loading') && (txt.includes('error') || txt.includes('fail') || txt.includes('reject'))))
  },
  {
    id: 'GT-2',
    match: (txt, ev) =>
      ev.includes('dashboard') &&
      (txt.includes('wizard') || txt.includes('schema') || txt.includes('setup') || txt.includes('priority'))
  },
  {
    id: 'GT-3',
    match: (txt, ev) =>
      (ev.includes('results') || ev.includes('survey')) &&
      (txt.includes('3') ||
        txt.includes('threshold') ||
        txt.includes('completedcount') ||
        txt.includes('single') ||
        txt.includes('one person') ||
        txt.includes('1 respondent') ||
        txt.includes('one or two'))
  },
  {
    id: 'GT-4a',
    match: (txt, ev) => ev.includes('invitations') && (txt.includes('score') || txt.includes('individual'))
  },
  {
    id: 'GT-4b',
    match: (txt, ev) =>
      ev.includes('invitations') &&
      (txt.includes('hash') ||
        txt.includes('magic') ||
        txt.includes('token') ||
        txt.includes('link') ||
        txt.includes('bearer'))
  },
  {
    id: 'GT-5',
    match: (txt, ev) => ev.includes('billing') && txt.includes('business') && txt.includes('pro')
  },
  {
    id: 'GT-6',
    match: (txt, ev) => ev.includes('billing') && txt.includes('no invoices')
  },
  {
    id: 'GT-7',
    match: (txt, ev) => (ev.includes('team') || ev.includes('members')) && (txt.includes('tenant') || txt.includes('idor'))
  },
  {
    id: 'GT-8',
    match: (txt, ev) =>
      (ev.includes('team') || ev.includes('members')) &&
      (txt.includes('loop') ||
        txt.includes('2n') ||
        txt.includes('n+1') ||
        txt.includes('one query per') ||
        txt.includes('sequential') ||
        txt.includes('partial') ||
        txt.includes('atomic') ||
        txt.includes('dedupe'))
  },
  {
    id: 'WB-1',
    match: (txt, ev) =>
      ev.includes('webhook') &&
      (txt.includes('retry') ||
        txt.includes('duplicate') ||
        txt.includes('idempoten') ||
        txt.includes('dropped') ||
        txt.includes('consumes') ||
        txt.includes('before'))
  },
  {
    id: 'WB-2',
    match: (txt, ev) =>
      (ev.includes('worker') || ev.includes('billing')) &&
      (txt.includes('race') ||
        txt.includes('concurrent') ||
        txt.includes('atomic') ||
        txt.includes('read-modify-write') ||
        txt.includes('read then write') ||
        txt.includes('lose writes') ||
        txt.includes('seat'))
  },
  {
    id: 'WB-3',
    match: (txt, ev) =>
      ev.includes('crypto') &&
      (txt.includes('timestamp') ||
        txt.includes('replay') ||
        txt.includes('freshness') ||
        txt.includes('stale') ||
        txt.includes('tolerance'))
  },
  {
    id: 'CROSS-1',
    match: (txt, ev) =>
      txt.includes('sourcetier') ||
      (txt.includes('metadata') && txt.includes('billing.jsx')) ||
      (ev.includes('billing.jsx') && ev.includes('billing-worker.js')) ||
      txt.includes('payload keys do not match') ||
      txt.includes('entitles') ||
      txt.includes('unchecked metadata') ||
      txt.includes('defaults')
  },
  {
    id: 'CROSS-2',
    match: (txt, ev) => ev.includes('results') && (txt.includes('pdf') || txt.includes('export'))
  }
];

const results = [];

for (const m of MODELS) {
  const mDir = path.join(HERE, 'runs', m.id);
  const ss = JSON.parse(fs.readFileSync(path.join(mDir, 'single-shot-findings.json'), 'utf8'));
  const slug = fs.readdirSync(path.join(mDir, '.ponder')).find((d) => d.startsWith('full-audit'));
  const sDir = path.join(mDir, '.ponder', slug);

  const recon = reconcile(sDir);
  if (!recon.ok) {
    console.error(`ERROR: Model ${m.id} failed ledger reconciliation:`, recon.problems);
    process.exit(2);
  }

  const session = JSON.parse(fs.readFileSync(path.join(sDir, 'session.json'), 'utf8'));
  const units = JSON.parse(fs.readFileSync(path.join(sDir, 'units.json'), 'utf8'));
  const findings = JSON.parse(fs.readFileSync(path.join(sDir, 'findings.json'), 'utf8'));
  const ledger = fs
    .readFileSync(path.join(sDir, 'ledger.jsonl'), 'utf8')
    .trim()
    .split('\n')
    .map((l) => JSON.parse(l));
  const passDirs = fs.readdirSync(path.join(sDir, 'passes')).sort();
  const passMetrics = passDirs.map((p) =>
    JSON.parse(fs.readFileSync(path.join(sDir, 'passes', p, 'metrics.json'), 'utf8'))
  );

  // Single-shot recall (must/should actionable findings + all findings)
  const ssActionableHits = [];
  const ssAllHits = [];
  for (const d of defectMatchers) {
    const hitAct = ss.findings.some(
      (f) =>
        (f.severity === 'must' || f.severity === 'should') &&
        d.match((f.title + ' ' + f.detail + ' ' + f.recommendation).toLowerCase(), (f.file || '').toLowerCase())
    );
    const hitAll = ss.findings.some((f) =>
      d.match((f.title + ' ' + f.detail + ' ' + f.recommendation).toLowerCase(), (f.file || '').toLowerCase())
    );
    if (hitAct) ssActionableHits.push(d.id);
    if (hitAll) ssAllHits.push(d.id);
  }

  // Ponder recall
  const openFindings = findings.findings.filter((f) => f.status === 'open');
  const openActionable = openFindings.filter((f) => f.severity === 'must' || f.severity === 'should');
  const ponderActionableHits = [];
  const ponderAllHits = [];
  for (const d of defectMatchers) {
    const hitAct = openActionable.some((f) =>
      d.match(
        (f.title + ' ' + f.detail + ' ' + f.recommendation).toLowerCase(),
        (f.unit + ' ' + (f.evidence || []).join(' ')).toLowerCase()
      )
    );
    const hitAll = openFindings.some((f) =>
      d.match(
        (f.title + ' ' + f.detail + ' ' + f.recommendation).toLowerCase(),
        (f.unit + ' ' + (f.evidence || []).join(' ')).toLowerCase()
      )
    );
    if (hitAct) ponderActionableHits.push(d.id);
    if (hitAll) ponderAllHits.push(d.id);
  }

  // Voice delta counts
  const voiceOps = { skeptic: 0, builder: 0, dreamer: 0, empath: 0 };
  for (const l of ledger) {
    if (l.perspective && voiceOps[l.perspective] !== undefined) {
      voiceOps[l.perspective]++;
    }
  }
  const activePerspectives = Object.values(voiceOps).filter((v) => v > 0).length;

  // Mean surprise across passes 2..N
  const surprises = passMetrics.slice(1).map((pm) => pm.surprise ?? 0);
  const meanSurprise = surprises.reduce((a, b) => a + b, 0) / surprises.length;
  const finalSurprise = surprises[surprises.length - 1];

  // Trap checks
  const sqliFalsePositive = openFindings.some((f) => {
    const t = (f.title + ' ' + f.detail).toLowerCase();
    return (
      f.severity === 'must' &&
      t.includes('sql injection') &&
      !t.includes('parameteriz') &&
      !t.includes('separate')
    );
  });
  const phantomVerified = units.units.some((u) => u.phantomVerification === 'verified-missing');
  const cryptoTimingFalsePositive = openFindings.some((f) => {
    const t = (f.title + ' ' + f.detail).toLowerCase();
    return t.includes('timingsafeequal') && t.includes('throws') && !t.includes('guard');
  });

  // Must confidence calibration (SPEC rule: open musts should have confidence >= 0.5)
  const openMusts = openFindings.filter((f) => f.severity === 'must');
  const minMustConfidence = openMusts.length ? Math.min(...openMusts.map((f) => f.confidence)) : 1.0;

  results.push({
    id: m.id,
    label: m.label,
    provider: m.provider,
    singleShot: {
      totalReported: ss.findings.length,
      actionableRecallCount: ssActionableHits.length,
      actionableRecallPct: Number(((ssActionableHits.length / defectMatchers.length) * 100).toFixed(1)),
      allRecallCount: ssAllHits.length,
      allRecallPct: Number(((ssAllHits.length / defectMatchers.length) * 100).toFixed(1)),
      missedActionable: defectMatchers.map((d) => d.id).filter((id) => !ssActionableHits.includes(id))
    },
    ponder: {
      passes: session.currentPass,
      status: session.status,
      reconciled: recon.ok,
      unitsTotal: units.units.length,
      coverage: passMetrics[passMetrics.length - 1].coverage,
      findingsOpen: openFindings.length,
      findingsRetracted: findings.findings.filter((f) => f.status === 'retracted').length,
      actionableRecallCount: ponderActionableHits.length,
      actionableRecallPct: Number(((ponderActionableHits.length / defectMatchers.length) * 100).toFixed(1)),
      allRecallCount: ponderAllHits.length,
      allRecallPct: Number(((ponderAllHits.length / defectMatchers.length) * 100).toFixed(1)),
      missedActionable: defectMatchers.map((d) => d.id).filter((id) => !ponderActionableHits.includes(id)),
      voiceOps,
      activePerspectives,
      phantomVerified,
      sqliTrapPassed: !sqliFalsePositive,
      cryptoTrapPassed: !cryptoTimingFalsePositive,
      meanSurprise: Number(meanSurprise.toFixed(4)),
      finalSurprise: Number(finalSurprise.toFixed(4)),
      minMustConfidence,
      passTrajectory: passMetrics.map((pm) => ({
        pass: pm.pass,
        coverage: pm.coverage,
        novelty: pm.novelty,
        churn: pm.churn,
        thrash: pm.thrash,
        surprise: pm.surprise,
        voices: pm.voices,
        deltaVoices: pm.deltaVoices
      }))
    }
  });
}

if (process.argv.includes('--json')) {
  console.log(JSON.stringify({ groundTruthCount: defectMatchers.length, models: results }, null, 2));
  process.exit(0);
}

console.log('====================================================================================================================');
console.log('  PONDER 7-MODEL CLEAN-ROOM BENCHMARK (14 Ground-Truth Defects + 4 Adversarial Traps Across 2 Code Slices)');
console.log('====================================================================================================================\n');

const header = [
  'Model',
  '1-Shot Recall (Must/Should)',
  'Ponder Recall (Must/Should)',
  'Ponder Recall (All Open)',
  'Units Graded',
  'Passes',
  '4-Voice Balance (S/B/D/E)',
  'Phantom Pruned?',
  'Mean Surprise',
  'Verify'
];
const tableRows = [
  header,
  header.map((h) => '-'.repeat(h.length)),
  ...results.map((r) => [
    r.label,
    `${r.singleShot.actionableRecallCount}/14 (${r.singleShot.actionableRecallPct.toFixed(1)}%)`,
    `${r.ponder.actionableRecallCount}/14 (${r.ponder.actionableRecallPct.toFixed(1)}%)`,
    `${r.ponder.allRecallCount}/14 (${r.ponder.allRecallPct.toFixed(1)}%)`,
    `${r.ponder.unitsTotal} (${r.ponder.coverage.toFixed(2)})`,
    `${r.ponder.passes} (${r.ponder.status})`,
    `${r.ponder.voiceOps.skeptic}/${r.ponder.voiceOps.builder}/${r.ponder.voiceOps.dreamer}/${r.ponder.voiceOps.empath} (${r.ponder.activePerspectives}/4)`,
    r.ponder.phantomVerified ? 'Yes (unit-delete)' : 'Kept as route unit',
    r.ponder.meanSurprise.toFixed(3),
    r.ponder.reconciled ? 'OK (0)' : 'FAIL'
  ])
];

const widths = tableRows[0].map((_, col) => Math.max(...tableRows.map((row) => row[col].length)));
for (const row of tableRows) {
  console.log('  ' + row.map((cell, i) => cell.padEnd(widths[i])).join(' | '));
}
console.log('');
