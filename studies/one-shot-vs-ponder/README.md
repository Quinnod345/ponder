# Study: Human One-Shot Toggle, Temperature Variance ($K = 5$), & The Cost of Forced Speech

This study answers three questions that come up immediately when evaluating **Ponder**:

1. **Is Ponder still a "one-shot" prompt for the human?**
   Yes. From the human's perspective, a "one-shot" prompt means **how many messages the human has to type before getting a trustworthy result**. We test the exact same 1-line human prompt with **Ponder OFF** vs. **Ponder ON**—showing that standard "one-shot" AI actually requires **`5.8` human prompts** (`1` initial prompt + `4.8` follow-up babysitting prompts to revert broken decoys and chase missed bugs), whereas **Ponder ON** is a true **`1.0`-prompt** human interaction.
2. **Does Ponder survive LLM temperature & sampling variance, or did a single run just get lucky?**
   Because LLMs sample stochastically (`temperature > 0`), giving the exact same prompt to the same AI at two different moments produces different outputs. We evaluate **`K = 5` independent trials (`Trial 1..5`)** per condition to measure mean $\pm$ standard deviation and cross-run pairwise Jaccard stability ($J(A, B) = |A \cap B| / |A \cup B|$).
3. **What is the real engineering cost of "Forced Speech" — and how does `/caveman` (Syntactic Brevity) interact with `Ponder` (Epistemic Silence)?**
   We quantify the developer minutes lost to forced speech and compare standalone syntactic token compression (`/caveman`) against epistemic silence (`Ponder`), plus a **Hybrid (`Ponder + Internal Caveman Deltas`)** configuration.

---

## Reproduce the Study

Zero npm dependencies are required. Run the multi-trial evaluator from the repository root:

```sh
node studies/one-shot-vs-ponder/evaluate-trials.mjs
```

---

## 1. The Human One-Shot Toggle (`Ponder OFF` vs. `Ponder ON`)

Both conditions begin with the **exact same single human prompt** against [`target-app/`](../head-to-head-benchmark/target-app/) (8 ground-truth bugs `GT-1`–`GT-8` + 3 planted traps `TRAP-DECOY-SQLI`, `TRAP-ORPHAN`, `TRAP-PHANTOM`):

| Condition | Exact Prompt Sent by the Human | Human Prompts Sent | Follow-Up Babysitting Prompts Needed |
|---|---|---:|---:|
| **One-Shot (`Ponder OFF`)** | `"Audit target-app and give me the bug-fix plan."` | `1` initial | **`+4.8` follow-ups** (*"Wait, `safe-query.js` is already parameterized—revert that"*, *"You broke the dashboard error state"*, *"Did you check `results.jsx`?"*) → **`5.8` total human prompts** |
| **One-Shot (`Ponder ON`)** | `"Audit target-app and give me the bug-fix plan. Use ponder."` | `1` initial | **`0.0` follow-ups** (the engine loops autonomously in the background across 4 passes until `coverage == 1.00` and `0` deltas remain) → **`1.0` total human prompt** |

---

## 2. Multi-Trial Temperature Variance Results ($K = 5$ Stochastic Runs)

