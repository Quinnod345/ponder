#!/bin/sh
#
# test/conformance.sh — the ponder conformance suite.
#
# Every expectation in this file is derived from SPEC.md, not from the engine's
# source. If a test here disagrees with lib/*.js, SPEC.md decides who is wrong.
#
#   ./test/conformance.sh                 run everything
#   ./test/conformance.sh -f coverage     run tests whose name contains "coverage"
#   ./test/conformance.sh -v              echo every ponder invocation
#   ./test/conformance.sh -l              list test names and exit
#   ./test/conformance.sh -k              keep the per-test work directories
#
# Exit status: 0 when every test passed, 1 when any test failed.

set -u

# ------------------------------------------------------------------ options --

FILTER=''
VERBOSE=0
KEEP=0
LIST_ONLY=0

usage() {
  cat <<'EOF'
usage: test/conformance.sh [-f SUBSTRING] [-v] [-l] [-k]

  -f SUBSTRING   only run tests whose name contains SUBSTRING
  -v             echo every ponder invocation and its exit status
  -l             list the test names and exit
  -k             keep the per-test work directories for inspection
  -h             this message

environment:
  PONDER_BIN     binary under test (default: bin/ponder next to this suite)
  PONDER_NODE    node executable (default: node)
  NO_COLOR       set to disable colour
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    -f)
      # Without this guard `shift 2` on a lone -f leaves FILTER empty and the
      # suite runs everything, which reads as "my filter matched all 60 tests".
      if [ $# -lt 2 ]; then
        printf '%s\n' '-f needs a substring' >&2; usage >&2; exit 1
      fi
      FILTER=$2; shift 2 ;;
    -f*) FILTER=${1#-f}; shift ;;
    -v) VERBOSE=1; shift ;;
    -l) LIST_ONLY=1; shift ;;
    -k) KEEP=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'unknown option: %s\n' "$1" >&2; usage >&2; exit 1 ;;
  esac
done

# -------------------------------------------------------------- environment --

HERE=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH='' cd -- "$HERE/.." && pwd)
PONDER_BIN=${PONDER_BIN:-$REPO_ROOT/bin/ponder}
FIXTURES="$HERE/fixtures"
SUITE_TMP=$(cd "$(mktemp -d "${TMPDIR:-/tmp}/ponder-conformance.XXXXXX")" && pwd -P)

export REPO_ROOT PONDER_BIN FIXTURES SUITE_TMP VERBOSE KEEP LIST_ONLY FILTER

# The suite is hermetic. It never talks to the live OCA at postgres://localhost/oneiro:
# the bridge is off by default and the OCA group turns it on against dead or fake
# endpoints only. HOME is sandboxed so a ~/.ponder fallback cannot escape the run.
export PONDER_OCA=off
unset PONDER_OCA_DSN 2>/dev/null || true
export HOME="$SUITE_TMP/home"
mkdir -p "$HOME"

# shellcheck source=test/lib.sh
. "$HERE/lib.sh"

cleanup() {
  [ "$KEEP" = "1" ] || rm -rf "$SUITE_TMP"
}
trap cleanup EXIT INT TERM

json_helper_init

if [ "$LIST_ONLY" != "1" ]; then
  if [ ! -x "$PONDER_BIN" ]; then
    printf '%s\n' "${C_RED}conformance: $PONDER_BIN is missing or not executable${C_OFF}" >&2
    exit 1
  fi
  if ! command -v "$NODE" >/dev/null 2>&1; then
    printf '%s\n' "${C_RED}conformance: node not found (set PONDER_NODE)${C_OFF}" >&2
    exit 1
  fi
fi

# --------------------------------------------------------- session driving ---

SUBJECT='the UI of the fixture app'
JSON_FLAG=''

# pcmd: run a ponder command; in --json mode also require parseable stdout.
pcmd() {
  # shellcheck disable=SC2086
  run_ponder "$@" ${JSON_FLAG}
  if [ -n "$JSON_FLAG" ]; then
    assert_json_stdout "$1 --json"
    assert_json_next "$1 --json"
  fi
}

p_start()      { pcmd start "$SUBJECT" --lens ui --project "$WORK" --slug "$SLUG" "$@"; }
p_predict()    { pcmd predict --session "$SLUG" --churn "$1" --claim "$2"; }
p_units()      { pcmd units --session "$SLUG" --file "$WORK/units.json"; }
p_grade()      { pcmd grade --session "$SLUG" --file "$1"; }
p_deliberate() { pcmd deliberate --session "$SLUG" --file "$WORK/deliberation.json"; }
p_delta()      { pcmd delta --session "$SLUG" --file "$(delta_file "$1")"; }
p_judge()      { pcmd judge --session "$SLUG"; }
p_decide()     { pcmd decide "$1" --session "$SLUG" --why "$2"; }

# p_judge_json — the only judge call for a pass, captured for verdict extraction.
JUDGE_JSON="" ; JUDGE_VERDICT="" ; JUDGE_REASON=""
p_judge_json() {
  run_ponder judge --session "$SLUG" --json
  JUDGE_JSON="$SUITE_TMP/judge-$$.json"
  printf '%s' "$OUT" > "$JUDGE_JSON"
  assert_json_stdout 'judge --json'
  JUDGE_VERDICT=$(jfind "$JUDGE_JSON" verdict advice)
  JUDGE_REASON=$(jfind "$JUDGE_JSON" reason)
}

# ledger_lines — lines currently on the ledger, 0 when it does not exist yet.
# Counts are always compared as growth, never as absolutes: SPEC 3.4 fixes that
# the ledger is the union of the per-pass delta files and that applying a delta
# appends a line, but it does not say whether the pass-1 grade seeding is itself
# recorded as deltas.
ledger_lines() {
  if [ -f "$(sess ledger.jsonl)" ]; then jlines "$(sess ledger.jsonl)"; else printf '0'; fi
}

# pass_delta_lines <n> — lines in passes/NN/deltas.jsonl, 0 when it does not exist
pass_delta_lines() {
  if [ -f "$(pass_dir "$1")/deltas.jsonl" ]; then jlines "$(pass_dir "$1")/deltas.jsonl"; else printf '0'; fi
}

# metric_json <pass> <name> — the raw JSON of a top-level metrics.json field, so `null`
# (a signal that does not exist for this pass) can be told from an absent key. `metric`
# above searches for a scalar and cannot see a null at all.
metric_json() {
  jget "$(pass_dir "$1")/metrics.json" \
    "(Object.prototype.hasOwnProperty.call(d, '$2') ? JSON.stringify(d.$2) : undefined)"
}

phase_now() { jget "$(sess session.json)" 'd.phase'; }
status_now() { jget "$(sess session.json)" 'd.status'; }
pass_now()  { jget "$(sess session.json)" 'd.currentPass'; }
metric()    { jfind "$(pass_dir "$1")/metrics.json" "$2"; }

# ok <label> — the previous command must have succeeded
ok() { assert_status 0 "$1"; }

# pass_one <findings-file> <deltas-fixture> — the pass-1 walk in spec order
pass_one() {
  p_predict 0.45 'Pass 1 inventories the screens and grades the obvious gaps.'
  ok 'pass 1 predict'
  p_units;            ok 'pass 1 units'
  p_grade "$1";       ok 'pass 1 grade'
  p_deliberate;       ok 'pass 1 deliberate'
  p_delta "$2";       ok 'pass 1 delta'
}

# later_pass <deltas-fixture> <predicted-churn> <claim>
# Walks a pass after the first by following session.phase, because SPEC 5.1
# leaves the ordering of deliberate against the delta-satisfies-appraise rule
# open. Anything the engine asks for, the suite supplies; a request for survey
# or a second delta on one pass is itself a conformance failure.
later_pass() {
  _lp_delta_used=0
  _lp_delib_used=0
  _lp_guard=0
  while [ "$_lp_guard" -lt 8 ]; do
    _lp_phase=$(phase_now)
    case "$_lp_phase" in
      predict)
        p_predict "$2" "$3" ;;
      survey)
        fail "SPEC 5.1: survey is skipped automatically after pass 1, but the engine asked for it on pass $(pass_now)"
        return 1 ;;
      appraise|revise)
        if [ "$_lp_delta_used" = "1" ]; then
          fail "SPEC 5.1: ponder delta satisfies appraise and revise together, but the engine asked for a second delta on pass $(pass_now)"
          return 1
        fi
        p_delta "$1"
        _lp_delta_used=1 ;;
      deliberate)
        if [ "$_lp_delib_used" = "1" ]; then
          fail "SPEC 2: one pass holds one deliberation, but the engine asked for a second on pass $(pass_now)"
          return 1
        fi
        p_deliberate
        _lp_delib_used=1 ;;
      judge)
        return 0 ;;
      *)
        fail "unexpected phase [$_lp_phase] while driving pass $(pass_now)"
        return 1 ;;
    esac
    if [ "$STATUS" -ne 0 ]; then
      fail "pass $(pass_now): \`$LAST_CMD\` exited $STATUS
$(printf '%s\n' "$ALL" | head -6 | sed 's/^/          | /')"
      return 1
    fi
    _lp_guard=$((_lp_guard + 1))
  done
  fail "pass $(pass_now) never reached the judge phase"
  return 1
}

# build_converged_session — twelve findings, four voices in pass 1, then two
# quiet passes. Under SPEC 4.1 rule 6 that is a convergence, not a budget stop.
# Snapshots the ledger after each pass so the append-only test can compare.
LEDGER_SNAP1='' ; LEDGER_SNAP2='' ; LEDGER_N1=0 ; LEDGER_N2=0
build_converged_session() {
  new_workdir converged
  p_start --max-passes 6 --min-passes 2
  ok 'start'

  pass_one "$FIXTURES/findings-full.json" deltas-pass1.jsonl
  LEDGER_SNAP1="$SUITE_TMP/ledger-p1.snap"
  LEDGER_N1=$(jlines "$(sess ledger.jsonl)")
  cp "$(sess ledger.jsonl)" "$LEDGER_SNAP1" 2>/dev/null
  p_judge;  ok 'pass 1 judge'
  p_decide continue 'Coverage is complete but a single pass is an opinion.'
  ok 'pass 1 decide'

  later_pass deltas-pass2.jsonl 0.50 'Pass 2 should only sharpen recommendations.' || return 1
  LEDGER_SNAP2="$SUITE_TMP/ledger-p2.snap"
  LEDGER_N2=$(jlines "$(sess ledger.jsonl)")
  cp "$(sess ledger.jsonl)" "$LEDGER_SNAP2" 2>/dev/null
  p_judge;  ok 'pass 2 judge'
  p_decide continue 'Novelty is gone but the rule needs a second quiet pass.'
  ok 'pass 2 decide'

  later_pass deltas-pass3.jsonl 0.08 'Pass 3 should find nothing new at all.' || return 1
  p_judge_json
  ok 'pass 3 judge'
}

# ------------------------------------------------------------------- smoke ---

t_smoke_help() {
  new_workdir help
  run_ponder --help
  ok 'ponder --help exits 0'
  # Match the usage line, not the bare word: "list" and "start" occur in ordinary
  # prose, so a substring check would pass on help text that documents nothing.
  for c in start units predict grade deliberate delta judge decide status verify report apply list abort doctor version; do
    assert_match "$ALL" "(^|[[:space:]])ponder $c([[:space:]]|$)" "--help gives a usage line for $c"
  done
  assert_contains "$ALL" '--session' '--help documents the --session flag (SPEC 5)'
  assert_contains "$ALL" '--json' '--help documents the --json flag (SPEC 5)'
  assert_contains "$ALL" '--repair' '--help documents verify --repair (SPEC 3.6)'
}

t_smoke_version_is_discoverable() {
  # SPEC 5. `ponder version` runs and prints a version, and a command that runs but is
  # documented nowhere is a command nobody can find — so it has to be in the command
  # list, in `ponder help version`, and in SPEC 5's CLI block.
  new_workdir version
  run_ponder version
  ok 'ponder version exits 0'
  assert_match "$ALL" 'ponder [0-9]+[.][0-9]+[.][0-9]+' 'and prints a semantic version'
  assert_next 'and prints NEXT like every other command'

  run_ponder version --json
  ok 'ponder version --json exits 0'
  assert_json_stdout 'version --json'
  assert_match "$(jout 'd.version')" '^[0-9]+[.][0-9]+[.][0-9]+$' 'with the version in the payload'

  run_ponder --help
  ok '--help exits 0'
  assert_match "$ALL" '(^|[[:space:]])version([[:space:]]|$)' \
    'the command list names version (SPEC 5)'
  assert_match "$ALL" '(^|[[:space:]])ponder version([[:space:]]|$)' 'with its usage line'

  run_ponder help version
  ok 'ponder help version exits 0'
  assert_contains "$ALL" 'ponder version' 'and prints its usage'

  # And the spec's own CLI block lists it, so an extractor reading either agrees.
  assert_match "$(cat "$REPO_ROOT/SPEC.md")" '^ponder version' \
    'SPEC 5 lists ponder version in the CLI contract'
}

t_smoke_doctor() {
  new_workdir doctor
  run_ponder doctor
  ok 'doctor exits 0 with the bridge off'
  assert_next 'doctor prints NEXT'
  assert_imatch "$ALL" 'oca' 'doctor reports on the OCA bridge'
}

t_smoke_start_shape() {
  new_workdir start
  p_start --max-passes 6 --min-passes 2
  ok 'start exits 0'
  assert_next 'start prints NEXT'
  assert_dir "$WORK/.ponder/$SLUG" 'start creates .ponder/<slug>/'
  assert_file "$(sess session.json)" 'start writes session.json'

  assert_session_field 'd.version'     '1'                'session.json version is 1'
  assert_session_field 'd.slug'        "$SLUG"            'session.json carries the slug'
  assert_session_field 'd.subject'     "$SUBJECT"         'session.json carries the subject'
  assert_session_field 'd.lens'        'ui'               'session.json carries the lens'
  assert_session_field 'd.project'     "$WORK"            'session.json carries the project path'
  assert_eq 'undefined' "$(jget "$(sess session.json)" 'typeof d.mode')" \
    'session.json carries no mode — there is exactly one mode (SPEC 3.1)'
  assert_session_field 'd.status'      'open'             'a new session is open'
  assert_session_field 'd.currentPass' '1'                'a new session is on pass 1'
  assert_session_field 'd.phase'       'predict'          'the first phase owed is predict'
  assert_session_field 'd.maxPasses'   '6'                '--max-passes is honoured'
  assert_session_field 'd.minPasses'   '2'                '--min-passes is honoured'
  assert_match "$(jget "$(sess session.json)" 'd.createdAt')" \
    '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}' 'createdAt is an ISO timestamp'
  assert_eq 'array' "$(jget "$(sess session.json)" 'Array.isArray(d.history) ? "array" : typeof d.history')" \
    'history is an array'
  assert_eq 'false' "$(jget "$(sess session.json)" 'String(!!(d.oca && d.oca.enabled))')" \
    'oca.enabled is false under PONDER_OCA=off'
}

t_smoke_defaults() {
  new_workdir defaults
  p_start
  ok 'start without pass bounds exits 0'
  _min=$(jget "$(sess session.json)" 'd.minPasses')
  _max=$(jget "$(sess session.json)" 'd.maxPasses')
  assert_gt "$_min" '0' 'minPasses defaults above zero'
  assert_gt "$_max" "$_min" 'maxPasses defaults above minPasses'
}

# ------------------------------------------------------------------- happy ---

t_happy_pass_one() {
  new_workdir pass1
  p_start --max-passes 6 --min-passes 2
  ok 'start'

  p_predict 0.45 'Pass 1 inventories the screens and grades the obvious gaps.'
  ok 'predict'
  assert_file "$(pass_dir 1)/predict.json" 'predict writes passes/01/predict.json'
  assert_eq 'ui-conformance' "$SLUG" 'slug fixed for this session'
  assert_eq '0.45' "$(jfind "$(pass_dir 1)/predict.json" churn predictedChurn)" \
    'predict.json records the predicted churn'
  assert_session_field 'd.phase' 'survey' 'predict advances the phase to survey'

  p_units; ok 'units'
  assert_file "$(sess units.json)" 'units writes units.json into the session'
  # SPEC 3.4: nothing enters a session's state without a ledger line, the pass-1 inventory
  # included. Without this record units.json is the coverage denominator taken on trust.
  assert_eq '1' "$(jl "$(sess ledger.jsonl)" 'd.filter(x => x.op === "unit-seed").length')" \
    'units writes exactly one unit-seed record to the ledger (SPEC 3.4)'
  assert_eq 'screen.settings.billing,screen.settings.profile,screen.onboarding.welcome' \
    "$(jl "$(sess ledger.jsonl)" 'd.find(x => x.op === "unit-seed").ids.join(",")')" \
    'the unit-seed record carries every enumerated unit id, in order'
  assert_eq 'true' \
    "$(jl "$(sess ledger.jsonl)" 'JSON.stringify(d.find(x => x.op === "unit-seed").units.map(u => u.id)) === JSON.stringify(d.find(x => x.op === "unit-seed").ids)')" \
    'and the unit bodies it carries agree with those ids'
  assert_eq '1' "$(jget "$(sess units.json)" 'd.version')" 'units.json version is 1'
  assert_eq 'ui' "$(jget "$(sess units.json)" 'd.lens')" 'units.json carries the lens'
  assert_eq '3' "$(jget "$(sess units.json)" 'd.units.length')" 'all three units are stored'
  assert_eq 'screen.settings.billing' "$(jget "$(sess units.json)" 'd.units[0].id')" \
    'unit ids survive verbatim'
  assert_eq 'true' "$(jget "$(sess units.json)" 'd.units.every(u => u.addedInPass === 1)')" \
    'pass-1 units are stamped addedInPass 1 (SPEC 3.2)'
  assert_session_field 'd.phase' 'appraise' 'units advances the phase to appraise'

  p_grade "$FIXTURES/findings-full.json"; ok 'grade'
  assert_file "$(sess findings.json)" 'grade writes findings.json'
  assert_eq '1' "$(jget "$(sess findings.json)" 'd.version')" 'findings.json version is 1'
  assert_eq '12' "$(jget "$(sess findings.json)" 'd.findings.length')" 'all twelve findings are stored'
  assert_eq 'true' "$(jget "$(sess findings.json)" 'd.findings.every(f => /^f-[0-9]{4}$/.test(f.id))')" \
    'every finding has an engine-assigned f-NNNN id (SPEC 3.3)'
  assert_eq 'true' "$(jget "$(sess findings.json)" 'new Set(d.findings.map(f => f.id)).size === d.findings.length')" \
    'finding ids are unique'
  assert_eq 'true' "$(jget "$(sess findings.json)" 'd.findings.every(f => f.createdInPass === 1)')" \
    'pass-1 findings are stamped createdInPass 1'
  assert_eq 'true' "$(jget "$(sess findings.json)" 'd.findings.every(f => f.status === "open")')" \
    'seeded findings are open'
  assert_session_field 'd.phase' 'deliberate' 'grade advances the phase to deliberate'

  p_deliberate; ok 'deliberate'
  assert_file "$(pass_dir 1)/deliberation.json" 'deliberate writes passes/01/deliberation.json'
  assert_session_field 'd.phase' 'revise' 'deliberate advances the phase to revise'

  _seeded=$(ledger_lines)
  p_delta deltas-pass1.jsonl; ok 'delta'
  assert_file "$(pass_dir 1)/deltas.jsonl" 'delta writes passes/01/deltas.jsonl'
  assert_file "$(sess ledger.jsonl)" 'delta appends to ledger.jsonl'
  assert_eq "$((_seeded + 4))" "$(ledger_lines)" 'the ledger grows by exactly the four applied deltas'
  assert_eq "$(ledger_lines)" "$(jlines "$(pass_dir 1)/deltas.jsonl")" \
    'ledger.jsonl is the union of the per-pass delta files (SPEC 3.4)'
  for _voice in skeptic builder dreamer empath; do
    assert_eq '1' "$(jl "$(sess ledger.jsonl)" "d.filter(x => x.perspective === \"$_voice\").length")" \
      "the $_voice delta is on the ledger"
  done
  assert_eq 'true' "$(jl "$(sess ledger.jsonl)" 'd.every(x => x.pass === 1)')" \
    'ledger lines are stamped with the pass number'
  # SPEC 4 excludes source:"grade" deltas from the numerator of every ratio, so seeding
  # cannot inflate novelty or churn. Pin the tag rather than warning about the effect.
  assert_eq '12' "$(jl "$(sess ledger.jsonl)" 'd.filter(x => x.source === "grade").length')" \
    'every seeded finding is tagged source:"grade" so the ratios can exclude it (SPEC 4)'
  assert_eq '0' "$(jl "$(sess ledger.jsonl)" 'd.filter(x => x.source === "grade" && x.perspective).length')" \
    'seeding carries no perspective — it is the baseline, not an argument'
  assert_eq "$_seeded" \
    "$(jl "$(sess ledger.jsonl)" 'd.filter(x => x.op === "unit-seed" || x.source === "grade").length')" \
    'the pre-delta ledger is exactly the inventory seed plus the seeded findings (SPEC 3.4)'
  assert_eq 'true' "$(jl "$(sess ledger.jsonl)" 'd.every(x => typeof x.why === "string" && x.why.length > 0)')" \
    'every ledger line carries a why (SPEC 3.4)'
  assert_eq 'true' "$(jl "$(sess ledger.jsonl)" 'd.every(x => typeof x.at === "string" && x.at.length > 0)')" \
    'every ledger line carries a timestamp'
  assert_eq '13' "$(jget "$(sess findings.json)" 'd.findings.length')" \
    'the added finding joins the set and the deleted one stays in it'
  assert_session_field 'd.phase' 'judge' 'delta advances the phase to judge'

  p_judge; ok 'judge'
  assert_file "$(pass_dir 1)/metrics.json" 'judge writes passes/01/metrics.json'
  # Every signal is present as a key. Four of them are null on pass 1 (SPEC 4) — present
  # and null, never absent, so a reader can tell "no such signal here" from "no such field".
  for m in coverage novelty churn thrash surprise stall confidenceFloor voices; do
    _v=$(metric_json 1 "$m")
    if [ -n "$_v" ]; then _assert_pass; else _assert_fail "metrics.json is missing $m (SPEC 4)"; fi
  done
  assert_close "$(metric 1 coverage)" 1 0.0001 'coverage is 1.0 once every unit is graded'
  assert_eq '4' "$(metric 1 voices)" 'four perspectives spoke in pass 1'
  for m in novelty churn thrash surprise; do
    assert_eq 'null' "$(metric_json 1 "$m")" \
      "pass 1 has no $m — it measures change against a previous pass (SPEC 4)"
  done
  assert_session_field 'd.phase' 'decide' 'judge advances the phase to decide'

  p_decide continue 'Coverage is complete but a single pass is an opinion.'
  ok 'decide continue'
  assert_file "$(pass_dir 1)/verdict.json" 'decide writes passes/01/verdict.json'
  assert_session_field 'd.currentPass' '2' 'deciding continue opens the next pass'
  assert_session_field 'd.phase' 'predict' 'the next pass owes a prediction'
  assert_session_field 'd.status' 'open' 'the session stays open'
  assert_eq '1' "$(jget "$(sess session.json)" 'd.history.length')" 'the decision lands in history'
  assert_eq 'continue' "$(jget "$(sess session.json)" 'd.history[0].decision')" 'history records the decision'
  assert_eq '1' "$(jget "$(sess session.json)" 'd.history[0].pass')" 'history records the pass number'
}

t_happy_converges() {
  build_converged_session || return 0

  assert_eq '3' "$(pass_now)" 'the third pass is the one that converges'
  assert_eq 'stop' "$JUDGE_VERDICT" 'two quiet passes produce a stop verdict (SPEC 4.1 rule 6)'
  assert_eq 'converged' "$JUDGE_REASON" 'the stop reason is convergence, not budget'
  assert_close "$(metric 3 coverage)" 1 0.0001 'coverage held at 1.0'
  assert_lt "$(metric 3 novelty)" '0.05' 'novelty under 0.05 on the converging pass'
  assert_lt "$(metric 3 churn)" '0.10' 'churn under 0.10 on the converging pass'
  assert_close "$(metric 3 thrash)" 0 0.0001 'a session that never reverses itself reports thrash 0'

  p_decide stop 'Two quiet passes in a row; the answer stopped changing.'
  ok 'decide stop on a converged verdict'
  assert_ne 'open' "$(status_now)" 'a stopped session is no longer open'
  assert_eq 'converged' "$(status_now)" 'the session closes as converged (SPEC 3.1)'
  assert_eq '3' "$(jget "$(sess session.json)" 'd.history.length')" 'all three passes are in history'

  # SPEC 4.2: stopping on a pass that heard fewer than three voices warns, never blocks.
  if [ "$(metric 3 voices)" -lt 3 ] 2>/dev/null; then
    assert_imatch "$ALL" 'voice|perspective' \
      'stopping with fewer than three voices prints a warning (SPEC 4.2)'
  fi

  # The suite's own lint from SPEC 3.4: a change that only moves prose hides
  # re-grading from the thrash detector. The happy path should trip none.
  _prose=$(jl "$(sess ledger.jsonl)" \
    'd.filter(x => x.op === "change" && x.set && Object.keys(x.set).every(k => ["title","detail","recommendation","evidence"].indexOf(k) >= 0)).length')
  [ "${_prose:-0}" = "0" ] || warn "$_prose change delta(s) touched only prose in the happy path"
}

t_happy_report() {
  build_converged_session || return 0
  p_decide stop 'Two quiet passes in a row; the answer stopped changing.'
  ok 'decide stop'

  run_ponder report --session "$SLUG"
  ok 'report exits 0'
  assert_next 'report prints NEXT'
  assert_file "$(sess report.md)" 'report writes report.md into the session directory'
  _r=$(cat "$(sess report.md)")
  assert_contains "$_r" "$SUBJECT" 'the report names the subject'
  assert_contains "$_r" 'screen.settings.billing' 'the report names the units'
  assert_contains "$_r" 'Billing empty state is a bare string' 'the report carries the findings'

  run_ponder report --session "$SLUG" --out "$WORK/elsewhere.md"
  ok 'report --out exits 0'
  assert_file "$WORK/elsewhere.md" 'report --out writes where it is told'
}

# ---------------------------------------------------------------- coverage ---

# build_partial_session — three units, only the billing screen graded.
build_partial_session() {
  new_workdir coverage
  p_start --max-passes 6 --min-passes 2
  ok 'start'
  pass_one "$FIXTURES/findings-partial.json" deltas-one-edit.jsonl
}

t_coverage_blocked() {
  build_partial_session
  p_judge_json
  ok 'judge exits 0 even when it blocks'
  assert_eq 'blocked' "$JUDGE_VERDICT" 'partial coverage yields a blocked verdict (SPEC 4.1 rule 1)'
  assert_lt "$(metric 1 coverage)" '1' 'coverage is below 1.0'
  assert_contains "$OUT" 'screen.settings.profile' 'the blocked verdict names the ungraded profile unit'
  assert_contains "$OUT" 'screen.onboarding.welcome' 'the blocked verdict names the ungraded welcome unit'
}

t_coverage_gate() {
  build_partial_session
  p_judge; ok 'judge'

  run_ponder decide stop --session "$SLUG" --why 'I would like to stop here regardless of coverage.'
  assert_status 2 'decide stop under partial coverage is a state violation (SPEC 5, SPEC 8.1)'
  assert_contains "$ALL" 'screen.settings.profile' 'the refusal names the ungraded profile unit'
  assert_contains "$ALL" 'screen.onboarding.welcome' 'the refusal names the ungraded welcome unit'
  assert_next 'the refusal still prints NEXT'

  assert_eq 'open' "$(status_now)" 'the session is still open after a refused stop'
  assert_eq '1' "$(pass_now)" 'the refused stop did not advance the pass'
  assert_eq 'decide' "$(phase_now)" 'the session still owes a decision'
  assert_eq '0' "$(jget "$(sess session.json)" 'd.history.length')" 'no decision was recorded'

  # The gate is not a suggestion: continuing is still allowed.
  run_ponder decide continue --session "$SLUG" --why 'Two screens are still ungraded, so keep going.'
  ok 'decide continue is still permitted while blocked'
}

t_coverage_no_override_flag() {
  new_workdir noflag
  run_ponder decide --help
  ok 'ponder decide --help exits 0'
  _help=$ALL
  run_ponder --help
  _help="$_help
$ALL"
  assert_no_imatch "$_help" \
    '--(force|override|ignore[a-z-]*|no-coverage|skip[a-z-]*coverage|allow[a-z-]*|anyway|unsafe|bypass|no-verify|incomplete|partial)' \
    'no flag on decide overrides the coverage gate (SPEC 8.1)'
  assert_contains "$_help" '--why' 'decide --help documents --why'
}

t_coverage_invented_flags() {
  build_partial_session
  p_judge; ok 'judge'

  # A non-zero exit is not enough on its own. Today the engine rejects every one
  # of these as an unknown flag, so "exit != 0" would still hold with the gate
  # ripped out entirely — the assertion has to distinguish "there is no such
  # flag" from "the flag exists and the gate refused anyway", and it has to
  # re-prove the bare gate on every iteration so the test cannot pass while the
  # only thing standing between the agent and a dishonest stop is arg parsing.
  for flag in --force --override --ignore-coverage --no-coverage --allow-partial --yes; do
    run_ponder decide stop --session "$SLUG" --why 'Stopping despite the coverage gate.' "$flag"
    assert_status_not 0 "decide stop $flag cannot force a stop"
    assert_eq 'open' "$(status_now)" "the session survives decide stop $flag"
    assert_eq '0' "$(jget "$(sess session.json)" 'd.history.length')" \
      "decide stop $flag commits nothing to history"

    if printf '%s\n' "$ALL" | grep -Fq 'unknown flag'; then
      # The flag does not exist. Fine — but then prove the gate itself, here,
      # with a plain stop that the parser has no opinion about.
      run_ponder decide stop --session "$SLUG" --why 'Stopping despite the coverage gate.'
      assert_status 2 "with $flag rejected as unknown, a plain decide stop is still refused by the gate"
      assert_contains "$ALL" 'screen.settings.profile' \
        "the plain refusal alongside $flag names an ungraded unit (SPEC 4.1 rule 1)"
    else
      # The engine accepted the flag. Then the refusal must be the coverage
      # gate — exit 2, naming what was never graded — and not anything else.
      assert_status 2 "$flag is a recognised flag, so the refusal must be the coverage gate"
      assert_contains "$ALL" 'screen.settings.profile' "the refusal under $flag names an ungraded unit"
    fi
  done

  assert_eq 'open' "$(status_now)" 'the session is still open after every attempt'
  assert_eq '1' "$(pass_now)" 'no attempt advanced the pass'
}

