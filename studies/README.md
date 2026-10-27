# Ponder Empirical Studies & Benchmarks

This directory contains empirical evaluations of **Ponder** against standard single-pass LLM review and unstructured multi-pass self-refinement (`Self-Refine` / `Reflexion`), alongside field telemetry from four production deployments.

| Study | Type | Subject | Key Question Answered |
|---|---|---|---|
| **[1. Head-to-Head Benchmark](#1-controlled-head-to-head-benchmark)** ([`head-to-head-benchmark/`](head-to-head-benchmark/)) | Controlled experiment with planted ground truth | Full-stack SaaS app (`target-app/`) with 8 planted bugs + 3 adversarial traps | How do **Single-Shot Review**, **4-Pass Unstructured Self-Refine**, and **4-Pass Ponder** compare on recall, precision, false-positive retraction, and late-pass hallucination? |
| **[2. Production Field Studies](field-studies.md)** ([`field-studies.md`](field-studies.md)) | Empirical telemetry from 4 production runs | 228-screen SaaS UI, 154-surface security audit, 16-journey emotional/privacy audit, 37-unit design sweep | How does Ponder behave at scale on real codebases, and what classes of bugs are caught *only* after Pass 1? |

---

## Why Standard LLM Reviews Fail

When an AI coding agent is asked to review a codebase or plan a complex change, it fails in three predictable ways:

1. **Coverage Decay & Silent Omission (Single-Shot Failure):**
   On any non-trivial surface, an agent inspects the most obvious route files, grades the first handful thoroughly, skims the rest, and misses unrouted state variants (`error` branches, conditional wizards) and cross-file contracts.
2. **Sycophancy & Un-Retracted False Positives (Missing Skeptic Voice):**
   When an initial pass flags a plausible-looking pattern—such as template-literal SQL interpolation (`sql\`SELECT ... \${id}\``) that is actually parameterized by a tagged-template helper, or low-contrast CSS inside an unimported dead file—unstructured refinement passes almost never open the helper or check the import graph to retract their own earlier claim.
3. **Performative Churn & Hallucination Under Iteration (Missing Epistemic Silence):**
   Standard LLMs are trained to equate helpfulness with token generation. When prompted to *"review and refine your findings again"* on Pass 3 or Pass 4 after the real defects have already been found, an unstructured loop cannot stay quiet. Instead, it manufactures speculative nitpicks (`React.memo` everywhere, BEM class renaming, dark-mode contexts) or hallucinates defects in routes it never opened.

Ponder addresses all three through **disk-backed unit enumeration (`coverage < 1.0` blocks stopping)**, **loss-function isomorphism (`Skeptic` = `delete`, `Builder` = `edit`, `Dreamer` = `add`, `Empath` = `change`)**, and **epistemic silence (`voices` vs. `deltaVoices`, where a 4-voice, 0-delta pass is the primary proof of convergence)**.

---

## 1. Controlled Head-to-Head Benchmark

All files, corpus code, raw outputs, and evaluation scripts live in [`head-to-head-benchmark/`](head-to-head-benchmark/).

### Reproduce the Benchmark

Zero npm dependencies are required. From the repository root:

```sh
# Evaluate the committed runs and verify the Ponder session against its append-only ledger:
node studies/head-to-head-benchmark/evaluate.mjs

# Or re-run the 4-pass Ponder engine from scratch and re-evaluate:
node studies/head-to-head-benchmark/run_ponder_benchmark.mjs
node studies/head-to-head-benchmark/evaluate.mjs
```

### Target Corpus & Planted Ground Truth ([`ground-truth.json`](head-to-head-benchmark/ground-truth.json))

The target application ([`head-to-head-benchmark/target-app/`](head-to-head-benchmark/target-app/)) is a multi-screen team-checkup SaaS app containing **8 planted ground-truth defects (`GT-1`–`GT-8`)** and **3 adversarial review traps (`TRAP-*`)**:

#### Ground-Truth Defects (`GT-1`–`GT-8`)
- **`GT-1` (State-Variant Dead-End — `must`):** In [`src/screens/dashboard.jsx:15-20`](head-to-head-benchmark/target-app/src/screens/dashboard.jsx), `.catch()` sets `error` without calling `setIsLoading(false)`. Because `if (isLoading)` at line 23 precedes `if (error)` at line 27, API failures pin the dashboard in a permanent loading skeleton and the error banner is unreachable dead code.
- **`GT-2` (Unrouted Surface UX — `should`):** In [`src/screens/dashboard.jsx:29-37`](head-to-head-benchmark/target-app/src/screens/dashboard.jsx), a state-switched first-run wizard (`currentStep === 'welcome'`, invisible to route-only enumeration) asks new users for `"Priority (Low / Medium / High)"` and `"Internal schema version"` before they have seen the product.
- **`GT-3` (Cross-Surface Privacy Breach — `must`):** [`src/screens/survey.jsx:9-13`](head-to-head-benchmark/target-app/src/screens/survey.jsx) promises participants that leadership only sees a combined reading once at least **3 teammates** complete the survey. [`src/screens/results.jsx:8-14`](head-to-head-benchmark/target-app/src/screens/results.jsx) unlocks at `completedCount >= 1`, exposing the first respondent's private answers as the "company average."
- **`GT-4` (Emotional Trust & Credential Leak — `must`):** [`src/screens/invitations.jsx:18-26`](head-to-head-benchmark/target-app/src/screens/invitations.jsx) prints each participant's `individualScore%` next to their name and renders their raw `/survey/${p.surveyHash}` bearer link in the table DOM.
- **`GT-5` (Dead-End Checkout Bug — `must`):** [`src/screens/billing.jsx:5-9`](head-to-head-benchmark/target-app/src/screens/billing.jsx) hardcodes `plan: 'business'` inside `startUpgrade(selectedTier)`, making the highlighted Pro tier impossible to purchase.
- **`GT-6` (Bare Empty State — `should`):** [`src/screens/billing.jsx:29-31`](head-to-head-benchmark/target-app/src/screens/billing.jsx) renders a bare `<div>No invoices</div>` with no explanation of when invoices appear.
- **`GT-7` (Cross-Tenant IDOR — `must`):** [`src/actions/team-actions.js:14-21`](head-to-head-benchmark/target-app/src/actions/team-actions.js) verifies campaign ownership at line 5, but queries `SELECT id, email FROM members WHERE id = ${memberId}` without filtering `tenant_id = currentUser.tenantId`, allowing cross-tenant member attachment.
- **`GT-8` (Unbounded 2N Query Loop — `should`):** [`src/actions/team-actions.js:14-21`](head-to-head-benchmark/target-app/src/actions/team-actions.js) executes a sequential `SELECT` and `INSERT` per `memberId` inside a `for...of` loop with no batching, deduplication, or array cap.

#### Adversarial Review Traps (`TRAP-*`)
- **`TRAP-DECOY-SQLI` (False-Positive SQLi Decoy):** [`src/actions/team-actions.js`](head-to-head-benchmark/target-app/src/actions/team-actions.js) uses a tagged template `sql\`SELECT ... WHERE id = \${memberId}\``. A superficial reviewer flags this as SQL injection. Opening [`src/lib/safe-query.js:5-14`](head-to-head-benchmark/target-app/src/lib/safe-query.js) proves `sql` compiles template values into parameterized `$1, $2` bindings.
- **`TRAP-ORPHAN` (Unimported Dead Code):** [`src/screens/legacy-v1-modal.jsx`](head-to-head-benchmark/target-app/src/screens/legacy-v1-modal.jsx) contains low-contrast `#ccc` text on `#fff`, but has **zero importers** anywhere in `src/`. Grading it as an actionable UI bug wastes engineering time on dead code.
- **`TRAP-PHANTOM` (Phantom Route in Router):** [`src/router.js:9`](head-to-head-benchmark/target-app/src/router.js) lists `{ path: '/settings/legacy-export', component: 'src/screens/legacy-export.jsx' }`, a file that **does not exist on disk**.

---

### Head-to-Head Results

| Metric | Single-Shot (1 Pass) | Unstructured Self-Refine (4 Passes) | Ponder (4 Passes) |
|---|---:|---:|---:|
| **Ground-Truth Recall (`GT-1`–`GT-8`)** | `3/8` (**37.5%**) | `5/8` (**62.5%**) | `8/8` (**100.0%**) |
| **Actionable Precision (`TP / Reported`)** | `3/6` (**50.0%**) | `5/17` (**29.4%**) | `8/8` (**100.0%**) |
| **False Positives in Final Plan** | `3` | `12` | **`0`** |
| **`TRAP-DECOY-SQLI` (`safe-query.js`)** | Failed (kept false SQLi) | Failed (kept across 4 passes) | **Passed** (Skeptic retracted `f-0009` on Pass 2) |
| **`TRAP-ORPHAN` (`legacy-v1-modal.jsx`)** | Failed (graded dead file) | Failed (kept across 4 passes) | **Passed** (Skeptic retracted `f-0008` + removed unit) |
| **`TRAP-PHANTOM` (`legacy-export.jsx`)** | Failed (hallucinated spinner bug) | Failed (kept hallucination) | **Passed** (`phantom: true` → `verified-missing`) |
| **Pass 3–4 Performative Noise** | N/A (1 pass) | `9` invented low-signal items | **`0`** (Pass 4: 4 voices argued, 0 deltas emitted) |
| **Ledger & Evidence Verification** | None | None | **100% reconciled (`ponder verify` exit `0`)** |
| **Final Session Status** | Unverified opinion | Drifting / un-converged | **`converged` (Rule 6 — 0 overrides)** |

### Pass-by-Pass Trajectory in Ponder ([`runs/ponder/.ponder/benchmark-app/report.md`](head-to-head-benchmark/runs/ponder/.ponder/benchmark-app/report.md))

| Pass | Coverage | Novelty | Churn | Thrash | Surprise | Voices (`argued` / `delta`) | Engine Advice | What Happened |
|---:|---:|---:|---:|---:|---:|---|---|---|
| **1** | `0.70` | `—` | `—` | `—` | `—` | `4 / 1` | **`blocked (coverage)`** | Seeded 10 units and graded 7. Empath promoted `f-0004` (invitations score leak) from `should` to `must`. Engine blocked stopping because `screen.dashboard.error`, `screen.results`, and `screen.legacy-export` were ungraded. |
| **2** | `1.00` | `0.18` | `0.73` | `0.00` | `0.18` | `4 / 3` | `continue (default)` | **Skeptic** opened `safe-query.js` and retracted the SQLi decoy (`f-0009`), proved `legacy-v1-modal.jsx` had 0 importers (`f-0008` retracted + `unit-delete`), and filed `phantom: true` on `legacy-export.jsx` (engine verified missing on disk). **Dreamer** graded the two missing units, uncovering the unreachable dashboard error state (`f-0012`) and the `N=1` results privacy breach (`f-0013`). |
| **3** | `1.00` | `0.00` | `0.09` | `0.00` | `0.00` | `4 / 1` | `continue (default)` | **First quiet pass:** Skeptic, Dreamer, and Empath verified all 11 open findings and emitted `0` deltas. **Builder** made 1 surgical edit on `f-0011` (`Set` deduplication + batch cap of 200). Predicted churn `0.09` matched actual churn `0.09` (`surprise = 0.00`). |
| **4** | `1.00` | `0.00` | `0.00` | `0.00` | `0.00` | `4 / 0` | **`stop (converged)`** | **Epistemic silence:** All 4 voices spoke in `deliberation.json` confirming every finding and line citation held (`voices = 4`), and emitted `0` deltas (`deltaVoices = 0`, `churn = 0.00`). Two consecutive passes with `novelty < 0.05` and `churn < 0.10` earned automatic Rule-6 convergence. |

---

## 2. Production Field Studies ([`field-studies.md`](field-studies.md))

See **[`studies/field-studies.md`](field-studies.md)** for full convergence tables and case analyses from four production Ponder runs:

1. **Field Study 1 — Exhaustive Surface Discovery (228 Units vs. 30 Route Globs):** How Ponder's 4-sweep enumeration (`routes` + `unrouted components` + `state variants` + `chrome`) uncovered 228 distinct UI units in a Next.js SaaS application where a standard route glob saw only 30 files—catching a `P0` state bug where a 60-second background poll silently wiped mid-edit user work.
2. **Field Study 2 — 154-Surface Security & Efficiency Audit:** How multi-pass deliberation across 154 API routes, server actions, and webhook handlers caught a webhook idempotency bug that permanently dropped legitimate retries after transient DB errors, and how the **Skeptic** voice retracted false-positive CSRF and rate-limit claims on Pass 2.
3. **Field Study 3 — First-Time User & Emotional/Privacy Audit (`product` + `ui` lenses):** How stepping into the shoes of an invited participant (`Empath` + `Dreamer`) exposed a three-way contradiction in anonymity thresholds (`>=5` on landing copy, `>=3` in the checkup header, `>=1` in the admin results API).
4. **Field Study 4 — 37-Unit Interactive Motion & Portfolio Deliberation:** How predictive coding (`surprise` dropping from `0.04` → `0.02` → `0.00`) and thrash detection (`0.00` across 4 passes) allowed 4 voices to converge on an exact engineering plan without over-engineering or oscillating.
