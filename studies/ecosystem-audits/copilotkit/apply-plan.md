# Apply Plan: CopilotKit/CopilotKit (38.5k★)

## Priority 1: Prevent JSON Patch Move Ancestor Destruction and Enforce Atomic Rollback
- **Target:** `packages/runtime/src/agent/state-delta.ts:160-220, 300-315`
- **Action:** Reject moves where `from` is an ancestor of `path`, and clone before applying so mutations are atomic:
```typescript
    case "move": {
      if (typeof operation.from !== "string") return { root, applied: false };
      const from = parseJsonPointer(operation.from);
      if (from === undefined) return { root, applied: false };
      const source = getJsonPointerValue(root, operation.from);
      if (!source.exists) return { root, applied: false };
      if (operation.from === operation.path) return { root, applied: true };

      // Prevent moving an ancestor into one of its own descendants
      if (
        path.length > from.length &&
        from.every((segment, i) => segment === path[i])
      ) {
        return { root, applied: false };
      }

      const nextRoot = cloneState(root);
      const removed = removeValue(nextRoot, from);
      if (!removed.applied) return { root, applied: false };
      const added = addValue(removed.root, path, source.value);
      return added.applied ? added : { root, applied: false };
    }
```

---

## Priority 2: Use Segment-Based Parent Resolution in normalizeStateDelta
- **Target:** `packages/runtime/src/agent/state-delta.ts:327-348`
- **Action:** Parse JSON pointer into segments rather than naive `lastIndexOf("/")` substring matching:
```typescript
    if (
      candidate?.op === "add" &&
      typeof candidate.path === "string" &&
      candidate.path.endsWith("/-")
    ) {
      const segments = parseJsonPointer(candidate.path);
      if (segments && segments.length >= 2) {
        const arraySegments = segments.slice(0, -1);
        const arrayPath = encodeJsonPointer(arraySegments);
        const array = getJsonPointerValue(state, arrayPath);
        if (!array.exists) {
          const parentSegments = arraySegments.slice(0, -1);
          const parentPath = encodeJsonPointer(parentSegments);
          if (getJsonPointerValue(state, parentPath).exists) {
            const initializer: StateDeltaOperation = {
              op: "add",
              path: arrayPath,
              value: [],
            };
            const applied = applyStateDeltaOperation(state, initializer);
            if (applied.applied) {
              normalized.push(initializer);
              state = applied.root;
            }
          }
        }
      }
    }
```

---

## Priority 3: Track Intra-Source Duplicate Tool Names in resolveMCPToolNames
- **Target:** `packages/runtime/src/agent/mcp-tool-names.ts:46-75`
- **Action:** Detect duplicates within individual sources and ensure uniqueness:
```typescript
  const sourceCount = new Map<string, number>();
  for (const { names } of sources) {
    const seenInSource = new Set<string>();
    for (const name of names) {
      if (seenInSource.has(name)) {
        // Flag intra-source duplicate so it receives disambiguation prefix
        sourceCount.set(name, (sourceCount.get(name) ?? 0) + 2);
      } else {
        seenInSource.add(name);
        sourceCount.set(name, (sourceCount.get(name) ?? 0) + 1);
      }
    }
  }
```

---

## Priority 4: Index Tool Calls for O(1) Tool Message Lookup in convertMessagesToVercelAISDKMessages
- **Target:** `packages/runtime/src/agent/index.ts:777-805`
- **Action:** Index assistant tool calls once in a Map<string, string> to eliminate nested iteration and break completely:
```typescript
    } else if (message.role === "tool") {
      let toolName = "unknown";
      outer: for (const msg of messages) {
        if (msg.role === "assistant") {
          for (const toolCall of msg.toolCalls ?? []) {
            if (toolCall.id === message.toolCallId) {
              toolName = toolCall.function.name;
              break outer;
            }
          }
        }
      }
```

---

## Priority 5: Forward Abort Signal to registry.acquireSnapshot
- **Target:** `packages/runtime/src/agent/learned-skills.ts:45-59`
- **Action:** Propagate consumer abort signal to registry method:
```typescript
async function acquireSnapshot(registry: SkillRegistry, signal: AbortSignal) {
  signal.throwIfAborted();
  return registry.acquireSnapshot(signal);
}
```

---

## Priority 6: Support Case-Insensitive SKILL.md Resolution
- **Target:** `packages/runtime/src/v2/runtime/intelligence-platform/skill-registry/skill-content.ts:32-35`
- **Action:** Accept uppercase and lowercase variants of SKILL.md:
```typescript
export function loadSkill(snapshot: VerifiedSnapshot, name: string): string {
  const skill = findSkill(snapshot, name);
  const content = skill.files.find(
    (file) => file.path.toLowerCase() === "skill.md"
  )?.text;
  if (content === undefined) throw new Error("Skill is unavailable.");
  return JSON.stringify({
    skill_name: skill.name,
    content,
    files: skill.files
      .filter((file) => file.path.toLowerCase() !== "skill.md" && file.text !== undefined)
      .map((file) => file.path)
      .sort(compare),
  });
}
```