t_coverage_gate_survives_tampering() {
  # SPEC 8.1 has no override, which means the gate cannot be satisfied by
  # anything the agent writes down — only by grading. The engine has to
  # recompute coverage from units.json and findings.json at decide time rather
  # than trust the judge's own metrics.json, or a hand-edited (or merely stale)
  # metrics file is the override the spec says does not exist.
  build_partial_session
  p_judge; ok 'judge'

  _m="$(pass_dir 1)/metrics.json"
  assert_file "$_m" 'judge wrote metrics.json'
  "$NODE" -e '
    const fs = require("fs");
    const p = process.argv[1];
    const m = JSON.parse(fs.readFileSync(p, "utf8"));
    (function walk(o) {
      for (const k of Object.keys(o)) {
        if (k.toLowerCase() === "coverage") o[k] = 1;
        else if (o[k] && typeof o[k] === "object") walk(o[k]);
      }
    })(m);
    fs.writeFileSync(p, JSON.stringify(m, null, 2));
  ' "$_m"
  assert_close "$(metric 1 coverage)" 1 0.0001 'the tampered metrics.json now claims full coverage'

  run_ponder decide stop --session "$SLUG" --why 'The metrics file says coverage is complete.'
  assert_status 2 'a metrics.json claiming coverage 1.0 does not unlock the gate (SPEC 8.1)'
  assert_contains "$ALL" 'screen.settings.profile' 'the refusal still names the truly ungraded unit'
  assert_eq 'open' "$(status_now)" 'the session is still open'
  assert_eq '0' "$(jget "$(sess session.json)" 'd.history.length')" 'nothing was committed'
}

t_coverage_forged_removal_kind() {
  # SPEC 3.5 *defines* an appraised removal as one whose unit carries at least one
  # finding — that is what buys it the right to shrink the coverage denominator.
  # But `removalKind` is read back off units.json, so the definition and the stored
  # field can be made to disagree. When they do, the definition has to win: a unit
  # with no findings is not appraised no matter what the file says, or writing six
  # characters into units.json is the override SPEC 8.1 says does not exist.
  build_partial_session

  _u="$(sess units.json)"
  assert_file "$_u" 'the session has a units.json'
  "$NODE" -e '
    const fs = require("fs");
    const p = process.argv[1];
    const d = JSON.parse(fs.readFileSync(p, "utf8"));
    const units = Array.isArray(d) ? d : d.units;
    let forged = 0;
    for (const u of units) {
      if (u.id === "screen.settings.profile" || u.id === "screen.onboarding.welcome") {
        u.removedInPass = 1;
        u.removalKind = "appraised";   // a lie: neither unit carries a finding
        forged++;
      }
    }
    if (forged !== 2) { console.error("fixture drift: forged " + forged); process.exit(3); }
    fs.writeFileSync(p, JSON.stringify(d, null, 2));
  ' "$_u"
  assert_status 0 'units.json now claims both ungraded units were appraised removals'

  # Outer defence (SPEC 3.6): the ledger never recorded a unit-delete for either unit, so
  # judge refuses to compute a signal off this inventory at all.
  run_ponder judge --session "$SLUG"
  assert_status 2 'judge refuses the forged inventory — it does not reconcile (SPEC 3.6)'
  assert_contains "$ALL" 'screen.settings.profile' 'the refusal names the forged profile unit'
  assert_contains "$ALL" 'screen.onboarding.welcome' 'the refusal names the forged welcome unit'
  assert_contains "$ALL" 'removalKind' 'and names the field that was forged'
  assert_next 'the refusal still prints NEXT'

  run_ponder decide stop --session "$SLUG" --why 'The inventory says these were appraised.'
  assert_status 2 'a forged removalKind does not unlock the gate (SPEC 3.5, SPEC 3.6, SPEC 8.1)'
  assert_eq 'open' "$(status_now)" 'the session is still open'
  assert_eq '0' "$(jget "$(sess session.json)" 'd.history.length')" 'nothing was committed'

  # Inner defence (SPEC 3.5), which reconciliation does not replace. `status` does not
  # reconcile — it is not a decision point — so it reads the forged file directly, and even
  # there an "appraised" removal on a unit with no findings does not shrink the denominator.
  run_ponder status --session "$SLUG" --json
  ok 'status reads the forged inventory without reconciling'
  assert_lt "$(jout 'd.coverage')" '1' \
    'a forged "appraised" does not shrink the denominator even unreconciled (SPEC 3.5)'
  assert_contains "$OUT" 'screen.settings.profile' 'and the unit is still counted as ungraded'
}

t_coverage_retraction_reopens_gate() {
  # The other way to fake a graded unit: grade everything, then delete the
  # findings you did not mean. A unit whose only judgments are retracted has no
  # live judgment, so coverage has to fall back and the gate has to close again.
  new_workdir retract
  p_start --max-passes 6 --min-passes 1
  ok 'start'
  p_predict 0.45 'Pass 1 grades every screen, then thinks better of two of them.'
  ok 'predict'
  p_units;  ok 'units'
  p_grade "$FIXTURES/findings-full.json"; ok 'grade'
  p_deliberate; ok 'deliberate'

  # Retract every finding that is not about billing.
  "$NODE" -e '
    const fs = require("fs");
    const d = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    const out = d.findings
      .filter((f) => f.unit !== "screen.settings.billing")
      .map((f) => JSON.stringify({
        op: "delete",
        target: f.id,
        perspective: "skeptic",
        why: "Asserted without evidence; retracting it rather than leaving it on the board.",
      }))
      .join("\n");
    fs.writeFileSync(process.argv[2], out + "\n");
  ' "$(sess findings.json)" "$WORK/retract.jsonl"

  run_ponder delta --session "$SLUG" --file "$WORK/retract.jsonl"
  ok 'the retractions apply'
  assert_eq '12' "$(jget "$(sess findings.json)" 'd.findings.length')" \
    'nothing left findings.json (SPEC 8.2)'

  p_judge_json; ok 'judge'
  assert_lt "$(metric 1 coverage)" '1' \
    'a unit whose only findings are retracted is not a graded unit'
  assert_eq 'blocked' "$JUDGE_VERDICT" 'so the verdict blocks again (SPEC 4.1 rule 1)'

  run_ponder decide stop --session "$SLUG" --why 'Only the findings I believed are left standing.'
  assert_status 2 'grade-then-retract is not a way through the gate (SPEC 8.1)'
  assert_eq 'open' "$(status_now)" 'the session is still open'
}

t_coverage_unit_add_reopens_gate() {
  new_workdir unitadd
  p_start --max-passes 6 --min-passes 2
  ok 'start'
  pass_one "$FIXTURES/findings-full.json" deltas-pass1.jsonl
  p_judge; ok 'pass 1 judge'
  p_decide continue 'Coverage is complete but one pass is an opinion.'
  ok 'pass 1 decide'

  later_pass deltas-unit-add.jsonl 0.20 'Pass 2 should surface the route pass 1 missed.' || return 0
  assert_eq '4' "$(jget "$(sess units.json)" 'd.units.length')" 'unit-add amends the inventory on a later pass'
  assert_eq '2' "$(jget "$(sess units.json)" 'd.units[3].addedInPass')" 'the amended unit is stamped with its pass'

  p_judge_json; ok 'pass 2 judge'
  assert_eq 'blocked' "$JUDGE_VERDICT" 'a newly enumerated unit drops coverage and blocks again'
  assert_contains "$OUT" 'screen.auth.reset' 'the blocked verdict names the newly added unit'

  # A blocked verdict is only advice until the gate acts on it. Prove the stop
  # is actually refused, or this test passes on an engine with no gate at all.
  run_ponder decide stop --session "$SLUG" --why 'The new route can wait for another day.'
  assert_status 2 'the reopened gate refuses a stop (SPEC 8.1)'
  assert_contains "$ALL" 'screen.auth.reset' 'the refusal names the unit the pass added and never graded'
  assert_eq 'open' "$(status_now)" 'the session is still open'
  assert_eq '1' "$(jget "$(sess session.json)" 'd.history.length')" 'only pass 1 is in history'
}

t_coverage_unit_delete_is_on_the_record() {
  # SPEC 3.5 lets a later pass amend the inventory with unit-delete. Every one of them has
  # to behave like any other delta: a why, a ledger line, no erasure, and a paper trail in
  # the report. A silent unit-delete would be SPEC 8.1 defeated by SPEC 5.1.
  #
  # This test covers the honest case — units that were appraised and are then dropped.
  # The never-graded case is t_coverage_delete_ungraded_does_not_open_gate.
  new_workdir unitdel
  p_start --max-passes 6 --min-passes 1
  ok 'start'
  p_predict 0.4 'Pass 1 grades all three screens, then narrows the subject.'
  ok 'predict'
  p_units;  ok 'units'
  p_grade "$FIXTURES/findings-full.json"; ok 'grade'
  p_deliberate; ok 'deliberate'

  cat > "$WORK/unit-delete.jsonl" <<'EOF'
{"op":"unit-delete","target":"screen.settings.profile","perspective":"skeptic","why":"Profile is owned by another team and is not part of this subject."}
{"op":"unit-delete","target":"screen.onboarding.welcome","perspective":"skeptic","why":"Onboarding was rewritten last week and is out of scope for this pondering."}
EOF
  cat > "$WORK/unit-delete-nowhy.jsonl" <<'EOF'
{"op":"unit-delete","target":"screen.settings.profile","perspective":"skeptic"}
EOF

  _before=$(ledger_lines)
  run_ponder delta --session "$SLUG" --file "$WORK/unit-delete-nowhy.jsonl"
  assert_status 1 'a unit-delete without a why is rejected like any other delta (SPEC 8.3)'
  assert_eq "$_before" "$(ledger_lines)" 'the rejected unit-delete wrote no ledger line'
  assert_eq '3' "$(jget "$(sess units.json)" 'd.units.length')" 'the inventory is untouched'

  run_ponder delta --session "$SLUG" --file "$WORK/unit-delete.jsonl"
  ok 'unit-delete applies with a why'
  assert_eq "$((_before + 2))" "$(ledger_lines)" 'each unit-delete appended exactly one ledger line'
  assert_eq '3' "$(jget "$(sess units.json)" 'd.units.length')" \
    'a dropped unit is never erased from units.json (SPEC 8.2)'
  assert_eq '2' "$(jget "$(sess units.json)" 'd.units.filter(u => u.removedInPass).length')" \
    'the dropped units are marked with the pass that dropped them'
  assert_eq '2' "$(jget "$(sess units.json)" 'd.units.filter(u => u.removalKind === "appraised").length')" \
    'a unit that carried findings is an appraised removal (SPEC 3.5)'
  assert_eq 'true' "$(jl "$(sess ledger.jsonl)" 'd.filter(x => x.op === "unit-delete").every(x => typeof x.why === "string" && x.why.length > 0)')" \
    'every unit-delete on the ledger carries its reason'
  assert_eq 'true' "$(jl "$(sess ledger.jsonl)" 'd.filter(x => x.op === "unit-delete").every(x => x.removal === "appraised")')" \
    'the ledger records which kind of removal each one was'

  p_judge_json; ok 'judge'
  assert_close "$(metric 1 coverage)" 1 0.0001 'dropping an appraised unit narrows the denominator honestly'
  assert_ne 'blocked' "$JUDGE_VERDICT" 'with nothing ungraded left, the gate is satisfied'

  run_ponder decide stop --session "$SLUG" --why 'Everything still in scope has been graded.'
  ok 'stopping is permitted once the inventory and the findings agree'

  run_ponder report --session "$SLUG"
  ok 'report exits 0'
  _r=$(cat "$(sess report.md)")
  assert_contains "$_r" 'screen.settings.profile' \
    'the report names the unit that was dropped, so narrowing the subject is never invisible'
  assert_contains "$_r" 'screen.onboarding.welcome' 'and the second one too'
  assert_imatch "$_r" 'removed from the inventory' 'under a heading that says what happened to them'
}

# build_escape_session — the reviewer's escape, set up but not yet attempted: three units,
# only billing graded, the other two never looked at. Leaves the session owing revise.
build_escape_session() {
  new_workdir escape
  p_start --max-passes 6 --min-passes 1
  ok 'start'
  p_predict 0.4 'Pass 1 grades billing and leaves the rest alone.'
  ok 'predict'
  p_units;  ok 'units'
  p_grade "$FIXTURES/findings-partial.json"; ok 'grade'
  p_deliberate; ok 'deliberate'
  assert_eq '1' "$(jget "$(sess findings.json)" 'new Set(d.findings.map(f => f.unit)).size')" \
    'exactly one of the three units carries a grade'
}

t_coverage_delete_ungraded_does_not_open_gate() {
  # The escape a reviewer proved: grade one unit of three, delete the two you never looked
  # at, and coverage reads 1.0. SPEC 3.5 closes it — a unit removed without ever being
  # appraised stays in the denominator, so the gate stays shut.
  build_escape_session

  cat > "$WORK/drop.jsonl" <<'EOF'
{"op":"unit-delete","target":"screen.settings.profile","perspective":"skeptic","why":"Not going to get to this one, so take it off the list."}
{"op":"unit-delete","target":"screen.onboarding.welcome","perspective":"skeptic","why":"Out of budget for onboarding this round."}
EOF
  run_ponder delta --session "$SLUG" --file "$WORK/drop.jsonl"
  ok 'deleting an ungraded unit is allowed — it just does not buy coverage'
  assert_eq '2' "$(jget "$(sess units.json)" 'd.units.filter(u => u.removalKind === "removed-ungraded").length')" \
    'a unit deleted without ever being graded is marked removed-ungraded (SPEC 3.5)'
  assert_imatch "$ALL" 'still counted|still counts' \
    'and the engine says so at the moment of the delete'

  p_judge_json; ok 'judge'
  assert_lt "$(metric 1 coverage)" '1' 'coverage did NOT reach 1.0 (SPEC 3.5, SPEC 8.1)'
  assert_close "$(metric 1 coverage)" 0.3333 0.001 'the denominator still holds all three units'
  assert_eq 'blocked' "$JUDGE_VERDICT" 'so the verdict is still blocked (SPEC 4.1 rule 1)'
  assert_eq '2' "$(jget "$(pass_dir 1)/metrics.json" 'd.removedUngraded.length')" \
    'metrics.json names the two deleted-ungraded units distinctly'
  assert_contains "$OUT" 'screen.settings.profile' 'the blocked verdict names them'
  assert_contains "$OUT" 'screen.onboarding.welcome' 'both of them'
  assert_imatch "$OUT" 'deleted (ungraded|without ever being graded)|cannot manufacture coverage' \
    'and says why a delete did not remove them from the count'

  run_ponder decide stop --session "$SLUG" --why 'The two screens I skipped are off the list now.'
  assert_status 2 'THE ESCAPE IS CLOSED: deleting ungraded units cannot force a stop (SPEC 8.1)'
  assert_contains "$ALL" 'screen.settings.profile' 'the refusal names the first deleted unit'
  assert_contains "$ALL" 'screen.onboarding.welcome' 'and the second'
  assert_imatch "$ALL" 'phantom' 'and points at the one honest way to drop a unit that is not real'
  assert_eq 'open' "$(status_now)" 'the session is still open'
  assert_eq '0' "$(jget "$(sess session.json)" 'd.history.length')" 'nothing was committed'

  # And the report keeps saying it, so the attempt is permanent.
  run_ponder report --session "$SLUG"
  ok 'report exits 0'
  _r=$(cat "$(sess report.md)")
  assert_imatch "$_r" 'deleted ungraded' 'the report marks them as deleted-ungraded'
  assert_contains "$_r" 'Not going to get to this one' 'with the why that was given at the time'
}

t_coverage_names_the_two_kinds_apart() {
  # SPEC 4.1 rule 1: the blocked verdict names every ungraded unit, and names the ones that
  # were deleted without ever being graded apart from the ones still sitting in the
  # inventory — with the reason they still count. One list of bare ids would tell an agent
  # that tried deleting its way out nothing about why it did not work.
  build_escape_session

  # Delete ONE of the two ungraded units, so the pass carries both kinds at once.
  cat > "$WORK/drop-one.jsonl" <<'EOF'
{"op":"unit-delete","target":"screen.settings.profile","perspective":"skeptic","why":"Taking profile off the list; nobody has looked at it."}
EOF
  run_ponder delta --session "$SLUG" --file "$WORK/drop-one.jsonl"
  ok 'the delete applies'

  p_judge_json; ok 'judge'
  assert_eq 'blocked' "$JUDGE_VERDICT" 'both kinds block'
  assert_eq '2' "$(jget "$(pass_dir 1)/metrics.json" 'd.ungraded.length')" 'two units are ungraded'
  assert_eq '1' "$(jget "$(pass_dir 1)/metrics.json" 'd.removedUngraded.length')" \
    'exactly one of them was deleted ungraded'
  assert_eq 'screen.settings.profile' "$(jget "$(pass_dir 1)/metrics.json" 'd.removedUngraded[0]')" \
    'and metrics.json says which'

  run_ponder decide stop --session "$SLUG" --why 'Profile is off the list and welcome can wait.'
  assert_status 2 'the stop is refused'
  # The deleted one is marked; the merely-ungraded one is not.
  assert_match "$ALL" 'screen\.settings\.profile.*deleted ungraded' \
    'the deleted-ungraded unit is marked as such in the refusal'
  assert_no_match "$ALL" 'screen\.onboarding\.welcome.*deleted ungraded' \
    'and the merely-ungraded one is not'
  assert_contains "$ALL" 'screen.onboarding.welcome' 'but it is still named'
  assert_imatch "$ALL" 'cannot manufacture coverage' 'and the refusal says why a delete bought nothing'
  assert_eq 'open' "$(status_now)" 'the session is still open'
}

t_coverage_phantom_live_path_is_rejected() {
  # SPEC 3.5: a phantom claim is checked, not trusted. Every unit in units-3.json has a
  # path that new_workdir actually creates, so every phantom claim here is false.
  build_escape_session

  cat > "$WORK/phantom-live.jsonl" <<'EOF'
{"op":"unit-delete","target":"screen.settings.profile","phantom":true,"perspective":"skeptic","why":"Pass 1 invented this screen; there is no profile route in this app."}
EOF
  _before=$(ledger_lines)
  run_ponder delta --session "$SLUG" --file "$WORK/phantom-live.jsonl"
  assert_status 1 'a phantom claim whose path exists is refused (SPEC 3.5)'
  assert_contains "$ALL" 'src/routes/settings/profile.tsx' 'the refusal names the file it found'
  assert_imatch "$ALL" 'phantom' 'and says the claim was the problem'
  assert_eq "$_before" "$(ledger_lines)" 'the refused phantom wrote no ledger line'
  assert_eq '0' "$(jget "$(sess units.json)" 'd.units.filter(u => u.removedInPass).length')" \
    'and left the inventory untouched'

  # A false phantom in a batch takes the whole batch with it (SPEC 3.4 atomicity).
  cat > "$WORK/phantom-mixed.jsonl" <<'EOF'
{"op":"unit-delete","target":"screen.onboarding.welcome","perspective":"skeptic","why":"Onboarding is out of scope for this pondering."}
{"op":"unit-delete","target":"screen.settings.profile","phantom":true,"perspective":"skeptic","why":"Pass 1 invented this screen; there is no profile route in this app."}
EOF
  run_ponder delta --session "$SLUG" --file "$WORK/phantom-mixed.jsonl"
  assert_status 1 'one false phantom rejects the whole batch'
  assert_eq "$_before" "$(ledger_lines)" 'nothing from that batch reached the ledger'
  assert_eq '0' "$(jget "$(sess units.json)" 'd.units.filter(u => u.removedInPass).length')" \
    'including the unit-delete that would have been fine on its own'

  # Belt and braces: with the false claim refused, the gate is still what it was. Satisfy
  # revise with an ordinary delta so the pass can be judged at all.
  p_delta deltas-one-edit.jsonl; ok 'an ordinary delta still applies'
  p_judge_json; ok 'judge'
  assert_eq 'blocked' "$JUDGE_VERDICT" 'the gate is unmoved by a claim that failed its check'
  assert_lt "$(metric 1 coverage)" '1' 'and coverage never moved'
  run_ponder decide stop --session "$SLUG" --why 'The screens I could not verify are gone now.'
  assert_status 2 'and a stop is still refused'
}

t_coverage_phantom_dead_path_is_accepted() {
  # The other half of SPEC 3.5: delete the file, and the same claim is verifiable and true.
  build_escape_session
  rm -f "$WORK/src/routes/settings/profile.tsx" "$WORK/src/routes/onboarding/welcome.tsx"

  cat > "$WORK/phantom-dead.jsonl" <<'EOF'
{"op":"unit-delete","target":"screen.settings.profile","phantom":true,"perspective":"skeptic","why":"Pass 1 read this route off a stale sitemap; the app has no profile screen."}
{"op":"unit-delete","target":"screen.onboarding.welcome","phantom":true,"perspective":"skeptic","why":"The onboarding welcome route was removed three releases ago and pass 1 enumerated it anyway."}
EOF
  run_ponder delta --session "$SLUG" --file "$WORK/phantom-dead.jsonl"
  ok 'a phantom claim whose path is missing is accepted (SPEC 3.5)'
  assert_eq '2' "$(jget "$(sess units.json)" 'd.units.filter(u => u.removalKind === "phantom").length')" \
    'both are recorded as phantom removals'
  assert_eq '2' "$(jget "$(sess units.json)" 'd.units.filter(u => u.phantomVerification === "verified-missing").length')" \
    'and both carry the verification result the engine actually computed'
  assert_eq '3' "$(jget "$(sess units.json)" 'd.units.length')" 'nothing was erased from units.json (SPEC 8.2)'
  assert_eq 'true' "$(jl "$(sess ledger.jsonl)" 'd.filter(x => x.op === "unit-delete").every(x => x.phantom === true && x.verification === "verified-missing")')" \
    'the ledger carries the claim and its verification, forever'

  p_judge_json; ok 'judge'
  assert_close "$(metric 1 coverage)" 1 0.0001 'a verified phantom leaves the coverage denominator'
  assert_ne 'blocked' "$JUDGE_VERDICT" 'so the gate opens — on a checked claim, not an assertion'
  assert_eq '2' "$(jget "$(pass_dir 1)/metrics.json" 'd.phantoms.length')" 'metrics.json records both phantoms'

  run_ponder decide stop --session "$SLUG" --why 'Only one screen was ever real, and it is graded.'
  ok 'and the stop is permitted'

  run_ponder report --session "$SLUG"
  ok 'report exits 0'
  _r=$(cat "$(sess report.md)")
  assert_contains "$_r" 'Phantom units' 'the report gives phantoms their own heading (SPEC 3.5)'
  assert_contains "$_r" 'screen.settings.profile' 'and names each one'
  assert_contains "$_r" 'verified-missing' 'with its verification result'
  assert_contains "$_r" 'stale sitemap' 'and the why that justified it'
}

t_coverage_phantom_without_path_is_unverified() {
  # A unit with no path cannot be checked. SPEC 3.5 accepts the claim and marks it
  # unverified, permanently and visibly — the claim is allowed, the silence is not.
  new_workdir phantomnopath
  p_start --max-passes 6 --min-passes 1
  ok 'start'
  cat > "$WORK/units-nopath.json" <<'EOF'
{ "version": 1, "lens": "ui", "units": [
  { "id": "screen.settings.billing", "label": "Settings > Billing", "path": "src/routes/settings/billing.tsx", "kind": "screen" },
  { "id": "screen.legacy.dashboard", "label": "Legacy > Dashboard", "kind": "screen" }
] }
EOF
  p_predict 0.4 'Pass 1 grades billing and questions whether the legacy dashboard exists.'
  ok 'predict'
  pcmd units --session "$SLUG" --file "$WORK/units-nopath.json"
  ok 'units without a path are accepted'
  p_grade "$FIXTURES/findings-partial.json"; ok 'grade'
  p_deliberate; ok 'deliberate'

  cat > "$WORK/phantom-nopath.jsonl" <<'EOF'
{"op":"unit-delete","target":"screen.legacy.dashboard","phantom":true,"perspective":"skeptic","why":"Nobody could find a legacy dashboard in the router, the build or the sitemap; pass 1 enumerated it from a stale design doc."}
EOF
  run_ponder delta --session "$SLUG" --file "$WORK/phantom-nopath.jsonl"
  ok 'a phantom claim on a unit with no path is accepted'
  assert_imatch "$ALL" 'unverified' 'and the engine says out loud that it could not check it'
  assert_eq 'unverified' "$(jget "$(sess units.json)" 'd.units.find(u => u.id === "screen.legacy.dashboard").phantomVerification')" \
    'the unit records verification unverified (SPEC 3.5)'
  assert_eq 'true' "$(jl "$(sess ledger.jsonl)" 'd.filter(x => x.op === "unit-delete").every(x => x.verification === "unverified")')" \
    'and so does the ledger line'

  p_judge_json; ok 'judge'
  assert_close "$(metric 1 coverage)" 1 0.0001 'an accepted phantom leaves the denominator even unverified'
  assert_ne 'blocked' "$JUDGE_VERDICT" 'so the gate opens'

  run_ponder decide stop --session "$SLUG" --why 'Billing is graded and the legacy dashboard does not exist.'
  ok 'the stop is permitted'
  run_ponder report --session "$SLUG"
  ok 'report exits 0'
  _r=$(cat "$(sess report.md)")
  assert_contains "$_r" 'Phantom units' 'the report carries the Phantom units heading'
  assert_contains "$_r" 'UNVERIFIED' 'and marks the unchecked claim distinctly (SPEC 3.5)'
  assert_contains "$_r" 'stale design doc' 'with its why'
  # The other side of the same pairing: here the unit really did have no path,
  # and the summary paragraph has to say that rather than blame a moved target.
  _intro=$(printf '%s\n' "$_r" | awk '/^### Phantom units/{f=1;next} f&&NF{print;exit}')
  assert_imatch "$_intro" 'no path' 'the Phantom units summary says the unit had no path'
  if printf '%s\n' "$_intro" | grep -Eqi 'path was edited|paths were edited|moved'; then
    fail "the Phantom units summary blames a moved path on a unit that never had one: $_intro"
  else
    _assert_pass
  fi
}

t_coverage_phantom_upgrade_and_limits() {
  # SPEC 3.5's edges: phantom is legal on unit-delete only, never on an appraised unit, and
  # a removed-ungraded unit may be re-deleted as a phantom — that upgrade is the one legal
  # repeat delete.
  build_escape_session

  cat > "$WORK/ph-on-add.jsonl" <<'EOF'
{"op":"unit-add","phantom":true,"perspective":"dreamer","why":"Trying to smuggle a phantom flag onto an unrelated op.","unit":{"id":"screen.auth.reset","label":"Auth > Reset","path":"src/routes/auth/reset.tsx","kind":"screen"}}
EOF
  run_ponder delta --session "$SLUG" --file "$WORK/ph-on-add.jsonl"
  assert_status 1 'phantom is legal on unit-delete only (SPEC 3.5)'

  cat > "$WORK/ph-on-graded.jsonl" <<'EOF'
{"op":"unit-delete","target":"screen.settings.billing","phantom":true,"perspective":"skeptic","why":"Claiming the one screen we actually graded does not exist."}
EOF
  run_ponder delta --session "$SLUG" --file "$WORK/ph-on-graded.jsonl"
  assert_status 1 'a unit that was appraised cannot also be one that never existed (SPEC 3.5)'
  assert_imatch "$ALL" 'appraised|finding' 'and the refusal says why'

  cat > "$WORK/ph-bad-type.jsonl" <<'EOF'
{"op":"unit-delete","target":"screen.settings.profile","phantom":"yes","perspective":"skeptic","why":"Phantom as a string rather than a boolean."}
EOF
  run_ponder delta --session "$SLUG" --file "$WORK/ph-bad-type.jsonl"
  assert_status 1 'phantom must be a boolean, not a truthy string'
  assert_eq '0' "$(jget "$(sess units.json)" 'd.units.filter(u => u.removedInPass).length')" \
    'none of those attempts touched the inventory'

  # The upgrade: drop it ungraded first, then come back with a checkable claim.
  cat > "$WORK/drop-one.jsonl" <<'EOF'
{"op":"unit-delete","target":"screen.settings.profile","perspective":"skeptic","why":"Taking profile off the list for now; nobody has looked at it."}
EOF
  run_ponder delta --session "$SLUG" --file "$WORK/drop-one.jsonl"
  ok 'the plain delete applies'
  assert_eq 'removed-ungraded' "$(jget "$(sess units.json)" 'd.units.find(u => u.id === "screen.settings.profile").removalKind')" \
    'it lands as removed-ungraded'

  p_judge; ok 'pass 1 judge'
  p_decide continue 'Profile still counts against coverage; check whether it is even real.'
  ok 'pass 1 decide'
  p_predict 0.1 'Pass 2 checks whether the profile route exists at all.'
  ok 'pass 2 predict'
  p_deliberate; ok 'pass 2 deliberate'

  cat > "$WORK/upgrade.jsonl" <<'EOF'
{"op":"unit-delete","target":"screen.settings.profile","phantom":true,"perspective":"skeptic","why":"Checked the router and the tree: there is no profile route, pass 1 enumerated it from a stale sitemap."}
EOF
  run_ponder delta --session "$SLUG" --file "$WORK/upgrade.jsonl"
  assert_status 1 'the upgrade is still checked — profile.tsx exists, so the claim is false'

  rm -f "$WORK/src/routes/settings/profile.tsx"

  # The upgrade is the ONE legal repeat delete. Doing it twice in one batch proves the
  # second one is refused, and SPEC 3.4 atomicity means the whole batch is rolled back.
  cat "$WORK/upgrade.jsonl" "$WORK/upgrade.jsonl" > "$WORK/upgrade-twice.jsonl"
  run_ponder delta --session "$SLUG" --file "$WORK/upgrade-twice.jsonl"
  assert_status 1 'a phantom cannot be deleted a second time (SPEC 3.5)'
  assert_imatch "$ALL" 'already removed' 'and the refusal says so'
  assert_eq 'removed-ungraded' "$(jget "$(sess units.json)" 'd.units.find(u => u.id === "screen.settings.profile").removalKind')" \
    'the rejected batch left the removal kind exactly as it was'

  run_ponder delta --session "$SLUG" --file "$WORK/upgrade.jsonl"
  ok 'with the file genuinely gone, a removed-ungraded unit may be re-deleted as a phantom'
  assert_eq 'phantom' "$(jget "$(sess units.json)" 'd.units.find(u => u.id === "screen.settings.profile").removalKind')" \
    'the removal kind is upgraded to phantom (SPEC 3.5)'
  assert_eq 'verified-missing' "$(jget "$(sess units.json)" 'd.units.find(u => u.id === "screen.settings.profile").phantomVerification')" \
    'and the engine checked it before accepting'
  assert_eq '2' "$(jl "$(sess ledger.jsonl)" 'd.filter(x => x.op === "unit-delete" && x.target === "screen.settings.profile").length')" \
    'and both deletes stay on the append-only ledger (SPEC 8.2)'

  p_judge_json; ok 'pass 2 judge'
  # Two units left in the denominator now: billing (graded) and welcome (still ungraded and
  # still real). The phantom cleared itself and nothing else.
  assert_close "$(metric 2 coverage)" 0.5 0.0001 'the verified phantom clears itself out of the denominator'
  assert_eq 'blocked' "$JUDGE_VERDICT" 'and buys nothing for the unit that is still ungraded'
  assert_eq '1' "$(jget "$(pass_dir 2)/metrics.json" 'd.phantoms.length')" 'exactly one phantom is on the record'
}

