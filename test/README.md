# The ponder conformance suite

This suite is written against [`SPEC.md`](../SPEC.md), not against the engine. Every
expectation about the contract was derived from the contract, which is the only way a test
suite can catch a bug rather than document one. When a test and `lib/*.js` disagree,
`SPEC.md` decides who is wrong.

A handful of tests go past the contract on purpose — concurrency, colour, closed-session
immutability, the slug rule, extensionless files. SPEC.md is silent on all of them, and
silence is not a licence to corrupt a store or lose a pass. Those are marked as such in
the table below and in **Beyond the contract**, so a future reader can tell a conformance
failure from a regression against a behaviour we chose to pin.

POSIX `sh` and standard Unix tools. No frameworks, no npm, no fixtures generated at build
time. The one non-shell tool is a small JSON probe that `lib.sh` writes into its own scratch
directory at startup so the shell can read `session.json` without adding a dependency to the
repo. The engine never sees it.

"POSIX" is checked, not assumed: the suite is run under `dash` as well as under the
system `sh`, because `/bin/sh` on macOS is bash wearing a hat and will happily accept
things dash will not. Fractional `sleep` is the one construct POSIX does not require, so
`lib.sh` probes for it at startup and falls back to whole seconds.

## Running it

```sh
./test/conformance.sh                  # everything
./test/conformance.sh -f coverage      # only tests whose name contains "coverage"
./test/conformance.sh -f 'delta: add'  # substring match, so this narrows to one test
./test/conformance.sh -v               # echo every ponder invocation and its exit status
./test/conformance.sh -l               # list test names, run nothing
./test/conformance.sh -k               # keep the per-test work directories for inspection
```

Exit status is `0` when every test passed and `1` when any test failed, so it drops into
CI unchanged. A `-f` that matches nothing also exits `1` rather than reporting a vacuous
success, because that is almost always a typo, and a bare `-f` with no substring is an
error rather than a silent full run. A full run is 76 tests in about three and a half
minutes; nearly every command and every JSON read starts a node process, and that startup
cost is essentially the entire runtime.

Output is one line per test — green `✓`, red `✗`, with failed assertions listed underneath
— plus yellow `⚠` warnings, which never fail the run. Set `NO_COLOR=1` to strip colour.

| Variable | Effect |
|---|---|
| `PONDER_BIN` | Binary under test. Defaults to `bin/ponder` beside this suite. |
| `PONDER_NODE` | Node executable for the JSON probe. Defaults to `node`. |
| `NO_COLOR` | Any value disables colour. The `output:` group saves, overrides and restores it, so setting it does not weaken that test. |

### The suite is hermetic

It never touches the live OCA at `postgres://localhost/oneiro`. `PONDER_OCA=off` is
exported for the whole run and reset after every test; the OCA group turns the bridge back
on only against a dead port or a stub `psql` it puts on `PATH` itself. `HOME` is pointed at
a scratch directory so a `~/.ponder` fallback cannot escape the run, and every session
lives in a throwaway project directory under `$TMPDIR`. `PATH` and the OCA variables are
restored by the runner after each test, so one leaky test cannot poison the next.

## What each group covers

