# Example session — pondering a mail client's screens

A real, complete `ponder` run, kept so the loop can be read rather than described. Nothing
here was hand-written after the fact: every file under `.ponder/mail-ui/` was produced by the
engine. The subject is committed too — the six screens under `src/screens/` — and the four
passes' inputs are kept under `.ponder/tmp/`, so the whole session replays against the
current engine. That is how the numbers below stay honest when the engine's signals change.

**Subject:** the mail client's screens · **Lens:** `ui` · **Result:** converged after 4 of a
6-pass budget · **Coverage:** 6 of 6 screens graded, after three phantom units left the
inventory.

This session was chosen as the committed example because it exercises the part of ponder
that everything else exists to protect: **pass 1 is refused a stop.** Three of the nine
enumerated screens had never been opened, so the verdict is `blocked` and `decide stop` is
not available — not discouraged, unavailable. Watch how the session gets out of that, because
the only honest exits are the two the engine names.

## What to read, in this order

| File | Why |
|---|---|
| [`.ponder/mail-ui/report.md`](.ponder/mail-ui/report.md) | Start here. The whole pondering in one document: the convergence table, prediction vs reality, every finding grouped by screen, the **Phantom units** section, all four deliberations, and the full ledger. |
| [`.ponder/mail-ui/ledger.jsonl`](.ponder/mail-ui/ledger.jsonl) | Every delta ever applied, in order, each with the perspective that emitted it and a `why`. 23 lines: the `unit-seed` record that puts pass 1's nine-screen inventory on the record, 13 pass-1 finding seeds, then 9 deliberative revisions. |
| `.ponder/mail-ui/passes/NN/metrics.json` | The eight convergence signals per pass. Read `01` then `02` and watch the four relative signals go from `null` to real numbers. |
| `.ponder/mail-ui/passes/NN/deliberation.json` | What the four voices actually argued, pass by pass. |
| `.ponder/tmp/` | The inputs handed to the engine — the unit inventory, the pass-1 finding set, and each pass's deliberation and delta batch. |

## How the numbers moved

| Pass | Coverage | Novelty | Churn | Thrash | Surprise | Voices | Delta voices | Advice |
|---:|---:|---:|---:|---:|---:|---:|---:|---|
| 1 | 0.67 | — | — | — | — | 4/4 | 3/4 | **blocked (coverage)** |
| 2 | 1.00 | 0.00 | 0.27 | 0.00 | 0.03 | 4/4 | 2/4 | continue (min-passes) |
| 3 | 1.00 | 0.00 | 0.07 | 0.00 | 0.01 | 4/4 | 1/4 | continue |
| 4 | 1.00 | 0.00 | 0.07 | 0.00 | 0.00 | 4/4 | 1/4 | **stop (converged)** |

Four things in that table are worth the detour:

- **Pass 1 is four dashes, and a dash is not a zero.** Novelty, churn, thrash and surprise all
  measure change against a previous pass. Pass 1 has none — every finding is new because
  nothing was there — so the engine declines to report a number rather than reporting the
  seeding as though it were movement. Surprise follows churn: with no churn to score the
  prediction against, there is nothing to be surprised by. The signals start reading at pass 2.
- **Coverage moves 0.67 → 1.00 without a single new grade.** That is the phantom path, and it
  is the one move in the system that can flatter the coverage number. Read the next section
  before believing it.
- **Voices stays at 4/4 while delta voices falls to 1/4.** `voices` counts the perspectives
  that argued; `delta voices` counts the ones that emitted anything. On pass 4 all four spoke
  and three of them reported finding nothing — which is a result, and the deliberation file
  says so in their own words. A pass where three voices go quiet on purpose is not the same
  as a pass nobody showed up to, and the two numbers keep that distinction visible.
- **Surprise falls 0.03 → 0.00.** Each pass predicts its own churn before doing any work. By
  pass 4 the loop predicts itself exactly. That is the signal that it has begun to model
  itself rather than just grinding.

## The interesting part: three units left the inventory

Pass 1 enumerated nine screens and graded six. Under SPEC 8.1 that is a hard stop — `coverage
< 1.0` blocks `stop`, with no override — and the pass-1 verdict is `blocked`. The three
ungraded screens were not skipped out of laziness; two of them turned out not to exist, and
the third was never a screen at all.

The engine does not take that on trust. Each removal is an explicit `unit-delete` carrying
`"phantom": true` and its own `why`, and each one is checked against the project on disk:

