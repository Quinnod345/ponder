# Ponder — the mail client's screens

`mail-ui` · lens **ui** · status **converged** · 4 passes of a 6-pass budget · generated 2026-08-25T01:54:20.561Z

| | |
|---|---|
| Subject | the mail client's screens |
| Lens | ui — unit = screen, 12 dimensions |
| Project | `/Users/quinnodonnell/code/ponder/docs/example-session` |
| Passes | 4 run · min 3 · max 6 |
| Coverage | 1.00 — 6 of 6 screens graded |
| Findings | 15 total · 15 open · 0 resolved · 0 deferred · 0 retracted |
| Final verdict | stop (converged) → decided **stop** |
| OCA | off |

## Convergence

| Pass | Coverage | Novelty | Churn | Thrash | Surprise | Stall | Conf-floor | Voices | Advice | Decision |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|---|
| 1 | 0.67 | — | — | — | — | 0 | 0.00 | 4 | blocked (coverage) | continue |
| 2 | 1.00 | 0.00 | 0.27 | 0.00 | 0.03 | 0 | 0.00 | 4 | continue (min-passes) | continue |
| 3 | 1.00 | 0.00 | 0.07 | 0.00 | 0.01 | 0 | 0.00 | 4 | continue (default) | continue |
| 4 | 1.00 | 0.00 | 0.07 | 0.00 | 0.00 | 0 | 0.00 | 4 | stop (converged) | stop |

`—` on pass 1 is not a zero. Novelty, churn, thrash and surprise measure change against a previous pass, and pass 1 has none.

## Overrides

None. Every decision followed the engine's advice.

## Prediction vs reality

| Pass | Predicted churn | Actual churn | Surprise | Claim |
|---:|---:|---:|---:|---|
| 1 | 0.90 | — | — | Pass 1 builds the set from nothing; the unhandled-absence pattern will dominate. |
| 2 | 0.30 | 0.27 | 0.03 | Pass 2 resolves the three unopened units; two should verify as missing on disk. |
| 3 | 0.08 | 0.07 | 0.01 | Pass 3 should sharpen at most one recommendation and find no new units. |
| 4 | 0.07 | 0.07 | 0.00 | Pass 4 should move at most one grade and confirm the set has settled. |

## Coverage

6 screens enumerated, 6 graded.

### Phantom units

3 screens were claimed not to exist in the software and dropped from the coverage denominator. 1 of them could not be checked: it had no path to check the claim against.

- `screen.drafts` — Drafts — unsent messages · pass 2 · verified-missing (`/Users/quinnodonnell/code/ponder/docs/example-session/src/screens/drafts.jsx` does not exist)
  > There is no drafts screen. Pass 1 enumerated it from a routing table that still lists routes the application stopped serving; src/screens/drafts.jsx does not exist and nothing imports it.
- `screen.labels` — Labels — managing labels · pass 2 · verified-missing (`/Users/quinnodonnell/code/ponder/docs/example-session/src/screens/labels.jsx` does not exist)
  > There is no labels screen either, and for the same reason: the same stale routing table. src/screens/labels.jsx does not exist and label management happens inline in the thread header instead.
- `screen.digest` — Daily digest — the email itself · pass 2 · **UNVERIFIED — this unit had no path, so the claim could not be checked**
  > The daily digest is an email template rendered server-side, not a screen in this application. It has no path in this repository for the engine to check, so this claim is recorded unverified on purpose.

## Findings

### Compose — writing a message `screen.compose`
`src/screens/compose.jsx`

- **f-0006** · must · score 2 · confidence 0.85 · effort s · affordance-clarity — Nothing signals that a draft was saved
  Compose autosaves, but the interface never says so, and there is no drafts screen to go and look — that route was enumerated in pass 1 and turned out not to exist. So the reader has no way to distinguish work that is safe from work that is about to be lost, and no second place to check. That is the single highest-stakes uncertainty on the screen.
  Evidence: `src/screens/compose.jsx:5`
  Do: Show a quiet, timestamped 'Saved' marker that updates on each autosave and turns into an explicit warning when a save fails.
  _Revised: p2 edit detail_

