# Ponder — full-audit

`full-audit-2026-11-06` · lens **ui** · status **converged** · 5 passes of a 5-pass budget · generated 2026-11-06T15:48:42.125Z

| | |
|---|---|
| Subject | full-audit |
| Lens | ui — unit = screen, 12 dimensions |
| Project | `/tmp/ponder-eval/models/claude-sonnet-5-5` |
| Passes | 5 run · min 2 · max 5 |
| Coverage | 1.00 — 41 of 41 screens graded |
| Findings | 52 total · 49 open · 0 resolved · 0 deferred · 3 retracted |
| Final verdict | stop (converged) → decided **stop** |
| OCA | reachable · ref 279721 |

## Convergence

| Pass | Coverage | Novelty | Churn | Thrash | Surprise | Stall | Conf-floor | Voices | Advice | Decision |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|---|
| 1 | 1.00 | — | — | — | — | 0 | 0.00 | 4 | continue (min-passes) | continue |
| 2 | 1.00 | 0.04 | 0.17 | 0.00 | 0.08 | 0 | 0.00 | 4 | continue (default) | continue |
| 3 | 1.00 | 0.02 | 0.18 | 0.00 | 0.04 | 0 | 0.00 | 4 | continue (default) | continue |
| 4 | 1.00 | 0.00 | 0.02 | 0.00 | 0.00 | 0 | 0.00 | 4 | continue (default) | continue |
| 5 | 1.00 | 0.00 | 0.00 | 0.00 | 0.00 | 1 | 0.00 | 4 | stop (converged) | stop |

`—` on pass 1 is not a zero. Novelty, churn, thrash and surprise measure change against a previous pass, and pass 1 has none.

## Overrides

None. Every decision followed the engine's advice.

## Prediction vs reality

| Pass | Predicted churn | Actual churn | Surprise | Claim |
|---:|---:|---:|---:|---|
| 1 | 0.45 | — | — | Pass 1 will be breadth-heavy and under-grade the non-render variants (loading/denied) and the backend slice; expect pass 2 to retract a few over-confident code-only guesses and raise confidence on the webhook retry bug. |
| 2 | 0.25 | 0.17 | 0.08 | Pass 2 will retract 1-2 echoes (privacy chain), tighten the unverified denied/invalid-link guesses, add missed units (dashboard configure step, survey loading stub) and no new must beyond the webhook retry details. |
| 3 | 0.14 | 0.18 | 0.04 | Pass 3 will write the through-line, re-point four crash findings at the shared primitive, and downgrade crash-on-undefined confidence; no new defects expected. |
| 4 | 0.02 | 0.02 | 0.00 | Pass 4 re-checks every must and the unverified guesses against source; expect at most one wording fix (f-0042 duplicate-insert claim assumes no unique constraint) and zero new findings. |
| 5 | 0.00 | 0.00 | 0.00 | Pass 5 re-verifies every open must and the enumeration against source; expect no adds and no changes. |

## Coverage

41 screens enumerated, 41 graded.

## Findings

### attachMembersToCampaign action `action.team.attach-members`
`target-app/src/actions/team-actions.js`

- **f-0041** · must · score 1 · confidence 0.90 · effort s · error-states — Member lookup is not tenant-scoped (cross-tenant attach)
  Campaign lookup is filtered by tenant_id, but the member query "SELECT id, email FROM members WHERE id = $1" has no tenant filter. A user can attach members belonging to another tenant by supplying their ids, linking foreign people (and, downstream, their survey data) to their campaign.
  Evidence: `target-app/src/actions/team-actions.js:12`
  Do: Add AND tenant_id = ${currentUser.tenantId} to the members query, or fetch all ids in one tenant-filtered query and report skipped ids.
  _Revised: p1 change dimension, p1 change score_

- **f-0042** · should · score 2 · confidence 0.80 · effort s · consistency — Per-member loop: no transaction, no dedupe, silent skips
  The loop at team-actions.js:11-19 runs one SELECT and one INSERT per member with no transaction, so a failure mid-loop leaves half the members attached. The INSERT has no ON CONFLICT clause, so re-running the action either inserts duplicate campaign_members rows or, if the table has a unique constraint (not visible here), throws part-way through the loop. Unknown ids are silently skipped while the action returns { ok: true }, so the caller cannot tell that some members were not attached.
  Evidence: `target-app/src/actions/team-actions.js:11-19`
  Do: Wrap in a transaction, use INSERT ... ON CONFLICT DO NOTHING, return { attached, skipped }.
  _Revised: p4 edit detail_

### Anonymity contract (min cohort) across survey, invitations and results `app.privacy.cohort-contract`
`target-app/src/screens/survey.jsx`

- **f-0048** · must · score 1 · confidence 0.85 · effort s · consistency — The minimum-cohort rule is stated three different ways and enforced nowhere shared
  survey.jsx:9-11 promises >=3 teammates; results.jsx:4 unlocks at <1; its copy says 'one person'; invitations.jsx:21 prints named individual scores. There is no MIN_COHORT constant, so copy and guard drifted apart. Respondents are promised something the product does not deliver.
  Evidence: `target-app/src/screens/survey.jsx:9-11`, `target-app/src/screens/results.jsx:4-8`, `target-app/src/screens/invitations.jsx:21`
  Do: Create MIN_COHORT = 3 in a shared module used by survey copy, the results guard, the results copy and the server aggregate endpoint; remove the individual score column. Done = changing the constant changes all four places.

### POST Stripe webhook handler `route.stripe-webhook`
`webhook-billing-slice/src/routes/stripe-webhook.js`

- **f-0044** · must · score 1 · confidence 0.90 · effort s · error-states — Event is recorded as processed before the upgrade runs, so failures are lost
  The dedupe row is inserted first. If applyPlanUpgrade throws the handler returns 500 so Stripe retries, but the retry hits ON CONFLICT DO NOTHING, rowCount 0, and responds 200 duplicate:true. The customer paid and the plan never changes. The 500 body also returns err.message to the caller and JSON.parse is unguarded.
  Evidence: `webhook-billing-slice/src/routes/stripe-webhook.js:12-28`
  Do: stripe-webhook.js:12-28 -> BEGIN; INSERT event row; applyPlanUpgrade(tx, ...); COMMIT, ROLLBACK on error (so the retry re-inserts). Return { error: 'processing_failed' } not err.message, and wrap JSON.parse in try/catch returning 400. Done = test: first delivery throws, second delivery with same event.id applies the upgrade.
  _Revised: p1 edit recommendation_

### Billing - plans and invoices `screen.billing`
`target-app/src/screens/billing.jsx`

