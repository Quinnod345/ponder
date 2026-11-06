# Ponder — full-audit

`full-audit-2026-11-06` · lens **ui** · status **converged** · 5 passes of a 5-pass budget · generated 2026-11-06T15:55:53.096Z

| | |
|---|---|
| Subject | full-audit |
| Lens | ui — unit = screen, 12 dimensions |
| Project | `/tmp/ponder-eval/models/claude-opus-5-5` |
| Passes | 5 run · min 2 · max 5 |
| Coverage | 1.00 — 54 of 54 screens graded |
| Findings | 79 total · 77 open · 0 resolved · 0 deferred · 2 retracted |
| Final verdict | stop (converged) → decided **stop** |
| OCA | reachable · ref 279748 |

## Convergence

| Pass | Coverage | Novelty | Churn | Thrash | Surprise | Stall | Conf-floor | Voices | Advice | Decision |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|---|
| 1 | 1.00 | — | — | — | — | 0 | 0.00 | 4 | continue (min-passes) | continue |
| 2 | 1.00 | 0.08 | 0.36 | 0.00 | 0.06 | 0 | 0.00 | 4 | continue (default) | continue |
| 3 | 1.00 | 0.04 | 0.14 | 0.09 | 0.02 | 0 | 0.00 | 4 | continue (default) | continue |
| 4 | 1.00 | 0.00 | 0.00 | 0.00 | 0.03 | 1 | 0.00 | 4 | continue (default) | continue |
| 5 | 1.00 | 0.00 | 0.00 | 0.00 | 0.02 | 2 | 0.00 | 4 | stop (converged) | stop |

`—` on pass 1 is not a zero. Novelty, churn, thrash and surprise measure change against a previous pass, and pass 1 has none.

## Overrides

None. Every decision followed the engine's advice.

## Prediction vs reality

| Pass | Predicted churn | Actual churn | Surprise | Claim |
|---:|---:|---:|---:|---|
| 1 | 0.95 | — | — | Pass 1 seeds every unit, mostly must and should on the privacy contract, billing and the webhook, after the single-shot read and a harness run of every state. |
| 2 | 0.30 | 0.36 | 0.06 | Pass 1 ranked too flat: crash echoes drop, org resolution rises to must, replay and error-leak claims weaken, and system findings for the variant columns plus anonymity differencing get added. |
| 3 | 0.12 | 0.14 | 0.02 | Pass 3 collapses to system level: the through-line, an empty-state column, an auth-boundary unit nobody enumerated, and at least one pass 2 severity that does not survive re-reading. |
| 4 | 0.03 | 0.00 | 0.03 | Pass 4 re-verifies by re-running everything and walking each user journey; expect close to no change, since the known errors were corrected in pass 3. |
| 5 | 0.02 | 0.00 | 0.02 | Pass 5 checks branch coverage and baseline recall as a different cut; expect no change unless the single-shot caught something the ledger dropped. |

## Coverage

54 screens enumerated, 54 graded.

## Findings

### startUpgrade checkout handler `action.billing.start-upgrade`
`target-app/src/screens/billing.jsx`

- **f-0044** · must · score 1 · confidence 0.99 · effort s · affordance-clarity — "Upgrade to Pro" starts a Business checkout
  startUpgrade always sends plan:"business". Clicking Pro called onCheckout with { plan: "business", sourceTier: "pro" }. A customer choosing the recommended $29 plan is sent to a $99 checkout.
  Evidence: `target-app/src/screens/billing.jsx:4-6`, `target-app/src/screens/billing.jsx:14`, `.ponder/tmp/harness/render-observations.json#action.billing.start-upgrade`
  Do: Send plan:selectedTier. Done when each button sends its own plan, with a test covering both.

### attachMembersToCampaign tenant and role scoping `action.team.attach-members`
`target-app/src/actions/team-actions.js`

- **f-0054** · must · score 1 · confidence 0.98 · effort s · auth-and-authz — Members from another tenant can be attached to a campaign
  The campaign is tenant-scoped but the member lookup uses id alone. Running it with a user from tenant A and a member from tenant B returned ok and created the link. The caller needs to know the other tenant's member id, and the id format is not visible here. If the participant query joins through campaign_members, that person's name would then appear in tenant A's invitations table, but that query is outside this workspace.
  Evidence: `target-app/src/actions/team-actions.js:4-6`, `target-app/src/actions/team-actions.js:12`, `.ponder/tmp/harness/backend-observations.json#teamAction.crossTenant`
  Do: Add tenant_id to the member query, and reject the whole request on any mismatch.
  _Revised: p2 edit detail_

- **f-0055** · should · score 2 · confidence 0.60 · effort s · auth-and-authz — The action has no role check
  Any user in the tenant can change a campaign's members, and a viewer role succeeded in the probe. The caller could enforce this, but no caller exists in scope.
  Evidence: `target-app/src/actions/team-actions.js:3`, `.ponder/tmp/harness/backend-observations.json#teamAction.viewerRoleAllowed`, `.ponder/tmp/harness/render-observations.json#closure`
  Do: Require an admin or campaign-owner role in the action.

### Dashboard fetch failed `screen.dashboard.error`
`target-app/src/screens/dashboard.jsx`

- **f-0009** · must · score 1 · confidence 0.98 · effort s · error-states — A failed load spins forever and the error banner is unreachable
  The catch handler sets error but leaves isLoading true, and the isLoading branch returns first. Running it with a rejected fetchSummary rendered "Loading workspace..." with aria-busy and no .error-banner.
  Evidence: `target-app/src/screens/dashboard.jsx:15-17`, `target-app/src/screens/dashboard.jsx:20-26`, `.ponder/tmp/harness/render-observations.json#screen.dashboard.error`
  Do: Clear isLoading in a finally block, and add a retry button to the banner. Done when a rejected fetch renders the banner.

### Setup wizard, configure step (set but has no arm) `screen.dashboard.wizard.configure`
`target-app/src/screens/dashboard.jsx`

- **f-0014** · must · score 1 · confidence 0.95 · effort m · affordance-clarity — Next discards the setup and skips to the overview
  Next sets currentStep to configure, which has no arm, so the code falls through to the overview. Both inputs are uncontrolled and unnamed, so typed values are thrown away. Clicking Next with Priority set to High rendered Workspace Overview with no inputs left and nothing saved. The user is told nothing.
  Evidence: `target-app/src/screens/dashboard.jsx:7`, `target-app/src/screens/dashboard.jsx:28-37`, `.ponder/tmp/harness/render-observations.json#screen.dashboard.wizard.configure`
  Do: Bind and save the inputs, then either build the configure step or make Next finish setup. Done when submitted values reach the API.

### Invitations table, populated `screen.invitations`
`target-app/src/screens/invitations.jsx`

- **f-0037** · must · score 1 · confidence 0.98 · effort s · trust-boundaries — Named individual scores are shown to admins
  The table renders each person's name and score, such as "Dana Completed 34%". This is the direct breach of the survey promise, and removing the column in the UI is not enough if the API still returns it.
  Evidence: `target-app/src/screens/invitations.jsx:12`, `target-app/src/screens/invitations.jsx:21`, `target-app/src/screens/survey.jsx:9-10`, `.ponder/tmp/harness/render-observations.json#screen.invitations`
  Do: Remove the column and stop sending individualScore to this screen's data source.
  _Revised: p2 edit dimension_

- **f-0038** · must · score 1 · confidence 0.90 · effort m · affordance-clarity — Magic links are visible to anyone viewing the table
  Each row shows a participant's /survey/hash path. Anyone viewing the table could open it and answer as that person, which breaks both the accuracy of the reading and the anonymity the survey promises. The rendered output shows the full path for every participant. Whether a hash can be reused is decided outside this workspace.
  Evidence: `target-app/src/screens/invitations.jsx:13`, `target-app/src/screens/invitations.jsx:22`, `.ponder/tmp/harness/render-observations.json#screen.invitations`, `.ponder/tmp/harness/render-observations.json#closure`
  Do: Stop returning surveyHash to admin views, and send links from the server only. Done when no hash appears in the invitations response.
  _Revised: p1 edit title, p1 edit detail, p1 edit recommendation, p1 change severity, p3 edit detail_

