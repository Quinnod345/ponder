# Live Open-Source Ecosystem Audits (4-Pass `ponder` Case Studies)

> **"AI that knows when to speak - and when to shut up."**

To test `Ponder` outside of synthetic benchmarks, we ran 4-pass sessions against eight major open-source AI developer repositories (**1,039,000+ combined GitHub stars**):

1. **[`obra/superpowers`](https://github.com/obra/superpowers)** (`308.3k`★) - Core agentic skills framework and subagent-driven development methodology (`SDD`)
2. **[`affaan-m/everything-claude-code`](https://github.com/affaan-m/ECC)** (`292.6k`★) - Agent harness performance optimization and hook system
3. **[`garrytan/gstack`](https://github.com/garrytan/gstack)** (`138.2k`★) - Garry Tan's Claude Code software factory and PreToolUse safety/boundary hooks
4. **[`JuliusBrussee/caveman`](https://github.com/JuliusBrussee/caveman)** (`116.1k`★) - Terse-response compression skill, standalone hook installers, and OpenCode plugin
5. **[`addyosmani/agent-skills`](https://github.com/addyosmani/agent-skills)** (`111.7k`★) - Addy Osmani's production engineering skills and Claude Code hook suite
6. **[`EveryInc/compound-engineering-plugin`](https://github.com/EveryInc/compound-engineering-plugin)** (`25.7k`★) - Multi-target AI coding plugin installer/converter (`Claude Code`, `Codex`, `Pi`, `OpenCode`, `Cursor`, etc.)
7. **[`coleam00/Archon`](https://github.com/coleam00/Archon)** (`23.8k`★) - Deterministic AI harness builder and self-hosted workflow server
8. **[`steipete/CodexBar`](https://github.com/steipete/CodexBar)** (`22.9k`★) - macOS menu-bar usage monitor and CLI process supervisor for Codex, Claude, Cursor, and Copilot

---

## Summary of Results

| Repository | Stars | Enumerated Units | Pass 2 `Skeptic` Falsification (`op: "delete"`) | Verified `must` Bugs | Verified `should` Bugs | Pass 3-4 Silence (`churn`) | Final Verdict | Artifacts, Live Issue & Fix PR |
| :--- | :---: | :---: | :--- | :---: | :---: | :---: | :---: | :--- |
| **[`obra/superpowers`](https://github.com/obra/superpowers)** | `308.3k`★ | `5/5` (`1.00`) | Retracted `sdd-workspace` worktree hash collision hypothesis after verifying per-worktree `git rev-parse --show-toplevel` (`test-sdd-workspace.sh:203-216`), and deferred `task-brief` AWK section/fence parsing to upstream `#2406` (`#2359` / `#2304`) | **2** | **0** | `0.20` -> `0.00` (`4` voices, `0` deltas) | `stop (converged)` | [`report.md`](./superpowers/report.md) · [`apply-plan.md`](./superpowers/apply-plan.md) · [Issue #2642](https://github.com/obra/superpowers/issues/2642) |
| **[`affaan-m/everything-claude-code`](https://github.com/affaan-m/ECC)** | `292.6k`★ | `5/5` (`1.00`) | Retracted dangling-symlink bypass hypothesis after verifying `fs.lstatSync` fail-closed handling (`config-protection.js:186`), and noted `MultiEdit` was resolved upstream in `#3775` | **2** | **0** | `0.17` -> `0.00` (`4` voices, `0` deltas) | `stop (converged)` | [`report.md`](./everything-claude-code/report.md) · [`apply-plan.md`](./everything-claude-code/apply-plan.md) · [Issue #3821](https://github.com/affaan-m/ECC/issues/3821) · [PR #3822](https://github.com/affaan-m/ECC/pull/3822) |
| **[`garrytan/gstack`](https://github.com/garrytan/gstack)** | `138.2k`★ | `4/4` (`1.00`) | Retracted `gstack_hook_normalize_path` POSIX backslash-traversal hypothesis after verifying `GSTACK_HOOK_IS_WINDOWS` early-return guard (`careful/bin/hook-extract.sh:110-113`) | **2** | **0** | `0.00` -> `0.00` (`4` voices, `0` deltas) | `stop (converged)` | [`report.md`](./gstack/report.md) · [`apply-plan.md`](./gstack/apply-plan.md) · [Issue #3623](https://github.com/garrytan/gstack/issues/3623) · [PR #3624](https://github.com/garrytan/gstack/pull/3624) |
| **[`JuliusBrussee/caveman`](https://github.com/JuliusBrussee/caveman)** | `116.1k`★ | `5/5` (`1.00`) | Retracted `getDefaultMode(startDir)` symlink traversal loop hypothesis after verifying lexical `path.resolve` + `path.dirname` convergence (`caveman-config.js:116-140`) | **3** | **0** | `0.20` -> `0.00` (`4` voices, `0` deltas) | `stop (converged)` | [`report.md`](./caveman/report.md) · [`apply-plan.md`](./caveman/apply-plan.md) · [Issue #1430](https://github.com/JuliusBrussee/caveman/issues/1430) · [PR #1431 (`ADOPTED` on #1395)](https://github.com/JuliusBrussee/caveman/pull/1431) |
| **[`addyosmani/agent-skills`](https://github.com/addyosmani/agent-skills)** | `111.7k`★ | `5/5` (`1.00`) | Retracted `sdd-cache-pre.sh` shell-expansion hypothesis after verifying `printf "%s\n" "$CONTENT"` (`hooks/sdd-cache-pre.sh:103`) | **2** | **1** | `0.14` -> `0.00` (`4` voices, `0` deltas) | `stop (converged)` | [`report.md`](./agent-skills/report.md) · [`apply-plan.md`](./agent-skills/apply-plan.md) · [Issue #765](https://github.com/addyosmani/agent-skills/issues/765) · [PR #766 (`MERGED`)](https://github.com/addyosmani/agent-skills/pull/766) |
| **[`EveryInc/compound-engineering-plugin`](https://github.com/EveryInc/compound-engineering-plugin)** | `25.7k`★ | `5/5` (`1.00`) | Retracted manifest path-traversal alarm after verifying `resolveWithinRoot` (`src/parsers/claude.ts:263-270`) | **3** | **1** | `0.00` -> `0.00` (`4` voices, `0` deltas) | `stop (converged)` | [`report.md`](./compound-engineering-plugin/report.md) · [`apply-plan.md`](./compound-engineering-plugin/apply-plan.md) · [Issue #1916](https://github.com/EveryInc/compound-engineering-plugin/issues/1916) · [PR #1919 (`MERGED`)](https://github.com/EveryInc/compound-engineering-plugin/pull/1919) |
| **[`coleam00/Archon`](https://github.com/coleam00/Archon)** | `23.8k`★ | `3/3` (`1.00`) | Retracted login `rd` open-redirect alarm (`isSafeRedirect`), `GET /login` double-decode hypothesis (`handleLoginPage` encodes `rd`), and `SSETransport` hypothesis (`dev` clears `liveWritePending` per entry) | **1** | **0** | `0.00` -> `0.00` (`4` voices, `0` deltas) | `stop (converged)` | [`report.md`](./archon/report.md) · [`apply-plan.md`](./archon/apply-plan.md) · [Issue #5256](https://github.com/coleam00/Archon/issues/5256) |
| **[`steipete/CodexBar`](https://github.com/steipete/CodexBar)** | `22.9k`★ | `4/4` (`1.00`) | Retracted credential symlink/permission-window alarm after verifying `0700` staging + `O_EXCL` `0600` + atomic `rename(2)` (`CredentialFileWriter.swift:38-74`) | **1** | **2** | `0.00` -> `0.00` (`4` voices, `0` deltas) | `stop (converged)` | [`report.md`](./codexbar/report.md) · [`apply-plan.md`](./codexbar/apply-plan.md) · [Issue #4829 (`🦞 diamond lobster`)](https://github.com/steipete/CodexBar/issues/4829) · [PR #4830 (`MERGED` · `🦞 diamond lobster`)](https://github.com/steipete/CodexBar/pull/4830) |

---

## Why This Matters for Maintainers

When maintainers receive AI-generated bug reports, two failure modes waste their time:
1. **Unverified Pass-1 False Positives**: A single-shot LLM skims a file, sees `manifest.hooks` path joining, `CredentialFileWriter`, or `Location: ${safeRd}`, and files a false security report without reading the defense helper 30 lines below.
2. **Incomplete Cross-Module Coverage**: A single-shot LLM flags one file and misses the sibling target (`codex.ts` vs `pi.ts` vs `opencode.ts`, or `install.sh` vs `install.ps1` vs `opencode/plugin.js`).

In all eight audits:
- **Pass 1 (`coverage < 1.00` or unverified hypotheses)** was prevented from stopping early.
- **Pass 2 (`Skeptic` + `Dreamer`)** opened the defense helpers, **retracted false alarms via `op: "delete"`** so maintainers never had to read them as noise, and graded the remaining modules.
- **Pass 4 (`stop (converged)`)** held 4-voice epistemic silence (`0` deltas) instead of inventing style nitpicks.
