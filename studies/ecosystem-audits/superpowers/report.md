# Ponder - SDD workspace, task-brief parser, and executing-plans helper scripts in obra/superpowers

`superpowers-sdd` · lens **architecture** · status **stopped** · 4 passes of a 6-pass budget · generated 2026-10-29T18:59:52.387Z

| | |
|---|---|
| Subject | SDD workspace, task-brief parser, and executing-plans helper scripts in obra/superpowers |
| Lens | architecture - unit = module, 11 dimensions |
| Project | `/Users/quinnodonnell/.gemini/antigravity/scratch/superpowers` |
| Passes | 4 run · min 2 · max 6 |
| Coverage | 1.00 - 5 of 5 modules graded |
| Findings | 6 total · 4 open (2 must, 2 note) · 1 tracked upstream (#2406) · 0 deferred · 1 retracted |
| Final verdict | continue (default) -> decided **stop** |
| OCA | off |

## Convergence

| Pass | Coverage | Novelty | Churn | Thrash | Surprise | Stall | Conf-floor | Voices | Advice | Decision |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|---|
| 1 | 1.00 | - | - | - | - | 0 | 0.00 | 4 | continue (min-passes) | continue |
| 2 | 1.00 | 0.20 | 0.40 | 0.00 | 0.05 | 0 | 0.00 | 4 | continue (default) | continue |
| 3 | 1.00 | 0.00 | 0.20 | 0.00 | 0.10 | 0 | 0.00 | 4 | continue (default) | continue |
| 4 | 1.00 | 0.00 | 0.00 | 0.00 | 0.00 | 1 | 0.00 | 4 | continue (default) | stop |

`-` on pass 1 is not a zero. Novelty, churn, thrash and surprise measure change against a previous pass, and pass 1 has none.

## Overrides

- **Pass 4** - advice `continue` (default), decided `stop`.
  > Converged across 4 passes after retracting 1 false positive in Pass 2, noting `task-brief` AWK section/fence parsing is already tracked upstream in `#2406` (`#2359` / `#2304`), and verifying the 2 `executing-plans` `${BASH:-bash}` invocation findings (`Issue #2642`) with deterministic tests.

## Prediction vs reality

| Pass | Predicted churn | Actual churn | Surprise | Claim |
|---:|---:|---:|---:|---|
| 1 | 0.45 | - | - | Pass 1 enumerates 5 helper scripts and seeds initial defects plus worktree hypothesis. |
| 2 | 0.35 | 0.40 | 0.05 | Pass 2 will falsify the sdd.workspace git worktree collision hypothesis and tighten evidence on the must findings. |
| 3 | 0.10 | 0.20 | 0.10 | Pass 3 will refine the regression test recommendations for test-executing-plans-scripts.sh and note upstream #2406 on task-brief. |
| 4 | 0.00 | 0.00 | 0.00 | Pass 4 will confirm zero new defects and full convergence across all 5 modules. |

## Coverage

5 modules enumerated, 5 graded.

## Findings

### Inline task-done runner & ledger writer (skills/executing-plans/scripts/task-done) `script.ep.task_done`
`skills/executing-plans/scripts/task-done`

- **f-0002** · must · score 1 · confidence 0.95 · effort xs · portability - task-done invokes $sdd/sdd-workspace directly instead of via ${BASH:-bash}, failing with Permission denied (exit 126) when unpacked without +x
  skills/executing-plans/scripts/task-done:25 runs dir=$("$sdd/sdd-workspace" "$plan") directly without "${BASH:-bash}", so recording task completion fails with exit 126 when installed via marketplace archive extractors that strip +x (see Issue #2040).
  Evidence: `skills/executing-plans/scripts/task-done:25`, `skills/subagent-driven-development/scripts/review-package:35`
  Do: Invoke "$sdd/sdd-workspace" via "${BASH:-bash}" "$sdd/sdd-workspace" "$plan" to match task-brief:26 and review-package:35.

### Inline task-start helper (skills/executing-plans/scripts/task-start) `script.ep.task_start`
`skills/executing-plans/scripts/task-start`

- **f-0001** · must · score 1 · confidence 0.95 · effort xs · portability - task-start invokes $sdd/task-brief directly instead of via ${BASH:-bash}, failing with Permission denied (exit 126) when unpacked without +x
  Issue #2040 noted that Python zipfile and marketplace skill extractors strip Unix execute bits, so task-brief:26 and review-package:35 invoke sibling scripts via "${BASH:-bash}". However, skills/executing-plans/scripts/task-start:23 still runs out=$("$sdd/task-brief" "$plan" "$n") directly, failing with exit 126 when execute bits are stripped.
  Evidence: `skills/executing-plans/scripts/task-start:23`, `skills/subagent-driven-development/scripts/task-brief:26`
  Do: Invoke "$sdd/task-brief" via "${BASH:-bash}" "$sdd/task-brief" "$plan" "$n" in skills/executing-plans/scripts/task-start:23, and add a chmod -x regression check in tests/claude-code/test-executing-plans-scripts.sh.
  _Revised: p3 edit recommendation_

### Task brief markdown extractor (skills/subagent-driven-development/scripts/task-brief) `script.sdd.task_brief`
`skills/subagent-driven-development/scripts/task-brief`

- **f-0003** · tracked upstream (`#2406` / `#2359` / `#2304`) · correctness - task-brief AWK parser trailing non-Task headings (e.g. ## Self-Review, ## Execution Handoff) and nested fences
  In skills/subagent-driven-development/scripts/task-brief:30-36, intask is only updated when matching /^#+[ \t]+Task[ \t]+[0-9]+/ and /^```/ { infence = !infence } toggles on any 3-backtick prefix. Because this is already tracked upstream in Issue #2406 and open PRs #2359 and #2304, we narrowed Issue #2642 strictly to the `executing-plans` `${BASH:-bash}` invocation gap (`f-0001` and `f-0002`).
  Evidence: `skills/subagent-driven-development/scripts/task-brief:30-36`, `skills/writing-plans/SKILL.md:163-204`
  Do: Deferred to upstream Issue #2406 (`#2359` / `#2304`).

### Review package diff generator (skills/subagent-driven-development/scripts/review-package) `script.sdd.review_package`
`skills/subagent-driven-development/scripts/review-package`

- **f-0005** · note · score 5 · confidence 0.90 · effort xs · correctness - review-package properly delegates to sdd-workspace via ${BASH:-bash} and handles base..head empty diff
  review-package:35 uses "${BASH:-bash}" "$here/sdd-workspace" "$plan" and validates git rev-parse before assembling review.md.
  Evidence: `skills/subagent-driven-development/scripts/review-package:35-65`
  Do: No change needed.

### SDD workspace resolver & plan-path marker (skills/subagent-driven-development/scripts/sdd-workspace) `script.sdd.workspace`
`skills/subagent-driven-development/scripts/sdd-workspace`

- **f-0006** · note · score 5 · confidence 0.95 · effort xs · state-integrity - sdd-workspace isolates linked git worktrees via per-worktree git rev-parse --show-toplevel hashing
  Empirical check and tests/claude-code/test-sdd-workspace.sh:203-216 confirm each git worktree gets a distinct top-level path hash and isolated workspace directory.
  Evidence: `skills/subagent-driven-development/scripts/sdd-workspace:56-59`, `tests/claude-code/test-sdd-workspace.sh:203-216`
  Do: No change needed.

## Retracted

Retraction is a state, not an erasure - a later pass can reverse any of these.

- `f-0004` (script.sdd.workspace) - sdd-workspace repo-relative plan_id could collide across git worktrees if top-level path resolves to shared git common dir · retracted in pass 2 by the skeptic: git rev-parse --show-toplevel returns each linked worktree's own directory, as verified in tests/claude-code/test-sdd-workspace.sh:203-216.

## Deliberation

### Pass 1

- **skeptic** (confidence 0.85) - All 5 modules have concrete file:line evidence, though the sdd.workspace worktree collision hypothesis needs empirical verification in Pass 2 before it can be promoted above should.
- **builder** (confidence 0.95) - Both executing-plans scripts (task-start:23 and task-done:25) can be fixed with one-line ${BASH:-bash} invocations matching Issue #2040.
- **dreamer** (confidence 0.85) - We should check if test-executing-plans-scripts.sh has regression coverage for stripped execute bits and whether task-brief is already tracked in upstream issues/PRs.
- **empath** (confidence 0.90) - Keeping our upstream issue focused strictly on the non-overlapping `executing-plans` `${BASH:-bash}` invocation bug (`Issue #2642`) avoids duplicating existing PRs (`#2359` / `#2304` on `#2406`).

Resolution: 1 edit (plus 5 findings seeded by `ponder grade` before the argument).

### Pass 2

- **skeptic** (confidence 0.98) - Testing git rev-parse --show-toplevel inside a linked git worktree confirms it returns the linked worktree root, not the main repo root, and tests/claude-code/test-sdd-workspace.sh:203-216 already tests worktree isolation. Retract f-0004 as a false positive.
- **builder** (confidence 0.95) - Re-substitute f-0004 on script.sdd.workspace with a verified clean-grade note so unit coverage stays 1.00 across all 5 enumerated scripts while keeping only true defects open.
- **dreamer** (confidence 0.90) - Verify whether task-brief:26 itself works when sdd-workspace loses +x: yes, line 26 uses ${BASH:-bash}, which proves task-start:23 and task-done:25 were missed when the Issue #2040 fix landed.
- **empath** (confidence 0.95) - Retracting the false worktree alarm and deferring f-0003 to upstream #2406 keeps Issue #2642 focused strictly on the reproducible `executing-plans` exit 126 bug.

Resolution: 1 add, 1 delete.

### Pass 3

- **skeptic** (confidence 0.98) - Both open must findings (f-0001 and f-0002) are empirically reproduced: chmod -x on sdd scripts causes task-start and task-done to exit 126.
- **builder** (confidence 0.95) - Include the exact test file location (tests/claude-code/test-executing-plans-scripts.sh) in the evidence and recommendations for f-0001 and f-0002.
- **dreamer** (confidence 0.95) - No additional defects exist across the 5 scripts; all edge cases in argument parsing and path normalization are covered.
- **empath** (confidence 0.95) - Issue #2642 clearly documents the exact two lines (`task-start:23` and `task-done:25`) and reproducer.

Resolution: 1 edit.

### Pass 4

- **skeptic** (confidence 0.99) - Zero remaining unverified claims; the false positive on sdd-workspace was retracted in Pass 2 and both open must findings have deterministic reproducers.
- **builder** (confidence 0.99) - Recommendations for task-start and task-done are minimal and self-contained.
- **dreamer** (confidence 0.99) - Cross-script contract between executing-plans and subagent-driven-development is now consistent with Issue #2040.
- **empath** (confidence 0.99) - Report is concise, evidence-backed, and ready for maintainers.

Resolution: no deltas.

## Ledger

9 deltas across 4 passes: 6 add, 2 edit, 1 delete.

| Pass | Deltas | Perspectives |
|---:|---|---|
| 1 | 5 add, 1 edit | builder |
| 2 | 1 add, 1 delete | dreamer, skeptic |
| 3 | 1 edit | builder |
| 4 | no deltas | - |

The full append-only record is `ledger.jsonl`.

---

*Generated by [Ponder](https://github.com/Quinnod345/ponder) - AI that knows when to speak, and when to shut up.*