- **f-0029** · must · score 1 · confidence 0.95 · effort s · error-states — Pro upgrade button starts a Business checkout
  startUpgrade ignores which card was clicked: it always calls onCheckout({ plan: "business", sourceTier: selectedTier }). The highlighted "Pro (Recommended)" $29/month card therefore sends plan "business" ($99/month). A user who chooses the recommended plan is billed for a different product at 3.4x the price. Not rendered: behaviour derived from reading the source.
  Evidence: `target-app/src/screens/billing.jsx:4-6`, `target-app/src/screens/billing.jsx:14`, `target-app/src/screens/billing.jsx:19`
  Do: billing.jsx:5 -> change startUpgrade to onCheckout({ plan: selectedTier }) (drop the hard-coded 'business'). Done = a test that clicking 'Upgrade to Pro' calls onCheckout with plan 'pro' and 'Upgrade to Business' with plan 'business'.
  _Revised: p1 edit recommendation_

- **f-0031** · should · score 2 · confidence 0.60 · effort s · affordance-clarity — Upgrade buttons have no pending state and no confirmation of price
  Clicking calls onCheckout and nothing changes on screen; the button does not disable, so repeated clicks can create multiple checkout sessions. Not rendered: behaviour derived from reading the source.
  Evidence: `target-app/src/screens/billing.jsx:14`, `target-app/src/screens/billing.jsx:19`
  Do: Disable the button and show "Redirecting to checkout..." while pending.

- **f-0030** · could · score 3 · confidence 0.60 · effort s · information-hierarchy — Plans lack feature lists and current-plan indicator
  Two cards show name and price only. Nothing says what each plan includes, which plan the user is on, or that "Upgrade to Business" is also offered to someone already on Business. Not rendered: behaviour derived from reading the source.
  Evidence: `target-app/src/screens/billing.jsx:10-21`
  Do: Show current plan, 3 bullet differences per plan, and disable the current plan's button with "Current plan".

### Billing - checkout fails or is pending after click `screen.billing.error-checkout`
`target-app/src/screens/billing.jsx`

- **f-0034** · must · score 1 · confidence 0.70 · effort m · error-states — Failed or slow checkout gives the user nothing
  startUpgrade returns the onCheckout promise to nobody: there is no catch, no error message, and no in-progress feedback. A declined card or network error leaves the user on an unchanged page. Combined with the webhook never retrying a failed upgrade, a paid customer may see no change at all. Not rendered: behaviour derived from reading the source.
  Evidence: `target-app/src/screens/billing.jsx:4-6`
  Do: Await onCheckout in try/catch, show an inline error with retry, and show a pending state until the plan updates.

### Dashboard - fetch failed (intended error banner) `screen.dashboard.error`
`target-app/src/screens/dashboard.jsx`

- **f-0002** · must · score 1 · confidence 0.90 · effort s · error-states — Error banner is unreachable: failed fetch spins forever
  The .catch handler calls setError but never setIsLoading(false). The isLoading check runs before the error check, so for a failed request the user sees the loading line permanently and the error banner can never render. When it would render it prints raw err.message with no retry and no class distinction (offline, 401, 500). Not rendered: behaviour derived from reading the source.
  Evidence: `target-app/src/screens/dashboard.jsx:15-17`, `target-app/src/screens/dashboard.jsx:20-26`
  Do: Move the error check above the isLoading check or set isLoading=false in a finally. Render a specific message per failure class with a Retry button that refetches in place.

### Dashboard - 'Set up your checkup' wizard step welcome `screen.dashboard.wizard-welcome`
`target-app/src/screens/dashboard.jsx`

- **f-0004** · must · score 1 · confidence 0.90 · effort s · copy-tone — Wizard exposes internal jargon and collects data it throws away
  The welcome step asks for "Priority (Low / Medium / High)" and "Internal schema version" as free-text inputs with placeholder as the only label. "Internal schema version" is developer vocabulary a customer cannot answer. Neither input has state, name or onChange, so whatever the user types is discarded; Next sets currentStep to "configure", which has no branch, so the user lands on the overview with no confirmation that setup happened. Not rendered: behaviour derived from reading the source.
  Evidence: `target-app/src/screens/dashboard.jsx:28-37`
  Do: Delete "Internal schema version". Replace Priority with a labelled select or radio group, store values in state, submit them on Next, and end with an explicit "You are set up" confirmation or a real configure step.

- **f-0005** · should · score 1 · confidence 0.85 · effort s · accessibility — Wizard inputs have no accessible names
  Both inputs rely on placeholder text only, with no label element or aria-label. Placeholder text disappears on typing and is not a reliable accessible name; contrast of default placeholder colour is also commonly below 4.5:1. There is no Back or Skip, so keyboard and screen-reader users cannot leave the wizard except by completing it. Not rendered: behaviour derived from reading the source.
  Evidence: `target-app/src/screens/dashboard.jsx:32-34`
  Do: Add visible <label htmlFor> elements, associate with inputs, and add a Skip for now button.

### Invitations - participants table `screen.invitations`
`target-app/src/screens/invitations.jsx`

- **f-0022** · must · score 1 · confidence 0.85 · effort s · information-hierarchy — Individual Score column exposes per-person results
  The table shows a named participant's individualScore once completedAt is set. Together with the n>=1 results gate and the survey privacy promise, this lets an admin see exactly what each person scored. It is the most prominent data column on the screen while the page job is "who has answered". Not rendered: behaviour derived from reading the source.
  Evidence: `target-app/src/screens/invitations.jsx:12`, `target-app/src/screens/invitations.jsx:21`
  Do: Remove the Individual Score column; show only Completed/Pending and completion date.

- **f-0023** · should · score 2 · confidence 0.70 · effort s · affordance-clarity — Magic link is shown as unclickable code with no copy or resend action
  The link is rendered as <code>/survey/{hash}</code>, a relative path with no origin, not an anchor and with no Copy or Resend button. An admin cannot send it anywhere from this screen. The hash is also the sole credential for the survey and is displayed in plain text to everyone who can load the page. Not rendered: behaviour derived from reading the source.
  Evidence: `target-app/src/screens/invitations.jsx:22`
  Do: invitations.jsx:22 -> render a 'Copy link' button that copies `${window.location.origin}/survey/${p.surveyHash}` and a 'Resend' button on Pending rows; stop printing the raw hash. Done = the hash string is not visible in the DOM text.
  _Revised: p1 edit recommendation_

### Results - locked until first completion `screen.results.empty-locked`
`target-app/src/screens/results.jsx`

