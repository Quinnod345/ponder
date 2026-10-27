# Ponder — the full-stack benchmark app

`benchmark-app` · lens **ui** · status **converged** · 4 passes of a 5-pass budget · generated 2026-10-27T21:42:59.065Z

| | |
|---|---|
| Subject | the full-stack benchmark app |
| Lens | ui — unit = screen, 12 dimensions |
| Project | `/Users/quinnodonnell/code/ponder/studies/head-to-head-benchmark/target-app` |
| Passes | 4 run · min 2 · max 5 |
| Coverage | 1.00 — 8 of 8 screens graded |
| Findings | 13 total · 11 open · 0 resolved · 0 deferred · 2 retracted |
| Final verdict | stop (converged) → decided **stop** |
| OCA | off |

## Convergence

| Pass | Coverage | Novelty | Churn | Thrash | Surprise | Stall | Conf-floor | Voices | Advice | Decision |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|---|
| 1 | 0.70 | — | — | — | — | 0 | 0.00 | 4 | blocked (coverage) | continue |
| 2 | 1.00 | 0.18 | 0.73 | 0.00 | 0.18 | 0 | 0.00 | 4 | continue (default) | continue |
| 3 | 1.00 | 0.00 | 0.09 | 0.00 | 0.00 | 0 | 0.00 | 4 | continue (default) | continue |
| 4 | 1.00 | 0.00 | 0.00 | 0.00 | 0.00 | 1 | 0.00 | 4 | stop (converged) | stop |

`—` on pass 1 is not a zero. Novelty, churn, thrash and surprise measure change against a previous pass, and pass 1 has none.

## Overrides

None. Every decision followed the engine's advice.

## Prediction vs reality

| Pass | Predicted churn | Actual churn | Surprise | Claim |
|---:|---:|---:|---:|---|
| 1 | 0.85 | — | — | Pass 1 enumerates all routes, state variants, and actions, seeding the initial findings. |
| 2 | 0.55 | 0.73 | 0.18 | Pass 2 grades the remaining units, retracts the SQLi decoy and dead modal, verifies the phantom export route, and sharpens recommendations. |
| 3 | 0.09 | 0.09 | 0.00 | Pass 3 is a verification pass: one Builder edit to tighten SQL batching syntax, zero new findings, zero retractions. |
| 4 | 0.00 | 0.00 | 0.00 | Pass 4 is completely silent: all four voices confirm the 11 open findings hold with zero deltas. |

## Coverage

8 screens enumerated, 8 graded.

**Removed from the inventory (1) — appraised, then dropped, so coverage above is measured against what is left:**

