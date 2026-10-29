# Ponder - Audit addyosmani/agent-skills simplify-ignore, sdd-cache, and session-start hooks

`agent-skills-hooks` · lens **architecture** · status **stopped** · 4 passes of a 6-pass budget · generated 2026-10-29T21:16:31.328Z

| | |
|---|---|
| Subject | Audit addyosmani/agent-skills simplify-ignore, sdd-cache, and session-start hooks |
| Lens | architecture - unit = module, 11 dimensions |
| Project | `/Users/quinnodonnell/.gemini/antigravity/scratch/agent-skills` |
| Passes | 4 run · min 2 · max 6 |
| Coverage | 1.00 - 5 of 5 modules graded |
| Findings | 8 total · 7 open · 0 resolved · 0 deferred · 1 retracted |
| Final verdict | continue (default) → decided **stop** |
| OCA | off |

## Convergence

| Pass | Coverage | Novelty | Churn | Thrash | Surprise | Stall | Conf-floor | Voices | Advice | Decision |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|---|
| 1 | 0.80 | - | - | - | - | 0 | 0.00 | 4 | blocked (coverage) | continue |
| 2 | 1.00 | 0.29 | 0.43 | 0.00 | 0.13 | 0 | 0.00 | 4 | continue (default) | continue |
| 3 | 1.00 | 0.00 | 0.14 | 0.00 | 0.04 | 0 | 0.00 | 4 | continue (default) | continue |
| 4 | 1.00 | 0.00 | 0.00 | 0.00 | 0.00 | 1 | 0.00 | 4 | continue (default) | stop |

`-` on pass 1 is not a zero. Novelty, churn, thrash and surprise measure change against a previous pass, and pass 1 has none.

## Overrides

- **Pass 4** - advice `continue` (default), decided `stop`.
  > Converged across 4 passes after retracting 1 false positive in Pass 2 and verifying 2 must and 1 should findings with deterministic tests.

## Prediction vs reality

| Pass | Predicted churn | Actual churn | Surprise | Claim |
|---:|---:|---:|---:|---|
| 1 | 0.45 | - | - | Pass 1 will identify placeholder expansion and Stop-loop defects in hooks/simplify-ignore.sh and test a printf/heredoc expansion hypothesis on hooks/sdd-cache-pre.sh. |
| 2 | 0.30 | 0.43 | 0.13 | Pass 2 will falsify and retract f-0004 on hooks.sdd_cache_pre, record clean notes on hooks.sdd_cache_pre and scripts.skill_lint to reach coverage 1.00. |
| 3 | 0.10 | 0.14 | 0.04 | Pass 3 will refine f-0001 recommendation with the exact test targets in hooks/simplify-ignore-test.sh (Tests 19-21) and approach convergence. |
| 4 | 0.00 | 0.00 | 0.00 | Pass 4 will produce zero deltas across all 4 voices as all findings and module grades have converged. |

## Coverage

5 modules enumerated, 5 graded.

## Findings

### Block-level code-simplify protection hook (hooks/simplify-ignore.sh) `hooks.simplify_ignore`
`hooks/simplify-ignore.sh`