t_coverage_abort_is_not_a_stop() {
  # `ponder abort` is the only exit from a blocked session, and SPEC 5 calls it
  # "close a session unfinished". That is the honest door, so the test is that
  # walking through it is never mistaken for the other one: the status is
  # `aborted`, never `converged` or `stopped`, and the report keeps saying what
  # was never graded. An abort that reads as a stop is the coverage gate
  # defeated by paperwork.
  build_partial_session
  p_judge; ok 'judge'

  run_ponder abort --session "$SLUG"
  assert_status 1 'abort still needs a reason, even out of a blocked session'
  assert_eq 'open' "$(status_now)" 'the refused abort left the session open'

  run_ponder abort --session "$SLUG" --why 'Abandoning this: two screens were never graded and will not be.'
  ok 'abort exits 0 from a blocked session'
  assert_eq 'aborted' "$(status_now)" 'the session closes as aborted (SPEC 3.1)'
  assert_ne 'converged' "$(status_now)" 'an abandonment is never a convergence'
  assert_ne 'stopped' "$(status_now)" 'nor a stop'

  run_ponder report --session "$SLUG"
  ok 'report exits 0 on an aborted session'
  _r=$(cat "$(sess report.md)")
  assert_imatch "$_r" 'aborted' 'the report says the session was aborted'
  assert_contains "$_r" 'screen.settings.profile' 'and still names what was never graded'
  assert_contains "$_r" 'screen.onboarding.welcome' 'both of them'
  assert_no_imatch "$_r" 'status[^a-z]*(converged|stopped)' \
    'the report never labels an abandoned session as one that stopped honestly'
}

t_coverage_session_lookup_is_scoped() {
  # --session names a session, not a path. A slug that resolves outside
  # .ponder/ would let one project's gate be answered with another project's
  # findings — and `..` is the cheapest way to try it.
  new_workdir scoped
  p_start --max-passes 6 --min-passes 2; ok 'start'

  for _bad in '../ui-conformance' '../../etc' '/etc/passwd' './ui-conformance/..'; do
    run_ponder status --session "$_bad"
    assert_status 1 "--session $_bad is a user error, not a path to follow"
    assert_next "the $_bad refusal still prints NEXT"
  done

  run_ponder status --session "$SLUG"
  ok 'the real slug still resolves'
}

# ------------------------------------------------------------- project root --
#
# SPEC 3.1. A project is defined by project markers, not by where sessions
# happen to be kept. Everything in a session — every unit path, every evidence
# anchor, and every phantom claim checked against one (3.5) — resolves from the
# project root, so which directory that is, and what decided it, is contract.

# pr_walk_pass_one <nested-dir> <slug> <findings-fixture>
# Pass 1 up to the revise phase, driven from a directory of the test's choosing.
pr_walk_pass_one() {
  run_ponder_in "$1" predict --session "$2" --churn 0.4 --claim 'Pass 1 grades billing and questions the rest.'
  ok 'predict'
  run_ponder_in "$1" units --session "$2" --file "$1/units.json"
  ok 'units'
  run_ponder_in "$1" grade --session "$2" --file "$3"
  ok 'grade'
  run_ponder_in "$1" deliberate --session "$2" --file "$1/deliberation.json"
  ok 'deliberate'
}

t_project_root_marker_outranks_a_stray_ponder() {
  # `.git` and package.json define what the project IS. `.ponder` is only where its
  # sessions are kept, and it must never outrank the thing it belongs to: a directory
  # with a real project marker is the project root even when an unrelated ancestor
  # .ponder is sitting above it.
  markerless_workdir markerwins pr-marker
  mkdir -p "$WORK/.ponder"                       # the unrelated ancestor store
  printf '%s\n' '{ "name": "nested-app", "private": true }' > "$NESTED/package.json"
  _store="$NESTED/.ponder/$SLUG"

  run_ponder_in "$NESTED" start "$SUBJECT" --lens ui --slug "$SLUG" --min-passes 1
  ok 'start resolves a project root without being told one'
  _row=$(kv_row "$ALL" project)
  assert_contains "$_row" "$NESTED" 'start names the resolved project root'
  assert_contains "$_row" 'package.json' 'and names the marker that decided it'
  assert_not_contains "$_row" "$WORK/.ponder" 'the ancestor .ponder did not decide it'
  assert_contains "$(kv_row "$ALL" store)" "$_store" 'and the store went to the project it belongs to'
  assert_dir "$_store" 'the session lives under the project with the marker'
  assert_no_dir "$WORK/.ponder/$SLUG" 'and nothing was written into the stray ancestor store'
  assert_no_imatch "$ALL" 'warning.*project root' 'a root a marker established earns no warning'
  assert_eq 'marker' "$(jget "$_store/session.json" 'd.projectFrom.how')" \
    'session.json records how the root was decided (SPEC 3.1)'
  assert_eq 'package.json' "$(jget "$_store/session.json" 'd.projectFrom.marker')" 'and which marker'
  assert_eq "$NESTED" "$(jget "$_store/session.json" 'd.project')" 'and the root itself'

  # status reports the decision the session recorded, whatever directory it is run from.
  run_ponder_in "$NESTED/src/routes" status --session "$SLUG"
  ok 'status from a subdirectory'
  _row=$(kv_row "$ALL" project)
  assert_contains "$_row" "$NESTED" 'status names the project root'
  assert_contains "$_row" 'package.json' 'and how it was decided'
  assert_no_imatch "$ALL" 'warning.*project root' 'still no warning — a marker settled it'

  # doctor resolves live, from wherever it is standing, and says both halves.
  run_ponder_in "$NESTED/src/routes" doctor
  assert_status 0 'doctor is clean in a real project'
  _row=$(kv_row "$ALL" project)
  assert_contains "$_row" "$NESTED" 'doctor names the project root too'
  assert_contains "$_row" 'package.json' 'and the marker that decided it'
  assert_contains "$_row" "cwd is $NESTED/src/routes" 'and says the working directory is not the root'
  assert_no_imatch "$ALL" 'adopted' 'and has nothing to say about adoption'
}

t_project_root_marker_leaves_the_phantom_rule_alone() {
  # The false-positive guard. A session in a real project must behave exactly as it did
  # before roots were tracked at all: a live path sinks a phantom claim, a dead one is
  # verified missing, and the gate opens on the check rather than on the assertion.
  markerless_workdir markerphantom pr-phantom
  mkdir -p "$WORK/.ponder"
  printf '%s\n' '{ "name": "nested-app", "private": true }' > "$NESTED/package.json"
  _store="$NESTED/.ponder/$SLUG"

  run_ponder_in "$NESTED" start "$SUBJECT" --lens ui --slug "$SLUG" --min-passes 1
  ok 'start'
  pr_walk_pass_one "$NESTED" "$SLUG" "$FIXTURES/findings-partial.json"

  cat > "$NESTED/phantom-live.jsonl" <<'EOF'
{"op":"unit-delete","target":"screen.settings.profile","phantom":true,"perspective":"skeptic","why":"Pass 1 invented this screen; there is no profile route in this app."}
EOF
  run_ponder_in "$NESTED" delta --session "$SLUG" --file "$NESTED/phantom-live.jsonl"
  assert_status 1 'a phantom claim whose path exists is still refused (SPEC 3.5)'
  assert_contains "$ALL" 'src/routes/settings/profile.tsx' 'and still names the file it found'
  assert_no_imatch "$ALL" 'guessed' 'the refusal is about the file, not about the root'

  rm -f "$NESTED/src/routes/settings/profile.tsx" "$NESTED/src/routes/onboarding/welcome.tsx"
  cat > "$NESTED/phantom-dead.jsonl" <<'EOF'
{"op":"unit-delete","target":"screen.settings.profile","phantom":true,"perspective":"skeptic","why":"Pass 1 read this route off a stale sitemap; the app has no profile screen."}
{"op":"unit-delete","target":"screen.onboarding.welcome","phantom":true,"perspective":"skeptic","why":"The onboarding welcome route was removed three releases ago and pass 1 enumerated it anyway."}
EOF
  run_ponder_in "$NESTED" delta --session "$SLUG" --file "$NESTED/phantom-dead.jsonl"
  ok 'and a phantom claim whose path is missing is still accepted'
  assert_eq '2' "$(jget "$_store/units.json" 'd.units.filter(u => u.phantomVerification === "verified-missing").length')" \
    'both are verified-missing — a marker root certifies exactly as it always did'
  run_ponder_in "$NESTED" judge --session "$SLUG"
  ok 'judge'
  assert_no_imatch "$ALL" 'blocked' 'the gate opens on the checked claim'
  run_ponder_in "$NESTED" decide stop --session "$SLUG" --why 'Only billing was ever real, and it is graded.'
  assert_status 0 'and the honest stop is permitted'
}

t_project_root_adopted_ponder_refuses_a_phantom() {
  # The headline. A directory with no project markers of its own, sitting under an
  # unrelated ancestor .ponder, adopts that ancestor as its project root — there is
  # nothing better available. What must not happen is that the adoption is silent, or
  # that a path which fails to resolve under a guessed root is read as proof that a
  # screen never existed. That reading is what turned the coverage gate into a rubber
  # stamp: the file was there all along, one directory over.
  markerless_workdir gateadopt pr-adopted
  mkdir -p "$WORK/.ponder"
  _store="$WORK/.ponder/$SLUG"

  run_ponder_in "$NESTED" start "$SUBJECT" --lens ui --slug "$SLUG" --min-passes 1
  ok 'start'
  _row=$(kv_row "$ALL" project)
  assert_contains "$_row" "$WORK" 'start says which root it adopted'
  assert_contains "$_row" "cwd is $NESTED" 'and that the working directory is not it'
  assert_imatch "$_row" 'adopted|no project marker' 'and that no project marker decided it'
  assert_imatch "$ALL" 'warning' 'the weak case warns'
  assert_contains "$ALL" '--project' 'and names the fix'
  assert_eq 'ponder' "$(jget "$_store/session.json" 'd.projectFrom.how')" \
    'session.json records that the root was adopted from a .ponder (SPEC 3.1)'

  pr_walk_pass_one "$NESTED" "$SLUG" "$FIXTURES/findings-partial.json"
  assert_lt "$(jget "$_store/units.json" 'd.units.filter(u => u.removedInPass).length')" '1' \
    'nothing has left the inventory yet'

  # Every unit path here exists — relative to the directory the command is run in. Under
  # the adopted root none of them resolve, and this is the batch that used to walk
  # through the gate on that: a path edit, then a phantom claim on a screen sitting in
  # the tree the whole time.
  cat > "$NESTED/phantom-guessed.jsonl" <<'EOF'
{"op":"unit-edit","target":"screen.settings.profile","perspective":"builder","why":"The route file moved when the settings folder was reorganised; pointing the unit at where it lives now.","set":{"path":"src/routes/settings/profile-v2.tsx"}}
{"op":"unit-delete","target":"screen.settings.profile","phantom":true,"perspective":"skeptic","why":"There is no profile screen in this app; pass 1 enumerated it off a stale sitemap."}
EOF
  _before=$(jlines "$_store/ledger.jsonl")
  run_ponder_in "$NESTED" delta --session "$SLUG" --file "$NESTED/phantom-guessed.jsonl"
  assert_status 1 'a phantom claim under a guessed project root is refused'
  assert_contains "$ALL" "$WORK" 'the refusal names the root it was resolving against'
  assert_imatch "$ALL" 'guessed|not established' 'and says the root was never established'
  assert_contains "$ALL" '--project' 'and names the fix'
  assert_eq "$_before" "$(jlines "$_store/ledger.jsonl")" 'the refused batch wrote no ledger line'
  assert_eq '0' "$(jget "$_store/units.json" 'd.units.filter(u => u.removedInPass).length')" \
    'and the path edit that carried it was refused with it (SPEC 3.4 atomicity)'

  # The gate is exactly where it was: two screens ungraded, and stop is not available.
  run_ponder_in "$NESTED" delta --session "$SLUG" --file "$(delta_file deltas-one-edit.jsonl)"
  ok 'an ordinary delta still applies'
  run_ponder_in "$NESTED" judge --session "$SLUG"
  ok 'judge'
  assert_imatch "$ALL" 'blocked' 'coverage is still short and the verdict says so'
  run_ponder_in "$NESTED" decide stop --session "$SLUG" --why 'The screens I could not find are gone now.'
  assert_status 2 'and stop is refused — the gate never opened'

  # status and doctor both say the same thing, for whoever inherits this.
  run_ponder_in "$NESTED" status --session "$SLUG"
  ok 'status'
  assert_contains "$(kv_row "$ALL" project)" "$WORK" 'status names the adopted root'
  assert_imatch "$ALL" 'warning' 'and warns about it too'
  run_ponder_in "$NESTED" doctor
  assert_status 1 'doctor treats an adopted ancestor .ponder as a problem'
  assert_imatch "$ALL" 'adopted' 'and says so in as many words'
  assert_contains "$ALL" '--project' 'with the fix beside it'

  # And the refusal is not a blanket one: pointed at the real root, the same claim is
  # refused for the honest reason — the screen is right there.
  run_ponder_in "$NESTED" start "$SUBJECT" --lens ui --slug pr-adopted-fixed --project "$NESTED" --min-passes 1
  ok 'a session started with --project'
  assert_eq 'explicit' "$(jget "$NESTED/.ponder/pr-adopted-fixed/session.json" 'd.projectFrom.how')" \
    'records that it was told, not that it guessed'
  pr_walk_pass_one "$NESTED" pr-adopted-fixed "$FIXTURES/findings-partial.json"
  run_ponder_in "$NESTED" delta --session pr-adopted-fixed --file "$NESTED/phantom-guessed.jsonl"
  assert_status 1 'the same claim is still refused under the real root'
  assert_contains "$ALL" 'src/routes/settings/profile.tsx' 'but now because the screen exists'
  assert_no_imatch "$ALL" 'guessed' 'a root that was given is never a guess'
}

t_project_root_cwd_fallback_is_a_guess() {
  # No project marker and no .ponder anywhere above: the working directory is the only
  # answer left, and it is still a guess. A path that does not resolve under it says
  # nothing about whether a screen exists.
  markerless_workdir cwdfallback pr-cwd
  _stray=$(nearest_ancestor_ponder "$WORK")
  _store="$NESTED/.ponder/$SLUG"

  run_ponder_in "$NESTED" start "$SUBJECT" --lens ui --slug "$SLUG" --min-passes 1
  ok 'start'
  if [ -n "$_stray" ]; then
    # This machine has a session store above the scratch directory (a stray /tmp/.ponder
    # from real work will do it). The engine is right to adopt it and the guess is the
    # same guess, but the exact wording under test here is the other one.
    warn "a .ponder at $_stray sits above the scratch tree; asserting the adopted wording instead of the cwd fallback"
    assert_eq 'ponder' "$(jget "$(nearest_ancestor_ponder "$WORK")/.ponder/$SLUG/session.json" 'd.projectFrom.how')" \
      'the root was adopted rather than fallen back to'
    return 0
  fi
  assert_eq "$NESTED" "$(jget "$_store/session.json" 'd.project')" 'the working directory is the root'
  assert_eq 'cwd' "$(jget "$_store/session.json" 'd.projectFrom.how')" 'recorded as the fallback it is (SPEC 3.1)'
  assert_imatch "$(kv_row "$ALL" project)" 'no project marker' 'and start says there was no marker to go on'
  assert_imatch "$ALL" 'warning' 'a fallback root warns'
  assert_contains "$ALL" '--project' 'and names the fix'

  pr_walk_pass_one "$NESTED" "$SLUG" "$FIXTURES/findings-partial.json"
  # The paths do resolve here — the fallback happens to be right. That is exactly why it
  # cannot be trusted: right and unverifiable look identical from inside.
  rm -f "$NESTED/src/routes/settings/profile.tsx"
  cat > "$NESTED/phantom-cwd.jsonl" <<'EOF'
{"op":"unit-delete","target":"screen.settings.profile","phantom":true,"perspective":"skeptic","why":"There is no profile screen in this app; pass 1 enumerated it off a stale sitemap."}
EOF
  run_ponder_in "$NESTED" delta --session "$SLUG" --file "$NESTED/phantom-cwd.jsonl"
  assert_status 1 'a phantom claim under a fallback root is refused too'
  assert_imatch "$ALL" 'guessed|not established' 'and says why'
  assert_eq '0' "$(jget "$_store/units.json" 'd.units.filter(u => u.removalKind === "phantom").length')" \
    'nothing left the coverage denominator on a guess'
}

t_project_root_provenance_survives_an_old_session() {
  # SPEC 3.1's new field cannot break a session written before it existed. An older
  # session is read, reported and reconciled exactly as it was — and where its recorded
  # root holds a project marker, its phantom claims are checked exactly as they were.
  new_workdir oldsession pr-legacy
  p_start --max-passes 6 --min-passes 1
  ok 'start'
  pass_one "$FIXTURES/findings-partial.json" deltas-one-edit.jsonl

  forge "$(sess session.json)" 'delete d.projectFrom;'
  assert_eq 'undefined' "$(jget "$(sess session.json)" 'typeof d.projectFrom')" 'the field is gone, as it would be in an older session'

  run_ponder status --session "$SLUG"
  ok 'status reads a session that predates the field'
  assert_contains "$(kv_row "$ALL" project)" "$WORK" 'and still says which root the session uses'
  assert_imatch "$(kv_row "$ALL" project)" 'inferred|package.json|\.git' 'saying where that came from'
  assert_no_imatch "$ALL" 'warning.*project root' 'a legacy session in a real project is not nagged'

  run_ponder verify --session "$SLUG"
  ok 'and it still reconciles — the ledger never knew about this field (SPEC 3.6)'

  rm -f "$WORK/src/routes/settings/profile.tsx"
  cat > "$WORK/phantom-legacy.jsonl" <<'EOF'
{"op":"unit-delete","target":"screen.settings.profile","phantom":true,"perspective":"skeptic","why":"Pass 1 read this route off a stale sitemap; the app has no profile screen."}
EOF
  run_ponder delta --session "$SLUG" --file "$WORK/phantom-legacy.jsonl"
  assert_status 2 'the session owes judge, not another delta'
  run_ponder judge --session "$SLUG"; ok 'judge'
  run_ponder decide continue --session "$SLUG" --why 'Two screens are still ungraded and one of them may not exist.'
  ok 'decide continue'
  run_ponder predict --session "$SLUG" --churn 0.3 --claim 'Pass 2 settles whether the profile screen exists.'
  ok 'pass 2 predict'
  run_ponder deliberate --session "$SLUG" --file "$WORK/deliberation.json"; ok 'pass 2 deliberate'
  run_ponder delta --session "$SLUG" --file "$WORK/phantom-legacy.jsonl"
  ok 'a phantom claim on a legacy session with a real project root is checked, not refused'
  assert_eq 'verified-missing' "$(jget "$(sess units.json)" 'd.units.find(u => u.id === "screen.settings.profile").phantomVerification')" \
    'and certified exactly as it always was'
}

# ------------------------------------------------------------------- phase ---

# expect_out_of_order <expected-phase> <label> <command...>
expect_out_of_order() {
  _eo_phase=$1; _eo_label=$2; shift 2
  run_ponder "$@" --session "$SLUG"
  assert_status 2 "$_eo_label exits 2"
  assert_contains "$ALL" "$_eo_phase" "$_eo_label names the expected phase [$_eo_phase]"
}

t_phase_state_machine() {
  new_workdir phase
  p_start --max-passes 6 --min-passes 2
  ok 'start'

  # owed: predict
  expect_out_of_order predict 'units before predict'      units --file "$WORK/units.json"
  expect_out_of_order predict 'grade before predict'      grade --file "$FIXTURES/findings-full.json"
  expect_out_of_order predict 'deliberate before predict' deliberate --file "$WORK/deliberation.json"
  expect_out_of_order predict 'delta before predict'      delta --file "$FIXTURES/deltas-one-edit.jsonl"
  expect_out_of_order predict 'judge before predict'      judge
  expect_out_of_order predict 'decide before predict'     decide continue --why 'Nothing has happened yet.'

  p_predict 0.4 'Pass 1 inventories the screens.'; ok 'predict'

  # owed: survey
  expect_out_of_order survey 'predict twice'          predict --churn 0.2 --claim 'Again.'
  expect_out_of_order survey 'grade before units'     grade --file "$FIXTURES/findings-full.json"
  expect_out_of_order survey 'judge before units'     judge

  p_units; ok 'units'

  # owed: appraise
  expect_out_of_order appraise 'units twice'               units --file "$WORK/units.json"
  expect_out_of_order appraise 'deliberate before grade'   deliberate --file "$WORK/deliberation.json"
  expect_out_of_order appraise 'judge before grade'        judge

  p_grade "$FIXTURES/findings-full.json"; ok 'grade'

  # owed: deliberate
  expect_out_of_order deliberate 'grade twice'             grade --file "$FIXTURES/findings-full.json"
  expect_out_of_order deliberate 'judge before deliberate' judge

  p_deliberate; ok 'deliberate'

  # owed: revise
  expect_out_of_order revise 'judge before revise'  judge
  expect_out_of_order revise 'decide before revise' decide continue --why 'Skipping the revision step.'

  p_delta deltas-pass1.jsonl; ok 'delta'

  # owed: judge
  expect_out_of_order judge 'decide before judge' decide continue --why 'Deciding without any advice.'
  expect_out_of_order judge 'delta twice'         delta --file "$FIXTURES/deltas-one-edit.jsonl"

  p_judge; ok 'judge'

  # owed: decide
  expect_out_of_order decide 'predict before decide' predict --churn 0.1 --claim 'Next pass already.'
  expect_out_of_order decide 'delta before decide'   delta --file "$FIXTURES/deltas-one-edit.jsonl"

  run_ponder decide sideways --session "$SLUG" --why 'Not one of the three decisions.'
  assert_status 1 'an unknown decision verb is a user error, not a state violation'
  run_ponder decide continue --session "$SLUG"
  assert_status 1 'decide without a why is a user error (SPEC 5)'

  # status is a reader and works in every phase
  run_ponder status --session "$SLUG"
  ok 'status works mid-pass'
  assert_contains "$ALL" 'decide' 'status names the phase the agent owes'
}

t_phase_units_is_pass_one_only() {
  new_workdir unitsonce
  p_start --max-passes 6 --min-passes 2
  ok 'start'
  pass_one "$FIXTURES/findings-full.json" deltas-pass1.jsonl
  p_judge; ok 'judge'
  p_decide continue 'Moving into a second pass to test the survey rule.'
  ok 'decide continue'

  run_ponder units --session "$SLUG" --file "$WORK/units.json"
  assert_status 2 'units on a later pass is a state violation (SPEC 5 CLI contract)'
  assert_eq '3' "$(jget "$(sess units.json)" 'd.units.length')" 'the inventory is untouched'
}

t_phase_survey_skipped_later() {
  new_workdir skipsurvey
  p_start --max-passes 6 --min-passes 2
  ok 'start'
  pass_one "$FIXTURES/findings-full.json" deltas-pass1.jsonl
  p_judge; ok 'judge'
  p_decide continue 'Moving into a second pass to test the survey rule.'
  ok 'decide continue'
  p_predict 0.2 'Pass 2 sharpens what pass 1 rushed.'
  ok 'pass 2 predict'
  assert_ne 'survey' "$(phase_now)" 'survey is skipped automatically after pass 1 (SPEC 5.1)'
}

t_phase_deliberate_skip() {
  new_workdir delibskip
  p_start --max-passes 6 --min-passes 2
  ok 'start'
  p_predict 0.4 'Pass 1 inventories the screens.'; ok 'predict'
  p_units; ok 'units'
  p_grade "$FIXTURES/findings-full.json"; ok 'grade'

  run_ponder deliberate --session "$SLUG" --skip
  assert_status 1 'deliberate --skip without a why is a user error (SPEC 5.1)'

  run_ponder deliberate --session "$SLUG" --skip --why 'No new evidence arrived since the last argument.'
  ok 'deliberate --skip --why exits 0'
  assert_eq 'revise' "$(phase_now)" 'a skipped deliberation still advances the phase'

  # The suite runs with PONDER_OCA=off, so the bridge wrote nothing. This is the
  # one line in the engine that tells an agent its reasoning was logged, so under
  # `off` it must not claim a metacognitive observation it never wrote (SPEC 6).
  assert_no_imatch "$ALL" 'recorded metacognitive observation' \
    'the skip does not claim an observation the bridge never wrote'
  assert_imatch "$ALL" 'PONDER_OCA=off' 'it says why nothing was recorded'
  assert_imatch "$ALL" 'deliberation.json' 'and what it did record'

  run_ponder deliberate --session "$SLUG" --skip --why 'x' --json
  assert_status 2 'a second deliberation on one pass is refused'

  # The same claim in --json, where an agent reads it as a field.
  new_workdir delibskipjson
  p_start --max-passes 6 --min-passes 2; ok 'start'
  p_predict 0.4 'Pass 1 inventories the screens.'; ok 'predict'
  p_units; ok 'units'
  p_grade "$FIXTURES/findings-full.json"; ok 'grade'
  run_ponder deliberate --session "$SLUG" --skip --why 'No new evidence arrived since the last argument.' --json
  ok 'deliberate --skip --json exits 0'
  assert_json_stdout 'deliberate --skip --json'
  assert_eq 'true' "$(jout 'String(d.skipped)')" 'the payload marks the pass skipped'
  assert_eq 'false' "$(jout 'String(d.observationRecorded)')" \
    'and says plainly that no observation was recorded under PONDER_OCA=off'

  # And the other direction: with a reachable OCA the claim is true, so it is made.
  new_workdir delibskipon
  fake_psql "printf '%s\\n' '{\"server\":\"18.0\",\"database\":\"oneiro\",\"tables\":[\"cognitive_events\",\"deliberations\",\"episodic_memory\",\"hypotheses\",\"metacognitive_observations\"],\"observationId\":1}'; exit 0"
  PONDER_OCA=on
  export PONDER_OCA
  p_start --max-passes 6 --min-passes 2; ok 'start under PONDER_OCA=on'
  p_predict 0.4 'Pass 1 inventories the screens.'; ok 'predict'
  p_units; ok 'units'
  p_grade "$FIXTURES/findings-full.json"; ok 'grade'
  run_ponder deliberate --session "$SLUG" --skip --why 'No new evidence arrived since the last argument.' --json
  ok 'deliberate --skip --json exits 0 against a reachable OCA'
  assert_eq 'true' "$(jout 'String(d.observationRecorded)')" \
    'a row that was actually written is reported as written'
  PONDER_OCA=off
  export PONDER_OCA
}

# ------------------------------------------------------------------- delta ---

# delta_session <findings-fixture> — a session parked at the revise phase.
delta_session() {
  new_workdir delta
  p_start --max-passes 6 --min-passes 2
  ok 'start'
  p_predict 0.4 'Pass 1 inventories the screens.'; ok 'predict'
  p_units; ok 'units'
  p_grade "$1"; ok 'grade'
  p_deliberate; ok 'deliberate'
}

t_delta_add_ids() {
  delta_session "$FIXTURES/findings-tiny.json"
  _id1=$(finding_id 1); _id2=$(finding_id 2); _id3=$(finding_id 3)

  cat "$(delta_file deltas-delete-only.jsonl)" "$(delta_file deltas-add-only.jsonl)" \
    > "$WORK/combined-1.jsonl"
  run_ponder delta --session "$SLUG" --file "$WORK/combined-1.jsonl"
  ok 'delete plus add in one pass'

  assert_eq '4' "$(jget "$(sess findings.json)" 'd.findings.length')" 'the set grew by exactly one'
  _new=$(jget "$(sess findings.json)" 'd.findings[3].id')
  assert_match "$_new" '^f-[0-9]{4}$' 'the added finding gets an f-NNNN id (SPEC 3.3)'
  assert_ne "$_id2" "$_new" 'the id of the retracted finding is not handed to the new one'
  assert_ne "$_id1" "$_new" 'the new id is not one already in use'
  assert_ne "$_id3" "$_new" 'the new id is not one already in use'
  assert_eq '1' "$(jget "$(sess findings.json)" 'd.findings[3].createdInPass')" \
    'the added finding is stamped with the pass that added it'

  p_judge; ok 'judge'
  p_decide continue 'Adding a second pass so a second id is assigned.'
  ok 'decide continue'
  later_pass deltas-add-only.jsonl 0.2 'Pass 2 adds one more finding.' || return 0

  assert_eq '5' "$(jget "$(sess findings.json)" 'd.findings.length')" 'the second add lands too'
  _new2=$(jget "$(sess findings.json)" 'd.findings[4].id')
  assert_ne "$_new" "$_new2" 'the second add gets a different id again'
  assert_eq 'true' "$(jget "$(sess findings.json)" 'new Set(d.findings.map(f => f.id)).size === d.findings.length')" \
    'no id is ever reused (SPEC 3.3)'
  assert_eq 'true' "$(jget "$(sess findings.json)" 'd.findings.every(f => /^f-[0-9]{4}$/.test(f.id))')" \
    'every id keeps the f-NNNN format'
}

