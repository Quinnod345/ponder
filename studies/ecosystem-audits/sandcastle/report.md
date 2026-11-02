# Ponder - Worktree control file overlay coverage, NTFS ADS alternate streams, and Seatbelt profile scoping in mattpocock/sandcastle

`sandcastle` · lens **architecture** · status **converged** · 4 passes of a 6-pass budget · generated 2026-11-02T21:29:31.050Z

| | |
|---|---|
| Subject | Worktree control file overlay coverage, NTFS ADS alternate streams, and Seatbelt profile scoping in mattpocock/sandcastle |
| Lens | architecture - unit = module, 11 dimensions |
| Project | `/var/folders/29/k94h5cq10ls0gm_1v1jlb1j00000gn/T/ponder-audit-sandcastle-Q6VgRj` |
| Passes | 4 run · min 2 · max 6 |
| Coverage | 1.00 - 3 of 3 modules graded |
| Findings | 5 total · 4 open · 0 resolved · 0 deferred · 1 retracted |
| Final verdict | stop (converged) → decided **stop** |
| OCA | off |

## Convergence

| Pass | Coverage | Novelty | Churn | Thrash | Surprise | Stall | Conf-floor | Voices | Advice | Decision |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|---|
| 1 | 0.67 | - | - | - | - | 0 | 0.00 | 4 | blocked (coverage) | continue |
| 2 | 1.00 | 0.25 | 0.50 | 0.00 | 0.15 | 0 | 0.00 | 4 | continue (default) | continue |
| 3 | 1.00 | 0.00 | 0.00 | 0.00 | 0.00 | 1 | 0.00 | 4 | continue (default) | continue |
| 4 | 1.00 | 0.00 | 0.00 | 0.00 | 0.00 | 2 | 0.00 | 4 | stop (converged) | stop |

`-` on pass 1 is not a zero. Novelty, churn, thrash and surprise measure change against a previous pass, and pass 1 has none.

## Overrides

None. Every decision followed the engine's advice.

## Prediction vs reality

| Pass | Predicted churn | Actual churn | Surprise | Claim |
|---:|---:|---:|---:|---|
| 1 | 0.45 | - | - | Pass 1 enumerates target modules and seeds initial findings. |
| 2 | 0.35 | 0.50 | 0.15 | Pass 2 falsifies NTFS ADS alarm and completes unit coverage. |
| 3 | 0.00 | 0.00 | 0.00 | Pass 3 confirms silence with zero deltas. |
| 4 | 0.00 | 0.00 | 0.00 | Pass 4 confirms convergence. |

## Coverage

3 modules enumerated, 3 graded.

## Findings

### Git control file overlay protection and anchor binding (src/protectGitMounts.ts) `module.protect.git`
`src/protectGitMounts.ts`

- **f-0001** · must · score 1 · confidence 0.98 · effort xs · boundary-integrity - linkedWorktreeControlPaths leaves config.worktree and gitdir in linked worktree admin dir writable by sandbox
  In src/protectGitMounts.ts:90-112, linkedWorktreeControlPaths resolves commondirFile = join(adminDir.value, "commondir") and commonDirControlPaths(commonDir.value). It does not include join(adminDir.value, "config.worktree") or join(adminDir.value, "gitdir"). When extensions.worktreeConfig is enabled, git reads worktree-specific configuration from .git/worktrees/<name>/config.worktree, allowing a sandboxed process to configure core.fsmonitor, diff.<driver>.command, or filter drivers executed on the host by git.
  Evidence: `src/protectGitMounts.ts:90-112`, `src/protectGitMounts.ts:199-242`
  Do: In linkedWorktreeControlPaths, include join(adminDir.value, "config.worktree") and join(adminDir.value, "gitdir") in the control paths array; this automatically feeds both protectGitControlFiles and buildSeatbeltPolicy.
  _Revised: p1 edit recommendation_

- **f-0002** · should · score 2 · confidence 0.94 · effort xs · boundary-integrity - relativeWithin tests rel.startsWith("..") instead of exact parent escape boundary
  In src/protectGitMounts.ts:71-79, relativeWithin rejects paths when rel.startsWith(".."). Unlike syncOutPaths.ts:116 which tests rel === ".." \|\| rel.startsWith(".." + sep) \|\| isAbsolute(rel), this rejects legitimate sibling paths starting with double dots.
  Evidence: `src/protectGitMounts.ts:71-79`, `src/syncOutPaths.ts:116`
  Do: Align relativeWithin with isOutside: return rel === ".." \|\| rel.startsWith(".." + sep) \|\| isAbsolute(rel) ? Option.none() : Option.some(rel).

### macOS Seatbelt (SBPL) profile builder and parameter generator (src/seatbeltProfile.ts) `module.seatbelt.profile`
`src/seatbeltProfile.ts`

