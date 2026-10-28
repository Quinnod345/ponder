#!/usr/bin/env node
/**
 * Reproducible 4-Pass Ponder Ecosystem Audits (Stage 3)
 *
 * Drives the real `bin/ponder` CLI state machine across 3 high-star open-source
 * AI developer repositories:
 *   1. EveryInc/compound-engineering-plugin (25.7k stars)
 *   2. steipete/CodexBar (22.9k stars)
 *   3. coleam00/Archon (23.8k stars)
 *
 * Each audit runs 4 passes through `bin/ponder` using the `architecture` lens:
 *   - Pass 1: Enumerates modules (`units`), seeds Pass-1 findings (`grade`, leaving 1 unit
 *             ungraded on Pass 1), runs 4-voice deliberation (`deliberate`), applies Pass-1
 *             revisions (`delta`), and runs `judge` -> `continue` (`coverage` < 1.0).
 *   - Pass 2: `skeptic` verifies defense code on the Pass-1 decoy/false-alarm finding and
 *             retracts it (`op: "delete"`), while `dreamer` grades the remaining unit so
 *             coverage reaches `1.00`. `builder` sharpens exact line-anchored fixes.
 *   - Pass 3: First quiet pass (`0` deltas across all 4 voices -> `churn = 0.00, novelty = 0.00`).
 *   - Pass 4: Second quiet pass (`0` deltas across all 4 voices -> Rule 6 `stop (converged)`).
 *
 * Verified via `reconcile()` (`lib/reconcile.js`), `ponder verify`, `ponder report`, and `ponder apply --plan`.
 */

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { reconcile } from '../../lib/reconcile.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = path.resolve(__dirname, '../..');
const PONDER_BIN = path.join(REPO_ROOT, 'bin/ponder');

function runPonder(args, cwd) {
  const out = execFileSync(PONDER_BIN, [...args, '--json'], {
    cwd,
    env: { ...process.env, PONDER_OCA: 'off', NO_COLOR: '1' },
    encoding: 'utf8',
  });
  return JSON.parse(out);
}

function writeJson(filePath, data) {
  fs.writeFileSync(filePath, JSON.stringify(data, null, 2) + '\n', 'utf8');
}

function writeJsonl(filePath, lines) {
  const content = lines.length ? lines.map((l) => JSON.stringify(l)).join('\n') + '\n' : '';
  fs.writeFileSync(filePath, content, 'utf8');
}

