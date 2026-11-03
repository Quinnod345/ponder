# Letta Remediation Plan

## Priority 1: Catch file lock timeout in claimMemoryConflictRepair
- **Target:** `src/agent/memory-conflict-repair.ts:133-176`
- **Action:** Catch timeout errors from `updateAttempt` and return `{ status: "in_progress" }`:
```typescript
  try {
    return await updateAttempt(
      path,
      async (previous) => {
        // ...
      },
      CLAIM_TIMEOUT_MS,
    );
  } catch (error) {
    debugWarn("memory-repair", `Claim timeout or lock contention: ${String(error)}`);
    return { status: "in_progress" };
  }
```

---

## Priority 2: Canonical git-dir resolution in withSerializedGitConfigMutation
- **Target:** `src/agent/memory-git-config-lock.ts:50-60`
- **Action:** Resolve the underlying git directory to ensure uniform queue keys:
```typescript
export async function withSerializedGitConfigMutation(
  dir: string,
  mutate: () => Promise<unknown>,
): Promise<void> {
  const resolved = resolve(dir);
  const gitDir = resolved.endsWith(".git") ? resolved : join(resolved, ".git");
  const key = gitDir;
  // ...
}
```

---

## Priority 3: UTF-8 safe buffer slicing in capTaskEvent
- **Target:** `src/agent/subagent-events.ts:35-51`
- **Action:** Adjust truncation boundary to avoid splitting multi-byte UTF-8 sequences:
```typescript
  let keep = Math.max(0, text.length - (size - maxBytes) - 128);
  // Rewind boundary if sitting on a UTF-8 continuation byte (0b10xxxxxx)
  while (keep > 0 && (text[keep] & 0xc0) === 0x80) {
    keep -= 1;
  }
  const dropped = text.length - keep;
```

---

## Priority 4: Multi-level directory watching in ClientSkillsWatcher
- **Target:** `src/agent/client-skills-watcher.ts:140-160`
- **Action:** Re-check nearest existing directory on mutation or watch recursively when supported:
```typescript
  private watchRoot(root: string): void {
    const existingDirectory = findNearestExistingDirectory(root);
    if (!existingDirectory) return;
    // When intermediate directories are created, re-evaluate watchRoot target
    // ...
  }
```

---

## Priority 5: Isolate invalid history signatures by branch name
- **Target:** `src/agent/memory-conflict-repair.ts:79-92`
- **Action:** Include local branch HEAD or branch ref in invalid signature:
```typescript
async function describeInvalidMemoryHistory(memoryDir: string): Promise<string> {
  try {
    const { stdout } = await promisify(execFile)("git", [
      "-C", memoryDir, "rev-parse", "--verify", "@{u}",
    ]);
    return `invalid\n${stdout.trim()}`;
  } catch {
    const { stdout } = await promisify(execFile)("git", [
      "-C", memoryDir, "rev-parse", "--abbrev-ref", "HEAD",
    ]).catch(() => ({ stdout: "unknown" }));
    return `invalid\nlocal:${stdout.trim()}`;
  }
}
```

---

## Priority 6: Increase retry backoff for git config lock contention
- **Target:** `src/agent/memory-git-config-lock.ts:25-30`
- **Action:** Increase attempts and max delay to tolerate multi-second git operations:
```typescript
const GIT_CONFIG_LOCK_ATTEMPTS = 8;
const GIT_CONFIG_LOCK_BASE_DELAY_MS = 50;
```