- **f-0069** · should · score 1 · confidence 0.80 · effort m · affordance-clarity — The invitations screen cannot invite anyone
  The page has zero buttons and zero links, so nobody can invite, resend or remove a participant from it. attachMembersToCampaign has no importer in the UI, so the one action that adds people is unreachable from this workspace.
  Evidence: `target-app/src/screens/invitations.jsx:3-29`, `.ponder/tmp/harness/render-observations.json#screen.invitations`, `.ponder/tmp/harness/render-observations.json#closure`
  Do: Add Invite, Resend and Remove controls wired to server actions. Done when a campaign's participants can be managed from this screen.

- **f-0035** · could · score 2 · confidence 0.80 · effort s · accessibility — Table semantics are incomplete
  Headers have no scope attribute, and the pending dash has no spoken alternative. The rendered output confirms both.
  Evidence: `target-app/src/screens/invitations.jsx:9-14`, `target-app/src/screens/invitations.jsx:21`, `.ponder/tmp/harness/render-observations.json#screen.invitations`
  Do: Add scope="col", and use a text alternative for the dash.

### Results with one or two respondents `screen.results.under-threshold`
`target-app/src/screens/results.jsx`

- **f-0029** · must · score 1 · confidence 0.98 · effort s · trust-boundaries — Results open at one respondent, revealing that person's score
  The gate is completedCount < 1. With one respondent, the page rendered "Combined Reading (1 answered)" and "Overall Score: 42%", which is that person's score. The survey promised at least 3. The PDF link is live in this state too.
  Evidence: `target-app/src/screens/results.jsx:4`, `target-app/src/screens/results.jsx:14-15`, `target-app/src/screens/survey.jsx:10-11`, `.ponder/tmp/harness/render-observations.json#screen.results.under-threshold`, `.ponder/tmp/harness/render-observations.json#screen.results.two-respondents`
  Do: Enforce a single minimum of 3 on the server, and use the same constant in the UI.
  _Revised: p2 edit dimension_

### Survey form, populated `screen.survey`
`target-app/src/screens/survey.jsx`

- **f-0016** · must · score 1 · confidence 0.98 · effort m · copy-tone — The privacy promise on the survey is false
  The survey promises that nobody at the company sees individual answers and that leadership sees only a combined reading after at least 3 completions. The invitations table shows each named person's score, and results unlock at one respondent. People answer candidly about their own leadership because of this sentence, so a false promise can cost them.
  Evidence: `target-app/src/screens/survey.jsx:8-12`, `target-app/src/screens/invitations.jsx:12`, `target-app/src/screens/invitations.jsx:21`, `target-app/src/screens/results.jsx:4`
  Do: Make the code true rather than softening the copy. That takes four fixes: remove individual scores (f-0037), enforce the threshold on the server (f-0029), stop exposing magic links (f-0038), and stop live updates that reveal one person (f-0073). Done when no admin view or API response can identify one person's answers.
  _Revised: p3 edit recommendation_

- **f-0017** · should · score 2 · confidence 0.85 · effort s · affordance-clarity — A 1 to 5 rating is a bare number box
  Each question is an empty number input with no statement of what 1 and 5 mean, which makes answers from different people hard to compare, and it is a poor fit for a phone.
  Evidence: `target-app/src/screens/survey.jsx:15-20`, `.ponder/tmp/harness/render-observations.json#screen.survey`
  Do: Use a five-option radio group with labelled ends.

- **f-0019** · should · score 2 · confidence 0.45 · effort s · consistency — Answers can land in the URL if the parent does not prevent default
  The form has no method or action and the component does not call preventDefault, so its native submission is a GET. A parent handler that fails to prevent default would put answers into the URL, browser history and server logs. No caller exists in scope, so this is unconfirmed.
  Evidence: `target-app/src/screens/survey.jsx:14`, `.ponder/tmp/harness/render-observations.json#screen.survey`
  Do: Call preventDefault in this component and set method="post".

- **f-0018** · could · score 2 · confidence 0.90 · effort s · accessibility — Rating inputs have no accessible name of their own
  The legend names the group, but each input has no label or aria-label. An automated check flags these as unlabelled controls.
  Evidence: `target-app/src/screens/survey.jsx:16-19`, `.ponder/tmp/harness/render-observations.json#screen.survey`
  Do: The radio group fix resolves this. Otherwise add aria-labelledby pointing at the legend.
  _Revised: p2 change severity_

### Webhook event dedupe `webhook.stripe.idempotency`
`webhook-billing-slice/src/routes/stripe-webhook.js`

- **f-0060** · must · score 1 · confidence 0.98 · effort m · state-and-concurrency — A failed upgrade is lost for good on retry
  The event id is committed before processing, outside any transaction. In the probe, a transient failure returned 500, Stripe's retry returned 200 duplicate, and the org was never upgraded. A concurrent duplicate gets the same result. The customer has paid and gets nothing.
  Evidence: `webhook-billing-slice/src/routes/stripe-webhook.js:12-19`, `webhook-billing-slice/src/routes/stripe-webhook.js:21-28`, `.ponder/tmp/harness/backend-observations.json#webhook.transientFailureThenRetry`, `.ponder/tmp/harness/backend-observations.json#webhook.concurrentDuplicate`
  Do: Run the dedupe insert and the upgrade in one transaction, or record processed_at after success and retry unprocessed rows. Done when a failure followed by a retry upgrades the org.

### attachMembersToCampaign failure and retry behaviour `action.team.attach-members.failure`
`target-app/src/actions/team-actions.js`

- **f-0056** · should · score 2 · confidence 0.90 · effort m · error-handling — Attach is non-atomic and reports false success
  Unknown ids are skipped and still return ok. A mid-loop failure kept the first link. Re-running throws if a unique constraint exists, or duplicates rows if not. Each member costs a lookup plus an insert.
  Evidence: `target-app/src/actions/team-actions.js:11-19`, `.ponder/tmp/harness/backend-observations.json#teamAction.unknownMemberSkippedButOk`, `.ponder/tmp/harness/backend-observations.json#teamAction.midLoopFailure`, `.ponder/tmp/harness/backend-observations.json#teamAction.reRun`, `.ponder/tmp/harness/backend-observations.json#teamAction.roundTripsForThreeIds`
  Do: Use one tenant-scoped INSERT ... SELECT ... ON CONFLICT DO NOTHING in a transaction, and return added and rejected ids.
  _Revised: p3 edit detail_

### Signature header parsing and timestamp handling `lib.webhook-crypto.header-and-timestamp`
`webhook-billing-slice/src/lib/webhook-crypto.js`

- **f-0068** · should · score 3 · confidence 0.90 · effort s · fail-closed-defaults — No timestamp tolerance, and rotated signatures can be rejected
  A five-year-old signature verified successfully, because the timestamp is signed but never compared to the clock. Event dedupe blunts this: replaying a seen event returned duplicate, and it only re-applied after its row was removed, when seats grew from 15 to 25. So exposure depends on the retention of stripe_webhook_events and on someone having captured a signed request. Separately, Object.fromEntries keeps only the last v1, so a valid event was rejected when its good signature came first. That can happen during secret rotation, when Stripe sends one v1 per active secret.
  Evidence: `webhook-billing-slice/src/lib/webhook-crypto.js:5-6`, `.ponder/tmp/harness/backend-observations.json#crypto.fiveYearOldSignatureAccepted`, `.ponder/tmp/harness/backend-observations.json#crypto.rotationGoodFirstOtherLast`
  Do: Reject timestamps outside 5 minutes and compare against every v1, or use stripe.webhooks.constructEvent.
  _Revised: p2 edit detail, p2 change score_

### Route table and its data contract `route.table`
`target-app/src/router.js`

- **f-0071** · should · score 1 · confidence 0.70 · effort m · error-states — No shared loading, error or crash boundary exists
  Reading the variant columns together: undefined data blanked survey, results, invitations and billing, and dashboard crashes with no api prop. Only the dashboard has any loading or error branch. No error boundary exists in the source, so one bad prop takes out the whole page. Each crash also has its own finding, ranked below this one.
  Evidence: `.ponder/tmp/harness/render-observations.json#screen.survey.loading`, `.ponder/tmp/harness/render-observations.json#screen.results.error`, `.ponder/tmp/harness/render-observations.json#screen.invitations.loading`, `.ponder/tmp/harness/render-observations.json#screen.billing.loading`, `.ponder/tmp/harness/render-observations.json#screen.dashboard.no-props`
  Do: Load data at the route level with one loading and error component, and wrap routes in an error boundary. Done when a failed fetch on any route shows a retry state.