- **f-0017** · must · score 1 · confidence 0.90 · effort s · copy-tone — Unlock threshold copy is "one person", contradicting the 3-person promise
  Both the guard (completedCount < 1) and the copy ("Results unlock as soon as one person completes a checkup") unlock at one respondent. survey.jsx promises at least 3. With n=1 the "combined reading" is exactly that person's answers, so anonymity is void. Not rendered: behaviour derived from reading the source.
  Evidence: `target-app/src/screens/results.jsx:4-10`, `target-app/src/screens/survey.jsx:8-12`
  Do: Change the guard to completedCount < MIN_COHORT (3) and the copy to "Results unlock when 3 teammates have answered (1 of 3 so far)". Enforce server-side too.

- **f-0018** · should · score 2 · confidence 0.70 · effort s · empty-states — Locked state conflates "no campaign" and "not enough answers" and has no action
  The same one-line message covers campaign==null and completedCount==0. There is no progress toward the threshold and no link to Invitations to remind people. Not rendered: behaviour derived from reading the source.
  Evidence: `target-app/src/screens/results.jsx:4-10`
  Do: Split the two cases; for the second show progress and a "Send reminders" link to /invitations.

### Survey - invalid, expired or already-used magic link `screen.survey.error-invalid-link`
`target-app/src/screens/survey.jsx`

- **f-0013** · must · score 1 · confidence 0.60 · effort m · error-states — No state for an invalid, expired or already-used magic link
  The route is /survey/:hash and invitations.jsx hands out the hash as the sole credential. The screen has no prop or branch for a hash that does not resolve, has expired, or was already completed, so those users get the form (or a crash) rather than an explanation. This is the first screen a respondent sees from an email link, so reach and stakes are high. Not rendered: behaviour derived from reading the source. Whether the container handles invalid hashes is outside this workspace.
  Evidence: `target-app/src/screens/survey.jsx:3`, `target-app/src/router.js:3`, `target-app/src/screens/invitations.jsx:22`
  Do: Add status="invalid"\|"expired"\|"completed" variants with specific copy and a contact-your-admin action.

### Survey - after submit (confirmation / error) `screen.survey.submitted`
`target-app/src/screens/survey.jsx`

- **f-0014** · must · score 1 · confidence 0.70 · effort m · error-states — No confirmation, success or failure state after submitting
  The component has no post-submit rendering: no thank-you, no error for a failed save, no statement that answers stay private. A respondent who submits cannot tell whether it worked, and may resubmit. Not rendered: behaviour derived from reading the source.
  Evidence: `target-app/src/screens/survey.jsx:14-22`
  Do: Add a submitted view ("Thanks - your answers are in. Nobody sees them individually.") and an inline retry error that preserves entered values.

### applyPlanUpgrade billing worker `worker.billing-upgrade`
`webhook-billing-slice/src/workers/billing-worker.js`

- **f-0045** · must · score 1 · confidence 0.75 · effort m · error-states — Worker trusts defaults, NaN seats and email matching
  Tier defaults to 'pro' and seats to 5 when metadata is missing (billing-worker.js:3-4); Number(metadata.seats) can be NaN and would be written to seat_limit. The org is matched by customer_email (line 2/7), which is null on many Checkout sessions (the address lives in customer_details), is case-sensitive and not guaranteed unique; a miss throws 'Organization not found', and because the webhook has already recorded the event (f-0044) the upgrade is then lost permanently. seat_limit is incremented (line 15) instead of set from the plan, so any replay adds seats again. payment_status is never checked, so unpaid or async-pending sessions can grant a plan.
  Evidence: `webhook-billing-slice/src/workers/billing-worker.js:2-4`, `webhook-billing-slice/src/workers/billing-worker.js:6-8`, `webhook-billing-slice/src/workers/billing-worker.js:15-19`
  Do: billing-worker.js:2-19 -> allow-list tier, require Number.isInteger(seats) && seats > 0, require checkoutSession.payment_status === 'paid', resolve the org by checkoutSession.client_reference_id or Stripe customer id, and UPDATE seat_limit = plan seat count (not +=). Done = a test with missing metadata rejects the session rather than defaulting.
  _Revised: p2 edit detail, p2 edit recommendation_

### App navigation shell (absent) `app.nav-shell`
`target-app/src/router.js`

- **f-0040** · should · score 1 · confidence 0.70 · effort m · affordance-clarity — No navigation exists: five routes are orphans
  Sweep 4 finds zero href/Link/navigate calls in target-app except the PDF download link. Dashboard, Invitations, Results and Billing are never linked from anywhere; users must type URLs. The only cross-reference is the survey hash printed as text. Not rendered: behaviour derived from reading the source.
  Evidence: `target-app/src/router.js:2-6`, `target-app/src/screens/results.jsx:16`
  Do: Add an app shell with a primary nav listing Dashboard, Invitations, Results, Billing and mark the current page.

### Unknown URL / 404 landing `app.router.not-found`
`target-app/src/router.js`

- **f-0039** · should · score 1 · confidence 0.70 · effort s · error-states — No catch-all route: unknown URLs have no 404 screen
  The route table has no path:"*" entry and the repo has no not-found screen, so a mistyped URL or an old bookmark resolves to nothing designed (rg for not-found/404 returns zero). Not rendered: behaviour derived from reading the source.
  Evidence: `target-app/src/router.js:1-8`
  Do: Add a "*" route with a not-found screen linking to the dashboard.

### Router table (6 routes) `app.router.table`
`target-app/src/router.js`

- **f-0038** · should · score 2 · confidence 0.80 · effort s · consistency — Router table has no auth marker and no default route
  router.js lists six plain {path, component} objects. Public /survey/:hash sits beside admin routes with no marker of which require authentication, and nothing handles '/' (no redirect to /dashboard). The dangling legacy-export entry is tracked separately in f-0036.
  Evidence: `target-app/src/router.js:1-8`
  Do: router.js:1-8 -> add { auth: 'public'\|'member'\|'admin' } per route and a { path: '/', redirect: '/dashboard' } entry. Done = every route declares its auth level.
  _Revised: p2 edit title, p2 edit detail, p2 edit recommendation_

### Cross-screen state contract (loading/empty/error/denied) `app.states.contract`
`target-app/src/screens/`

- **f-0047** · should · score 1 · confidence 0.70 · effort m · consistency — No shared status primitive: data screens crash or lie while loading or failed
  survey.jsx:15 questions.map, invitations.jsx:17 participants.map and billing.jsx:25 invoices.length all throw when their prop is undefined; results.jsx:4 treats a null campaign (loading) as 'no completions'. Only dashboard.jsx has a loading branch and it is stuck on failure (f-0002). The component API is data-only, so no screen can represent loading, error or denied; the fix is one shared {status, data, error} contract, not per-screen patches.
  Evidence: `target-app/src/screens/survey.jsx:15`, `target-app/src/screens/invitations.jsx:17`, `target-app/src/screens/billing.jsx:25`, `target-app/src/screens/results.jsx:4`, `target-app/src/screens/dashboard.jsx:4-26`
  Do: First read the code that renders these screens (not in this workspace) to see whether it already defaults props. Then introduce <AsyncBoundary status data error> (loading skeleton, retryable error by failure class, denied state, empty slot) and wrap every data screen. Done = no screen calls .map/.length on a prop that can be undefined.
  _Revised: p3 change confidence, p3 edit recommendation_