| Condition ($K = 5$ Trials Each) | Ground-Truth Recall ($\mu \pm \sigma$) | Actionable Precision ($\mu \pm \sigma$) | Cross-Run Stability (Jaccard $J$) | Mean False Positives | Total Human Prompts | Developer Time Cost | Mean Output Tokens |
|---|---:|---:|---:|---:|---:|---:|---:|
| **1. Standard 1-Prompt (`Ponder OFF`)** | `40.0% ± 9.4%` | `49.5% ± 8.7%` | `0.51` | `3.2` | `5.8` | `92.8 min` | `1,490` |
| **2. Caveman 1-Prompt (`/caveman`, `Ponder OFF`)** | `40.0% ± 9.4%` | `49.5% ± 8.7%` | `0.51` | `3.2` | `5.8` | `92.8 min` | `387` (`-74%`) |
| **3. Unstructured 4-Pass (`Forced Speech`)** | `62.5% ± 7.9%` | `29.0% ± 1.7%` | `0.86` | `12.2` | `8.2` | `205.3 min` | `6,954` |
| **4. Ponder 1-Prompt (`Ponder ON` — Full Prose)** | **`97.5% ± 5.0%`** | **`100.0% ± 0.0%`** | **`0.95`** | **`0.0`** | **`1.0`** | **`13.5 min`** | `5,438` |
| **5. Ponder + Internal Caveman Deltas (`Hybrid`)** | **`97.5% ± 5.0%`** | **`100.0% ± 0.0%`** | **`0.95`** | **`0.0`** | **`1.0`** | **`13.5 min`** | **`2,376` (`-56%`)** |

### Why Ponder Collapses Temperature Variance (`0.51` → `0.95` Stability)

Under **Standard 1-Prompt (`Ponder OFF`)**, sampling variance determines which files the agent happens to skim closely before running out of attention:
- In `Trial 3`, it catches only `2/8` bugs (`25.0%` recall) and falls for all 3 traps plus a BEM CSS nitpick.
- In `Trial 2` and `Trial 4`, it catches `4/8` bugs (`50.0%` recall), but different subsets (`{GT-1, GT-4, GT-6, GT-8}` vs. `{GT-1, GT-2, GT-4, GT-7}`).
- Two runs of the exact same prompt agree on only **51%** of their reported findings (`Jaccard = 0.51`).

Under **Ponder 1-Prompt (`Ponder ON`)**, Pass 1 *also* experiences temperature variance—initial Pass-1 recall swings between `50.0%` (`4/8`) and `75.0%` (`6/8`) across the 5 trials. **However, the deterministic state machine absorbs that variance on Pass 2:**
1. **The Coverage Gate (`coverage < 1.0 → blocked`)** refuses to let any trial stop while a single enumerated unit (`screen.dashboard.error`, `screen.results`, `screen.legacy-export`) is ungraded, forcing Pass 2 to inspect the exact units Pass 1 skipped.
2. **The Skeptic Voice (`delete`)** is explicitly tasked with minimizing false positives, forcing Pass 2 to open [`safe-query.js`](../head-to-head-benchmark/target-app/src/lib/safe-query.js) and check importers for [`legacy-v1-modal.jsx`](../head-to-head-benchmark/target-app/src/screens/legacy-v1-modal.jsx), retracting the planted traps in `5/5` trials (`100.0% ± 0.0%` precision).

---

## 3. The Cost of Forced Speech

Standard LLMs suffer from a structural plot hole: during reinforcement learning (RLHF), models are rewarded for producing helpful-looking tokens and penalized for empty responses. **They have no concept that silence can be the highest-value output.**

- When a standard model does not know what is inside a missing route (`legacy-export.jsx`), it guesses and hallucinates a bug.
- When an unstructured multi-pass loop (`Condition 3`) asks the model to *"review and refine your findings"* on Pass 3 and Pass 4 after the obvious bugs are already listed, the model is **structurally incapable of saying "Nothing left to change."** Instead, it manufactures `9`–`10` performative nitpicks per trial (`React.memo` wrappers, BEM renaming, arbitrary constant extraction).

### Developer Time Accounting (`evaluate-trials.mjs`)

Using empirically calibrated remediation times (`14.0 min` to investigate, debug, and revert a false positive or broken decoy; `9.0 min` to manually track down a missed defect via follow-up prompts; `1.5 min` to apply a verified, line-anchored fix):

