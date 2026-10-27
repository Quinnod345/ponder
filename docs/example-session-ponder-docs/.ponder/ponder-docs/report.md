# Ponder — ponder's own documentation

`ponder-docs` · lens **docs** · status **converged** · 4 passes of a 6-pass budget · generated 2026-08-24T18:01:25.836Z

| | |
|---|---|
| Subject | ponder's own documentation |
| Lens | docs — unit = document, 6 dimensions |
| Project | `/Users/quinnodonnell/code/ponder/docs/example-session` |
| Passes | 4 run · min 2 · max 6 |
| Coverage | 1.00 — 9 of 9 documents graded |
| Findings | 17 total · 16 open · 0 resolved · 0 deferred · 1 retracted |
| Final verdict | stop (converged) → decided **stop** |
| OCA | off |

## Convergence

| Pass | Coverage | Novelty | Churn | Thrash | Surprise | Stall | Conf-floor | Voices | Advice | Decision |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|---|
| 1 | 1.00 | — | — | — | — | 0 | 0.00 | 4 | continue (min-passes) | continue |
| 2 | 1.00 | 0.06 | 0.25 | 0.25 | 0.03 | 0 | 0.00 | 4 | continue (default) | continue |
| 3 | 1.00 | 0.00 | 0.06 | 0.00 | 0.01 | 0 | 0.00 | 4 | continue (default) | continue |
| 4 | 1.00 | 0.00 | 0.06 | 0.00 | 0.00 | 0 | 0.00 | 4 | stop (converged) | stop |

`—` on pass 1 is not a zero. Novelty, churn, thrash and surprise measure change against a previous pass, and pass 1 has none.

## Overrides

None. Every decision followed the engine's advice.

## Prediction vs reality

| Pass | Predicted churn | Actual churn | Surprise | Claim |
|---:|---:|---:|---:|---|
| 1 | 0.90 | — | — | Pass 1 builds the finding set from nothing; the missing root README will dominate. |
| 2 | 0.28 | 0.25 | 0.03 | Pass 2 should kill at least one of the Dreamer's adds and re-rank the SPEC findings; no new document-level gaps. |
| 3 | 0.07 | 0.06 | 0.01 | Pass 3 should find nothing new; at most one recommendation still needs sharpening. |
| 4 | 0.06 | 0.06 | 0.00 | Pass 4 should move at most one grade and confirm the set has settled. |

## Coverage

9 documents enumerated, 9 graded.

## Findings

### harness-notes.md — Claude Code vs Codex `doc.harness-notes`
`skill/ponder/references/harness-notes.md`

- **f-0006** · must · score 1 · confidence 0.95 · effort s · accuracy — "Nothing in the engine locks anything" is false
  The Known bites section states that nothing in the engine locks, and claims a reproduction where two concurrent `ponder delta` calls both succeed and the loser's edit is lost. The engine has held an advisory session lock since lib/session.js:369, every mutating command takes it via useSession(..., {lock: true}), and the conformance suite pins the opposite behaviour in 45 checks: a race has exactly one winner and the ledger grows by exactly one line. An agent reading this will architect around a hazard that no longer exists.
  Evidence: `skill/ponder/references/harness-notes.md:known-bites`, `lib/session.js:369`, `test/conformance.sh:concurrency`
  Do: Replace the bite with what is now true: the engine takes an advisory lock per session, a race has one winner, and the guidance that only the parent runs ponder stands for a different reason — fan-out agents grade and return text.

- **f-0007** · should · score 3 · confidence 0.75 · effort s · staleness — Machine-specific facts are stated without a shelf life
  The document opens "Facts below were verified on Quinn's personal Mac on 2026-08-24: node v25.5.0 and psql at /opt/homebrew/bin, codex-cli 0.147.0", then mixes those with durable architectural facts. A reader cannot tell which lines expire.
  Evidence: `skill/ponder/references/harness-notes.md:1-8`
  Do: Split the machine-specific block into its own section headed with the verification date, and leave the architectural claims undated.

### protocol.md — command + JSON reference `doc.protocol`
`skill/ponder/references/protocol.md`

- **f-0017** · must · score 1 · confidence 0.90 · effort s · accuracy — `--mode build` is documented but unimplemented
  `ponder start --mode deliberate\|build` is in SPEC 5's usage line, SPEC 3.1 defines build as 'deltas may touch disk', and protocol.md:91 gives it a table row reading 'build permits deltas that touch disk'. In lib/, `session.mode` is validated at cli.js:517, stored, and read exactly once more — report.md:57 prints it. No delta path branches on it. A reader who starts a session with --mode build gets deliberate-mode behaviour and no warning.
  Evidence: `skill/ponder/references/protocol.md:91`, `SPEC.md:135`, `lib/cli.js:517`, `lib/report.js:57`
  Do: Either mark build as reserved-and-unimplemented everywhere it appears, or have `ponder start --mode build` refuse with a message saying so. Documenting a flag that silently does nothing is worse than not offering it.