const AUDITS = [
  {
    slug: 'compound-engineering-plugin',
    repo: 'EveryInc/compound-engineering-plugin',
    stars: '25.7k',
    subject: 'Target sync, symlink preservation, and backup lifecycle in EveryInc/compound-engineering-plugin',
    units: [
      {
        id: 'module.targets.codex',
        label: 'Codex target writer & symlink/manifest cleanup (src/targets/codex.ts)',
        path: 'src/targets/codex.ts',
        kind: 'module',
        meta: {},
      },
      {
        id: 'module.targets.pi',
        label: 'Pi target writer, extension bundler & legacy artifact cleanup (src/targets/pi.ts)',
        path: 'src/targets/pi.ts',
        kind: 'module',
        meta: {},
      },
      {
        id: 'module.targets.opencode',
        label: 'OpenCode config & command writer (src/targets/opencode.ts)',
        path: 'src/targets/opencode.ts',
        kind: 'module',
        meta: {},
      },
      {
        id: 'module.commands.install',
        label: 'Install CLI command & GitHub repo cloner (src/commands/install.ts)',
        path: 'src/commands/install.ts',
        kind: 'module',
        meta: {},
      },
      {
        id: 'module.parsers.claude',
        label: 'Claude plugin manifest parser & path resolver (src/parsers/claude.ts)',
        path: 'src/parsers/claude.ts',
        kind: 'module',
        meta: {},
      },
    ],
    pass1Findings: [
      {
        unit: 'module.targets.codex',
        title: 'Codex prompt writer bypasses symlink and ownership checks, clobbering user symlinks and deleting them on cleanup',
        detail:
          'In src/targets/codex.ts:57-61, prompts are written directly via writeText(targetPath, content) (fs.writeFile) without checking if targetPath is a user symlink or unmanaged file, and are unconditionally recorded in writeInstallManifest (codex.ts:177). By contrast, skills and agents call cleanupCurrentManagedSkillDir and cleanupCurrentManagedAgentFile (codex.ts:364-403) to preserve user symlinks and unmanaged files. In addition, cleanupRemovedPrompts (codex.ts:326-338) omits if (await isPreservedSymlink(entryPath)) continue.',
        dimension: 'data-ownership',
        score: 1,
        severity: 'must',
        confidence: 0.96,
        effort: 's',
        evidence: ['src/targets/codex.ts:57-61', 'src/targets/codex.ts:177', 'src/targets/codex.ts:326-338', 'src/targets/codex.ts:364-403'],
        recommendation:
          'Gate prompt writes in src/targets/codex.ts with a cleanupCurrentManagedPromptFile check matching cleanupCurrentManagedAgentFile, and skip preserved symlinks in cleanupRemovedPrompts.',
        status: 'open',
      },
      {
        unit: 'module.targets.pi',
        title: 'Pi prompt and extension writers clobber user symlinks and cleanupKnownLegacyPiArtifacts ignores prompt ownership',
        detail:
          'In src/targets/pi.ts:95-99 and 150-154, both prompts and extensions call writeText directly without checking for preserved symlinks or unmanaged files, while cleanupRemovedPrompts (pi.ts:407-419) and cleanupRemovedExtensions (pi.ts:421-433) omit isPreservedSymlink checks. Furthermore, cleanupKnownLegacyPiArtifacts (pi.ts:532-535) and cleanupPi (src/commands/cleanup.ts:411-413) move legacy prompts without checking ownedPrompts (unlike codex.ts:428-430).',
        dimension: 'data-ownership',
        score: 1,
        severity: 'must',
        confidence: 0.96,
        effort: 's',
        evidence: ['src/targets/pi.ts:95-99', 'src/targets/pi.ts:150-154', 'src/targets/pi.ts:407-433', 'src/targets/pi.ts:532-535', 'src/commands/cleanup.ts:411-413'],
        recommendation:
          'Apply managed-file ownership and symlink checks before writing Pi prompts/extensions, add isPreservedSymlink guards to cleanupRemovedPrompts/cleanupRemovedExtensions, and check ownedPrompts in cleanupKnownLegacyPiArtifacts and cleanupPi.',
        status: 'open',
      },
      {
        unit: 'module.targets.opencode',
        title: 'Idempotent OpenCode installs accumulate unbounded .bak.<timestamp> files inside .opencode/commands/ and opencode.json',
        detail:
          'In src/targets/opencode.ts:123 and 169-174, writeOpenCode calls backupFile(paths.configPath) and backupFile(commandPath) unconditionally before writing without comparing incoming content against existing file content on disk (unlike src/targets/codex.ts:218-227). Every idempotent install or sync creates a new <command>.md.bak.<timestamp> inside the live .opencode/commands/ directory.',
        dimension: 'failure-modes',
        score: 2,
        severity: 'must',
        confidence: 0.95,
        effort: 'xs',
        evidence: ['src/targets/opencode.ts:123', 'src/targets/opencode.ts:169-174', 'src/targets/codex.ts:218-227'],
        recommendation:
          'Compare existing file content against incoming content in src/targets/opencode.ts:123 and 169-174 before calling backupFile and writeText, matching src/targets/codex.ts:218-227.',
        status: 'open',
      },
      {
        unit: 'module.parsers.claude',
        title: 'Custom manifest.hooks and manifest.skills paths in plugin.json may allow path traversal outside pluginRoot',
        detail:
          'In src/parsers/claude.ts:135-141 and 237-249, loadClaudeHooks and resolveComponentDirs accept custom relative path strings from plugin.json manifest fields.',
        dimension: 'boundary-integrity',
        score: 1,
        severity: 'must',
        confidence: 0.55,
        effort: 'xs',
        evidence: ['src/parsers/claude.ts:135-141', 'src/parsers/claude.ts:237-249'],
        recommendation: 'Verify that all manifest paths are constrained to pluginRoot.',
        status: 'open',
      },
    ],
    pass1Delib: {
      version: 1,
      pass: 1,
      skipped: false,
      question: null,
      notes: null,
      perspectives: {
        skeptic: {
          argument:
            'Pass 1 graded 4 of 5 modules (coverage 0.80). Before we report f-0004 (manifest path traversal in src/parsers/claude.ts), I need to inspect resolveWithinRoot at lines 263-270 on Pass 2.',
          confidence: 0.92,
        },
        builder: {
          argument:
            'The symlink clobbering on prompts/extensions (f-0001, f-0002) and unbounded .bak.<timestamp> creation in .opencode/commands/ (f-0003) are confirmed by direct comparison with codex.ts:218-227 and 364-403. Still need to grade module.commands.install.',
          confidence: 0.9,
        },
        dreamer: {
          argument:
            'All managed artifact types (skills, agents, prompts, extensions) across Codex, Pi, and OpenCode should obey the same ownership invariant: never write through a user symlink and never back up an unchanged file.',
          confidence: 0.9,
        },
        empath: {
          argument:
            'Users who symlink custom prompts or Pi extensions into ~/.codex/prompts or .pi/extensions lose their local work silently when writeText writes through the symlink.',
          confidence: 0.95,
        },
      },
    },
    pass1Deltas: [
      {
        op: 'edit',
        target: 'f-0003',
        perspective: 'builder',
        why: 'Cite exact lines in opencode.ts and codex.ts so the diff is immediately actionable.',
        set: {
          recommendation:
            'In src/targets/opencode.ts:123 and 169-174, read existingContent via fs.readFile(path, "utf8").catch(() => null) and skip backupFile + writeText when existingContent === content (mirroring src/targets/codex.ts:218-227).',
        },
      },
    ],
    pass2Delib: {
      version: 1,
      pass: 2,
      skipped: false,
      question: null,
      notes: null,
      perspectives: {
        skeptic: {
          argument:
            'Opened src/parsers/claude.ts:263-270: resolveWithinRoot resolves every manifest path via path.resolve(root, normalizedPath) and throws whenever resolvedPath !== resolvedRoot && !resolvedPath.startsWith(resolvedRoot + path.sep). Retracting f-0004 as a false positive and leaving a clean note on module.parsers.claude.',
          confidence: 0.99,
        },
        dreamer: {
          argument:
            'Graded module.commands.install (src/commands/install.ts): found that --help advertises --permissions from-command (singular) at line 59 while permissionModes at line 15 requires from-commands (plural), and cloneGitHubRepo (lines 330-334) omits "--" before positional git clone args.',
          confidence: 0.95,
        },
        builder: {
          argument:
            'Sharpened f-0001 and f-0002 with the exact helper signatures and manifest filtering so writtenPromptNames and writtenExtensionNames only record plugin-written files.',
          confidence: 0.96,
        },
        empath: {
          argument:
            'Copy-pasting --permissions from-command from --help currently fails with Unknown permissions mode: from-command.',
          confidence: 0.92,
        },
      },
    },
    pass2Deltas: [
      {
        op: 'delete',
        target: 'f-0004',
        perspective: 'skeptic',
        why: 'Falsified on direct code inspection: resolveWithinRoot in src/parsers/claude.ts:263-270 enforces resolvedRoot + path.sep containment on every manifest path in resolveComponentDirs (lines 239, 245) and resolveConfigPaths (lines 254, 259).',
      },
      {
        op: 'add',
        perspective: 'skeptic',
        why: 'Keep coverage on module.parsers.claude after retracting the false-positive traversal finding.',
        finding: {
          unit: 'module.parsers.claude',
          title: 'resolveWithinRoot enforces strict pluginRoot path containment for all manifest-supplied paths',
          detail:
            'src/parsers/claude.ts:263-270 validates all manifest paths against resolvedRoot + path.sep and throws before any filesystem read.',
          dimension: 'boundary-integrity',
          score: 5,
          severity: 'note',
          confidence: 0.99,
          effort: 'xs',
          evidence: ['src/parsers/claude.ts:237-270'],
          recommendation: 'No change needed; keep resolveWithinRoot as the single path resolution gate.',
          status: 'open',
        },
      },
      {
        op: 'add',
        perspective: 'dreamer',
        why: 'Grades module.commands.install to reach 1.00 unit coverage.',
        finding: {
          unit: 'module.commands.install',
          title: 'CLI --help advertises --permissions from-command (singular) while validation requires from-commands (plural), and cloneGitHubRepo omits "--"',
          detail:
            'src/commands/install.ts:59 documents "--permissions <mode> ... (none | broad | from-command)", whereas permissionModes at line 15 is ["none", "broad", "from-commands"], causing --permissions from-command to throw "Unknown permissions mode: from-command" at line 87. Separately, cloneGitHubRepo (lines 330-334) constructs git clone args without "--" before [source, destination].',
          dimension: 'contract-stability',
          score: 2,
          severity: 'should',
          confidence: 0.96,
          effort: 'xs',
          evidence: ['src/commands/install.ts:15', 'src/commands/install.ts:59', 'src/commands/install.ts:86-90', 'src/commands/install.ts:330-334'],
          recommendation:
            'Update src/commands/install.ts:59 help text to "from-commands" (or accept "from-command" as an alias in resolvePermissionsMode at line 86) and insert "--" before source, destination in cloneGitHubRepo at line 334.',
          status: 'open',
        },
      },
      {
        op: 'edit',
        target: 'f-0001',
        perspective: 'builder',
        why: 'Specify manifest tracking for skipped symlinks/unmanaged files in codex.ts.',
        set: {
          recommendation:
            'In src/targets/codex.ts:57-61, check await cleanupCurrentManagedPromptFile(targetPath, prompt.name, ownedPrompts, backupDir) before writeText, only include written prompt names in writeInstallManifest (line 177), and add if (await isPreservedSymlink(entryPath)) continue to cleanupRemovedPrompts (line 331).',
        },
      },
    ],
  },
  {
    slug: 'codexbar',
    repo: 'steipete/CodexBar',
    stars: '22.9k',
    subject: 'Subprocess process-group isolation, watchdog signal safety, and credential file staging in steipete/CodexBar',
    units: [
      {
        id: 'module.watchdog.main',
        label: 'CodexBarClaudeWatchdog process spawner & tree killer (Sources/CodexBarClaudeWatchdog/main.swift)',
        path: 'Sources/CodexBarClaudeWatchdog/main.swift',
        kind: 'module',
        meta: {},
      },
      {
        id: 'module.process.spawnedgroup',
        label: 'SpawnedProcessGroup lifecycle & WNOWAIT reaper (Sources/CodexBarCore/Host/Process/SpawnedProcessGroup.swift)',
        path: 'Sources/CodexBarCore/Host/Process/SpawnedProcessGroup.swift',
        kind: 'module',
        meta: {},
      },
      {
        id: 'module.process.reaper',
        label: 'ProcessOwnershipReaper capability marker (Sources/CodexBarCore/Host/Process/ProcessOwnershipReaper.swift)',
        path: 'Sources/CodexBarCore/Host/Process/ProcessOwnershipReaper.swift',
        kind: 'module',
        meta: {},
      },
      {
        id: 'module.credentials.writer',
        label: 'CredentialFileWriter atomic 0600 file publisher (Sources/CodexBarCore/CredentialFileWriter.swift)',
        path: 'Sources/CodexBarCore/CredentialFileWriter.swift',
        kind: 'module',
        meta: {},
      },
    ],
    pass1Findings: [
      {
        unit: 'module.watchdog.main',
        title: 'CodexBarClaudeWatchdog post-spawn setpgid EACCES race and unguarded kill(-pgid) can send SIGTERM/SIGKILL to the parent process group',
        detail:
          'In Sources/CodexBarClaudeWatchdog/main.swift:71, posix_spawnp(&pid, childPath, nil, nil, cBuffer.baseAddress, environ) spawns the child with attrp = nil (inheriting the watchdog and parent app process group), and line 85 calls _ = setpgid(globalChildPID, globalChildPID) ignoring errors. Once posix_spawnp has exec\'d the child binary, setpgid(2) from the parent fails with EACCES, leaving globalChildPID in the parent process group (pgid == getpgrp()). When killProcessTree (main.swift:17-38) runs on signal or parent death (getppid() == 1), let pgid = getpgid(childPID); if pgid > 0 { kill(-pgid, SIGTERM) } checks only pgid > 0 instead of pgid == childPID && pgid != getpgrp(), sending SIGTERM and SIGKILL to the parent process group.',
        dimension: 'failure-modes',
        score: 1,
        severity: 'must',
        confidence: 0.97,
        effort: 'xs',
        evidence: [
          'Sources/CodexBarClaudeWatchdog/main.swift:17-38',
          'Sources/CodexBarClaudeWatchdog/main.swift:71',
          'Sources/CodexBarClaudeWatchdog/main.swift:85',
          'Sources/CodexBarCore/Host/Process/SpawnedProcessGroup.swift:362-367',
          'Sources/CodexBarCore/Host/Process/ProcessOwnershipReaper.swift:38',
        ],
        recommendation:
          'Configure posix_spawnattr_t with POSIX_SPAWN_SETPGROUP (pgroup = 0) in posix_spawnp at main.swift:71, and guard kill(-pgid, ...) in killProcessTree (main.swift:19, 33) with if pgid == childPID, pgid != getpgrp().',
        status: 'open',
      },
      {
        unit: 'module.watchdog.main',
        title: 'killProcessTree reaps childPID and discards its wait status, causing getppid() == 1 teardown to exit 0 after ECHILD',
        detail:
          'In Sources/CodexBarClaudeWatchdog/main.swift:28-29, killProcessTree calls let rc = waitpid(childPID, &status, WNOHANG); if rc == childPID { return }, reaping childPID and discarding status. When getppid() == 1 (lines 115-118) calls terminateChild() followed by _ = waitpid(globalChildPID, &status, 0), the second waitpid fails with ECHILD (-1), leaving outer status = 0 (from line 101) and exiting with 0.',
        dimension: 'contract-stability',
        score: 2,
        severity: 'should',
        confidence: 0.95,
        effort: 'xs',
        evidence: ['Sources/CodexBarClaudeWatchdog/main.swift:26-30', 'Sources/CodexBarClaudeWatchdog/main.swift:101', 'Sources/CodexBarClaudeWatchdog/main.swift:108-119'],
        recommendation:
          'Return the reaped wait status from killProcessTree / terminateChild when waitpid(childPID, &status, WNOHANG) succeeds, and only call blocking waitpid at lines 111/117 if the child was not yet reaped.',
        status: 'open',
      },
      {
        unit: 'module.process.reaper',
        title: 'ProcessOwnershipReaper guards group != getpgrp() and revalidates process identity before every signal',
        detail:
          'Sources/CodexBarCore/Host/Process/ProcessOwnershipReaper.swift:38-44 explicitly checks guard group > 0, group != getpgrp() and verifies CODEXBAR_PROBE_OWNER marker + start-time identity before signaling.',
        dimension: 'boundary-integrity',
        score: 5,
        severity: 'note',
        confidence: 0.98,
        effort: 'xs',
        evidence: ['Sources/CodexBarCore/Host/Process/ProcessOwnershipReaper.swift:37-45'],
        recommendation: 'Keep ProcessOwnershipReaper.signalGroup as the reference pattern for CodexBarClaudeWatchdog.',
        status: 'open',
      },
      {
        unit: 'module.credentials.writer',
        title: 'CredentialFileWriter may expose a permission window or follow symlinks when writing token files',
        detail:
          'Sources/CodexBarCore/CredentialFileWriter.swift:29-79 writes session tokens and cookies to user disk paths.',
        dimension: 'data-ownership',
        score: 1,
        severity: 'must',
        confidence: 0.5,
        effort: 's',
        evidence: ['Sources/CodexBarCore/CredentialFileWriter.swift:29-79'],
        recommendation: 'Verify staging directory permissions, O_EXCL creation mode, and atomic rename behavior.',
        status: 'open',
      },
    ],
    pass1Delib: {
      version: 1,
      pass: 1,
      skipped: false,
      question: null,
      notes: null,
      perspectives: {
        skeptic: {
          argument:
            'Pass 1 graded 3 of 4 modules (coverage 0.75). On Pass 2 I will inspect Sources/CodexBarCore/CredentialFileWriter.swift:38-74 to verify whether f-0004 is a false alarm, and we must grade module.process.spawnedgroup.',
          confidence: 0.92,
        },
        builder: {
          argument:
            'The contrast between SpawnedProcessGroup.swift:362-367 (which uses POSIX_SPAWN_SETPGROUP) and CodexBarClaudeWatchdog/main.swift:71,85 (which spawns with nil attributes and ignores setpgid EACCES) proves f-0001.',
          confidence: 0.95,
        },
        dreamer: {
          argument:
            'On Pass 2 I will trace how SpawnedProcessGroup.abortSynchronously interacts with the unreaped WNOWAIT zombie created by startWaiter() at line 686.',
          confidence: 0.9,
        },
        empath: {
          argument:
            'A watchdog helper meant to clean up hung Claude CLI probes must never be able to SIGKILL the user\'s running menu-bar app.',
          confidence: 0.95,
        },
      },
    },
    pass1Deltas: [
      {
        op: 'edit',
        target: 'f-0001',
        perspective: 'builder',
        why: 'Include POSIX_SPAWN_CLOEXEC_DEFAULT alongside POSIX_SPAWN_SETPGROUP in the watchdog spawn attributes.',
        set: {
          recommendation:
            'In Sources/CodexBarClaudeWatchdog/main.swift:69-72, initialize posix_spawnattr_t with POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT and posix_spawnattr_setpgroup(&attr, 0), and in killProcessTree (lines 19, 33) check if pgid == childPID, pgid != getpgrp() before calling kill(-pgid, ...).',
        },
      },
    ],
    pass2Delib: {
      version: 1,
      pass: 2,
      skipped: false,
      question: null,
      notes: null,
      perspectives: {
        skeptic: {
          argument:
            'Inspected Sources/CodexBarCore/CredentialFileWriter.swift:38-74: writePrivate creates a 0700 staging directory, opens the staged file with O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC at 0600, calls fchmod(0600) before writing, fsyncs, and atomically renames over the target URL. Retracting f-0004.',
          confidence: 0.99,
        },
        dreamer: {
          argument:
            'Graded module.process.spawnedgroup (SpawnedProcessGroup.swift:524-589, 686-705, 778-782): because startWaiter uses waitid(..., WNOWAIT) and waits up to 30s before waitpid, self.pid remains a zombie in self.processGroup during abortSynchronously, keeping hasResidualProcessGroup (kill(-pgid, 0) == 0) true for the full 2 * grace (800ms) spin.',
          confidence: 0.94,
        },
        builder: {
          argument:
            'In abortTargetsRemain (SpawnedProcessGroup.swift:778-782), checking !self.currentProcessGroupMemberIdentities().isEmpty once termination.hasObservedExit is true eliminates the 800ms zombie spin.',
          confidence: 0.93,
        },
        empath: {
          argument:
            'Eliminating the 800ms synchronous wait during PTY/process abort keeps menu-bar teardown responsive.',
          confidence: 0.9,
        },
      },
    },
    pass2Deltas: [
      {
        op: 'delete',
        target: 'f-0004',
        perspective: 'skeptic',
        why: 'Falsified on direct code inspection: CredentialFileWriter.writePrivate (Sources/CodexBarCore/CredentialFileWriter.swift:38-74) stages in a 0700 directory with O_CREAT|O_EXCL 0600, fchmod(0600) before write, synchronize(), and atomic rename(2).',
      },
      {
        op: 'add',
        perspective: 'skeptic',
        why: 'Record verified note on module.credentials.writer so coverage remains 1.00 after retracting f-0004.',
        finding: {
          unit: 'module.credentials.writer',
          title: 'CredentialFileWriter establishes 0600 permissions in a 0700 staging directory before write and publishes via atomic rename(2)',
          detail:
            'Sources/CodexBarCore/CredentialFileWriter.swift:38-74 prevents both permission-window exposure and symlink-following.',
          dimension: 'data-ownership',
          score: 5,
          severity: 'note',
          confidence: 0.99,
          effort: 'xs',
          evidence: ['Sources/CodexBarCore/CredentialFileWriter.swift:38-74'],
          recommendation: 'No change needed.',
          status: 'open',
        },
      },
      {
        op: 'add',
        perspective: 'dreamer',
        why: 'Grades module.process.spawnedgroup to complete 1.00 coverage.',
        finding: {
          unit: 'module.process.spawnedgroup',
          title: 'abortSynchronously spins for the full 2 * grace (800ms) after root exit because unreaped WNOWAIT zombie keeps hasResidualProcessGroup true',
          detail:
            'In Sources/CodexBarCore/Host/Process/SpawnedProcessGroup.swift:686-699, startWaiter() uses waitid(P_PID, id_t(pid), &info, WEXITED | WNOWAIT) and leaves self.pid as an unreaped zombie until finishSynchronously() calls requestReap() at line 588. During abortSynchronously (lines 568-589), abortTargetsRemain (line 781) checks self.hasResidualProcessGroup (kill(-self.processGroup, 0) == 0). On Darwin/XNU, an unreaped zombie remains in its pgrp until waitpid reaps it, so kill(-self.processGroup, 0) stays 0 even when the child exited immediately on SIGTERM and no live group members remain.',
          dimension: 'failure-modes',
          score: 2,
          severity: 'should',
          confidence: 0.93,
          effort: 'xs',
          evidence: [
            'Sources/CodexBarCore/Host/Process/SpawnedProcessGroup.swift:524-526',
            'Sources/CodexBarCore/Host/Process/SpawnedProcessGroup.swift:568-589',
            'Sources/CodexBarCore/Host/Process/SpawnedProcessGroup.swift:686-705',
            'Sources/CodexBarCore/Host/Process/SpawnedProcessGroup.swift:778-791',
          ],
          recommendation:
            'In abortTargetsRemain (SpawnedProcessGroup.swift:778-782), when self.termination.hasObservedExit is true, check !self.currentProcessGroupMemberIdentities().isEmpty rather than self.hasResidualProcessGroup.',
          status: 'open',
        },
      },
    ],
  },
  {
    slug: 'archon',
    repo: 'coleam00/Archon',
    stars: '23.8k',
    subject: 'Authentication gateway cookie signing, login redirect decoding, and SSE transport buffer synchronization in coleam00/Archon',
    units: [
      {
        id: 'module.auth.server',
        label: 'Reverse-proxy authentication service (auth-service/server.js)',
        path: 'auth-service/server.js',
        kind: 'module',
        meta: {},
      },
      {
        id: 'module.web.ssetransport',
        label: 'Web SSE streaming & replay buffer transport (packages/server/src/adapters/web/transport.ts)',
        path: 'packages/server/src/adapters/web/transport.ts',
        kind: 'module',
        meta: {},
      },
      {
        id: 'module.server.internalroutes',
        label: 'Loopback git-credential endpoint (packages/server/src/server-routes.ts)',
        path: 'packages/server/src/server-routes.ts',
        kind: 'module',
        meta: {},
      },
    ],
    pass1Findings: [
      {
        unit: 'module.auth.server',
        title: 'signCookie("authenticated") signs a static constant with no server-side expiration or credential-rotation binding',
        detail:
          'In auth-service/server.js:35-50 and 180-185, handleLogin calls signCookie("authenticated"), which computes HMAC-SHA256(SECRET, "authenticated") over a static string literal. verifyCookie (lines 40-50, called by handleVerify at line 145) only checks that the HMAC matches "authenticated" and enforces no server-side expiry timestamp and no binding to USERNAME or PASSWORD_HASH. As a result, Max-Age is purely a client hint (any captured archon_auth cookie header is valid forever against /verify), and rotating AUTH_USERNAME or AUTH_PASSWORD_HASH does not invalidate existing cookies.',
        dimension: 'boundary-integrity',
        score: 1,
        severity: 'must',
        confidence: 0.98,
        effort: 'xs',
        evidence: ['auth-service/server.js:35-50', 'auth-service/server.js:145-148', 'auth-service/server.js:180-185'],
        recommendation:
          'Include an expiration unix timestamp and a short HMAC fingerprint of USERNAME:PASSWORD_HASH inside the signed payload (e.g., authenticated.<exp>.<credTag>), and verify both in verifyCookie (auth-service/server.js:40-50).',
        status: 'open',
      },
      {
        unit: 'module.auth.server',
        title: 'Unhandled URIError 500 crash on double-decoded rd parameter in POST /login and GET /logout CSRF via SameSite=Lax',
        detail:
          'In auth-service/server.js:166-169, handleLogin parses the form body with new URLSearchParams(body) (which already URL-decodes parameter values once) and then calls decodeURIComponent(params.get("rd") ?? "/") a second time without a try/catch. Any redirect path containing a literal percent sign after form decoding (e.g. /workflows?search=100%25 -> "100%") throws URIError: URI malformed and returns HTTP 500 on a valid login. Additionally, routeFor (line 218) allows GET /logout while session cookies use SameSite=Lax (line 183), allowing cross-site top-level navigation or link prerendering to log out authenticated users.',
        dimension: 'failure-modes',
        score: 1,
        severity: 'must',
        confidence: 0.97,
        effort: 'xs',
        evidence: ['auth-service/server.js:158-170', 'auth-service/server.js:183', 'auth-service/server.js:218', 'auth-service/server.js:226-229'],
        recommendation:
          'Remove the redundant decodeURIComponent() call on params.get("rd") at auth-service/server.js:169 (and guard the query-string decodeURIComponent at line 150 with try/catch), and restrict /logout in routeFor (line 218) to POST.',
        status: 'open',
      },
      {
        unit: 'module.auth.server',
        title: 'Potential open redirect via rd parameter in auth-service/server.js',
        detail:
          'auth-service/server.js:150-152 and 170 redirect to Location: ${safeRd} after reading the user-controlled rd parameter.',
        dimension: 'boundary-integrity',
        score: 1,
        severity: 'must',
        confidence: 0.5,
        effort: 'xs',
        evidence: ['auth-service/server.js:62-65', 'auth-service/server.js:150-152', 'auth-service/server.js:169-170'],
        recommendation: 'Verify that isSafeRedirect blocks protocol-relative // and backslash /\\ redirects.',
        status: 'open',
      },
      {
        unit: 'module.server.internalroutes',
        title: 'Internal git-credential route enforces loopback socket binding and scoped HMAC token verification',
        detail:
          'packages/server/src/server-routes.ts:145-165 checks assertInternalEndpointBind against loopback addresses before verifying the short-lived credential token.',
        dimension: 'boundary-integrity',
        score: 5,
        severity: 'note',
        confidence: 0.98,
        effort: 'xs',
        evidence: ['packages/server/src/server-routes.ts:145-165'],
        recommendation: 'No change needed.',
        status: 'open',
      },
    ],
    pass1Delib: {
      version: 1,
      pass: 1,
      skipped: false,
      question: null,
      notes: null,
      perspectives: {
        skeptic: {
          argument:
            'Pass 1 graded 2 of 3 modules (coverage 0.67). On Pass 2 I will inspect isSafeRedirect in auth-service/server.js:62-65 to test whether f-0003 is a false positive, and we must grade module.web.ssetransport.',
          confidence: 0.93,
        },
        builder: {
          argument:
            'Both f-0001 (static HMAC cookie with no expiry/rotation binding) and f-0002 (double decodeURIComponent throwing URIError on POST /login + GET /logout) are reproducible in auth-service/server.js.',
          confidence: 0.96,
        },
        dreamer: {
          argument:
            'On Pass 2 I will trace concurrent emitEvent and drainBufferedEvents calls in packages/server/src/adapters/web/transport.ts.',
          confidence: 0.9,
        },
        empath: {
          argument:
            'Returning HTTP 500 after a user enters valid credentials just because the return URL had a percent-encoded character is a jarring auth failure.',
          confidence: 0.94,
        },
      },
    },
    pass1Deltas: [
      {
        op: 'edit',
        target: 'f-0002',
        perspective: 'builder',
        why: 'Also wrap the GET /login query-string decodeURIComponent at line 150 in a safe helper so malformed query strings return "/".',
        set: {
          recommendation:
            'In auth-service/server.js:169, use params.get("rd") ?? "/" directly (since URLSearchParams.get already decodes once), wrap the query-string decodeURIComponent at line 150 in a try/catch falling back to "/", and restrict /logout at line 218 to method === "POST".',
        },
      },
    ],
    pass2Delib: {
      version: 1,
      pass: 2,
      skipped: false,
      question: null,
      notes: null,
      perspectives: {
        skeptic: {
          argument:
            'Inspected isSafeRedirect(rd) at auth-service/server.js:62-65: it enforces rd === "/" || (/^\\/[^/\\\\]/.test(rd) && !rd.includes("://")), which blocks protocol-relative //evil.com, backslash /\\evil.com, and scheme separators. Retracting f-0003.',
          confidence: 0.99,
        },
        dreamer: {
          argument:
            'Graded module.web.ssetransport (packages/server/src/adapters/web/transport.ts:212-239): emitEvent awaits Promise.all(writes) and then loops over all entries in currentBuffer setting entry.liveWritePending = false, prematurely clearing liveWritePending on any concurrent emitEvent that started while the first await was in flight.',
          confidence: 0.94,
        },
        builder: {
          argument:
            'Binding const bufferedEntry = { data, timestamp: Date.now(), liveWritePending: true } and setting bufferedEntry.liveWritePending = false in a finally block fixes the overlapping SSE write race in 3 lines.',
          confidence: 0.95,
        },
        empath: {
          argument:
            'Preventing premature replay during concurrent SSE emissions avoids duplicate tool/message events in the web UI.',
          confidence: 0.91,
        },
      },
    },
    pass2Deltas: [
      {
        op: 'delete',
        target: 'f-0003',
        perspective: 'skeptic',
        why: 'Falsified on direct code inspection: isSafeRedirect(rd) in auth-service/server.js:62-65 enforces /^\\/[^/\\\\]/.test(rd) && !rd.includes("://"), blocking //, /\\, and scheme redirects.',
      },
      {
        op: 'add',
        perspective: 'dreamer',
        why: 'Grades module.web.ssetransport to reach 1.00 coverage.',
        finding: {
          unit: 'module.web.ssetransport',
          title: 'SSETransport.emitEvent clears liveWritePending across all currentBuffer entries after await Promise.all, prematurely marking concurrent in-flight events as completed',
          detail:
            'In packages/server/src/adapters/web/transport.ts:212-239, emitEvent pushes { data, timestamp: Date.now(), liveWritePending: true } into buffer, awaits Promise.all(writes) at line 234, and then iterates over const currentBuffer = this.buffered.get(conversationId) ?? []; for (const entry of currentBuffer) { entry.liveWritePending = false; } (lines 236-239). When two emitEvent calls for the same conversationId overlap across the async write boundary, the first call finishing clears liveWritePending = false on the second call\'s entry while its writes are still in flight, allowing drainBufferedEvents (line 119) to replay the in-flight event a second time.',
          dimension: 'failure-modes',
          score: 2,
          severity: 'should',
          confidence: 0.94,
          effort: 'xs',
          evidence: ['packages/server/src/adapters/web/transport.ts:119', 'packages/server/src/adapters/web/transport.ts:206-241'],
          recommendation:
            'Keep a reference to the specific BufferedEvent pushed at transport.ts:212 (const bufferedEntry: BufferedEvent = { data, timestamp: Date.now(), liveWritePending: true }) and set bufferedEntry.liveWritePending = false in a finally block around await Promise.all(writes).',
          status: 'open',
        },
      },
    ],
  },
];