| Group | What it proves |
|---|---|
| `smoke:` | `--help` names every command in the SPEC 5 contract; `doctor` runs; `start` writes the SPEC 3.1 session skeleton with the right defaults. `--mode` is asserted *gone* — rejected by the parser, absent from `--help`, absent from `session.json` and absent from `report.md` — because a retracted flag that still parses is a flag that will grow an implementation again. |
| `happy:` | A pass-1 walk through predict → survey → appraise → deliberate → revise → judge → decide, asserting the shape of `session.json`, `units.json`, `findings.json`, `ledger.jsonl` and `passes/01/*` after each step; then a three-pass session that reaches a `converged` stop and a generated `report.md`. |
| `coverage:` | The reason ponder exists, tested from every direction we could invent. Grade some units, then try to stop: exit `2`, every ungraded unit id in the output, session still `open`, nothing in `history`. `ponder decide --help` documents no flag that overrides it. Invented flags (`--force`, `--override`, `--ignore-coverage`, …) cannot force a stop — and because the engine rejects those as unknown flags, each iteration also fires a plain `decide stop` and requires the gate itself to refuse it, so the test cannot pass on arg parsing alone. A hand-edited `metrics.json` claiming `coverage: 1` does not unlock it — though read **Proving the suite has teeth** before trusting that test to mean what its name says. Grading a unit and then retracting its only finding drops it back to ungraded and closes the gate again. A `unit-add` on a later pass reopens it, and the stop is then actually refused rather than merely advised against. |
| `coverage:` (`unit-delete`) | The one honest way the ungraded list gets shorter, so it is held to every other delta's rules: a `unit-delete` without a `why` is rejected, an accepted one appends a ledger line, the unit is marked `removedInPass` rather than erased from `units.json`, and the dropped units are named in `report.md`. Narrowing the subject is allowed; doing it invisibly is not. |
| `coverage:` (the phantom rule) | The bypass the gate would otherwise have. Deleting a never-graded unit leaves it in the coverage denominator, so the gate does not open — asserted directly, because a delete that raised coverage would make SPEC 8.1 decorative. It also has to be *legible*: the refusal and `report.md` name a deleted-ungraded unit apart from a merely ungraded one, and say why it still counts, so an agent that tried deleting its way out can see which deletes bought it nothing. `"phantom": true` is then held to the SPEC 3.5 checks from all three directions: a claim on a unit whose path exists is rejected and takes the whole batch with it; a claim on a path that is genuinely gone is accepted, drops out of the denominator and lands under **Phantom units** in `report.md`; a unit with no path is accepted and marked `unverified` there, permanently and distinctly. Scope is asserted too — `phantom` on any other op, on a unit that carries a finding, or as a non-boolean is refused, and the one legal re-delete (upgrading `removed-ungraded` to a checked phantom) works exactly once. |
| `coverage:` (the other doors) | `ponder abort` is the only exit from a blocked session, so the test is that walking through it is never mistaken for the other one: status `aborted`, never `converged` or `stopped`, and a `report.md` that still names what was never graded. And `--session` names a slug, not a path — `../other`, `/etc/passwd` and friends are user errors, because a slug that resolved outside `.ponder/` would let one project's gate be answered with another project's findings. |
| `phase:` | The SPEC 5.1 state machine. Every out-of-order command exits `2` and names the phase the session owes. `units` is pass-1 only, `survey` is skipped afterwards, and `deliberate --skip` needs a `--why` but still advances. |
| `delta:` | `add` assigns a fresh `f-NNNN` and never reuses one, including the id of a retracted finding. `delete` sets `status: retracted` and leaves the object in `findings.json`. `edit` and `change` apply partial sets and leave every other field alone, appending to the finding's `history`. A delta with an empty or missing `why` is rejected and changes nothing. A batch is all-or-nothing: a good line sharing a file with a why-less line, an unknown target, an unknown op or a line that is not JSON leaves the finding set, the ledger and the pass's own `deltas.jsonl` exactly where they were, and the phase still owing its revision — then the same good line is applied on its own to prove the batch really was rejected rather than quietly dropped. `--stdin` works for `units` and `delta`. |
| `ledger:` | Append-only. Pass 1's lines are compared byte-for-byte with `cmp` after passes 2 and 3 have run, and the ledger is checked to be exactly the union of the per-pass `deltas.jsonl` files. |
| `metrics:` | A session that oscillates one severity across three passes reports `thrash > 0.25`; a session that never reverses itself reports `thrash 0`. `stall`, `confidenceFloor` and `voices` are computed. Pass 1 reports `null` — not `0` — for `novelty`, `churn`, `thrash` and `surprise`, because all four measure change against a pass that does not exist; the distinction is asserted as a JSON null, since a test that accepted either would not notice the regression it exists to catch. The `add`s that `ponder grade` writes are excluded from every ratio, so a pass's numbers describe what it changed rather than what it created. And `voices` counts the perspectives that spoke in `deliberation.json`, not the ones that emitted a delta — checked with a pass where those two counts differ, which is the only shape that can tell them apart. |
| `verdict:` | SPEC 4.1 rule ordering, tested with fixtures that satisfy two rules at once: coverage (rule 1) beats the budget stop (rule 7), and `minPasses` (rule 2) beats thrash (rule 3). Pass 1 cannot converge however clean it is. Reaching `maxPasses` reports reason `budget`, never `converged`. |
| `override:` | Deciding against the advice needs a `--why` of at least 12 characters — 9 and 11 are rejected, 12 is accepted — and the reason lands in `verdict.json` and permanently in `report.md` under **Overrides**. |
| `json:` | Every command in the SPEC 5 contract emits one parseable JSON document on stdout under `--json`, checked by piping stdout through `JSON.parse`. Each document also has to carry the next phase, because a `NEXT:` line printed beside the JSON would make stdout unparseable and an agent driving with `--json` would otherwise lose the thread the moment its context is compacted. Failures are machine-readable too: a refused command emits a JSON payload marked `ok: false` on stdout and leaves stderr empty. |
| `next:` | Every command prints a `NEXT:` line, including commands that exit `2`. That line is what survives context compaction, so an error owes it as much as a success does. |
| `exit:` | `0` on success, `1` on user error (unknown command, missing subject, unknown session, out-of-range `--churn`, missing `--file`), `2` on a state-machine violation. |
| `oca:` | The bridge cannot break the engine. `PONDER_OCA=off` never shells out to `psql` for any loop command. A dead DSN under `auto` degrades silently, and every command still exits `0` inside its timeout. A stub `psql` that sleeps for a minute cannot hold the engine open. `PONDER_OCA=on` against an unreachable database is a hard error — not only for `start`, but for every command that writes an OCA row (`deliberate`, `deliberate --skip`, `judge`, `decide stop`, a committed `apply`), while the commands that write none (`status`, `apply --dry-run`) keep working. SPEC 6 makes the hard error a property of the mode, and a `deliberate` that exits `0` there has silently dropped its `deliberations` row. Separately and statically: `cognitive_events.event_type` is a Postgres enum whose live definition carries 33 labels, of which SPEC 6.1 sanctions seven. `bridge.js` is scanned in both directions — it must use none of the other 26, and every label it does use must be a real enum member. A label outside the enum fails the insert and one inside it but outside the subset misfiles the row, and neither shows up in a run with `PONDER_OCA=off`. |
| `apply:` | The fixture source tree is checksummed before and after `ponder apply` and `apply --dry-run`; a single changed byte outside `.ponder/` fails the test. The plan is grouped by unit, carries evidence paths and recommendations, excludes retracted findings, and honours `--severity`. `--dry-run` writes nothing and does not mark the session `applied`, and it stays available on an open session — committing a plan does not, because SPEC 5.2 marks the session `applied` and a session with a pass still owed has nothing to commit. An `aborted` session is refused both ways, `--dry-run` included: SPEC 5.2 will not let a pondering somebody walked out of become an applied one. |
| `input:` | The boring failures. Truncated and garbage JSON, a directory passed as `--file`, a missing file, `units` with neither `--file` nor `--stdin`, and `--stdin` with nothing on it are all user errors that print a `NEXT:` line, leave no half-written state, and never surface a node stack trace. An extensionless file resolves like any other. An empty unit inventory is refused outright, because SPEC 4.1 rule 1 has to divide by something. Coverage counts distinct graded units, not findings — four findings on one screen is one screen — and a finding about a unit nobody enumerated is refused. A unicode subject and a project path with a space in it survive `start`, `status`, `report --out` and `--json` unchanged, while a slug that is not a safe directory name is refused. A duplicate slug never overwrites the session already there. |
| `lens:` | Every lens named in SPEC 1 opens a session, reports its unit and its dimension count, and names all five rungs of its scale — SPEC 3.3 fixes the range and leaves the wording to the pack, so the wording is not asserted. A count is not a rubric, so each pack's dimension *names* are read straight out of its front matter — deliberately not through `lib/lens.js`, so a parser that drops one cannot also drop it from the expectation — and every one of them is required to reach `ponder start`, `ponder units` (the handoff into appraise, where grading actually starts) and `ponder status` (what an agent runs after losing its context). `--lens custom --rubric <file>` loads a front-matter file and records it by name; a missing `--rubric`, a `--rubric` pointing at nothing, and a rubric with no front matter are all user errors. |
| `output:` | Colour is decided by the terminal, not by the caller. Nothing coloured reaches a redirected stdout or stderr, `--json` is never coloured, a real pty does get colour, and `NO_COLOR` turns it off there too. The pty half runs under `script` and degrades to a warning where `script` is unusable. |
| `deps:` | SPEC 8.5, the one non-negotiable that is invisible at runtime. `package.json` declares no dependencies of any kind, there is no lockfile and no `node_modules/`, and every module `lib/`, `bin/` and `oca/` import is a node builtin or a relative path. |
| `concurrency:` | Not in SPEC.md, but every mutating command is a read-decide-write over three files, and two of those interleaved is how "ids are never reused" and "the ledger is every delta ever applied" come apart. A race has to have a winner: two `delta` invocations at once (three rounds, three fresh sessions) commit exactly one, grow the ledger by exactly one line, advance the phase once, and leave `findings.json` agreeing with the line that landed. Two `decide continue` at once record one pass, not two. Two `start` on one slug leave one readable session. Between them these two tests are the only place the session lock in `lib/session.js` is pinned — 45 checks in the first, 14 in the second — so they are also the documentation for it. |
| `lifecycle:` | `abort` needs a reason and closes the session as `aborted`; `list` and `status` report where the loop is; `--session` defaults to the most recently touched **open** session, checked with three sessions rather than one so the rule is visible. A closed session refuses `predict`, `units`, `grade`, `deliberate`, `delta`, `judge`, `decide` and `abort` — each with a `NEXT:` line, without reopening, and without appending to the ledger — while `status` and `report` still read it. |