| Time Component | Standard 1-Prompt (`Ponder OFF`) | Unstructured 4-Pass (`Forced Speech`) | **Ponder 1-Prompt (`Ponder ON`)** |
|---|---:|---:|---:|
| **Chasing & reverting false positives** (`14.0m × FP`) | `44.8 min` (`3.2` FPs) | `170.8 min` (`12.2` FPs) | **`0.0 min` (`0.0` FPs)** |
| **Manually debugging missed bugs** (`9.0m × FN`) | `43.2 min` (`4.8` missed) | `27.0 min` (`3.0` missed) | **`2.2 min` (`0.2` missed)** |
| **Applying verified line-anchored fixes** (`1.5m × TP`) | `4.8 min` (`3.2` fixed) | `7.5 min` (`5.0` fixed) | **`11.3 min` (`7.8` fixed)** |
| **Total Engineering Time per Audit** | **`92.8 min`** | **`205.3 min`** | **`13.5 min` (`6.9x` faster)** |

**Forced speech is not free.** Even a single-pass review costs **44.8 minutes of wasted engineering time** chasing 3.2 false positives, and an unstructured 4-pass loop costs **nearly 3 hours (`170.8 min`)** of pure noise remediation. Because Ponder knows when to speak (Passes 1–2) and when to shut up (Passes 3–4, `0` deltas), it saves **79.3 minutes per audit** over a standard 1-shot prompt (`6.9x` faster).

---

## 4. Two Axes of AI Compression: `/caveman` vs. `Ponder`

A common question is how Ponder relates to syntactic compression skills like **[`/caveman`](https://github.com/JuliusBrussee/caveman)** (*"Why use many token when few do trick"*). They operate on **orthogonal axes**:

| Dimension | `/caveman` Alone (`Condition 2`) | `Ponder` Alone (`Condition 4`) | **`Ponder + Internal Caveman Deltas` (`Condition 5`)** |
|---|---|---|---|
| **What it compresses** | **Syntactic Brevity:** Strips articles, pleasantries, and filler words from prose (`-74%` output tokens). | **Epistemic Silence:** Eliminates false positives (`Skeptic` → `delete`) and halts when findings stabilize (`0` deltas on Pass 4). | **Both:** Terse causal shorthand inside machine-to-machine pass artifacts + full epistemic silence on Pass 4. |
| **What happens to a hallucinated SQLi bug (`TRAP-DECOY-SQLI`)?** | Still reported — just in 5 words instead of 50 (*`"team-actions.js:15 SQLi. Parameterize query."`*). **Still wastes 14 minutes breaking working code.** | **Retracted on Pass 2** (`Skeptic` opens `safe-query.js:5`, verifies `$1` binding, emits `delete`). **0 minutes wasted.** | **Retracted on Pass 2** with terse internal `why` (`"safe-query.js:5 binds $1 -> SQLi false -> delete"`). **0 minutes wasted.** |
| **Mean Output Tokens** | `387` | `5,438` | **`2,376` (`-56%` vs. standard Ponder)** |
| **Precision / Developer Time** | `49.5%` / `92.8 min` | **`100.0%` / `13.5 min`** | **`100.0%` / `13.5 min`** |

### Why Hybrid Mode Works (`Condition 5`)

Even [`caveman/SKILL.md`](https://github.com/JuliusBrussee/caveman) explicitly mandates an **Auto-Clarity Boundary**: *drop caveman mode for security warnings, irreversible action confirmations, and multi-step sequences where fragment misread costs more than a few tokens*.

In Ponder, there are two distinct audiences:
1. **Internal Machine-to-Machine Ledger State (`passes/NN/deliberation.json` and `passes/NN/deltas.jsonl` `why` strings):** Read by the engine and subsequent agent passes. Writing these in terse causal arrow notation (`"safe-query.js:5 -> parameterized $1 -> SQLi false -> delete"`) cuts Ponder's multi-pass token overhead by **56%** (`5,438 → 2,376` tokens) with zero loss in accuracy.
2. **External Human-Facing Handoffs (`findings.json` titles/recommendations, `report.md`, and `apply-plan.md`):** Read by the engineer executing the fixes. Keeping these in clear, complete prose ensures zero ambiguity when modifying production code.
