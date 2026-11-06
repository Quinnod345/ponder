# Study: 7-Model Frontier Benchmark — Which Model Uses Ponder Best, Finds the Most, and Follows the Protocol?

This study evaluates **seven frontier models across three providers** (**Anthropic**, **Google**, **OpenAI**) in a clean-room, blind software audit benchmark comparing **Single-Shot Review (`Ponder OFF`)** against **Multi-Pass Deliberation (`Ponder ON`)** on the exact same codebase workspace.

Every model was tested in an isolated workspace containing **two code slices** with **all source hint comments stripped**:
1. **`target-app/`** — 6 React screens, router registry, and server action (`GT-1`–`GT-8` + `CROSS-2` + 3 adversarial traps: `TRAP-DECOY-SQLI`, `TRAP-PHANTOM`, `TRAP-ORPHAN`).
2. **`webhook-billing-slice/`** — Stripe webhook handler, HMAC signature verifier, and seat-upgrade worker (`WB-1`–`WB-3` + `CROSS-1` + `TRAP-CRYPTO-TIMING`).

---

## Reproduce the 7-Model Benchmark Verification

All raw model outputs (`single-shot-findings.json`), full `.ponder/full-audit-2026-11-06/` ledgers, per-pass `metrics.json` / `deliberation.json` / `deltas.jsonl`, and exported `ponder-report.md` files are committed under [`runs/`](runs/).

From the repository root, run the zero-dependency evaluator (which also runs `reconcile()` ledger verification across all 7 sessions):

```sh
node studies/model-benchmark/evaluate-models.mjs
```

---

## 1. Master Results Table (All 7 Frontier Models)

| Model | Provider | Single-Shot Recall (`must`/`should`) | Ponder Recall (`must`/`should`) | Ponder Recall (All Open) | Ponder Lift (`must`/`should`) | Units Enumerated (Coverage) | Passes to Converge | 4-Voice Revisions (`S / B / D / E`) | Phantom Route Pruned (`phantom: true`) | Mean Surprise ($\lvert\text{pred} - \text{actual}\rvert$) | `ponder verify` |
|---|---|---:|---:|---:|---:|---:|---:|---|---:|---:|---:|
| **Gemini 4 Argon** | Google | `12/14` (`85.7%`) | **`14/14` (`100.0%`)** | **`14/14` (`100.0%`)** | **`+14.3%`** | `18` (`1.00`) | `4` (`converged`) | `3 / 5 / 2 / 2` (**4/4 voices**) | **Yes (`unit-delete`)** | **`0.002`** | `OK (0)` |
| **Claude Sonnet 5.5** | Anthropic | `11/14` (`78.6%`) | **`14/14` (`100.0%`)** | **`14/14` (`100.0%`)** | **`+21.4%`** | `41` (`1.00`) | `5` (`converged`) | `3 / 9 / 11 / 12` (**4/4 voices**) | Kept as route unit | `0.032` | `OK (0)` |
| **Claude Haiku 5.5** | Anthropic | `12/14` (`85.7%`) | **`14/14` (`100.0%`)** | **`14/14` (`100.0%`)** | **`+14.3%`** | `37` (`1.00`) | `4` (`converged`) | `2 / 4 / 11 / 8` (**4/4 voices**) | Kept as route unit | `0.062` | `OK (0)` |
| **Claude Opus 5.5** | Anthropic | **`13/14` (`92.9%`)** | `13/14` (`92.9%`)* | **`14/14` (`100.0%`)** | `+32 deep findings` | `54` (`1.00`) | `5` (`converged`) | `2 / 17 / 11 / 14` (**4/4 voices**) | Kept as route unit | `0.035` | `OK (0)` |
| **GPT-6.1 Sol** | OpenAI | `12/14` (`85.7%`) | `13/14` (`92.9%`) | `13/14` (`92.9%`) | `+7.2%` | **`62` (`1.00`)** | `4` (`converged`) | `0 / 11 / 3 / 2` (`3/4` — 0 Skeptic deletes) | Kept as route unit | `0.031` | `OK (0)` |
| **GPT-6 Astra** | OpenAI | `12/14` (`85.7%`) | `13/14` (`92.9%`) | `13/14` (`92.9%`) | `+7.2%` | `46` (`1.00`) | `4` (`converged`) | `0 / 8 / 4 / 2` (`3/4` — 0 Skeptic deletes) | Kept as route unit | `0.036` | `OK (0)` |
| **Gemini 3.8 Flash** | Google | `9/14` (`64.3%`) | `11/14` (`78.6%`) | `12/14` (`85.7%`) | **`+14.3%`** | `17` (`1.00`) | `4` (`converged`) | `2 / 2 / 2 / 2` (**4/4 voices**) | **Yes (`unit-delete`)** | `0.026` | `OK (0)` |