### verifyStripeSignature helper `lib.webhook-crypto`
`webhook-billing-slice/src/lib/webhook-crypto.js`

- **f-0046** · should · score 2 · confidence 0.75 · effort s · error-states — No timestamp tolerance and only the last v1 signature considered
  The signed timestamp t is never compared to now, so a captured valid payload and header can be replayed indefinitely. Object.fromEntries keeps only one v1 value, but Stripe sends several during secret rotation. Header parts lacking "=" produce undefined values.
  Evidence: `webhook-billing-slice/src/lib/webhook-crypto.js:5-6`, `webhook-billing-slice/src/lib/webhook-crypto.js:7-14`
  Do: Reject \|now - t\| > 300s, collect all v1 entries and accept if any matches in constant time.

- **f-0051** · could · score 2 · confidence 0.70 · effort xs · error-states — Missing webhook secret fails closed with an indistinguishable 401
  webhook-crypto.js:4 returns false when secret is falsy, and stripe-webhook.js:7-9 turns that into 401 'Invalid signature' with no log. A deploy missing STRIPE_WEBHOOK_SECRET rejects every real Stripe event exactly like a forged one, and no upgrade ever applies.
  Evidence: `webhook-billing-slice/src/lib/webhook-crypto.js:4`, `webhook-billing-slice/src/routes/stripe-webhook.js:7-9`
  Do: Throw (or log at error level) at startup when process.env.STRIPE_WEBHOOK_SECRET is unset, and log invalid-signature rejections with the event timestamp.

### Billing - non-owner viewer `screen.billing.denied`
`target-app/src/screens/billing.jsx`

- **f-0035** · should · score 2 · confidence 0.40 · effort m · error-states — No owner-only gate on payment actions
  Any member who can load /billing can click Upgrade; no role check appears (rg gate lines return zero). Not rendered: behaviour derived from reading the source.
  Evidence: `target-app/src/screens/billing.jsx:3-21`
  Do: Render plan cards as read-only with "Ask your workspace owner to upgrade" for non-owners.

### Billing - No invoices `screen.billing.empty`
`target-app/src/screens/billing.jsx`

- **f-0032** · should · score 1 · confidence 0.90 · effort xs · empty-states — "No invoices" bare div
  Exactly the lens's rung-1 example: a bare "No invoices" div with no styling, cause, expectation or action. Not rendered: behaviour derived from reading the source.
  Evidence: `target-app/src/screens/billing.jsx:25-26`
  Do: Write "No invoices yet - your first invoice appears after your first paid month" and link to the plan cards.

### Billing - invoices loading `screen.billing.loading`
`target-app/src/screens/billing.jsx`

- **f-0033** · should · score 1 · confidence 0.60 · effort s · loading-states — invoices undefined crashes the screen
  invoices.length is read with no guard, so loading invoices throws on first render. Not rendered: behaviour derived from reading the source.
  Evidence: `target-app/src/screens/billing.jsx:25`
  Do: Default invoices to [] and add a loading skeleton row.
  _Revised: p3 change confidence_

### Billing - payment failed / subscription cancelled `screen.billing.payment-failed`
`target-app/src/screens/billing.jsx`

- **f-0050** · should · score 1 · confidence 0.50 · effort l · error-states — No payment-failed or cancelled state exists in UI or webhook
  stripe-webhook.js:22 handles only checkout.session.completed; every other event type is stored in stripe_webhook_events and acknowledged with 200 but changes nothing. billing.jsx has only plans and invoices, no status banner. A customer whose card is declined (or who cancels) keeps their plan_tier and seats forever, or loses service with no explanation, and sees the same upgrade cards. Not rendered; derived from source and unverified against Stripe configuration.
  Evidence: `webhook-billing-slice/src/routes/stripe-webhook.js:22`, `target-app/src/screens/billing.jsx:10-30`
  Do: Handle invoice.payment_failed and customer.subscription.deleted in the worker, store billing status on organizations, and render a top-of-page banner on /billing ('Your payment failed on 3 Nov - update your card to keep Business') with an Update card action.

### Dashboard - loading workspace `screen.dashboard.loading`
`target-app/src/screens/dashboard.jsx`

- **f-0001** · should · score 2 · confidence 0.80 · effort s · loading-states — Loading skeleton is a text line and never ends on failure
  The loading branch renders a div with aria-busy and the text "Loading workspace..." and no skeleton geometry. isLoading is only cleared in the .then handler, so a rejected fetch leaves this exact screen up forever with no escalation after 5 seconds. Not rendered: behaviour derived from reading the source.
  Evidence: `target-app/src/screens/dashboard.jsx:4`, `target-app/src/screens/dashboard.jsx:10-17`, `target-app/src/screens/dashboard.jsx:20-22`
  Do: Render a skeleton shaped like the overview (heading + one stat row), clear isLoading in a finally block, and after ~5s show "Still loading - this is taking longer than usual" with a Retry button.

### Dashboard - Workspace Overview (populated) `screen.dashboard.overview`
`target-app/src/screens/dashboard.jsx`

- **f-0006** · should · score 2 · confidence 0.70 · effort s · information-hierarchy — Overview is a heading and one number
  The only content is 'Workspace Overview' and 'Active campaigns: N' (dashboard.jsx:41-42). There is no primary action for the user's state (create a campaign, invite teammates), so the landing page after setup does not say what to do next. Not rendered: derived from source.
  Evidence: `target-app/src/screens/dashboard.jsx:39-44`
  Do: dashboard.jsx:39-44 -> add one primary button chosen by state: 'Start a checkup' when activeCount is 0, 'View results' otherwise. Done = the overview always has exactly one filled primary action.
  _Revised: p2 edit detail, p2 edit recommendation_

### Dashboard - Workspace Overview with zero/absent summary `screen.dashboard.overview-empty`
`target-app/src/screens/dashboard.jsx`

- **f-0007** · should · score 1 · confidence 0.80 · effort s · empty-states — Zero campaigns renders "Active campaigns: 0" with no guidance
  summary?.activeCount ?? 0 turns both "no data" and "zero campaigns" into the literal text "Active campaigns: 0". A new customer sees a bare zero with no explanation and no action to create one. Not rendered: behaviour derived from reading the source.
  Evidence: `target-app/src/screens/dashboard.jsx:42`
  Do: When activeCount is 0 show "No campaigns yet" with a primary "Start a checkup" button.