- **f-0010** · should · score 3 · confidence 0.80 · effort m · staleness — protocol.md restates SPEC.md and will drift from it
  protocol.md is a 441-line mirror of the contract — state layout, phase machine, every command, every file shape, the convergence table and the verdict rules. It names SPEC.md as the authority and says SPEC.md wins on disagreement, which is the right disclaimer, but a disclaimer does not stop drift: two documents now have to be edited together on every contract change and nothing checks that they were.
  Evidence: `skill/ponder/references/protocol.md:1-5`, `skill/ponder/references/protocol.md:343-383`
  Do: Cut the sections that only restate SPEC (convergence signals, verdict rules) down to a pointer, and keep protocol.md for what SPEC deliberately does not carry: worked JSON payloads and the error catalogue.

### README.md — the repository front door `doc.readme-root`
`README.md`

- **f-0001** · must · score 1 · confidence 0.95 · effort m · discoverability — The repository has no README at all
  `ls README.md` fails. A visitor landing in ~/code/ponder gets a bare directory listing: bin, docs, install.sh, lenses, lib, oca, package.json, skill, SPEC.md, test. SPEC.md is the contract and reads like one — 377 lines opening on vocabulary tables — so the only entry point is a document written for implementers, not for someone deciding whether this tool is for them.
  Evidence: `README.md`, `SPEC.md:1-12`
  Do: Write README.md with these sections, each answering one question: what ponder is and the problem it solves; install (install.sh and the symlink into both harnesses); the loop as one diagram; a 60-second quickstart that runs; the full command table; the convergence signals table; OCA integration and how to turn it off; where the lenses live and how to add one.
  _Revised: p2 edit recommendation, p2 edit evidence_

- **f-0015** · must · score 1 · confidence 0.85 · effort m · runnable-examples — No document shows a complete session from start to converged stop
  SPEC.md defines the phases, protocol.md documents each command's payload, and SKILL.md carries a worked example written as instructions to an agent. None of them is a real session: there is no ledger a reader can open, no metrics.json to see the signals move, no report.md to see what the output actually looks like. A reader has to assemble the loop in their head from three documents before they can judge whether it is worth running.
  Evidence: `skill/ponder/SKILL.md:177-390`
  Do: Commit one real session to the repo and link it from the README, so the ledger, the metrics and the report can be read rather than described.

- **f-0002** · must · score 2 · confidence 0.85 · effort s · completeness — No document states the install story end to end
  install.sh does the work and harness-notes.md explains the symlinks, but harness-notes lives three directories down inside the skill and is written for an agent reasoning about its own harness, not for a human installing the tool.
  Evidence: `install.sh:1-20`, `skill/ponder/references/harness-notes.md:9-30`
  Do: Covered by f-0001's install section. Keep this finding only as the reason that section is load-bearing: harness-notes.md is written for an agent reasoning about its own sandbox, and a human installing the tool should not have to read it.
  _Revised: p3 edit recommendation_

### SPEC.md — the contract `doc.spec`
`SPEC.md`

- **f-0003** · must · score 2 · confidence 0.95 · effort xs · accuracy — SPEC 6.1 misstates the cognitive_events enum
  SPEC.md:310 says of cognitive_event_type: "Only these existing labels may be used" and lists seven, adding "Never invent a label — the insert will fail." The live enum in postgres://localhost/oneiro has 33 labels; the seven are a subset. The restriction is a sound design choice, but it is stated as a fact about the database and that fact is wrong, which makes a reader distrust the surrounding table.
  Evidence: `SPEC.md:310-313`
  Do: Reword as a deliberate restriction rather than a claim about the schema: "the enum carries more labels than these; ponder deliberately uses only this subset."

- **f-0004** · must · score 2 · confidence 0.90 · effort s · completeness — SPEC 3.4 never says whether pass-1 seeding is recorded as deltas
  SPEC 3.4 fixes the delta vocabulary and the ledger rules but is silent on whether `ponder grade`'s pass-1 seeding lands on the ledger. SPEC 4 then divides add-deltas and total-deltas by total findings, so the silence decides novelty and churn on pass 1. The engine records the seed, which pins pass-1 novelty near 1.0; the conformance suite raises it as a warning rather than asserting either reading, because the contract does not settle it.
  Evidence: `SPEC.md:159-190`, `test/README.md:warnings`
  Do: Add one sentence to SPEC 3.4 ruling on it, and say what pass-1 novelty and churn are expected to read as a consequence.

