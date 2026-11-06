# Ponder — full-audit

`full-audit-2026-11-06` · lens **ui** · status **converged** · 4 passes of a 5-pass budget · generated 2026-11-06T15:48:06.531Z

| | |
|---|---|
| Subject | full-audit |
| Lens | ui — unit = screen, 12 dimensions |
| Project | `/tmp/ponder-eval/models/claude-haiku-5-5` |
| Passes | 4 run · min 2 · max 5 |
| Coverage | 1.00 — 37 of 37 screens graded |
| Findings | 47 total · 45 open · 0 resolved · 0 deferred · 2 retracted |
| Final verdict | stop (converged) → decided **stop** |
| OCA | reachable · ref 279738 |

## Convergence

| Pass | Coverage | Novelty | Churn | Thrash | Surprise | Stall | Conf-floor | Voices | Advice | Decision |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|---|
| 1 | 1.00 | — | — | — | — | 0 | 0.00 | 4 | continue (min-passes) | continue |
| 2 | 1.00 | 0.07 | 0.30 | 0.00 | 0.15 | 0 | 0.00 | 4 | continue (default) | continue |
| 3 | 1.00 | 0.02 | 0.09 | 0.00 | 0.03 | 0 | 0.00 | 4 | continue (default) | continue |
| 4 | 1.00 | 0.00 | 0.00 | 0.00 | 0.00 | 1 | 0.00 | 4 | stop (converged) | stop |

`—` on pass 1 is not a zero. Novelty, churn, thrash and surprise measure change against a previous pass, and pass 1 has none.

## Overrides

None. Every decision followed the engine's advice.

## Prediction vs reality

| Pass | Predicted churn | Actual churn | Surprise | Claim |
|---:|---:|---:|---:|---|
| 1 | 0.90 | — | — | Pass 1 will find many state-variant units (loading/error/empty) with no code, the dashboard error-path lockup, the billing plan mismatch, the results threshold contradicting the privacy promise, and backend webhook/billing failure handling that the ui lens does not natively cover. |
| 2 | 0.45 | 0.30 | 0.15 | Pass 2 will retract or reword a few low-confidence hypotheses, promote the privacy-promise contradiction to a system-level finding, and make small severity changes; novelty should be low since the inventory is already broad. |
| 3 | 0.12 | 0.09 | 0.03 | Pass 3 is systemic: the four denied findings collapse into one access-model problem by downgrading the echoes, and a through-line is written. Few revisions, so churn should drop under 0.10 and novelty under 0.05. |
| 4 | 0.00 | 0.00 | 0.00 | Pass 4 is a quiet verification pass: the musts and the through-line are re-checked against source with no new ground and no revisions expected. |

## Coverage

37 screens enumerated, 37 graded.

## Findings

### Team action: attach members to campaign `action.team.attach-members-to-campaign`
`target-app/src/actions/team-actions.js`

- **f-0038** · must · score 1 · confidence 0.90 · effort s · error-states — Any member ID is attached across tenants
  The campaign lookup is scoped by tenant_id (line 5), but the member lookup at line 12 is not. A caller can attach a member from another tenant by ID, which is cross-tenant IDOR.
  Evidence: `target-app/src/actions/team-actions.js:11-17`, `target-app/src/actions/team-actions.js:4-6`
  Do: Scope the member query by tenant_id, or verify every memberId against the tenant in one query. Add a regression test with a cross-tenant id.

- **f-0039** · should · score 2 · confidence 0.80 · effort m · consistency — No role check, and the loop issues one query per member
  Any authenticated tenant user can change campaign membership, since the action checks neither role nor permission. The loop runs one SELECT and one INSERT per member, and the INSERT has no ON CONFLICT clause, so a repeated member can create duplicate rows.
  Evidence: `target-app/src/actions/team-actions.js:3-20`
  Do: Add a campaign-management role check, batch the lookup and insert, and use ON CONFLICT (campaign_id, member_id) DO NOTHING.
  _Revised: p1 change effort_

### Stripe webhook: upgrade throws after event recorded `flow.stripe-webhook.processing-failure`
`webhook-billing-slice/src/routes/stripe-webhook.js`

- **f-0032** · must · score 1 · confidence 0.90 · effort s · error-states — A failed upgrade is recorded as processed and then never retried
  The event row is inserted before applyPlanUpgrade and there is no transaction. If the upgrade throws, the handler returns 500 but the row stays. Stripe's retry hits rowCount 0 and gets 200 duplicate: true, so the upgrade is never applied and the event is never retried.
  Evidence: `webhook-billing-slice/src/routes/stripe-webhook.js:12-28`
  Do: Wrap the event insert and the upgrade in one transaction, so a failure rolls back the event row. Add a test that forces the upgrade to throw and then checks that a retry applies it.

### Billing: plan cards and invoices (populated) `screen.billing`
`target-app/src/screens/billing.jsx`

- **f-0021** · must · score 1 · confidence 0.95 · effort s · affordance-clarity — The Pro button starts a Business checkout
  startUpgrade ignores the tier it receives and always sends plan 'business' (line 5). The button labelled 'Upgrade to Pro' (line 14) starts a Business checkout. What the user clicks does not match what they buy.
  Evidence: `target-app/src/screens/billing.jsx:4-6,14,19`
  Do: Pass the selected tier through as the plan and add a test asserting the payload for each button.