## Warnings

A yellow `⚠` is an observation, not a failure. The suite emits one where SPEC.md asks it
to, one where SPEC.md is genuinely open, and one where the machine cannot run a check:

- **A `change` delta whose `set` touches only prose.** SPEC 3.4 says the engine does not
  enforce which fields go with which op, but that the suite warns, because re-grading
  disguised as an edit is invisible to the thrash detector. Warned twice: once in the happy
  path, once in the `delta:` group that exists to provoke it.
- **No usable `script(1)`.** The terminal half of the `output:` group needs a pty. Where
  `script` is missing or takes neither the BSD nor the GNU argument form, that half is
  skipped with a warning rather than failing on an unrelated missing tool.

There used to be a third: pass-1 seeding, which SPEC.md was silent about, so the suite
reported what the engine chose instead of asserting either reading. The spec now answers it —
seeding is recorded in the ledger and excluded from every ratio, and pass 1 reports no
`novelty`, `churn`, `thrash` or `surprise` at all — so that observation became the two
assertions in the `metrics:` group. A warning is what a suite writes while the contract is
undecided, and it should not outlive the decision.

## Proving the suite has teeth

A green suite means nothing until you have watched it go red for the right reason. Every
group here was checked by mutating a *copy* of the engine and confirming that the tests
which should notice do, and that the tests which should not, don't. The mutations that
matter, and who caught them:

| Mutation on a copy of the engine | Caught by |
|---|---|
| Both `stop` guards in `checkDecision` replaced with `if (false)` | Nine tests: `coverage: decide stop`, `coverage: invented override flags`, `coverage: a tampered metrics.json`, `coverage: retracting a unit last finding`, `coverage: a unit added on a later pass`, `coverage: deleting ungraded units does not open the gate`, `coverage: a phantom claim with a live path`, `verdict: coverage outranks the budget stop`, `input: coverage counts units, not findings` |
| A delta batch applies its good lines and reports the bad ones instead of rejecting the batch | Six tests: `delta: one bad line rejects the whole batch` (26 of 36 checks), `delta: a delta without a why`, `coverage: unit-delete narrows the subject on the record`, both phantom tests, `input: coverage counts units, not findings` |
| `lockSession` degrades to a no-op | `concurrency: racing deltas` (both invocations exit 0, the ledger grows by two lines), `concurrency: racing decisions and starts` (one pass recorded twice) |
| **`decide` takes `coverage` *and* `ungraded` straight from `metrics.json` instead of recomputing them** | **Nothing. The whole suite passes.** See below |

That last row is the one to read. `coverage: a tampered metrics.json` is named for exactly
this mutation and does not catch it, because the two halves miss each other: the test
rewrites every key called `coverage` to `1` and leaves `metrics.ungraded` alone, while the
engine's gate is `coverage < 1 || ungraded.length > 0` — so the untouched ungraded list
refuses the stop and the recompute is never what saved it. An engine that trusted
`metrics.json` wholesale would still be caught by *this* tamper, and would not be caught by a
tamper that also emptied `ungraded`. **To close it, the test should empty `ungraded` as well
as zeroing the coverage number, and assert the refusal still names the unit.**

That is the point of this section. `coverage: invented override flags` was the first case:
it used to assert only that each invented flag exited non-zero and left the session open —
which the engine satisfies by rejecting them as unknown flags, so the test passed with the
gate ripped out. It now fires a plain `decide stop` in the same loop and requires the gate to
refuse that too. Any test whose subject is a refusal should be read with the same suspicion:
ask what else could produce that exit code, and assert past it. A test that has never been
watched go red for its own reason is a claim, not evidence.

## Where the suite deliberately stays loose

Five places, all because SPEC.md fixes a behaviour without fixing a shape. Each one is
handled by measuring rather than hard-coding, so a conformant engine passes whichever
choice it made:

1. **Ledger and delta counts** are asserted as growth — "the ledger grew by exactly the
   deltas I applied", "the ledger is the union of the per-pass files" — never as absolute
   line counts, so a change in how the engine records seeding cannot break every test that
   merely needs the ledger to be append-only.
2. **Later-pass phase order.** SPEC 5.1 says `ponder delta` satisfies `appraise` and
   `revise` together on later passes, but does not say where `deliberate` sits relative to
   that. `later_pass()` in `conformance.sh` follows `session.phase` and supplies whatever
   the engine asks for. Asking for `survey` after pass 1, or asking for a second `delta` in
   one pass, is still a failure.
3. **`verdict.json` key names.** SPEC 4.1 fixes the verdict values (`continue`, `stop`,
   `escalate`, `blocked`) and the stop reasons (`perseveration`, `converged`, `budget`) but
   not the object that carries them, so `jfind` searches the JSON breadth-first for the
   first scalar under a `verdict`/`advice`/`reason` key. Metric names come straight from
   the SPEC 4 table and are asserted exactly.
4. **Lens scale wording.** SPEC 3.3 fixes the 1–5 range and says the packs define each
   rung, so the `lens:` group asserts that all five rungs are named and not what they say.
5. **Which exit code a malformed payload gets.** SPEC 5's table makes `1` the reading for
   user error, so a delta with no `why`, `deliberate --skip` without `--why`, `abort`
   without `--why` and a malformed `--file` are all asserted as `1`. The spec does not
   spell those four out; `2` would be a defensible engine and an indefensible silence.

Everything else about the contract is asserted literally.

## Beyond the contract

Four things the suite pins that SPEC.md never mentions. Each is written down here because
a test with no clause behind it is the kind of test people delete during a refactor.

1. **Concurrency.** Not in the spec, but every mutating command is a read-decide-write over
   `session.json`, `findings.json` and `ledger.jsonl`. Two interleaved is how SPEC 3.3's
   "ids are never reused" and SPEC 3.4's "every delta ever applied" break without anyone
   editing either file. The suite requires a race to have a winner rather than a merge —
   which is what `lockSession` in `lib/session.js` delivers, and these are the only two
   tests that hold it to it.
2. **Closed-session immutability.** SPEC 3.1 gives a session five states and only one of
   them is `open`. A closed session that still accepts `delta` is a session whose
   `report.md` can be contradicted after it was written, so every loop command is required
   to bounce while `status` and `report` still read it.
3. **Colour.** SPEC 5 puts machine output behind `--json`, which only holds up if the human
   output is plain when a machine is reading it. Escape sequences on a redirected stdout
   would be a `--json` contract failure one pipe removed.
4. **The slug rule.** SPEC 3 puts sessions in `.ponder/<slug>/`, so a slug is a directory
   name. The suite requires one that is not a safe directory name to be refused rather than
   to create a session nobody can name again — it does not assert which characters.
`unit-delete` bookkeeping used to be the fifth. It is now SPEC 3.5, in more detail than the
suite had invented for it: removal kinds, the phantom claim and how the engine verifies it.
The tests that were beyond the contract are now conformance tests, which is the outcome to
want — a suite that pins a behaviour long enough for the spec to catch up has done its job.

## The files

```
test/
  conformance.sh     the tests, the session builders, and main
  lib.sh             colours, counters, assertions, the JSON probe, the CLI runner
  fixtures/*.json    units, finding sets, one deliberation
  fixtures/*.jsonl   delta batches, one per scenario
```

`lib.sh` is generic plumbing and knows nothing about ponder's semantics. Everything that
encodes SPEC.md lives in `conformance.sh`.

### Fixtures

| File | Used for |
|---|---|
| `units-3.json` | Three UI units. Every session starts from this inventory. |
| `findings-full.json` | Twelve findings across all three units, every confidence above 0.5. Sized so one delta lands under the SPEC 4.1 rule 6 churn threshold and four do not. |
| `findings-partial.json` | Two findings, both on the billing screen. Leaves two units ungraded, which is what the coverage group runs on. |
| `findings-tiny.json` | One finding per unit. Fast full coverage for the delta group. |
| `deliberation.json` | Four perspectives with arguments and confidences, written in both the array shape and the keyed shape so a strict reader of either is satisfied. |
| `deltas-*.jsonl` | One batch per scenario: the four-voice pass, quiet later passes, an oscillating severity, a prose-only `change`, a missing `why`, a `unit-add`. |