- **f-0007** · should · score 2 · confidence 0.75 · effort m · affordance-clarity — Send is irreversible the instant it is pressed
  There is no undo window. The most consequential and most frequently regretted action in the product commits immediately, and the only recovery is a second message apologising for the first.
  Evidence: `src/screens/compose.jsx:5`
  Do: Hold the send for a few seconds behind an 'Undo' snackbar, the way every mail client the reader already uses does.

### Inbox — the message list `screen.inbox`
`src/screens/inbox.jsx`

- **f-0001** · must · score 1 · confidence 0.90 · effort s · empty-states — The empty inbox is an empty rectangle
  `inbox.jsx` renders `<List items={data} />` whenever data resolves, including when it resolves to zero rows. A brand-new account therefore lands on a bordered rectangle with a header and nothing else — no explanation that the account is genuinely empty rather than broken, and no action.
  Evidence: `src/screens/inbox.jsx:5`
  Do: Branch on `data.length === 0` and render a state that says the inbox is empty, why that is expected on a new account, and the one action that changes it.

- **f-0014** · must · score 1 · confidence 0.85 · effort m · consistency — Absence is unhandled product-wide, not screen by screen
  Inbox, search, archive and drafts each render only their success case. There is no shared empty-state component and no convention for what absence looks like, so every screen invents its own or, more often, invents nothing. Fixing these one at a time will produce four different empty states.
  Evidence: `src/screens/inbox.jsx:5`, `src/screens/search.jsx:5`, `src/screens/archive.jsx:5`
  Do: Build one empty-state component that takes a headline, an explanation and a primary action, then adopt it everywhere absence is possible.

- **f-0002** · should · score 2 · confidence 0.85 · effort m · loading-states — Loading replaces the whole layout with a spinner
  `if (!data) return <Spinner />` throws away the chrome the reader was already looking at. The header, the toolbar and the list frame all vanish and then reappear, so every navigation costs a full-page flash even when the payload is small.
  Evidence: `src/screens/inbox.jsx:4`
  Do: Keep the frame mounted and render row skeletons inside it, so only the rows change and nothing the reader is looking at moves.

- **f-0003** · could · score 3 · confidence 0.60 · effort m · density — Row density is not tuned for the long case
  The list uses one spacing value for every row, which reads comfortably at twenty messages and becomes an enormous scroll at two thousand. There is no compact affordance and no grouping by date. Confidence stays at 0.6 across four passes because nobody has opened this screen against a genuinely large mailbox; the reasoning is sound but the evidence is a code read, not an observation.
  Evidence: `src/screens/inbox.jsx:5`
  Do: Add a compact row height and group rows under sticky date headers so the long case stays navigable.
  _Revised: p4 change detail_

### Search — results over messages `screen.search`
`src/screens/search.jsx`

- **f-0010** · must · score 1 · confidence 0.90 · effort s · empty-states — A search with no matches looks like a failure
  Zero results renders the same bare list frame as an error, so the reader cannot tell whether the query genuinely matched nothing or whether the search itself broke.
  Evidence: `src/screens/search.jsx:5`
  Do: Say that the query matched nothing, echo the query back, and offer the obvious relaxation — drop a filter, search all mail.

- **f-0011** · could · score 3 · confidence 0.60 · effort s · motion — Results arrive with no transition
  Each keystroke swaps the result list instantly, so the list flickers through intermediate states while the reader is still typing.
  Evidence: `src/screens/search.jsx:5`
  Do: Debounce the query and cross-fade the result set so the change reads as one settled update.

### Thread — one conversation `screen.thread`
`src/screens/thread.jsx`