- **f-0022** · should · score 2 · confidence 0.85 · effort s · information-hierarchy — Invoice amounts are raw numbers with no currency
  Each invoice shows inv.amount with no currency symbol, minor-unit conversion, or date, so a value like 2900 has no clear meaning.
  Evidence: `target-app/src/screens/billing.jsx:28`
  Do: Format amounts with Intl.NumberFormat using the invoice currency and show the date and status.

### Dashboard: load failure banner `screen.dashboard.error`
`target-app/src/screens/dashboard.jsx`

- **f-0004** · must · score 1 · confidence 0.90 · effort s · error-states — A failed load never shows the error; the screen spins forever
  The catch at lines 15-17 sets error but never clears isLoading. The loading check at line 20 runs first, so the error banner at line 24 is unreachable. The user sees 'Loading workspace...' indefinitely with no retry.
  Evidence: `target-app/src/screens/dashboard.jsx:9-26`
  Do: Model load state as loading \| error \| ready, render an error with a retry action, and add a test that rejects fetchSummary.

### Dashboard: 'Set up your checkup' wizard step `screen.dashboard.wizard`
`target-app/src/screens/dashboard.jsx`

- **f-0002** · must · score 1 · confidence 0.85 · effort s · affordance-clarity — Setup wizard inputs are discarded and Next leads to an unhandled step
  Both inputs are uncontrolled and never stored. Next sets currentStep to 'configure', which has no render branch, so the user lands on Workspace Overview with nothing saved. The user is misled into thinking the settings were applied.
  Evidence: `target-app/src/screens/dashboard.jsx:28-37`
  Do: Make the wizard a controlled form that saves its values and advances through real steps, or remove it until it does anything.

### Invitations: participant table (populated) `screen.invitations`
`target-app/src/screens/invitations.jsx`

- **f-0017** · must · score 1 · confidence 0.90 · effort s · consistency — Individual scores are shown in the invitations table
  Each completed participant's individualScore appears in the 'Individual Score' column. The survey promises nobody at the company sees individual answers. The table is a campaign-admin view, so the score is visible to whoever can open it.
  Evidence: `target-app/src/screens/invitations.jsx:12,21`, `target-app/src/screens/survey.jsx:8-11`
  Do: Remove the Individual Score column. Show only completion status.

- **f-0018** · should · score 2 · confidence 0.80 · effort s · affordance-clarity — Magic link is code text, not a usable link, and the token is exposed
  The survey hash is rendered inside a code element as '/survey/<hash>' with no anchor, so it cannot be opened from the table. Because the hash is the only credential for /survey/:hash, anyone who can see this table can copy and submit as that respondent.
  Evidence: `target-app/src/screens/invitations.jsx:22`
  Do: Render the link as an anchor, show it only on an explicit 'Copy link' action, and restrict the table to the admins who need it.

### Results: combined reading (populated) `screen.results`
`target-app/src/screens/results.jsx`

- **f-0011** · must · score 1 · confidence 0.90 · effort s · consistency — Combined reading unlocks after a single completed checkup
  The gate is completedCount < 1, so one person's answers become the leadership 'Combined Reading', and the heading shows the exact count (for example '(1 answered)'). The survey header promises leadership sees a combined reading only once at least 3 teammates have completed. The copy and the gate contradict each other, and the result exposes one person's answers.
  Evidence: `target-app/src/screens/results.jsx:4-5,14`, `target-app/src/screens/survey.jsx:8-11`
  Do: Raise the gate to fewer than 3 completions, and enforce the same minimum server-side for the PDF and any aggregate endpoint.

### Executive PDF export (download link) `surface.results.executive-pdf`
`target-app/src/screens/results.jsx`

- **f-0016** · must · score 1 · confidence 0.60 · effort s · consistency — PDF export shows the aggregate at the same unenforced threshold
  The 'Download Executive PDF' link is shown on the results page at the one-completion threshold. The server endpoint is not in the workspace, so whether it enforces the 3-person minimum cannot be verified here.
  Evidence: `target-app/src/screens/results.jsx:16-18`
  Do: Hide the export until the threshold is met, and enforce the same minimum in the export handler.
  _Revised: p2 change severity, p2 change score_

### Stripe webhook: checkout completed, plan applied `flow.stripe-webhook.applied`
`webhook-billing-slice/src/routes/stripe-webhook.js`

- **f-0029** · should · score 2 · confidence 0.75 · effort s · consistency — Plan is granted before the payment is confirmed
  On checkout.session.completed the handler applies the upgrade without checking payment_status. For delayed payment methods the session completes as unpaid, so the plan can be granted before any money moves.
  Evidence: `webhook-billing-slice/src/routes/stripe-webhook.js:21-23`, `webhook-billing-slice/src/workers/billing-worker.js:1-2`
  Do: Grant only when payment_status is 'paid', and handle checkout.session.async_payment_succeeded for the delayed case. Done when a checkout completed with payment_status 'unpaid' leaves the plan unchanged.
  _Revised: p2 edit recommendation_

### Signature verification helper `lib.webhook-crypto.verify-stripe-signature`
`webhook-billing-slice/src/lib/webhook-crypto.js`

- **f-0033** · should · score 2 · confidence 0.80 · effort s · error-states — Duplicate v1 signatures are collapsed, so secret rotation rejects valid deliveries
  Object.fromEntries keeps only the last key=value pair. During Stripe secret rotation the header carries several v1 values and only the last is checked. If that one is signed with the old secret, a valid delivery gets 401.
  Evidence: `webhook-billing-slice/src/lib/webhook-crypto.js:5-6`
  Do: Collect every v1 value into an array and accept if any matches, using timingSafeEqual. Add a fixture with two v1 entries.

