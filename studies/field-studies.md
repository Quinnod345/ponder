# Production Field Studies

Beyond the controlled head-to-head benchmark in [`studies/head-to-head-benchmark/`](head-to-head-benchmark/), Ponder has been run across production codebases ranging from B2B SaaS platforms to interactive developer portfolios.

This document records the empirical telemetry, convergence trajectories, and qualitative discoveries from **four production field studies**.

---

## Summary Across All Four Field Studies

| Study | Domain & Lens | Enumerated Units | Passes to Converge | Final Coverage | False Positives Retracted | Final Pass Churn / Surprise |
|---|---|---:|---:|---:|---:|---:|
| **[Study 1](#field-study-1-228-unit-saas-ui-sweep)** | B2B SaaS Platform (`ui` lens) | **228** screens & state variants | 4 | `1.00` (228/228) | 11 | `0.01` churn / `0.00` surprise |
| **[Study 2](#field-study-2-154-surface-security--efficiency-audit)** | Full-Stack API & Webhooks (`architecture` lens) | **154** endpoints, actions, migrations | 4 | `1.00` (154/154) | 5 | `0.00` churn / `0.00` surprise |
| **[Study 3](#field-study-3-first-time-user--emotional-privacy-audit)** | Onboarding & Anonymity Contract (`product` lens) | **16** end-to-end user journeys | 4 | `1.00` (16/16) | 3 | `0.00` churn / `0.00` surprise |
| **[Study 4](#field-study-4-37-unit-interactive-portfolio-deliberation)** | Interactive Web Portfolio (`ui` + `product` lens) | **37** sections, shaders, mobile states | 4 | `1.00` (37/37) | 1 | `0.02` churn / `0.00` surprise |

---

## Field Study 1: 228-Unit SaaS UI Sweep
**Why Route Globs Miss 86% of the Real Product**

### Context
A production Next.js App Router SaaS application had **30 `page.tsx` route files**. A standard single-pass agent review globbed `app/**/page.tsx`, inspected those 30 files, and declared the UI review complete.

When Ponder ran with the [`ui`](../lenses/ui.md) lens, its 4-sweep enumeration protocol (`1a` route files, `1b` unrouted modals/drawers/wizards, `1c` state variants `empty · loading · error · populated`, and `1d` persistent navigation chrome) enumerated **228 distinct units**:
- **30** routed pages
- **112** unrouted components, dialogs, drawers, tabs, and state-switched sub-screens
- **86** state variants (`empty`, `loading`, `error`, `expired`, `locked`)

### Pass-by-Pass Telemetry

| Pass | Graded Units | Coverage | Novelty | Churn | Thrash | Surprise | Voices (`argued` / `delta`) | Verdict |
|---:|---:|---:|---:|---:|---:|---:|---|---|
| **1** | 184 / 228 | `0.81` | `—` | `—` | `—` | `—` | `4 / 2` | **`blocked (coverage)`** — 44 state variants & unrouted modals still ungraded |
| **2** | 228 / 228 | `1.00` | `0.24` | `0.38` | `0.00` | `0.07` | `4 / 4` | `continue` — coverage complete; Skeptic retracted 9 findings on dead V1 components |
| **3** | 228 / 228 | `1.00` | `0.02` | `0.06` | `0.00` | `0.01` | `4 / 2` | `continue` — first quiet pass (`novelty < 0.05`, `churn < 0.10`) |
| **4** | 228 / 228 | `1.00` | `0.00` | `0.01` | `0.00` | `0.00` | `4 / 1` | **`stop (converged)`** |

### What Only Ponder Caught
1. **Silent Data Loss During 60-Second Polling (`must`, Score 1):**
   On the core admin workspace, a `setInterval(..., 60_000)` background poll re-fetched campaign data and reset local React state—silently wiping out whatever email address, inline edit, or modal form the user was actively typing every 60 seconds. Single-pass route review missed this because the state reset lived inside a child workspace hook rather than `page.tsx`.
2. **Orphaned V1 Components Retracted by the Skeptic:**
   Five legacy v1 components (`score-ring.tsx`, `share-card.tsx`, `setup-checklist.tsx`, `reflection-card.tsx`, `v1-results-modal.tsx`) still lived in `src/components/` with zero importers. Whereas a naive sweep filed 11 accessibility and token-consistency tickets inside those dead files, Ponder's **Skeptic** traced the import graph on Pass 2, retracted all 11 findings, and replaced them with a single hygiene task to delete the dead files.

---

## Field Study 2: 154-Surface Security & Efficiency Audit
**Adversarial Verification Across Auth, Webhooks, and Database Boundaries**

### Context
Ponder was pointed at the security, tenancy, and database performance surface of a multi-tenant web application covering **154 units**: 40 API routes, 26 server actions, 42 database helpers, 15 SQL migrations, and 31 client-side auth/storage consumers.

### Pass-by-Pass Telemetry

| Pass | Coverage | Novelty | Churn | Thrash | Surprise | Voices (`argued` / `delta`) | Verdict |
|---:|---:|---:|---:|---:|---:|---|---|
| **1** | `1.00` | `—` | `—` | `—` | `—` | `4 / 3` | `continue` — `minPasses` guard (`pass < 2`) |
| **2** | `1.00` | `0.08` | `0.31` | `0.00` | `0.05` | `4 / 4` | `continue` — Skeptic retracted 5 false alarms; Dreamer found webhook retry drop |
| **3** | `1.00` | `0.00` | `0.04` | `0.00` | `0.01` | `4 / 1` | `continue` — Builder refined SQL batching & index DDL |
| **4** | `1.00` | `0.00` | `0.00` | `0.00` | `0.00` | `4 / 0` | **`stop (converged)`** — 4 voices argued, 0 deltas emitted |

### What Only Ponder Caught
1. **Billing Webhook Idempotency Lockout (`must`, Score 1):**
   In the Stripe webhook handler, `INSERT INTO stripe_webhook_events (event_id) ON CONFLICT DO NOTHING` ran *before* the business logic (`updateOrgBilling`), and errors inside `updateOrgBilling` were caught and returned `500` so Stripe would retry—**without deleting the `stripe_webhook_events` row**. On every subsequent Stripe retry, the idempotency check saw the `event_id` row from the failed attempt, returned `200 { duplicate: true }`, and permanently dropped the customer's subscription upgrade.
2. **Unbounded 200-Query Loop in Member Attachment (`must`, Score 1):**
   `attachCampaignMembers` iterated over a user-supplied `memberIds` array with no length cap, running 2 sequential database round-trips (`SELECT` + `INSERT`) per element. Builder rewrote the recommendation on Pass 2–3 into a single parameterized `WHERE id = ANY($1) AND org_id = $2` query with a 200-item cap.
3. **False Positives Killed by Skeptic on Pass 2:**
   Pass 1 flagged five apparent vulnerabilities (including suspected SQL injection on a helper and missing rate limiting on a route that was already protected upstream in `middleware.ts`). On Pass 2, the **Skeptic** inspected the upstream middleware and query driver, retracting all 5 false positives so the final engineering plan contained zero noise.

---

## Field Study 3: First-Time User & Emotional/Privacy Audit
**Stepping Into the Actor's Emotional State Across 16 Journeys**

### Context
Standard static analysis checks whether code compiles and types match. It rarely asks: *"What did we promise the human on Screen A, how do they feel when they land on Screen B, and whose convenience won when the engineer took a shortcut?"*

Using the [`product`](../lenses/product.md) lens (`whose convenience wins`, `path-clarity`, `recovery`, `trust`), Ponder audited **16 end-to-end journeys** from first-time sign-up through inviting a team and viewing the first organizational score.

### Pass-by-Pass Telemetry

| Pass | Coverage | Novelty | Churn | Thrash | Surprise | Voices (`argued` / `delta`) | Verdict |
|---:|---:|---:|---:|---:|---:|---|---|
| **1** | `1.00` | `—` | `—` | `—` | `—` | `4 / 3` | `continue` (`minPasses` guard) |
| **2** | `1.00` | `0.14` | `0.42` | `0.00` | `0.06` | `4 / 4` | `continue` — Empath re-ranked privacy leaks above UI polish |
| **3** | `1.00` | `0.00` | `0.05` | `0.00` | `0.01` | `4 / 1` | `continue` — first quiet pass |
| **4** | `1.00` | `0.00` | `0.00` | `0.00` | `0.00` | `4 / 0` | **`stop (converged)`** |

### What Only Ponder Caught
1. **The Three-Way Anonymity Promise Contradiction (`must`, Score 1):**
   By walking the journey simultaneously as the **Participant** (an employee nervous about rating leadership honestly) and the **Admin** (the founder checking the dashboard):
   - The landing page promised: *"Individual answers are never shown; results unlock after **5** responses."*
   - The participant survey header promised: *"Leadership only sees a combined reading once at least **3** people have completed it."*
   - The admin dashboard unlocked the full radar wheel at **1 response (`completedCount >= 1`)**, and the admin's Invitations table printed each named respondent's individual percentage score (`78%`) and raw `/survey/[hash]` link right next to their name.
   - **Empath** promoted this cross-journey trust violation to the #1 `must` finding in the session, ahead of every visual and layout finding.
2. **"Database-Schema Onboarding" (`should`, Score 2):**
   On a new user's first visit, an unrouted state-switched wizard intercepted the workspace and asked the user to configure `"Priority (Low / Medium / High)"` and `"Department tag"`—fields that were never explained and never used to tailor the experience. As [`lenses/product.md`](../lenses/product.md) frames it: *"A form that asks for seven fields because the table has seven columns is a 2: the engineer's convenience beat the user's."*

---

## Field Study 4: 37-Unit Interactive Portfolio Deliberation
**Converging Subjective Design & Motion Without Thrashing**

### Context
On subjective creative tasks—like reviewing an interactive developer portfolio with WebGL/canvas effects, scroll choreography, and typography—unstructured multi-pass LLM reviews notoriously **thrash**: Pass 1 says *"Make the hero bolder with more motion,"* Pass 2 says *"Strip the hero back for minimalism,"* and Pass 3 reverses Pass 2.

Ponder ran 4 passes over **37 units** of an interactive portfolio (`UpawayWebsite`), tracking `thrash` (reversals of earlier deltas) and `surprise` (`|predicted churn - actual churn|`).

### Pass-by-Pass Telemetry

| Pass | Coverage | Novelty | Churn | Thrash | Surprise | Voices (`argued` / `delta`) | Verdict |
|---:|---:|---:|---:|---:|---:|---|---|
| **1** | `1.00` | `—` | `—` | `—` | `—` | `4 / 2` | `continue` (`minPasses` guard) |
| **2** | `1.00` | `0.05` | `0.19` | `0.00` | `0.04` | `4 / 3` | `continue` — Skeptic cut speculative scope; Builder grounded CSS/motion fixes |
| **3** | `1.00` | `0.00` | `0.05` | `0.00` | `0.02` | `4 / 1` | `continue` — first quiet pass |
| **4** | `1.00` | `0.00` | `0.02` | `0.00` | `0.00` | `4 / 1` | **`stop (converged)`** |

### Why It Converged Instead of Thrashing
- **Append-Only History With Explicit `why`:** Because every revision in `deltas.jsonl` sees the prior pass's finding and must supply a written `why`, voices cannot silently flip-flop without triggering the `thrash > 0.25` escalation rule (`lib/metrics.js`).
- **Role Separation Prevents Scope Creep:** **Dreamer** proposed ambitious interactive additions on Pass 1–2, **Skeptic** pruned anything that harmed frame rate or mobile readability (`delete`), **Empath** re-ranked findings around a hiring manager or prospective client scanning on mobile (`change`), and **Builder** reduced the survivors to concrete CSS/JS diffs (`edit`). By Pass 3 and Pass 4, `surprise` dropped to `0.00`.
