---
name: code
unit: file
enumerate: |
  A unit is a source file, module, or script under review. When auditing a pull
  request or commit range, use `ponder units --diff <ref>` so the inventory is
  seeded directly from `git diff` without omitting any touched file.

  Work in three sweeps.

  Sweep 1 - modified or untracked files in the active branch or working tree.
  git diff --name-only --diff-filter=d HEAD
  git ls-files --others --exclude-standard

  Sweep 2 - direct callers and importers of every modified symbol.
  rg -n 'import .* from|require\(' -g '!node_modules' .

  Sweep 3 - error handling, state mutations, and resource cleanup paths.
  rg -n 'catch\s*\(|finally\s*\{|close\(|destroy\(|abort\(' -g '!node_modules' .
dimensions: [correctness, error-handling, boundary-conditions, state-and-concurrency, resource-lifecycle, maintainability]
scale:
  1: broken - reproducible logic bug, unhandled failure, data corruption, or race condition on reachable inputs
  2: bad - fragile control flow, silent error swallowing, or unguarded edge case
  3: acceptable - works on happy paths but lacks defensive guards or clear invariants
  4: good - handles edge cases, errors, and cleanup paths cleanly with explicit invariants
  5: exemplary - self-evident invariants, fail-safe error recovery, and zero dead or speculative code
---

# Code Review Lens

Grade every source `file` in the inventory across the six code quality dimensions:

1. **`correctness`**: Does the implementation match its specification and caller contract across all reachable inputs?
2. **`error-handling`**: Are failures propagated with actionable context rather than silently swallowed or left partially mutated?
3. **`boundary-conditions`**: Are empty inputs, zero/negative numbers, `null`/`undefined`, off-by-one indices, and encoding boundaries handled safely?
4. **`state-and-concurrency`**: Are shared state updates, async races, lock lifetimes, and idempotency invariants sound?
5. **`resource-lifecycle`**: Are file descriptors, child processes, timers, listeners, and temporary directories cleaned up on both success and error paths?
6. **`maintainability`**: Is the control flow direct, minimal, and free of dead branches or speculative abstractions?
