# Ponder Multi-Pass Audit: CopilotKit/CopilotKit (38.5k★)

## Executive Summary
- **Target Repository:** `CopilotKit/CopilotKit` (38.5k stars, [GitHub](https://github.com/CopilotKit/CopilotKit))
- **Audit Tool:** Ponder (4-perspective deliberation loop: skeptic, builder, dreamer, empath)
- **Convergence:** 3 passes, 1.00 coverage across 4 key units, 0.00 churn at fixed point.
- **Key Findings:**
  1. `applyStateDeltaOperation` for "move" deletes the source path via `removeValue(nextRoot, from)` before invoking `addValue`. When `from` is an ancestor prefix of `path`, removing the parent destroys the destination path, causing destination addition to fail while permanently deleting the source subtree. Furthermore, `addValue`, `removeValue`, and `replaceValue` mutate `parent.value` in place on `root`, leaving partial mutations on midway failures without transaction rollback.
  2. `normalizeStateDelta` slices `arrayPath.lastIndexOf("/")` to find parent containers for synthesized array initializers, splitting escaped JSON pointer tokens (`~1` and `~0`) midway and creating invalid paths when property keys contain slashes or tildes.
  3. `resolveMCPToolNames` counts name frequencies across sources with `new Set(names)`, ignoring duplicates within the same MCP source. Un-prefixed duplicate tool names are emitted to model providers, triggering tool validation rejections.
  4. `convertMessagesToVercelAISDKMessages` uses a nested loop for `role: "tool"` messages where `break` only exits the inner tool-call loop, continuing the outer message scan across all remaining messages; defaults to `toolName = "unknown"` when context truncation prunes earlier assistant turns.
  5. `acquireSnapshot` in `learned-skills.ts` rejects on consumer abort signal but fails to cancel the underlying background `registry.acquireSnapshot()` request and archive extraction.
  6. `loadSkill` in `skill-content.ts` strictly checks exact case `file.path === "SKILL.md"`, dropping skills named `skill.md` or `Skill.md` without case-insensitive fallback.
  7. Skeptic verification successfully falsified the IPv4-mapped IPv6 SSRF hypothesis by verifying `buildAddressPolicy` normalizes mapped addresses before subnet comparison, retracting the false alarm with zero churn in Pass 2.