- **f-0034** · should · score 2 · confidence 0.80 · effort s · error-states — No timestamp tolerance, so a captured delivery can be replayed
  The function never reads parts.t as an integer or compares it to the current time. Stripe recommends rejecting deliveries older than about 5 minutes. The event_id dedupe limits the impact, but a stored payload stays valid indefinitely.
  Evidence: `webhook-billing-slice/src/lib/webhook-crypto.js:3-15`
  Do: Parse t as an integer and reject it outside a 300-second window. Add tests for stale and future timestamps.

### Billing: upgrade checkout in flight `screen.billing.checkout-pending`
`target-app/src/screens/billing.jsx`

- **f-0024** · should · score 2 · confidence 0.80 · effort s · loading-states — Upgrade buttons have no pending or disabled state
  Neither button changes while the checkout request is in flight, so a double-click can start two checkouts.
  Evidence: `target-app/src/screens/billing.jsx:14,19`
  Do: Disable both buttons and show an inline spinner on the chosen one while the request is pending.

### Billing: checkout or invoice load failed `screen.billing.error`
`target-app/src/screens/billing.jsx`

- **f-0025** · should · score 2 · confidence 0.60 · effort s · error-states — A failed checkout gives the user no feedback in this component
  The click handler returns onCheckout's promise but does not handle its rejection, and this component renders no error. A failure is silent unless the parent reports it. Code-read only.
  Evidence: `target-app/src/screens/billing.jsx:4-6,14,19`
  Do: Catch the rejection, show an inline error that says the checkout did not start and that no charge was made, and offer a retry.

### Billing: no invoices yet `screen.billing.no-invoices`
`target-app/src/screens/billing.jsx`

- **f-0023** · should · score 2 · confidence 0.85 · effort s · empty-states — 'No invoices' is a bare string with no cause or action
  A plain div reads 'No invoices'. It does not say when invoices appear, which is the question a new customer has.
  Evidence: `target-app/src/screens/billing.jsx:25-27`
  Do: Say 'Invoices appear here after your first billing cycle' and link to the plan details.

### Dashboard: workspace overview (populated) `screen.dashboard`
`target-app/src/screens/dashboard.jsx`

- **f-0001** · should · score 2 · confidence 0.70 · effort s · information-hierarchy — Populated overview is one sentence with no next action
  After setup the page shows h1 'Workspace Overview' and a single line 'Active campaigns: N'. No campaign list, no primary action, and nothing to act on. Code-read only; not rendered.
  Evidence: `target-app/src/screens/dashboard.jsx:39-44`
  Do: Show the active campaigns as a list with a primary 'New campaign' action, and keep the count as a summary rather than the whole screen.

- **f-0047** · should · score 2 · confidence 0.70 · effort l · consistency — Through-line
  This product is not badly designed. It is under-decided. Its one stated promise, that individual answers stay private and leadership sees a combined reading only after 3 people complete, is written as copy and enforced nowhere in the subject. The survey header states it (survey.jsx:8-11). The results gate uses 1 (results.jsx:4-5). The invitations table shows each person's score (invitations.jsx:12,21). The PDF export ships the same aggregate with no check (results.jsx:16). The billing button labelled Pro sends Business (billing.jsx:5,14). The webhook marks an event processed before the upgrade succeeds (stripe-webhook.js:12-28). Every serious finding is a seam where a stated promise stops at a component boundary. The empty states (four treatments), the denied states (none exist) and the missing navigation shell are the same seam at another layer: the product was designed as copy and built as components, with no shared policy between them. The fix is one decision, a disclosure and access policy enforced on the server and quoted by the copy, not a set of screen fixes. This would be falsified by a server-side threshold check and a role gate outside the subject, which the subject does not show.
  Evidence: `target-app/src/screens/survey.jsx:8-11`, `target-app/src/screens/results.jsx:4-5,16`, `target-app/src/screens/invitations.jsx:12,21`, `target-app/src/screens/billing.jsx:5,14`, `webhook-billing-slice/src/routes/stripe-webhook.js:12-28`
  Do: Write the disclosure and access policy once, enforce it in the server handlers for results, export, invitations and billing, and make the survey copy and empty states quote the same thresholds.

- **f-0042** · should · score 2 · confidence 0.50 · effort m · affordance-clarity — No navigation reaches any route; every screen is an orphan in the subject
  Sweep 4 found no Link, NavLink, router.push or navigate call in the subject, except the PDF href on results. The six router entries and the wizard have no path between them, so a user cannot reach /results, /invitations or /billing from the dashboard. Whether a shell lives outside the subject is unknown, so confidence is 0.5.
  Evidence: `target-app/src/router.js:2-7`, `target-app/src/screens/dashboard.jsx:39-44`
  Do: Add a persistent navigation shell with a link to each route, or record where the shell lives so the subject can be audited with it. Done when /results, /invitations and /billing each have an in-app link reachable from /dashboard.
  _Revised: p2 edit recommendation_

### Dashboard: zero active campaigns `screen.dashboard.empty`
`target-app/src/screens/dashboard.jsx`

- **f-0043** · should · score 2 · confidence 0.75 · effort m · empty-states — No shared empty-state primitive: four empty screens, four treatments
  Dashboard shows 'Active campaigns: 0'. Results shows a sentence with the wrong threshold. Invitations shows headers over an empty body. Billing shows a bare 'No invoices' string. None of the four imports an empty-state component, so each invented its own.
  Evidence: `target-app/src/screens/dashboard.jsx:42`, `target-app/src/screens/results.jsx:6-8`, `target-app/src/screens/invitations.jsx:17-18`, `target-app/src/screens/billing.jsx:25-27`
  Do: Create one EmptyState component with a cause line, an expectation line and one action, and use it on all four screens.