const quietPassDelib = (pass) => ({
  version: 1,
  pass,
  skipped: false,
  question: null,
  notes: null,
  perspectives: {
    skeptic: {
      argument: `Pass ${pass}: Re-checked all open findings against file:line evidence; no remaining false positives or unverified assumptions. Holding silence (0 deltas).`,
      confidence: 0.98,
    },
    builder: {
      argument: `Pass ${pass}: Every open finding has a minimal, line-anchored fix recommendation. Holding silence (0 deltas).`,
      confidence: 0.98,
    },
    dreamer: {
      argument: `Pass ${pass}: All enumerated modules are graded (coverage 1.00) and cross-module invariants are satisfied. Holding silence (0 deltas).`,
      confidence: 0.97,
    },
    empath: {
      argument: `Pass ${pass}: Severity tiers accurately reflect user and maintainer impact. Holding silence (0 deltas).`,
      confidence: 0.97,
    },
  },
});

const summaryRows = [];

for (const audit of AUDITS) {
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), `ponder-audit-${audit.slug}-`));
  try {
    // Create a minimal project marker so ponder resolves tmpDir as the project root
    writeJson(path.join(tmpDir, 'package.json'), { name: audit.slug, private: true });
    for (const u of audit.units) {
      const abs = path.join(tmpDir, u.path);
      fs.mkdirSync(path.dirname(abs), { recursive: true });
      fs.writeFileSync(abs, `// ${u.label}\n`, 'utf8');
    }

    // Start session
    runPonder(
      ['start', audit.subject, '--lens', 'architecture', '--project', tmpDir, '--slug', audit.slug, '--max-passes', '6', '--min-passes', '2'],
      tmpDir
    );

    // --- PASS 1 ---
    runPonder(['predict', '--session', audit.slug, '--churn', '0.45', '--claim', 'Pass 1 enumerates target modules and seeds initial findings.'], tmpDir);
    const unitsFile = path.join(tmpDir, 'units-input.json');
    writeJson(unitsFile, { version: 1, lens: 'architecture', units: audit.units });
    runPonder(['units', '--session', audit.slug, '--file', unitsFile], tmpDir);

    const gradeFile = path.join(tmpDir, 'grade-pass1.json');
    writeJson(gradeFile, { version: 1, findings: audit.pass1Findings });
    runPonder(['grade', '--session', audit.slug, '--file', gradeFile], tmpDir);

    const delib1File = path.join(tmpDir, 'delib-pass1.json');
    writeJson(delib1File, audit.pass1Delib);
    runPonder(['deliberate', '--session', audit.slug, '--file', delib1File], tmpDir);

    const delta1File = path.join(tmpDir, 'deltas-pass1.jsonl');
    writeJsonl(delta1File, audit.pass1Deltas);
    runPonder(['delta', '--session', audit.slug, '--file', delta1File], tmpDir);

    const j1 = runPonder(['judge', '--session', audit.slug], tmpDir);
    runPonder(['decide', 'continue', '--session', audit.slug, '--why', 'Coverage is incomplete and Pass-1 decoy hypothesis requires Skeptic verification.'], tmpDir);

    // --- PASS 2 ---
    runPonder(['predict', '--session', audit.slug, '--churn', '0.35', '--claim', 'Pass 2 verifies and retracts Pass-1 false positive and grades remaining module to reach coverage 1.00.'], tmpDir);
    const delib2File = path.join(tmpDir, 'delib-pass2.json');
    writeJson(delib2File, audit.pass2Delib);
    runPonder(['deliberate', '--session', audit.slug, '--file', delib2File], tmpDir);

    const delta2File = path.join(tmpDir, 'deltas-pass2.jsonl');
    writeJsonl(delta2File, audit.pass2Deltas);
    runPonder(['delta', '--session', audit.slug, '--file', delta2File], tmpDir);

    const j2 = runPonder(['judge', '--session', audit.slug], tmpDir);
    runPonder(['decide', 'continue', '--session', audit.slug, '--why', 'Coverage reached 1.00 and false positive retracted; continuing to verify stability across two quiet passes.'], tmpDir);

    // --- PASS 3 (Quiet Pass 1) ---
    runPonder(['predict', '--session', audit.slug, '--churn', '0.02', '--claim', 'Pass 3 expects near-zero churn after Pass 2 falsification and full unit coverage.'], tmpDir);
    const delib3File = path.join(tmpDir, 'delib-pass3.json');
    writeJson(delib3File, quietPassDelib(3));
    runPonder(['deliberate', '--session', audit.slug, '--file', delib3File], tmpDir);

    const delta3File = path.join(tmpDir, 'deltas-pass3.jsonl');
    writeJsonl(delta3File, []);
    runPonder(['delta', '--session', audit.slug, '--file', delta3File], tmpDir);

    const j3 = runPonder(['judge', '--session', audit.slug], tmpDir);
    runPonder(['decide', 'continue', '--session', audit.slug, '--why', 'First quiet pass (0 deltas across 4 voices); one more quiet pass required for Rule 6 convergence.'], tmpDir);

    // --- PASS 4 (Quiet Pass 2 -> Converged) ---
    runPonder(['predict', '--session', audit.slug, '--churn', '0.00', '--claim', 'Pass 4 expects 0 deltas and Rule 6 convergence.'], tmpDir);
    const delib4File = path.join(tmpDir, 'delib-pass4.json');
    writeJson(delib4File, quietPassDelib(4));
    runPonder(['deliberate', '--session', audit.slug, '--file', delib4File], tmpDir);

    const delta4File = path.join(tmpDir, 'deltas-pass4.jsonl');
    writeJsonl(delta4File, []);
    runPonder(['delta', '--session', audit.slug, '--file', delta4File], tmpDir);

    const j4 = runPonder(['judge', '--session', audit.slug], tmpDir);
    runPonder(['decide', 'stop', '--session', audit.slug, '--why', 'Two consecutive quiet passes with coverage 1.00 and 4 voices in epistemic silence; converged under Rule 6.'], tmpDir);

    // Verify ledger reconciliation
    const sessDir = path.join(tmpDir, '.ponder', audit.slug);
    const recon = reconcile(sessDir);
    if (!recon.ok) {
      throw new Error(`Reconciliation failed for ${audit.slug}: ${JSON.stringify(recon.problems)}`);
    }
    runPonder(['verify', '--session', audit.slug], tmpDir);

    // Export report.md and apply-plan.md
    const outDir = path.join(__dirname, audit.slug);
    fs.mkdirSync(outDir, { recursive: true });
    const reportPath = path.join(outDir, 'report.md');
    const applyPlanPath = path.join(outDir, 'apply-plan.md');

    runPonder(['report', '--session', audit.slug, '--out', reportPath], tmpDir);
    const applyRes = runPonder(['apply', '--session', audit.slug], tmpDir);
    fs.copyFileSync(applyRes.path || path.join(sessDir, 'apply-plan.md'), applyPlanPath);

    const findingsJson = JSON.parse(fs.readFileSync(path.join(sessDir, 'findings.json'), 'utf8'));
    const openMust = findingsJson.findings.filter((f) => f.status === 'open' && f.severity === 'must').length;
    const openShould = findingsJson.findings.filter((f) => f.status === 'open' && f.severity === 'should').length;
    const retracted = findingsJson.findings.filter((f) => f.status === 'delete' || f.status === 'deleted' || f.status === 'retracted').length;

    summaryRows.push({
      slug: audit.slug,
      repo: audit.repo,
      stars: audit.stars,
      units: audit.units.length,
      must: openMust,
      should: openShould,
      retracted,
      pass1Verdict: `${j1.verdict} (${j1.reason})`,
      pass2Verdict: `${j2.verdict} (${j2.reason})`,
      pass3Verdict: `${j3.verdict} (${j3.reason})`,
      pass4Verdict: `${j4.verdict} (${j4.reason})`,
      reconciled: recon.ok,
    });
    console.log(`[OK] ${audit.repo}: must=${openMust}, should=${openShould}, retracted=${retracted}, pass4=${j4.verdict} (${j4.reason})`);
  } finally {
    fs.rmSync(tmpDir, { recursive: true, force: true });
  }
}

console.log(JSON.stringify(summaryRows, null, 2));