- **f-0072** · should · score 1 · confidence 0.65 · effort l · error-states — The app has no concept of permissions
  Sweep 3 found zero role gates and zero plan gates across all source, and no screen accepts a role or plan prop. The denied variant of every screen is therefore whatever the server sends, and four of five screens have no way to show it. Server enforcement is outside this workspace, so it may exist there, but the UI has nowhere to show it.
  Evidence: `.ponder/tmp/harness/render-observations.json#closure`, `target-app/src/screens/invitations.jsx:3`, `target-app/src/screens/billing.jsx:3`, `target-app/src/screens/results.jsx:3`
  Do: Define roles on the server, return 403 from data routes, and render one denied state that names the role and who can grant it.

- **f-0001** · should · score 2 · confidence 0.50 · effort m · consistency — Routes carry no data contract or guards
  Each route row is a path and a string component path, with no loader, props or access metadata. Every screen needs props, and all six screens use named exports with no default export. Mounted bare, DashboardScreen crashes on api.fetchSummary. Nothing in scope imports router.js, so the real mounting code could not be inspected.
  Evidence: `target-app/src/router.js:1-8`, `.ponder/tmp/harness/render-observations.json#closure`, `.ponder/tmp/harness/render-observations.json#screen.dashboard.no-props`
  Do: Add a loader and an access field to each route row, or document where they live, so a route declares what it needs.

- **f-0078** · could · score 1 · confidence 0.85 · effort m · empty-states — No empty state offers a way forward
  Read together, the five empties are a number (dashboard), a submit button with nothing to answer (survey), a sentence (results), a bare header (invitations) and two words (billing). None offers an action. Most could not, because the create-campaign and invite controls they would link to do not exist anywhere in the UI.
  Evidence: `.ponder/tmp/harness/render-observations.json#screen.dashboard.empty`, `.ponder/tmp/harness/render-observations.json#screen.survey.empty`, `.ponder/tmp/harness/render-observations.json#screen.results.empty`, `.ponder/tmp/harness/render-observations.json#screen.invitations.empty`, `.ponder/tmp/harness/render-observations.json#screen.billing.empty`
  Do: Build the create and invite actions first, then have each empty state state its cause and link to the action that resolves it.

- **f-0070** · note · score 3 · confidence 0.95 · effort s · responsive-behaviour — Visual dimensions were not graded because no stylesheet exists
  The workspace has no CSS and no transitions, so density, responsive behaviour, motion and rendered contrast could not be measured, except the one inline colour pair on the legacy modal. All screens were rendered to the DOM through React and jsdom, and none was seen in a browser. Invitation emails, Stripe-hosted pages and the server code behind each prop are also outside this workspace. Grades here cover behaviour, structure and copy only.
  Evidence: `.ponder/tmp/harness/render-observations.json#closure`
  Do: Repeat the visual dimensions in a browser once the stylesheets are available.
  _Revised: p3 edit detail_

### Signed out or expired session on a protected screen `screen.auth.signed-out`
`target-app/src/router.js`

- **f-0077** · should · score 1 · confidence 0.55 · effort m · error-states — Signed-out and expired sessions have no screen
  The attach action takes a currentUser, so the app has signed-in users, but the route table has no sign-in route, and no source file mentions login, session or auth. Someone whose session expires mid-task has no designed path. Auth could live outside this workspace, since the source shows no sign of how it is wired.
  Evidence: `target-app/src/router.js:1-8`, `target-app/src/actions/team-actions.js:3`
  Do: Add sign-in and session-expired routes that return the person to where they were. Done when an expired session on any screen leads back there after signing in.

### Billing plans and invoices, populated `screen.billing`
`target-app/src/screens/billing.jsx`

- **f-0046** · should · score 1 · confidence 0.75 · effort s · copy-tone — Invoices are bare numbers
  An invoice renders as just "2900", with no currency, date, status or download. If amounts are stored in cents, it reads as $2900 rather than $29.
  Evidence: `target-app/src/screens/billing.jsx:28`, `.ponder/tmp/harness/render-observations.json#screen.billing`
  Do: Format the amount and add date, status and receipt link.

- **f-0045** · should · score 2 · confidence 0.80 · effort m · information-hierarchy — Plans cannot be compared and the current plan is not shown
  Each card is a name, a price and a button, with no features or seat counts, so the choice comes down to price. Nothing marks the current plan, so an existing Pro customer can "upgrade" to Pro.
  Evidence: `target-app/src/screens/billing.jsx:10-21`, `.ponder/tmp/harness/render-observations.json#screen.billing`
  Do: Give each .plan-card in billing.jsx a seat count and feature list, take a currentTier prop, and replace the matching button with a Current plan label. Done when a Pro customer cannot start a Pro checkout.
  _Revised: p2 edit recommendation_

### Billing after checkout fails `screen.billing.error`
`target-app/src/screens/billing.jsx`

- **f-0049** · should · score 1 · confidence 0.90 · effort s · error-states — A failed checkout is silent and repeatable
  onCheckout's promise is not handled. A rejection produced unhandled rejections and no message on screen, and the button stayed enabled, so a double click started two checkouts.
  Evidence: `target-app/src/screens/billing.jsx:4-6`, `.ponder/tmp/harness/render-observations.json#screen.billing.error`
  Do: Track pending state, disable the buttons during the call, and show the failure inline.

### Billing after returning from Stripe `screen.billing.post-checkout`
`target-app/src/screens/billing.jsx`

- **f-0051** · should · score 1 · confidence 0.70 · effort m · error-states — Returning from Stripe shows no confirmation
  The component reads no success, cancel or processing signal. The plan change arrives later by webhook, and a customer who has just paid sees the same upgrade buttons with no sign that it worked. If the webhook loses the event, this never changes.
  Evidence: `target-app/src/screens/billing.jsx:3-33`, `webhook-billing-slice/src/routes/stripe-webhook.js:21-25`, `.ponder/tmp/harness/render-observations.json#screen.billing.post-checkout`
  Do: Add a post-checkout state that says processing, then confirms from the server's plan value.

### Dashboard overview, populated `screen.dashboard`
`target-app/src/screens/dashboard.jsx`

- **f-0006** · should · score 2 · confidence 0.70 · effort m · information-hierarchy — The overview shows one number and no next step
  Once past the wizard, the page is a heading and "Active campaigns: 2". It does not name the campaigns, show progress, or offer an action, so it does not answer what to do next.
  Evidence: `target-app/src/screens/dashboard.jsx:39-44`, `.ponder/tmp/harness/render-observations.json#screen.dashboard`
  Do: List active campaigns with response counts and link each one to its invitations and results.

- **f-0076** · could · score 3 · confidence 0.50 · effort s · loading-states — An older dashboard response can overwrite a newer one
  The effect has no cancellation. When the api prop changed and the first request resolved last, the page showed the old value, 99 rather than 2. This needs the api prop to change identity, and no caller is in scope to say whether it does.
  Evidence: `target-app/src/screens/dashboard.jsx:9-18`, `.ponder/tmp/harness/pass2-observations.json#staleFetchOverwritesNewer`
  Do: Add an ignore flag in the effect cleanup, or use an AbortController.

### Dashboard with zero or missing campaigns `screen.dashboard.empty`
`target-app/src/screens/dashboard.jsx`

- **f-0007** · should · score 1 · confidence 0.90 · effort s · empty-states — Zero campaigns and missing data look identical
  activeCount 0 and a null summary both render "Active campaigns: 0" because of summary?.activeCount ?? 0. A new customer gets no explanation or way to start, and a broken response is reported as a real zero.
  Evidence: `target-app/src/screens/dashboard.jsx:42`, `.ponder/tmp/harness/render-observations.json#screen.dashboard.empty`, `.ponder/tmp/harness/render-observations.json#screen.dashboard.null-summary`
  Do: Render a first-campaign empty state with a create action when the count is 0, and treat a null summary as an error.

### Setup wizard shown again to a returning user `screen.dashboard.wizard.returning`
`target-app/src/screens/dashboard.jsx`

- **f-0015** · should · score 1 · confidence 0.95 · effort s · information-hierarchy — The wizard blocks the dashboard on every visit
  currentStep always starts at welcome and nothing consults saved state, so a second mount showed the wizard again. Returning users must click through a setup form to reach their overview.
  Evidence: `target-app/src/screens/dashboard.jsx:7`, `target-app/src/screens/dashboard.jsx:28`, `.ponder/tmp/harness/render-observations.json#screen.dashboard.remount`
  Do: Initialize the step from a server-side setup-complete flag.