### Dashboard: loading skeleton `screen.dashboard.loading`
`target-app/src/screens/dashboard.jsx`

- **f-0003** · should · score 2 · confidence 0.80 · effort s · loading-states — Loading state is a bare text line with no content shape
  The skeleton is a div reading 'Loading workspace...' with aria-busy. It has no layout resembling the overview, so the content jumps when data arrives. It appears on the first frame, so a fast response flashes it.
  Evidence: `target-app/src/screens/dashboard.jsx:20-22`
  Do: Replace the text with a skeleton that matches the overview geometry, and delay the loader about 300ms so fast responses do not flash.

### Invitations: viewer without admin rights `screen.invitations.denied`
`target-app/src/screens/invitations.jsx`

- **f-0041** · should · score 1 · confidence 0.60 · effort m · error-states — No permission-denied state; any reachable viewer sees the admin table
  Sweep 3 greps for hasPermission, requireRole, isAdmin, can() and featureFlag returned nothing in the subject. The route /invitations renders the full participant table for any signed-in viewer, so the denied state is reachable but not designed. Code-read only.
  Evidence: `target-app/src/router.js:5`, `target-app/src/screens/invitations.jsx:3-29`, `target-app/src/actions/team-actions.js:3-9`
  Do: Gate the route by role, and render a denied state that names the missing permission and who can grant it.

### Invitations: no participants `screen.invitations.empty`
`target-app/src/screens/invitations.jsx`

- **f-0019** · should · score 2 · confidence 0.85 · effort s · empty-states — No participants renders headers over an empty body
  With an empty participants array the table shows four column headers and no rows. No copy says why or what to do next (for example 'Add people to start the checkup').
  Evidence: `target-app/src/screens/invitations.jsx:17-18`
  Do: Render an empty state with the reason and an 'Add participants' action in place of the table body.

### Unmatched route (no catch-all) `screen.not-found`
`target-app/src/router.js`

- **f-0028** · should · score 2 · confidence 0.50 · effort xs · error-states — No catch-all route, so unknown URLs fall through to the framework
  The router has six entries and no path '*'. An unmatched URL renders whatever the framework does by default, which is not designed. Hypothesis from code; not rendered.
  Evidence: `target-app/src/router.js:1-8`
  Do: Add a catch-all route to a not-found screen with a link back to the dashboard.

### Results: locked until first completion `screen.results.empty`
`target-app/src/screens/results.jsx`

- **f-0013** · should · score 2 · confidence 0.85 · effort s · empty-states — Locked-results copy states the wrong threshold and gives no progress
  'Results unlock as soon as one person completes a checkup' is wrong, because the product promises 3. The copy gives no progress toward the threshold and no action such as sending reminders.
  Evidence: `target-app/src/screens/results.jsx:6-8`, `target-app/src/screens/survey.jsx:8-11`
  Do: Say 'Results unlock after 3 people complete the checkup (1 of 3 so far)' and offer a reminder action.

### Results: aggregate failed to load `screen.results.error`
`target-app/src/screens/results.jsx`

- **f-0015** · should · score 1 · confidence 0.60 · effort s · error-states — Undefined aggregate throws and takes the whole page down
  When campaign.completedCount is at least 1 and aggregate is undefined, line 15 reads aggregate.overall and throws a TypeError. Nothing in this component guards that case or renders a failure state. Hypothesis from code; the parent's handling is not visible.
  Evidence: `target-app/src/screens/results.jsx:15`
  Do: Guard aggregate, render an error with a retry action, and keep the header and export link visible.

### Settings: legacy export (routed, screen file missing) `screen.settings.legacy-export`
`target-app/src/router.js`

- **f-0026** · should · score 2 · confidence 0.95 · effort xs · error-states — Route points at a screen file that does not exist
  /settings/legacy-export is declared in the router, but src/screens/legacy-export.jsx is not in the workspace. Navigating there has no screen to render.
  Evidence: `target-app/src/router.js:7`
  Do: Add the screen or remove the route. If the legacy export is retired, delete both.
  _Revised: p1 change severity, p1 change score_

### Survey: team checkup form `screen.survey`
`target-app/src/screens/survey.jsx`

- **f-0007** · should · score 2 · confidence 0.80 · effort s · affordance-clarity — Scale inputs have no labels for the 1-5 meaning
  Each question is a bare number input with min 1 and max 5. Nothing says what 1 or 5 means, so respondents must guess the scale direction.
  Evidence: `target-app/src/screens/survey.jsx:15-19`
  Do: Replace the number box with a labelled 1-5 scale (for example 'Strongly disagree' to 'Strongly agree') and keep the native fieldset semantics.

- **f-0006** · note · score 4 · confidence 0.80 · effort xs · copy-tone — Privacy promise is specific and names the threshold
  The header states that nobody at the company sees individual answers and that leadership sees one combined reading after at least 3 teammates complete. That is a decision stated in plain words with the threshold named. Points off because the results screen does not enforce the threshold (see screen.results).
  Evidence: `target-app/src/screens/survey.jsx:7-12`
  Do: Keep the copy. Make the product enforce the threshold it describes.

### Survey: invalid or expired magic link `screen.survey.error`
`target-app/src/router.js`

