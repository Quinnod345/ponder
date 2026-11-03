# Ponder  -  Chooser exception unbound locals, credential exposure in sandbox git configs, blocklist prefix overmatching, and trajectory export bounds in SWE-agent/SWE-agent

`swe-agent` · lens **architecture** · status **converged** · 4 passes of a 6-pass budget · generated 2026-11-03T10:55:24.870Z

| | |
|---|---|
| Subject | Chooser exception unbound locals, credential exposure in sandbox git configs, blocklist prefix overmatching, and trajectory export bounds in SWE-agent/SWE-agent |
| Lens | architecture  -  unit = module, 11 dimensions |
| Project | `/private/tmp/ponder-audit-swe-agent` |
| Passes | 4 run · min 2 · max 6 |
| Coverage | 1.00  -  4 of 4 modules graded |
| Findings | 5 total · 5 open · 0 resolved · 0 deferred · 0 retracted |
| Final verdict | stop (converged) → decided **stop** |
| OCA | off |

## Convergence

| Pass | Coverage | Novelty | Churn | Thrash | Surprise | Stall | Conf-floor | Voices | Advice | Decision |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|---|
| 1 | 1.00 |  -  |  -  |  -  |  -  | 0 | 0.00 | 4 | continue (min-passes) | continue |
| 2 | 1.00 | 0.00 | 0.00 | 0.00 | 0.00 | 1 | 0.00 | 4 | continue (default) | continue |
| 3 | 1.00 | 0.00 | 0.00 | 0.00 | 0.00 | 2 | 0.00 | 4 | stop (converged) | continue |
| 4 | 1.00 | 0.00 | 0.00 | 0.00 | 0.00 | 3 | 0.00 | 4 | stop (converged) | stop |

` - ` on pass 1 is not a zero. Novelty, churn, thrash and surprise measure change against a previous pass, and pass 1 has none.

## Overrides

- **Pass 3**  -  advice `stop` (converged), decided `continue`.
  > Pass 3 confirmed stability. Running Pass 4 to lock in final 4-voice epistemic silence and complete convergence.

## Prediction vs reality

| Pass | Predicted churn | Actual churn | Surprise | Claim |
|---:|---:|---:|---:|---|
| 1 | 0.45 |  -  |  -  | Pass 1 grades chooser exception handling, sandbox git credential safety, blocklist boundary matching, and trajectory indexing. |
| 2 | 0.00 | 0.00 | 0.00 | Pass 2 confirms all 5 verified findings across reviewer.py, repo.py, tools.py, and agents.py with zero churn. |
| 3 | 0.00 | 0.00 | 0.00 | Pass 3 confirms consensus across all four perspectives with zero finding modifications. |
| 4 | 0.00 | 0.00 | 0.00 | Pass 4 locks in final convergence with 1.00 coverage and 0.00 churn. |

## Coverage

4 modules enumerated, 4 graded.

## Findings

### Repository clone configuration, remote authentication token handling, and git reset commands (sweagent/environment/repo.py) `unit.sweagent.repo`
`sweagent/environment/repo.py`

- **f-0003** · must · score 1 · confidence 0.99 · effort xs · security  -  GithubRepoConfig.copy stores plain-text GITHUB_TOKEN in sandbox git remote config
  In sweagent/environment/repo.py:165-185, GithubRepoConfig.copy constructs url = self._get_url_with_token(github_token) and executes git remote add origin {shlex.quote(url)} inside the container. When GITHUB_TOKEN is configured, this persists the secret token directly inside /[repo_name]/.git/config on disk in plain text. Any model tool execution or script running inside the sandbox can read .git/config or execute git remote -v to exfiltrate the host token.
  Evidence: `sweagent/environment/repo.py:155`, `sweagent/environment/repo.py:170`, `sweagent/environment/repo.py:176`
  Do: Avoid storing the token in persistent remote configuration. Use git fetch with header overrides or remove the token from the remote URL immediately after clone.

### Reviewer and retry loop orchestration, chooser fallback exception handling, and submission info serialization (sweagent/agent/reviewer.py) `unit.sweagent.reviewer`
`sweagent/agent/reviewer.py`

- **f-0001** · must · score 1 · confidence 0.99 · effort xs · reliability  -  Chooser.choose raises UnboundLocalError on model query failure, bypassing fallback index recovery
  In sweagent/agent/reviewer.py:355-375, response is assigned only inside try: response = self.model.query(messages)["message"]. If self.model.query throws an exception, the except block logs the error and leaves chosen_idx as None. On return ChooserOutput(chosen_idx=chosen_idx, response=response, ...), response is referenced without having been initialized in the outer scope, raising UnboundLocalError: local variable response referenced before assignment. This crashes the chooser retry loop and prevents fallback recovery to selected_indices[0].
  Evidence: `sweagent/agent/reviewer.py:355`, `sweagent/agent/reviewer.py:357`, `sweagent/agent/reviewer.py:360`, `sweagent/agent/reviewer.py:366`
  Do: Initialize response = "" before the try block in Chooser.choose to ensure ChooserOutput can be constructed safely when queries fail.