t_delta_delete_retracts() {
  delta_session "$FIXTURES/findings-tiny.json"
  _id2=$(finding_id 2)
  _before=$(jget "$(sess findings.json)" 'd.findings.length')

  p_delta deltas-delete-only.jsonl; ok 'delete delta'

  assert_eq "$_before" "$(jget "$(sess findings.json)" 'd.findings.length')" \
    'delete never removes an object from findings.json (SPEC 3.4, SPEC 8.2)'
  assert_eq 'retracted' "$(jget "$(sess findings.json)" "(d.findings.find(f => f.id === \"$_id2\") || {}).status")" \
    'delete sets status retracted'
  assert_eq 'Avatar upload control is unreachable by keyboard' \
    "$(jget "$(sess findings.json)" "(d.findings.find(f => f.id === \"$_id2\") || {}).title")" \
    'the retracted finding keeps its content so a later pass can reverse it'
  assert_eq 'true' "$(jl "$(sess ledger.jsonl)" 'd.some(x => x.op === "delete")')" \
    'the delete is on the ledger'
}

t_delta_partial_sets() {
  delta_session "$FIXTURES/findings-tiny.json"
  _id1=$(finding_id 1)
  _id3=$(finding_id 3)

  p_delta deltas-edit-and-change.jsonl; ok 'edit and change deltas'

  _f1="d.findings.find(f => f.id === \"$_id1\")"
  assert_eq 'Billing empty state gives a new account nothing to do' \
    "$(jget "$(sess findings.json)" "$_f1.title")" 'edit replaces the title'
  assert_eq '2' "$(jget "$(sess findings.json)" "$_f1.evidence.length")" 'edit replaces the evidence list'
  assert_eq 'should' "$(jget "$(sess findings.json)" "$_f1.severity")" \
    'edit leaves untouched fields alone (partial set)'
  assert_eq '2' "$(jget "$(sess findings.json)" "$_f1.score")" 'edit leaves the score alone'
  assert_eq 'empty-states' "$(jget "$(sess findings.json)" "$_f1.dimension")" 'edit leaves the dimension alone'
  assert_eq '1' "$(jget "$(sess findings.json)" "$_f1.lastTouchedPass")" 'edit stamps lastTouchedPass'

  _f3="d.findings.find(f => f.id === \"$_id3\")"
  assert_eq 'must'     "$(jget "$(sess findings.json)" "$_f3.severity")"   'change applies severity'
  assert_eq '1'        "$(jget "$(sess findings.json)" "$_f3.score")"      'change applies score'
  assert_eq '0.9'      "$(jget "$(sess findings.json)" "$_f3.confidence")" 'change applies confidence'
  assert_eq 'l'        "$(jget "$(sess findings.json)" "$_f3.effort")"     'change applies effort'
  assert_eq 'deferred' "$(jget "$(sess findings.json)" "$_f3.status")"     'change applies status'
  assert_eq 'Welcome hero overflows below 380px' \
    "$(jget "$(sess findings.json)" "$_f3.title")" 'change leaves prose alone (partial set)'
  assert_eq 'true' "$(jget "$(sess findings.json)" "Array.isArray($_f3.history) && $_f3.history.length > 0")" \
    'the change appends to the finding history (SPEC 3.3)'
  assert_eq 'true' "$(jget "$(sess findings.json)" "$_f3.history.some(h => h.op === \"change\" && h.pass === 1)")" \
    'the history entry records the op and the pass'
}

t_delta_requires_why() {
  delta_session "$FIXTURES/findings-tiny.json"
  _before=$(jget "$(sess findings.json)" 'd.findings[0].recommendation')

  _ledger_before=$(ledger_lines)

  run_ponder delta --session "$SLUG" --file "$(delta_file deltas-empty-why.jsonl)"
  assert_status 1 'a delta with an empty why is rejected (SPEC 3.4, SPEC 8.3)'
  assert_eq "$_before" "$(jget "$(sess findings.json)" 'd.findings[0].recommendation')" \
    'the rejected delta changed nothing'
  assert_eq "$_ledger_before" "$(ledger_lines)" 'a rejected delta writes no ledger line'

  run_ponder delta --session "$SLUG" --file "$(delta_file deltas-missing-why.jsonl)"
  assert_status 1 'a delta with no why field at all is rejected'
  assert_eq "$_before" "$(jget "$(sess findings.json)" 'd.findings[0].recommendation')" \
    'the second rejected delta changed nothing'

  p_delta deltas-one-edit.jsonl
  ok 'a well-formed delta still applies after two rejections'
  assert_ne "$_before" "$(jget "$(sess findings.json)" 'd.findings[0].recommendation')" \
    'the valid delta did land'
  assert_eq "$((_ledger_before + 1))" "$(ledger_lines)" 'the accepted delta appended exactly one line'
}

t_delta_batch_is_atomic() {
  # The why-less fixtures are one line each, so on their own they only prove
  # that a bad delta is refused — not that a good delta sharing the file with it
  # is refused too. A half-applied batch is the worst outcome available: the
  # finding set moves, the ledger disagrees about why, and the agent's next pass
  # revises something it never chose.
  delta_session "$FIXTURES/findings-tiny.json"
  _id1=$(finding_id 1)
  _id2=$(finding_id 2)
  _rec=$(jget "$(sess findings.json)" 'd.findings[0].recommendation')
  _before=$(ledger_lines)
  _pass_before=$(pass_delta_lines 1)

  _good="{\"op\":\"edit\",\"target\":\"$_id1\",\"perspective\":\"builder\",\"why\":\"Recommendation named a quality, not a change.\",\"set\":{\"recommendation\":\"APPLIED-BY-THE-GOOD-LINE\"}}"

  # good line first, then each kind of bad line
  for _bad in \
    "{\"op\":\"delete\",\"target\":\"$_id2\",\"perspective\":\"skeptic\"}" \
    "{\"op\":\"edit\",\"target\":\"f-9999\",\"perspective\":\"builder\",\"why\":\"Targets a finding that does not exist.\",\"set\":{\"recommendation\":\"x\"}}" \
    "{\"op\":\"frobnicate\",\"target\":\"$_id2\",\"perspective\":\"builder\",\"why\":\"An operation the spec never defined.\"}" \
    "this line is not JSON at all"
  do
    printf '%s\n%s\n' "$_good" "$_bad" > "$WORK/batch.jsonl"
    run_ponder delta --session "$SLUG" --file "$WORK/batch.jsonl"
    assert_status 1 'a batch containing a bad delta is a user error'
    assert_next 'the rejected batch still prints NEXT'
    assert_eq "$_rec" "$(jget "$(sess findings.json)" 'd.findings[0].recommendation')" \
      'the good line in a rejected batch was not applied'
    assert_eq 'open' "$(jget "$(sess findings.json)" 'd.findings[1].status')" \
      'and neither was anything else in it'
    assert_eq "$_before" "$(ledger_lines)" 'a rejected batch appends nothing to the ledger (SPEC 8.2)'
    assert_eq "$_pass_before" "$(pass_delta_lines 1)" "and nothing to the pass's own delta file"
    assert_eq 'revise' "$(phase_now)" 'the pass still owes its revision'
  done

  printf '%s\n' "$_good" > "$WORK/batch.jsonl"
  run_ponder delta --session "$SLUG" --file "$WORK/batch.jsonl"
  ok 'the same good line applies on its own'
  assert_eq 'APPLIED-BY-THE-GOOD-LINE' "$(jget "$(sess findings.json)" 'd.findings[0].recommendation')" \
    'so the batch really was rejected as a whole, not silently dropped'
  assert_eq "$((_before + 1))" "$(ledger_lines)" 'and exactly one line joined the ledger'
}

t_delta_stdin() {
  new_workdir stdin
  p_start --max-passes 6 --min-passes 2
  ok 'start'
  p_predict 0.4 'Pass 1 inventories the screens.'; ok 'predict'

  run_ponder_stdin "$WORK/units.json" units --session "$SLUG" --stdin
  ok 'units --stdin exits 0'
  assert_eq '3' "$(jget "$(sess units.json)" 'd.units.length')" 'units --stdin stores the inventory'

  p_grade "$FIXTURES/findings-tiny.json"; ok 'grade'
  p_deliberate; ok 'deliberate'

  _ledger_before=$(ledger_lines)
  run_ponder_stdin "$(delta_file deltas-one-edit.jsonl)" delta --session "$SLUG" --stdin
  ok 'delta --stdin exits 0'
  assert_eq "$((_ledger_before + 1))" "$(ledger_lines)" 'delta --stdin appends exactly one ledger line'
}

t_delta_prose_change_warns() {
  delta_session "$FIXTURES/findings-tiny.json"
  p_delta deltas-prose-change.jsonl
  ok 'the engine accepts a change that only moves prose'
  _prose=$(jl "$(sess ledger.jsonl)" \
    'd.filter(x => x.op === "change" && x.set && Object.keys(x.set).every(k => ["title","detail","recommendation","evidence"].indexOf(k) >= 0)).length')
  if [ "${_prose:-0}" != "0" ]; then
    warn "$_prose change delta(s) edited only prose: re-grading hidden from the thrash detector (SPEC 3.4)"
  else
    fail 'the suite lint failed to spot a change delta that only moved prose'
  fi
}

# --------------------------------------------------------------- unit-edit ---
#
# SPEC 3.4. A unit's label, path, kind and meta go stale like anything else a pass
# writes down. Before `unit-edit` there was no way to fix one: unit-delete plus
# unit-add drops coverage below 1.0 and blocks the stop, so a loop that noticed a
# wrong caption had to ship it or reopen. Neither is acceptable, so the correction
# is a first-class revising delta — on the ledger, in the churn, in the report.

t_unit_edit_corrects_a_stale_label() {
  # The case the real run hit: a unit's pass-1 label said the opposite of what the
  # finding hanging off it now says, and there was no op to fix it.
  new_workdir unitedit
  p_start --max-passes 6 --min-passes 1;  ok 'start'
  p_predict 0.4 'Pass 1 grades all three screens.'; ok 'predict'
  p_units;  ok 'units'
  p_grade "$FIXTURES/findings-full.json"; ok 'grade'
  p_deliberate; ok 'deliberate'

  _cov_before=$(jget "$(sess units.json)" 'd.units.length')
  _ledger_before=$(ledger_lines)

  cat > "$WORK/edit-nowhy.jsonl" <<'EOF'
{"op":"unit-edit","target":"screen.settings.billing","perspective":"builder","set":{"label":"Settings > Billing (privacy link resolves)"}}
EOF
  run_ponder delta --session "$SLUG" --file "$WORK/edit-nowhy.jsonl"
  assert_status 1 'a unit-edit without a why is rejected like every other delta (SPEC 8.3)'
  assert_eq "$_ledger_before" "$(ledger_lines)" 'and wrote no ledger line'

  cat > "$WORK/edit.jsonl" <<'EOF'
{"op":"unit-edit","target":"screen.settings.billing","perspective":"builder","why":"Pass 1's label said both links 404; the finding under it now says the opposite, and says it correctly.","set":{"label":"Settings > Billing (privacy link resolves)","meta":{"state":"corrected"}}}
EOF
  run_ponder delta --session "$SLUG" --file "$WORK/edit.jsonl"
  ok 'a unit-edit with a why applies'
  assert_contains "$ALL" 'unit-edit' 'and the op is named in the delta summary'
  assert_eq "$((_ledger_before + 1))" "$(ledger_lines)" 'exactly one ledger line was appended'

  assert_eq 'Settings > Billing (privacy link resolves)' \
    "$(jget "$(sess units.json)" 'd.units.find(u => u.id === "screen.settings.billing").label')" \
    'the label is corrected in place (SPEC 3.4)'
  assert_eq 'screen.settings.billing' \
    "$(jget "$(sess units.json)" 'd.units.find(u => u.id === "screen.settings.billing").id')" \
    'and the id it joins findings on is untouched'
  assert_eq "$_cov_before" "$(jget "$(sess units.json)" 'd.units.length')" 'nothing entered or left the inventory'
  assert_eq '0' "$(jget "$(sess units.json)" 'd.units.filter(u => u.removedInPass).length')" \
    'a unit-edit is not a removal'

  # meta merges key by key: correcting a route must not wipe the marker beside it.
  assert_eq '/settings/billing' \
    "$(jget "$(sess units.json)" 'd.units.find(u => u.id === "screen.settings.billing").meta.route')" \
    'meta merges key by key — the route pass 1 recorded survives (SPEC 3.4)'
  assert_eq 'corrected' \
    "$(jget "$(sess units.json)" 'd.units.find(u => u.id === "screen.settings.billing").meta.state')" \
    'and the new key is there beside it'

  # The ledger carries the exact set that was applied, so replay derives it.
  assert_eq 'true' "$(jl "$(sess ledger.jsonl)" 'd.some(x => x.op === "unit-edit" && x.target === "screen.settings.billing" && x.perspective === "builder" && x.set.label === "Settings > Billing (privacy link resolves)" && typeof x.why === "string" && x.why.length > 0)')" \
    'the ledger record carries the target, the perspective, the why and the set (SPEC 3.4)'
  run_ponder verify --session "$SLUG"
  ok 'the session still reconciles — a unit-edit is replayed, not merely tolerated (SPEC 3.6)'

  p_judge_json; ok 'judge'
  assert_close "$(metric 1 coverage)" 1 0.0001 'a unit-edit does not touch coverage (SPEC 4)'
  assert_ne 'blocked' "$JUDGE_VERDICT" 'so a session that was stoppable stays stoppable'

  run_ponder decide stop --session "$SLUG" --why 'Every screen is graded and the stale caption is fixed.'
  ok 'the stop the wrong caption used to cost is still available'

  run_ponder report --session "$SLUG"; ok 'report exits 0'
  _r=$(cat "$(sess report.md)")
  assert_imatch "$_r" 'corrected screen' 'the report gives corrected units their own heading'
  assert_contains "$_r" 'screen.settings.billing' 'and names the unit'
  assert_contains "$_r" 'pass 1' 'with the pass that corrected it'
  assert_contains "$_r" 'builder' 'the perspective that asked for it'
  assert_contains "$_r" 'says the opposite' 'and the why, the same treatment removals get'
}

t_unit_edit_never_moves_an_id() {
  # SPEC 3.4 / SPEC 8.11: `id` is the join key between units.json and findings.json.
  # Moving it would orphan every finding on the unit, so it is rejected by name.
  build_escape_session

  cat > "$WORK/edit-id.jsonl" <<'EOF'
{"op":"unit-edit","target":"screen.settings.billing","perspective":"builder","why":"Tidying the id up to something shorter.","set":{"id":"screen.billing"}}
EOF
  _before=$(ledger_lines)
  run_ponder delta --session "$SLUG" --file "$WORK/edit-id.jsonl"
  assert_status 1 'a unit-edit that sets id is refused, exit 1 (SPEC 3.4)'
  assert_imatch "$ALL" 'join key' 'and the refusal says why the id is special'
  assert_imatch "$ALL" 'orphan' 'naming what changing it would do to the findings'
  assert_eq "$_before" "$(ledger_lines)" 'the refused edit wrote no ledger line'
  assert_eq 'screen.settings.billing' \
    "$(jget "$(sess units.json)" 'd.units[0].id')" 'and the id is exactly what it was'

  # An id smuggled in beside a legal field takes the whole batch with it (SPEC 3.4).
  cat > "$WORK/edit-id-mixed.jsonl" <<'EOF'
{"op":"unit-edit","target":"screen.settings.profile","perspective":"builder","why":"A perfectly ordinary label correction.","set":{"label":"Settings > Profile"}}
{"op":"unit-edit","target":"screen.settings.billing","perspective":"builder","why":"And an id change hiding behind it.","set":{"label":"Billing","id":"screen.billing"}}
EOF
  run_ponder delta --session "$SLUG" --file "$WORK/edit-id-mixed.jsonl"
  assert_status 1 'one id change rejects the whole batch'
  assert_eq "$_before" "$(ledger_lines)" 'nothing from that batch reached the ledger'
  assert_eq 'Settings > Billing' "$(jget "$(sess units.json)" 'd.units[0].label')" \
    'including the label edit that would have been fine on its own'

  # And the neighbouring refusals, so "unit-edit rejects things" is not the only claim.
  cat > "$WORK/edit-unknown.jsonl" <<'EOF'
{"op":"unit-edit","target":"screen.settings.billing","perspective":"builder","why":"Inventing a field that is not part of a unit.","set":{"owner":"platform-team"}}
EOF
  run_ponder delta --session "$SLUG" --file "$WORK/edit-unknown.jsonl"
  assert_status 1 'a unit-edit setting an unknown field is refused'
  assert_imatch "$ALL" 'label, path, kind, meta' 'and lists what a unit-edit may set'

  cat > "$WORK/edit-missing.jsonl" <<'EOF'
{"op":"unit-edit","target":"screen.nowhere.atall","perspective":"builder","why":"Editing a unit that was never enumerated.","set":{"label":"Nowhere"}}
EOF
  run_ponder delta --session "$SLUG" --file "$WORK/edit-missing.jsonl"
  assert_status 1 'a unit-edit against an unknown unit is refused'

  # A removed unit is re-added, not edited back into shape.
  cat > "$WORK/drop-then-edit.jsonl" <<'EOF'
{"op":"unit-delete","target":"screen.onboarding.welcome","perspective":"skeptic","why":"Onboarding is off the list for this round; nobody has looked at it."}
EOF
  run_ponder delta --session "$SLUG" --file "$WORK/drop-then-edit.jsonl"
  ok 'the delete applies'
  p_judge; ok 'pass 1 judge'
  p_decide continue 'Welcome still counts against coverage, so keep going.'; ok 'pass 1 decide'
  p_predict 0.1 'Pass 2 tries to edit a unit that has left the inventory.'; ok 'pass 2 predict'
  p_deliberate; ok 'pass 2 deliberate'
  cat > "$WORK/edit-removed.jsonl" <<'EOF'
{"op":"unit-edit","target":"screen.onboarding.welcome","perspective":"builder","why":"Fixing the label of a unit that is no longer in the inventory.","set":{"label":"Onboarding > Welcome"}}
EOF
  run_ponder delta --session "$SLUG" --file "$WORK/edit-removed.jsonl"
  assert_status 1 'a unit that has left the inventory cannot be edited (SPEC 3.4)'
  assert_imatch "$ALL" 'removed in pass' 'and the refusal says when it left'
}

t_unit_edit_thrashes_like_any_other_revision() {
  # SPEC 4: a unit-edit is a revising delta, so a label edited back and forth is
  # oscillation exactly like a severity flipped back and forth, and it counts.
  new_workdir uethrash
  p_start --max-passes 8 --min-passes 1; ok 'start'
  p_predict 0.4 'Pass 1 grades everything.'; ok 'predict'
  p_units; ok 'units'
  p_grade "$FIXTURES/findings-full.json"; ok 'grade'
  p_deliberate; ok 'deliberate'
  cat > "$WORK/ue-a.jsonl" <<'EOF'
{"op":"unit-edit","target":"screen.settings.billing","perspective":"builder","why":"Pass 1's caption was copied from the wrong screen; this one names what is actually there.","set":{"label":"Billing — invoice list"}}
EOF
  cat > "$WORK/ue-b.jsonl" <<'EOF'
{"op":"unit-edit","target":"screen.settings.billing","perspective":"empath","why":"Putting the caption back to what pass 1 said; the invoice framing reads worse to a first-time user.","set":{"label":"Settings > Billing"}}
EOF
  run_ponder delta --session "$SLUG" --file "$WORK/ue-a.jsonl"; ok 'pass 1 moves the label'
  p_judge; ok 'pass 1 judge'
  p_decide continue 'One pass is an opinion.'; ok 'pass 1 decide'

  p_predict 0.2 'Pass 2 puts the caption back where pass 1 had it.'; ok 'pass 2 predict'
  p_deliberate; ok 'pass 2 deliberate'
  run_ponder delta --session "$SLUG" --file "$WORK/ue-b.jsonl"; ok 'pass 2 puts it back'
  p_judge_json; ok 'pass 2 judge'

  assert_gt "$(metric 2 churn)" '0' 'a unit-edit counts toward churn (SPEC 4)'
  assert_gt "$(metric 2 thrash)" '0' 'and putting a label back is a reversal (SPEC 4)'
  assert_eq '1' "$(jget "$(pass_dir 2)/metrics.json" 'd.reversals.length')" \
    'exactly one reversal is recorded'
  assert_eq 'screen.settings.billing' "$(jget "$(pass_dir 2)/metrics.json" 'd.reversals[0].target')" \
    'and it names the unit that oscillated'
  assert_contains "$(jget "$(pass_dir 2)/metrics.json" 'd.reversals[0].fields.join(",")')" 'label' \
    'and the field'
  assert_close "$(metric 2 coverage)" 1 0.0001 'while coverage never moved (SPEC 4)'
}

t_unit_edit_cannot_walk_a_path_past_the_coverage_gate() {
  # THE TRAP. `unit-edit` can move a unit's `path`, and a phantom claim is checked
  # against a path. Naively, that is a two-delta route straight through SPEC 8.1:
  # point a real screen at a filename that does not exist, claim it never existed,
  # and let the engine certify the absence. SPEC 3.5 closes it — the claim is checked
  # against EVERY path the unit has ever carried, and one survivor sinks it.
  build_escape_session

  # First: the attack in one batch. Both screens are real files on disk.
  cat > "$WORK/walk.jsonl" <<'EOF'
{"op":"unit-edit","target":"screen.settings.profile","perspective":"builder","why":"Correcting the route: profile actually lives under account, not settings.","set":{"path":"src/routes/account/profile.tsx"}}
{"op":"unit-delete","target":"screen.settings.profile","phantom":true,"perspective":"skeptic","why":"There is no such file, so pass 1 enumerated a screen that does not exist."}
EOF
  _before=$(ledger_lines)
  run_ponder delta --session "$SLUG" --file "$WORK/walk.jsonl"
  assert_status 1 'editing a path and then claiming phantom is refused (SPEC 3.5)'
  assert_contains "$ALL" 'src/routes/settings/profile.tsx' \
    'the refusal names the path that was found'
  assert_imatch "$ALL" 'pass 1' 'and the pass that set it'
  assert_imatch "$ALL" 'every path the unit has ever had' \
    'and says the check is against the whole history, not the current value'
  assert_eq "$_before" "$(ledger_lines)" 'the refused batch wrote no ledger line'
  assert_eq '0' "$(jget "$(sess units.json)" 'd.units.filter(u => u.removedInPass).length')" \
    'and the inventory is untouched — including the edit that came first'

  # Second: the same attack split across passes, so the check has to read the ledger
  # rather than a within-batch memo.
  cat > "$WORK/walk-edit.jsonl" <<'EOF'
{"op":"unit-edit","target":"screen.settings.profile","perspective":"builder","why":"Correcting the route: profile actually lives under account, not settings.","set":{"path":"src/routes/account/profile.tsx"}}
EOF
  cat > "$WORK/walk-phantom.jsonl" <<'EOF'
{"op":"unit-delete","target":"screen.settings.profile","phantom":true,"perspective":"skeptic","why":"There is no such file, so pass 1 enumerated a screen that does not exist."}
EOF
  run_ponder delta --session "$SLUG" --file "$WORK/walk-edit.jsonl"
  ok 'the path edit on its own is a perfectly legal delta'
  assert_eq 'src/routes/account/profile.tsx' \
    "$(jget "$(sess units.json)" 'd.units.find(u => u.id === "screen.settings.profile").path')" \
    'and it really did move the path'
  p_judge; ok 'pass 1 judge'
  p_decide continue 'Two screens are still ungraded.'; ok 'pass 1 decide'
  p_predict 0.1 'Pass 2 tries to certify away a screen whose path it moved last pass.'
  ok 'pass 2 predict'
  p_deliberate; ok 'pass 2 deliberate'

  _before2=$(ledger_lines)
  run_ponder delta --session "$SLUG" --file "$WORK/walk-phantom.jsonl"
  assert_status 1 'a pass later, the claim is still checked against the original path'
  assert_contains "$ALL" 'src/routes/settings/profile.tsx' 'the refusal still names the file it found'
  assert_eq "$_before2" "$(ledger_lines)" 'and wrote nothing'

  # Third: with every version of the path genuinely gone, the claim is accepted —
  # but as UNVERIFIED, never verified-missing. The engine will not certify an absence
  # about a target that moved.
  rm -f "$WORK/src/routes/settings/profile.tsx"
  run_ponder delta --session "$SLUG" --file "$WORK/walk-phantom.jsonl"
  ok 'with no version of the path on disk, the phantom is accepted'
  assert_eq 'unverified' \
    "$(jget "$(sess units.json)" 'd.units.find(u => u.id === "screen.settings.profile").phantomVerification')" \
    'a unit whose path was edited is never verified-missing (SPEC 3.5)'
  assert_eq 'null' \
    "$(jget "$(sess units.json)" 'JSON.stringify(d.units.find(u => u.id === "screen.settings.profile").phantomPath)')" \
    'and carries no certified path'
  assert_imatch "$ALL" 'unverified' 'the engine says so at the moment of the delete'
  assert_imatch "$ALL" 'moved|edited' 'and says the target moved, not that there was no path'
  assert_eq '2' "$(jl "$(sess ledger.jsonl)" 'd.filter(x => x.op === "unit-delete" && x.target === "screen.settings.profile").pop().pathsChecked.length')" \
    'the ledger records both paths the engine checked (SPEC 3.5)'

  # The gate is still shut on the screen nobody looked at.
  p_judge_json; ok 'pass 2 judge'
  assert_eq 'blocked' "$JUDGE_VERDICT" 'the still-ungraded screen keeps the gate shut'
  run_ponder decide stop --session "$SLUG" --why 'The screens I never graded are gone now.'
  assert_status 2 'and a stop is still refused (SPEC 8.1)'

  run_ponder report --session "$SLUG"; ok 'report exits 0'
  _r=$(cat "$(sess report.md)")
  assert_contains "$_r" 'UNVERIFIED' 'the report marks the unchecked claim distinctly'
  assert_imatch "$_r" "path was edited" 'and says which kind of unverified it is'

  # The paragraph that INTRODUCES the list has to say the same thing the list
  # says. SPEC 3.5 keeps two unverified claims apart — no path at all, versus a
  # path that moved — and a summary written off the unverified count alone
  # announced "the unit had no path" directly above a line saying the opposite.
  _intro=$(printf '%s\n' "$_r" | awk '/^### Phantom units/{f=1;next} f&&NF{print;exit}')
  assert_imatch "$_intro" 'path was edited|paths were edited' \
    'the Phantom units summary names the reason the claim could not be checked'
  if printf '%s\n' "$_intro" | grep -Eqi 'had no path|none had a path'; then
    fail "the Phantom units summary claims the unit had no path, but its path was edited: $_intro"
  else
    _assert_pass
  fi
}

t_unit_edit_a_hand_written_label_is_still_caught() {
  # The correction being cheap must not make forging one cheap. SPEC 3.6 pins label,
  # path, kind and meta, and every one of them is now derived by replaying unit-edit
  # records — so a caption changed in units.json with no ledger line still diverges.
  build_partial_session
  reconcile_refuses 'hand-written label' "$(sess units.json)" '
    const u = d.units.find((x) => x.id === "screen.settings.billing");
    if (!u) throw new Error("fixture drift");
    u.label = "Settings > Billing (edited by hand)";
  '
}

# ------------------------------------------------------------------ ledger ---

t_ledger_append_only() {
  build_converged_session || return 0

  _total=$(jlines "$(sess ledger.jsonl)")
  assert_eq "$((LEDGER_N1 + 1))" "$LEDGER_N2" 'pass 2 appended exactly the one delta it applied'
  assert_eq "$((LEDGER_N2 + 1))" "$_total" 'pass 3 appended exactly the one delta it applied'
  _sum=$(( $(jlines "$(pass_dir 1)/deltas.jsonl") + $(jlines "$(pass_dir 2)/deltas.jsonl") + $(jlines "$(pass_dir 3)/deltas.jsonl") ))
  assert_eq "$_sum" "$_total" 'the ledger is the union of every pass delta file (SPEC 3.4)'

  head -n "$LEDGER_N1" "$(sess ledger.jsonl)" > "$SUITE_TMP/head1"
  if cmp -s "$SUITE_TMP/head1" "$LEDGER_SNAP1"; then
    _assert_pass
  else
    _assert_fail "pass 1 ledger lines were rewritten by later passes (SPEC 8.2)
$(diff "$LEDGER_SNAP1" "$SUITE_TMP/head1" 2>&1 | head -10 | sed 's/^/          | /')"
  fi

  head -n "$LEDGER_N2" "$(sess ledger.jsonl)" > "$SUITE_TMP/head2"
  if cmp -s "$SUITE_TMP/head2" "$LEDGER_SNAP2"; then
    _assert_pass
  else
    _assert_fail 'pass 2 ledger lines were rewritten by pass 3 (SPEC 8.2)'
  fi

  assert_eq 'true' "$(jl "$(sess ledger.jsonl)" 'd.map(x => x.pass).every((p, i, a) => i === 0 || p >= a[i-1])')" \
    'ledger lines never move backwards in pass order'
  assert_eq 'true' "$(jl "$(sess ledger.jsonl)" 'd.every(x => typeof x.why === "string" && x.why.length > 0)')" \
    'every line on the ledger carries a why'
}

# ------------------------------------------------------------- reconcile ---
#
# SPEC 3.6. units.json and findings.json are ordinary files; ledger.jsonl is
# append-only and records every operation the session ever applied. So the
# honest state is not trusted, it is recomputed — and the four commands that
# draw a conclusion refuse to run on state the ledger does not account for.
#
# Every test in this group forges a state file the way an agent that wanted
# past the coverage gate would, and pins the refusal.

# forge <file> <js-body> — rewrite a state document in place. `d` is the parsed
# document. A body that throws is fixture drift, not a passing test, so the
# forge asserts on itself: a test that forges nothing must not read as green.
forge() {
  if "$NODE" -e '
    const fs = require("fs");
    const p = process.argv[1];
    const d = JSON.parse(fs.readFileSync(p, "utf8"));
    (new Function("d", process.argv[2]))(d);
    fs.writeFileSync(p, JSON.stringify(d, null, 2));
  ' "$1" "$2" 2> "$SUITE_TMP/forge-err"; then
    _assert_pass
  else
    _assert_fail "the forgery of $1 did not apply
$(_excerpt "$(cat "$SUITE_TMP/forge-err")")"
  fi
}

# reconcile_refuses <label> <state-file> <forge-js>
#
# All four decision points against one forgery. judge is checked before the
# session has judged and the others after, because a forged session cannot be
# walked past judge — so the file is put back, judged honestly, and re-forged.
#
# Every refusal has to say "reconcile": an exit 2 on its own would also be
# produced by the phase machine or by the coverage gate, and those two prove
# nothing about this mechanism.
reconcile_refuses() {
  _rr_label=$1
  _rr_file=$2
  _rr_js=$3
  _rr_honest="$SUITE_TMP/honest-state.json"
  cp "$_rr_file" "$_rr_honest"

  forge "$_rr_file" "$_rr_js"
  run_ponder verify --session "$SLUG"
  assert_status 2 "$_rr_label: ponder verify reports the divergence (SPEC 3.6)"
  assert_imatch "$ALL" 'does not reconcile' "$_rr_label: and says the session does not reconcile"
  assert_next "$_rr_label: the refusal still prints NEXT"

  run_ponder judge --session "$SLUG"
  assert_status 2 "$_rr_label: judge refuses to compute signals off unreconciled state"
  assert_imatch "$ALL" 'does not reconcile' "$_rr_label: judge refuses for the ledger, not the phase"
  assert_no_file "$(pass_dir 1)/metrics.json" "$_rr_label: and writes no metrics.json"

  # Put it back, judge honestly, and forge again — now against decide.
  cp "$_rr_honest" "$_rr_file"
  run_ponder judge --session "$SLUG"
  assert_status 0 "$_rr_label: the honest state judges without complaint"
  forge "$_rr_file" "$_rr_js"

  run_ponder decide stop --session "$SLUG" --why 'The files on disk say this session is finished.'
  assert_status 2 "$_rr_label: decide stop is refused (SPEC 8.1, SPEC 8.9)"
  assert_imatch "$ALL" 'does not reconcile' "$_rr_label: and refused for the ledger, not for coverage"
  assert_eq 'open' "$(status_now)" "$_rr_label: the session is still open"
  assert_eq '0' "$(jget "$(sess session.json)" 'd.history.length')" "$_rr_label: nothing was committed"

  run_ponder report --session "$SLUG"
  assert_status 2 "$_rr_label: report refuses to narrate unreconciled state"
  assert_imatch "$ALL" 'does not reconcile' "$_rr_label: report says why"
  assert_no_file "$(sess report.md)" "$_rr_label: and writes no report.md"

  run_ponder apply --session "$SLUG" --dry-run
  assert_status 2 "$_rr_label: even apply --dry-run refuses — the preview is the plan"
  assert_imatch "$ALL" 'does not reconcile' "$_rr_label: apply says why"
  assert_no_file "$(sess apply-plan.md)" "$_rr_label: and writes no apply-plan.md"
}

t_reconcile_forged_phantom() {
  # The first route: write removalKind "phantom" onto two units the ledger never
  # removed. Both drop out of the coverage denominator, coverage reads 1.0, and
  # the gate opens on a few characters of JSON.
  build_partial_session

  _forge_phantom='
    let n = 0;
    for (const u of d.units) {
      if (u.id === "screen.settings.profile" || u.id === "screen.onboarding.welcome") {
        u.removedInPass = 1;
        u.removalKind = "phantom";
        u.phantomVerification = "verified-missing";
        u.phantomPath = "/nowhere/at/all.tsx";
        n++;
      }
    }
    if (n !== 2) throw new Error("fixture drift: forged " + n);
  '
  forge "$(sess units.json)" "$_forge_phantom"
  run_ponder verify --session "$SLUG"
  assert_status 2 'a forged phantom does not reconcile with the ledger (SPEC 3.6)'
  assert_contains "$ALL" 'screen.settings.profile' 'the diagnosis names the first forged unit'
  assert_contains "$ALL" 'screen.onboarding.welcome' 'the diagnosis names the second'
  assert_contains "$ALL" 'removalKind' 'and names the field'
  assert_contains "$ALL" '"phantom"' 'and quotes what units.json claims'
  assert_imatch "$ALL" 'ledger says .*unset' 'and says the ledger never removed them'

  # Restore, then run the full four-point check from a clean start.
  build_partial_session
  reconcile_refuses 'forged phantom' "$(sess units.json)" "$_forge_phantom"
}

t_reconcile_deleted_unit_entries() {
  # The second route, and the cheapest one: claim nothing about the two ungraded
  # units, just delete their entries from units.json. The denominator is whatever
  # the file holds, so coverage reads 1 of 1 and the gate opens.
  build_partial_session

  _forge_delete='
    d.units = d.units.filter((u) => u.id === "screen.settings.billing");
    if (d.units.length !== 1) throw new Error("fixture drift");
  '
  forge "$(sess units.json)" "$_forge_delete"
  assert_eq '1' "$(jget "$(sess units.json)" 'd.units.length')" 'the two ungraded units are gone from the file'
  run_ponder verify --session "$SLUG"
  assert_status 2 'a unit deleted out of units.json does not reconcile (SPEC 3.6)'
  assert_contains "$ALL" 'screen.settings.profile' 'the diagnosis names the first deleted unit'
  assert_contains "$ALL" 'screen.onboarding.welcome' 'the diagnosis names the second'
  assert_imatch "$ALL" 'ledger enumerated it' 'and says the ledger enumerated it'
  assert_imatch "$ALL" 'unit-delete' 'and names the operation that removes a unit honestly'

  build_partial_session
  reconcile_refuses 'deleted unit entries' "$(sess units.json)" "$_forge_delete"
}

t_reconcile_fabricated_findings() {
  # The third route: leave the inventory alone and invent the grades. One
  # finding per ungraded unit and coverage is complete — except that no add
  # record ever created them.
  build_partial_session

  _forge_findings='
    const one = (id, unit) => ({
      id, unit, title: "Fabricated grade for " + unit, detail: "",
      dimension: "empty-states", score: 3, severity: "note", confidence: 0.9,
      effort: "s", evidence: [], recommendation: "", status: "open",
      createdInPass: 1, lastTouchedPass: 1, history: [],
    });
    d.findings.push(one("f-9001", "screen.settings.profile"));
    d.findings.push(one("f-9002", "screen.onboarding.welcome"));
  '
  forge "$(sess findings.json)" "$_forge_findings"
  run_ponder verify --session "$SLUG"
  assert_status 2 'a fabricated finding does not reconcile (SPEC 3.6)'
  assert_contains "$ALL" 'f-9001' 'the diagnosis names the first invented id'
  assert_contains "$ALL" 'f-9002' 'and the second'
  assert_imatch "$ALL" 'no ledger record ever created it' 'and says why they are not findings'

  build_partial_session
  reconcile_refuses 'fabricated findings' "$(sess findings.json)" "$_forge_findings"

  # A second copy of a real finding is the same lie with better camouflage.
  build_partial_session
  _real=$(finding_id 1)
  forge "$(sess findings.json)" 'd.findings.push(JSON.parse(JSON.stringify(d.findings[0])));'
  run_ponder verify --session "$SLUG"
  assert_status 2 'a duplicated finding entry does not reconcile'
  assert_contains "$ALL" "$_real" 'the diagnosis names the duplicated id'
  assert_imatch "$ALL" 'more than once' 'and says it appears more than once'

  # And so is deleting one, which SPEC 8.2 forbids outright.
  build_partial_session
  _real=$(finding_id 1)
  forge "$(sess findings.json)" 'd.findings.shift();'
  run_ponder verify --session "$SLUG"
  assert_status 2 'a finding removed from findings.json does not reconcile'
  assert_contains "$ALL" "$_real" 'the diagnosis names the finding that went missing'
  assert_imatch "$ALL" 'never removed|8\.2' 'and cites the rule it breaks'
}

t_reconcile_forged_status() {
  # The fourth route: flip a status by hand. Both directions are material —
  # retracted to open manufactures coverage, open to resolved manufactures
  # finished work and drops the finding out of the apply plan.
  new_workdir forgedstatus
  p_start --max-passes 6 --min-passes 1; ok 'start'
  p_predict 0.45 'Pass 1 grades every screen and then withdraws most of it.'
  ok 'predict'
  p_units; ok 'units'
  p_grade "$FIXTURES/findings-full.json"; ok 'grade'
  p_deliberate; ok 'deliberate'

  # Retract everything that is not about billing — honestly, through a delta.
  "$NODE" -e '
    const fs = require("fs");
    const d = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    const out = d.findings
      .filter((f) => f.unit !== "screen.settings.billing")
      .map((f) => JSON.stringify({
        op: "delete", target: f.id, perspective: "skeptic",
        why: "Asserted without evidence; retracting it rather than leaving it on the board.",
      }))
      .join("\n");
    fs.writeFileSync(process.argv[2], out + "\n");
  ' "$(sess findings.json)" "$WORK/retract.jsonl"
  run_ponder delta --session "$SLUG" --file "$WORK/retract.jsonl"
  ok 'the retractions apply'

  run_ponder verify --session "$SLUG"
  ok 'an honestly retracted session still reconciles — retraction is an operation, not an edit'

  # Now put the retractions back to open with a text editor — one per ungraded
  # screen, which is exactly enough to make coverage read 1.0 again.
  _forge_unretract='
    let n = 0;
    for (const unit of ["screen.settings.profile", "screen.onboarding.welcome"]) {
      const f = d.findings.find((x) => x.unit === unit && x.status === "retracted");
      if (!f) throw new Error("fixture drift: nothing retracted on " + unit);
      f.status = "open";
      n++;
    }
    if (n !== 2) throw new Error("fixture drift: un-retracted " + n);
  '
  cp "$(sess findings.json)" "$WORK/findings-honest.json"
  forge "$(sess findings.json)" "$_forge_unretract"
  run_ponder verify --session "$SLUG"
  assert_status 2 'un-retracting a finding by hand does not reconcile (SPEC 3.6)'
  assert_imatch "$ALL" 'status .*ledger says "retracted".*findings.json says "open"' \
    'the diagnosis names the field and quotes both sides'
  cp "$WORK/findings-honest.json" "$(sess findings.json)"

  reconcile_refuses 'un-retracted findings' "$(sess findings.json)" "$_forge_unretract"

  # The other direction, on a closed session: open to resolved is work nobody did.
  build_converged_session || return 0
  p_decide stop 'Two quiet passes in a row; the answer stopped changing.'
  ok 'decide stop'
  run_ponder report --session "$SLUG"; ok 'the honest session reports'
  _target=$(jget "$(sess findings.json)" 'd.findings.find(f => f.status === "open" && f.severity === "must").id')
  assert_match "$_target" '^f-[0-9]{4}$' 'the session has an open must-finding to forge'
  forge "$(sess findings.json)" '
    const f = d.findings.find((x) => x.status === "open" && x.severity === "must");
    f.status = "resolved";
  '
  run_ponder verify --session "$SLUG"
  assert_status 2 'marking a finding resolved by hand does not reconcile'
  assert_contains "$ALL" "$_target" 'the diagnosis names the finding'
  assert_imatch "$ALL" 'ledger says "open"' 'and says the ledger still has it open'
  run_ponder apply --session "$SLUG" --dry-run
  assert_status 2 'so it cannot quietly drop out of the apply plan (SPEC 3.6)'
  assert_imatch "$ALL" 'does not reconcile' 'apply says why'
  run_ponder report --session "$SLUG"
  assert_status 2 'and report refuses too'
}

t_reconcile_stays_silent_on_an_honest_session() {
  # The other half of SPEC 3.6, and the more important half: a reconciler that
  # cries wolf gets worked around by the next agent. Five passes and every
  # operation the engine has — add, edit, change, delete, unit-add, all three
  # unit-delete kinds, the phantom upgrade, a retraction and a re-add, a field
  # reverted, a finding moved to another unit, a dimension set back to null —
  # and it stays silent after every single command.
  new_workdir soak
  cp "$FIXTURES/units-soak.json" "$WORK/units.json"

  # v <what just happened> — reconciliation must be clean here.
  v() {
    run_ponder verify --session "$SLUG"
    if [ "$STATUS" -eq 0 ]; then
      _assert_pass
    else
      _assert_fail "SPEC 3.6: an honest session diverged after $1
$(_excerpt "$ALL")"
    fi
  }

  p_start --max-passes 9 --min-passes 1; ok 'start'
  v 'start'

  p_predict 0.5 'Pass 1 enumerates six screens and grades four of them.'; ok 'p1 predict'
  p_units; ok 'p1 units'; v 'units'
  p_grade "$FIXTURES/findings-soak.json"; ok 'p1 grade'; v 'grade'
  p_deliberate; ok 'p1 deliberate'
  p_delta deltas-soak-1.jsonl; ok 'p1 delta'; v 'edit, change, delete and add'
  p_judge; ok 'p1 judge'; v 'judge'
  p_decide continue 'One pass is an opinion, and the inventory still needs pruning.'
  ok 'p1 decide'; v 'decide'

  later_pass deltas-soak-2.jsonl 0.4 'Pass 2 prunes the inventory three different ways.' || return 0
  v 'appraised, removed-ungraded and verified-phantom unit-deletes, plus a unit-add'
  assert_eq 'appraised' "$(jget "$(sess units.json)" 'd.units.find(u => u.id === "screen.partner.embed").removalKind')" \
    'the appraised removal is stored as such'
  assert_eq 'removed-ungraded' "$(jget "$(sess units.json)" 'd.units.find(u => u.id === "screen.legacy.unknown").removalKind')" \
    'the ungraded removal is stored as such'
  assert_eq 'verified-missing' "$(jget "$(sess units.json)" 'd.units.find(u => u.id === "screen.auth.sso").phantomVerification')" \
    'and the phantom claim with a dead path is verified'
  p_judge; ok 'p2 judge'; v 'p2 judge'
  p_decide continue 'The route pass 2 added to the inventory has not been graded.'
  ok 'p2 decide'; v 'p2 decide'

  later_pass deltas-soak-3.jsonl 0.3 'Pass 3 upgrades a claim and grades the new route.' || return 0
  v 'the phantom upgrade, a fresh add and a retraction'
  assert_eq 'phantom' "$(jget "$(sess units.json)" 'd.units.find(u => u.id === "screen.legacy.unknown").removalKind')" \
    'the removed-ungraded unit was upgraded to a phantom'
  assert_eq 'unverified' "$(jget "$(sess units.json)" 'd.units.find(u => u.id === "screen.legacy.unknown").phantomVerification')" \
    'and marked unverified, because it had no path to check'
  p_judge; ok 'p3 judge'; v 'p3 judge'
  p_decide continue 'A screen lost its only live judgment; that has to be answered.'
  ok 'p3 decide'; v 'p3 decide'

  later_pass deltas-soak-4.jsonl 0.3 'Pass 4 re-adds what pass 3 killed and reverts a grade.' || return 0
  v 'a revived delete, a reverted field, resolved, deferred, a moved unit and a nulled dimension'
  p_judge; ok 'p4 judge'; v 'p4 judge'
  assert_gt "$(metric 4 thrash)" '0' 'pass 4 really did reverse itself, so the ledger holds a reversal'
  p_decide continue 'The thrash needs one quiet pass before this can close.'
  ok 'p4 decide'; v 'p4 decide'

  later_pass deltas-soak-5.jsonl 0.05 'Pass 5 should find nothing but wording.' || return 0
  v 'p5 delta'
  p_judge; ok 'p5 judge'; v 'p5 judge'
  assert_close "$(metric 5 coverage)" 1 0.0001 'every live screen is graded by the end'

  p_decide stop 'Every live screen is graded and the answer stopped moving.'
  ok 'p5 decide stop'; v 'decide stop'
  run_ponder report --session "$SLUG"; ok 'report'; v 'report'
  run_ponder apply --session "$SLUG" --dry-run; ok 'apply --dry-run'; v 'apply --dry-run'
  run_ponder apply --session "$SLUG"; ok 'apply'; v 'apply'

  run_ponder doctor
  ok 'doctor is clean on an honest session'
  assert_imatch "$ALL" 'reconcile' 'and reports on reconciliation'
  assert_no_imatch "$ALL" 'not reconcile' 'with nothing flagged'
}

t_reconcile_verify_is_first_class() {
  # SPEC 3.6: verify is a command, not a flag on something else. An agent that
  # inherits a session has to be able to check it before spending a pass on it.
  new_workdir verifycmd
  p_start --max-passes 6 --min-passes 2; ok 'start'
  pass_one "$FIXTURES/findings-full.json" deltas-pass1.jsonl

  run_ponder verify --session "$SLUG"
  ok 'verify exits 0 on an honest session'
  assert_next 'verify prints NEXT'
  assert_imatch "$ALL" 'ledger' 'verify reports on the ledger'
  assert_imatch "$ALL" 'reconcile' 'and says the session reconciles'

  run_ponder verify --session "$SLUG" --json
  ok 'verify --json exits 0'
  assert_json_stdout 'verify --json'
  assert_json_next 'verify --json'
  assert_eq 'true' "$(jout 'String(d.ok)')" 'the JSON payload says the session reconciles'
  assert_eq '0' "$(jout 'String(d.divergences.length)')" 'with no divergences'
  assert_eq '3' "$(jout 'String(d.counts.expectedUnits)')" 'and derives all three units from the ledger'

  # An agent that has lost its context runs verify without knowing the slug.
  run_ponder verify
  ok 'verify with no --session resolves the open session like every other command'

  # It is a gate, not a report: the divergent case exits 2 in JSON too.
  forge "$(sess units.json)" 'd.units[2].path = "src/routes/somewhere/else.tsx";'
  run_ponder verify --session "$SLUG" --json
  assert_status 2 'verify --json exits 2 on a divergence'
  assert_json_stdout 'a failing verify --json still emits JSON'
  assert_json_next 'a failing verify --json still names the next phase'
  assert_eq 'false' "$(jout 'String(d.ok)')" 'and marks itself failed'
  assert_contains "$OUT" 'screen.onboarding.welcome' 'naming the unit whose path was rewritten'
  assert_contains "$OUT" 'path' 'and the field'

  # A rewritten path is not cosmetic: it is what a phantom claim is checked
  # against, so a unit that quietly loses one is a claim nobody can check.
  forge "$(sess units.json)" 'delete d.units[2].path;'
  run_ponder verify --session "$SLUG"
  assert_status 2 'a unit that loses its path does not reconcile either (SPEC 3.6)'
  assert_contains "$ALL" 'path' 'and the diagnosis names the field'

  # doctor is where an inherited checkout gets told (SPEC 3.6).
  run_ponder doctor
  assert_status 1 'doctor reports an unreconciled session as a problem'
  assert_contains "$ALL" "$SLUG" 'naming the session'
  assert_contains "$ALL" 'ponder verify' 'and the command that explains it'

  run_ponder doctor --json
  assert_status_not 0 'doctor --json agrees'
  assert_json_stdout 'doctor --json'
  assert_eq '1' "$(jout 'String(d.unreconciled.length)')" 'and carries the divergent session in its payload'
}

# forge_ledger <js-body> — rewrite ledger.jsonl in place. `L` is the array of
# parsed records; the body returns the array to write back. Like forge(), it
# asserts on itself: a forgery that throws must not read as a passing test.
forge_ledger() {
  if "$NODE" -e '
    const fs = require("fs");
    const p = process.argv[1];
    const L = fs.readFileSync(p, "utf8").trim().split("\n").filter(Boolean).map((l) => JSON.parse(l));
    const out = (new Function("L", process.argv[2]))(L);
    if (!Array.isArray(out)) throw new Error("the forgery returned no ledger array");
    fs.writeFileSync(p, out.map((r) => JSON.stringify(r)).join("\n") + "\n");
  ' "$(sess ledger.jsonl)" "$1" 2> "$SUITE_TMP/forge-err"; then
    _assert_pass
  else
    _assert_fail "the forgery of ledger.jsonl did not apply
$(_excerpt "$(cat "$SUITE_TMP/forge-err")")"
  fi
}

# every_decision_point_refuses <label>
#
# The session is already forged when this is called. Checks the same four
# commands reconcile_refuses does, and insists every refusal says "reconcile" —
# an exit 2 alone would also come from the phase machine or the coverage gate.
# decide is checked through the same put-it-back-judge-re-forge dance, off a
# whole-directory snapshot, because these forgeries span more than one file.
every_decision_point_refuses() {
  _ed_label=$1
  run_ponder verify --session "$SLUG"
  assert_status 2 "$_ed_label: verify reports the divergence"
  assert_imatch "$ALL" 'does not reconcile' "$_ed_label: and says the session does not reconcile"

  run_ponder judge --session "$SLUG"
  assert_status 2 "$_ed_label: judge refuses"
  assert_imatch "$ALL" 'does not reconcile' "$_ed_label: judge refuses for the ledger, not the phase"

  run_ponder report --session "$SLUG"
  assert_status 2 "$_ed_label: report refuses"
  assert_imatch "$ALL" 'does not reconcile' "$_ed_label: report says why"

  run_ponder apply --session "$SLUG" --dry-run
  assert_status 2 "$_ed_label: apply --dry-run refuses"
  assert_imatch "$ALL" 'does not reconcile' "$_ed_label: apply says why"
}

t_reconcile_a_ledger_line_alone_is_not_enough() {
  # The route a reader of the source takes next. The state-file forgeries are
  # caught by replay, so forge both sides: invent a finding in findings.json and
  # append the `add` record that would have created it to ledger.jsonl, so the
  # two agree with each other.
  #
  # They still lose, because ledger.jsonl is not the only copy of those records.
  # SPEC 3.4: it is the union of the per-pass deltas.jsonl files, written in the
  # same call. A record that reaches one and not the other is a record the
  # session never applied.
  build_partial_session

  forge "$(sess findings.json)" '
    const seed = JSON.parse(JSON.stringify(d.findings[0]));
    seed.id = "f-0099";
    seed.unit = "screen.onboarding.welcome";
    seed.title = "A finding invented to close the coverage gate";
    seed.createdInPass = 1;
    seed.lastTouchedPass = 1;
    seed.history = [];
    d.findings.push(seed);
  '
  forge_ledger '
    const body = {};
    for (const k of ["unit","title","detail","dimension","score","severity","confidence","effort","evidence","recommendation","status"]) {
      body[k] = k === "unit" ? "screen.onboarding.welcome"
        : k === "title" ? "A finding invented to close the coverage gate"
        : L[1].finding[k];
    }
    L.push({ pass: 1, op: "add", perspective: null, why: "Pass 1 appraisal against the lens rubric.", at: new Date().toISOString(), source: "grade", id: "f-0099", finding: body });
    return L;
  '

  every_decision_point_refuses 'a ledger line with no matching pass record'
  run_ponder verify --session "$SLUG"
  assert_imatch "$ALL" 'deltas.jsonl' 'the diagnosis names the per-pass file that is missing the record'
  assert_contains "$ALL" 'SPEC 3.4' 'and cites the invariant it broke'
}

t_reconcile_an_unwritable_record_is_caught() {
  # The cheapest forgery the two copies cannot catch on their own.
  #
  # `unit-edit` may set label, path, kind and meta, and NOTHING else — `id`
  # above all, because it is the join key to findings.json (SPEC 3.4). A replay
  # ignores an unsettable field, so a forged unit-edit that sets one derives the
  # state that is already on disk: no divergence, and no state file has to be
  # touched at all. Written into ledger.jsonl AND the matching passes/NN file,
  # it costs two edits, not the three SPEC 3.6 names as the bar — and report.md
  # then prints the correction as something the session did.
  #
  # So the record itself is checked, not only what replaying it derives: a
  # record the engine refuses to write is not a record the engine wrote.
  build_partial_session

  run_ponder verify --session "$SLUG"
  assert_status 0 'the session is honest before the forgery'

  _forged='{"pass":1,"op":"unit-edit","target":"screen.settings.billing","set":{"id":"screen.settings.forged"},"perspective":"builder","why":"A forged correction the engine would never have applied.","at":"2026-01-01T00:00:00.000Z"}'
  printf '%s\n' "$_forged" >> "$(sess ledger.jsonl)"
  printf '%s\n' "$_forged" >> "$(pass_dir 1)/deltas.jsonl"

  every_decision_point_refuses 'a unit-edit setting a field the engine refuses to set'
  run_ponder verify --session "$SLUG"
  assert_contains "$ALL" 'ledger.jsonl' 'the diagnosis says the problem is inside the ledger itself'
  assert_contains "$ALL" '"id"' 'and names the field that could never have been set'
  assert_imatch "$ALL" 'not a settable unit field' 'and says why that record is impossible'

  # And the honest ops are untouched: every settable field still replays clean.
  forge_ledger 'return L.slice(0, -1);'
  _pd="$(pass_dir 1)/deltas.jsonl"
  "$NODE" -e '
    const fs = require("fs");
    const p = process.argv[1];
    const L = fs.readFileSync(p, "utf8").trim().split("\n").filter(Boolean);
    L.pop();
    fs.writeFileSync(p, L.join("\n") + "\n");
  ' "$_pd"
  run_ponder verify --session "$SLUG"
  assert_status 0 'and the session reconciles again once the impossible record is gone'
}

t_reconcile_rewriting_the_ledger_is_caught() {
  # ledger.jsonl is append-only (SPEC 3.4). Three ways to rewrite it anyway,
  # none of which append anything, so none of which a replay-only reconciler
  # could see as a contradiction:
  #   - reorder it, so replay derives a different answer from the same records;
  #   - truncate it, so the last pass's work stops being on the record;
  #   - delete the pass directory it is supposed to be the union of.
  build_partial_session
  _sdir="$WORK/.ponder/$SLUG"
  _snapshot="$SUITE_TMP/honest-session"
  rm -rf "$_snapshot"
  cp -R "$_sdir" "$_snapshot"
  _restore() { rm -rf "$_sdir"; cp -R "$_snapshot" "$_sdir"; }

  run_ponder verify --session "$SLUG"
  ok 'the snapshot is of an honest session'

  # 1. reorder: move the last record to the front, changing nothing else.
  forge_ledger 'const last = L.pop(); L.unshift(last); return L;'
  every_decision_point_refuses 'a reordered ledger'
  _restore

  # 2. truncate: drop the last three records.
  forge_ledger 'return L.slice(0, -3);'
  every_decision_point_refuses 'a truncated ledger'
  _restore

  # 3. delete the pass directory the ledger is the union of.
  rm -rf "$(pass_dir 1)"
  every_decision_point_refuses 'a deleted pass directory'
  _restore

  run_ponder verify --session "$SLUG"
  ok 'and the honest session still verifies once it is put back'
}

t_reconcile_the_union_is_reported_on_an_honest_session() {
  # The check has to be visible when it passes, not only when it fires: an
  # agent reading `ponder verify` should be able to see that both copies were
  # compared and how many records that was.
  new_workdir unionreport
  p_start --max-passes 6 --min-passes 2; ok 'start'
  pass_one "$FIXTURES/findings-full.json" deltas-pass1.jsonl

  run_ponder verify --session "$SLUG" --json
  ok 'verify exits 0'
  _lr=$(jout 'String(d.counts.records)')
  _pr=$(jout 'String(d.counts.passRecords)')
  assert_eq "$_lr" "$_pr" 'every ledger record is also in a per-pass deltas.jsonl (SPEC 3.4)'
  assert_eq '0' "$(jout 'String(d.unionProblems.length)')" 'and the two copies agree'

  run_ponder verify --session "$SLUG"
  ok 'verify exits 0 in text mode too'
  assert_imatch "$ALL" 'per-pass delta' 'and says out loud that both copies were compared'
}

t_reconcile_repair_restores_a_crashed_session() {
  # SPEC 3.6, write ordering. Every state change appends to ledger.jsonl BEFORE it
  # writes units.json, findings.json or the pass's deltas.jsonl, so the only crash
  # state reachable is a ledger that is ahead of its own view. This test produces
  # exactly that state — apply a batch, then rewind everything except the ledger to
  # what it was a moment before — and pins that `ponder verify --repair` rebuilds it.
  new_workdir repair
  p_start --max-passes 6 --min-passes 1; ok 'start'
  p_predict 0.4 'Pass 1 grades all three screens.'; ok 'predict'
  p_units; ok 'units'
  p_grade "$FIXTURES/findings-full.json"; ok 'grade'
  p_deliberate; ok 'deliberate'

  _fid=$(finding_id 1)
  cat > "$WORK/crashy.jsonl" <<EOF
{"op":"unit-edit","target":"screen.settings.profile","perspective":"builder","why":"Pass 1's caption for profile was copied off the billing screen by mistake.","set":{"label":"Settings > Profile (display name form)","meta":{"state":"corrected"}}}
{"op":"add","perspective":"dreamer","why":"No pass had looked at the welcome screen's loading state as a set.","finding":{"unit":"screen.onboarding.welcome","title":"Welcome has no loading state","detail":"The screen renders nothing at all while the plan list is in flight.","dimension":"loading-states","score":2,"severity":"must","confidence":0.8,"effort":"s","evidence":["src/routes/onboarding/welcome.tsx:1"],"recommendation":"Render a skeleton while the plan list loads."}}
{"op":"change","target":"$_fid","perspective":"empath","why":"This one blocks first run, so it outranks the polish items below it.","set":{"severity":"must","score":2}}
{"op":"delete","target":"$(finding_id 2)","perspective":"skeptic","why":"Duplicate of the finding above it; same unit, same dimension, weaker evidence."}
EOF

  # Snapshot the state files and the pass file as they stand BEFORE the batch.
  _pre="$WORK/pre"; mkdir -p "$_pre"
  cp "$(sess units.json)" "$_pre/units.json"
  cp "$(sess findings.json)" "$_pre/findings.json"
  _pd="$(pass_dir 1)/deltas.jsonl"
  _pd_lines=$(jlines "$_pd")

  run_ponder delta --session "$SLUG" --file "$WORK/crashy.jsonl"
  ok 'the batch applies cleanly'

  # Keep what the engine actually wrote, so the repair can be compared against it.
  _truth="$WORK/truth"; mkdir -p "$_truth"
  cp "$(sess units.json)" "$_truth/units.json"
  cp "$(sess findings.json)" "$_truth/findings.json"
  cp "$_pd" "$_truth/deltas.jsonl"

  # THE CRASH: the ledger append landed, nothing after it did.
  cp "$_pre/units.json" "$(sess units.json)"
  cp "$_pre/findings.json" "$(sess findings.json)"
  head -n "$_pd_lines" "$_truth/deltas.jsonl" > "$_pd"

  run_ponder verify --session "$SLUG"
  assert_status 2 'a crashed session does not reconcile — the ledger is ahead of its view'
  assert_imatch "$ALL" 'does not reconcile' 'and says so'

  # The loop refuses to draw a conclusion from it, exactly as SPEC 3.6 requires.
  run_ponder judge --session "$SLUG"
  assert_status 2 'judge refuses the crashed session'
  run_ponder report --session "$SLUG"
  assert_status 2 'report refuses it too'

  run_ponder verify --session "$SLUG" --repair
  ok 'ponder verify --repair rebuilds a ledger-ahead session (SPEC 3.6)'
  assert_imatch "$ALL" 'repaired from the ledger' 'and says what it did'
  assert_contains "$ALL" 'units.json' 'naming units.json'
  assert_contains "$ALL" 'findings.json' 'naming findings.json'
  assert_contains "$ALL" 'deltas.jsonl' 'and the pass delta file it caught up'

  # The repaired session is the session the interrupted command would have written.
  for f in units.json findings.json; do
    if cmp -s "$_truth/$f" "$(sess "$f")"; then
      _assert_pass
    else
      _assert_fail "$f after --repair is not what the engine wrote before the crash
$(diff "$_truth/$f" "$(sess "$f")" 2>&1 | head -12 | sed 's/^/          | /')"
    fi
  done
  if cmp -s "$_truth/deltas.jsonl" "$_pd"; then
    _assert_pass
  else
    _assert_fail 'passes/01/deltas.jsonl after --repair is not what the engine wrote'
  fi

  run_ponder verify --session "$SLUG"
  ok 'and the repaired session reconciles on its own'

  # It is a repaired session, not a museum piece: the loop carries on from here.
  p_judge_json; ok 'judge runs on the repaired session'
  assert_close "$(metric 1 coverage)" 1 0.0001 'with the coverage the ledger says it has'
  run_ponder decide stop --session "$SLUG" --why 'Every screen is graded and the session is whole again.'
  ok 'and the session can still be closed'

  # --repair on a healthy session is a no-op that says so.
  run_ponder verify --session "$SLUG" --repair
  ok '--repair on a session that already reconciles exits 0'
  assert_imatch "$ALL" 'nothing to repair' 'and says there was nothing to do'
}

t_reconcile_repair_refuses_state_ahead_of_the_ledger() {
  # The asymmetry that makes the write ordering worth having. A ledger-ahead session
  # is rebuildable because every record determines what the files must hold. State
  # ahead of the ledger exists in exactly one copy, so nothing can rebuild it — and
  # it is indistinguishable from the forgery SPEC 3.6 exists to catch. Hard error.
  build_partial_session

  forge "$(sess findings.json)" '
    d.findings.push({ id: "f-9999", unit: "screen.settings.profile", title: "Invented",
      detail: "", dimension: null, score: 3, severity: "note", confidence: 0.9,
      effort: "s", evidence: [], recommendation: "", status: "open",
      createdInPass: 1, lastTouchedPass: 1, history: [] });
  '
  run_ponder verify --session "$SLUG" --repair
  assert_status 2 'a finding no ledger record created is not repairable (SPEC 3.6)'
  assert_imatch "$ALL" 'cannot rebuild' 'and --repair says it cannot'
  assert_imatch "$ALL" 'ahead of the ledger' 'naming the shape of the problem'
  assert_imatch "$ALL" 'no other copy|nothing can rebuild' 'and why nothing can fix it'
  assert_contains "$ALL" 'f-9999' 'and which record'
  assert_eq 'true' "$(jget "$(sess findings.json)" 'String(d.findings.some(f => f.id === "f-9999"))')" \
    'the refused repair changed nothing'

  # A unit invented in units.json is refused the same way.
  build_partial_session
  forge "$(sess units.json)" '
    d.units.push({ id: "screen.invented.one", label: "Invented", path: null,
      kind: "screen", meta: {}, addedInPass: 1 });
  '
  run_ponder verify --session "$SLUG" --repair
  assert_status 2 'a unit no ledger record enumerated is not repairable either'
  assert_contains "$ALL" 'screen.invented.one' 'and the refusal names it'

  # A ledger that contradicts itself is nothing to rebuild FROM.
  build_partial_session
  forge_ledger 'L.push({ pass: 1, op: "change", target: "f-4242", perspective: "empath", why: "A revision of a finding no add record ever created.", set: { severity: "must" } }); return L;'
  run_ponder verify --session "$SLUG" --repair
  assert_status 2 'a ledger that contradicts itself cannot be repaired from'
  assert_imatch "$ALL" 'cannot rebuild' 'and --repair says so'
  assert_imatch "$ALL" 'contradicts itself' 'naming the ledger as the broken side'
  assert_imatch "$ALL" 'nothing to rebuild' \
    'because repair rebuilds from the ledger and this one does not describe a session'
}

t_reconcile_the_ledger_is_written_before_the_state_files() {
  # SPEC 8.9. The ordering is the whole reason --repair can exist, so it is pinned
  # directly rather than inferred from the repair working: after every state-changing
  # command, the ledger must already account for everything the state files hold.
  new_workdir writeorder
  p_start --max-passes 6 --min-passes 1; ok 'start'
  p_predict 0.4 'Pass 1 grades all three screens.'; ok 'predict'

  # After `units`, the seed record is on the ledger and units.json matches it.
  p_units; ok 'units'
  assert_eq 'true' "$(jl "$(sess ledger.jsonl)" 'String(d.some(x => x.op === "unit-seed"))')" \
    'ponder units puts the inventory on the ledger'
  run_ponder verify --session "$SLUG"
  ok 'and the session reconciles the moment units.json exists'

  p_grade "$FIXTURES/findings-full.json"; ok 'grade'
  run_ponder verify --session "$SLUG"
  ok 'and again once findings.json exists'
  assert_eq "$(jget "$(sess findings.json)" 'd.findings.length')" \
    "$(jl "$(sess ledger.jsonl)" 'd.filter(x => x.op === "add").length')" \
    'every finding on disk has an add record behind it (SPEC 3.4)'

  p_deliberate; ok 'deliberate'
  p_delta deltas-pass1.jsonl; ok 'delta'
  run_ponder verify --session "$SLUG"
  ok 'and after a delta batch too'
  assert_eq "$(jlines "$(sess ledger.jsonl)")" "$(pass_delta_lines 1)" \
    'the pass delta file is exactly the ledger for a one-pass session (SPEC 3.4)'
}

# ----------------------------------------------------------------- metrics ---

# build_thrash_session <min-passes> — pass 1 raises a severity, pass 2 lowers it,
# pass 3 raises it back. That last one is a reversal under SPEC 4.
build_thrash_session() {
  new_workdir thrash
  p_start --max-passes 8 --min-passes "$1"
  ok 'start'
  pass_one "$FIXTURES/findings-tiny.json" deltas-thrash-must.jsonl
  p_judge; ok 'pass 1 judge'
  p_decide continue 'Pass 1 only re-ranked a single finding.'
  ok 'pass 1 decide'

  later_pass deltas-thrash-should.jsonl 0.3 'Pass 2 revisits the severity pass 1 raised.' || return 1
  p_judge; ok 'pass 2 judge'
  p_decide continue 'Still arguing about the same severity, keep going.'
  ok 'pass 2 decide'

  later_pass deltas-thrash-must.jsonl 0.3 'Pass 3 puts the severity back where pass 1 had it.' || return 1
  p_judge_json
  ok 'pass 3 judge'
}

t_metrics_thrash_escalates() {
  build_thrash_session 2 || return 0
  assert_gt "$(metric 3 thrash)" '0.25' 'an oscillating pass exceeds the thrash threshold (SPEC 4)'
  assert_eq 'escalate' "$JUDGE_VERDICT" 'thrash above 0.25 escalates (SPEC 4.1 rule 3)'
  assert_close "$(metric 3 coverage)" 1 0.0001 'coverage was complete, so rule 1 did not fire first'
  assert_imatch "$OUT" 'escalate' 'the judge output reports the escalation'
}

t_metrics_thrash_zero() {
  build_converged_session || return 0
  assert_close "$(metric 2 thrash)" 0 0.0001 'a pass that reverses nothing reports thrash 0'
  assert_close "$(metric 3 thrash)" 0 0.0001 'still zero on the converging pass'
  assert_close "$(metric 3 novelty)" 0 0.0001 'a pass with no add delta reports novelty 0'
  assert_gt "$(metric 3 churn)" '0' 'a pass with one delta reports churn above 0'
}

t_metrics_stall_and_floor_present() {
  build_converged_session || return 0
  assert_close "$(metric 3 confidenceFloor)" 0 0.0001 \
    'no open must-finding is a guess, so the confidence floor is 0 (SPEC 4)'
  assert_le "$(metric 3 stall)" '1' 'no pass was quiet enough to count as a stall'
  # SPEC 4: voices counts who spoke in the deliberation, not who emitted a delta. All four
  # argue on the converging pass; only one of them has anything left to change.
  assert_eq '4' "$(metric 3 voices)" 'the converging pass heard all four perspectives'
  assert_eq '1' "$(metric 3 deltaVoices)" 'and exactly one of them emitted a delta'
}

# ---------------------------------------------------------------- verdicts ---

t_verdict_order_coverage_beats_budget() {
  # Rule 1 (blocked) must win over rule 7 (budget stop) on the same pass.
  new_workdir order1
  p_start --max-passes 2 --min-passes 1
  ok 'start'
  pass_one "$FIXTURES/findings-partial.json" deltas-one-edit.jsonl
  p_judge_json; ok 'pass 1 judge'
  assert_eq 'blocked' "$JUDGE_VERDICT" 'rule 1 outranks rule 2 on pass 1'
  p_decide continue 'Coverage is short, so continue rather than stop.'
  ok 'pass 1 decide'

  later_pass deltas-one-edit.jsonl 0.2 'Pass 2 with the budget already spent.' || return 0
  p_judge_json; ok 'pass 2 judge'
  assert_eq '2' "$(pass_now)" 'the session is at maxPasses'
  assert_eq 'blocked' "$JUDGE_VERDICT" \
    'rule 1 outranks rule 7: an incomplete session at maxPasses is blocked, not stopped'
  assert_ne 'budget' "$JUDGE_REASON" 'the budget reason does not appear while coverage is short'

  run_ponder decide stop --session "$SLUG" --why 'The budget is spent, let me out of here.'
  assert_status 2 'the budget does not unlock the coverage gate'
  assert_eq 'open' "$(status_now)" 'the session is still open'
}

t_verdict_order_minpasses_beats_thrash() {
  # Rule 2 (continue) must win over rule 3 (escalate) on the same pass.
  build_thrash_session 4 || return 0
  assert_gt "$(metric 3 thrash)" '0.25' 'the session really is thrashing'
  assert_eq 'continue' "$JUDGE_VERDICT" \
    'rule 2 outranks rule 3: below minPasses the advice is continue, not escalate'
}

t_verdict_minpasses_blocks_convergence() {
  # Perfect metrics on pass 1 must still not converge.
  new_workdir minpasses
  p_start --max-passes 6 --min-passes 2
  ok 'start'
  pass_one "$FIXTURES/findings-full.json" deltas-pass2.jsonl
  p_judge_json; ok 'judge'
  assert_close "$(metric 1 coverage)" 1 0.0001 'coverage is complete, so rule 1 cannot be what fires'
  assert_eq 'null' "$(metric_json 1 thrash)" \
    'pass 1 has no thrash at all, so rule 3 cannot be what fires (SPEC 4)'
  assert_close "$(metric 1 confidenceFloor)" 0 0.0001 'no important finding is a guess, so rule 5 cannot fire'
  assert_eq '0' "$(metric 1 stall)" 'there is no history to stall against'
  assert_eq 'continue' "$JUDGE_VERDICT" 'pass 1 cannot converge (SPEC 4.1 rule 2)'
  assert_ne 'stop' "$JUDGE_VERDICT" 'pass 1 is never advised to stop'
  assert_ne 'converged' "$JUDGE_REASON" 'pass 1 is never reported as converged'
}

t_verdict_budget_not_convergence() {
  new_workdir budget
  p_start --max-passes 2 --min-passes 1
  ok 'start'
  pass_one "$FIXTURES/findings-full.json" deltas-pass1.jsonl
  p_judge; ok 'pass 1 judge'
  p_decide continue 'One more pass before the budget runs out.'
  ok 'pass 1 decide'

  later_pass deltas-pass2-wide.jsonl 0.3 'Pass 2 still has plenty to move.' || return 0
  p_judge_json; ok 'pass 2 judge'

  assert_eq '2' "$(pass_now)" 'the session reached maxPasses'
  assert_close "$(metric 2 coverage)" 1 0.0001 'coverage is complete, so the gate is not what stopped it'
  assert_gt "$(metric 2 churn)" '0.10' 'the pass was still moving, so rule 6 cannot claim convergence'
  assert_eq 'stop' "$JUDGE_VERDICT" 'reaching maxPasses stops the loop (SPEC 4.1 rule 7)'
  assert_eq 'budget' "$JUDGE_REASON" 'the stop is reported as a budget stop'
  assert_ne 'converged' "$JUDGE_REASON" 'a budget stop is never reported as convergence'
}

# --------------------------------------------------------------- overrides ---

t_override_why_length() {
  new_workdir override1
  p_start --max-passes 6 --min-passes 2
  ok 'start'
  pass_one "$FIXTURES/findings-full.json" deltas-pass1.jsonl
  p_judge_json; ok 'judge'
  assert_eq 'continue' "$JUDGE_VERDICT" 'the advice is continue, so stopping is an override'

  run_ponder decide stop --session "$SLUG" --why 'too short'
  assert_status 1 'an override with a 9-character why is rejected (SPEC 4.2)'
  assert_eq 'open' "$(status_now)" 'the rejected override left the session open'

  run_ponder decide stop --session "$SLUG" --why 'eleven char'
  assert_status 1 'an override with an 11-character why is still rejected'
  assert_eq 'open' "$(status_now)" 'the session is still open'

  run_ponder decide stop --session "$SLUG" --why 'twelve chars'
  ok 'an override with a 12-character why is accepted'
  assert_ne 'open' "$(status_now)" 'the accepted override closed the session'
}

t_override_lands_in_report() {
  new_workdir override2
  _why='Shipping now: the remaining screens are cosmetic and the deadline is real.'
  p_start --max-passes 6 --min-passes 2
  ok 'start'
  pass_one "$FIXTURES/findings-full.json" deltas-pass1.jsonl
  p_judge_json; ok 'judge'
  assert_eq 'continue' "$JUDGE_VERDICT" 'the advice is continue'

  run_ponder decide stop --session "$SLUG" --why "$_why"
  ok 'the override is accepted'
  assert_contains "$(cat "$(pass_dir 1)/verdict.json")" "$_why" \
    'the reason is written to verdict.json (SPEC 4.2)'

  run_ponder report --session "$SLUG"
  ok 'report exits 0'
  _r=$(cat "$(sess report.md)")
  assert_imatch "$_r" '^#+[[:space:]]*overrides' 'report.md has an Overrides section (SPEC 4.2)'
  assert_contains "$_r" "$_why" 'the override reason is surfaced permanently in the report'
}

# -------------------------------------------------------------------- json ---

t_json_every_command() {
  JSON_FLAG='--json'
  new_workdir json

  run_ponder doctor --json;  ok 'doctor --json';  assert_json_stdout 'doctor --json'
  assert_json_next 'doctor --json'
  p_start --max-passes 6 --min-passes 2; ok 'start --json'
  run_ponder status --session "$SLUG" --json; ok 'status --json'; assert_json_stdout 'status --json'
  assert_json_next 'status --json'
  run_ponder list --json;    ok 'list --json';    assert_json_stdout 'list --json'
  assert_json_next 'list --json'

  pass_one "$FIXTURES/findings-full.json" deltas-pass1.jsonl
  p_judge; ok 'judge --json'
  p_decide continue 'Coverage is complete but one pass is an opinion.'
  ok 'decide --json'

  later_pass deltas-pass2.jsonl 0.1 'Pass 2 sharpens recommendations only.' || { JSON_FLAG=''; return 0; }
  p_judge; ok 'pass 2 judge --json'
  p_decide stop 'Stopping here with a deliberate override of the advice.'
  ok 'decide stop --json'

  run_ponder report --session "$SLUG" --json; ok 'report --json'; assert_json_stdout 'report --json'
  assert_json_next 'report --json'
  run_ponder apply --session "$SLUG" --dry-run --json; ok 'apply --dry-run --json'
  assert_json_stdout 'apply --json'
  assert_json_next 'apply --dry-run --json'
  run_ponder apply --session "$SLUG" --json; ok 'apply --json'; assert_json_stdout 'apply --json'

  # A second session so abort --json has something to close.
  SLUG='ui-conformance-2'
  p_start --max-passes 6 --min-passes 2; ok 'second start --json'
  run_ponder abort --session "$SLUG" --why 'Aborting to exercise the JSON output path.' --json
  ok 'abort --json'
  assert_json_stdout 'abort --json'
  assert_json_next 'abort --json'

  # Failure is a machine-readable outcome too. An agent driving with --json only
  # reads stdout, so a refusal that arrives as bare prose is a refusal it cannot
  # parse — and the NEXT phase has to survive into it (SPEC 8.6).
  run_ponder judge --session "$SLUG" --json
  assert_status_not 0 'judge on an aborted session fails'
  assert_json_stdout 'a failing judge --json still emits JSON on stdout'
  assert_json_next 'a failing judge --json still names the next phase'
  assert_eq 'false' "$(jout 'String(d.ok)')" 'the JSON failure payload marks itself failed'
  assert_eq '' "$ERR" 'a --json failure puts nothing on stderr either'

  JSON_FLAG=''
}

# -------------------------------------------------------------------- next ---

t_next_line_everywhere() {
  new_workdir next
  run_ponder doctor;  ok 'doctor';  assert_next 'doctor'
  run_ponder list;    ok 'list';    assert_next 'list'
  p_start --max-passes 6 --min-passes 2; ok 'start'; assert_next 'start'
  run_ponder status --session "$SLUG"; ok 'status'; assert_next 'status'

  p_predict 0.4 'Pass 1 inventories the screens.'; ok 'predict'; assert_next 'predict'
  p_units;      ok 'units';      assert_next 'units'
  p_grade "$FIXTURES/findings-full.json"; ok 'grade'; assert_next 'grade'
  p_deliberate; ok 'deliberate'; assert_next 'deliberate'
  p_delta deltas-pass1.jsonl; ok 'delta'; assert_next 'delta'
  p_judge;      ok 'judge';      assert_next 'judge'

  # Errors owe a NEXT line too: that line is what survives compaction.
  run_ponder delta --session "$SLUG" --file "$FIXTURES/deltas-one-edit.jsonl"
  assert_status 2 'delta out of order'
  assert_next 'an out-of-order command still prints NEXT'

  p_decide continue 'Coverage is complete but one pass is an opinion.'
  ok 'decide'; assert_next 'decide'

  later_pass deltas-pass2.jsonl 0.1 'Pass 2 sharpens recommendations only.' || return 0
  p_judge; ok 'pass 2 judge'
  p_decide stop 'Stopping here with a deliberate override of the advice.'
  ok 'decide stop'
  run_ponder report --session "$SLUG"; ok 'report'; assert_next 'report'
  run_ponder apply --session "$SLUG" --dry-run; ok 'apply'; assert_next 'apply'
}

# --------------------------------------------------------------- exit codes --

t_exit_codes() {
  new_workdir exits
  run_ponder doctor
  assert_status 0 'exit 0 on success'

  run_ponder frobnicate
  assert_status 1 'an unknown command is a user error'

  run_ponder start
  assert_status 1 'start without a subject is a user error'

  run_ponder start "$SUBJECT" --lens ui --project "$WORK" --slug "$SLUG"
  ok 'start'

  run_ponder status --session no-such-session
  assert_status 1 'an unknown session is a user error'

  run_ponder predict --session "$SLUG" --churn 5 --claim 'Churn out of range.'
  assert_status 1 'a churn outside 0-1 is a user error'

  run_ponder judge --session "$SLUG"
  assert_status 2 'a command out of phase is a state violation'

  # Walk to the appraise phase so the only fault left is the missing file.
  run_ponder predict --session "$SLUG" --churn 0.4 --claim 'Pass 1 inventories the screens.'
  ok 'predict'
  run_ponder units --session "$SLUG" --file "$WORK/units.json"
  ok 'units'
  run_ponder grade --session "$SLUG" --file "$WORK/does-not-exist.json"
  assert_status 1 'a missing --file is a user error, not a state violation'
}

# --------------------------------------------------------------------- OCA ---

# fake_psql <body> — put a stub psql at the front of PATH for one test.
fake_psql() {
  mkdir -p "$WORK/fakebin"
  printf '#!/bin/sh\n%s\n' "$1" > "$WORK/fakebin/psql"
  chmod +x "$WORK/fakebin/psql"
  PATH="$WORK/fakebin:$PATH"
  export PATH
}

t_oca_off_is_inert() {
  new_workdir ocaoff
  _marker="$WORK/psql-was-called"
  fake_psql "printf 'called\n' >> \"$_marker\"; exit 0"
  export PONDER_OCA=off

  p_start --max-passes 6 --min-passes 2; ok 'start with the bridge off'
  pass_one "$FIXTURES/findings-full.json" deltas-pass1.jsonl
  p_judge; ok 'judge with the bridge off'
  p_decide continue 'Coverage is complete but one pass is an opinion.'
  ok 'decide with the bridge off'
  run_ponder status --session "$SLUG"; ok 'status with the bridge off'
  run_ponder list; ok 'list with the bridge off'

  assert_no_file "$_marker" 'no loop command shells out to psql when the bridge is off (SPEC 6)'

  # doctor is the one command whose job is to report on the environment, so it
  # may look for psql. It still may not open a connection.
  run_ponder doctor; ok 'doctor with the bridge off'
  if [ -f "$_marker" ]; then
    assert_no_match "$(cat "$_marker")" '(postgres(ql)?://|[[:space:]]-c[[:space:]]|--command|--dbname|[[:space:]]-d[[:space:]])' \
      'doctor may check that psql exists but must not connect while the bridge is off'
  else
    _assert_pass
  fi
  assert_eq 'false' "$(jget "$(sess session.json)" 'String(!!(d.oca && d.oca.enabled))')" \
    'the session records the bridge as disabled'

}

t_oca_dead_dsn_degrades() {
  new_workdir ocadead
  export PONDER_OCA=auto
  export PONDER_OCA_DSN='postgres://127.0.0.1:59999/nope'

  _t0=$(date +%s)
  run_ponder_limit 20 start "$SUBJECT" --lens ui --project "$WORK" --slug "$SLUG" \
    --max-passes 6 --min-passes 2
  assert_status 0 'start survives an unreachable database (SPEC 6, SPEC 8.4)'
  assert_eq '0' "$TIMED_OUT" 'start did not hang'
  assert_le "$ELAPSED" '10' 'start finished inside the probe budget'

  for c in "predict --churn 0.4 --claim A-pass-that-does-not-need-the-bridge." \
           "units --file $WORK/units.json" \
           "grade --file $FIXTURES/findings-full.json" \
           "deliberate --file $WORK/deliberation.json"; do
    # shellcheck disable=SC2086
    run_ponder_limit 20 $c --session "$SLUG"
    assert_status 0 "\`$c\` survives an unreachable database"
    assert_eq '0' "$TIMED_OUT" "\`$c\` did not hang"
    assert_le "$ELAPSED" '10' "\`$c\` finished quickly"
  done

  run_ponder_limit 20 delta --session "$SLUG" --file "$(delta_file deltas-pass1.jsonl)"
  assert_status 0 'delta survives an unreachable database'
  run_ponder_limit 20 judge --session "$SLUG"
  assert_status 0 'judge survives an unreachable database'
  assert_le "$ELAPSED" '10' 'judge finished quickly despite the dead bridge'
  run_ponder_limit 20 decide continue --session "$SLUG" --why 'The bridge is dead and the loop does not care.'
  assert_status 0 'decide survives an unreachable database'

  _total=$(( $(date +%s) - _t0 ))
  assert_le "$_total" '60' 'the whole session finished without hanging'
  assert_eq '1' "$(jget "$(sess findings.json)" 'd.findings.length > 0 ? 1 : 0')" \
    'the engine did its own work regardless of the bridge'

  export PONDER_OCA=off
  unset PONDER_OCA_DSN
}

t_oca_hanging_psql() {
  new_workdir ocahang
  fake_psql 'sleep 60'
  export PONDER_OCA=auto
  export PONDER_OCA_DSN='postgres://localhost/oneiro-test-should-not-matter'

  run_ponder_limit 25 start "$SUBJECT" --lens ui --project "$WORK" --slug "$SLUG" \
    --max-passes 6 --min-passes 2
  assert_eq '0' "$TIMED_OUT" 'a hanging psql cannot hold the engine open (SPEC 6.3)'
  assert_status 0 'start still succeeds with a hanging psql'
  assert_le "$ELAPSED" '15' 'the probe and call timeouts are enforced'

  run_ponder_limit 25 status --session "$SLUG"
  assert_eq '0' "$TIMED_OUT" 'status does not hang either'
  assert_status 0 'status still succeeds'

  export PONDER_OCA=off
  unset PONDER_OCA_DSN
}

t_oca_on_is_fatal() {
  new_workdir ocaon
  export PONDER_OCA=on
  export PONDER_OCA_DSN='postgres://127.0.0.1:59999/nope'

  run_ponder_limit 20 start "$SUBJECT" --lens ui --project "$WORK" --slug "$SLUG" \
    --max-passes 6 --min-passes 2
  assert_status_not 0 'PONDER_OCA=on with an unreachable database is a hard error (SPEC 6)'
  assert_eq '0' "$TIMED_OUT" 'the hard error arrives quickly'

  # SPEC 6 makes the hard error a property of the mode, not of `start`. Every command that
  # writes an OCA row has to refuse too — a `deliberate` that exits 0 under deliberate
  # coupling has silently dropped its `deliberations` row, which is the exact failure the
  # `on` mode exists to prevent. Build the session with the bridge off, then flip it on.
  export PONDER_OCA=off
  unset PONDER_OCA_DSN
  build_converged_session || return 0

  export PONDER_OCA=on
  export PONDER_OCA_DSN='postgres://127.0.0.1:59999/nope'

  # decide stop writes the `ponder_converged` episodic row (SPEC 6.1).
  run_ponder_limit 20 decide stop --session "$SLUG" --why 'Two quiet passes in a row; the answer stopped changing.'
  assert_status_not 0 'decide stop is fatal under PONDER_OCA=on with an unreachable OCA'
  assert_eq '0' "$TIMED_OUT" 'decide stop fails fast rather than hanging'

  # Read-only commands have no row to drop, so coupling must not take them out.
  run_ponder_limit 20 status --session "$SLUG"
  assert_status 0 'status still works under PONDER_OCA=on — it writes no OCA row'
  run_ponder_limit 20 apply --dry-run --session "$SLUG"
  assert_status 0 'apply --dry-run still works under PONDER_OCA=on — it writes nothing'

  # Close the session with the bridge off so the committed apply has something to act on.
  export PONDER_OCA=off
  unset PONDER_OCA_DSN
  run_ponder decide stop --session "$SLUG" --why 'Two quiet passes in a row; the answer stopped changing.'
  assert_status 0 'decide stop succeeds again once the bridge is off'

  export PONDER_OCA=on
  export PONDER_OCA_DSN='postgres://127.0.0.1:59999/nope'
  # A committed apply writes an episodic row (SPEC 5.2), so it is coupled.
  run_ponder_limit 20 apply --session "$SLUG"
  assert_status_not 0 'a committed apply is fatal under PONDER_OCA=on with an unreachable OCA'
  assert_eq '0' "$TIMED_OUT" 'apply fails fast rather than hanging'

  export PONDER_OCA=off
  unset PONDER_OCA_DSN
}

# `deliberate` needs its own fixture: build_converged_session drives past it. SPEC 6.1 puts
# a `deliberations` row at deliberate, so deliberate is coupled under `on`.
t_oca_on_blocks_deliberate() {
  new_workdir ocaondelib
  export PONDER_OCA=off
  p_start --max-passes 6 --min-passes 2
  ok 'start'
  p_predict 0.9 'Pass 1 builds the finding set from nothing.'
  p_units
  p_grade "$FIXTURES/findings-full.json"
  assert_eq 'deliberate' "$(phase_now)" 'the session is parked at deliberate'

  export PONDER_OCA=on
  export PONDER_OCA_DSN='postgres://127.0.0.1:59999/nope'
  run_ponder_limit 20 deliberate --session "$SLUG" --file "$WORK/deliberation.json"
  assert_status_not 0 'deliberate is fatal under PONDER_OCA=on with an unreachable OCA'
  assert_eq '0' "$TIMED_OUT" 'deliberate fails fast rather than hanging'
  assert_eq 'deliberate' "$(phase_now)" 'the refused deliberate did not advance the phase'

  run_ponder_limit 20 deliberate --session "$SLUG" --skip --why 'No time to argue this pass.'
  assert_status_not 0 'deliberate --skip is fatal too — it writes a deliberation_skipped observation'

  export PONDER_OCA=off
  unset PONDER_OCA_DSN
  run_ponder deliberate --session "$SLUG" --file "$WORK/deliberation.json"
  assert_status 0 'deliberate succeeds once the bridge is off'
}

# ------------------------------------------------------------------- apply ---

t_apply_never_touches_source() {
  build_converged_session || return 0
  p_decide stop 'Two quiet passes in a row; the answer stopped changing.'
  ok 'decide stop'

  _before="$SUITE_TMP/tree-before"
  _after="$SUITE_TMP/tree-after"
  hash_tree > "$_before"

  run_ponder apply --session "$SLUG" --dry-run
  ok 'apply --dry-run exits 0'
  hash_tree > "$_after"
  if cmp -s "$_before" "$_after"; then _assert_pass; else
    _assert_fail "apply --dry-run modified the project tree
$(diff "$_before" "$_after" | head -10 | sed 's/^/          | /')"
  fi
  assert_no_file "$(sess apply-plan.md)" 'apply --dry-run writes no plan file (SPEC 5.2)'
  assert_ne 'applied' "$(status_now)" 'apply --dry-run does not mark the session applied'

  run_ponder apply --session "$SLUG"
  ok 'apply exits 0'
  hash_tree > "$_after"
  if cmp -s "$_before" "$_after"; then _assert_pass; else
    _assert_fail "apply modified a file outside .ponder/ (SPEC 8.7)
$(diff "$_before" "$_after" | head -10 | sed 's/^/          | /')"
  fi
  assert_eq '1' "$(find "$WORK/.ponder" -name apply-plan.md | wc -l | tr -d ' ')" \
    'apply writes apply-plan.md inside .ponder/'
  assert_eq 'applied' "$(status_now)" 'apply marks the session applied (SPEC 5.2)'
}

t_apply_plan_content() {
  build_converged_session || return 0
  p_decide stop 'Two quiet passes in a row; the answer stopped changing.'
  ok 'decide stop'

  run_ponder apply --session "$SLUG" --dry-run
  ok 'apply --dry-run exits 0'
  assert_contains "$ALL" 'screen.settings.billing' 'the plan groups work by unit'
  assert_contains "$ALL" 'src/routes/settings/billing.tsx' 'the plan carries evidence paths'
  assert_contains "$ALL" 'Billing empty state is a bare string' 'the plan carries the must findings'
  assert_contains "$ALL" 'empty state' 'the plan carries the recommendations'
  assert_not_contains "$ALL" 'Failed card charge surfaces as a raw API string' \
    'a retracted finding never reaches the plan (SPEC 5.2 selects open findings)'
  assert_not_contains "$ALL" 'Profile copy uses passive voice throughout' \
    'the default severity is must, so a should finding is left out'

  run_ponder apply --session "$SLUG" --dry-run --severity must,should
  ok 'apply --severity must,should exits 0'
  assert_contains "$ALL" 'Billing empty state is a bare string' 'must findings are still selected'
  assert_contains "$ALL" 'Profile copy uses passive voice throughout' 'should findings join the plan'
  assert_not_contains "$ALL" 'Failed card charge surfaces as a raw API string' \
    'the retracted finding stays out at every severity'
}

# ---------------------------------------------------------------- lifecycle --

t_apply_refuses_an_aborted_session() {
  # SPEC 5.2 / SPEC 8.7: an abandoned pondering must not be able to quietly become an
  # applied one. This holds for --dry-run too — there is no plan to preview out of a
  # session nobody stood behind.
  new_workdir applyaborted
  p_start --max-passes 6 --min-passes 2; ok 'start'
  pass_one "$FIXTURES/findings-partial.json" deltas-one-edit.jsonl
  p_judge; ok 'judge'

  run_ponder abort --session "$SLUG" --why 'Two screens were never graded and will not be.'
  ok 'abort exits 0'
  assert_eq 'aborted' "$(status_now)" 'the session is aborted'

  run_ponder apply --session "$SLUG"
  assert_status 2 'apply on an aborted session is a state violation (SPEC 5.2)'
  assert_next 'the refusal still prints NEXT'
  assert_imatch "$ALL" 'abort' 'the refusal says the session was aborted'
  assert_eq 'aborted' "$(status_now)" 'the session is still aborted, never applied'
  assert_no_file "$(sess apply-plan.md)" 'and no plan was written'

  run_ponder apply --session "$SLUG" --dry-run
  assert_status 2 '--dry-run does not get a pass either'
  assert_eq 'aborted' "$(status_now)" 'still aborted'
  assert_no_file "$(sess apply-plan.md)" 'still no plan'

  # A stopped session is the contrast: that one applies.
  new_workdir applystopped
  p_start --max-passes 6 --min-passes 1; ok 'start'
  pass_one "$FIXTURES/findings-full.json" deltas-pass1.jsonl
  p_judge; ok 'judge'
  p_decide stop 'Coverage is complete and the set has settled.'
  ok 'decide stop'
  run_ponder apply --session "$SLUG"
  ok 'a stopped session still applies'
  assert_eq 'applied' "$(status_now)" 'and reaches the applied status'
}

t_mode_is_retracted() {
  # SPEC 3.1 / SPEC 8.8: there is exactly one mode. `--mode build` was documented and never
  # implemented; it is gone from the CLI, the session file and the report — not stubbed.
  new_workdir nomode
  run_ponder --help
  ok 'ponder --help exits 0'
  _help=$ALL
  run_ponder help start
  _help="$_help
$ALL"
  assert_not_contains "$_help" '--mode' 'no --mode flag is documented anywhere'
  assert_not_contains "$_help" 'deliberate|build' 'nor the mode vocabulary it used to offer'

  run_ponder start "$SUBJECT" --lens ui --project "$WORK" --slug "$SLUG" --mode build
  assert_status 1 '--mode build is an unknown flag, not a supported one'
  assert_imatch "$ALL" 'unknown flag' 'and is refused as such — no stub, no "coming soon"'
  assert_no_imatch "$ALL" 'coming soon|not yet|unsupported mode' 'nothing promises it later'
  assert_no_dir "$WORK/.ponder/$SLUG" 'the refused start created no session'

  run_ponder start "$SUBJECT" --lens ui --project "$WORK" --slug "$SLUG" --mode deliberate
  assert_status 1 'even the mode that used to be the default is gone'

  p_start; ok 'start without a mode works'
  assert_eq 'undefined' "$(jget "$(sess session.json)" 'typeof d.mode')" \
    'session.json has no mode field (SPEC 3.1)'

  # An older session that still carries the field is tolerated and ignored.
  "$NODE" -e '
    const fs = require("fs");
    const p = process.argv[1];
    const d = JSON.parse(fs.readFileSync(p, "utf8"));
    d.mode = "build";
    fs.writeFileSync(p, JSON.stringify(d, null, 2));
  ' "$(sess session.json)"
  run_ponder status --session "$SLUG"
  ok 'a session carrying a legacy mode field still loads'
  assert_no_imatch "$OUT" '^ *mode ' 'and status never reports a mode'

  pass_one "$FIXTURES/findings-full.json" deltas-pass1.jsonl
  p_judge; ok 'judge'
  p_decide stop 'Everything is graded; closing it to read the report.'
  ok 'decide stop'
  run_ponder report --session "$SLUG"
  ok 'report exits 0'
  assert_no_imatch "$(cat "$(sess report.md)")" '^\| *mode *\|' 'report.md has no Mode row (SPEC 3.1)'
}

t_metrics_pass_one_has_no_relative_signals() {
  # SPEC 4: novelty, churn, thrash and surprise are change measured against a previous
  # pass. Pass 1 has none, so they are null and render as an em dash — never as numbers
  # computed against the pass's own baseline.
  new_workdir passonenulls
  p_start --max-passes 6 --min-passes 2; ok 'start'
  pass_one "$FIXTURES/findings-full.json" deltas-pass1.jsonl
  p_judge; ok 'judge'

  for m in novelty churn thrash surprise; do
    assert_eq 'null' "$(metric_json 1 "$m")" "pass 1 emits null $m (SPEC 4)"
  done
  assert_eq '0' "$(metric_json 1 stall)" 'a pass with no churn cannot contribute to stall'
  assert_ne 'null' "$(metric_json 1 coverage)" 'coverage is absolute, so pass 1 has one'
  assert_ne 'null' "$(metric_json 1 confidenceFloor)" 'and so is the confidence floor'
  assert_ne 'null' "$(metric_json 1 voices)" 'and voices'
  assert_contains "$ALL" '—' 'human output renders the absent signals as an em dash'
  assert_no_match "$ALL" 'novelty +1\.00' 'never as the 1.00 a self-referential ratio produced'

  # And the verdict rules never read one: pass 1 advises continue on rule 2, not on a
  # threshold that a null quietly cleared.
  assert_eq 'continue' "$(jget "$(pass_dir 1)/verdict.json" 'd.verdict')" 'pass 1 advises continue'
  assert_eq 'min-passes' "$(jget "$(pass_dir 1)/verdict.json" 'd.reason')" \
    'on rule 2, not on a threshold a null quietly cleared (SPEC 4.1)'
  p_decide continue 'One pass is an opinion; the signals do not exist yet.'
  ok 'decide continue'

  # Pass 2 has a previous pass, so every signal comes back as a number.
  later_pass deltas-pass2.jsonl 0.2 'Pass 2 sharpens what pass 1 wrote down.' || return 0
  p_judge; ok 'pass 2 judge'
  for m in novelty churn thrash surprise; do
    assert_ne 'null' "$(metric_json 2 "$m")" "pass 2 has a real $m"
  done
}

t_metrics_seeding_is_excluded_from_the_ratios() {
  # SPEC 4: pass-1 seeding is tagged source:"grade" and excluded from the numerator of
  # every ratio in every pass. It is the baseline, not a revision of one — but it stays on
  # the ledger for provenance.
  new_workdir seedexcluded
  p_start --max-passes 6 --min-passes 2; ok 'start'
  pass_one "$FIXTURES/findings-full.json" deltas-pass1.jsonl
  p_judge; ok 'pass 1 judge'

  _seeded=$(jget "$(pass_dir 1)/metrics.json" 'd.deltas.seeded')
  _total=$(jget "$(pass_dir 1)/metrics.json" 'd.deltas.total')
  _revisions=$(jget "$(pass_dir 1)/metrics.json" 'd.deltas.revisions')
  assert_eq '12' "$_seeded" 'the twelve seeded findings are counted as seeded'
  assert_eq '4' "$_revisions" 'and the four deliberative deltas as revisions'
  assert_eq "$_total" "$((_seeded + _revisions))" 'seeded plus revisions is the whole pass'
  assert_eq "$_seeded" "$(jl "$(sess ledger.jsonl)" 'd.filter(x => x.source === "grade").length')" \
    'every seeded delta stays on the ledger, tagged (SPEC 4)'
  # SPEC 3.4: unit-seed is a seed, not a delta. It is on the ledger for reconciliation and
  # nowhere in the arithmetic — counting it would make seeded + revisions stop adding up.
  assert_eq '1' "$(jl "$(sess ledger.jsonl)" 'd.filter(x => x.op === "unit-seed").length')" \
    'the inventory seed is on the ledger'
  assert_eq "$((_total + 1))" "$(jlines "$(sess ledger.jsonl)")" \
    'and it is excluded from deltas.total (SPEC 3.4)'

  p_decide continue 'Coverage is complete but one pass is an opinion.'
  ok 'pass 1 decide'
  later_pass deltas-pass2.jsonl 0.2 'Pass 2 sharpens what pass 1 wrote down.' || return 0
  p_judge; ok 'pass 2 judge'
  assert_eq '0' "$(jget "$(pass_dir 2)/metrics.json" 'd.deltas.seeded')" 'pass 2 seeds nothing'

  # The proof: the pass-2 churn denominator is the live finding set, and its numerator is
  # the pass-2 deltas alone. Nothing from pass 1's seeding leaks into it.
  _live=$(jget "$(sess findings.json)" 'd.findings.filter(f => f.status !== "retracted").length')
  _rev2=$(jget "$(pass_dir 2)/metrics.json" 'd.deltas.revisions')
  assert_close "$(metric 2 churn)" \
    "$(awk -v a="$_rev2" -v b="$_live" 'BEGIN { print a / b }')" 0.001 \
    'churn is this pass revisions over live findings (SPEC 4)'
}

t_metrics_voices_counts_who_spoke() {
  # SPEC 4: voices counts distinct perspectives in the pass deliberation, not in its
  # deltas. Rule 6 caps churn below 0.10, which on a small set permits one delta — the old
  # measure forced voices == 1 and warned at every genuine convergence.
  build_converged_session || return 0

  assert_eq '4' "$(metric 3 voices)" 'all four perspectives spoke on the converging pass'
  assert_eq '1' "$(metric 3 deltaVoices)" 'exactly one of them emitted a delta'
  assert_eq 'true' "$(jget "$(pass_dir 3)/metrics.json" 'd.voiceNames.length === 4')" \
    'and metrics.json names all four'

  p_decide stop 'Two quiet passes in a row; the answer stopped changing.'
  ok 'decide stop on the converged verdict'
  assert_no_imatch "$ALL" 'heard [0-2] of 4|weak place to stop' \
    'a converging pass is not warned at for being quiet (SPEC 4.2)'
  assert_eq '0' "$(jget "$(pass_dir 3)/verdict.json" 'd.warnings.filter(w => /perspective/.test(w)).length')" \
    'and no voices warning is recorded against it'

  # The warning still fires where it should: a pass that never argued at all.
  new_workdir voicesskip
  p_start --max-passes 6 --min-passes 1; ok 'start'
  p_predict 0.4 'Pass 1 grades everything and skips the argument.'
  ok 'predict'
  p_units; ok 'units'
  p_grade "$FIXTURES/findings-full.json"; ok 'grade'
  run_ponder deliberate --session "$SLUG" --skip --why 'No time to run the four perspectives this pass.'
  ok 'deliberate --skip'
  p_delta deltas-pass1.jsonl; ok 'delta'
  p_judge; ok 'judge'
  assert_eq '0' "$(metric 1 voices)" 'a skipped deliberation heard nobody'
  assert_gt "$(metric 1 deltaVoices)" '0' 'even though deltas carried perspectives'
  run_ponder decide stop --session "$SLUG" --why 'Stopping after a pass that never argued with itself.'
  ok 'the stop is allowed'
  assert_imatch "$ALL" 'weak place to stop' 'but it warns (SPEC 4.2)'
}

t_oca_uses_only_the_sanctioned_enum_subset() {
  # SPEC 6.1: cognitive_events.event_type is a Postgres enum. The live enum carries 33
  # labels; ponder deliberately uses a sanctioned subset of seven. A label outside the enum
  # fails the insert; one inside it but outside the subset misfiles the row. Both are caught
  # statically, against the enum as it exists in the live OCA, so no database is needed here.
  new_workdir enumsubset
  _bridge="$REPO_ROOT/oca/bridge.js"
  assert_file "$_bridge" 'the OCA bridge is where the cognitive_events labels live'

  _bad=$("$NODE" -e '
    const fs = require("fs");
    // The 33 labels of postgres://localhost/oneiro cognitive_event_type, in enum order.
    const ENUM = ["perception_update","motor_command","motor_feedback","memory_store",
      "memory_retrieve","memory_retrieval_result","emotion_update","hypothesis_formed",
      "hypothesis_tested","simulation_result","metacognition_alert","deliberation_request",
      "deliberation_result","creative_output","attention_shift","goal_update",
      "workspace_broadcast","interrupt","body_ownership_request","body_ownership_grant",
      "reasoning_trace_created","causal_experiment_designed","causal_experiment_completed",
      "counterfactual_evaluated","semantic_reinforced","semantic_created",
      "semantic_contradicted","self_build","dream_executed","x_post","self_modification",
      "thinker.thought","thinker.proactive_intent"];
    const SANCTIONED = new Set(["deliberation_request","deliberation_result",
      "hypothesis_formed","hypothesis_tested","metacognition_alert",
      "reasoning_trace_created","workspace_broadcast"]);
    if (ENUM.length !== 33) { process.stdout.write("enum-list-is-not-33"); process.exit(0); }
    const src = fs.readFileSync(process.argv[1], "utf8");
    const bad = ENUM.filter((label) => !SANCTIONED.has(label) && src.includes("\u0027" + label + "\u0027"));
    process.stdout.write(bad.join(","));
  ' "$_bridge")
  assert_eq '' "$_bad" 'the bridge uses no enum label outside the sanctioned seven (SPEC 6.1)'

  # And every sanctioned label the bridge does use has to be a real member of the enum,
  # or the insert fails at runtime.
  _unknown=$("$NODE" -e '
    const fs = require("fs");
    const ENUM = new Set(["perception_update","motor_command","motor_feedback","memory_store",
      "memory_retrieve","memory_retrieval_result","emotion_update","hypothesis_formed",
      "hypothesis_tested","simulation_result","metacognition_alert","deliberation_request",
      "deliberation_result","creative_output","attention_shift","goal_update",
      "workspace_broadcast","interrupt","body_ownership_request","body_ownership_grant",
      "reasoning_trace_created","causal_experiment_designed","causal_experiment_completed",
      "counterfactual_evaluated","semantic_reinforced","semantic_created",
      "semantic_contradicted","self_build","dream_executed","x_post","self_modification",
      "thinker.thought","thinker.proactive_intent"]);
    const SANCTIONED = ["deliberation_request","deliberation_result","hypothesis_formed",
      "hypothesis_tested","metacognition_alert","reasoning_trace_created","workspace_broadcast"];
    const src = fs.readFileSync(process.argv[1], "utf8");
    const used = SANCTIONED.filter((l) => src.includes("\u0027" + l + "\u0027"));
    process.stdout.write(used.filter((l) => !ENUM.has(l)).join(",") + "|" + used.length);
  ' "$_bridge")
  assert_match "$_unknown" '^\|[1-9]' 'the bridge really does use labels from that subset, and none outside the enum'

  # SPEC.md must not claim the enum contains only those seven — it contains 33.
  _spec=$(cat "$REPO_ROOT/SPEC.md")
  assert_contains "$_spec" '33 labels' 'SPEC 6.1 states the real size of the live enum'
  assert_imatch "$_spec" 'subset' 'and calls the seven a deliberate subset of it'
  assert_not_contains "$_spec" 'Only these existing labels may be' \
    'the old claim that the enum holds only seven is gone'
}

t_lifecycle_abort() {
  new_workdir abort
  p_start --max-passes 6 --min-passes 2; ok 'start'
  p_predict 0.4 'Pass 1 inventories the screens.'; ok 'predict'

  run_ponder abort --session "$SLUG"
  assert_status 1 'abort without a why is a user error (SPEC 5)'

  run_ponder abort --session "$SLUG" --why 'The subject was wrong; starting again with a different lens.'
  ok 'abort exits 0'
  assert_next 'abort prints NEXT'
  assert_eq 'aborted' "$(status_now)" 'abort closes the session as aborted (SPEC 3.1)'
}

t_lifecycle_list_and_status() {
  new_workdir list
  p_start --max-passes 6 --min-passes 2; ok 'start'

  run_ponder list
  ok 'list exits 0'
  assert_contains "$ALL" "$SLUG" 'list names the session'
  assert_contains "$ALL" 'open' 'list reports the status'

  run_ponder status --session "$SLUG"
  ok 'status exits 0'
  assert_contains "$ALL" "$SLUG" 'status names the session'
  assert_contains "$ALL" 'predict' 'status names the phase owed'
  assert_imatch "$ALL" 'pass' 'status reports where the loop is in its passes'
}

t_lifecycle_default_session() {
  # SPEC 5: --session defaults to "the most recently touched open session in the
  # current project". With one session on disk every resolution rule looks
  # correct, so this needs three: an older one, a newer one, and then the newer
  # one closed so the fallback has to be visible.
  new_workdir defaultsess ui-older
  p_start --max-passes 6 --min-passes 2; ok 'start the older session'
  _older=$SLUG

  SLUG='ui-newer'
  p_start --max-passes 6 --min-passes 2; ok 'start the newer session'
  _newer=$SLUG

  run_ponder predict --churn 0.4 --claim 'Driving without naming the session.'
  ok 'predict resolves the default session'
  assert_eq 'survey' "$(jget "$WORK/.ponder/$_newer/session.json" 'd.phase')" \
    'the most recently touched session is the one that advanced'
  assert_eq 'predict' "$(jget "$WORK/.ponder/$_older/session.json" 'd.phase')" \
    'the older session was left exactly where it was'

  run_ponder abort --session "$_newer" --why 'Closing the newest session so the default has to fall back.'
  ok 'abort the newer session'

  run_ponder predict --churn 0.4 --claim 'The default should now fall back to the older session.'
  ok 'predict resolves the default again'
  assert_eq 'survey' "$(jget "$WORK/.ponder/$_older/session.json" 'd.phase')" \
    'a closed session is skipped: the default is the most recent *open* one (SPEC 5)'
  assert_eq 'aborted' "$(jget "$WORK/.ponder/$_newer/session.json" 'd.status')" \
    'the aborted session stayed aborted'
}

# ------------------------------------------------------------------- input ---
#
# The boring failures. Nothing in SPEC.md promises a well-formed file, a path
# without a space in it, or an agent that reads the usage line before typing.

t_input_bad_files() {
  new_workdir badfiles
  p_start --max-passes 6 --min-passes 2; ok 'start'
  p_predict 0.4 'Pass 1 inventories the screens.'; ok 'predict'

  printf '{"version":1,"lens":"ui","units":[' > "$WORK/truncated.json"
  printf 'not json at all\n' > "$WORK/garbage.json"
  mkdir -p "$WORK/a-directory"

  for bad in truncated.json garbage.json; do
    run_ponder units --session "$SLUG" --file "$WORK/$bad"
    assert_status 1 "$bad is a user error, not a crash and not a state violation"
    assert_next "the $bad refusal still prints NEXT"
    assert_no_match "$ALL" '(at [A-Za-z]+ \(|node:internal|^[[:space:]]*at )' \
      "the $bad refusal is a message, not a node stack trace"
    assert_eq '0' "$(jget "$(sess units.json)" 'd.units.length')" \
      "$bad left no half-written inventory behind"
  done

  run_ponder units --session "$SLUG" --file "$WORK/a-directory"
  assert_status 1 'a directory passed as --file is a user error'
  assert_next 'the directory refusal still prints NEXT'

  run_ponder units --session "$SLUG" --file "$WORK/never-created.json"
  assert_status 1 'a missing --file is a user error'

  run_ponder units --session "$SLUG"
  assert_status 1 'units with neither --file nor --stdin is a user error'

  run_ponder_stdin /dev/null units --session "$SLUG" --stdin
  assert_status 1 'units --stdin with nothing on stdin is a user error'

  # Extensionless files are ordinary files. A tool that resolves --file by
  # sniffing the extension breaks on `ponder units --file inventory`.
  cp "$FIXTURES/units-3.json" "$WORK/inventory"
  run_ponder units --session "$SLUG" --file "$WORK/inventory"
  ok 'units reads an extensionless file'
  assert_eq '3' "$(jget "$(sess units.json)" 'd.units.length')" 'the extensionless inventory landed'

  run_ponder grade --session "$SLUG" --file "$WORK/garbage.json"
  assert_status 1 'grade rejects malformed JSON as a user error'
  assert_eq '0' "$(jget "$(sess findings.json)" 'd.findings.length')" 'the rejected grade seeded nothing'
  assert_eq 'appraise' "$(phase_now)" 'and the session still owes its appraisal'
}

t_input_empty_inventory() {
  # SPEC 4.1 rule 1 divides by the enumerated units. An empty inventory makes
  # coverage 0/0, and whatever that evaluates to it is not evidence that
  # anything was looked at — so an empty survey has to be refused outright,
  # before it can become a session that stops honestly having done nothing.
  new_workdir emptyunits
  p_start --max-passes 6 --min-passes 1; ok 'start'
  p_predict 0.1 'Pass 1 enumerates nothing at all.'; ok 'predict'

  printf '{"version":1,"lens":"ui","units":[]}\n' > "$WORK/none.json"
  run_ponder units --session "$SLUG" --file "$WORK/none.json"
  assert_status 1 'an empty unit inventory is refused (SPEC 4.1 rule 1 has to divide by something)'
  assert_next 'the refusal still prints NEXT'
  assert_eq 'survey' "$(phase_now)" 'the session still owes a survey'
}

t_input_coverage_counts_units() {
  # coverage is graded units ÷ enumerated units (SPEC 4). Not findings ÷ units:
  # twelve findings about one screen is one screen graded, and a finding about a
  # screen nobody enumerated is not coverage of anything.
  new_workdir covcount
  p_start --max-passes 6 --min-passes 1; ok 'start'
  p_predict 0.4 'Pass 1 piles every finding onto one screen.'; ok 'predict'
  p_units; ok 'units'

  "$NODE" -e '
    const fs = require("fs");
    const one = (unit, n) => ({
      unit, title: "Finding " + n, detail: "Detail " + n, dimension: "empty-states",
      score: 3, severity: "note", confidence: 0.9, effort: "s",
      evidence: ["src/routes/settings/billing.tsx:1-2"],
      recommendation: "Recommendation " + n, status: "open",
    });
    const dir = process.argv[1];
    fs.writeFileSync(dir + "/same-unit.json", JSON.stringify({ version: 1, findings: [
      one("screen.settings.billing", 1), one("screen.settings.billing", 2),
      one("screen.settings.billing", 3), one("screen.settings.billing", 4),
    ] }, null, 2));
    fs.writeFileSync(dir + "/unknown-unit.json", JSON.stringify({ version: 1, findings: [
      one("screen.settings.billing", 1), one("screen.settings.profile", 2),
      one("screen.nobody.enumerated", 3),
    ] }, null, 2));
  ' "$WORK"

  run_ponder grade --session "$SLUG" --file "$WORK/unknown-unit.json"
  assert_status 1 'a finding about a unit that was never enumerated is refused'
  assert_contains "$ALL" 'screen.nobody.enumerated' 'the refusal names the unit it does not recognise'

  run_ponder grade --session "$SLUG" --file "$WORK/same-unit.json"
  ok 'four findings on one screen are accepted'
  p_deliberate; ok 'deliberate'
  p_delta deltas-one-edit.jsonl; ok 'delta'
  p_judge; ok 'judge'
  assert_close "$(metric 1 coverage)" 0.3333 0.005 \
    'coverage counts distinct graded units, not findings (SPEC 4)'

  run_ponder decide stop --session "$SLUG" --why 'Four findings on one screen is surely enough.'
  assert_status 2 'piling findings onto one unit does not satisfy the gate'
}

t_input_unicode_and_spaces() {
  # A project path with a space in it and a subject that is not ASCII. Both are
  # ordinary in the world this ships into, and both break a tool that builds
  # shell strings or assumes latin-1 anywhere in the round trip.
  new_workdir "space test"
  _spaced=$WORK          # new_workdir already gave this one a space in its name
  mkdir -p "$WORK/out dir"
  _subject='the “Café” UI — ünïcode ✨ and a  double space'
  _slug='ui-unicode'

  # A slug is a directory name, so it is the one field that has to stay
  # boring — and the refusal has to say so rather than creating a session
  # nobody can name again.
  run_ponder start "$_subject" --lens ui --project "$_spaced" --slug 'ui ünïcode' \
    --max-passes 6 --min-passes 2
  assert_status 1 'a slug that is not a safe directory name is a user error'
  assert_imatch "$ALL" 'slug' 'the refusal says which argument is at fault'
  assert_next 'the slug refusal still prints NEXT'

  run_ponder start "$_subject" --lens ui --project "$_spaced" --slug "$_slug" \
    --max-passes 6 --min-passes 2
  ok 'start accepts a spaced project path and a unicode subject'
  assert_dir "$_spaced/.ponder/$_slug" 'the session directory is created under the spaced path'
  assert_eq "$_subject" "$(jget "$_spaced/.ponder/$_slug/session.json" 'd.subject')" \
    'the subject survives the round trip byte for byte'
  assert_eq "$_spaced" "$(jget "$_spaced/.ponder/$_slug/session.json" 'd.project')" \
    'the project path survives the space'

  run_ponder status --session "$_slug"
  ok 'status finds the session under the spaced path'
  assert_contains "$ALL" "$_subject" 'status echoes the subject unmangled'

  run_ponder report --session "$_slug" --out "$WORK/out dir/a report with spaces.md"
  ok 'report --out writes to a path with spaces'
  assert_file "$WORK/out dir/a report with spaces.md" 'the report landed where it was told'
  assert_contains "$(cat "$WORK/out dir/a report with spaces.md")" "$_subject" \
    'the report carries the unicode subject'

  # And the same text has to survive the machine-readable path too.
  run_ponder status --session "$_slug" --json
  ok 'status --json exits 0'
  assert_json_stdout 'status --json under a spaced path'
  assert_eq "$_subject" "$(jout 'd.subject || (d.session && d.session.subject)')" \
    'the JSON payload carries the unicode subject unescaped into mojibake'
}

t_input_duplicate_slug() {
  new_workdir dupslug
  p_start --max-passes 6 --min-passes 2; ok 'start'
  _created=$(jget "$(sess session.json)" 'd.createdAt')

  run_ponder start "a completely different subject" --lens docs --project "$WORK" --slug "$SLUG"
  assert_status 1 'starting a second session on an existing slug is a user error'
  assert_next 'the refusal still prints NEXT'
  assert_eq "$_created" "$(jget "$(sess session.json)" 'd.createdAt')" \
    'the existing session was not overwritten'
  assert_eq "$SUBJECT" "$(jget "$(sess session.json)" 'd.subject')" 'nor was its subject'
  assert_eq 'ui' "$(jget "$(sess session.json)" 'd.lens')" 'nor its lens'
}

# ------------------------------------------------------------------- lenses ---

# lens_dimensions <name> -> space-separated dimension names, read straight out of
# lenses/<name>.md's front matter without going through lib/lens.js. The point is to
# have an expectation the engine's own parser did not produce.
lens_dimensions() {
  "$NODE" -e '
    const fs = require("node:fs");
    const text = fs.readFileSync(process.argv[1], "utf8").replace(/\r\n/g, "\n");
    const lines = text.split("\n");
    if (lines[0].trim() !== "---") process.exit(1);
    let close = -1;
    for (let i = 1; i < lines.length; i++) if (lines[i].trim() === "---") { close = i; break; }
    if (close === -1) process.exit(1);
    const fm = lines.slice(1, close);
    const at = fm.findIndex((l) => /^dimensions\s*:/.test(l));
    if (at === -1) process.exit(1);
    let buf = fm[at].replace(/^dimensions\s*:/, "");
    let i = at;
    while (!buf.includes("]") && ++i < fm.length) buf += " " + fm[i];
    const inner = buf.slice(buf.indexOf("[") + 1, buf.lastIndexOf("]"));
    const names = inner.split(",").map((s) => s.trim().replace(/^["\x27]|["\x27]$/g, "")).filter(Boolean);
    if (!names.length) process.exit(1);
    process.stdout.write(names.join(" "));
  ' "$REPO_ROOT/lenses/$1.md" 2>/dev/null
}

t_lens_every_pack() {
  # SPEC 1 names seven lenses. The suite drives `ui` everywhere else, which
  # would hide a pack whose front matter does not parse (SPEC 7) until the day
  # somebody reaches for it.
  new_workdir lenses
  for _lens in ui architecture docs tests product copy; do
    SLUG="lens-$_lens"
    run_ponder start "the $_lens of the fixture app" --lens "$_lens" \
      --project "$WORK" --slug "$SLUG" --max-passes 6 --min-passes 2
    ok "start --lens $_lens exits 0"
    assert_next "start --lens $_lens prints NEXT"
    assert_eq "$_lens" "$(jget "$(sess session.json)" 'd.lens')" \
      "the session records the $_lens lens"
    # SPEC 7: the pack the agent reads at survey names its unit and its
    # dimensions, and the scale runs 1 to 5.
    assert_match "$ALL" 'unit = [a-z]' "the $_lens pack names its unit (SPEC 7)"
    assert_match "$ALL" '[0-9]+ dimensions' "the $_lens pack declares its dimensions (SPEC 7)"
    # SPEC 3.3 fixes the range and leaves the wording to the pack, so this
    # checks that all five rungs are named, not what they are named.
    # The scale row is 143-204 characters, so it wraps at any real terminal
    # width; kv_row rejoins the hung continuations before the rungs are counted,
    # so this asserts the contract and not the layout.
    _scale=$(kv_row "$ALL" scale)
    assert_match "$_scale" '1 .*[^0-9]2 .*[^0-9]3 .*[^0-9]4 .*[^0-9]5 ' \
      "the $_lens scale names all five rungs (SPEC 7)"

    # A count of dimensions is not a rubric. SPEC 2 has appraise grade each unit
    # "against the lens rubric", so the dimension NAMES have to reach the agent —
    # read here straight out of the pack's front matter rather than through the
    # engine's own parser, so a parser that silently drops one cannot also
    # silently drop it from what this test expects.
    _dims=$(lens_dimensions "$_lens")
    if [ -z "$_dims" ]; then
      fail "could not read the dimensions of the $_lens pack out of its front matter"
    else
      _start_out="$ALL"
      _missing=''
      for _d in $_dims; do
        case $_start_out in *"$_d"*) ;; *) _missing="$_missing $_d" ;; esac
      done
      assert_eq '' "$_missing" "ponder start names every $_lens dimension, not just the count (SPEC 2)"

      # And again at the appraise handoff, which is where grading actually starts.
      printf '{"version":1,"units":[{"id":"unit.a","label":"A","path":"a.txt"}]}\n' > "$WORK/u-$_lens.json"
      run_ponder predict --session "$SLUG" --churn 0.9 --claim 'Pass one builds the set from nothing.'
      run_ponder units --session "$SLUG" --file "$WORK/u-$_lens.json"
      _units_out="$ALL"
      _missing=''
      for _d in $_dims; do
        case $_units_out in *"$_d"*) ;; *) _missing="$_missing $_d" ;; esac
      done
      assert_eq '' "$_missing" "ponder units hands appraise every $_lens dimension to grade against"

      # status is what an agent runs after losing its context; the rubric has to
      # be recoverable from it.
      run_ponder status --session "$SLUG"
      _status_out="$ALL"
      _missing=''
      for _d in $_dims; do
        case $_status_out in *"$_d"*) ;; *) _missing="$_missing $_d" ;; esac
      done
      assert_eq '' "$_missing" "ponder status can recover the $_lens rubric after a context loss"
    fi
  done

  run_ponder start "an unknown lens" --lens nonesuch --project "$WORK" --slug lens-bad
  assert_status 1 'an unknown lens is a user error'
  assert_next 'the unknown-lens refusal still prints NEXT'
}