### Invitations - no participants yet `screen.invitations.empty`
`target-app/src/screens/invitations.jsx`

- **f-0025** · should · score 1 · confidence 0.80 · effort s · empty-states — Zero participants shows column headers over nothing
  participants=[] renders the heading and a table with only the header row. No explanation, no "Invite people" action. Not rendered: behaviour derived from reading the source.
  Evidence: `target-app/src/screens/invitations.jsx:7-26`
  Do: Show "Nobody invited yet" with an Invite teammates primary button instead of the empty table.

### Invitations - load failed `screen.invitations.error`
`target-app/src/screens/invitations.jsx`

- **f-0027** · should · score 1 · confidence 0.65 · effort s · error-states — No error state for a failed load
  The component takes only participants; there is no way to represent a failed fetch, so the page either crashes or shows an empty table that reads as "nobody invited". Not rendered: behaviour derived from reading the source.
  Evidence: `target-app/src/screens/invitations.jsx:3`
  Do: Add an error prop with retry.

### Invitations - participants loading `screen.invitations.loading`
`target-app/src/screens/invitations.jsx`

- **f-0026** · should · score 1 · confidence 0.60 · effort s · loading-states — participants undefined crashes the screen
  participants.map has no guard, so a not-yet-loaded list throws. Not rendered: behaviour derived from reading the source.
  Evidence: `target-app/src/screens/invitations.jsx:17`
  Do: Add status prop and a 5-row table skeleton.
  _Revised: p3 change confidence_

### Results - combined reading (unlocked) `screen.results`
`target-app/src/screens/results.jsx`

- **f-0016** · should · score 2 · confidence 0.70 · effort s · error-states — aggregate undefined throws when campaign loads first
  aggregate.overall is read with no guard. If campaign resolves before aggregate (two fetches) the screen throws a TypeError. Not rendered: behaviour derived from reading the source.
  Evidence: `target-app/src/screens/results.jsx:15`
  Do: Guard aggregate?.overall and show a skeleton for the number.

### Results - PDF export fails `screen.results.error-export`
`target-app/src/screens/results.jsx`

- **f-0020** · should · score 2 · confidence 0.55 · effort s · error-states — Executive PDF is a plain link with no feedback or failure state
  The download is an <a href="/api/campaigns/:id/pdf-export">. A 4xx/5xx navigates the tab to an API error page. There is no generating indicator for a slow render. Whether the endpoint enforces the cohort threshold is not visible in this workspace. Not rendered: behaviour derived from reading the source.
  Evidence: `target-app/src/screens/results.jsx:16-18`
  Do: results.jsx:16-18 -> replace the anchor with a button that fetches /api/campaigns/:id/pdf-export, shows 'Preparing PDF...' and an inline retry on non-2xx. Done = a 500 from the endpoint leaves the user on the results page with a visible message.
  _Revised: p1 edit recommendation_

### Results - campaign still loading `screen.results.loading`
`target-app/src/screens/results.jsx`

- **f-0019** · should · score 1 · confidence 0.60 · effort s · loading-states — While campaign is loading the screen claims results are locked
  A null campaign (still fetching) takes the same branch as zero completions, so a loading screen displays "Results unlock as soon as one person completes", which is false for a campaign that has answers. Not rendered: behaviour derived from reading the source.
  Evidence: `target-app/src/screens/results.jsx:4`
  Do: Add a loading prop and render a skeleton; only show the locked copy when the campaign is known.
  _Revised: p3 change confidence_

### Legacy export - routed screen whose component file is missing `screen.settings.legacy-export`
`target-app/src/router.js`

- **f-0036** · should · score 1 · confidence 0.90 · effort xs · error-states — Route points at a component file that does not exist
  router.js maps /settings/legacy-export to src/screens/legacy-export.jsx. That file is not in the repository (screens/ holds six files, none of them legacy-export), so the route cannot render: the user hits a module-not-found or blank screen.
  Evidence: `target-app/src/router.js:7`
  Do: Delete the route or add the screen; add a build-time check that every route component resolves.
  _Revised: p1 change severity_

### Survey - team checkup form `screen.survey`
`target-app/src/screens/survey.jsx`

- **f-0009** · should · score 2 · confidence 0.75 · effort s · accessibility — 1-5 scale is a bare number input with no anchors
  Each question is a fieldset/legend with <input type="number" min=1 max=5>. The meaning of 1 and 5 is never stated, spinner arrows are the primary affordance on desktop, and number inputs are poorly supported by screen readers for rating tasks. Native min/max validation errors are the only feedback. Not rendered: behaviour derived from reading the source.
  Evidence: `target-app/src/screens/survey.jsx:15-20`
  Do: Use a radio group per question with endpoint labels ("Strongly disagree" ... "Strongly agree") and visible focus styling.

- **f-0010** · should · score 2 · confidence 0.70 · effort s · affordance-clarity — Submit has no pending/disabled state and the handler gets the raw event
  The form passes onSubmit directly, so the consumer receives a SubmitEvent and must call preventDefault itself; if it does not the page reloads and the answers are lost. The Submit Checkup button never disables, so double-submits are possible. Not rendered: behaviour derived from reading the source.
  Evidence: `target-app/src/screens/survey.jsx:14`, `target-app/src/screens/survey.jsx:21`
  Do: Wrap: onSubmit={(e)=>{e.preventDefault(); onSubmit(new FormData(e.currentTarget));}} and disable the button while submitting.

### Survey - questions not yet loaded `screen.survey.loading`
`target-app/src/screens/survey.jsx`

- **f-0011** · should · score 1 · confidence 0.60 · effort s · loading-states — questions undefined crashes instead of loading
  questions.map is called unconditionally, so while questions are being fetched (undefined) the component throws and the user sees a blank page or the framework crash screen. There is no loading branch at all. Not rendered: behaviour derived from reading the source.
  Evidence: `target-app/src/screens/survey.jsx:15`
  Do: Accept a status prop; render a skeleton of 3 fieldsets while loading.
  _Revised: p3 change confidence_

### Legacy V1 Settings modal (open) `surface.legacy-v1-modal`
`target-app/src/screens/legacy-v1-modal.jsx`

