# PR-Agent Remediation Plan

## Priority 1: Retain Active Findings for Excluded Files in review_finding_state.py
- **Target:** `pr_agent/algo/review_finding_state.py:264-276`
- **Action:** Check whether `previous.get("path")` is present in `excluded` before marking a finding as `RESOLVED`:
```python
    excluded_set = set(excluded)
    for finding_id, previous in previous_by_id.items():
        if finding_id in current_by_id:
            continue
        record = copy.deepcopy(previous)
        # Never resolve findings in files that were excluded from the current review run
        is_in_excluded = record.get("path") in excluded_set
        if record.get("state") == "ACTIVE" and resolution_allowed and not is_in_excluded:
            record["state"] = "RESOLVED"
            record["resolved_at"] = now
            if head_sha:
                record["resolved_head_sha"] = head_sha
            if run_id:
                record["resolution_run_id"] = run_id
            resolved_ids.append(finding_id)
            changed = True
        reconciled[finding_id] = record
```

---

## Priority 2: Sort Key Issues by Severity Before Capping in review_merge.py
- **Target:** `pr_agent/algo/review_merge.py:113-126`
- **Action:** Sort issues by severity / importance descending before applying the slice limit:
```python
def _cap_key_issues(review: dict, max_findings: int | None) -> None:
    if max_findings is None:
        return
    try:
        limit = max(0, int(max_findings))
    except (TypeError, ValueError):
        return
    issues = review.get("key_issues_to_review")
    if isinstance(issues, list) and len(issues) > limit:
        # Prioritize high-importance / high-severity findings over arrival order
        def _issue_priority(issue):
            if not isinstance(issue, dict):
                return 0
            # Higher score/importance ranks first
            return int(issue.get("importance", issue.get("score", 0)) or 0)
        sorted_issues = sorted(issues, key=_issue_priority, reverse=True)
        review["key_issues_to_review"] = sorted_issues[:limit]
```

---

## Priority 3: Guard AzureDevopsProvider Comment Body Iterator in inline_comment_dedup.py
- **Target:** `pr_agent/algo/inline_comment_dedup.py:236-239`
- **Action:** Remove redundant fallthrough or check callable:
```python
    elif provider_name == "AzureDevopsProvider":
        getter = getattr(git_provider, "get_persistent_comment_bodies", None)
        if callable(getter):
            yield from getter()
        else:
            raise NotImplementedError("Persistent comment bodies not supported on AzureDevopsProvider")
```

---

## Priority 4: Reuse Worker ThreadPoolExecutor in token_handler.py
- **Target:** `pr_agent/algo/token_handler.py:44-59`
- **Action:** Use a module-level cached executor for background token counting rather than recreating per call:
```python
_TOKEN_EXECUTOR = None
_TOKEN_EXECUTOR_LOCK = Lock()

def _get_token_executor():
    global _TOKEN_EXECUTOR
    if _TOKEN_EXECUTOR is None:
        with _TOKEN_EXECUTOR_LOCK:
            if _TOKEN_EXECUTOR is None:
                _TOKEN_EXECUTOR = ThreadPoolExecutor(max_workers=2, thread_name_prefix="token-count")
    return _TOKEN_EXECUTOR
```
