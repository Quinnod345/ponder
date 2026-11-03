# Apply Plan: elizaOS/eliza Audit

Generated from Ponder deliberation audit session `eliza` (4 passes, 1.00 coverage, 0.00 churn).

## Priority 1: Restrict container commands to "run" subcommand in validateMcpServerConfig
- **Target:** `packages/core/src/security/mcp-server-config.ts:340-345`
- **Action:** Ensure the first positional argument for container commands (`docker` and `podman`) is strictly `run`:
```typescript
			if (CONTAINER_MCP_COMMANDS.has(normalizedCommand)) {
				const subcommand = firstPositionalArg(args);
				if (subcommand !== "run") {
					return `Container command "${normalizedCommand}" must use the "run" subcommand (received "${subcommand ?? ""}")`;
				}
				const blocked = hasBlockedFlag(args, BLOCKED_CONTAINER_FLAGS);
				if (blocked) {
					return `Flag "${blocked}" is not allowed for ${normalizedCommand} MCP servers`;
				}
			}
```
- **Impact:** Prevents container isolation escapes via unrestricted container subcommands (`exec`, `system`, `build`).

## Priority 2: Reject pending service promise handlers on plugin unload in stopOwnedServices
- **Target:** `packages/core/src/plugin-lifecycle.ts:602-608`
- **Action:** Before deleting `servicePromiseHandlers`, retrieve any registered handler and reject it with an explanatory error:
```typescript
		} else {
			runtime.services.delete(key);
			if (remainingClasses.length > 0) {
				privateState.serviceRegistrationStatus.set(key, "pending");
			} else {
				privateState.serviceRegistrationStatus.delete(key);
				const pendingHandler = privateState.servicePromiseHandlers.get(key);
				if (pendingHandler) {
					pendingHandler.reject(new ElizaError(
						`Service "${key}" is no longer available because the owning plugin was unloaded`,
						{ code: "SERVICE_UNLOADED" }
					));
				}
				privateState.servicePromises.delete(key);
				privateState.servicePromiseHandlers.delete(key);
			}
		}
```
- **Impact:** Eliminates permanently hanging async calls when services are unloaded while callers are awaiting them.

## Priority 3: Preserve pre-existing createdAt in createMessageMemory
- **Target:** `packages/core/src/memory.ts:47-56`
- **Action:** Preserve explicit `createdAt` if provided in params:
```typescript
	const { scope, createdAt: providedCreatedAt, ...memoryFields } = params;
	const now = Date.now();
	const createdAt = providedCreatedAt ?? now;
	return {
		...memoryFields,
		createdAt,
		metadata: {
			type: MemoryType.MESSAGE,
			timestamp: createdAt,
			scope: scope ?? (params.agentId ? "private" : "shared"),
		},
	};
```
- **Impact:** Ensures historical memories retain their original creation timestamps across synchronizations and imports.

## Priority 4: Return immutable clone in stampAppConversationProvenance
- **Target:** `packages/core/src/memory.ts:160-165`
- **Action:** Return a shallow copy with stamped properties rather than mutating input in place:
```typescript
	return {
		...memory,
		agentId: memory.agentId ?? agentId,
		metadata: {
			...metadataRecord,
			type: "message",
			scope: memory.metadata?.scope ?? "private",
			provider,
			accountId,
			platformMessageId,
		},
	};
```
- **Impact:** Prevents accidental shared-state mutation across callers and pipelines.

## Priority 5: Add nullish coalescing to messageText in formatSelectedExamples
- **Target:** `packages/core/src/actions.ts:200-205`
- **Action:** Prevent rendering literal `undefined` when action message content has no text string:
```typescript
				.map((message) => {
					let messageText = `${message.name}: ${message.content.text ?? ""}`;
```
- **Impact:** Eliminates `undefined` artifacts from prompt action examples.

## Priority 6: Provide scalar fallback in formatPromptScalar
- **Target:** `packages/core/src/actions.ts:235-245`
- **Action:** Fall back to stringification for any non-handled scalar:
```typescript
	return String(value);
```
- **Impact:** Prevents `undefined` evaluation for BigInts or symbol parameters in prompt formatting.
