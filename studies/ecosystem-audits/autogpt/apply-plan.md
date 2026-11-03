# Apply Plan: Significant-Gravitas/AutoGPT Audit

Generated from Ponder deliberation audit session `autogpt` (4 passes, 1.00 coverage, 0.00 churn).

## Priority 1: Use atomic CAS compare-and-extend in cluster_lock.py
- **Target:** `autogpt_platform/backend/backend/executor/cluster_lock.py:161-175` and `302-316`
- **Action:** Replace the separate `get(self.key)` check and `expire(self.key, self.timeout)` with an atomic Lua CAS script:
```python
_EXTEND_LUA = (
    "if redis.call('get', KEYS[1]) == ARGV[1] then "
    "return redis.call('expire', KEYS[1], ARGV[2]) "
    "else return 0 end"
)
```
- **Impact:** Eliminates the race condition where a lapsed or force-released key reacquired by another process has its TTL blindly extended by the previous holder.

## Priority 2: Back off retries for tokenless rows in reaper.py
- **Target:** `autogpt_platform/backend/backend/copilot/dream/reaper.py:320-350`
- **Action:** For dead passes that lack an ownership token, record a deferred retry timestamp instead of immediately re-polling them on every 10-minute reaper cycle until the 24-hour key TTL expires.
- **Impact:** Saves reaper attempt budget for actionable rows and reduces unnecessary Redis/Prisma query load.
