# Apply Plan: SWE-agent/SWE-agent Audit

Generated from Ponder deliberation audit session `swe-agent` (4 passes, 1.00 coverage, 0.00 churn).

## Priority 1: Initialize response before query in Chooser.choose
- **Target:** `sweagent/agent/reviewer.py:355-375`
- **Action:** Ensure `response = ""` is initialized before the `try:` block so that when `self.model.query` raises an exception, `ChooserOutput` construction does not fail with `UnboundLocalError`:
```python
        messages = self.build_messages(problem_statement, [input[i] for i in selected_indices])
        chosen_idx = None
        response = ""
        try:
            response = self.model.query(messages)["message"]  # type: ignore
            chosen_idx = self.interpret(response)
        except Exception as e:
            self.logger.critical(f"Chooser failed: {e}", exc_info=True)
            chosen_idx = None
```

## Priority 2: Prevent plain-text GITHUB_TOKEN storage in sandbox .git/config
- **Target:** `sweagent/environment/repo.py:165-185`
- **Action:** Do not embed `github_token` in the persistent `origin` remote URL:
```python
        # Use header configuration or remove credentials from the persistent remote URL
        clean_url = self.github_url
        asyncio.run(
            deployment.runtime.execute(
                Command(
                    command=" && ".join(
                        (
                            f"mkdir /{self.repo_name}",
                            f"cd /{self.repo_name}",
                            "git init",
                            f"git remote add origin {shlex.quote(clean_url)}",
                            f"git -c http.extraHeader="Authorization: token {github_token}" fetch --depth 1 origin {shlex.quote(base_commit)}" if github_token else f"git fetch --depth 1 origin {shlex.quote(base_commit)}",
                            "git checkout FETCH_HEAD",
                            "cd ..",
                        )
                    ),
                    timeout=self.clone_timeout,
                    shell=True,
                    check=True,
                )
            ),
        )
```

## Priority 3: Enforce word boundaries on blocklist prefix matching in ToolHandler
- **Target:** `sweagent/tools/tools.py:345-360`
- **Action:** Avoid matching prefixes without word boundaries so commands like `virtualenv` or `make_dataset.py` are not blocked by `vi` or `make`:
```python
    def should_block_action(self, action: str) -> bool:
        """Check if the command should be blocked."""
        action = action.strip()
        if not action:
            return False
        if any(action == f or action.startswith(f + " ") for f in self.config.filter.blocklist):
            return True
        if action in self.config.filter.blocklist_standalone:
            return True
```

## Priority 4: Guard attempt index access in Agent.get_trajectory_data
- **Target:** `sweagent/agent/agents.py:355-375`
- **Action:** Guard against empty `_attempt_data` during aborts or premature exits:
```python
        if choose:
            try:
                best_attempt_idx = self._rloop.get_best()
            except TotalCostLimitExceededError:
                raise
            except Exception as e:
                self.logger.critical(f"Error getting best attempt index: {e}. Setting to 0.", exc_info=True)
                best_attempt_idx = 0
            if self._attempt_data and 0 <= best_attempt_idx < len(self._attempt_data):
                data |= copy.deepcopy(self._attempt_data[best_attempt_idx])  # type: ignore
                data["info"]["best_attempt_idx"] = best_attempt_idx
```

## Priority 5: Format non-string scalar values in ReviewSubmission.to_format_dict
- **Target:** `sweagent/agent/reviewer.py:53-65`
- **Action:** Include numeric and boolean values in formatted telemetry dictionary:
```python
        for k, v in info.items():
            if isinstance(v, (str, int, float, bool)):
                out[f"{k}{suffix}"] = v
            elif isinstance(v, dict):
                for k2, v2 in v.items():
                    out[f"{k}_{k2}{suffix}"] = v2
```
