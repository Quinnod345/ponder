# Ponder - Target sync, symlink preservation, and backup lifecycle in EveryInc/compound-engineering-plugin

`compound-engineering-plugin` · lens **architecture** · status **converged** · 4 passes of a 6-pass budget · generated 2026-10-28T15:12:49.108Z

| | |
|---|---|
| Subject | Target sync, symlink preservation, and backup lifecycle in EveryInc/compound-engineering-plugin |
| Lens | architecture - unit = module, 11 dimensions |
| Project | `/var/folders/29/k94h5cq10ls0gm_1v1jlb1j00000gn/T/ponder-audit-compound-engineering-plugin-ZMJLPr` |
| Passes | 4 run · min 2 · max 6 |
| Coverage | 1.00 - 5 of 5 modules graded |
| Findings | 6 total · 5 open · 0 resolved · 0 deferred · 1 retracted |
| Final verdict | stop (converged) → decided **stop** |
| OCA | off |

## Convergence

| Pass | Coverage | Novelty | Churn | Thrash | Surprise | Stall | Conf-floor | Voices | Advice | Decision |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|---|
| 1 | 0.80 | - | - | - | - | 0 | 0.00 | 4 | blocked (coverage) | continue |
| 2 | 1.00 | 0.40 | 0.80 | 0.00 | 0.45 | 0 | 0.00 | 4 | continue (default) | continue |
| 3 | 1.00 | 0.00 | 0.00 | 0.00 | 0.02 | 1 | 0.00 | 4 | continue (default) | continue |
| 4 | 1.00 | 0.00 | 0.00 | 0.00 | 0.00 | 2 | 0.00 | 4 | stop (converged) | stop |

`-` on pass 1 is not a zero. Novelty, churn, thrash and surprise measure change against a previous pass, and pass 1 has none.

## Overrides

None. Every decision followed the engine's advice.

## Prediction vs reality

| Pass | Predicted churn | Actual churn | Surprise | Claim |
|---:|---:|---:|---:|---|
| 1 | 0.45 | - | - | Pass 1 enumerates target modules and seeds initial findings. |
| 2 | 0.35 | 0.80 | 0.45 | Pass 2 verifies and retracts Pass-1 false positive and grades remaining module to reach coverage 1.00. |
| 3 | 0.02 | 0.00 | 0.02 | Pass 3 expects near-zero churn after Pass 2 falsification and full unit coverage. |
| 4 | 0.00 | 0.00 | 0.00 | Pass 4 expects 0 deltas and Rule 6 convergence. |

## Coverage

5 modules enumerated, 5 graded.

## Findings

### Codex target writer & symlink/manifest cleanup (src/targets/codex.ts) `module.targets.codex`
`src/targets/codex.ts`

- **f-0001** · must · score 1 · confidence 0.96 · effort s · data-ownership - Codex prompt writer bypasses symlink and ownership checks, clobbering user symlinks and deleting them on cleanup
  In src/targets/codex.ts:57-61, prompts are written directly via writeText(targetPath, content) (fs.writeFile) without checking if targetPath is a user symlink or unmanaged file, and are unconditionally recorded in writeInstallManifest (codex.ts:177). By contrast, skills and agents call cleanupCurrentManagedSkillDir and cleanupCurrentManagedAgentFile (codex.ts:364-403) to preserve user symlinks and unmanaged files. In addition, cleanupRemovedPrompts (codex.ts:326-338) omits if (await isPreservedSymlink(entryPath)) continue.
  Evidence: `src/targets/codex.ts:57-61`, `src/targets/codex.ts:177`, `src/targets/codex.ts:326-338`, `src/targets/codex.ts:364-403`
  Do: In src/targets/codex.ts:57-61, check await cleanupCurrentManagedPromptFile(targetPath, prompt.name, ownedPrompts, backupDir) before writeText, only include written prompt names in writeInstallManifest (line 177), and add if (await isPreservedSymlink(entryPath)) continue to cleanupRemovedPrompts (line 331).
  _Revised: p2 edit recommendation_

### OpenCode config & command writer (src/targets/opencode.ts) `module.targets.opencode`
`src/targets/opencode.ts`