- **f-0004** · must · score 1 · confidence 0.95 · effort s · error-states — Errors surface the raw HTTP status
  `return <div>{error.status}</div>` puts the literal number in front of the reader. A 403 on a shared thread and a 500 on a broken server are the same experience: a bare number, no explanation of whether the message is gone, private, or merely unavailable right now, and nothing to click.
  Evidence: `src/screens/thread.jsx:3`
  Do: Map the status to a sentence that says what happened, whether anything was lost, and the single action that resolves it — retry, request access, or go back to the inbox.

- **f-0015** · must · score 1 · confidence 0.90 · effort m · error-states — Error handling exists on exactly one screen
  Thread is the only screen that checks `error` at all, and it does so badly. The other five destructure `error` and never read it, so a failed request on any of them leaves the spinner up forever. The reader waits indefinitely for a request that has already failed.
  Evidence: `src/screens/inbox.jsx:2`, `src/screens/search.jsx:2`, `src/screens/settings.jsx:2`
  Do: Handle the error branch on every screen that fetches, and make an unresolved request time out into an error rather than an eternal spinner.

- **f-0005** · must · score 1 · confidence 0.80 · effort xs · accessibility — No visible focus ring on the reply affordance
  The reply control is styled from scratch and never restores an outline on `:focus-visible`, so a keyboard reader tabbing through a long thread loses their place entirely once they pass the message body.
  Evidence: `src/screens/thread.jsx:5`
  Do: Restore a `:focus-visible` outline with a 2px offset on every interactive element that overrides the default.

### Archive — everything filed away `screen.archive`
`src/screens/archive.jsx`

- **f-0012** · should · score 2 · confidence 0.80 · effort s · consistency — Archive is a second inbox with no way back
  The archive reuses the inbox list wholesale, including its row actions, but offers no un-archive affordance. Filing something away is therefore a one-way door reachable by a single click.
  Evidence: `src/screens/archive.jsx:5`
  Do: Give archived rows a restore action, and make the archive's header visually distinct from the inbox's so the two are never confused.

- **f-0013** · should · score 2 · confidence 0.70 · effort s · responsive-behaviour — The list does not reflow below 640px
  The row lays sender, subject, preview and timestamp on one line with fixed columns, so on a narrow viewport the subject truncates to a few characters while the timestamp keeps its full width.
  Evidence: `src/screens/archive.jsx:5`
  Do: Below 640px, put sender and timestamp on one row and give subject and preview the full width beneath them; keep the single-line layout at 640px and above.
  _Revised: p3 change recommendation, p3 change effort_

### Settings — account preferences `screen.settings`
`src/screens/settings.jsx`

- **f-0008** · should · score 2 · confidence 0.80 · effort s · affordance-clarity — Preference changes give no confirmation
  Toggles write on change and render nothing back. The reader flips a switch and is left to infer from the absence of an error that the preference stuck.
  Evidence: `src/screens/settings.jsx:5`
  Do: Reflect the saved state on the control itself and surface failures inline next to the toggle that failed.

- **f-0009** · should · score 2 · confidence 0.75 · effort m · information-hierarchy — Every section carries identical visual weight
  Account, notifications, appearance and the destructive account-deletion block are all rendered as the same flat list of rows, so the one irreversible action on the screen is as quiet as a theme preference.
  Evidence: `src/screens/settings.jsx:5`
  Do: Give the destructive block its own separated, differently-weighted treatment at the end of the page.

## Retracted

Nothing was retracted.

## Deliberation

### Pass 1

- **skeptic** (confidence 0.90) — Thirteen findings over six screens, and three of the nine units in the inventory have never been opened. Two of those three have paths that do not resolve to anything on disk and the third has no path at all, which means the enumeration itself is the least trustworthy artefact in this session. Nothing here should be called converged until that is settled one way or the other.
- **builder** (confidence 0.85) — The empty and error states are the same defect wearing three hats: every screen renders its success case and treats absence as if it cannot happen. That is one shared component and an afternoon, not four separate tickets, and saying so changes how the plan should be ordered.
- **dreamer** (confidence 0.80) — Read the six graded screens as three columns — empty, loading, error — and the shape of the product appears. Every screen has a success case, four have no empty state, and exactly one has any error handling at all. The holes are not scattered; the whole non-success half of this product was never designed.
- **empath** (confidence 0.85) — Ranking by reach times stakes times recoverability puts the thread error first — it is the screen a person reaches from a shared link, and a bare 403 tells them nothing about whether to ask for access or give up. The compose undo window is second: high stakes, and today entirely unrecoverable.

