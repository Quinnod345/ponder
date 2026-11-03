# Apply Plan: crewAIInc/crewAI Audit

Generated from Ponder deliberation audit session `crewai` (4 passes, 1.00 coverage, 0.00 churn).

## Priority 1: Attach _registered_hook in hook decorators
- **Target:** `lib/crewai/src/crewai/hooks/decorators.py:72`
- **Action:** In `_create_hook_decorator`, set `f._registered_hook = filtered_hook` before calling `register_function(filtered_hook)`.
- **Impact:** Enables `dispatch.unregister()` to successfully locate and unregister hooks decorated with `tools=` or `agents=` filters, preventing permanent memory leaks in `_global_hooks`.

## Priority 2: Enforce symlink safety in _safe_extract_zip
- **Target:** `lib/crewai/src/crewai/skills/cache.py:220-228`
- **Action:** In `_safe_extract_zip`, inspect `ZipInfo` attributes for symlink file types (`(info.external_attr >> 16) & 0o170000 == 0o120000`) and refuse extraction, matching the strict symlink refusal policy in `_safe_extractall`.
- **Impact:** Guarantees that extracted skill ZIP archives cannot create symbolic links that point outside the destination cache folder.

## Priority 3: Clean up cache on missing SKILL.md
- **Target:** `lib/crewai/src/crewai/skills/registry.py:385` and `lib/crewai/src/crewai/skills/cache.py:115`
- **Action:** Only write `.crewai_meta.json` after verifying that `SKILL.md` was successfully extracted, and invoke `cache.invalidate(org, name)` if `SKILL.md` is missing.
- **Impact:** Eliminates poisoned cache entries that cause `cache.list_cached()` to list broken skills and prevents perpetual download failure loops.