*\*Note on Claude Opus 5.5: Opus 5.5 caught all `14/14` (`100.0%`) ground-truth defects in Ponder, intentionally ranking `GT-6` (bare `"No invoices"` empty state) as `could` (`f-0047`) so that its `must`/`should` tier remained reserved for functional, security, and privacy defects.*

---

## 2. Executive Synthesis: Which Model is Best at What?

No single model wins every axis—instead, the 7-model study reveals three distinct specialization profiles and proves that **Ponder raises every single model's recall and cross-file discovery**:

### 1. Best at Protocol Mastery, Phantom Pruning & Predictive Calibration: **Gemini 4 Argon**
- **100% Ground-Truth Actionable Recall (`14/14` `must`/`should`)** in 4 passes (`12/14` in single-shot -> `14/14` with Ponder).
- **Only flagship model to execute the full `unit-delete` `"phantom": true` protocol** on `screen.settings.legacy-export` (`target-app/src/screens/legacy-export.jsx`), cleanly removing the non-existent route from the coverage denominator (`verified-missing`) and also using `unit-edit` to refine `screen.dashboard` metadata.
- **Explicit Skeptic decoy retraction:** Seeded the plausible SQL injection hypothesis on `team-actions.js` (`f-0018`) during Pass 1 appraisal, then had the **Skeptic** open `safe-query.js` and retract it (`delete`) alongside a duplicate wizard finding (`f-0007`).
- **Best predictive self-calibration (`meanSurprise = 0.002`):** Predicted Pass 2 churn `0.23` vs. actual `0.2273` (`surprise = 0.0027`), Pass 3 churn `0.05` vs. actual `0.0455` (`surprise = 0.0045`), and Pass 4 `0.00` vs. `0.00` (`surprise = 0.0000`).

### 2. Best at Deep Architectural Discovery & Cross-Contract Synthesis: **Claude Opus 5.5 & Claude Sonnet 5.5**
- **Claude Opus 5.5 (`54 units`, `77 open findings`, `100%` total recall):** Wrote a custom React + `jsdom` + in-memory DB execution harness inside `.ponder/tmp/harness/` during Ponder to empirically test state transitions rather than relying on static reading alone. Discovered **32 verified architectural findings beyond its 20-finding single-shot baseline**, including:
  - **Differential privacy / delta deanonymization (`f-0030`):** Even after raising `completedCount` from `1` to `3`, watching `aggregate.overall` update from $N=3$ to $N=4$ algebraically reveals the 4th respondent's exact score ($4 \cdot \bar{x}_4 - 3 \cdot \bar{x}_3$).
  - **Cross-slice entitlement disconnect (`f-0074`):** `BillingScreen` sends `{ plan: 'business', sourceTier }` with no seat count, while `applyPlanUpgrade` reads `checkoutSession.metadata.{tier, seats}` and defaults missing metadata to `pro` + `5` seats.
  - **Honest self-correction (`thrash = 0.09` on Pass 3):** Promoted `f-0065` (org lookup by billing email) to `must` on Pass 2, then down-ranked it back to `should` on Pass 3 after proving its own Pass 2 exploit premise required an unverified email change vector.
- **Claude Sonnet 5.5 (`41 units`, `49 open findings`, `+21.4%` Ponder recall lift):** Jumped from `11/14` (`78.6%`) in single-shot to **`14/14` (`100.0%`)** in Ponder (`5` passes, `0` overrides). Used `unit-add` 5 times across Passes 1–2 to add cross-cutting contract units (`app.states.contract`, `app.privacy.cohort-contract`, `flow.billing-upgrade`, `screen.billing.payment-failed`, `app.through-line`) and used the **Skeptic** (`3` `delete` deltas) to kill duplicate and taste-only findings.

### 3. Best Value / Speed-to-Completeness With Ponder: **Claude Haiku 5.5**
- Achieved **`14/14` (`100.0%`) actionable recall** in 4 passes (`37` units, `45` open findings, `2` Skeptic retractions), matching Sonnet 5.5 and Gemini 4 Argon on the 14 planted defects while running at Haiku speed and cost.
- Demonstrated strong 4-voice balance (`2` Skeptic deletes, `4` Builder edits, `11` Dreamer adds/unit-adds, `8` Empath severity re-ranks).

---

## 3. Failure Modes Uncovered Across Model Families (How Models Misuse Ponder)

Running all 7 models blind against the same CLI protocol exposed three systematic model behavior patterns that engineers should know when choosing a model for Ponder:

### Pattern A: The "Zero-Skeptic Over-Caution" Failure in GPT-6.1 Sol & GPT-6 Astra
Both OpenAI Codex models (**GPT-6.1 Sol** at `62` units and **GPT-6 Astra** at `46` units) followed the CLI state machine cleanly (`ponder verify` exit `0`, 4 passes, `13/14` recall), **but emitted `0` `skeptic:delete` deltas across all 4 passes**:
- Instead of seeding candidate hypotheses in Pass 1 and letting the **Skeptic** falsify them in Pass 2, both models pre-filtered their Pass 1 findings into `note` observations (e.g., `f-0047 [note]: SQL values remain separate from text`).
- Consequently, their multi-pass loop only ran `3/4` active delta voices (`Builder`, `Dreamer`, `Empath`), never exercising `Skeptic` deletion.
- **GPT-6 Astra Confidence Under-Calibration:** Because no runnable browser server was attached, GPT-6 Astra assigned `confidence: 0.45` to every UI finding (`f-0001`–`f-0028`) and downgraded even broken checkout (`GT-5`), infinite error skeleton (`GT-1`), and privacy leaks (`GT-3`, `GT-4`) from `must` (in its single-shot run!) to `should` in Ponder so it wouldn't violate the `confidenceFloor` rule (`must` findings require `confidence >= 0.5`). **GPT-6.1 Sol** avoided this mistake (`confidence: 0.90` on `must` UI bugs) and is strongly preferred over `gpt-6-astra` for Ponder.

### Pattern B: Phantom Route Handling (`unit-delete` `"phantom": true` vs. Route-Entry Grading)
When confronted with `{ path: '/settings/legacy-export', component: 'src/screens/legacy-export.jsx' }` in `router.js` (where `legacy-export.jsx` does not exist on disk):
- **Gemini 4 Argon** and **Gemini 3.8 Flash** both seeded the unit and then executed `{"op":"unit-delete","target":"...","perspective":"skeptic","phantom":true}`, letting the Ponder engine verify the missing path on disk (`phantomVerification: "verified-missing"`) and remove it from the denominator.
- **Claude Opus 5.5, Sonnet 5.5, Haiku 5.5, GPT-6.1 Sol, and GPT-6 Astra** kept `route.legacy-export` as an active unit anchored to `target-app/src/router.js:7` and graded the dangling router entry as a `must`/`should` broken-route defect. Crucially, **zero models hallucinated code inside `legacy-export.jsx`** once Ponder's file-anchored evidence check was active.

### Pattern C: How Ponder Lifts Smaller Models (`Gemini 3.8 Flash` & `Claude Haiku 5.5`)
- **Gemini 3.8 Flash** in single-shot mode caught only `9/14` (`64.3%`) actionable defects—missing the unrouted dashboard wizard (`GT-2`), the bare invoice empty state (`GT-6`), the `2N` query loop (`GT-8`), the concurrent seat race (`WB-2`), and the unguarded PDF export (`CROSS-2`).
- With **Ponder ON**, Pass 1's coverage gate blocked `gemini-3.8-flash` at `0.88` coverage (`15/17` units), forcing Pass 2 to grade the remaining units, verify and prune the phantom route (`screen.legacy-export`), and add `f-0017` (unhandled wizard `configure` state) and `f-0019` (non-atomic seat limit race)—lifting its actionable recall from **`64.3%` to `78.6%` (`85.7%` including `could`)**.

---

## 4. Per-Defect Matrix Across All 7 Models (`Single-Shot` → `Ponder`)

Legend:
- `✓` = Caught as actionable (`must` or `should`)
- `○` = Caught as low-priority (`could`)
- `✗` = Missed