| Unit | Claim | What the engine did |
|---|---|---|
| `screen.drafts` | enumerated off a stale routing table | resolved `src/screens/drafts.jsx`, found nothing → **verified-missing** |
| `screen.labels` | same stale routing table | resolved `src/screens/labels.jsx`, found nothing → **verified-missing** |
| `screen.digest` | an email template, not a screen | no `path` to resolve → **unverified**, and permanently marked as such |

All three are listed forever under **Phantom units** in `report.md`, each with its `why`, its
pass and its verification result, and the unverified one is called out in bold as the claim
nobody could check. That is the deal the phantom rule makes: dropping a unit you never graded
is possible, but it is explicit, individually justified, checked wherever checking is
possible, and permanently on the record.

The two things that are *not* possible are worth stating, because they are what the rule is
for:

- **Deleting an ungraded unit without a phantom claim does not raise coverage.** The unit
  leaves the inventory and stays in the coverage denominator, and `judge`, `status` and
  `decide` all name it as `(deleted ungraded — still counts)`.
- **A phantom claim on a unit whose file exists is refused**, and it takes the whole delta
  batch with it. Something you can open is not something pass 1 imagined.

## What it found

Seven `must` findings survived to the apply plan (`ponder apply --dry-run --session mail-ui`).
The set has a shape, which is what four passes bought over one:

- **`f-0015`** (Dreamer, pass 1) — error handling exists on exactly one screen. Five screens
  destructure `error` and never read it, so a failed request leaves the spinner up forever.
  No single-screen appraisal found this; it came from reading all six screens as one column.
- **`f-0014`** (Builder, pass 1) — absence is unhandled product-wide rather than screen by
  screen. Filed as one systemic finding precisely so the plan does not order it as four
  unrelated tickets that would produce four different empty states.
- **`f-0004`** — the thread screen's raw HTTP status. The Empath raised its severity to `must`
  on pass 1 with an explicit ranking argument: reach × stakes × recoverability puts it first,
  because thread is the screen a person reaches from a shared link with no other route in.

Pass 2's phantom finding also changed the meaning of an existing one: `f-0006` (compose never
says a draft was saved) got worse, not better, once drafts turned out not to exist — the work
is saved somewhere the reader has no screen to go and find. That edit is in the ledger with
its reasoning.

## Re-running it

The session is closed, so the loop commands refuse it; `status`, `report` and `apply --dry-run`
still read it.

```sh
ponder status --session mail-ui
ponder apply --dry-run --session mail-ui
```

To replay it from scratch against whatever the engine does today, delete `.ponder/mail-ui/`
and feed the files in `.ponder/tmp/` back through `predict → units → grade → deliberate →
delta → judge → decide` in pass order, with the four predictions and four decision reasons
below. The phantom verification reads the real `src/screens/` directory committed here, so
`drafts.jsx` and `labels.jsx` must stay absent for the replay to reproduce.

| Pass | `predict --churn` | `predict --claim` |
|---:|---:|---|
| 1 | 0.9 | Pass 1 builds the set from nothing; the unhandled-absence pattern will dominate. |
| 2 | 0.3 | Pass 2 resolves the three unopened units; two should verify as missing on disk. |
| 3 | 0.08 | Pass 3 should sharpen at most one recommendation and find no new units. |
| 4 | 0.07 | Pass 4 should move at most one grade and confirm the set has settled. |

The four `decide --why` reasons are in `session.json` under `history`, and `ponder start` is
run with `--max-passes 6 --min-passes 3`.

### Why `.ponder/tmp/` is committed

`.ponder/tmp/` holds scratch input files — the unit inventory, the pass-1 finding set, and
each pass's deliberation and delta batch. They are working files, not engine output, and the
engine neither writes nor reads them once a command has consumed them.

They are committed **on purpose**, and the reason is the one above: they are what makes this
session reproducible. Without them the directory is a set of results that can be read but
never re-derived, and the first time the engine's signals change, nobody can tell whether the
committed numbers are still what the engine produces or a fossil of an older version. With
them, the whole run is a fixture: replaying it is how this example is checked against the
current engine, and it currently reproduces byte for byte apart from timestamps and the
absolute project path.

The trade is a handful of duplicated JSON, and it is worth it. If you are copying this
directory's shape for your own committed session, copy the inputs too.

## The other example

[`../example-session-ponder-docs/`](../example-session-ponder-docs/) is a second complete run
— four passes over ponder's own documentation with the `docs` lens, ending converged. It has
full coverage from pass 1, so it never exercises the gate, but it shows a `thrash` event (the
Skeptic reversing a Dreamer add) and a retraction, and two of its findings drove real changes
to this repository.