- **f-0005** · note · score 5 · confidence 0.98 · effort xs · boundary-integrity - buildSeatbeltPolicy denies container engine sockets and directories after writable roots
  In src/seatbeltProfile.ts:255-275, engineFilters and XPC service denies are ordered after allowSubpaths to guarantee container sockets remain unreachable even when inside home.
  Evidence: `src/seatbeltProfile.ts:255-275`
  Do: Maintain rule ordering.

### Sync-out path canonicalization, NTFS ADS and symlink resolution (src/syncOutPaths.ts) `module.sync.paths`
`src/syncOutPaths.ts`

- **f-0003** · note · score 5 · confidence 0.97 · effort xs · boundary-integrity - resolveHostDestination validates deepest existing symlink on host to prevent path traversal breakouts
  In src/syncOutPaths.ts:101-157, resolveHostDestination uses deepestExisting to find the deepest existing ancestor under realRoot and asserts checkResolvesInside using realPathOf before allowing writes.
  Evidence: `src/syncOutPaths.ts:101-157`
  Do: Keep current validation logic intact.

## Retracted

Retraction is a state, not an erasure - a later pass can reverse any of these.

- `f-0004` (module.sync.paths) - Decoy: splitSegments and isGitSegment might miss NTFS alternate data stream syntax .git:stream on Windows · retracted in pass 2 by the skeptic: Falsified on inspection: checkRelativePath and realpath reject Windows ADS streams before sync-out.

## Deliberation

### Pass 1

- **skeptic** (confidence 0.92) - Pass 1 evaluated 2 of 3 modules (coverage 0.67). On Pass 2 I will check whether NTFS ADS is already rejected by checkRelativePath, and we must grade module.seatbelt.profile.
- **builder** (confidence 0.97) - linkedWorktreeControlPaths omitting config.worktree is a concrete gap: git worktrees with extensions.worktreeConfig read that file directly.
- **dreamer** (confidence 0.93) - We should evaluate seatbeltProfile.ts container socket rules to verify full defense-in-depth across platforms.
- **empath** (confidence 0.95) - Developers rely on Sandcastle to safely run untrusted coding agents without risking host command execution.

Resolution: 1 edit (plus 4 findings seeded by `ponder grade` before the argument).

### Pass 2

- **skeptic** (confidence 0.99) - Falsified f-0004: checkRelativePath in syncOutPaths.ts calls isAbsoluteAnywhere which matches colon syntax (/^[a-z]:/iu) and resolveHostDestination resolves via realpath which fails on invalid ADS streams. Retracting f-0004.
- **builder** (confidence 0.98) - The config.worktree fix is a clean 2-line addition to linkedWorktreeControlPaths.
- **dreamer** (confidence 0.97) - Graded module.seatbelt.profile: verified CONTAINER_ENGINE_HOME_DIRS and CONTAINER_ENGINE_SOCKETS correctly follow writableRoots to prevent socket escape.
- **empath** (confidence 0.97) - Zero noise report for Matt Pocock: false alarms cleanly retracted.

Resolution: 1 add, 1 delete.

### Pass 3

- **skeptic** (confidence 0.99) - Pass 3: All open findings verified against source code; no remaining false positives. Holding silence (0 deltas).
- **builder** (confidence 0.99) - Pass 3: Line-anchored fix recommendations verified against linked worktree admin dir semantics. Holding silence (0 deltas).
- **dreamer** (confidence 0.98) - Pass 3: 100% unit coverage across git mounts, sync-out paths, and Seatbelt profiles. Holding silence (0 deltas).
- **empath** (confidence 0.98) - Pass 3: High-signal, low-ego review that respects maintainer time. Holding silence (0 deltas).

Resolution: no deltas.

### Pass 4

- **skeptic** (confidence 0.99) - Pass 4: All open findings verified against source code; no remaining false positives. Holding silence (0 deltas).
- **builder** (confidence 0.99) - Pass 4: Line-anchored fix recommendations verified against linked worktree admin dir semantics. Holding silence (0 deltas).
- **dreamer** (confidence 0.98) - Pass 4: 100% unit coverage across git mounts, sync-out paths, and Seatbelt profiles. Holding silence (0 deltas).
- **empath** (confidence 0.98) - Pass 4: High-signal, low-ego review that respects maintainer time. Holding silence (0 deltas).

Resolution: no deltas.

## Ledger

7 deltas across 4 passes: 5 add, 1 edit, 1 delete.

| Pass | Deltas | Perspectives |
|---:|---|---|
| 1 | 4 add, 1 edit | builder |
| 2 | 1 add, 1 delete | dreamer, skeptic |
| 3 | no deltas | - |
| 4 | no deltas | - |

The full append-only record is `ledger.jsonl`.

---

*Generated by [Ponder](https://github.com/Quinnod345/ponder) - AI that knows when to speak, and when to shut up.*