- **f-0009** · should · score 2 · confidence 0.40 · effort s · error-states — Invalid or expired magic link has no designed state in the subject
  The route /survey/:hash is the only entry point, and no error or not-found component is visible in the workspace. What a bad hash renders is not shown. Hypothesis: the user sees a blank page or the framework default. Not rendered.
  Evidence: `target-app/src/router.js:3`
  Do: Render an invalid-link state that says the link is expired or wrong and gives a contact path. Done when a request to /survey/<unknown-hash> shows that state, not a blank page.
  _Revised: p1 edit recommendation_

### Survey: confirmation after submit `screen.survey.submitted`
`target-app/src/screens/survey.jsx`

- **f-0010** · should · score 2 · confidence 0.40 · effort s · copy-tone — No confirmation is rendered after submit
  The component has no confirmation branch. Whatever the parent does after onSubmit is invisible from the subject, so the respondent may not know the answers were received.
  Evidence: `target-app/src/screens/survey.jsx:14-22`
  Do: Render a confirmation that says the answers were received, that they stay private, and when the combined reading is available.

### Survey: submitting state after submit `screen.survey.submitting`
`target-app/src/screens/survey.jsx`

- **f-0008** · should · score 2 · confidence 0.60 · effort s · loading-states — No submitting state; a long survey can be double-submitted
  The submit button has no pending or disabled state in this component. Code-read only, so the parent handler may add one, but nothing in the subject shows it.
  Evidence: `target-app/src/screens/survey.jsx:21`
  Do: Disable the submit button and show a progress message while the submit request is in flight.

### Billing worker: apply plan upgrade `worker.billing.apply-plan-upgrade`
`webhook-billing-slice/src/workers/billing-worker.js`

- **f-0035** · should · score 2 · confidence 0.80 · effort s · consistency — Seat limit is a read-modify-write that loses concurrent increments
  The worker reads seat_limit, adds seatDelta in JavaScript, and writes the result. Two events for one organization that run together can lose an increment. Event dedupe does not cover this, since the event ids differ.
  Evidence: `webhook-billing-slice/src/workers/billing-worker.js:6-20`
  Do: Use one atomic UPDATE with seat_limit = seat_limit + $n, or lock the row with SELECT ... FOR UPDATE inside a transaction.

- **f-0036** · should · score 2 · confidence 0.80 · effort s · error-states — Missing or invalid checkout metadata silently applies defaults
  Number(metadata.seats \|\| 5) produces NaN for non-numeric input, which is then written as the seat limit. A missing tier silently grants 'pro', so a checkout that drops the tier would upgrade a Business buyer to Pro.
  Evidence: `webhook-billing-slice/src/workers/billing-worker.js:3-4,15`
  Do: Validate tier against an allowlist and seats as a positive integer. Reject and alert on missing metadata instead of defaulting.

### Billing worker: no org for billing email `worker.billing.org-not-found`
`webhook-billing-slice/src/workers/billing-worker.js`

- **f-0037** · should · score 2 · confidence 0.80 · effort s · error-states — Org is matched by billing email and a missing email becomes a raw error
  The lookup uses billing_email = customer_email. A null or differently cased email finds no org and throws 'Organization not found for billing email', which the route returns to Stripe as err.message (stripe-webhook.js:27). A shared email can also upgrade the wrong organization.
  Evidence: `webhook-billing-slice/src/workers/billing-worker.js:6-12`, `webhook-billing-slice/src/routes/stripe-webhook.js:27`
  Do: Carry the org id in client_reference_id or metadata and look it up by that id. Log internal errors and return a generic message to Stripe. Done when a checkout with no matching org is logged internally and the webhook response carries no internal text.
  _Revised: p2 edit recommendation_

### Stripe webhook: invalid signature rejected `flow.stripe-webhook.invalid-signature`
`webhook-billing-slice/src/routes/stripe-webhook.js`

- **f-0031** · could · score 3 · confidence 0.80 · effort xs · error-states — Signature failure returns 401, but a signed non-JSON body throws
  The 401 path returns a JSON error and does not reveal why. JSON.parse at line 11 sits outside any try block, so a payload that passes verification but is not valid JSON throws an unhandled error rather than a 400.
  Evidence: `webhook-billing-slice/src/routes/stripe-webhook.js:6-11`
  Do: Wrap the parse in try/catch and return 400 for invalid JSON. Keep the 401 for bad signatures.

### SQL tag helper (safe-query) `lib.safe-query.sql`
`target-app/src/lib/safe-query.js`

- **f-0040** · could · score 3 · confidence 0.80 · effort xs · consistency — Tag parameterizes values but its name implies it guards identifiers too
  Interpolated values become $n placeholders, which is correct for data. Identifiers are emitted raw. The name 'safe-query' suggests a broader guarantee than the helper gives.
  Evidence: `target-app/src/lib/safe-query.js:1-10`
  Do: Document that only values are parameterized. Add an identifier() helper that checks against an allowlist for dynamic names.

### Billing: viewer without billing rights `screen.billing.denied`
`target-app/src/screens/billing.jsx`

- **f-0045** · could · score 1 · confidence 0.60 · effort m · error-states — No permission-denied state on billing; any viewer can start an upgrade checkout
  billing.jsx renders the plan cards and upgrade buttons with no check on who is viewing. Nothing in the subject restricts checkout to a billing owner, so the denied state is reachable but not designed. Code-read only.
  Evidence: `target-app/src/screens/billing.jsx:8-32`, `target-app/src/router.js:6`
  Do: Gate checkout by billing role and render a denied state that says who can change the plan.
  _Revised: p3 change severity_