### Setup wizard, welcome step `screen.dashboard.wizard.welcome`
`target-app/src/screens/dashboard.jsx`

- **f-0011** · should · score 1 · confidence 0.95 · effort s · copy-tone — Setup asks customers for an "Internal schema version"
  An implementation detail is shown to customers as a required-looking field, with no explanation. Nobody setting up a team checkup can know the answer, which makes them doubt they are in the right place.
  Evidence: `target-app/src/screens/dashboard.jsx:33`
  Do: Remove the field and set the schema version on the server.

- **f-0012** · should · score 1 · confidence 0.95 · effort s · accessibility — Wizard inputs are labelled only by placeholders
  Both inputs have zero associated labels and no aria-label, so screen readers have no reliable name and the hint vanishes on typing. They sit outside a form, so Enter does nothing.
  Evidence: `target-app/src/screens/dashboard.jsx:32-34`, `.ponder/tmp/harness/render-observations.json#screen.dashboard.wizard.welcome`
  Do: Wrap the step in a form and give each field a visible label.

- **f-0013** · could · score 2 · confidence 0.85 · effort s · affordance-clarity — Priority is free text with only three valid values
  The placeholder lists Low, Medium and High but accepts anything, and nothing validates it.
  Evidence: `target-app/src/screens/dashboard.jsx:32`
  Do: Use a select or radio group.

### Invitations for a user without permission `screen.invitations.denied`
`target-app/src/screens/invitations.jsx`

- **f-0043** · should · score 1 · confidence 0.60 · effort m · error-states — No permission state exists for participant data
  The component has no role input, and no role gate exists anywhere in the source. Anyone who can load the screen sees every name and magic link. Server checks are outside this workspace.
  Evidence: `target-app/src/screens/invitations.jsx:3`, `.ponder/tmp/harness/render-observations.json#screen.invitations.denied`, `.ponder/tmp/harness/render-observations.json#closure`
  Do: Gate this data by role on the server and add a denied state.

### Invitations with no participants `screen.invitations.empty`
`target-app/src/screens/invitations.jsx`

- **f-0040** · should · score 1 · confidence 0.95 · effort s · empty-states — No participants renders a table header and nothing else
  Zero participants produces a header row and no body. There is no explanation or invite action.
  Evidence: `target-app/src/screens/invitations.jsx:16-25`, `.ponder/tmp/harness/render-observations.json#screen.invitations.empty`
  Do: Add an empty state with an invite action.

### Unknown URL (no catch-all route) `screen.not-found`
`target-app/src/router.js`

- **f-0003** · should · score 1 · confidence 0.70 · effort s · error-states — Unknown URLs have no destination
  The route table has no catch-all, so a mistyped URL or a stale link has no designed screen. What the user actually sees depends on a router that is not in this workspace.
  Evidence: `target-app/src/router.js:1-8`, `.ponder/tmp/harness/render-observations.json#closure`
  Do: Add a path:"*" route with a not-found screen that links back to the dashboard.

### Results, at or above the promised threshold `screen.results`
`target-app/src/screens/results.jsx`

- **f-0073** · should · score 2 · confidence 0.75 · effort m · trust-boundaries — Score changes reveal individuals even above the threshold
  The page shows the respondent count and the average, and they update as people finish. If a team goes from 3 responses averaging 60 to 4 averaging 55, the fourth person scored exactly 40, and the invitations table says who just completed. Rounding to whole percents barely helps on a small team: at 4 people the result is still within about 3.5 points. So fixing the threshold to 3 does not by itself make the survey's promise true.
  Evidence: `target-app/src/screens/results.jsx:14-15`, `target-app/src/screens/invitations.jsx:20`, `target-app/src/screens/survey.jsx:9-11`, `.ponder/tmp/harness/pass2-observations.json#differencing`
  Do: Publish results as a snapshot when a campaign closes, or update only in batches, and hide per-person completion once the threshold is met. Done when no two views differ by exactly one respondent.

- **f-0027** · should · score 2 · confidence 0.70 · effort m · information-hierarchy — The results page gives a score with no meaning
  The page offers one percentage and a PDF link. There is no scale, dimension breakdown or suggested action, so leadership cannot tell whether 71% is good.
  Evidence: `target-app/src/screens/results.jsx:12-20`, `.ponder/tmp/harness/render-observations.json#screen.results`
  Do: In results.jsx, under the Overall Score line, add a per-dimension breakdown, a plain sentence interpreting the score, and a next action. Done when someone seeing 71% for the first time can say whether it is good and what to do next.
  _Revised: p2 edit recommendation_

- **f-0028** · should · score 2 · confidence 0.60 · effort s · consistency — The /results URL does not identify a campaign
  The route has no campaign id, so results cannot be linked or shared per campaign, and the same is true of /invitations. A customer with two campaigns has no URL for either.
  Evidence: `target-app/src/router.js:4-5`, `target-app/src/screens/results.jsx:3`
  Do: Use /campaigns/:id/results and /campaigns/:id/invitations.

### Results with aggregate withheld `screen.results.denied`
`target-app/src/screens/results.jsx`

- **f-0033** · should · score 1 · confidence 0.70 · effort s · error-states — Withheld results crash instead of explaining
  If the server correctly withholds the aggregate, the page crashes the same way. Fixing the threshold on the server alone would turn this bug into the main path.
  Evidence: `target-app/src/screens/results.jsx:15`, `.ponder/tmp/harness/render-observations.json#screen.results.denied`
  Do: Have the API return a below-threshold state and render it.

### Results with no respondents `screen.results.empty`
`target-app/src/screens/results.jsx`

- **f-0030** · should · score 1 · confidence 0.95 · effort s · copy-tone — The empty state advertises the broken threshold
  The copy says results unlock when one person completes a checkup, directly contradicting the survey. It also gives no progress or action.
  Evidence: `target-app/src/screens/results.jsx:7`, `.ponder/tmp/harness/render-observations.json#screen.results.empty`
  Do: Say "Results unlock once 3 people finish. 0 of 3 so far." and link to invitations.

### Results with completions but no aggregate `screen.results.error`
`target-app/src/screens/results.jsx`

- **f-0032** · should · score 1 · confidence 0.90 · effort s · error-states — Completions without an aggregate crash the page
  aggregate.overall is read with no guard, so a null aggregate blanks the page. An aggregate that is still computing would hit this.
  Evidence: `target-app/src/screens/results.jsx:15`, `.ponder/tmp/harness/render-observations.json#screen.results.error`
  Do: Render a pending state with retry when the aggregate is missing.

### Results with campaign not available yet `screen.results.loading`
`target-app/src/screens/results.jsx`

- **f-0031** · should · score 1 · confidence 0.85 · effort s · loading-states — Missing campaign data shows the no-responses message
  A missing campaign shares a branch with no completions, so a slow load, a failed load and a wrong id all claim nobody has responded yet.
  Evidence: `target-app/src/screens/results.jsx:4-10`, `.ponder/tmp/harness/render-observations.json#screen.results.loading`
  Do: Separate loading, not found and failed from the zero-responses state.

### Survey link already used or campaign closed `screen.survey.denied`
`target-app/src/screens/survey.jsx`

- **f-0023** · should · score 1 · confidence 0.60 · effort m · error-states — Used links and closed campaigns have no state
  Nothing in the component can represent an already-submitted link or a closed campaign, so it shows the same blank form. A second submission might overwrite or double-count, and that handling is outside this workspace.
  Evidence: `target-app/src/screens/survey.jsx:3-25`
  Do: Add explicit already-completed and campaign-closed screens, and reject repeats on the server.

### Survey with no questions `screen.survey.empty`
`target-app/src/screens/survey.jsx`

- **f-0020** · should · score 1 · confidence 0.90 · effort s · empty-states — A survey with no questions can still be submitted
  With no questions, the page shows the promise and an enabled Submit Checkup button, so a person can submit nothing and believe they have taken part.
  Evidence: `target-app/src/screens/survey.jsx:15-21`, `.ponder/tmp/harness/render-observations.json#screen.survey.empty`
  Do: Show "This checkup has no questions yet" and hide the submit button.