- **f-0037** · should · score 1 · confidence 0.90 · effort s · accessibility — Legacy modal: #ccc on #fff is 1.6:1 and no dialog semantics
  Inline style color #ccc on background #fff gives a contrast ratio of about 1.6:1 (AA needs 4.5:1), so the heading and Close text are close to unreadable. The container is a div with no role="dialog", aria-modal, labelling, focus trap, Escape handling or backdrop. Nothing imports or renders this component, so it is also unreachable.
  Evidence: `target-app/src/screens/legacy-v1-modal.jsx:6`, `target-app/src/screens/legacy-v1-modal.jsx:4-10`
  Do: Delete the component if truly legacy; otherwise use theme tokens (>=4.5:1), role="dialog" aria-labelledby, focus management and Escape to close.

### Upgrade flow: billing click -> checkout -> webhook -> plan change `flow.billing-upgrade`
`target-app/src/screens/billing.jsx`

- **f-0049** · could · score 1 · confidence 0.45 · effort s · consistency — Checkout payload keys do not match the keys the billing worker reads
  billing.jsx:5 passes { plan, sourceTier } to onCheckout; billing-worker.js:3-4 reads metadata.tier and Number(metadata.seats) and defaults to 'pro' and 5. If onCheckout copies its argument into Stripe metadata verbatim, tier and seats are never set, so every upgrade becomes plan_tier 'pro' with +5 seats whatever the user chose. onCheckout is outside this workspace, hence moderate confidence.
  Evidence: `target-app/src/screens/billing.jsx:5`, `webhook-billing-slice/src/workers/billing-worker.js:3-4`
  Do: Define one shared type { tier, seats } for checkout metadata, use it in billing.jsx and the worker, and reject sessions that lack it instead of defaulting.
  _Revised: p2 change confidence, p2 change severity_

### Dashboard - user lacks workspace access `screen.dashboard.denied`
`target-app/src/screens/dashboard.jsx`