t_lens_custom_rubric() {
  # SPEC 7: `--lens custom --rubric <file>` loads any file with the same front
  # matter shape.
  new_workdir customlens
  cat > "$WORK/rubric.md" <<'EOF'
---
name: conformance-widgets
unit: widget
enumerate: |
  Every widget in the fixture app, found by reading the widget registry.
dimensions: [alpha, beta, gamma]
scale:
  1: broken
  2: bad
  3: acceptable
  4: good
  5: exemplary
---

A widget is one thing on the board. Grade alpha, beta and gamma.
EOF

  SLUG='lens-custom'
  run_ponder start 'the widgets' --lens custom --rubric "$WORK/rubric.md" \
    --project "$WORK" --slug "$SLUG" --max-passes 6 --min-passes 2
  ok 'start --lens custom --rubric exits 0'
  assert_contains "$ALL" 'widget' 'the custom pack renames the unit'
  assert_contains "$ALL" 'conformance-widgets' 'the custom pack names itself'
  assert_eq 'conformance-widgets' "$(jget "$(sess session.json)" 'd.lens')" \
    'the session records the custom rubric by name'

  run_ponder start 'the widgets' --lens custom --project "$WORK" --slug lens-custom-2
  assert_status 1 '--lens custom without --rubric is a user error'

  run_ponder start 'the widgets' --lens custom --rubric "$WORK/nowhere.md" \
    --project "$WORK" --slug lens-custom-3
  assert_status 1 '--rubric pointing at nothing is a user error'

  printf 'no front matter here, just prose\n' > "$WORK/no-front-matter.md"
  run_ponder start 'the widgets' --lens custom --rubric "$WORK/no-front-matter.md" \
    --project "$WORK" --slug lens-custom-4
  assert_status 1 'a rubric with no front matter is a user error (SPEC 7)'
}