- **f-0003** · must · score 2 · confidence 0.95 · effort xs · failure-modes - Idempotent OpenCode installs accumulate unbounded .bak.<timestamp> files inside .opencode/commands/ and opencode.json
  In src/targets/opencode.ts:123 and 169-174, writeOpenCode calls backupFile(paths.configPath) and backupFile(commandPath) unconditionally before writing without comparing incoming content against existing file content on disk (unlike src/targets/codex.ts:218-227). Every idempotent install or sync creates a new <command>.md.bak.<timestamp> inside the live .opencode/commands/ directory.
  Evidence: `src/targets/opencode.ts:123`, `src/targets/opencode.ts:169-174`, `src/targets/codex.ts:218-227`
  Do: In src/targets/opencode.ts:123 and 169-174, read existingContent via fs.readFile(path, "utf8").catch(() => null) and skip backupFile + writeText when existingContent === content (mirroring src/targets/codex.ts:218-227).
  _Revised: p1 edit recommendation_

### Pi target writer, extension bundler & legacy artifact cleanup (src/targets/pi.ts) `module.targets.pi`
`src/targets/pi.ts`

- **f-0002** · must · score 1 · confidence 0.96 · effort s · data-ownership - Pi prompt and extension writers clobber user symlinks and cleanupKnownLegacyPiArtifacts ignores prompt ownership
  In src/targets/pi.ts:95-99 and 150-154, both prompts and extensions call writeText directly without checking for preserved symlinks or unmanaged files, while cleanupRemovedPrompts (pi.ts:407-419) and cleanupRemovedExtensions (pi.ts:421-433) omit isPreservedSymlink checks. Furthermore, cleanupKnownLegacyPiArtifacts (pi.ts:532-535) and cleanupPi (src/commands/cleanup.ts:411-413) move legacy prompts without checking ownedPrompts (unlike codex.ts:428-430).
  Evidence: `src/targets/pi.ts:95-99`, `src/targets/pi.ts:150-154`, `src/targets/pi.ts:407-433`, `src/targets/pi.ts:532-535`, `src/commands/cleanup.ts:411-413`
  Do: Apply managed-file ownership and symlink checks before writing Pi prompts/extensions, add isPreservedSymlink guards to cleanupRemovedPrompts/cleanupRemovedExtensions, and check ownedPrompts in cleanupKnownLegacyPiArtifacts and cleanupPi.

### Install CLI command & GitHub repo cloner (src/commands/install.ts) `module.commands.install`
`src/commands/install.ts`

- **f-0006** · should · score 2 · confidence 0.96 · effort xs · contract-stability - CLI --help advertises --permissions from-command (singular) while validation requires from-commands (plural), and cloneGitHubRepo omits "--"
  src/commands/install.ts:59 documents "--permissions <mode> ... (none \| broad \| from-command)", whereas permissionModes at line 15 is ["none", "broad", "from-commands"], causing --permissions from-command to throw "Unknown permissions mode: from-command" at line 87. Separately, cloneGitHubRepo (lines 330-334) constructs git clone args without "--" before [source, destination].
  Evidence: `src/commands/install.ts:15`, `src/commands/install.ts:59`, `src/commands/install.ts:86-90`, `src/commands/install.ts:330-334`
  Do: Update src/commands/install.ts:59 help text to "from-commands" (or accept "from-command" as an alias in resolvePermissionsMode at line 86) and insert "--" before source, destination in cloneGitHubRepo at line 334.

### Claude plugin manifest parser & path resolver (src/parsers/claude.ts) `module.parsers.claude`
`src/parsers/claude.ts`

- **f-0005** · note · score 5 · confidence 0.99 · effort xs · boundary-integrity - resolveWithinRoot enforces strict pluginRoot path containment for all manifest-supplied paths
  src/parsers/claude.ts:263-270 validates all manifest paths against resolvedRoot + path.sep and throws before any filesystem read.
  Evidence: `src/parsers/claude.ts:237-270`
  Do: No change needed; keep resolveWithinRoot as the single path resolution gate.

## Retracted

Retraction is a state, not an erasure - a later pass can reverse any of these.

- `f-0004` (module.parsers.claude) - Custom manifest.hooks and manifest.skills paths in plugin.json may allow path traversal outside pluginRoot · retracted in pass 2 by the skeptic: Falsified on direct code inspection: resolveWithinRoot in src/parsers/claude.ts:263-270 enforces resolvedRoot + path.sep containment on every manifest path in resolveComponentDirs (lines 239, 245) and resolveConfigPaths (lines 254, 259).