### Survey opened from a bad magic link `screen.survey.error`
`target-app/src/screens/survey.jsx`

- **f-0022** · should · score 1 · confidence 0.75 · effort m · error-states — A bad magic link renders a broken page with the privacy promise
  With no company and no questions, the page reads " Team Checkup" and "nobody at  sees what you answered", plus a working submit button. An expired or mistyped link has no designed response.
  Evidence: `target-app/src/screens/survey.jsx:7-11`, `.ponder/tmp/harness/render-observations.json#screen.survey.error`
  Do: Add an invalid-link screen that explains the cause and who to ask for a new link.

### Survey submit failed `screen.survey.submit-failed`
`target-app/src/screens/survey.jsx`

- **f-0025** · should · score 1 · confidence 0.90 · effort s · error-states — A failed submit shows nothing
  A rejected handler leaves the page unchanged, with no alert. The participant cannot tell whether their answers were recorded.
  Evidence: `target-app/src/screens/survey.jsx:14`, `.ponder/tmp/harness/render-observations.json#screen.survey.submit-failed`
  Do: Show an inline retry message in a role="alert" region and keep the answers.

### Survey submit in flight `screen.survey.submit-pending`
`target-app/src/screens/survey.jsx`

- **f-0024** · should · score 1 · confidence 0.90 · effort s · loading-states — Double submit sends the checkup twice
  The button stays enabled during submission and shows nothing. Two submit events called the handler twice. Duplicate responses would skew a small team's combined reading.
  Evidence: `target-app/src/screens/survey.jsx:14`, `target-app/src/screens/survey.jsx:21`, `.ponder/tmp/harness/render-observations.json#screen.survey.submit-pending`
  Do: Disable the button while pending and show progress. Make the server idempotent per hash.

### Navigation between screens `shell.navigation`
`target-app/src/router.js`

- **f-0079** · should · score 1 · confidence 0.80 · effort l · copy-tone — Through-line
  This product's problem is not that it's unfinished. It's that it says things that aren't true. The survey says nobody sees your answers, and the admin table shows them by name. The Pro button asks for Business. Next implies another step, then throws away what you typed. The spinner implies progress after the request has failed. Results call one person's score a combined reading. The webhook answers a purchase it never applied with 200. Attach returns ok for people it skipped. Nearly every serious finding is a label, sentence or status code that is false, and most of the rest are silence: blank pages and unlogged failures, which is why nothing corrects the false claims. More screens would not fix this.
  Evidence: `target-app/src/screens/survey.jsx:8-12`, `target-app/src/screens/invitations.jsx:21`, `target-app/src/screens/billing.jsx:4-6`, `target-app/src/screens/dashboard.jsx:28-37`, `target-app/src/screens/dashboard.jsx:15-22`, `target-app/src/screens/results.jsx:4`, `webhook-billing-slice/src/routes/stripe-webhook.js:17-19`, `target-app/src/actions/team-actions.js:19`, `.ponder/tmp/harness/backend-observations.json#webhook.transientFailureThenRetry`
  Do: Tie every claim to one server-side fact: an anonymity rule, a plan catalog, a setup-complete flag, and an event-applied state. Review each label, sentence and status code against those facts, and log any path that fails silently.

- **f-0005** · should · score 1 · confidence 0.70 · effort m · affordance-clarity — No navigation connects the screens
  Sweep 4 over all source files found one link: the PDF export. Nothing links to /results, /invitations or /billing, and the dashboard overview has no links or buttons at all. The only screen reachable by design is the survey, through its magic link. A shell could exist outside this workspace, but router.js has no layout entry to suggest one.
  Evidence: `.ponder/tmp/harness/render-observations.json#closure`, `target-app/src/screens/dashboard.jsx:39-44`
  Do: Add an app shell with links to all routes, plus next-step links from the dashboard to results and invitations.

- **f-0075** · could · score 2 · confidence 0.85 · effort s · consistency — One product uses several names for the same things
  The survey and wizard say "checkup", the dashboard says "campaigns" and "workspace", and results say "Combined Reading" and "Overall Score". Copy calls people "teammates" and "person", and the code calls them "participants" and "members". Capitalization drifts too: "Set up your checkup" against "Submit Checkup" and "Download Executive PDF".
  Evidence: `target-app/src/screens/survey.jsx:7`, `target-app/src/screens/survey.jsx:21`, `target-app/src/screens/dashboard.jsx:31`, `target-app/src/screens/dashboard.jsx:41-42`, `target-app/src/screens/results.jsx:14-17`, `target-app/src/screens/invitations.jsx:6`
  Do: Pick one customer-facing word each for the survey, the batch and the person, then apply them with sentence case.
  _Revised: p3 edit detail_

### Executive PDF export link `surface.results.pdf-export`
`target-app/src/screens/results.jsx`

- **f-0034** · should · score 2 · confidence 0.45 · effort m · error-states — PDF export has no failure handling, and its threshold is unverified
  The export is a plain link with no download attribute, progress or error handling, so a failure lands the user on a raw API response. It is live at one respondent in the UI. The endpoint is not in this workspace, so whether it enforces a threshold is unknown.
  Evidence: `target-app/src/screens/results.jsx:16-18`, `.ponder/tmp/harness/render-observations.json#screen.results`
  Do: Hide the link below the threshold, enforce it on the endpoint, and handle failure in place.

### Webhook event dispatch `webhook.stripe.dispatch`
`webhook-billing-slice/src/routes/stripe-webhook.js`

- **f-0074** · should · score 1 · confidence 0.85 · effort l · correctness — Nothing defines what a purchase entitles
  The UI hardcodes plan names and prices, and the plan it sends is wrong (f-0044). The worker takes the tier from metadata with a default and the seats from metadata with a default (f-0064), and picks the org by email (f-0065). Any failure is then lost on retry (f-0060), and the screen shows no result (f-0051). No code connects a Stripe price to what it grants, so each of these can disagree with what the customer paid for.
  Evidence: `target-app/src/screens/billing.jsx:4-6`, `target-app/src/screens/billing.jsx:12-19`, `webhook-billing-slice/src/workers/billing-worker.js:3-4`, `webhook-billing-slice/src/workers/billing-worker.js:6-9`, `webhook-billing-slice/src/routes/stripe-webhook.js:12-25`
  Do: Create one server-side plan catalog that maps Stripe price ids to tier and seats. Use it for the pricing cards, the checkout call and the worker. Done when the worker reads no tier or seat value from metadata.

- **f-0061** · should · score 2 · confidence 0.80 · effort s · correctness — Upgrades are applied without checking payment status
  checkout.session.completed also fires for delayed payment methods before funds settle. A session with payment_status "unpaid" was upgraded in the probe.
  Evidence: `webhook-billing-slice/src/routes/stripe-webhook.js:22-24`, `.ponder/tmp/harness/backend-observations.json#webhook.unpaidAsyncCheckout`
  Do: Grant on paid or no_payment_required, and handle the async_payment events.

- **f-0062** · should · score 2 · confidence 0.80 · effort m · correctness — Entitlements only ever grow
  customer.subscription.deleted and invoice.payment_failed returned 200 and changed nothing, so cancelled customers keep their paid plan and seats, as far as this slice shows. The worker also writes only plan_tier and seat_limit, not the Stripe customer or subscription id, so a lifecycle handler added later would have only an email to find the org with.
  Evidence: `webhook-billing-slice/src/routes/stripe-webhook.js:22-24`, `.ponder/tmp/harness/backend-observations.json#webhook.subscriptionDeleted`, `.ponder/tmp/harness/backend-observations.json#webhook.invoicePaymentFailed`
  Do: Store stripe_customer_id and subscription id on the org when checkout completes, then handle the subscription lifecycle events. Done when a cancellation returns the org to its base plan.
  _Revised: p2 edit detail, p2 edit recommendation_

### Webhook failure response and logging `webhook.stripe.error-response`
`webhook-billing-slice/src/routes/stripe-webhook.js`