### Dashboard: viewer without workspace access `screen.dashboard.denied`
`target-app/src/screens/dashboard.jsx`

- **f-0046** · could · score 1 · confidence 0.60 · effort m · error-states — No denied state on the dashboard; a viewer without access sees the setup wizard
  dashboard.jsx has no access check. A viewer who should not see the workspace gets the same setup wizard and overview as the owner. Code-read only, so the access model may live outside the subject.
  Evidence: `target-app/src/screens/dashboard.jsx:3-45`, `target-app/src/router.js:2`
  Do: Check workspace membership before rendering, and show a denied state that names the missing access and who can grant it.
  _Revised: p3 change severity_

### Invitations: loading `screen.invitations.loading`
`target-app/src/screens/invitations.jsx`

- **f-0020** · could · score 2 · confidence 0.40 · effort s · loading-states — No loading state for participants
  The component renders participants directly with no loading branch. Code-read only; the parent may gate it.
  Evidence: `target-app/src/screens/invitations.jsx:3-29`
  Do: Render a table skeleton with the same column widths while participants load.
  _Revised: p2 change severity_

### Legacy V1 settings modal (unrouted) `screen.legacy-v1-modal`
`target-app/src/screens/legacy-v1-modal.jsx`

- **f-0027** · could · score 1 · confidence 0.80 · effort xs · accessibility — Unrouted legacy modal has #ccc text on #fff and no dialog semantics
  Color #ccc on background #fff is a contrast ratio of 1.6:1 (AA needs 4.5:1). The dialog has no role, no aria-modal, no focus trap, and no Escape handling. Nothing in the router references it, so it is unreachable as the code stands.
  Evidence: `target-app/src/screens/legacy-v1-modal.jsx:6-9`
  Do: Delete the file if it is dead. If it is kept, use theme tokens with at least 4.5:1 contrast and add dialog semantics and focus management.

### Results: viewer without leadership rights `screen.results.denied`
`target-app/src/screens/results.jsx`

- **f-0044** · could · score 1 · confidence 0.60 · effort m · error-states — No permission-denied state on results; any reachable viewer sees the combined reading
  Sweep 3 greps for hasPermission, requireRole, isAdmin, can() and featureFlag returned nothing. results.jsx renders the combined reading for any viewer past the completion gate, and nothing in the subject restricts it to leadership. Code-read only.
  Evidence: `target-app/src/screens/results.jsx:3-21`, `target-app/src/router.js:4`
  Do: Gate the results route by role. Render a denied state that names the missing permission and who can grant it.
  _Revised: p3 change severity_

### Results: loading `screen.results.loading`
`target-app/src/screens/results.jsx`

- **f-0014** · could · score 2 · confidence 0.40 · effort s · loading-states — No loading state for the aggregate
  The component takes campaign and aggregate as props and renders immediately. Code-read only: if the parent loads aggregate later, the page shows nothing or the wrong thing until it arrives.
  Evidence: `target-app/src/screens/results.jsx:3`
  Do: Render a skeleton with the header and score geometry while aggregate loads.
  _Revised: p2 change severity_

### Stripe webhook: duplicate event acknowledged `flow.stripe-webhook.duplicate`
`webhook-billing-slice/src/routes/stripe-webhook.js`

- **f-0030** · note · score 4 · confidence 0.85 · effort xs · error-states — Duplicate deliveries are acknowledged with a clear idempotent response
  The insert uses ON CONFLICT DO NOTHING ... RETURNING, and a zero row count returns 200 with duplicate: true. The response tells Stripe the event is handled and avoids re-applying the upgrade. The good behaviour is undercut by the ordering problem in processing-failure.
  Evidence: `webhook-billing-slice/src/routes/stripe-webhook.js:12-19`
  Do: Keep the idempotency check. Move the event record into the same transaction as the upgrade.

## Retracted

Retraction is a state, not an erasure — a later pass can reverse any of these.

- `f-0005` (screen.dashboard.empty) — Zero active campaigns shows a bare count · retracted in pass 2 by the skeptic: Echo: the dashboard empty treatment is one of the four named in f-0043, the systemic empty-state finding on the same unit. Keep the systemic one and retract this restatement.
- `f-0012` (screen.results) — Overall score is a single unlabelled line · retracted in pass 1 by the skeptic: Taste, not a rule: names no measurement and no user harm, and the same sentence would fit any results page. Retracted.

## Deliberation

### Pass 1