- **f-0005** · could · score 3 · confidence 0.80 · effort xs · accuracy — SPEC 5.2's --severity wording is self-contradictory
  SPEC.md:283 says apply selects findings "at or above --severity", which reads as a threshold, but the signature in the same section is `--severity must,should`, which reads as an explicit set. Both readings pass the current implementation, so nothing forces the ambiguity into the open.
  Evidence: `SPEC.md:283-289`
  Do: Pick one. If it is a threshold, write `--severity must` and say the rest are implied; if it is a set, drop "at or above".
  _Revised: p2 change severity_

### perspectives.md — the four voices `doc.perspectives`
`skill/ponder/references/perspectives.md`

- **f-0011** · should · score 3 · confidence 0.80 · effort xs · accuracy — The prompts cite a path no reader outside this machine can open
  The document says the prompts are adapted from the real engine at ~/oneiro/oca-cognitive/deliberation/engine.js and quotes each OCA system prompt verbatim. The quotes carry their own weight, but the citation is unresolvable for anyone who is not on Quinn's Mac, and it is the only evidence offered that the two systems match.
  Evidence: `skill/ponder/references/perspectives.md:1-6`
  Do: Keep the verbatim quotes, mark the path as a local source, and note the OCA version or date they were taken from.
  _Revised: p1 change severity, p1 change confidence_

### Ponder — Project Status.md `doc.project-status`
`docs/Ponder — Project Status.md`

- **f-0008** · should · score 2 · confidence 0.85 · effort s · discoverability — The status document contradicts itself on where it lives
  The file opens with a banner saying it belongs in the Obsidian vault and could not be written there because macOS TCC denies access, with a cp command to run after granting Full Disk Access. So the copy in the repo is by its own account not the real one, and there is no way to tell whether the vault copy now exists and has diverged.
  Evidence: `docs/Ponder — Project Status.md:3-8`
  Do: Either make the repo copy canonical and delete the banner, or move it and leave a one-line pointer. Two copies with a banner explaining why is the worst of the three.

- **f-0009** · should · score 3 · confidence 0.80 · effort xs · staleness — Open threads have gone stale
  "No real-world session run yet against a live project of Quinn's" is listed as an open thread, and the log records Phase 1 as complete with six lens packs built. The repo now carries a worked session under docs/example-session/, so the first thread is answered and nothing in the document points at it.
  Evidence: `docs/Ponder — Project Status.md:92-97`
  Do: Delete the 'No real-world session run yet' bullet, and replace it with a link to docs/example-session/ naming the subject, the pass count and the stop reason.
  _Revised: p1 edit recommendation_

### SKILL.md — the agent entry point `doc.skill`
`skill/ponder/SKILL.md`

- **f-0012** · should · score 3 · confidence 0.80 · effort xs · audience-fit — SKILL.md hard-codes an absolute path to the binary
  The opening tells the agent "The binary is ~/code/ponder/bin/ponder (symlink it to ~/.local/bin/ponder, which is on PATH, or call the absolute path)." That is true on this machine and false on any other checkout, and it is in the first screen an agent reads.
  Evidence: `skill/ponder/SKILL.md:10`
  Do: Lead with `ponder` on PATH, and give the repo-relative fallback rather than one user's home directory.

### oca/README.md — the bridge `doc.oca-readme`
`oca/README.md`

- **f-0014** · could · score 3 · confidence 0.70 · effort s · completeness — The bridge README documents writes far better than reads
  Every table ponder writes gets a column-by-column section and a set of runnable SQL recipes for reading a session back out. The two reads the engine actually performs — priorPondering at start and openObservations at judge — are covered mostly from the writer's side, and openObservations only appears in the degradation table.
  Evidence: `oca/README.md:209-330`
  Do: Give the two reads a short section of their own: the query, when it fires, and what the engine does with the result.

### test/README.md — the conformance suite `doc.test-readme`
`test/README.md`

- **f-0013** · note · score 4 · confidence 0.85 · effort xs · staleness — The test count is written into prose and goes stale on every added test
  "A full run is 64 tests in about three minutes" is a number a reader will trust and a number that changes whenever anyone adds a test. It had already drifted once.
  Evidence: `test/README.md:38`
  Do: Say "about sixty tests in roughly three minutes", or drop the count and keep the runtime.
  _Revised: p4 change severity, p4 change score_

## Retracted

Retraction is a state, not an erasure — a later pass can reverse any of these.

- `f-0016` (doc.spec) — The zero-dependency guarantee is buried in a numbered non-negotiable · retracted in pass 2 by the skeptic: Checked where the guarantee is kept rather than where it is made: test/README.md gives it the whole `deps:` conformance group with a row saying exactly what is asserted, and oca/README.md's opening line calls the bridge zero-dependency. The claim that it appears only in SPEC 8.5 is false.

## Deliberation

### Pass 1

