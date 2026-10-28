# Ponder — Subprocess process-group isolation, watchdog signal safety, and credential file staging in steipete/CodexBar

`codexbar` · lens **architecture** · status **converged** · 4 passes of a 6-pass budget · generated 2026-10-28T15:12:50.585Z

| | |
|---|---|
| Subject | Subprocess process-group isolation, watchdog signal safety, and credential file staging in steipete/CodexBar |
| Lens | architecture — unit = module, 11 dimensions |
| Project | `/var/folders/29/k94h5cq10ls0gm_1v1jlb1j00000gn/T/ponder-audit-codexbar-YVlU6E` |
| Passes | 4 run · min 2 · max 6 |
| Coverage | 1.00 — 4 of 4 modules graded |
| Findings | 6 total · 5 open · 0 resolved · 0 deferred · 1 retracted |
| Final verdict | stop (converged) → decided **stop** |
| OCA | off |

## Convergence

| Pass | Coverage | Novelty | Churn | Thrash | Surprise | Stall | Conf-floor | Voices | Advice | Decision |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|---|
| 1 | 0.75 | — | — | — | — | 0 | 0.00 | 4 | blocked (coverage) | continue |
| 2 | 1.00 | 0.40 | 0.60 | 0.00 | 0.25 | 0 | 0.00 | 4 | continue (default) | continue |
| 3 | 1.00 | 0.00 | 0.00 | 0.00 | 0.02 | 1 | 0.00 | 4 | continue (default) | continue |
| 4 | 1.00 | 0.00 | 0.00 | 0.00 | 0.00 | 2 | 0.00 | 4 | stop (converged) | stop |

`—` on pass 1 is not a zero. Novelty, churn, thrash and surprise measure change against a previous pass, and pass 1 has none.

## Overrides

None. Every decision followed the engine's advice.

## Prediction vs reality

| Pass | Predicted churn | Actual churn | Surprise | Claim |
|---:|---:|---:|---:|---|
| 1 | 0.45 | — | — | Pass 1 enumerates target modules and seeds initial findings. |
| 2 | 0.35 | 0.60 | 0.25 | Pass 2 verifies and retracts Pass-1 false positive and grades remaining module to reach coverage 1.00. |
| 3 | 0.02 | 0.00 | 0.02 | Pass 3 expects near-zero churn after Pass 2 falsification and full unit coverage. |
| 4 | 0.00 | 0.00 | 0.00 | Pass 4 expects 0 deltas and Rule 6 convergence. |

## Coverage

4 modules enumerated, 4 graded.

## Findings

### CodexBarClaudeWatchdog process spawner & tree killer (Sources/CodexBarClaudeWatchdog/main.swift) `module.watchdog.main`
`Sources/CodexBarClaudeWatchdog/main.swift`

- **f-0001** · must · score 1 · confidence 0.97 · effort xs · failure-modes — CodexBarClaudeWatchdog post-spawn setpgid EACCES race and unguarded kill(-pgid) can send SIGTERM/SIGKILL to the parent process group
  In Sources/CodexBarClaudeWatchdog/main.swift:71, posix_spawnp(&pid, childPath, nil, nil, cBuffer.baseAddress, environ) spawns the child with attrp = nil (inheriting the watchdog and parent app process group), and line 85 calls _ = setpgid(globalChildPID, globalChildPID) ignoring errors. Once posix_spawnp has exec'd the child binary, setpgid(2) from the parent fails with EACCES, leaving globalChildPID in the parent process group (pgid == getpgrp()). When killProcessTree (main.swift:17-38) runs on signal or parent death (getppid() == 1), let pgid = getpgid(childPID); if pgid > 0 { kill(-pgid, SIGTERM) } checks only pgid > 0 instead of pgid == childPID && pgid != getpgrp(), sending SIGTERM and SIGKILL to the parent process group.
  Evidence: `Sources/CodexBarClaudeWatchdog/main.swift:17-38`, `Sources/CodexBarClaudeWatchdog/main.swift:71`, `Sources/CodexBarClaudeWatchdog/main.swift:85`, `Sources/CodexBarCore/Host/Process/SpawnedProcessGroup.swift:362-367`, `Sources/CodexBarCore/Host/Process/ProcessOwnershipReaper.swift:38`
  Do: In Sources/CodexBarClaudeWatchdog/main.swift:69-72, initialize posix_spawnattr_t with POSIX_SPAWN_SETPGROUP \| POSIX_SPAWN_CLOEXEC_DEFAULT and posix_spawnattr_setpgroup(&attr, 0), and in killProcessTree (lines 19, 33) check if pgid == childPID, pgid != getpgrp() before calling kill(-pgid, ...).
  _Revised: p1 edit recommendation_