- **skeptic** (confidence 0.85) — Re-read every must against its cited lines. The must findings hold: screen.dashboard.wizard (dashboard.jsx:28-37, values never stored), screen.dashboard.error (dashboard.jsx:15-17 never clears isLoading, so line 24 is unreachable), screen.results (results.jsx:4-5 gate at completedCount < 1 vs survey.jsx:8-11 promise of 3), screen.invitations (invitations.jsx:12,21 individual score column), screen.billing (billing.jsx:5 always sends plan 'business' while the Pro button sits at line 14), screen.settings.legacy-export (router.js:7 names a file absent from the workspace), flow.stripe-webhook.processing-failure (stripe-webhook.js:12-28 row inserted before the upgrade, no transaction), and action.team.attach-members-to-campaign (team-actions.js:12 member lookup not tenant-scoped). Each is grounded in a line I opened. Delete f-0012 (results 'overall score is a single unlabelled line'): it names no measurement and no user harm, and the same sentence would fit any results page. That is taste, not a rule. f-0009 and f-0010 rest on absent code and carry confidence 0.4, which is honest hypothesis; keep them, flagged. No other finding is a restatement.
- **builder** (confidence 0.70) — Check each finding has a where, a what and a done state. Most do. Three need a checkable done sentence: f-0009 (invalid magic link) needs 'a request to an unknown hash shows the invalid-link state, not a blank page'; f-0021 (Pro button) needs 'the checkout payload carries plan pro when the Pro button is clicked'; f-0032 (processing failure) needs 'a forced throw followed by a retry applies the upgrade'. Edit f-0009's recommendation to carry its done state. f-0021 and f-0032 already state a test and a done condition in prose. One effort estimate is wrong and belongs to Empath, not Builder: f-0039 bundles a role check with a batched insert and needs 'm', not 's'. I leave that re-grade to Empath.
- **dreamer** (confidence 0.75) — Read the set as a set, not one screen at a time. Three system-level gaps show up that no per-screen grade can see. First, no screen has a permission-denied unit: sweep 3 found zero role, permission or feature gates in the subject, so the denied variant is reachable and undesigned on the invitations screen. I add the unit screen.invitations.denied and a finding. Second, sweep 4 found no link or navigation call that reaches any of the six routes, so every screen is an orphan inside the subject. I file that once on screen.dashboard. Third, four screens with empty states use four treatments (dashboard bare count, results wrong sentence, invitations headers over nothing, billing bare string), and no shared empty-state component is imported. I file that once on screen.dashboard.empty. Watch for a through-line later: the privacy promise in survey.jsx is contradicted by results.jsx, invitations.jsx and the PDF export. That is one system fact, not three screen faults, and pass 3 should name it.
- **empath** (confidence 0.70) — Who is on each screen. The wizard and the dashboard error are first-run and recoverability-poor: a new admin who hits a failed load or loses setup values cannot recover in place, so they stay must. The billing Pro-to-Business mismatch is reach-limited to people who click Upgrade but its stakes are money, so it stays must with score 1. The results threshold and the invitations score are must: leadership and the respondents they describe are the people hurt, and a privacy leak cannot be taken back. The legacy-export dead route is reach-limited (legacy users only) and recoverable in one line, so I downgrade f-0026 from must to should and score 1 to 2. Ranking rule: reach times stakes times recoverability. The webhook processing failure stays must: a paying customer whose upgrade silently drops is hard to recover without manual reconciliation.

Resolution: 3 add, 1 edit, 2 change, 1 delete, 1 unit-add (plus 40 findings seeded by `ponder grade` before the argument).

### Pass 2

- **skeptic** (confidence 0.85) — Re-checked the cited lines for each must. All hold: dashboard.jsx:15-17 and 20-26 (error unreachable behind isLoading), results.jsx:4-5 vs survey.jsx:8-11 (threshold 1 vs 3), invitations.jsx:12,21 (individual score column), billing.jsx:5 vs 14 (Pro sends business), router.js:7 (missing file), stripe-webhook.js:12-28 (row inserted before upgrade, no transaction), team-actions.js:12 (unscoped member lookup). Retract f-0005 (dashboard.empty, 'bare count'): it is one of the four empty treatments that the systemic finding f-0043 names on the same unit, so it is an echo. Keep f-0043 and retract f-0005. f-0009 and f-0010 remain confidence 0.4 hypotheses and are not musts, so they do not block convergence. I did not delete f-0014 or f-0020 because each is the only finding on its unit, and deleting it would leave the unit ungraded.
- **builder** (confidence 0.75) — Three findings name a where and a what but no done state, so a reviewer cannot check them. f-0029 (plan granted on unpaid) needs 'a checkout completed with payment_status unpaid leaves the plan unchanged'. f-0037 (org by email) needs 'a checkout with no matching org is logged internally and Stripe receives a generic message'. f-0042 (no navigation) needs 'each of /results, /invitations and /billing has an in-app link from /dashboard'. Edit all three recommendations to carry those done states. No prose needs more than this.
- **dreamer** (confidence 0.70) — The lens requires every screen to owe a permission-denied unit, or to be ruled out with a mechanism. Sweep 3 found no role, permission or feature gate anywhere in the subject, so the denied state is reachable on results, billing and dashboard as well as invitations. I add a denied unit for each of those three, with one finding each, so the variant column is complete. Pass 3 should collapse the four denied findings (f-0041 plus these three) into one system-level finding about a missing access model. Expect that collapse, not four separate grades.
- **empath** (confidence 0.70) — Re-rank by reach times stakes times recoverability. Two loading findings (f-0014 results, f-0020 invitations) describe a state the subject never reaches on its own: the real failure is f-0015, an undefined aggregate that throws. Downgrade both to could so they do not outrank the throw. f-0016 (PDF export) moves up: the PDF leaves the app and cannot be recalled, so its recoverability is zero even though its reach is leadership only. Raise it to must, score 1, confidence 0.6, which passes the 0.5 floor. f-0029 (grant before payment) stays should: reach is limited to delayed payment methods.

Resolution: 3 add, 3 edit, 3 change, 1 delete, 3 unit-add.

### Pass 3

