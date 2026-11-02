// Ponder Claude Code Mod: read-only status line and /ponder-status inspector.
// Reads .ponder/<slug>/{session,units,findings}.json to display live deliberation
// progress, coverage, and convergence state in Claude Code 2.1.287+.

async function loadLatestSession($) {
  const root = await $.session.root();
  if (!root) return null;
  const storeDir = `${root}/.ponder`;
  if (!(await $.fs.exists(storeDir))) return null;

  let entries = [];
  try {
    entries = await $.fs.list(storeDir);
  } catch {
    return null;
  }

  let newest = null;
  for (const entry of entries) {
    const name = typeof entry === 'string' ? entry : entry?.name;
    if (!name || name.startsWith('.')) continue;
    const sessionPath = `${storeDir}/${name}/session.json`;
    if (!(await $.fs.exists(sessionPath))) continue;
    try {
      const raw = await $.fs.read(sessionPath);
      const session = JSON.parse(String(raw));
      if (!session || typeof session !== 'object') continue;
      const updated = Date.parse(session.updatedAt || session.startedAt || '') || 0;
      if (!newest || updated >= newest.updated) {
        newest = { slug: session.slug || name, dir: `${storeDir}/${name}`, session, updated };
      }
    } catch {
      continue;
    }
  }
  if (!newest) return null;

  let unitList = [];
  const unitsPath = `${newest.dir}/units.json`;
  if (await $.fs.exists(unitsPath)) {
    try {
      const units = JSON.parse(String(await $.fs.read(unitsPath)));
      unitList = Array.isArray(units) ? units : Array.isArray(units?.units) ? units.units : [];
    } catch {
      // ignore unreadable units.json
    }
  }

  let findingList = [];
  const findingsPath = `${newest.dir}/findings.json`;
  if (await $.fs.exists(findingsPath)) {
    try {
      const findings = JSON.parse(String(await $.fs.read(findingsPath)));
      findingList = Array.isArray(findings) ? findings : Array.isArray(findings?.findings) ? findings.findings : [];
    } catch {
      // ignore unreadable findings.json
    }
  }

  const standing = findingList.filter((f) => f && f.status !== 'retracted');
  const gradedUnitIds = new Set(standing.map((f) => f.unit).filter(Boolean));
  const activeUnits = unitList.filter((u) => u && u.status !== 'removed');
  const totalUnits = activeUnits.length;
  const gradedUnits = activeUnits.filter(
    (u) => gradedUnitIds.has(u.id) || gradedUnitIds.has(u.path) || Boolean(u.grade || u.score),
  ).length;
  const activeFindings = standing.length;

  return {
    slug: newest.slug,
    session: newest.session,
    totalUnits,
    gradedUnits,
    activeFindings,
  };
}

function formatStatusLine(info) {
  if (!info) return undefined;
  const { slug, session, totalUnits, gradedUnits, activeFindings } = info;
  const pass = session.pass ?? 1;
  const phase = session.phase || 'survey';
  const status = session.status || 'open';
  const cov = totalUnits > 0 ? `${gradedUnits}/${totalUnits} units` : '0 units';
  return `ponder (${slug}) : pass ${pass} ${phase} | ${cov} | ${activeFindings} findings | ${status}`;
}

function formatStatusCard(info) {
  if (!info) {
    return 'ponder: no active session in .ponder/. Start one with: ponder start "<subject>" --files <paths>';
  }
  const { slug, session, totalUnits, gradedUnits, activeFindings } = info;
  const pct = totalUnits > 0 ? Math.round((gradedUnits / totalUnits) * 100) : 0;
  return [
    `session   ${slug}`,
    `subject   ${session.subject || '(none)'}`,
    `lens      ${session.lens || 'review'}`,
    `status    ${session.status || 'open'} (pass ${session.pass ?? 1}, phase: ${session.phase || 'survey'})`,
    `coverage  ${gradedUnits}/${totalUnits} units (${pct}%)`,
    `findings  ${activeFindings} active`,
  ].join('\n');
}

export const register = (on) => {
  on('session.start', async ($, e, next) => {
    const r = await next(e);
    await $.command.register({
      name: 'ponder-status',
      description: 'Show active Ponder deliberation session status, pass, unit coverage, and findings',
      argumentHint: '[status]',
      immediate: true,
    });
    const info = await loadLatestSession($);
    $.ui.status(formatStatusLine(info));
    return r;
  });

  on('turn.complete', async ($, e, next) => {
    const r = await next(e);
    if (!e.agentId) {
      const info = await loadLatestSession($);
      $.ui.status(formatStatusLine(info));
    }
    return r;
  });

  on('command.run', { command: 'ponder-status' }, async ($) => {
    const info = await loadLatestSession($);
    $.ui.status(formatStatusLine(info));
    return { text: formatStatusCard(info) };
  });
};
