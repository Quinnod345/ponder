# Apply Plan: Nutlope/hallmark Audit

Generated from Ponder deliberation audit session `hallmark` (4 passes, 1.00 coverage, 0.00 churn).

## Priority 1: Cross-platform Windows file name extraction in lint-hook.mjs
- **Target:** `skills/hallmark/scripts/lint-hook.mjs:29`
- **Action:** Replace `const name = filePath.split("/").pop();` with `const name = basename(filePath);` (importing `basename` from `node:path`).
- **Impact:** Prevents full Windows paths from overflowing Claude Code hook context strings.

## Priority 2: Fallback copy strategy on EXDEV in install.mjs
- **Target:** `skills/hallmark/scripts/install.mjs:54`
- **Action:** Wrap `fs.renameSync(tmp, dir)` in a try-catch block falling back to `copyDir(tmp, dir); fs.rmSync(tmp, { recursive: true, force: true });` when `err.code === 'EXDEV'`.
- **Impact:** Eliminates install crashes when installing across container mounts or filesystem boundaries.

## Priority 3: Clean hook pruning in install-hook.mjs
- **Target:** `skills/hallmark/scripts/install-hook.mjs:29-33`
- **Action:** In `withoutOurs`, filter out entries where `hooks` is empty, and on `--remove`, delete `settings.hooks.PostToolUse` if empty.
- **Impact:** Leaves `settings.json` clean without orphaned empty arrays.