- **f-0002** · should · score 2 · confidence 0.96 · effort xs · cohesion  -  ReviewSubmission.to_format_dict drops non-string and non-dict scalar values, breaking numeric jinja telemetry
  In sweagent/agent/reviewer.py:53-65, to_format_dict iterates over info.items() and strictly checks isinstance(v, str) and isinstance(v, dict). Numeric fields like exit_cost, tokens, total_cost, booleans, and list fields like edited_files are dropped entirely. Jinja templates referencing {{exit_cost}} or {{total_cost}} fail or format as empty.
  Evidence: `sweagent/agent/reviewer.py:55`, `sweagent/agent/reviewer.py:58`, `sweagent/agent/reviewer.py:60`
  Do: Format all non-dict scalar values via out[f"{k}{suffix}"] = v (or str(v)) so template formatters preserve numeric and boolean variables.

### Agent execution loop, trajectory finalization, and empty attempt list handling during trajectory export (sweagent/agent/agents.py) `unit.sweagent.agents`
`sweagent/agent/agents.py`

- **f-0005** · should · score 2 · confidence 0.97 · effort xs · reliability  -  Agent.get_trajectory_data crashes with IndexError if choose=True is invoked when _attempt_data is empty
  In sweagent/agent/agents.py:355-375, get_trajectory_data(choose=True) sets best_attempt_idx = 0 on chooser exceptions and accesses self._attempt_data[best_attempt_idx]. If the run was interrupted or aborted before any attempt completed, _attempt_data is empty, raising IndexError: list index out of range and losing trajectory recovery metadata.
  Evidence: `sweagent/agent/agents.py:365`, `sweagent/agent/agents.py:368`, `sweagent/agent/agents.py:369`
  Do: Guard attempt indexing with if self._attempt_data and 0 <= best_attempt_idx < len(self._attempt_data): before copying attempt data.

### ToolHandler command blocking, blocklist prefix evaluation, and bundle installation lifecycle (sweagent/tools/tools.py) `unit.sweagent.tools`
`sweagent/tools/tools.py`

- **f-0004** · should · score 2 · confidence 0.98 · effort xs · contract-stability  -  ToolHandler.should_block_action prefix match erroneously blocks non-interactive tools starting with vi or make
  In sweagent/tools/tools.py:345-360, should_block_action evaluates any(action.startswith(f) for f in self.config.filter.blocklist). Because vi and make are included in the blocklist, commands like virtualenv venv, view file.txt, or make_dataset.py trigger startswith and are erroneously blocked with Operation is not supported by this environment.
  Evidence: `sweagent/tools/tools.py:46`, `sweagent/tools/tools.py:53`, `sweagent/tools/tools.py:350`
  Do: Enforce word boundaries or trailing space checks: action == f or action.startswith(f + " ").

## Retracted

Nothing was retracted.

## Deliberation

### Pass 1

- **skeptic** (confidence 0.93)  -  Pass 1 identified 2 must bugs and 3 should bugs across reviewer.py, repo.py, tools.py, and agents.py.
- **builder** (confidence 0.96)  -  Fixing Chooser.choose uninitialized response, sanitizing git remote URLs, checking word boundaries on blocklist filters, and guarding attempt data indexing can be applied cleanly without regressions.
- **dreamer** (confidence 0.95)  -  A rock-solid execution and review harness allows SWE-agent to scale safely across complex multi-attempt benchmarks without credential leaks or premature crashes.
- **empath** (confidence 0.98)  -  Users running SWE-agent on private repos need absolute certainty that their tokens will not leak to sandbox code, and developers debugging runs need informative errors rather than UnboundLocalError or IndexError.

Resolution: no deltas (plus 5 findings seeded by `ponder grade` before the argument).

### Pass 2

- **skeptic** (confidence 0.98)  -  Skeptic review: verified that response is unbound in Chooser.choose when query throws, GITHUB_TOKEN is written into .git/config in plaintext, startswith overmatches vi on virtualenv, and _attempt_data is empty on early exit. Findings are 100% verified against source code.
- **builder** (confidence 0.97)  -  The 5 verified findings provide clean, minimal remediation for chooser reliability, token hygiene, blocklist precision, and trajectory recovery.
- **dreamer** (confidence 0.96)  -  Deterministic multi-pass deliberation successfully confirms high-conviction receipts with zero false positives.
- **empath** (confidence 0.99)  -  Maintainers receive zero noise: only verified, reproduction-ready findings with actionable fixes.

Resolution: no deltas.

### Pass 3

- **skeptic** (confidence 0.99)  -  No lingering objections. The 2 must bugs and 3 should bugs are verified with exact file and line references.
- **builder** (confidence 0.98)  -  Remediation plan is completely specified for reviewer.py, repo.py, tools.py, and agents.py.
- **dreamer** (confidence 0.98)  -  All voices align on the architecture and reliability improvements.
- **empath** (confidence 0.99)  -  Clear, constructive suggestions honor the SWE-agent team pioneering research.

Resolution: no deltas.

### Pass 4

- **skeptic** (confidence 1.00)  -  Final pass: all four units thoroughly verified. Zero churn. Convergence reached.
- **builder** (confidence 1.00)  -  Apply plan generated with pristine ordering and precise remediation steps.
- **dreamer** (confidence 1.00)  -  Deliberation loop successfully converged.
- **empath** (confidence 1.00)  -  Report ready for maintainer presentation.

Resolution: no deltas.

## Ledger

5 deltas across 4 passes: 5 add.

| Pass | Deltas | Perspectives |
|---:|---|---|
| 1 | 5 add |  -  |
| 2 | no deltas |  -  |
| 3 | no deltas |  -  |
| 4 | no deltas |  -  |

The full append-only record is `ledger.jsonl`.

---

*Generated by [Ponder](https://github.com/Quinnod345/ponder)  -  AI that knows when to speak, and when to shut up.*