- **f-0063** · should · score 2 · confidence 0.85 · effort s · error-handling — Billing failures are never logged
  The catch logs nothing, and JSON.parse and the dedupe insert sit outside the try, so they escape as thrown errors. Because the retry then returns 200, the failure also clears from Stripe's view, and nobody is told a paying customer went unserved. The handler also returns err.message, but only a request with a valid signature reaches it, so that is minor exposure, limited to people with access to the Stripe dashboard.
  Evidence: `webhook-billing-slice/src/routes/stripe-webhook.js:11-15`, `webhook-billing-slice/src/routes/stripe-webhook.js:26-28`, `.ponder/tmp/harness/backend-observations.json#webhook.errorBodyExposes`, `.ponder/tmp/harness/backend-observations.json#webhook.dedupeInsertFails`, `.ponder/tmp/harness/backend-observations.json#webhook.signedButInvalidJson`
  Do: Log failures with the event id and alert on them, return a generic body, and bring the parse and insert under the same guard. Done when a forced failure produces a log line with the event id.
  _Revised: p2 edit title, p2 edit detail, p2 edit recommendation_

### Billing worker tier and seat inputs `worker.billing.entitlement-inputs`
`webhook-billing-slice/src/workers/billing-worker.js`

- **f-0064** · should · score 2 · confidence 0.90 · effort s · input-validation — Tier and seats are trusted, with paid-looking defaults
  Missing metadata grants Pro plus 5 seats. Probes also wrote an unknown tier verbatim, took seat_limit to -45 from seats="-50", and produced NaN from seats="abc". A Business buyer with missing metadata would receive Pro.
  Evidence: `webhook-billing-slice/src/workers/billing-worker.js:3-4`, `webhook-billing-slice/src/workers/billing-worker.js:15`, `.ponder/tmp/harness/backend-observations.json#worker.noMetadata`, `.ponder/tmp/harness/backend-observations.json#worker.seatsNegative`, `.ponder/tmp/harness/backend-observations.json#worker.unknownTierWritten`
  Do: Derive tier and seats from the Stripe price or line items with an allowlist, and fail loudly otherwise.

### Billing worker organization lookup `worker.billing.org-resolution`
`webhook-billing-slice/src/workers/billing-worker.js`

- **f-0065** · should · score 1 · confidence 0.65 · effort m · correctness — The organization is found by matching a checkout email field
  The worker reads customer_email and matches it exactly against billing_email. That field holds only what the server passed when creating the session, while an address typed by the buyer appears in customer_details, which the worker ignores. In the probe, a null customer_email threw Organization not found, and that 500 hits the retry bug in f-0060, so the purchase is lost for good. When two orgs shared an email, rows[0] won arbitrarily. A case difference or a changed billing email also misses. The session-creation code is outside this workspace, so how often customer_email is absent is unknown.
  Evidence: `webhook-billing-slice/src/workers/billing-worker.js:2`, `webhook-billing-slice/src/workers/billing-worker.js:6-14`, `.ponder/tmp/harness/backend-observations.json#worker.emailOnlyInCustomerDetails`, `.ponder/tmp/harness/backend-observations.json#worker.twoOrgsSameEmail`
  Do: Resolve by client_reference_id, metadata.org_id or the stored Stripe customer id.
  _Revised: p2 edit detail, p2 change severity, p2 change score, p3 edit title, p3 edit detail, p3 change severity, p3 change confidence_

### Billing worker seat write `worker.billing.seat-update`
`webhook-billing-slice/src/workers/billing-worker.js`

- **f-0066** · should · score 2 · confidence 0.80 · effort s · state-and-concurrency — Seat updates lose writes under concurrency
  seat_limit is read, added to in JavaScript and written back. Two interleaved purchases gave 10 seats rather than 15. If the driver returns the column as a string, the result is "105" rather than 15; the column type is not visible here.
  Evidence: `webhook-billing-slice/src/workers/billing-worker.js:15`, `webhook-billing-slice/src/workers/billing-worker.js:17-20`, `.ponder/tmp/harness/backend-observations.json#worker.interleavedPurchases`, `.ponder/tmp/harness/backend-observations.json#worker.seatLimitNumericStringFromDriver`
  Do: Use SET seat_limit = seat_limit + $1 in one statement.

### Legacy V1 settings modal, open `modal.legacy-v1`
`target-app/src/screens/legacy-v1-modal.jsx`

- **f-0052** · could · score 1 · confidence 0.90 · effort s · accessibility — The modal fails contrast and has no dialog behaviour
  #ccc on #fff measures 1.61:1 against the 4.5:1 AA requirement. There is no role, aria-modal or focus handling, and Escape did not close it. Nothing mounts it today, which is why this ranks low.
  Evidence: `target-app/src/screens/legacy-v1-modal.jsx:6`, `.ponder/tmp/harness/render-observations.json#modal.legacy-v1`
  Do: Delete it if unused. Otherwise use a shared dialog with accessible colours.

- **f-0053** · could · score 2 · confidence 0.85 · effort s · consistency — The modal is an orphan with no content
  No file imports it, it holds only a heading and a Close button, and it is the only inline style in the app.
  Evidence: `target-app/src/screens/legacy-v1-modal.jsx:3-10`, `.ponder/tmp/harness/render-observations.json#closure`
  Do: Delete it, along with the dead legacy-export route.

### Billing for a user without billing permission `screen.billing.denied`
`target-app/src/screens/billing.jsx`

- **f-0050** · could · score 2 · confidence 0.55 · effort m · error-states — No billing permission state exists
  The component has no role input, so any member sees active upgrade buttons and the invoice list. The server might refuse checkout, but that is not in this workspace.
  Evidence: `target-app/src/screens/billing.jsx:3`, `.ponder/tmp/harness/render-observations.json#screen.billing.denied`, `.ponder/tmp/harness/render-observations.json#closure`
  Do: Gate billing to owners and show who to contact.
  _Revised: p2 change severity_

### Billing with no invoices `screen.billing.empty`
`target-app/src/screens/billing.jsx`

- **f-0047** · could · score 1 · confidence 0.95 · effort s · empty-states — "No invoices" explains nothing
  The empty state is two words with no cause or expectation. Plans remain visible, so the page is still usable.
  Evidence: `target-app/src/screens/billing.jsx:25-26`, `.ponder/tmp/harness/render-observations.json#screen.billing.empty`
  Do: Say when the first invoice will appear.

### Billing with invoices not ready `screen.billing.loading`
`target-app/src/screens/billing.jsx`

- **f-0048** · could · score 1 · confidence 0.60 · effort s · loading-states — Undefined invoices blank the whole billing page
  invoices.length throws, taking the plan cards down too, although they do not depend on the data.
  Evidence: `target-app/src/screens/billing.jsx:25`, `.ponder/tmp/harness/render-observations.json#screen.billing.loading`
  Do: Give invoices its own loading state and keep the plans rendered.
  _Revised: p2 change severity_

### Dashboard fetch returns 403 `screen.dashboard.denied`
`target-app/src/screens/dashboard.jsx`

- **f-0010** · could · score 1 · confidence 0.85 · effort m · error-states — A 403 is indistinguishable from slow loading
  A permission failure takes the same catch path, so it also spins forever. With the spinner bug fixed, the banner would show the raw message "Request failed with status code 403".
  Evidence: `target-app/src/screens/dashboard.jsx:15-17`, `.ponder/tmp/harness/render-observations.json#screen.dashboard.denied`
  Do: Branch on status and name the missing permission and who can grant it.
  _Revised: p2 change severity_

### Dashboard loading `screen.dashboard.loading`
`target-app/src/screens/dashboard.jsx`

- **f-0008** · could · score 2 · confidence 0.70 · effort s · loading-states — Loading has no escalation
  The skeleton is one line of text with aria-busy, and it never changes however long the request takes. There is no timeout or slow-state message.
  Evidence: `target-app/src/screens/dashboard.jsx:20-22`, `.ponder/tmp/harness/render-observations.json#screen.dashboard.loading`
  Do: Add a timeout that moves to the error state, and a skeleton shaped like the overview.

### Invitations after a failed fetch `screen.invitations.error`
`target-app/src/screens/invitations.jsx`

- **f-0042** · could · score 1 · confidence 0.60 · effort s · error-states — A failed fetch has no state and crashes on null
  The component has no error prop, and a null list blanks the page.
  Evidence: `target-app/src/screens/invitations.jsx:3`, `target-app/src/screens/invitations.jsx:17`, `.ponder/tmp/harness/render-observations.json#screen.invitations.error`
  Do: Add an error state with retry at the route level.
  _Revised: p2 change severity_

### Invitations with participants not ready `screen.invitations.loading`
`target-app/src/screens/invitations.jsx`