- **skeptic** (confidence 0.80) — Every one of the fourteen was checked against the file it names and all fourteen hold; the enum claim and the locking claim were both verified against the live database and lib/session.js rather than taken on trust. I have nothing to delete this pass, and I would rather say so than manufacture a deletion to look like I argued.
- **builder** (confidence 0.85) — Most of these name a change. The project-status recommendation does not — 'close the thread or the document stops being a status' is a judgment, not something you can do on Monday morning. Findings that cannot be turned into a diff are moods.
- **dreamer** (confidence 0.70) — Every finding here grades a document that exists against what it says. Nobody looked at the shape of the set: there is no worked example anywhere — no document shows a whole session from start to converged stop, so a reader has to assemble the loop from a contract, a reference and a skill. And the zero-dependency promise, which is the most unusual thing about this tool, is asserted once inside a numbered non-negotiable and nowhere a reader would look.
- **empath** (confidence 0.75) — The ranking is written from inside the repo. The perspectives.md path citation is marked 'could', but it is the first thing that breaks for the only audience that matters for a skill — an agent on somebody else's machine. Rank by who hits it and how soon.

Resolution: 2 add, 1 edit, 1 change (plus 14 findings seeded by `ponder grade` before the argument).

### Pass 2

- **skeptic** (confidence 0.85) — f-0016 says the zero-dependency guarantee is buried in SPEC 8.5 and nowhere a reader would look. That is wrong on its own evidence: test/README.md gives it a whole conformance group with a table row explaining what is asserted, and oca/README.md opens by calling the bridge zero-dependency. The Dreamer graded where the promise is *made* and never checked where it is *kept*. Delete it.
- **builder** (confidence 0.90) — f-0001 is the most important finding on the board and its recommendation is a list of nouns. 'Write README.md as the front door' is not a task; a section list with the question each section answers is.
- **dreamer** (confidence 0.85) — Everyone is grading documents against the code they describe. Try the reverse: grade the code against the documents. `--mode deliberate\|build` is offered by the CLI, fixed in SPEC 3.1 as 'deltas may touch disk', and given a table row in protocol.md. Nothing in lib/ ever reads session.mode except report.md, which prints it. The documentation is describing a feature that does not exist.
- **empath** (confidence 0.75) — f-0005 is ranked 'should' for a contradiction where both readings produce the same behaviour today. Nobody is hurt by it this week. Meanwhile a reader who trusts the build-mode docs loses an afternoon. Move the harmless one down and stop spending the reader's attention on it.

Resolution: 1 add, 1 edit, 1 change, 1 delete.

### Pass 3

- **skeptic** (confidence 0.85) — I re-opened f-0017's four evidence anchors — protocol.md:91, SPEC.md:135, cli.js:517, report.js:57 — and the phantom-feature claim holds exactly as written. Nothing else on the board is unsupported. No deletions.
- **builder** (confidence 0.80) — f-0002 now restates the README section list that f-0001 already carries, because I expanded f-0001 last pass. Two findings telling the same person to write the same section is one instruction and one echo. Point f-0002 at the install section instead of repeating the whole outline.
- **dreamer** (confidence 0.60) — I went looking for a third frame and did not find one. The document-against-code direction produced f-0017 last pass and the code-against-document direction is now exhausted for this surface. Nothing to add that would not be invented.
- **empath** (confidence 0.70) — The ranking now matches what it costs a reader: two musts on the missing front door, one on a lie about locking, one on a phantom flag. I would not move anything.

Resolution: 1 edit.

### Pass 4

- **skeptic** (confidence 0.90) — Third re-check of the four must-findings. f-0001 and f-0002 are confirmed by README.md still not existing; f-0006 by lib/session.js:369 and the concurrency group; f-0017 by grepping lib/ for session.mode. Nothing here is unsupported. No deletions, and I would say so if there were.
- **builder** (confidence 0.85) — Every recommendation on the board now names a file and a change. I have nothing left to sharpen without rewriting for its own sake.
- **dreamer** (confidence 0.70) — Two passes without a new frame. The gap-hunting enumerators — a dimension no finding mentions, an audience nobody wrote for, a document that should exist and does not — all come back empty against this inventory. That is a survey result, not silence.
- **empath** (confidence 0.80) — One thing left. f-0013 says the test count in prose goes stale, ranked 'could'. It costs a reader nothing — a wrong count in a README sentence misleads no one about behaviour — and it is sitting above nothing. It is a note, and calling it a finding inflates the apparent size of the problem.

Resolution: 1 change.

## Ledger

24 deltas across 4 passes: 17 add, 3 edit, 3 change, 1 delete.

| Pass | Deltas | Perspectives |
|---:|---|---|
| 1 | 16 add, 1 edit, 1 change | builder, dreamer, empath |
| 2 | 1 add, 1 edit, 1 change, 1 delete | builder, dreamer, empath, skeptic |
| 3 | 1 edit | builder |
| 4 | 1 change | empath |

The full append-only record is `ledger.jsonl`.
