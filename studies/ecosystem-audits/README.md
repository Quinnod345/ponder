# Live Open-Source Ecosystem Audits (4-Pass `ponder` Case Studies)

> **"AI that knows when to speak — and when to shut up."**

To test `Ponder` outside of synthetic benchmarks, we ran 4-pass `architecture` lens sessions against three popular open-source AI developer repositories (**72,300+ combined GitHub stars**):

1. **[`EveryInc/compound-engineering-plugin`](https://github.com/EveryInc/compound-engineering-plugin)** (`25.7k`★) — Multi-target AI coding plugin installer/converter (`Claude Code`, `Codex`, `Pi`, `OpenCode`, `Cursor`, etc.)
2. **[`steipete/CodexBar`](https://github.com/steipete/CodexBar)** (`22.9k`★) — macOS menu-bar usage monitor and CLI process supervisor for Codex, Claude, Cursor, and Copilot
3. **[`coleam00/Archon`](https://github.com/coleam00/Archon)** (`23.8k`★) — Deterministic AI harness builder and self-hosted workflow server

---

## Summary of Results

| Repository | Stars | Enumerated Units | Pass 1 Coverage | Pass 2 `Skeptic` Falsification (`op: "delete"`) | Verified `must` Bugs | Verified `should` Bugs | Pass 3–4 Silence (`churn`) | Final Verdict | Artifacts |
| :--- | :---: | :---: | :---: | :--- | :---: | :---: | :---: | :---: | :--- |
| **[`EveryInc/compound-engineering-plugin`](https://github.com/EveryInc/compound-engineering-plugin)** | `25.7k`★ | `5/5` (`1.00`) | `0.80` (`blocked`) | Retracted manifest path-traversal alarm after verifying `resolveWithinRoot` (`src/parsers/claude.ts:263-270`) | **3** | **1** | `0.00` -> `0.00` (`4` voices, `0` deltas) | `stop (converged)` | [`report.md`](./compound-engineering-plugin/report.md) · [`apply-plan.md`](./compound-engineering-plugin/apply-plan.md) |
| **[`steipete/CodexBar`](https://github.com/steipete/CodexBar)** | `22.9k`★ | `4/4` (`1.00`) | `0.75` (`blocked`) | Retracted credential symlink/permission-window alarm after verifying `0700` staging + `O_EXCL` `0600` + atomic `rename(2)` (`CredentialFileWriter.swift:38-74`) | **1** | **2** | `0.00` -> `0.00` (`4` voices, `0` deltas) | `stop (converged)` | [`report.md`](./codexbar/report.md) · [`apply-plan.md`](./codexbar/apply-plan.md) |
| **[`coleam00/Archon`](https://github.com/coleam00/Archon)** | `23.8k`★ | `3/3` (`1.00`) | `0.67` (`blocked`) | Retracted login `rd` open-redirect alarm after verifying `isSafeRedirect` (`auth-service/server.js:62-65`) blocks `//`, `/\`, and `://` | **2** | **1** | `0.00` -> `0.00` (`4` voices, `0` deltas) | `stop (converged)` | [`report.md`](./archon/report.md) · [`apply-plan.md`](./archon/apply-plan.md) |

---

## Why This Matters for Maintainers

When maintainers receive AI-generated bug reports, two failure modes waste their time:
1. **Unverified Pass-1 False Positives**: A single-shot LLM skims a file, sees `manifest.hooks` path joining, `CredentialFileWriter`, or `Location: ${safeRd}`, and files a false security report without reading the defense helper 30 lines below.
2. **Incomplete Cross-Module Coverage**: A single-shot LLM flags one file and misses the sibling target (`codex.ts` vs `pi.ts` vs `opencode.ts`, or `SpawnedProcessGroup.swift` vs `CodexBarClaudeWatchdog/main.swift`).

In all three audits:
- **Pass 1 (`blocked (coverage)`)** was prevented from stopping early because `coverage < 1.00`.
- **Pass 2 (`Skeptic` + `Dreamer`)** opened the defense helpers (`resolveWithinRoot`, `CredentialFileWriter.writePrivate`, `isSafeRedirect`), **retracted all 3 false alarms via `op: "delete"`** so maintainers never had to read them as noise, and graded the remaining modules.
- **Passes 3 & 4 (`stop (converged)`)** held 4-voice epistemic silence (`0` deltas) instead of inventing style nitpicks.

---

## Reproducing All 3 Sessions Locally

```bash
node studies/ecosystem-audits/run-audits.mjs
```

This script drives [`bin/ponder`](../../bin/ponder) through all 4 passes for each repository, verifies ledger integrity via `reconcile()` (`lib/reconcile.js`) and `ponder verify`, and regenerates `report.md` and `apply-plan.md` for each target.