- `screen.legacy-v1-modal` — Legacy V1 Settings Modal · removed in pass 2 by the skeptic: Appraised in pass 1 and confirmed unreachable (zero importers in src/router.js or src/screens/*).

### Corrected screen

1 screen was corrected in place by a `unit-edit`. Correcting a unit changes nothing about coverage — it is neither an addition nor a removal — but it is a revision, so it is on the ledger and it counts toward churn.

- `screen.results` — Admin Results (/results) — unlocks at completedCount >= 1 against the 3-respondent survey promise · pass 2 · label corrected by the builder
  - `label` → Admin Results (/results) — unlocks at completedCount >= 1 against the 3-respondent survey promise
  > Pass 2 established that /results unlocks at completedCount >= 1 against the >= 3 survey privacy promise; the caption should state this.

### Phantom units

1 screen was claimed not to exist in the software and dropped from the coverage denominator.

- `screen.legacy-export` — Legacy Export (/settings/legacy-export) · pass 2 · verified-missing (`/Users/quinnodonnell/code/ponder/studies/head-to-head-benchmark/target-app/src/screens/legacy-export.jsx` does not exist)
  > Opened src/screens/legacy-export.jsx (enumerated from stale src/router.js:9) — file does not exist on disk.

## Findings

### attachMembersToCampaign server action `action.attach-members`
`src/actions/team-actions.js`

- **f-0010** · must · score 1 · confidence 0.95 · effort s · consistency — attachMembersToCampaign does not scope memberIds to currentUser.tenantId (cross-tenant IDOR)
  attachMembersToCampaign verifies campaign ownership at line 5, but loads each memberId with WHERE id = ${memberId} only (line 15), allowing any tenant to attach another tenant's members to their campaign.
  Evidence: `src/actions/team-actions.js:14-21`
  Do: Add AND tenant_id = ${currentUser.tenantId} to the members lookup in src/actions/team-actions.js:15.

- **f-0011** · should · score 2 · confidence 0.95 · effort s · loading-states — attachMembersToCampaign executes an unbounded 2N sequential query loop per memberId
  Lines 14-21 run a sequential SELECT and INSERT inside for (const memberId of memberIds) with no batching or length cap, causing 2N DB round-trips.
  Evidence: `src/actions/team-actions.js:14-21`
  Do: In src/actions/team-actions.js:14-21, deduplicate and cap `const ids = [...new Set(memberIds)].slice(0, 200)`, query `WHERE id = ANY(${ids}) AND tenant_id = ${currentUser.tenantId}` in one round-trip, and insert all matched rows in one multi-row INSERT.
  _Revised: p3 edit recommendation_

### Billing & Plans (/billing) `screen.billing`
`src/screens/billing.jsx`

- **f-0006** · must · score 1 · confidence 0.98 · effort xs · affordance-clarity — Upgrade to Pro button hardcodes plan: "business" in checkout payload
  startUpgrade(selectedTier) ignores selectedTier for the plan key and sends { plan: "business", sourceTier: selectedTier }, making the highlighted Pro plan impossible to buy.
  Evidence: `src/screens/billing.jsx:5-9`, `src/screens/billing.jsx:17`
  Do: Pass plan: selectedTier in startUpgrade at src/screens/billing.jsx:8.

- **f-0007** · should · score 2 · confidence 0.90 · effort xs · empty-states — Invoices empty state is a bare "No invoices" string
  When invoices.length === 0, BillingScreen renders a bare <div>No invoices</div> with no explanation of when invoices appear.
  Evidence: `src/screens/billing.jsx:29-31`
  Do: Replace the bare string at src/screens/billing.jsx:31 with an empty state explaining that invoices appear after the first billing cycle.

### Dashboard — error state on API failure `screen.dashboard.error`
`src/screens/dashboard.jsx`

- **f-0012** · must · score 1 · confidence 0.98 · effort xs · error-states — Dashboard catch handler never clears isLoading, pinning the screen in a permanent skeleton on error
  In src/screens/dashboard.jsx:15-20, .catch() calls setError(...) without calling setIsLoading(false). Because if (isLoading) at line 23 precedes if (error) at line 27, a failed fetchSummary() leaves the skeleton mounted forever and the error banner is unreachable.
  Evidence: `src/screens/dashboard.jsx:15-28`
  Do: Call setIsLoading(false) inside the .catch() block at src/screens/dashboard.jsx:18 (or in a .finally() handler) and add a Retry button to the error-banner at line 27.

### Admin Invitations Table (/invitations) `screen.invitations`
`src/screens/invitations.jsx`

- **f-0004** · must · score 1 · confidence 0.98 · effort s · consistency — Invitations table leaks individual respondent scores and raw surveyHash bearer links
  Every row in InvitationsScreen prints p.individualScore% by name and renders /survey/{p.surveyHash} in the DOM, breaking the privacy promise in survey.jsx:9-13 and exposing each participant bearer token.
  Evidence: `src/screens/invitations.jsx:18-26`, `src/screens/survey.jsx:9-13`
  Do: Remove the Individual Score and Magic Link columns from InvitationsScreen; show only Name and Completed/Pending status.
  _Revised: p1 change severity, p1 change confidence_

- **f-0005** · note · score 4 · confidence 0.95 · effort xs · information-hierarchy — Completed vs Pending status column gives clear per-participant progress feedback
  The Status column cleanly distinguishes Completed from Pending respondents without exposing answers.
  Evidence: `src/screens/invitations.jsx:19`
  Do: Keep the Name and Status columns as the sole columns in InvitationsScreen.

### Admin Results (/results) — unlocks at completedCount >= 1 against the 3-respondent survey promise `screen.results`
`src/screens/results.jsx`

- **f-0013** · must · score 1 · confidence 0.98 · effort s · consistency — Results unlock at completedCount >= 1, exposing the first respondent's private answers as the company average
  SurveyScreen (src/screens/survey.jsx:9-13) promises participants that leadership only sees a combined reading once at least 3 teammates respond. ResultsScreen (src/screens/results.jsx:8-14) gates on campaign.completedCount < 1 and says "Results unlock as soon as one person completes a checkup", so at N=1 the aggregate score is the first respondent's exact answers.
  Evidence: `src/screens/results.jsx:8-14`, `src/screens/survey.jsx:9-13`
  Do: Export MIN_RESPONDENTS = 3 and gate ResultsScreen at src/screens/results.jsx:8 on campaign.completedCount < MIN_RESPONDENTS, updating the empty-state copy at line 11 to match survey.jsx.

### Dashboard — unrouted currentStep setup wizard `screen.dashboard.wizard`
`src/screens/dashboard.jsx`

- **f-0002** · should · score 2 · confidence 0.90 · effort s · affordance-clarity — Unrouted first-run wizard asks new users for internal schema version and priority
  Sweep 1b found a state-switched wizard (currentStep === "welcome") that prompts a first-time user for "Priority (Low / Medium / High)" and "Internal schema version" before they have seen the workspace.
  Evidence: `src/screens/dashboard.jsx:29-37`
  Do: In src/screens/dashboard.jsx:29-37, remove the Priority and Internal schema version <input> elements and start new workspaces directly on the overview with a single inline "Create first campaign" CTA.
  _Revised: p2 edit recommendation_

### Dashboard — populated workspace overview `screen.dashboard`
`src/screens/dashboard.jsx`

- **f-0001** · note · score 4 · confidence 0.90 · effort xs · information-hierarchy — Workspace overview renders activeCount cleanly once summary resolves
  Populated state displays active campaign count with a nullish fallback to 0.
  Evidence: `src/screens/dashboard.jsx:40-44`
  Do: No change required on the populated overview.

### Participant Survey (/survey/:hash) `screen.survey`
`src/screens/survey.jsx`

- **f-0003** · note · score 4 · confidence 0.95 · effort xs · copy-tone — Survey header states a clear 3-respondent privacy floor to participants
  The survey header explicitly promises respondents that leadership only sees a combined reading once at least 3 teammates have completed the checkup.
  Evidence: `src/screens/survey.jsx:9-13`
  Do: Enforce this 3-respondent privacy floor on every admin read surface.

## Retracted

Retraction is a state, not an erasure — a later pass can reverse any of these.

- `f-0009` (action.attach-members) — SQL injection in attachMembersToCampaign via sql template literal · retracted in pass 2 by the skeptic: Opened src/lib/safe-query.js:5-14 — the sql tagged template emits $1, $2 placeholders and passes values separately to pg; no string interpolation into SQL occurs.
- `f-0008` (screen.legacy-v1-modal) — LegacyV1Modal uses low-contrast #ccc text on #fff background · retracted in pass 2 by the skeptic: Grep across src/ confirms zero importers of src/screens/legacy-v1-modal.jsx; grading contrast on unreachable dead code is false-positive noise.

## Deliberation

### Pass 1

- **skeptic** (confidence 0.90) — Pass 1 seeded 11 findings across 7 of 10 enumerated units. Before we can converge, I need to verify the SQL injection claim in f-0009 against src/lib/safe-query.js, check whether src/screens/legacy-v1-modal.jsx is reachable at all, and check whether src/screens/legacy-export.jsx exists on disk.
- **builder** (confidence 0.85) — The checkout bug (f-0006), cross-tenant IDOR (f-0010), and 2N query loop (f-0011) are clear, but we are still missing grades for screen.dashboard.error and screen.results.
- **dreamer** (confidence 0.90) — Looking across the survey and admin screens together: survey.jsx promises a 3-respondent anonymity threshold, and we have not yet graded results.jsx against that promise or checked dashboard.jsx error state.
- **empath** (confidence 0.95) — f-0004 (invitations leaking individual scores and surveyHash links) is currently ranked should, but to a team member promised privacy in survey.jsx, seeing their individual score in the admin table is a critical trust breach and must be promoted to must.

Resolution: 1 change (plus 11 findings seeded by `ponder grade` before the argument).

### Pass 2

- **skeptic** (confidence 0.98) — Opened every cited path and ran an import-graph check across target-app/src. Three falsifications: (1) src/lib/safe-query.js:5-14 compiles template literals into parameterized $1..$n bindings, so f-0009 (SQL injection) is false and I am retracting it. (2) src/screens/legacy-v1-modal.jsx has zero importers anywhere in src/, so grading its contrast (f-0008) is noise on dead code; I am retracting f-0008 and removing screen.legacy-v1-modal as an appraised out-of-scope unit. (3) src/screens/legacy-export.jsx listed in src/router.js:9 does not exist on disk at all, so I am filing a verified phantom unit-delete.
- **builder** (confidence 0.92) — Rewriting recommendations on f-0002, f-0004, f-0010, and f-0011 so each names the exact lines, props, and SQL batch query to ship, and updating screen.results caption via unit-edit to record the N=1 privacy breach.
- **dreamer** (confidence 0.96) — Closed the two real coverage gaps by reading dashboard.jsx and results.jsx against survey.jsx: (1) On screen.dashboard.error, dashboard.jsx:15-20 catches fetchSummary errors without calling setIsLoading(false), so isLoading stays true forever and the error banner at line 27 is unreachable dead code. (2) On screen.results, results.jsx:8 unlocks the combined reading at completedCount >= 1 while survey.jsx:9-13 promised a minimum of 3 respondents—so at N=1 the company wheel is one person's private answers.
- **empath** (confidence 0.95) — Confirmed from the participant and first-time admin perspectives that the two new findings (f-0012 permanent loading skeleton on error, f-0013 N=1 privacy breach on Results) are both must-fix trust and dead-end failures.

Resolution: 2 add, 1 edit, 2 delete, 1 unit-edit, 2 unit-delete.

### Pass 3

- **skeptic** (confidence 0.98) — VOTE: DONE. Re-verified all 11 open findings against src/screens/*.jsx and src/actions/team-actions.js. Every path and line range resolves, no duplicate (unit, dimension) pairs remain, and no retracted anchor is referenced.
- **builder** (confidence 0.95) — VOTE: DONE after one edit. Tightened f-0011 recommendation to specify deduplicating memberIds with new Set() and capping batch size at 200 before the parameterized ANY($1) query.
- **dreamer** (confidence 0.97) — VOTE: DONE. All 8 live units are covered, the orphan modal and phantom export route are cleanly accounted for on the ledger, and the cross-surface privacy contract between survey.jsx, results.jsx, and invitations.jsx is complete. Emitting zero deltas.
- **empath** (confidence 0.96) — VOTE: DONE. Re-checked the severity order: the 5 must findings (f-0004, f-0006, f-0010, f-0012, f-0013) are all genuine blockers for trust, security, or core task completion, and the 3 shoulds (f-0002, f-0007, f-0011) are properly ranked below them.

Resolution: 1 edit.

### Pass 4

- **skeptic** (confidence 0.99) — VOTE: DONE. Re-checked all 11 open findings and 14 evidence citations on disk. Zero unsupported claims, zero duplicates. Emitting 0 deltas.
- **builder** (confidence 0.99) — VOTE: DONE. Every open must and should finding names the exact file, line range, and concrete code change to ship. Emitting 0 deltas.
- **dreamer** (confidence 0.99) — VOTE: DONE. No unenumerated surfaces or systemic gaps remain. Staying silent so the settled set converges cleanly.
- **empath** (confidence 0.99) — VOTE: DONE. Ranking and confidence floor (0.00) hold without change. Emitting 0 deltas.

Resolution: no deltas.

## Ledger

21 deltas across 4 passes: 13 add, 2 edit, 1 change, 2 delete, 1 unit-edit, 2 unit-delete.

| Pass | Deltas | Perspectives |
|---:|---|---|
| 1 | 11 add, 1 change | empath |
| 2 | 2 add, 1 edit, 2 delete, 1 unit-edit, 2 unit-delete | builder, dreamer, skeptic |
| 3 | 1 edit | builder |
| 4 | no deltas | — |

The full append-only record is `ledger.jsonl`.