# ------------------------------------------------------------------ output ---

t_output_colour() {
  # SPEC 5 puts machine-readable output behind --json, which only works if the
  # human output is plain when it is being read by a machine. NO_COLOR and a
  # non-terminal stdout both mean "no escape sequences".
  new_workdir colour
  p_start --max-passes 6 --min-passes 2; ok 'start'

  # This test owns NO_COLOR for its duration. The suite itself is often run with
  # NO_COLOR set, and if that leaked in, "no escape sequences on a pipe" would
  # be proving NO_COLOR works rather than proving the pipe was noticed.
  _saved_no_color=${NO_COLOR:-__unset__}
  unset NO_COLOR 2>/dev/null || true

  run_ponder status --session "$SLUG"
  ok 'status exits 0'
  assert_no_ansi "$OUT" 'stdout redirected to a file carries no escape sequences'
  assert_no_ansi "$ERR" 'nor does stderr'

  run_ponder status --session "$SLUG" --json
  ok 'status --json exits 0'
  assert_no_ansi "$OUT" '--json output is never coloured'

  if run_ponder_tty status --session "$SLUG"; then
    assert_has_ansi "$TTY_OUT" 'a real terminal does get colour'
    NO_COLOR=1; export NO_COLOR
    run_ponder_tty status --session "$SLUG"
    assert_no_ansi "$TTY_OUT" 'NO_COLOR turns colour off on a terminal too'
  else
    warn 'no usable `script` on this machine: the terminal half of the colour test was skipped'
  fi

  if [ "$_saved_no_color" = '__unset__' ]; then
    unset NO_COLOR 2>/dev/null || true
  else
    NO_COLOR=$_saved_no_color; export NO_COLOR
  fi
}