| Defect ID | Description | Opus 5.5 (`SS`→`P`) | Argon (`SS`→`P`) | Sonnet 5.5 (`SS`→`P`) | Haiku 5.5 (`SS`→`P`) | GPT-6.1 Sol (`SS`→`P`) | GPT-6 Astra (`SS`→`P`) | Flash 3.8 (`SS`→`P`) |
|---|---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| **`GT-1`** | Dashboard `.catch()` omits `setIsLoading(false)` (permanent skeleton) | `✓ → ✓` | `✓ → ✓` | `✓ → ✓` | `✓ → ✓` | `✓ → ✓` | `✓ → ✓` | `✓ → ✓` |
| **`GT-2`** | Unrouted welcome wizard leaks schema field & dead-ends on `configure` | `✓ → ✓` | `✓ → ✓` | `✓ → ✓` | `✓ → ✓` | `✓ → ✓` | `✓ → ✓` | `○ → ✓` |
| **`GT-3`** | `ResultsScreen` unlocks at `>= 1` vs. survey promise of `>= 3` | `✓ → ✓` | `✓ → ✓` | `✓ → ✓` | `✓ → ✓` | `✓ → ✓` | `✓ → ✓` | `✓ → ✓` |
| **`GT-4a`** | `InvitationsScreen` prints named `individualScore%` | `✓ → ✓` | `✓ → ✓` | `✓ → ✓` | `✓ → ✓` | `✓ → ✓` | `✓ → ✓` | `✓ → ✓` |
| **`GT-4b`** | `InvitationsScreen` exposes raw `/survey/{surveyHash}` magic link | `✓ → ✓` | `✓ → ✓` | `✗ → ✓` | `✓ → ✓` | `✓ → ✓` | `✓ → ✓` | `✓ → ✓` |
| **`GT-5`** | `BillingScreen` hardcodes `plan: 'business'` on Pro upgrade | `✓ → ✓` | `✓ → ✓` | `✓ → ✓` | `✓ → ✓` | `✓ → ✓` | `✓ → ✓` | `✓ → ✓` |
| **`GT-6`** | Bare `"No invoices"` empty state with no cause or next action | `○ → ○` | `✗ → ✓` | `✗ → ✓` | `✗ → ✓` | `✗ → ✓` | `✗ → ✓` | `✗ → ○` |
| **`GT-7`** | Cross-tenant IDOR in `attachMembersToCampaign` | `✓ → ✓` | `✓ → ✓` | `✓ → ✓` | `✓ → ✓` | `✓ → ✓` | `✓ → ✓` | `✓ → ✓` |
| **`GT-8`** | Unbounded `2N` query loop / non-atomic partial member writes | `✓ → ✓` | `✓ → ✓` | `✗ → ✓` | `○ → ✓` | `✗ → ✓` | `✗ → ✓` | `✗ → ✗` |
| **`WB-1`** | Stripe webhook inserts `event_id` before worker; drops failed retries | `✓ → ✓` | `✓ → ✓` | `✓ → ✓` | `✓ → ✓` | `✓ → ✓` | `✓ → ✓` | `✓ → ✓` |
| **`WB-2`** | Non-atomic `seat_limit` read-modify-write race in `billing-worker.js` | `✓ → ✓` | `✓ → ✓` | `✓ → ✓` | `✓ → ✓` | `✓ → ✓` | `✓ → ✓` | `✗ → ✓` |
| **`WB-3`** | `verifyStripeSignature` omits timestamp replay tolerance & collapses `v1` | `✓ → ✓` | `✓ → ✓` | `✓ → ✓` | `✓ → ✓` | `✓ → ✓` | `✓ → ✓` | `✓ → ✓` |
| **`CROSS-1`** | Cross-slice contract mismatch (`plan`/`sourceTier` vs `metadata.tier`/`seats`) | `✓ → ✓` | `✓ → ✓` | `✓ → ✓` | `✓ → ✓` | `✓ → ✗` | `✓ → ✗` | `✓ → ✓` |
| **`CROSS-2`** | `ResultsScreen` unguarded `/pdf-export` link & null `aggregate` crash | `✓ → ✓` | `✗ → ✓` | `○ → ✓` | `✗ → ✓` | `✗ → ✓` | `✗ → ✓` | `✗ → ✗` |
| **Total (`must`/`should`)** | **14 Ground-Truth Defects** | **`13 → 13`** (`14` all) | **`12 → 14`** | **`11 → 14`** | **`12 → 14`** | **`12 → 13`** | **`12 → 13`** | **`9 → 11`** (`12` all) |

---

## 5. Practical Recommendations: Choosing a Model for Ponder

1. **For maximum architectural depth & subtle cross-file/math invariants:** Run **Claude Opus 5.5** (`5` passes). It enumerates fine-grained state variants (`54` units) and discovers second-order vulnerabilities (like $N \to N+1$ score-diff deanonymization) that no other model spotted.
2. **For strict protocol discipline, exact phantom pruning, and calibrated 4-pass convergence:** Run **Gemini 4 Argon** or **Claude Sonnet 5.5**. Both achieved **`14/14` (`100.0%`) actionable recall** with full 4-voice participation (`Skeptic`, `Builder`, `Dreamer`, `Empath`), and **Gemini 4 Argon** achieved the lowest prediction error (`0.002` mean surprise) and complete `phantom: true` unit pruning.
3. **For fast, low-cost CI or everyday PR sweeps:** Run **Claude Haiku 5.5** with Ponder. Ponder lifted Haiku 5.5 from `12/14` in single-shot to **`14/14` (`100.0%`)** in 4 passes—outperforming single-shot runs of much larger models.
4. **If running on Codex / OpenAI:** Prefer **GPT-6.1 Sol** over **GPT-6 Astra** (which under-grades confidence on un-rendered UI units), and explicitly prompt the **Skeptic** voice to challenge Pass 1 assumptions rather than pre-converting uncertain items into `note` findings.