- **f-0002** · should · score 2 · confidence 0.95 · effort xs · contract-stability — killProcessTree reaps childPID and discards its wait status, causing getppid() == 1 teardown to exit 0 after ECHILD
  In Sources/CodexBarClaudeWatchdog/main.swift:28-29, killProcessTree calls let rc = waitpid(childPID, &status, WNOHANG); if rc == childPID { return }, reaping childPID and discarding status. When getppid() == 1 (lines 115-118) calls terminateChild() followed by _ = waitpid(globalChildPID, &status, 0), the second waitpid fails with ECHILD (-1), leaving outer status = 0 (from line 101) and exiting with 0.
  Evidence: `Sources/CodexBarClaudeWatchdog/main.swift:26-30`, `Sources/CodexBarClaudeWatchdog/main.swift:101`, `Sources/CodexBarClaudeWatchdog/main.swift:108-119`
  Do: Return the reaped wait status from killProcessTree / terminateChild when waitpid(childPID, &status, WNOHANG) succeeds, and only call blocking waitpid at lines 111/117 if the child was not yet reaped.

### SpawnedProcessGroup lifecycle & WNOWAIT reaper (Sources/CodexBarCore/Host/Process/SpawnedProcessGroup.swift) `module.process.spawnedgroup`
`Sources/CodexBarCore/Host/Process/SpawnedProcessGroup.swift`

- **f-0006** · should · score 2 · confidence 0.93 · effort xs · failure-modes — abortSynchronously spins for the full 2 * grace (800ms) after root exit because unreaped WNOWAIT zombie keeps hasResidualProcessGroup true
  In Sources/CodexBarCore/Host/Process/SpawnedProcessGroup.swift:686-699, startWaiter() uses waitid(P_PID, id_t(pid), &info, WEXITED \| WNOWAIT) and leaves self.pid as an unreaped zombie until finishSynchronously() calls requestReap() at line 588. During abortSynchronously (lines 568-589), abortTargetsRemain (line 781) checks self.hasResidualProcessGroup (kill(-self.processGroup, 0) == 0). On Darwin/XNU, an unreaped zombie remains in its pgrp until waitpid reaps it, so kill(-self.processGroup, 0) stays 0 even when the child exited immediately on SIGTERM and no live group members remain.
  Evidence: `Sources/CodexBarCore/Host/Process/SpawnedProcessGroup.swift:524-526`, `Sources/CodexBarCore/Host/Process/SpawnedProcessGroup.swift:568-589`, `Sources/CodexBarCore/Host/Process/SpawnedProcessGroup.swift:686-705`, `Sources/CodexBarCore/Host/Process/SpawnedProcessGroup.swift:778-791`
  Do: In abortTargetsRemain (SpawnedProcessGroup.swift:778-782), when self.termination.hasObservedExit is true, check !self.currentProcessGroupMemberIdentities().isEmpty rather than self.hasResidualProcessGroup.

### CredentialFileWriter atomic 0600 file publisher (Sources/CodexBarCore/CredentialFileWriter.swift) `module.credentials.writer`
`Sources/CodexBarCore/CredentialFileWriter.swift`

- **f-0005** · note · score 5 · confidence 0.99 · effort xs · data-ownership — CredentialFileWriter establishes 0600 permissions in a 0700 staging directory before write and publishes via atomic rename(2)
  Sources/CodexBarCore/CredentialFileWriter.swift:38-74 prevents both permission-window exposure and symlink-following.
  Evidence: `Sources/CodexBarCore/CredentialFileWriter.swift:38-74`
  Do: No change needed.

### ProcessOwnershipReaper capability marker (Sources/CodexBarCore/Host/Process/ProcessOwnershipReaper.swift) `module.process.reaper`
`Sources/CodexBarCore/Host/Process/ProcessOwnershipReaper.swift`

- **f-0003** · note · score 5 · confidence 0.98 · effort xs · boundary-integrity — ProcessOwnershipReaper guards group != getpgrp() and revalidates process identity before every signal
  Sources/CodexBarCore/Host/Process/ProcessOwnershipReaper.swift:38-44 explicitly checks guard group > 0, group != getpgrp() and verifies CODEXBAR_PROBE_OWNER marker + start-time identity before signaling.
  Evidence: `Sources/CodexBarCore/Host/Process/ProcessOwnershipReaper.swift:37-45`
  Do: Keep ProcessOwnershipReaper.signalGroup as the reference pattern for CodexBarClaudeWatchdog.

## Retracted

Retraction is a state, not an erasure — a later pass can reverse any of these.