Some tests build their input inline instead — the retraction batch, the unit-delete batch,
the same-unit and unknown-unit finding sets, and the custom rubric — because each is
derived from ids the engine has just assigned, or is a one-off shape that would only ever
have one reader.

Delta fixtures never hard-code finding ids. They carry `@F1@`, `@F2@`, … placeholders, and
`delta_file()` substitutes the real engine-assigned ids out of `findings.json` at the
moment the delta is applied. The engine owns id assignment; the suite asserts the format
and the uniqueness, never the numbering base.

## Adding a case

1. Write a `t_*` function in `conformance.sh`, in the group it belongs to.
2. Call `new_workdir <short-name>` first. It creates a throwaway project with a fake source
   tree, copies `units.json` and `deliberation.json` into it, and sets `$WORK` and `$SLUG`.
3. Drive the CLI through the `p_*` wrappers (`p_start`, `p_predict`, `p_units`, `p_grade`,
   `p_deliberate`, `p_delta`, `p_judge`, `p_decide`) or `run_ponder` directly for the
   cases where you need an odd argument list. Every run leaves `$STATUS`, `$OUT`, `$ERR`,
   `$ALL` and `$ELAPSED` set.
4. Assert. The last argument of every assertion is the label printed on failure — write it
   as the claim being made, and cite the SPEC section when the assertion is not obvious.
5. Register it with a `run_test '<group>: <what it proves>' t_your_function` line in the
   main block at the bottom. The name is what `-f` matches on, so keep the group prefix.

To reuse a whole session, call one of the builders: `build_converged_session` (three
passes to a converged stop, snapshotting the ledger after each pass),
`build_partial_session` (parked at `judge` with two units ungraded), or
`build_thrash_session <minPasses>` (three passes oscillating one severity).

### The assertions

```
assert_status <expected> <label>        assert_status_not <expected> <label>
assert_eq <expected> <actual> <label>   assert_ne <unexpected> <actual> <label>
assert_match <text> <regex> <label>     assert_imatch   (case-insensitive)
assert_no_match <text> <regex> <label>  assert_no_imatch
assert_contains <text> <literal> <lbl>  assert_not_contains
assert_file <path> <label>              assert_no_file / assert_dir
assert_gt / assert_lt / assert_le / assert_ge_int <a> <b> <label>
assert_close <actual> <expected> <tolerance> <label>
assert_json_stdout <label>              assert_json_next <label>
assert_next <label>                     assert_session_field <js-expr> <expected> <label>
assert_parses <json-file> <label>       assert_jsonl_parses <jsonl-file> <label>
assert_no_ansi <text> <label>           assert_has_ansi <text> <label>
fail <message>                          warn <message>
```

Reading JSON from the shell:

```sh
jget  <file> <js-expression-over-d>     # d is the parsed document
jl    <jsonl-file> <expression>         # d is the array of parsed lines
jfind <file> <key> [key...]             # first scalar under any of those keys, any depth
jlines <jsonl-file>                     # line count, fails if a line is not JSON
jout  <js-expression-over-d>            # the last run's --json stdout, parsed
```

Path helpers: `sess <relative>` for a file in the session directory, `pass_dir <n>` for
`passes/NN`, `ledger_lines` and `pass_delta_lines <n>` for ledger and per-pass delta
lengths, `hash_tree` for a checksum of the project tree excluding `.ponder/`.

Runners beyond `run_ponder`:

```sh
run_ponder_stdin <file> <args...>       # feed a file on stdin
run_ponder_limit <seconds> <args...>    # wall-clock watchdog; sets TIMED_OUT
run_ponder_tty <args...>                # stdout on a pty; sets TTY_OUT, returns 1 if unavailable
run_ponder_pair <fileA> <fileB> <args…> # two at once, @FILE@ marks the differing argument;
                                        # sets PAIR_RC_A and PAIR_RC_B
```

The runner clears `$WORK`, `$SLUG`, `$OUT`, `$ERR`, `$ALL`, `$STATUS` and `$JSON_FLAG`
before every test, so a test that forgets its `new_workdir` fails on its own missing state
instead of quietly asserting against the previous test's session.

## If a test fails

Run it alone with `-v -k`:

```sh
./test/conformance.sh -f 'coverage: decide stop' -v -k
```

`-v` prints every invocation with its exit status and duration; `-k` keeps the work
directory, whose path is printed in the header line, so you can open the session and read
`session.json`, `ledger.jsonl` and `passes/NN/metrics.json` for yourself.