- **f-0001** · must · score 1 · confidence 0.96 · effort s · data-ownership - expand_file bakes original leading indentation into placeholder and omits :* in fuzzy matching, corrupting files and .bak when /code-simplify re-indents or edits reason text
  In hooks/simplify-ignore.sh:84 and 170-196, filter_file stores the full line prefix before simplify-ignore-start (including leading whitespace) in .prefix.<hash>. When /code-simplify flattens a nested block (e.g. unindenting a placeholder from 4 spaces to 2 spaces), neither esc_placeholder nor esc_fuzzy matches because both require the original 4-space prefix. expand_file falls through to line=${line//BLOCK_${h}/$block_content} (line 193), replacing only the bare BLOCK_<hash> token and leaving the comment opener before the expanded block and : <reason> */ after simplify-ignore-end. During PostToolUse Edit\|Write (line 424), this corrupted syntax overwrites $CACHE/${ID}.bak. The same fallback failure hits any /* ... */ or <!-- ... --> block whose reason text was modified by the model, because esc_fuzzy (${bp}BLOCK_${h}${bs}) omits :* between BLOCK_${h} and ${bs}, and in // or # comments ${bp}BLOCK_${h} matches only the prefix+hash and leaves : <modified-reason> appended to simplify-ignore-end.
  Evidence: `hooks/simplify-ignore.sh:84`, `hooks/simplify-ignore.sh:170-196`, `hooks/simplify-ignore.sh:418-432`
  Do: In hooks/simplify-ignore.sh:170-196, match re-indented placeholders by stripping leading whitespace from bp (${bp#"${bp%%[![:space:]]*}"}) and pairing with the current line indentation, update the fuzzy fallback to match ${esc_bp}BLOCK_${h}:*${esc_bs} (or ${esc_bp}BLOCK_${h}:* when bs is empty) before ${esc_bp}BLOCK_${h}${esc_bs}, and add regression Tests 19-21 in hooks/simplify-ignore-test.sh.
  _Revised: p3 edit recommendation_

- **f-0002** · must · score 1 · confidence 0.96 · effort xs · failure-modes - Stop loop aborts under set -euo pipefail when .lock directory is missing, and parse_error on malformed JSON falls through into Stop and wipes active backups
  hooks/simplify-ignore.sh enables set -euo pipefail at line 17, but calls rmdir "$CACHE/${fid}.lock" 2>/dev/null without \|\| true at lines 326, 332, 339, and 392 (unlike line 373 which uses \|\| true). If a lock directory is missing when Stop iterates over multiple .bak files, rmdir returns exit code 1 on the first file and aborts the script before restoring remaining files. In addition, when jq fails to parse malformed hook input at lines 37-47, parse_error is logged with TOOL_NAME="" but execution does not exit, falling straight into if [ -z "$TOOL_NAME" ] at line 287 (the Stop handler) and wiping active session backups mid-session.
  Evidence: `hooks/simplify-ignore.sh:17`, `hooks/simplify-ignore.sh:36-47`, `hooks/simplify-ignore.sh:287-340`, `hooks/simplify-ignore.sh:392`
  Do: Exit 0 after logging parse_error at hooks/simplify-ignore.sh:47, append \|\| true to rmdir calls at lines 326, 332, 339, and 392, and add regression coverage in hooks/simplify-ignore-test.sh.
  _Revised: p1 edit recommendation_

- **f-0003** · should · score 2 · confidence 0.95 · effort xs · contract-stability - expand_file calls grep -qF without -- on first_line, emitting a false block-deleted warning on SQL/Lua/Haskell -- simplify-ignore-start comments
  At hooks/simplify-ignore.sh:213-216, expand_file checks whether a block was expanded by running grep -qF "$first_line" "$dest" 2>/dev/null without -- (unlike lines 265 and 363 which pass --). When a protected block uses double-dash comments (-- simplify-ignore-start in SQL, Lua, Haskell, or Ada), grep interprets $first_line as an unrecognized long option, exits 2, and prints a false Warning: protected block BLOCK_<hash> was deleted by model on every Edit, Write, and Stop.
  Evidence: `hooks/simplify-ignore.sh:213-219`, `hooks/simplify-ignore.sh:265`, `hooks/simplify-ignore.sh:363`
  Do: Pass -- to grep -qF in hooks/simplify-ignore.sh:213 and 216.

### PostToolUse WebFetch validator capture hook (hooks/sdd-cache-post.sh) `hooks.sdd_cache_post`
`hooks/sdd-cache-post.sh`

- **f-0005** · note · score 5 · confidence 0.95 · effort xs · data-ownership - sdd-cache-post.sh strips CR before AWK paragraph splitting and writes cache files atomically via temp file rename
  hooks/sdd-cache-post.sh:82-133 strips \r from curl -sI -L output so AWK paragraph mode isolates the final redirect hop headers, and writes .claude/sdd-cache/<sha>.json atomically via ${CACHE_FILE}.$$.tmp + mv.
  Evidence: `hooks/sdd-cache-post.sh:82-133`
  Do: No change needed.

### PreToolUse WebFetch 304 cache hook (hooks/sdd-cache-pre.sh) `hooks.sdd_cache_pre`
`hooks/sdd-cache-pre.sh`

- **f-0007** · note · score 5 · confidence 0.96 · effort xs · boundary-integrity - sdd-cache-pre.sh safely emits cached WebFetch content via printf %s without shell or format expansion
  hooks/sdd-cache-pre.sh:91-105 validates ETag/Last-Modified via HTTP 304 and writes $CONTENT with printf "%s\n" "$CONTENT" >&2, preventing command substitution and format-string interpretation.
  Evidence: `hooks/sdd-cache-pre.sh:91-105`, `hooks/sdd-cache-test.sh:142-156`
  Do: No change needed.

### SessionStart meta-skill injection hook (hooks/session-start.sh) `hooks.session_start`
`hooks/session-start.sh`

- **f-0006** · note · score 5 · confidence 0.95 · effort xs · contract-stability - session-start.sh emits a valid SessionStart hookSpecificOutput JSON envelope on all code paths
  hooks/session-start.sh:18-33 uses jq -cn --arg context when jq is available and falls back to static valid JSON envelopes when jq or SKILL.md is missing.
  Evidence: `hooks/session-start.sh:18-33`
  Do: No change needed.

### Shared skill and persona linter (scripts/lib/skill-lint.js) `scripts.skill_lint`
`scripts/lib/skill-lint.js`

- **f-0008** · note · score 5 · confidence 0.95 · effort xs · contract-stability - skill-lint.js enforces CommonMark fence stripping and strict YAML frontmatter rules without external dependencies
  scripts/lib/skill-lint.js:129-156 and 229-322 accurately strip backtick and tilde fences of variable length and catch unquoted colons, tabs, and indicator characters that break host YAML parsers.
  Evidence: `scripts/lib/skill-lint.js:129-156`, `scripts/lib/skill-lint.js:229-322`
  Do: No change needed.

## Retracted

Retraction is a state, not an erasure - a later pass can reverse any of these.

- `f-0004` (hooks.sdd_cache_pre) - sdd-cache-pre.sh stderr payload emission could interpret format specifiers or backticks in cached documentation bodies · retracted in pass 2 by the skeptic: hooks/sdd-cache-pre.sh:103 passes $CONTENT as a data argument to printf "%s\n", never as a format string or unquoted heredoc, as verified by hooks/sdd-cache-test.sh:142-156.

## Deliberation

### Pass 1

- **skeptic** (confidence 0.90) - f-0001, f-0002, and f-0003 in hooks/simplify-ignore.sh are all empirically reproducible in bash, whereas f-0004 on hooks/sdd-cache-pre.sh is suspect because line 103 uses printf "%s\n" "$CONTENT". We also still need to grade scripts.skill_lint in Pass 2.
- **builder** (confidence 0.95) - In hooks/simplify-ignore.sh, expand_file can strip leading whitespace from bp when matching re-indented lines, use ${esc_bp}BLOCK_${h}:*${esc_bs} for modified reasons, exit 0 on parse_error, and guard rmdir with \|\| true.
- **dreamer** (confidence 0.90) - Check hooks/simplify-ignore-test.sh and scripts/lib/skill-lint.js in Pass 2 so all 5 units reach coverage 1.00 and regression tests are pinned.
- **empath** (confidence 0.95) - Flattening nested conditionals (which unindents the body) is the #1 transformation in /code-simplify; corrupting protected blocks into invalid syntax on unindent directly breaks the hook for its primary use case.

Resolution: 1 edit (plus 6 findings seeded by `ponder grade` before the argument).

### Pass 2

- **skeptic** (confidence 0.96) - Inspecting hooks/sdd-cache-pre.sh:91-105 and hooks/sdd-cache-test.sh:142-156 confirms line 103 uses printf "%s\n" "$CONTENT" (with %s as a literal format string) and Test 7 already verifies backticks, $HOME, backslashes, globs, and $(...) round-trip byte-for-byte. Retract f-0004.
- **builder** (confidence 0.95) - Replace retracted f-0004 with a clean-grade note on hooks.sdd_cache_pre and grade scripts.skill_lint so coverage reaches 1.00 across all 5 units.
- **dreamer** (confidence 0.95) - scripts/lib/skill-lint.js:129-156 and 229-322 cleanly handle CommonMark fence stripping and strict YAML frontmatter validation across all 25 skills and 4 personas.
- **empath** (confidence 0.95) - Retracting the false alarm on sdd-cache-pre.sh keeps the maintainer report focused solely on the reproducible simplify-ignore.sh defects.

Resolution: 2 add, 1 delete.

### Pass 3

- **skeptic** (confidence 0.98) - All 3 open findings in hooks/simplify-ignore.sh (f-0001, f-0002, f-0003) fail deterministically before the fix and pass all 73 assertions in hooks/simplify-ignore-test.sh after the fix.
- **builder** (confidence 0.98) - Pin hooks/simplify-ignore-test.sh in f-0001 recommendation so the implementation and regression tests (Tests 19-21) stay coupled.
- **dreamer** (confidence 0.97) - All 5 enumerated modules are graded (coverage 1.00) and all repository validators pass.
- **empath** (confidence 0.97) - Coupling the minimal hook diff with self-contained bash tests makes the PR effortless for maintainers to verify.

Resolution: 1 edit.

### Pass 4

- **skeptic** (confidence 0.99) - Zero remaining unverified claims; f-0004 was falsified and retracted in Pass 2, and f-0001, f-0002, and f-0003 have deterministic reproducers in hooks/simplify-ignore-test.sh.
- **builder** (confidence 0.99) - Diffs in hooks/simplify-ignore.sh and hooks/simplify-ignore-test.sh are minimal, POSIX/Bash 3.2 compatible, and pass all 73 hook assertions.
- **dreamer** (confidence 0.99) - Full unit coverage (5/5) achieved with zero churn in Pass 4.
- **empath** (confidence 0.99) - Audit report is concise, evidence-backed, and ready for addyosmani/agent-skills maintainers.

Resolution: no deltas.

## Ledger

11 deltas across 4 passes: 8 add, 2 edit, 1 delete.

| Pass | Deltas | Perspectives |
|---:|---|---|
| 1 | 6 add, 1 edit | builder |
| 2 | 2 add, 1 delete | dreamer, skeptic |
| 3 | 1 edit | builder |
| 4 | no deltas | - |

The full append-only record is `ledger.jsonl`.

---

*Generated by [Ponder](https://github.com/Quinnod345/ponder) - AI that knows when to speak, and when to shut up.*