# --------------------------------------------------------------- immutable ---

t_lifecycle_closed_session_is_closed() {
  # SPEC 3.1 gives a session five states and only one of them is `open`. A
  # closed session that still accepts predict or delta is a session whose
  # report can be contradicted after it was written.
  new_workdir closed
  p_start --max-passes 6 --min-passes 1; ok 'start'
  pass_one "$FIXTURES/findings-full.json" deltas-pass1.jsonl
  p_judge; ok 'judge'
  p_decide stop 'Closing this session so the loop commands have something to bounce off.'
  ok 'decide stop'
  assert_ne 'open' "$(status_now)" 'the session is closed'
  _closed_status=$(status_now)
  _ledger_at_close=$(ledger_lines)
  _findings_at_close=$(jget "$(sess findings.json)" 'd.findings.length')

  expect_closed() {
    _ec_label=$1; shift
    run_ponder "$@" --session "$SLUG"
    assert_status_not 0 "$_ec_label is refused on a closed session"
    assert_next "the $_ec_label refusal still prints NEXT"
    assert_eq "$_closed_status" "$(status_now)" "$_ec_label did not reopen the session"
  }

  expect_closed 'predict'    predict --churn 0.2 --claim 'Another pass, after the fact.'
  expect_closed 'units'      units --file "$WORK/units.json"
  expect_closed 'grade'      grade --file "$FIXTURES/findings-full.json"
  expect_closed 'deliberate' deliberate --file "$WORK/deliberation.json"
  expect_closed 'delta'      delta --file "$(delta_file deltas-one-edit.jsonl)"
  expect_closed 'judge'      judge
  expect_closed 'decide'     decide continue --why 'Reopening a session that already stopped.'
  expect_closed 'abort'      abort --why 'Aborting a session that has already stopped.'

  assert_eq "$_ledger_at_close" "$(ledger_lines)" 'nothing was appended to the ledger after the close'
  assert_eq "$_findings_at_close" "$(jget "$(sess findings.json)" 'd.findings.length')" \
    'the finding set is frozen'

  # Readers still work on a closed session — that is the point of closing it.
  run_ponder status --session "$SLUG"; ok 'status still reads a closed session'
  run_ponder report --session "$SLUG"; ok 'report still reads a closed session'
}