Resolution: 2 add, 1 change (plus 13 findings seeded by `ponder grade` before the argument).

### Pass 2

- **skeptic** (confidence 0.90) — I went and looked instead of arguing. `src/screens/drafts.jsx` and `src/screens/labels.jsx` do not exist — pass 1 read them off a routing table that still lists routes the app stopped serving. The daily digest is a real thing but it is an email template, not a screen this lens can grade, and it has no path for the engine to check. All three should leave the inventory as phantom claims, checked where they can be checked.
- **builder** (confidence 0.80) — Dropping three units is the one move in this system that can flatter the coverage number, so it should cost something. Two of these the engine can verify against disk; the digest it cannot, and that one should stay visibly marked as a claim nobody checked rather than quietly disappearing.
- **dreamer** (confidence 0.65) — A routing table that lists two screens nobody built is its own finding about this codebase, but it is a finding about the router, and the router is not a unit in this inventory. Naming it here and letting it go is the honest move.
- **empath** (confidence 0.80) — If drafts genuinely does not exist, then the compose autosave finding gets worse rather than better: the work is saved somewhere the reader has no screen to go and find. That is worth saying inside the compose finding itself.

Resolution: 1 edit, 3 unit-delete.

### Pass 3

- **skeptic** (confidence 0.85) — I tried to find a fourth phantom and could not: the remaining six units all resolve to files that exist and all six carry findings. The inventory is now what it claims to be. I have nothing to emit, which is a result rather than an absence of effort.
- **builder** (confidence 0.80) — The set has stopped moving on substance. The one thing still worth touching is the archive responsive finding, whose recommendation says 'stack them' without saying at what width or in what order — an engineer would have to redesign it themselves.
- **dreamer** (confidence 0.70) — Reading the six survivors as columns again, the picture is unchanged from pass 1 now that the phantom rows are gone — which is itself the useful signal. The holes were never in the units that did not exist.
- **empath** (confidence 0.80) — Re-ran the ranking with the phantoms gone and it did not move: thread error first, compose undo second, the systemic absence finding third because it is what makes the first two feel like a pattern rather than a bug.

Resolution: 1 change.

### Pass 4

- **skeptic** (confidence 0.85) — Second pass in a row where I have looked for something to overturn and found nothing. Every open must-finding names a file and a line, and every one of them is above 0.75 confidence. I have no objection left to make.
- **builder** (confidence 0.80) — Every recommendation now names the change concretely enough to start work from. The only remaining edit is the density finding, whose confidence has sat at 0.6 since pass 1 because nobody has looked at a real long inbox — worth saying so on the finding rather than leaving the number unexplained.
- **dreamer** (confidence 0.75) — I have tried two reframes this pass — reading the set by dimension rather than by screen, and reading it as a first-run journey — and both reproduce the same three priorities. When the reframes stop producing new orderings, the set has settled.
- **empath** (confidence 0.80) — Ranking is stable across three passes now. Nothing to add.

Resolution: 1 change.

## Ledger

22 deltas across 4 passes: 15 add, 1 edit, 3 change, 3 unit-delete.

| Pass | Deltas | Perspectives |
|---:|---|---|
| 1 | 15 add, 1 change | builder, dreamer, empath |
| 2 | 1 edit, 3 unit-delete | empath, skeptic |
| 3 | 1 change | builder |
| 4 | 1 change | builder |

The full append-only record is `ledger.jsonl`.