- **skeptic** (confidence 0.80) — Check the collapse before accepting it. The four denied findings (f-0041 invitations, f-0044 results, f-0045 billing, f-0046 dashboard) all state one fact: the subject has no role, permission or feature gate (sweep 3 grep returned none). Each unit is different, but the cause is the same. Keep f-0041 as the systemic one and downgrade the three echoes to could, because each unit still needs its own grade and deleting them would ungrade it. I also re-check the top of the scale. The only 4s are f-0006 (survey privacy copy, which names a decision and a threshold) and f-0030 (the duplicate-webhook response). The f-0030 4 rests on idempotency, which is a server decision, not a screen one, so it stays a 4 but I note it is not a UI judgment. No 5 is claimed, so no 5 needs deleting. f-0042 (no navigation) stays at confidence 0.5 because a shell may live outside the subject; the finding says so.
- **builder** (confidence 0.70) — f-0041 already names the where and the what. Its done state is 'a route-level role gate exists and a viewer without the role sees a denied state'. That is enough for the systemic finding, so no edit is needed. The three echoes need no prose change either: each already says what to gate on its own unit. I leave the edit budget at zero this pass, because churn should fall on purpose, not from rewording.
- **dreamer** (confidence 0.70) — The through-line. This product is not badly designed. It is under-decided: its one stated promise, that individual answers stay private and leadership sees a combined reading only after 3 people complete, is written as copy and enforced nowhere in the code. The survey header states it. The results gate uses 1. The invitations table shows each person's score. The PDF export ships the same aggregate with no check. The billing button labelled Pro sends Business, so the product says one plan and charges another. The webhook records an event as processed before the upgrade succeeds, so a paying customer can be marked done without the plan. Every serious finding is a seam where a stated promise stops at a component boundary. The empty states (four treatments), the denied states (none exist), and the missing navigation shell are the same seam at a different layer: the product was designed as a set of copy and implemented as a set of components, with no shared policy between them. The thing to fix is one decision, a disclosure and access policy enforced on the server and quoted by the copy, not any single screen. This is arguable: a counter-reading would say the subject is a fragment and the promise lives in code outside it, which is why the through-line states the single fact that would falsify it, the absence of a server-side threshold check in the subject.
- **empath** (confidence 0.70) — Who is hurt by the collapse. A respondent who answers honestly is the person the systemic privacy failure hits hardest: at one completion their answers are the whole combined reading, and their individual score sits in the invitations table. Re-rank: the three denied echoes (f-0044, f-0045, f-0046) are real but each is one more screen a viewer can open, so their reach stacks on f-0041 rather than adding a new cause. Downgrade them to could so the ranking reflects one cause, one fix. Keep f-0041 at should. The privacy items (f-0011, f-0017, f-0016) stay must because they are the ones that expose a person.

Resolution: 1 add, 3 change.

### Pass 4

- **skeptic** (confidence 0.90) — Re-verified the must set against source with grep at the cited lines, not from memory. Confirmed: router.js:7 names src/screens/legacy-export.jsx, which is absent from the workspace; no Link, NavLink, router.push or navigate call exists in target-app or webhook-billing-slice; results.jsx:4 gates at completedCount < 1; invitations.jsx:12 and :21 show individual score; billing.jsx:5 sends plan 'business' and billing.jsx:14 is the Pro button; team-actions.js:12 selects members with no tenant_id (tenant_id appears only at line 5); webhook-crypto.js:5 uses Object.fromEntries and :14 is timingSafeEqual; billing-worker.js:15 adds seatDelta; 'payment_status' appears nowhere in the webhook slice; #ccc on #fff is at legacy-v1-modal.jsx:6. Each claim held. No finding is a restatement left over from pass 3. Nothing to retract.
- **builder** (confidence 0.85) — Checked that every must and every through-line evidence path opens. The paths in f-0047 (survey.jsx:8-11, results.jsx:4-5,16, invitations.jsx:12,21, billing.jsx:5,14, stripe-webhook.js:12-28) all resolve to the lines quoted. The done states added in pass 2 (f-0029, f-0037, f-0042) read as checkable. No prose is wrong. No edit.
- **dreamer** (confidence 0.80) — Re-read the set as a set. The through-line still holds: the survey promise, the results gate, the invitations column, the PDF, the billing mismatch and the webhook ordering are each a seam where a stated promise stops at a component boundary, and the echoes now collapse into f-0041 with the three denied units at could. The falsifier in f-0047 is still the right one: a server-side threshold check or role gate outside the subject would change the reading, and the subject shows neither. I looked for new ground and found none that a unit does not already carry. Adding a finding now would be manufacturing churn, so none is added.
- **empath** (confidence 0.80) — Re-checked each re-rank against who is hurt. The privacy items (f-0011, f-0016, f-0017) stay must: they expose respondents and cannot be recalled. The billing mismatch (f-0021) stays must: the person is charged the wrong plan. The webhook drop (f-0032) stays must: a paying customer is left without a plan and no retry recovers it. The legacy dead route (f-0026) stays should. The three denied echoes stay could under the one-cause reading. Nothing needs re-grading.

Resolution: no deltas.

## Ledger

65 deltas across 4 passes: 47 add, 4 edit, 8 change, 2 delete, 4 unit-add.

| Pass | Deltas | Perspectives |
|---:|---|---|
| 1 | 43 add, 1 edit, 2 change, 1 delete, 1 unit-add | builder, dreamer, empath, skeptic |
| 2 | 3 add, 3 edit, 3 change, 1 delete, 3 unit-add | builder, dreamer, empath, skeptic |
| 3 | 1 add, 3 change | dreamer, empath |
| 4 | no deltas | — |

The full append-only record is `ledger.jsonl`.

---

*Generated by [Ponder](https://github.com/Quinnod345/ponder) — AI that knows when to speak, and when to shut up.*
