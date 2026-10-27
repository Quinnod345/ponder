# Example session — pondering ponder's own documentation

> A second committed run. The primary example is
> [`../example-session/`](../example-session/), which starts `blocked` on partial coverage and
> resolves it with three checked phantom claims — the coverage gate and the phantom rule in
> action. This session has full coverage from pass 1, so it never exercises the gate; what it
> shows instead is a `thrash` event, a retraction, and two findings that drove real changes to
> this repository.

A real, complete `ponder` run, kept so the loop can be read rather than described. Nothing
here was hand-written after the fact: every file under `.ponder/ponder-docs/` was produced
by the engine. The four passes' inputs are kept under `.ponder/tmp/`, so the whole session
replays against the current engine — which is how the numbers below stay honest when the
engine's signals change.

**Subject:** ponder's own documentation · **Lens:** `docs` · **Result:** converged after 4
of a 6-pass budget · **Coverage:** 9 of 9 documents graded.

## What to read, in this order

| File | Why |
|---|---|
| [`.ponder/ponder-docs/report.md`](.ponder/ponder-docs/report.md) | Start here. The whole pondering in one document: the convergence table, prediction vs reality, every finding grouped by document, what was retracted and why, all four deliberations, and the full ledger. |
| [`.ponder/ponder-docs/ledger.jsonl`](.ponder/ponder-docs/ledger.jsonl) | Every delta ever applied, in order, each with the perspective that emitted it and a `why`. 25 lines: the `unit-seed` record that puts pass 1's nine-document inventory on the record, 14 pass-1 finding seeds, then 10 deliberative revisions. |
| `.ponder/ponder-docs/passes/NN/metrics.json` | The eight convergence signals per pass. Read `02` then `04` and watch novelty go 0.06 → 0.00 and surprise go 0.03 → 0.00. |
| `.ponder/ponder-docs/passes/NN/deliberation.json` | What the four voices actually argued, pass by pass. |
| `.ponder/tmp/` | The inputs handed to the engine — the unit inventory, the pass-1 finding set, and each pass's deliberation and delta batch. |

## How the numbers moved

| Pass | Novelty | Churn | Thrash | Surprise | Voices | Delta voices | Advice |
|---:|---:|---:|---:|---:|---:|---:|---|
| 1 | — | — | — | — | 4/4 | 3/4 | continue (min-passes) |
| 2 | 0.06 | 0.25 | 0.25 | 0.03 | 4/4 | 4/4 | continue |
| 3 | 0.00 | 0.06 | 0.00 | 0.01 | 4/4 | 1/4 | continue |
| 4 | 0.00 | 0.06 | 0.00 | 0.00 | 4/4 | 1/4 | **stop (converged)** |

Four things in that table are worth the detour:

- **Pass 1 is four dashes, and a dash is not a zero.** Novelty, churn, thrash and surprise
  all measure change against a previous pass. Pass 1 has none — every finding is new because
  nothing was there — so the engine declines to report a number rather than reporting the
  seeding as though it were movement. The signals start at pass 2.
- **Surprise falls 0.03 → 0.00.** Each pass predicts its own churn before doing any work. By
  pass 4 the loop predicts itself exactly. That is the signal that it has begun to model
  itself rather than just grinding.
- **Thrash 0.25 on pass 2** is one reversing delta, named in the report: the Skeptic deleted
  `f-0016`, which the Dreamer had added on pass 1. That is the loop arguing with itself and
  the engine noticing — one pass over the limit and the verdict would have been `escalate`.
- **Voices stays at 4/4 while delta voices drops to 1/4.** `voices` counts the perspectives
  that argued; `delta voices` counts the ones that emitted anything. On passes 3 and 4 all
  four argued and three of them reported finding nothing, which is a result — the deliberation
  files say so in their own words. SPEC 4.1 rule 6 wants churn below 0.10 to call convergence,
  and against a 16-finding set that allows exactly one delta, so a converging pass here can
  only act once however many voices spoke.

## What it found

Seven `must` findings survived to the apply plan (`ponder apply --dry-run --session ponder-docs`).
Two were verified against the code rather than asserted:

- **`f-0006`** — `harness-notes.md` claimed "nothing in the engine locks anything" and told
  agents to architect around a lost-update race. The engine takes an advisory session lock in
  `lib/session.js`, and the conformance suite pins that behaviour in 45 checks.
- **`f-0017`** — `--mode build` was in SPEC 5's usage line, defined in SPEC 3.1 as "deltas may
  touch disk", and given a row in `protocol.md`. Nothing in `lib/` read `session.mode` except
  `report.js`, which printed it. A documented flag that did nothing.

**Both were acted on.** The lock section in `harness-notes.md` now describes what the lock
actually does — the wait, the stale reclaim, what the loser of a race sees. `--mode` was
retracted rather than implemented: ponder has one mode, it deliberates and produces a plan,
and `ponder apply` is the separate explicit step. Reading those findings next to the files
they are about is the point of keeping this session.

`f-0001` — "the repository has no README at all" — is why the README at the repo root now
exists. This session produced its own follow-up work.

## Re-running it

The session is closed, so the loop commands refuse it; `status`, `report` and
`apply --dry-run` still read it.

```sh
cd docs/example-session
ponder status  --session ponder-docs
ponder report  --session ponder-docs
ponder apply   --session ponder-docs --dry-run
```

It was run with `PONDER_OCA=off` so it is reproducible anywhere and leaves no rows in a
database. The OCA bridge was verified separately against a live Postgres.

**Replaying it from scratch** — every input is in `.ponder/tmp/`, so the session can be
rebuilt against whatever the engine does today. Delete `.ponder/ponder-docs/`, then walk the
four passes with the recorded predictions, deliberations, delta batches and decision reasons
(they are in `report.md` and in each pass's `predict.json` and `verdict.json`). The engine
assigns the same `f-NNNN` ids from the same inputs, so a replay that lands different numbers
means the *signals* changed, not the pondering — which is the point of keeping the inputs
next to the output.