- `f-0004` (module.credentials.writer) — CredentialFileWriter may expose a permission window or follow symlinks when writing token files · retracted in pass 2 by the skeptic: Falsified on direct code inspection: CredentialFileWriter.writePrivate (Sources/CodexBarCore/CredentialFileWriter.swift:38-74) stages in a 0700 directory with O_CREAT\|O_EXCL 0600, fchmod(0600) before write, synchronize(), and atomic rename(2).

## Deliberation

### Pass 1

- **skeptic** (confidence 0.92) — Pass 1 graded 3 of 4 modules (coverage 0.75). On Pass 2 I will inspect Sources/CodexBarCore/CredentialFileWriter.swift:38-74 to verify whether f-0004 is a false alarm, and we must grade module.process.spawnedgroup.
- **builder** (confidence 0.95) — The contrast between SpawnedProcessGroup.swift:362-367 (which uses POSIX_SPAWN_SETPGROUP) and CodexBarClaudeWatchdog/main.swift:71,85 (which spawns with nil attributes and ignores setpgid EACCES) proves f-0001.
- **dreamer** (confidence 0.90) — On Pass 2 I will trace how SpawnedProcessGroup.abortSynchronously interacts with the unreaped WNOWAIT zombie created by startWaiter() at line 686.
- **empath** (confidence 0.95) — A watchdog helper meant to clean up hung Claude CLI probes must never be able to SIGKILL the user's running menu-bar app.

Resolution: 1 edit (plus 4 findings seeded by `ponder grade` before the argument).

### Pass 2

- **skeptic** (confidence 0.99) — Inspected Sources/CodexBarCore/CredentialFileWriter.swift:38-74: writePrivate creates a 0700 staging directory, opens the staged file with O_WRONLY \| O_CREAT \| O_EXCL \| O_CLOEXEC at 0600, calls fchmod(0600) before writing, fsyncs, and atomically renames over the target URL. Retracting f-0004.
- **builder** (confidence 0.93) — In abortTargetsRemain (SpawnedProcessGroup.swift:778-782), checking !self.currentProcessGroupMemberIdentities().isEmpty once termination.hasObservedExit is true eliminates the 800ms zombie spin.
- **dreamer** (confidence 0.94) — Graded module.process.spawnedgroup (SpawnedProcessGroup.swift:524-589, 686-705, 778-782): because startWaiter uses waitid(..., WNOWAIT) and waits up to 30s before waitpid, self.pid remains a zombie in self.processGroup during abortSynchronously, keeping hasResidualProcessGroup (kill(-pgid, 0) == 0) true for the full 2 * grace (800ms) spin.
- **empath** (confidence 0.90) — Eliminating the 800ms synchronous wait during PTY/process abort keeps menu-bar teardown responsive.

Resolution: 2 add, 1 delete.

### Pass 3

- **skeptic** (confidence 0.98) — Pass 3: Re-checked all open findings against file:line evidence; no remaining false positives or unverified assumptions. Holding silence (0 deltas).
- **builder** (confidence 0.98) — Pass 3: Every open finding has a minimal, line-anchored fix recommendation. Holding silence (0 deltas).
- **dreamer** (confidence 0.97) — Pass 3: All enumerated modules are graded (coverage 1.00) and cross-module invariants are satisfied. Holding silence (0 deltas).
- **empath** (confidence 0.97) — Pass 3: Severity tiers accurately reflect user and maintainer impact. Holding silence (0 deltas).

Resolution: no deltas.

### Pass 4

- **skeptic** (confidence 0.98) — Pass 4: Re-checked all open findings against file:line evidence; no remaining false positives or unverified assumptions. Holding silence (0 deltas).
- **builder** (confidence 0.98) — Pass 4: Every open finding has a minimal, line-anchored fix recommendation. Holding silence (0 deltas).
- **dreamer** (confidence 0.97) — Pass 4: All enumerated modules are graded (coverage 1.00) and cross-module invariants are satisfied. Holding silence (0 deltas).
- **empath** (confidence 0.97) — Pass 4: Severity tiers accurately reflect user and maintainer impact. Holding silence (0 deltas).

Resolution: no deltas.

## Ledger

8 deltas across 4 passes: 6 add, 1 edit, 1 delete.

| Pass | Deltas | Perspectives |
|---:|---|---|
| 1 | 4 add, 1 edit | builder |
| 2 | 2 add, 1 delete | dreamer, skeptic |
| 3 | no deltas | — |
| 4 | no deltas | — |

The full append-only record is `ledger.jsonl`.

---

*Generated by [Ponder](https://github.com/Quinnod345/ponder) — AI that knows when to speak, and when to shut up.*
