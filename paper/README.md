# Forced Speech vs. Epistemic Silence: Why Multi-Pass LLM Self-Refinement Degrades Precision and How Loss-Function Isomorphism Restores Convergence

**Author:** Quinn O'Donnell ([`@quinnod7`](https://x.com/quinnod7) · [`Quinnod345`](https://github.com/Quinnod345))  
**Repository:** [`https://github.com/Quinnod345/ponder`](https://github.com/Quinnod345/ponder)  
**Reproducible Artifacts:** [`studies/head-to-head-benchmark/`](../studies/head-to-head-benchmark/) · [`studies/one-shot-vs-ponder/`](../studies/one-shot-vs-ponder/) · [`studies/ecosystem-audits/`](../studies/ecosystem-audits/)

---

## Abstract

Iterative self-refinement (`Self-Refine`) and multi-agent debate are widely used to improve the quality of large language model (LLM) outputs on complex software engineering tasks. However, when applied to open-ended codebase auditing and architectural planning without an external test oracle, unstructured multi-pass loops exhibit a systematic pathology: **beyond Pass 2, additional passes degrade actionable precision rather than improving it.** We identify the root cause as **forced speech**, a training artifact of autoregressive instruction tuning and RLHF in which a model treats an empty revision turn as a failure and manufactures speculative nitpicks or false-positive defects to justify its turn.

We introduce **Ponder**, a zero-dependency state machine and deliberation protocol derived from the Oneiro Cognitive Architecture (`oneiro-oca`) that replaces open-ended prose self-refinement with three formal invariants: (1) a **disk-anchored monotonic coverage gate** (`ponder units --scan <dir> --strict-scope`) with path-history phantom verification, (2) **loss-function isomorphism**, a bijection mapping four adversarial cognitive voices (`Dreamer`, `Builder`, `Empath`, `Skeptic`) onto the four state transitions (`add`, `edit`, `change`, `delete`) of an append-only ledger, and (3) **epistemic silence decoupling**, which tracks verification participation (`voices`) separately from state mutation (`deltaVoices`) so that emitting zero deltas after full evidence verification serves as the formal certificate of convergence.

Across $K = 5$ stochastic trials on a benchmark codebase with 8 planted defects and 3 adversarial traps, unstructured 4-pass self-refinement lifts recall from $40.0\% \pm 9.4\%$ to $62.5\% \pm 7.9\%$ but collapses precision from $49.5\% \pm 8.7\%$ to $29.0\% \pm 1.7\%$ ($12.2$ false positives per run). Ponder achieves **$97.5\% \pm 5.0\%$ recall**, **$100.0\% \pm 0.0\%$ precision** ($0.0$ false positives, Mann-Whitney $U = 25.0, p = 0.0079$), and raises cross-run Jaccard stability from $J = 0.51$ to $J = 0.95$. Furthermore, combining Ponder's epistemic silence with terse causal notation (`/caveman` style) inside internal ledger deltas reduces multi-pass token consumption by **56%** without loss of precision. In live 4-pass audits across three production open-source repositories totaling **72,400+ GitHub stars** (`EveryInc/compound-engineering-plugin`, `steipete/CodexBar`, and `coleam00/Archon`), Pass-2 `Skeptic` falsification retracted plausible Pass-1 security false alarms in all three repositories while surfacing verified defects resulting in merged upstream fixes ([`EveryInc/compound-engineering-plugin#1919`](https://github.com/EveryInc/compound-engineering-plugin/pull/1919)) and maintainer-verified source reproductions ([`steipete/CodexBar#4829`](https://github.com/steipete/CodexBar/issues/4829)).

---

## 1. Introduction: The Forced Speech Pathology

When a software engineer prompts an LLM coding agent to audit a codebase in a single pass, two failure modes dominate:
1. **Attention decay and premature stopping:** Over a surface of $N$ files or UI states, the agent inspects a subset of obvious files and silently skips the rest.
2. **Surface-pattern false positives:** When the agent encounters a pattern that resembles a vulnerability at the call site (for example, a tagged SQL template literal or a redirect parameter), it flags a high-severity defect without opening the callee helper that sanitizes or parameterizes the input.

A natural remedy is iterative self-refinement (Madaan et al., 2023) or multi-agent debate (Du et al., 2023; Liang et al., 2023): prompting the model across $K$ passes to *"review your previous findings, find what you missed, and refine the plan."*

Yet in our controlled experiments, running an unstructured 4-pass self-refinement loop causes actionable precision to drop from **$49.5\%$ (Pass 1) to $29.0\%$ (Pass 4)**, burying real defects under an average of **$12.2$ false positives and speculative nitpicks per run**.

### 1.1 Formalizing Forced Speech

Let $F_k$ denote the set of active findings after pass $k$, partitioned into true positives $T_k$ and false positives $N_k$ ($F_k = T_k \sqcup N_k$). In an unstructured refinement prompt, each pass $k \ge 2$ samples a prose revision $\Delta_k \sim \pi_\theta(\cdot \mid x, F_{k-1})$.

Because instruction-tuned LLMs are optimized via RLHF to equate helpfulness with substantive token generation, the conditional probability of emitting a no-op turn is near zero:

$$P_{\pi_\theta}(\Delta_k = \emptyset \mid x, F_{k-1}) \approx 0$$

Simultaneously, without an explicit retraction operator and falsification incentive, models exhibit strong **confirmation inertia** on prior claims ($P(\text{retract } f \in N_{k-1}) \ll P(\text{append } f' \in N_k)$). Once the easily discoverable true positives saturate ($|T_k| \to |T^*|$ around Pass 2), the obligation to produce output forces the model to sample lower-probability, speculative claims from the long tail of stylistic preferences and hallucinated edge cases ($\mathbb{E}[|N_k| - |N_{k-1}|] > 0$). Consequently:

$$\lim_{k \to K} \text{Precision}(F_k) = \frac{|T_k|}{|T_k| + \sum_{j=1}^{k} \Delta N_j} \quad \text{decreases monotonically once } \Delta T_k \to 0.$$

We call this phenomenon **the Forced Speech Trap**.

---

## 2. Architecture of Ponder

Ponder resolves the Forced Speech Trap by moving loop control, inventory accounting, and convergence verification out of the LLM prompt and into a deterministic external state machine (`bin/ponder`).

### 2.1 Disk-Anchored Monotonic Coverage Gate (`--scan` & `--strict-scope`)

To prevent premature stopping and Pass-1 inventory omission:
1. **Deterministic Scope Enumeration:** On Pass 1 (`survey`), `ponder units --scan <dir> [--strict-scope]` enumerates tracked files via `git ls-files` (or recursive directory traversal) directly in the CLI. If an agent supplies a custom `units.json` while omitting any file present on disk under `<dir>`, `--strict-scope` rejects the seed with exit code `2` (`stateError`).
2. **Monotonic Counted Denominator:** Let $U_{\text{live}}$ be current units in `units.json` and $U_{\text{ungraded-deleted}}$ be units removed via `unit-delete` without ever receiving a finding. The counted denominator is:

$$U_{\text{counted}} = U_{\text{live}} \cup U_{\text{ungraded-deleted}}, \qquad \text{coverage} = \frac{|\{u \in U_{\text{counted}} : \text{graded}(u)\}|}{|U_{\text{counted}}|}$$

Deleting an ungraded unit does not reduce $|U_{\text{counted}}|$. While $\text{coverage} < 1.00$, `ponder judge` returns **`blocked`** (Rule 1) and `ponder decide stop` is refused by the CLI with exit code `2`.
3. **Path-History Phantom Verification:** An ungraded unit leaves $U_{\text{counted}}$ only if deleted with `"phantom": true`. The engine resolves every `path` the unit has ever carried across `ledger.jsonl` (`unit-seed`, `unit-add`, and all `unit-edit` records). If **any** historical path exists on disk, the entire delta batch is rejected (`exit 2`).

### 2.2 Loss-Function Isomorphism (4 Voices $\leftrightarrow$ 4 Ledger Operations)

Instead of open-ended multi-agent roleplay where personas emit overlapping prose, Ponder enforces a strict bijection between four cognitive perspectives and the four mutation operators on the append-only finding ledger (`ledger.jsonl`):

| Cognitive Voice | Objective / Loss Function | Permitted Ledger Op | Effect on Finding Set $F_k$ |
|---|---|---|---|
| **Dreamer** | Minimize false negatives ($\text{FN}$) | `add` (`unit-add`) | Expands coverage to missed units, states, and cross-module seams |
| **Builder** | Minimize specification ambiguity | `edit` (`unit-edit`) | Rewrites vague recommendations into concrete `file:line` diffs |
| **Empath** | Minimize human/emotional miscalibration | `change` | Re-scores severity and confidence from the lived user experience |
| **Skeptic** | Minimize false positives ($\text{FP}$) | `delete` (`unit-delete`) | Retracts claims falsified by helper implementations or dead-code graphs |

Because `Skeptic` can **only** act by emitting `delete` (or voting `DONE` with zero deltas), Pass 2 always includes an adversarial falsification pass that traces Pass-1 claims into their target helpers and import graphs.

### 2.3 Epistemic Silence Decoupling & Predictive Coding

Ponder decouples **verification participation** from **state mutation**:
- $\text{voices}_k \in \{0, 1, 2, 3, 4\}$ counts how many perspectives recorded an evidence-backed argument in `passes/NN/deliberation.json`.
- $\text{deltaVoices}_k \in \{0, 1, 2, 3, 4\}$ counts how many perspectives emitted at least one mutation in `passes/NN/deltas.jsonl`.

Before each pass, the agent must also record a churn forecast $\hat{c}_k \in [0, 1]$ (`ponder predict --churn`), which is scored at `ponder judge` as predictive-coding surprise:

$$\text{surprise}_k = |\hat{c}_k - c_k|, \qquad c_k = \frac{|\Delta_k^{\text{revising}}|}{|F_k^{\text{live}}|}$$

Under Verdict Rule 6, a session achieves **`stop (converged)`** when two consecutive passes satisfy:

$$\text{coverage}_k = 1.00, \quad \text{novelty}_k < 0.05, \quad \text{churn}_k < 0.10, \quad \text{thrash}_k \le 0.25, \quad \text{voices}_k \ge 3, \quad \text{confidenceFloor}_k = 0$$

When a finding set is accurate and complete, all four voices inspect the evidence ($\text{voices}_k = 4$) and emit zero deltas ($\text{deltaVoices}_k = 0, c_k = 0.00$). Silence after full verification is rewarded as convergence rather than punished as inactivity.

---

## 3. Empirical Evaluation

### 3.1 Controlled Multi-Trial Benchmark ($K = 5$ Stochastic Runs)

We evaluated five prompting conditions across $K = 5$ independent stochastic trials (`studies/one-shot-vs-ponder/`) against a reproducible multi-file web application (`studies/head-to-head-benchmark/target-app/`) containing **8 ground-truth defects (`GT-1`..`GT-8`)** and **3 adversarial traps**:
- `TRAP-DECOY-SQLI`: A tagged template query `sql\`SELECT ... WHERE id = \${memberId}\`` that looks like SQL injection at the call site but compiles into parameterized `$1, $2` bindings inside `src/lib/safe-query.js`.
- `TRAP-ORPHAN`: A legacy modal (`src/screens/legacy-v1-modal.jsx`) with accessibility violations but **zero importers** anywhere in the repository.
- `TRAP-PHANTOM`: A route entry referencing `src/screens/legacy-export.jsx`, which does not exist on disk.

| Condition ($K = 5$ Trials) | Recall ($\mu \pm \sigma$) | Precision ($\mu \pm \sigma$) | Cross-Run Stability ($J$) | Mean False Positives | Human Prompts | Dev Time Cost | Mean Output Tokens |
|---|---:|---:|---:|---:|---:|---:|---:|
| **1. Standard 1-Prompt (`Ponder OFF`)** | $40.0\% \pm 9.4\%$ | $49.5\% \pm 8.7\%$ | $0.51$ | $3.2$ | $5.8$ | $92.8\text{ min}$ | $1,490$ |
| **2. `/caveman` 1-Prompt (`Ponder OFF`)** | $40.0\% \pm 9.4\%$ | $49.5\% \pm 8.7\%$ | $0.51$ | $3.2$ | $5.8$ | $92.8\text{ min}$ | $387\ (-74\%)$ |
| **3. Unstructured 4-Pass (`Forced Speech`)** | $62.5\% \pm 7.9\%$ | $29.0\% \pm 1.7\%$ | $0.86$ | $12.2$ | $8.2$ | $205.3\text{ min}$ | $6,954$ |
| **4. Ponder 1-Prompt (`Ponder ON`)** | **$97.5\% \pm 5.0\%$** | **$100.0\% \pm 0.0\%$** | **$0.95$** | **$0.0$** | **$1.0$** | **$13.5\text{ min}$** | $5,438$ |
| **5. Ponder + Internal Caveman Deltas** | **$97.5\% \pm 5.0\%$** | **$100.0\% \pm 0.0\%$** | **$0.95$** | **$0.0$** | **$1.0$** | **$13.5\text{ min}$** | **$2,376\ (-56\%)$** |

### 3.2 Two Orthogonal Axes of Efficiency: Syntactic Brevity vs. Epistemic Silence

Comparing Condition 2 (`/caveman` standalone), Condition 4 (`Ponder` standalone), and Condition 5 (`Ponder + Internal Caveman Deltas`) isolates two distinct axes of LLM efficiency:
- **Syntactic brevity (`/caveman` alone)** compresses surface prose by $74\%$ ($1,490 \to 387$ tokens) but performs zero falsification. It still reports all $3.2$ false positives in five terse words (`"team-actions.js:15 SQLi. Parameterize query."`), saving $0$ minutes of engineering debugging time.
- **Epistemic silence (`Ponder`) + terse internal ledger notation (`Hybrid`)** uses compact causal strings (`"safe-query.js:5 binds $1 -> SQLi claim false -> retract"`) inside machine-to-machine `deliberation.json` and `deltas.jsonl` artifacts while rendering human-facing `report.md` in full prose. This reduces Ponder's token footprint by **56%** ($5,438 \to 2,376$ tokens) while maintaining $100.0\%$ precision ($0.0$ false positives).

### 3.3 In-the-Wild Open-Source Audits (72,400+ Combined GitHub Stars)

To evaluate Ponder outside synthetic benchmarks, we executed 4-pass `architecture` lens sessions across three major open-source AI repositories (`studies/ecosystem-audits/`). In all three repositories, Pass 1 raised a plausible security finding that **Pass-2 `Skeptic` falsified and retracted (`delete`)** after reading the defense helper, while the surviving `must` and `should` findings were confirmed upstream:

1. **[`EveryInc/compound-engineering-plugin`](https://github.com/EveryInc/compound-engineering-plugin) (`25.7k` stars)**:
   - **Pass-2 `Skeptic` Falsification:** Retracted a Pass-1 manifest path-traversal alarm after verifying `resolveWithinRoot` (`src/parsers/claude.ts:263-270`).
   - **Surviving Verified Defects:** `codex.ts` and `pi.ts` sync writers unlinking user symlinks on prompts/extensions (`fs.lstat` vs. `fs.stat`), and unbounded `.bak.<timestamp>` backup accumulation in `.opencode/commands/` causing duplicate command registration.
   - **Upstream Outcome:** Reported in [Issue #1916](https://github.com/EveryInc/compound-engineering-plugin/issues/1916); companion fix [PR #1919](https://github.com/EveryInc/compound-engineering-plugin/pull/1919) was reviewed by maintainer `@tmchow`, expanded with 6 regression tests (`4,723` passing tests), and **merged into `main`**.
2. **[`steipete/CodexBar`](https://github.com/steipete/CodexBar) (`22.9k` stars)**:
   - **Pass-2 `Skeptic` Falsification:** Retracted a Pass-1 credential-file symlink/permission race alarm after verifying `0700` staging directory creation, `O_EXCL | O_CREAT` (`0600`), and atomic `rename(2)`.
   - **Surviving Verified Defects:** `CodexBarClaudeWatchdog` post-spawn `setpgid` `EACCES` race and unguarded `kill(-pgid)` capable of signaling the watchdog's own process group, plus lost child exit status on orphan cleanup.
   - **Upstream Outcome:** [Issue #4829](https://github.com/steipete/CodexBar/issues/4829) was verified by the repository's automated triage system (`clawsweeper`) and awarded **`issue-rating: 🦞 diamond lobster`** (`clawsweeper:source-repro`, `clawsweeper:fix-shape-clear`, `clawsweeper:queueable-fix`).
3. **[`coleam00/Archon`](https://github.com/coleam00/Archon) (`23.8k` stars)**:
   - **Pass-2 `Skeptic` Falsification:** Retracted a Pass-1 login `rd` open-redirect alarm after verifying `isSafeRedirect` (`auth-service/server.js:62-65`).
   - **Surviving Verified Defects:** Double `decodeURIComponent(rd)` throwing unhandled `URIError` (`HTTP 500`), static `signCookie('authenticated')` cookie without server-side expiry or credential rotation binding, and an SSE `liveWritePending` replay race.
   - **Upstream Outcome:** Filed with runnable reproductions in [Issue #5256](https://github.com/coleam00/Archon/issues/5256) and companion fix [PR #5257](https://github.com/coleam00/Archon/pull/5257).

---

## 4. Reproducing All Results

Every session ledger, pass metric, and evaluation script is committed to this repository and runs with zero external dependencies on Node.js $\ge 18$:

```sh
# 1. Run the 101-check specification conformance suite
./test/conformance.sh

# 2. Run the unit and deterministic scope-scan verification tests
node --test test/*.test.mjs

# 3. Reproduce the controlled head-to-head benchmark (Single-Shot vs. Self-Refine vs. Ponder)
node studies/head-to-head-benchmark/evaluate.mjs

# 4. Reproduce the K=5 stochastic temperature-variance & /caveman hybrid study
node studies/one-shot-vs-ponder/evaluate-trials.mjs
```

---

## 5. Citation

```bibtex
@software{odonnell2026ponder,
  author       = {O'Donnell, Quinn},
  title        = {{Ponder: Epistemic Silence and Loss-Function Isomorphism for Convergent Multi-Pass AI Deliberation}},
  year         = {2026},
  url          = {https://github.com/Quinnod345/ponder},
  note         = {Zero-dependency deliberation state machine and empirical benchmark suite}
}
```