- **f-0041** · could · score 1 · confidence 0.60 · effort s · loading-states — Undefined participants crash the page
  participants.map throws, blanking the screen. No loading state exists here. A parent could prevent this, but none is in scope.
  Evidence: `target-app/src/screens/invitations.jsx:17`, `.ponder/tmp/harness/render-observations.json#screen.invitations.loading`
  Do: Add a loading state and default to an empty list only after data has loaded.
  _Revised: p2 change severity_

### Site root (no / route) `screen.root`
`target-app/src/router.js`

- **f-0004** · could · score 1 · confidence 0.60 · effort s · information-hierarchy — The site root has no route
  There is no / route and no redirect, so anyone entering at the bare domain falls through to the missing not-found state.
  Evidence: `target-app/src/router.js:1-8`, `.ponder/tmp/harness/render-observations.json#closure`
  Do: Route / to /dashboard, or to sign-in for signed-out users.
  _Revised: p2 change severity_

### Legacy export route, whose component file is absent `screen.settings.legacy-export`
`target-app/src/router.js`

- **f-0002** · could · score 1 · confidence 0.95 · effort s · error-states — Route points at a component file that does not exist
  /settings/legacy-export resolves to src/screens/legacy-export.jsx, which is not on disk. A person who has this URL gets whatever the failed resolve produces, and there is no error boundary or 404 route in scope to catch it.
  Evidence: `target-app/src/router.js:7`, `.ponder/tmp/harness/render-observations.json#closure`
  Do: Delete the route row, or add the screen. Done when every component path in router.js exists on disk.
  _Revised: p2 change severity_

### Survey data not ready `screen.survey.loading`
`target-app/src/screens/survey.jsx`

- **f-0021** · could · score 1 · confidence 0.60 · effort s · loading-states — The survey has no loading state and crashes without data
  Undefined questions throws on map and leaves a blank page. This is the first screen a participant sees from their email. A parent might hold rendering until data arrives, but none is in scope.
  Evidence: `target-app/src/screens/survey.jsx:15`, `.ponder/tmp/harness/render-observations.json#screen.survey.loading`
  Do: Add a loading state in the survey route, and accept questions=[] by default.
  _Revised: p2 change severity_

### Survey submitted `screen.survey.submit-success`
`target-app/src/screens/survey.jsx`

- **f-0026** · could · score 2 · confidence 0.55 · effort s · information-hierarchy — No confirmation exists in this component
  After a successful submit, the same form stays on screen with its values. The parent might navigate away, but no thank-you state exists in this workspace.
  Evidence: `target-app/src/screens/survey.jsx:3-25`, `.ponder/tmp/harness/render-observations.json#screen.survey`
  Do: Add a confirmation that restates the privacy promise and says when results will be shared.
  _Revised: p2 change severity_

### Webhook signature gate `webhook.stripe.signature-gate`
`webhook-billing-slice/src/routes/stripe-webhook.js`

- **f-0059** · could · score 3 · confidence 0.85 · effort s · fail-closed-defaults — A missing secret looks the same as an attack
  An unset STRIPE_WEBHOOK_SECRET correctly fails closed, but returns the same 401 with no log, so a deployment mistake silently blocks all billing events.
  Evidence: `webhook-billing-slice/src/routes/stripe-webhook.js:7-9`, `.ponder/tmp/harness/backend-observations.json#webhook.secretEnvMissing`
  Do: Fail at startup when the secret is unset, and log verification failures.

- **f-0058** · note · score 4 · confidence 0.95 · effort s · trust-boundaries — The signature gate is ordered correctly
  The handler reads the raw body, verifies before parsing, and writes nothing on failure. Bad and absent signatures returned 401 with no dedupe row.
  Evidence: `webhook-billing-slice/src/routes/stripe-webhook.js:5-11`, `.ponder/tmp/harness/backend-observations.json#webhook.badSignature`, `.ponder/tmp/harness/backend-observations.json#webhook.noRowWrittenOnBadSignature`
  Do: Keep this ordering.

### sql tagged-template parameter binding `lib.safe-query.sql`
`target-app/src/lib/safe-query.js`

- **f-0057** · note · score 4 · confidence 0.95 · effort s · input-validation — Parameter binding is correct
  Probes confirmed that values never reach the query text. An injection payload stayed in values, a value resembling a placeholder stayed literal, and a nested fragment was bound as a value rather than spliced in, which fails closed.
  Evidence: `target-app/src/lib/safe-query.js:1-10`, `.ponder/tmp/harness/backend-observations.json#safeQuery`
  Do: Keep it. No SQL injection finding applies to this helper or its callers.

### Signature HMAC and comparison `lib.webhook-crypto.compare`
`webhook-billing-slice/src/lib/webhook-crypto.js`

- **f-0067** · note · score 4 · confidence 0.95 · effort s · secret-hygiene — HMAC computation and comparison are correct
  It uses HMAC-SHA256 over t.payload, a length check, then timingSafeEqual. Tampered bodies, wrong secrets, swapped timestamps, truncated and non-hex signatures, and null inputs were all rejected.
  Evidence: `webhook-billing-slice/src/lib/webhook-crypto.js:7-14`, `.ponder/tmp/harness/backend-observations.json#crypto`
  Do: Keep it.

## Retracted

Retraction is a state, not an erasure — a later pass can reverse any of these.

- `f-0039` (screen.invitations) — Completed participants with no score render "null%" · retracted in pass 1 by the skeptic: invitations.jsx:21 null% only exists in the score column f-0037 removes -> echo -> absorbed by f-0037
- `f-0036` (screen.invitations) — A four-column table may overflow on phones · retracted in pass 1 by the skeptic: closure.stylesheets=0, never rendered visually -> harm theoretical, no measurement -> replaced by the limit note added this pass

## Deliberation

### Pass 1

- **skeptic** — Walked all 68 against rendered output and backend probes. f-0039 'null%' dies with the score column in f-0037, so it is an echo. f-0036 phone overflow has no stylesheet and no render behind it (closure.stylesheets=0), so the harm is theoretical; replace it with one honest limit note. Crash findings f-0021, f-0041, f-0042, f-0048 share a mechanism but each sits alone on its unit, so deleting them would empty a variant unit; hold them for a system finding and a re-rank next pass. Three note grades are 4s, each backed by probe output, and none claims 5. Next pass must attack f-0068 and f-0063: dedupe may blunt replay, and err.message only reaches Stripe past the signature.
- **builder** — Every must names file, line and a done test. f-0038 mixes exposed tokens with missing controls, two fixes with different owners and different stakes; split it so each stays actionable. Backend recommendations already name exact SQL shape. Effort is not uniformly m, so estimates look considered. Remaining vagueness is in f-0027 and f-0045, which name concepts rather than components; sharpen on pass 2.
- **dreamer** — Reading variants as columns: loading column is 1 crash per props screen, error column is crash or silence, denied column has no role concept anywhere (roleGateHits=0). That is a missing system rather than 15 screen bugs, and it needs a system finding on pass 2. Biggest cross-file chain not yet written: the survey promise is broken by three separate paths, and billing bugs chain across UI and webhook. Also missing: nothing says visual dimensions went ungraded, so add that limit now so coverage 1.00 is not read as visual review.
- **empath** — Rank by reach x stakes x recoverability. A participant who trusted the promise and was individually exposed is unrecoverable, so the exposed magic link in f-0038 belongs with the privacy musts: high stakes, cannot be undone once someone answers as them. Missing invite controls are high reach but recoverable, so they stay should. The orphan modal stays could despite 1.61:1 because reach is zero today.

Resolution: 2 add, 1 edit, 1 change, 2 delete (plus 68 findings seeded by `ponder grade` before the argument).

### Pass 2