- **f-0003** · could · score 2 · confidence 0.40 · effort m · error-states — No permission-denied state: a 403 is the same raw error text
  There is no gate or role check in the screen (rg for hasPermission/isAdmin/can( returns zero). A user without access can only ever see whatever message the API puts in err.message, assuming the error branch were reachable, which it is not (see error unit). Not rendered: behaviour derived from reading the source. Reachability of a 403 depends on the API, which is not in this workspace, hence low confidence.
  Evidence: `target-app/src/screens/dashboard.jsx:15-26`
  Do: Branch on err.status === 403 and show who can grant access and a "Request access" action.
  _Revised: p1 change severity_

### Invitations - non-admin viewer `screen.invitations.denied`
`target-app/src/screens/invitations.jsx`

- **f-0028** · could · score 2 · confidence 0.40 · effort m · error-states — No permission-denied state
  There is no gate; any user who can load the route sees participant names and survey hashes (a credential). Reachability depends on server enforcement, not visible here. Not rendered: behaviour derived from reading the source.
  Evidence: `target-app/src/screens/invitations.jsx:3-28`
  Do: Gate on admin role and show an explanatory denied state.
  _Revised: p1 change severity_

### Results - user not allowed to see combined reading `screen.results.denied`
`target-app/src/screens/results.jsx`

- **f-0021** · could · score 2 · confidence 0.40 · effort m · error-states — No permission-denied state for the combined reading
  No role check exists in the screen (rg gate lines return zero). Who may view leadership results is an unstated rule; a non-leader would see either the data or the generic locked message. Not rendered: behaviour derived from reading the source.
  Evidence: `target-app/src/screens/results.jsx:3-10`
  Do: Define the rule and render "Only workspace owners can see results" with who to ask.
  _Revised: p1 change severity_

### Survey - zero questions `screen.survey.empty`
`target-app/src/screens/survey.jsx`

- **f-0012** · could · score 2 · confidence 0.60 · effort s · empty-states — Zero questions renders an empty form with a Submit button
  With questions=[] the user sees the privacy header, nothing else, and a Submit Checkup button that submits an empty form. Not rendered: behaviour derived from reading the source.
  Evidence: `target-app/src/screens/survey.jsx:14-22`
  Do: Render "This checkup has no questions yet" and hide Submit.

### Through-line: what is wrong with this product as a whole `app.through-line`
`target-app/src/router.js`

- **f-0052** · note · score 2 · confidence 0.75 · effort l · consistency — Through-line
  This workspace is not carelessly built, it is unspecified at its seams: each file is small and locally plausible, and every must-level defect is a place where two files disagree about a rule that was never written down once. billing.jsx sends plan 'business' for the Pro card; the worker reads tier and seats keys the UI never sets; the webhook records an event as handled before the handling succeeds; survey.jsx promises a cohort of 3 while results.jsx unlocks at 1 and invitations.jsx prints named scores; the members query forgets the tenant filter the campaign query remembered. The screens render only the happy path because their props carry data but no status, so loading, error, denied and payment-failed states cannot exist rather than merely being undrawn. The fix is to write four contracts - minimum cohort, checkout metadata shape, event idempotency, and async status - not to patch twelve screens. No unit scores above 3: nothing here has been chosen yet, which is also why there is nothing wrong with the taste and everything wrong with the decisions.
  Evidence: `target-app/src/screens/billing.jsx:5`, `webhook-billing-slice/src/workers/billing-worker.js:3-4`, `webhook-billing-slice/src/routes/stripe-webhook.js:12-28`, `target-app/src/screens/survey.jsx:9-11`, `target-app/src/screens/results.jsx:4`, `target-app/src/actions/team-actions.js:5`, `target-app/src/actions/team-actions.js:12`
  Do: Before fixing individual screens, write the four contracts as shared constants/types (MIN_COHORT, CheckoutMetadata, processed-event semantics, Async<T> status) and make each file import them.

### sql tagged-template helper `lib.safe-query`
`target-app/src/lib/safe-query.js`

- **f-0043** · note · score 3 · confidence 0.70 · effort xs · consistency — sql tag correctly parameterizes values
  Each interpolated value becomes $n with the value placed in values, so the template literal cannot inject SQL. This is a competent choice; limitation is no fragment composition and no undefined guard.
  Evidence: `target-app/src/lib/safe-query.js:1-10`
  Do: Throw on undefined values; support nested fragments if needed.
  _Revised: p3 change score_

## Retracted

Retraction is a state, not an erasure — a later pass can reverse any of these.

- `f-0008` (screen.survey) — Privacy promise contradicts what the product shows leadership · retracted in pass 2 by the skeptic: Absorbed by f-0048 (cohort contract), f-0017 (results guard+copy) and f-0022 (individual score): same false-promise root and same fix. Unit screen.survey retains f-0009/f-0010. Opened survey.jsx:8-12 and results.jsx:4 again - claim holds, but as a separate must it double-counts.
- `f-0015` (screen.results) — Results shows a single percentage with no breakdown · retracted in pass 1 by the skeptic: 'Single percentage, no breakdown' is an adjective with no measurement or failing task; a 3 with no change named. Unit screen.results retains f-0016 (aggregate guard).
- `f-0024` (screen.invitations) — Table is semantic but headers lack scope and status relies on text only · retracted in pass 1 by the skeptic: Cites missing scope=col on a simple one-header-row table - browsers infer column scope and no user task is named as harder; theoretical harm, taste. Unit screen.invitations keeps f-0022/f-0023.

## Deliberation

### Pass 1

- **skeptic** — Pass 1 mixes UI-lens judgments with backend security findings. dashboard.jsx:15-17 setIsLoading never called in catch -> error banner unreachable CONFIRMED by reading; f-0007-style 'denied' units (dashboard/results/invitations/billing, conf 0.4) are hypotheses: no gate code exists and server enforcement is outside the workspace -> keep but flag as unverified, do not let them stay should. lib.safe-query 4/note holds: values bound as $n, no injection. Dimension labels for backend units (accessibility on the tenant-scope bug) are a misfit -> fix. Nothing rendered, so unit-level visual claims stay <1.0.
- **builder** — Most findings name file:line and a change, but several recommendations are vague: invitations 'Add scope=col' is cosmetic; results.error-export lacks a done-criterion; the Pro/Business bug needs the exact one-line fix (onCheckout({plan: tier})) and a test assertion; webhook retry fix needs a concrete transaction shape. Also effort estimates are skewed to s/m and the unrouted LegacyV1Modal has no owner.
- **dreamer** — Read as a set: three screens (invitations, results, survey) form one trust failure around the 3-person privacy promise - n>=1 gate, per-person score column, magic hash printed as text. Billing->webhook is a second chain: wrong plan sent (billing.jsx:5) -> webhook marks event done before upgrade -> worker trusts defaults. A third systemic gap: every data screen crashes on undefined props (survey.questions, invitations.participants, billing.invoices) because no screen has a loading branch except dashboard - a missing status/loading primitive. Also no nav shell and no 404.
- **empath** — Reach x stakes x recoverability: billing Pro->Business is billed money to every upgrader (stakes high, recoverability low) so must stays. Survey respondents arrive from an email link with no context (survey.error-invalid-link, survey.submitted) and are the audience whose trust the privacy copy buys; the false promise outranks any polish. Dashboard wizard 'Internal schema version' is seen by every new customer exactly once - first impression, keep as must. Legacy export route and legacy modal are low reach (nothing links to them) so legacy modal accessibility stays should not must, and the router 404 is should.

Resolution: 3 add, 4 edit, 5 change, 2 delete, 3 unit-add (plus 46 findings seeded by `ponder grade` before the argument).

### Pass 2

- **skeptic** — Re-opened sources with rg: setIsLoading appears only at dashboard.jsx:4 and :13 (then-branch) -> f-0002 holds, error banner unreachable. tenant appears only on the campaigns query (team-actions.js:5), not the members query at :12 -> f-0041 holds. Contrast #ccc on #fff measured 1.61:1 -> f-0037 holds. No Date.now/tolerance anywhere in webhook-crypto.js -> f-0046 holds. No BEGIN/ROLLBACK/DELETE in the webhook slice -> f-0044 holds. Retract f-0008: the survey-copy contradiction is absorbed by f-0048 (cohort contract) + f-0017 + f-0022; same sentence, same fix. f-0049 depends on onCheckout, which is not in this workspace: confidence 0.55 overstated -> lower and reduce to could. Denied units f-0003/21/28/35 stay hypotheses (rg gate lines return zero, server unknown).
- **builder** — f-0006 mixes two claims: 'no primary action' (screen-local, keep) and 'no links to other pages' (owned by f-0040 nav-shell) -> edit f-0006 to drop the link claim. f-0038 router-table finding also restates the dangling route owned by f-0036 -> edit it to the auth/default-route gap only. f-0045 worker lacks two concrete failure modes found on re-read: customer_email can be null on Checkout sessions (details live in customer_details) which throws 'Organization not found' and, with f-0044, loses the upgrade permanently; and seat_limit is incremented rather than set, so any replayed or double event adds seats. Fold both into f-0045 detail and recommendation.
- **dreamer** — Read the full state space the system can reach vs what the UI draws: the webhook records every event type but only acts on checkout.session.completed (stripe-webhook.js:22), so invoice.payment_failed, customer.subscription.deleted and downgrades never update anything. The billing screen therefore has no payment-failed or cancelled unit and cannot have one -> unit-add screen.billing.payment-failed and a finding. Also STRIPE_WEBHOOK_SECRET unset makes verifyStripeSignature return false for every event (webhook-crypto.js:4) so a misconfigured deploy returns 401 silently - add. Enumeration re-check: sweep 1 router (6 routes, 1 dangling), 1b currentStep (2 arms: welcome, fallthrough), sweep 2 (1 modal), sweep 3, sweep 4 (zero nav) all closed; no stories or html files exist, zero explained. No other unit missing. Through-line deferred to pass 3 per lens.
- **empath** — Re-ranked by reach x stakes x recoverability. Billing Pro->Business (f-0029): every upgrader, money, hard to reverse -> must holds. Webhook retry loss (f-0044): every paid customer on a transient DB error, support ticket and refund -> must holds. Survey invalid-link/submitted (f-0013/f-0014): every respondent, first and only contact with the product -> must holds; confidence 0.6/0.7 because the container code is not in this workspace. f-0049 cross-file key mismatch cannot be confirmed (onCheckout absent) -> confidence 0.45, severity could. The payment-failed gap (new) is should: reach moderate (customers whose card lapses), stakes high (they lose service unaware), but unverified how the product bills, conf 0.5. No must is under 0.5 confidence.

Resolution: 2 add, 3 edit, 1 change, 1 delete, 1 unit-add.

### Pass 3

- **skeptic** — Walked every finding for taste-vs-evidence. Every must (f-0002, f-0004, f-0013, f-0014, f-0017, f-0022, f-0029, f-0034, f-0036?, f-0041, f-0044, f-0045, f-0048) has a file:line anchor that was opened in passes 1-2 and the grep re-checks held (setIsLoading, tenant filter, contrast 1.61:1, absent BEGIN/ROLLBACK). No finding is scored 5, so the top-of-scale honesty check is vacuous; the distribution is 1s and 2s because the code shows no designed states, not because of flattery. One real inflation: f-0043 scored 4 for a ten-line helper that is competent but chosen by nobody (a tagged template over $n) - that is a 3. The four crash-on-undefined findings (f-0011/19/26/33) only crash if a caller passes undefined; the callers are not in this workspace, so 0.8 confidence overstated. No delete warranted this pass: the retractions that mattered (f-0015, f-0024, f-0008) are already made.
- **builder** — Re-read each recommendation for where/what/done. The must-level ones all name file, line, replacement and a check (f-0029 test on plan, f-0044 transaction shape and retry test, f-0045 allow-list plus paid check). One gap: f-0047 (shared status primitive) states the fix but not its dependency on callers; add that so the reader knows to read the container code first. I deliberately did not re-point the four per-screen crash findings at f-0047 - that would be cosmetic churn and each already names its own one-line guard.
- **dreamer** — Read the 51 findings as a set. Three columns: loading (4 units, all 1s), error (9 units, 1s and 2s), denied (5 units, all unverified hypotheses). No unit scores above 3 anywhere, so there is no 'good thing worth propagating' to add; I looked (lib.safe-query is the only competent thing and it is a 3). Four contracts recur and none is written down once: (1) cohort size 3 vs 1, (2) the checkout payload keys vs worker metadata keys, (3) 'processed' means recorded before it means done, (4) screen props carry no status. That is the through-line - added as one finding. Enumeration unchanged from pass 2: 6 routes, 2 wizard arms, 1 modal, 0 nav, 0 stories - nothing new surfaced when re-running sweeps.
- **empath** — Re-ranked after setting reach x stakes x recoverability against the pass-2 set. No severity moves: the musts are the ones that bill customers (f-0029, f-0044), mislead respondents about privacy (f-0017, f-0022, f-0014, f-0013) or cross tenants (f-0041). Confidence moves only on the crash-on-undefined cluster: the claim is true of the component code but depends on whether callers default props, so 0.6 for the four per-screen findings and 0.7 for the systemic f-0047. f-0043 drops to 3 (competent, nothing chosen). Every open must has confidence >= 0.5 (lowest f-0013 at 0.6).

Resolution: 1 add, 1 edit, 6 change, 1 unit-add.

### Pass 4

- **skeptic** — Adversarial re-read of every must against the source this pass. survey.jsx:14-21 still shows onSubmit passed raw and a bare number input (f-0009/f-0010 hold). team-actions.js:12 members query still lacks tenant_id (f-0041 holds); rg for unique/ON CONFLICT finds the only conflict clause in the whole workspace at stripe-webhook.js:13, so f-0042 'duplicates' is an assumption about a schema we cannot see - it may throw on a unique constraint instead; the claim needs softening, the finding stays. rg href/navigate/<Link finds only the PDF anchor at results.jsx:16 so f-0040 holds. The two lowest-confidence musts (f-0013 at 0.6, f-0014 at 0.7) are explicitly marked as depending on container code outside the workspace; I tried to argue them down and could not do so without new evidence. No finding is retracted.
- **builder** — Rechecked that each open must still has where/what/done: f-0002, f-0004, f-0013, f-0014, f-0017, f-0022, f-0029, f-0034, f-0041, f-0044, f-0045, f-0048 all name file and line and a change. The only wording defect is f-0042, which asserts duplicate inserts without knowing the schema; fix the wording to cover both outcomes (duplicate row or aborted loop) and keep the same recommendation (ON CONFLICT DO NOTHING inside a transaction).
- **dreamer** — Re-ran the five sweeps mentally against the 41-unit inventory: routes (6, one dangling), 1b currentStep (2 arms, folded into wizard-welcome and overview), modal (1), nav diff (zero links, both directions empty), gate greps (role zero, plan only in the worker). Every screen has loading/empty/error/denied or a recorded reason. The set-level read is unchanged from the pass-3 through-line f-0052, which I re-read against the current set and find still accurate: the four contracts still explain the musts. No new class of unit or finding emerged, so I add nothing.
- **empath** — Re-ranked once more by reach x stakes x recoverability and moved nothing: money (f-0029, f-0044) and respondent trust (f-0017, f-0022) stay on top; tenant leak f-0041 is high stakes but needs a malicious or buggy caller (lower reach); wizard f-0004 is first-run only. All open musts have confidence >= 0.6. Unverified denied hypotheses stay at could. No severity, score or confidence change is justified by anything new.

Resolution: 1 edit.

### Pass 5

- **skeptic** — Re-checked all 12 open musts (f-0002, f-0004, f-0013, f-0014, f-0017, f-0022, f-0029, f-0034, f-0041, f-0044, f-0045, f-0048) against the cited lines; each anchor still exists and says what the finding says (line counts of all 12 source files are unchanged since pass 1, so nothing moved under the evidence). Every must is >= 0.6 confidence. The 5 unverified denied hypotheses stay at could/should with conf 0.4 and the detail says why. Nothing is cited as an adjective, no score of 5 exists to inflate. Held, nothing to retract.
- **builder** — Re-read all 12 musts for where/what/done: each names file and line, the replacement, and a check a reviewer can run (plan-sent test for f-0029, retry-after-throw test for f-0044, tenant filter for f-0041, MIN_COHORT shared constant for f-0048). The f-0042 wording fixed in pass 4 matches the source. Nothing left that needs another meeting.
- **dreamer** — Read the 52-finding set as columns once more: loading, empty, error, denied each stand as units for the 5 data screens plus survey/results, the through-line f-0052 still names the same four missing contracts, and no new class (no unit, no cross-file contract, no unreachable state) appeared when re-walking sweeps 1, 1b, 2, 3, 4 and the cross-file chain billing.jsx -> webhook -> worker. Nothing to add; adding for the sake of it would be a manufactured delta.
- **empath** — Re-ranked reach x stakes x recoverability against the final set: the top six (f-0029, f-0044, f-0045, f-0017, f-0022, f-0041) are money, respondent trust and cross-tenant data and they are still the top six; first-run-only wizard (f-0004) and unrouted legacy surfaces (f-0036, f-0037) sit below. No severity, score or confidence needs to move. Confidence floor is 0.6 on every open must.

Resolution: no deltas.

## Ledger

81 deltas across 5 passes: 52 add, 9 edit, 12 change, 3 delete, 5 unit-add.

| Pass | Deltas | Perspectives |
|---:|---|---|
| 1 | 49 add, 4 edit, 5 change, 2 delete, 3 unit-add | builder, dreamer, empath, skeptic |
| 2 | 2 add, 3 edit, 1 change, 1 delete, 1 unit-add | builder, dreamer, empath, skeptic |
| 3 | 1 add, 1 edit, 6 change, 1 unit-add | builder, dreamer, empath |
| 4 | 1 edit | builder |
| 5 | no deltas | — |

The full append-only record is `ledger.jsonl`.

---

*Generated by [Ponder](https://github.com/Quinnod345/ponder) — AI that knows when to speak, and when to shut up.*