t_apply_needs_a_closed_session() {
  # SPEC 5.2: apply marks the session `applied`. A session that is still open
  # has a next pass owed, so committing it to a plan is a state violation —
  # while --dry-run, which commits nothing, stays available all the way through.
  new_workdir applyopen
  p_start --max-passes 6 --min-passes 2; ok 'start'
  pass_one "$FIXTURES/findings-full.json" deltas-pass1.jsonl
  p_judge; ok 'judge'

  run_ponder apply --session "$SLUG" --dry-run
  ok 'apply --dry-run reads an open session'
  assert_eq 'open' "$(status_now)" 'a dry run changes no state'

  run_ponder apply --session "$SLUG"
  assert_status 2 'apply on an open session is a state violation (SPEC 5.2)'
  assert_next 'the refusal still prints NEXT'
  assert_eq 'open' "$(status_now)" 'the session was not marked applied'
  assert_no_file "$(sess apply-plan.md)" 'and no plan was written'
}

# -------------------------------------------------------------------- deps ---

t_deps_zero_npm() {
  # SPEC 8.5. Node's standard library and psql only. This is the one
  # non-negotiable that is invisible at runtime — it only bites the day someone
  # installs ponder on a machine with no registry access.
  new_workdir deps
  _pkg="$REPO_ROOT/package.json"
  assert_file "$_pkg" 'the package manifest exists'
  assert_eq '0' "$(jget "$_pkg" 'Object.keys(d.dependencies || {}).length')" \
    'package.json declares no dependencies (SPEC 8.5)'
  assert_eq '0' "$(jget "$_pkg" 'Object.keys(d.devDependencies || {}).length')" \
    'package.json declares no devDependencies'
  assert_eq '0' "$(jget "$_pkg" 'Object.keys(d.peerDependencies || {}).length')" \
    'package.json declares no peerDependencies'

  for _lock in package-lock.json npm-shrinkwrap.json yarn.lock pnpm-lock.yaml; do
    assert_no_file "$REPO_ROOT/$_lock" "there is no $_lock to install from"
  done
  if [ -d "$REPO_ROOT/node_modules" ]; then
    _assert_fail 'node_modules/ exists: something is being installed (SPEC 8.5)'
  else
    _assert_pass
  fi

  # And prove it at the import level: every module the shipped code pulls in has
  # to be a node builtin or a relative path.
  _imports=$("$NODE" -e '
    const fs = require("fs"), path = require("path");
    const root = process.argv[1];
    const builtin = new Set(require("module").builtinModules);
    const bad = [];
    const walk = (dir) => {
      for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
        const p = path.join(dir, e.name);
        if (e.isDirectory()) { walk(p); continue; }
        if (!/\.(m|c)?js$/.test(e.name)) continue;
        const src = fs.readFileSync(p, "utf8");
        const re = /(?:^|[^.\w])(?:import\s[^;]*?from\s*|import\s*|require\s*\(\s*)["\x27]([^"\x27]+)["\x27]/g;
        let m;
        while ((m = re.exec(src))) {
          const spec = m[1];
          if (spec.startsWith(".") || spec.startsWith("/")) continue;
          const bare = spec.replace(/^node:/, "").split("/")[0];
          if (!builtin.has(bare)) bad.push(path.relative(root, p) + " -> " + spec);
        }
      }
    };
    for (const d of ["lib", "bin", "oca"]) {
      const full = path.join(root, d);
      if (fs.existsSync(full)) walk(full);
    }
    process.stdout.write(bad.join(", "));
  ' "$REPO_ROOT" 2>&1)
  assert_eq '' "$_imports" 'lib/, bin/ and oca/ import nothing but node builtins (SPEC 8.5)'
}

# ------------------------------------------------------------ concurrency ---

t_concurrency_store_survives() {
  # SPEC.md never mentions two agents driving one session at once, but every
  # mutating command is a read-decide-write over session.json, findings.json and
  # ledger.jsonl, and two of those interleaved is how "ids are never reused"
  # (SPEC 3.3) and "the ledger is every delta ever applied" (SPEC 3.4) come
  # apart in the field. The invariant under test is that a race has a winner:
  # one command commits, the other is refused, and nothing lands half-written.
  #
  # Three rounds over three fresh sessions. A correct engine answers the same
  # way every time; a lock-free one only loses the race some of the time, and a
  # single attempt would let it through about half these runs.
  _round=1
  while [ "$_round" -le 3 ]; do
  delta_session "$FIXTURES/findings-full.json"
  _id=$(finding_id 1)
  _before=$(ledger_lines)

  printf '{"op":"edit","target":"%s","perspective":"builder","why":"Concurrent revision A, racing B.","set":{"recommendation":"AAA from the first process"}}\n' \
    "$_id" > "$WORK/race-a.jsonl"
  printf '{"op":"edit","target":"%s","perspective":"empath","why":"Concurrent revision B, racing A.","set":{"recommendation":"BBB from the second process"}}\n' \
    "$_id" > "$WORK/race-b.jsonl"

  run_ponder_pair "$WORK/race-a.jsonl" "$WORK/race-b.jsonl" \
    delta --session "$SLUG" --file @FILE@

  assert_parses "$(sess session.json)"  "round $_round: session.json is still readable"
  assert_parses "$(sess findings.json)" "round $_round: findings.json is still readable"
  assert_parses "$(sess units.json)"    "round $_round: units.json is still readable"
  assert_jsonl_parses "$(sess ledger.jsonl)" "round $_round: every ledger line is one whole JSON object"

  _winners=0
  [ "$PAIR_RC_A" -eq 0 ] && _winners=$((_winners + 1))
  [ "$PAIR_RC_B" -eq 0 ] && _winners=$((_winners + 1))
  assert_eq '1' "$_winners" \
    "round $_round: exactly one of two concurrent deltas commits (got exit $PAIR_RC_A and $PAIR_RC_B)"
  assert_eq "$((_before + 1))" "$(ledger_lines)" "round $_round: the ledger grew by exactly one line"
  assert_eq 'judge' "$(phase_now)" "round $_round: the phase advanced exactly once"

  # The ledger must not claim a revision that findings.json never took.
  _applied=$(jget "$(sess findings.json)" "(d.findings.find(f => f.id === \"$_id\") || {}).recommendation")
  _claimed=$(jl "$(sess ledger.jsonl)" \
    "d.filter(x => x.target === \"$_id\" && x.set && x.set.recommendation).length")
  assert_eq '1' "$_claimed" "round $_round: only the winning delta reached the ledger"
  assert_match "$_applied" '(AAA|BBB) from the (first|second) process' \
    "round $_round: findings.json carries that same revision (SPEC 3.4)"

  run_ponder status --session "$SLUG"
  ok "round $_round: the session is still drivable after the race"
  _round=$((_round + 1))
  done
}

t_concurrency_decide_and_start() {
  # The two races that would be worst: a pass counted twice, and two sessions
  # in one directory.
  new_workdir raceclose
  p_start --max-passes 6 --min-passes 2; ok 'start'
  pass_one "$FIXTURES/findings-full.json" deltas-pass1.jsonl
  p_judge; ok 'judge'

  run_ponder_pair '' '' decide continue --session "$SLUG" --why \
    'Two processes committing the same decision at once.'
  _winners=0
  [ "$PAIR_RC_A" -eq 0 ] && _winners=$((_winners + 1))
  [ "$PAIR_RC_B" -eq 0 ] && _winners=$((_winners + 1))
  assert_eq '1' "$_winners" \
    "exactly one of two concurrent decisions commits (got exit $PAIR_RC_A and $PAIR_RC_B)"
  assert_eq '1' "$(jget "$(sess session.json)" 'd.history.length')" 'the pass is recorded once'
  assert_eq '2' "$(pass_now)" 'and the loop advanced exactly one pass'

  # Two starts on one slug: one session, readable, and one clean refusal.
  new_workdir racestart
  SLUG='ui-race-start'
  run_ponder_pair '' '' start "$SUBJECT" --lens ui --project "$WORK" --slug "$SLUG"
  _winners=0
  [ "$PAIR_RC_A" -eq 0 ] && _winners=$((_winners + 1))
  [ "$PAIR_RC_B" -eq 0 ] && _winners=$((_winners + 1))
  assert_eq '1' "$_winners" \
    "exactly one of two concurrent starts creates the session (got exit $PAIR_RC_A and $PAIR_RC_B)"
  assert_parses "$(sess session.json)" 'the session that survives is readable'
  assert_eq '1' "$(ls "$WORK/.ponder" | wc -l | tr -d ' ')" 'exactly one session directory exists'
  run_ponder status --session "$SLUG"
  ok 'and it is drivable'
}

# -------------------------------------------------------------------- main ---

if [ "$LIST_ONLY" != "1" ]; then
  printf '\n%sponder conformance suite%s\n' "$C_BLD" "$C_OFF"
  printf '%s%s  •  node %s  •  PONDER_OCA=off  •  %s%s\n\n' \
    "$C_DIM" "$PONDER_BIN" "$("$NODE" --version 2>/dev/null)" "$SUITE_TMP" "$C_OFF"
fi

SUITE_T0=$(date +%s)

run_test 'smoke: --help lists every command'                                  t_smoke_help
run_test 'smoke: doctor reports the environment'                              t_smoke_doctor
run_test 'smoke: start writes the session skeleton'                           t_smoke_start_shape
run_test 'smoke: pass bounds have sane defaults'                              t_smoke_defaults
run_test 'smoke: version runs and is documented everywhere it is listed'      t_smoke_version_is_discoverable
run_test 'smoke: --mode is retracted from the CLI, session and report'        t_mode_is_retracted

run_test 'happy: pass 1 walks predict to decide and writes every artefact'    t_happy_pass_one
run_test 'happy: three passes reach a converged stop'                         t_happy_converges
run_test 'happy: report.md is generated from the closed session'              t_happy_report

run_test 'coverage: judge blocks and names every ungraded unit'               t_coverage_blocked
run_test 'coverage: decide stop exits 2 and the session stays open'           t_coverage_gate
run_test 'coverage: no flag on decide overrides the gate'                     t_coverage_no_override_flag
run_test 'coverage: invented override flags cannot force a stop'              t_coverage_invented_flags
run_test 'coverage: a tampered metrics.json does not unlock the gate'         t_coverage_gate_survives_tampering
run_test 'coverage: a forged removalKind does not unlock the gate'           t_coverage_forged_removal_kind
run_test 'coverage: retracting a unit last finding reopens the gate'          t_coverage_retraction_reopens_gate
run_test 'coverage: a unit added on a later pass reopens the gate'            t_coverage_unit_add_reopens_gate
run_test 'coverage: unit-delete narrows the subject on the record'            t_coverage_unit_delete_is_on_the_record
run_test 'coverage: deleting ungraded units does not open the gate'           t_coverage_delete_ungraded_does_not_open_gate
run_test 'coverage: a deleted-ungraded unit is named apart from an ungraded one' t_coverage_names_the_two_kinds_apart
run_test 'coverage: a phantom claim with a live path is rejected'             t_coverage_phantom_live_path_is_rejected
run_test 'coverage: a phantom with a dead path drops out and is reported'     t_coverage_phantom_dead_path_is_accepted
run_test 'coverage: a phantom with no path is accepted but marked unverified' t_coverage_phantom_without_path_is_unverified
run_test 'coverage: phantom is checked, scoped, and upgradable once'          t_coverage_phantom_upgrade_and_limits
run_test 'coverage: aborting a blocked session is never dressed as a stop'    t_coverage_abort_is_not_a_stop
run_test 'coverage: --session names a slug, never a path out of .ponder'      t_coverage_session_lookup_is_scoped

run_test 'project root: a project marker outranks a stray ancestor .ponder'    t_project_root_marker_outranks_a_stray_ponder
run_test 'project root: a marker root leaves the phantom rule exactly as it was' t_project_root_marker_leaves_the_phantom_rule_alone
run_test 'project root: an adopted .ponder refuses a phantom claim'            t_project_root_adopted_ponder_refuses_a_phantom
run_test 'project root: a cwd fallback is a guess and is treated as one'       t_project_root_cwd_fallback_is_a_guess
run_test 'project root: provenance survives a session written without it'      t_project_root_provenance_survives_an_old_session

run_test 'phase: out-of-order commands exit 2 and name the expected phase'    t_phase_state_machine
run_test 'phase: units is a pass-1 command only'                              t_phase_units_is_pass_one_only
run_test 'phase: survey is skipped after pass 1'                              t_phase_survey_skipped_later
run_test 'phase: deliberate --skip needs a why and still advances'            t_phase_deliberate_skip

run_test 'delta: add assigns a fresh f-NNNN and never reuses an id'           t_delta_add_ids
run_test 'delta: delete retracts in place and removes nothing'                t_delta_delete_retracts
run_test 'delta: edit and change apply partial sets'                          t_delta_partial_sets
run_test 'delta: a delta without a why is rejected'                           t_delta_requires_why
run_test 'delta: one bad line rejects the whole batch'                        t_delta_batch_is_atomic
run_test 'delta: units and delta accept --stdin'                              t_delta_stdin
run_test 'delta: a change that only moves prose is flagged'                   t_delta_prose_change_warns

run_test 'unit-edit: a stale label is corrected in place, on the record'      t_unit_edit_corrects_a_stale_label
run_test 'unit-edit: a unit id can never be moved'                           t_unit_edit_never_moves_an_id
run_test 'unit-edit: an oscillating label thrashes like any other revision'  t_unit_edit_thrashes_like_any_other_revision
run_test 'unit-edit: editing a path cannot walk a unit past the gate'        t_unit_edit_cannot_walk_a_path_past_the_coverage_gate
run_test 'unit-edit: a label written by hand is still caught'                t_unit_edit_a_hand_written_label_is_still_caught

run_test 'ledger: earlier passes are byte-identical after later passes'       t_ledger_append_only

run_test 'reconcile: a forged phantom removal is caught, not believed'        t_reconcile_forged_phantom
run_test 'reconcile: a unit deleted out of units.json is caught'              t_reconcile_deleted_unit_entries
run_test 'reconcile: fabricated, duplicated and vanished findings are caught' t_reconcile_fabricated_findings
run_test 'reconcile: a status flipped by hand is caught in both directions'   t_reconcile_forged_status
run_test 'reconcile: five honest passes of every op raise nothing'            t_reconcile_stays_silent_on_an_honest_session
run_test 'reconcile: verify is a first-class command and doctor wires it in'  t_reconcile_verify_is_first_class
run_test 'reconcile: a ledger line with no pass record is not believed'       t_reconcile_a_ledger_line_alone_is_not_enough
run_test 'reconcile: a record the engine refuses to write is not believed'    t_reconcile_an_unwritable_record_is_caught
run_test 'reconcile: reordering, truncating or dropping a pass is caught'     t_reconcile_rewriting_the_ledger_is_caught
run_test 'reconcile: an honest session reports both copies agreeing'          t_reconcile_the_union_is_reported_on_an_honest_session
run_test 'reconcile: the ledger is written before the state files'           t_reconcile_the_ledger_is_written_before_the_state_files
run_test 'reconcile: --repair restores a session crashed mid-write'          t_reconcile_repair_restores_a_crashed_session
run_test 'reconcile: --repair refuses state ahead of the ledger'             t_reconcile_repair_refuses_state_ahead_of_the_ledger

run_test 'metrics: an oscillating session thrashes and escalates'             t_metrics_thrash_escalates
run_test 'metrics: a non-oscillating session reports thrash 0'                t_metrics_thrash_zero
run_test 'metrics: stall, confidence floor and voices are computed'           t_metrics_stall_and_floor_present
run_test 'metrics: pass 1 has no novelty, churn, thrash or surprise'          t_metrics_pass_one_has_no_relative_signals
run_test 'metrics: grade seeding is excluded from every ratio'                t_metrics_seeding_is_excluded_from_the_ratios
run_test 'metrics: voices counts who spoke, not who emitted a delta'          t_metrics_voices_counts_who_spoke

run_test 'verdict: coverage outranks the budget stop'                         t_verdict_order_coverage_beats_budget
run_test 'verdict: minPasses outranks thrash'                                 t_verdict_order_minpasses_beats_thrash
run_test 'verdict: pass 1 cannot converge with perfect metrics'               t_verdict_minpasses_blocks_convergence
run_test 'verdict: reaching maxPasses is a budget stop, not convergence'      t_verdict_budget_not_convergence

run_test 'override: deciding against advice needs a why of 12 characters'     t_override_why_length
run_test 'override: the reason lands in report.md under Overrides'            t_override_lands_in_report

run_test 'json: every command emits parseable JSON on stdout'                 t_json_every_command
run_test 'next: every command prints a NEXT line, errors included'            t_next_line_everywhere
run_test 'exit: 0 success, 1 user error, 2 state violation'                   t_exit_codes

run_test 'input: malformed, missing and extensionless files'                  t_input_bad_files
run_test 'input: an empty unit inventory is refused'                          t_input_empty_inventory
run_test 'input: coverage counts units, not findings'                         t_input_coverage_counts_units
run_test 'input: unicode subjects and paths with spaces survive'              t_input_unicode_and_spaces
run_test 'input: a duplicate slug never overwrites a session'                 t_input_duplicate_slug

run_test 'lens: every pack named in SPEC 1 opens a session'                   t_lens_every_pack
run_test 'lens: --lens custom --rubric loads a front-matter file'             t_lens_custom_rubric

run_test 'output: no colour off a terminal, NO_COLOR honoured on one'         t_output_colour
run_test 'deps: zero npm dependencies, builtins only'                         t_deps_zero_npm
run_test 'concurrency: racing deltas have exactly one winner'                 t_concurrency_store_survives
run_test 'concurrency: racing decisions and starts have one winner too'       t_concurrency_decide_and_start

run_test 'oca: PONDER_OCA=off never shells out to psql'                       t_oca_off_is_inert
run_test 'oca: a dead DSN under auto degrades silently and quickly'           t_oca_dead_dsn_degrades
run_test 'oca: a hanging psql cannot hang the engine'                         t_oca_hanging_psql
run_test 'oca: PONDER_OCA=on with an unreachable database is fatal'           t_oca_on_is_fatal
run_test 'oca: PONDER_OCA=on couples deliberate to the database too'         t_oca_on_blocks_deliberate
run_test 'oca: only the sanctioned cognitive_event_type subset is used'       t_oca_uses_only_the_sanctioned_enum_subset

run_test 'apply: the plan never touches a file outside .ponder/'              t_apply_never_touches_source
run_test 'apply: the plan is grouped, evidenced and severity-filtered'        t_apply_plan_content
run_test 'apply: committing a plan needs a closed session'                    t_apply_needs_a_closed_session
run_test 'apply: an aborted session is refused, dry run included'             t_apply_refuses_an_aborted_session

run_test 'lifecycle: abort closes the session with a reason'                  t_lifecycle_abort
run_test 'lifecycle: list and status report where the loop is'                t_lifecycle_list_and_status
run_test 'lifecycle: --session defaults to the most recent open session'      t_lifecycle_default_session
run_test 'lifecycle: a closed session refuses every loop command'             t_lifecycle_closed_session_is_closed

if [ "$LIST_ONLY" = "1" ]; then
  exit 0
fi

SUITE_ELAPSED=$(( $(date +%s) - SUITE_T0 ))

if [ "$TESTS_RUN" -eq 0 ]; then
  printf '\n%sno test name contains [%s]%s — run with -l to list them\n' "$C_RED" "$FILTER" "$C_OFF"
  exit 1
fi

printf '\n'
if [ "$TESTS_FAILED" -eq 0 ]; then
  printf '%s%s %s passed%s' "$C_GRN" "$MARK_OK" "$TESTS_PASSED" "$C_OFF"
else
  printf '%s%s %s failed%s, %s passed' "$C_RED" "$MARK_BAD" "$TESTS_FAILED" "$C_OFF" "$TESTS_PASSED"
fi
if [ "$WARNINGS" -gt 0 ]; then
  printf ', %s%s %s warned%s' "$C_YEL" "$MARK_WARN" "$WARNINGS" "$C_OFF"
fi
printf '  %s(%ss)%s\n' "$C_DIM" "$SUITE_ELAPSED" "$C_OFF"

if [ "$TESTS_FAILED" -ne 0 ]; then
  printf '\n%sfailed:%s\n' "$C_RED" "$C_OFF"
  printf '%s' "$FAILED_NAMES" | sed 's/^/  /'
  printf '\n'
  exit 1
fi
exit 0