- **skeptic** — Reopened every must and ran new probes. All 9 musts survive contact: each reproduced in execution or render. Two claims were overstated. f-0068 replay: dedupe returned duplicate for a seen event, so old signatures only re-apply after the row is pruned (yearOldReplayAfterDedupePruned grew seats 15->25), so the boundary mostly holds. f-0063 leak: err.message sits after the signature gate so only Stripe sees it; the logging half is the real defect. f-0054 claimed visibility in tenant A's invitations, but the participant query is out of scope, so that is inference. Tried to kill XSS: 0 img elements across invitations, survey and results, so no XSS finding is warranted and none is made. Stale fetch looked theoretical, but the probe shows the older response wins (99 over 2); mechanism is real, trigger unknown, so it enters as could. Crash findings keep their units but lose rank to one system finding.
- **builder** — Made the overstated findings true rather than deleting them, and tightened f-0027 and f-0045 into named components. Added the missing mechanism to f-0062: the worker stores no Stripe customer or subscription id, so a lifecycle handler added later would have nothing but email to resolve an org with. f-0065 now states the chain into f-0060. Moved f-0029 and f-0037 off error-states, because they are trust failures rather than error handling.
- **dreamer** — Read columns across variants. Loading and error: 5 of 5 data screens crash or stay silent, one missing boundary. Denied: roleGateHits=0 and planGateHits=0 over all source, so permission is absent as a concept. Billing is a chain with no catalog: UI hardcodes plan and prices, metadata supplies tier with a default, seats default to 5, the email picks the org, and any miss is lost on retry. Anonymity has a flaw a threshold cannot fix: n=3 avg 60 then n=4 avg 55 gives the new person's score of exactly 40, and invitations says who just completed. Vocabulary drifts across checkup, campaign, workspace, reading, score.
- **empath** — Rank by reach x stakes x recoverability; 48 shoulds was not a ranking. f-0065 rises to must: reach is any buyer whose Checkout email differs or is absent, stakes are paid and unserved or another org upgraded, recoverability is none once f-0060 swallows the retry. f-0004, f-0002 drop: nothing links to them, reach near zero. Crash echoes f-0021, f-0041, f-0042, f-0048 drop to could because one boundary fixes them and a parent may guard them. f-0010, f-0050 drop: same reasoning under the role finding. f-0018 drops because the f-0017 fix resolves it. f-0026 drops: a parent likely navigates, low stakes. f-0068 moves to score 3: boundary holds through dedupe. f-0015 stays should despite daily reach, since one click recovers.

Resolution: 6 add, 9 edit, 12 change.

### Pass 3

- **skeptic** — Audited the ledger: 200 of 200 evidence references resolve, 12 of 12 source files have units, sweep zeros explained (no middleware, html or stories in this stack). f-0065 fails re-reading: worker reads customer_email (billing-worker.js:2), a field set at session creation, while buyer-typed addresses arrive in customer_details, so 'email the buyer controls' is backwards and the takeover scenario does not follow from this code. Pass 2's must was built on that premise, and session-creation code is out of scope, so reach is unproven; severity returns to should. f-0056 'three ids, six round trips' came from a probe with one unknown id; f-0075 listed code-only words as copy; f-0038 'working path' claims more than a render shows. No delete is warranted: each remaining overlap is the sole finding on its unit or names a different fix, and deleting would be manufacturing motion.
- **builder** — Corrected text rather than leaving overstated claims: f-0065 retitled with the real mechanism, f-0056 per-member cost, f-0075 copy versus code vocabulary, f-0038 wording. f-0016 now names every fix its truth depends on (f-0037, f-0029, f-0038, f-0073) so nobody closes it with a copy edit. f-0070 now also states what was out of reach: invitation emails and Stripe-hosted pages.
- **dreamer** — Screens that do not exist: action takes currentUser, yet no route or component handles signed out or expired session, and rg finds no login, signin or auth anywhere, so that unit was missing from my inventory. Empty column read: 5 of 5 empties have no action, since no create or invite control exists to link to. Through-line: this product says things that are not true, in labels, copy and status codes, and its failures are silent, so nothing corrects them. Rewritten from scratch this pass, first time written.
- **empath** — Reversing my own pass 2 raise on f-0065 is the honest move: reach depended on the buyer-typed premise; stakes remain high, but with session creation unseen it is confirmed only for absent emails and shared billing addresses, so should at 0.65. Rechecked the remaining 9 musts by reach x stakes x recoverability: privacy cluster (f-0016, f-0029, f-0037, f-0038) hits every participant and cannot be undone; billing (f-0044, f-0060) touches money directly; f-0054 crosses tenants; f-0009 and f-0014 block first use. All stand, all at confidence 0.9 or above.

Resolution: 3 add, 6 edit, 1 change, 1 unit-add.

### Pass 4

- **skeptic** — Re-ran all three harnesses from scratch: render, backend and pass2 observation files are byte-identical, so no cited result was a one-off. Tried new kills and new attacks. tenantId undefined -> Campaign not found, null user -> TypeError, empty-string secret -> false: all fail closed, no finding. rg: dangerouslySetInnerHTML and eval 0 hits; 6 of 6 db calls use bound parameters; only 2 catch blocks exist and both are already graded (f-0009, f-0063). A signed event missing data.object goes to catch and 500, which is already f-0060's path. 216 evidence refs still resolve. Nothing to retract and nothing new; held.
- **builder** — Re-read every open must and system finding for where, what and a done check. f-0009, f-0014, f-0016, f-0029, f-0037, f-0038, f-0044, f-0054 and f-0060 each name a file and a test a reviewer could run. f-0071, f-0072, f-0074 and f-0079 name a single mechanism. Pass 3's corrections to f-0056, f-0065 and f-0075 read true against source lines. Effort is spread across s, m and l. No edit would change what someone does.
- **dreamer** — Walked seven journeys against the ledger as a different cut from units: first-time admin, participant, results reader, buyer, cancelling customer, member with no rights, attacker with a member id. Every step already maps to an open finding, and no step exposed an unlisted state. Re-examined the through-line clause by clause against harness output: survey promise vs Dana 34%, Pro sends plan business, Next drops values, spinner after rejection, Combined Reading at n=1, 200 duplicate after a 500, ok for a skipped id. All seven hold, and it still accounts for the new findings, so it is right rather than unexamined and needs no rewrite. No new ground.
- **empath** — Re-ranked by journey instead of by unit: 9 musts are the steps where someone is exposed, overcharged, lost or stopped, and each has confidence 0.9 or above. f-0065's return to should held when re-read: confirmed mechanism, unproven reach. Nothing in the could tier blocks a journey. f-0015 stays should: daily reach, one click to recover. Moving anything now would be taste, not evidence.

Resolution: no deltas.

### Pass 5

- **skeptic** — Used a cut pass 4 did not: rg of every if, ternary, catch, fallback and map across 12 files gives 28 branch sites, and each lands on a graded unit. The err.message fallback at dashboard.jsx:16 is unreachable until f-0009 is fixed, which f-0009 already says. Source untouched: 0 files modified since setup. Baseline recall: all 20 single-shot findings have open counterparts. One sub-claim was dropped on purpose: ss-20's missing Content-Type, since Stripe ignores response type and no person is affected. No retraction and no new claim survives this check.
- **builder** — Compared baseline recommendations with ledger ones for the same defects; the ledger's are at least as concrete, and each must carries a done check the baseline lacked. ss-11's fix and f-0002 agree, ranked lower because nothing links to the route. No baseline recommendation is better than its ledger counterpart, so no edit is warranted.
- **dreamer** — The 32 findings with no baseline counterpart are what the passes earned: variant states, permissions, differencing, a plan catalog, auth. Re-read those for anything implying yet another unlisted state, and found none beyond what is already enumerated or stated as out of workspace in f-0070. Through-line re-read against the branch map: false claims at the labelled branches and silence at the unhandled ones; it still explains the set and is right as written, unchanged because it was re-checked and held. No new ground.
- **empath** — Compared severities with the baseline to look for drift I could not defend. Rises: f-0038 to must (unrecoverable impersonation) and f-0014 to must (silent data loss on first use). Drop: f-0002 to could (zero reach). Each has reach, stakes and recoverability written in its why. 9 musts, all confidence 0.9 or above. No re-rank is justified by new evidence, so ranking holds.

Resolution: no deltas.

## Ledger

112 deltas across 5 passes: 79 add, 16 edit, 14 change, 2 delete, 1 unit-add.

| Pass | Deltas | Perspectives |
|---:|---|---|
| 1 | 70 add, 1 edit, 1 change, 2 delete | builder, dreamer, empath, skeptic |
| 2 | 6 add, 9 edit, 12 change | builder, dreamer, empath |
| 3 | 3 add, 6 edit, 1 change, 1 unit-add | builder, dreamer, empath |
| 4 | no deltas | — |
| 5 | no deltas | — |

The full append-only record is `ledger.jsonl`.

---

*Generated by [Ponder](https://github.com/Quinnod345/ponder) — AI that knows when to speak, and when to shut up.*