## Deliberation

### Pass 1

- **skeptic** (confidence 0.92) - Pass 1 graded 4 of 5 modules (coverage 0.80). Before we report f-0004 (manifest path traversal in src/parsers/claude.ts), I need to inspect resolveWithinRoot at lines 263-270 on Pass 2.
- **builder** (confidence 0.90) - The symlink clobbering on prompts/extensions (f-0001, f-0002) and unbounded .bak.<timestamp> creation in .opencode/commands/ (f-0003) are confirmed by direct comparison with codex.ts:218-227 and 364-403. Still need to grade module.commands.install.
- **dreamer** (confidence 0.90) - All managed artifact types (skills, agents, prompts, extensions) across Codex, Pi, and OpenCode should obey the same ownership invariant: never write through a user symlink and never back up an unchanged file.
- **empath** (confidence 0.95) - Users who symlink custom prompts or Pi extensions into ~/.codex/prompts or .pi/extensions lose their local work silently when writeText writes through the symlink.

Resolution: 1 edit (plus 4 findings seeded by `ponder grade` before the argument).

### Pass 2

- **skeptic** (confidence 0.99) - Opened src/parsers/claude.ts:263-270: resolveWithinRoot resolves every manifest path via path.resolve(root, normalizedPath) and throws whenever resolvedPath !== resolvedRoot && !resolvedPath.startsWith(resolvedRoot + path.sep). Retracting f-0004 as a false positive and leaving a clean note on module.parsers.claude.
- **builder** (confidence 0.96) - Sharpened f-0001 and f-0002 with the exact helper signatures and manifest filtering so writtenPromptNames and writtenExtensionNames only record plugin-written files.
- **dreamer** (confidence 0.95) - Graded module.commands.install (src/commands/install.ts): found that --help advertises --permissions from-command (singular) at line 59 while permissionModes at line 15 requires from-commands (plural), and cloneGitHubRepo (lines 330-334) omits "--" before positional git clone args.
- **empath** (confidence 0.92) - Copy-pasting --permissions from-command from --help currently fails with Unknown permissions mode: from-command.

Resolution: 2 add, 1 edit, 1 delete.

### Pass 3

- **skeptic** (confidence 0.98) - Pass 3: Re-checked all open findings against file:line evidence; no remaining false positives or unverified assumptions. Holding silence (0 deltas).
- **builder** (confidence 0.98) - Pass 3: Every open finding has a minimal, line-anchored fix recommendation. Holding silence (0 deltas).
- **dreamer** (confidence 0.97) - Pass 3: All enumerated modules are graded (coverage 1.00) and cross-module invariants are satisfied. Holding silence (0 deltas).
- **empath** (confidence 0.97) - Pass 3: Severity tiers accurately reflect user and maintainer impact. Holding silence (0 deltas).

Resolution: no deltas.

### Pass 4

- **skeptic** (confidence 0.98) - Pass 4: Re-checked all open findings against file:line evidence; no remaining false positives or unverified assumptions. Holding silence (0 deltas).
- **builder** (confidence 0.98) - Pass 4: Every open finding has a minimal, line-anchored fix recommendation. Holding silence (0 deltas).
- **dreamer** (confidence 0.97) - Pass 4: All enumerated modules are graded (coverage 1.00) and cross-module invariants are satisfied. Holding silence (0 deltas).
- **empath** (confidence 0.97) - Pass 4: Severity tiers accurately reflect user and maintainer impact. Holding silence (0 deltas).

Resolution: no deltas.

## Ledger

9 deltas across 4 passes: 6 add, 2 edit, 1 delete.

| Pass | Deltas | Perspectives |
|---:|---|---|
| 1 | 4 add, 1 edit | builder |
| 2 | 2 add, 1 edit, 1 delete | builder, dreamer, skeptic |
| 3 | no deltas | - |
| 4 | no deltas | - |

The full append-only record is `ledger.jsonl`.

---

*Generated by [Ponder](https://github.com/Quinnod345/ponder) - AI that knows when to speak, and when to shut up.*
