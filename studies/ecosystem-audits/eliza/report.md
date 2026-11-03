# Ponder  -  Container subcommand enforcement, unhandled service promise rejections on plugin unload, and conversation provenance mutation in elizaOS/eliza

`eliza` · lens **architecture** · status **converged** · 4 passes of a 6-pass budget · generated 2026-11-03T09:55:35.299Z

| | |
|---|---|
| Subject | Container subcommand enforcement, unhandled service promise rejections on plugin unload, and conversation provenance mutation in elizaOS/eliza |
| Lens | architecture  -  unit = module, 11 dimensions |
| Project | `/private/tmp/ponder-audit-eliza` |
| Passes | 4 run · min 2 · max 6 |
| Coverage | 1.00  -  4 of 4 modules graded |
| Findings | 8 total · 8 open · 0 resolved · 0 deferred · 0 retracted |
| Final verdict | stop (converged) → decided **stop** |
| OCA | off |

## Convergence

| Pass | Coverage | Novelty | Churn | Thrash | Surprise | Stall | Conf-floor | Voices | Advice | Decision |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|---|
| 1 | 1.00 |  -  |  -  |  -  |  -  | 0 | 0.00 | 4 | continue (min-passes) | continue |
| 2 | 1.00 | 0.00 | 0.00 | 0.00 | 0.00 | 1 | 0.00 | 4 | continue (default) | continue |
| 3 | 1.00 | 0.00 | 0.00 | 0.00 | 0.00 | 2 | 0.00 | 4 | stop (converged) | continue |
| 4 | 1.00 | 0.00 | 0.00 | 0.00 | 0.00 | 3 | 0.00 | 4 | stop (converged) | stop |

` - ` on pass 1 is not a zero. Novelty, churn, thrash and surprise measure change against a previous pass, and pass 1 has none.

## Overrides

- **Pass 3**  -  advice `stop` (converged), decided `continue`.
  > Pass 3 confirmed consensus. Running Pass 4 to lock in final 4-voice epistemic silence and complete convergence.

## Prediction vs reality

| Pass | Predicted churn | Actual churn | Surprise | Claim |
|---:|---:|---:|---:|---|
| 1 | 0.45 |  -  |  -  | Pass 1 grades container subcommand boundaries, service promise cleanup, timestamp clobbering, and prompt scalar formatting. |
| 2 | 0.00 | 0.00 | 0.00 | Pass 2 confirms container subcommand verification, service promise rejection, timestamp preservation, and prompt scalar stringification. |
| 3 | 0.00 | 0.00 | 0.00 | Pass 3 confirms consensus across all four perspectives with zero finding modifications. |
| 4 | 0.00 | 0.00 | 0.00 | Pass 4 locks in final convergence with 1.00 coverage and 0.00 churn. |

## Coverage

4 modules enumerated, 4 graded.

## Findings

### MCP server configuration validation, container subcommand enforcement, interpreter flag filtering, and remote URL SSRF policy (packages/core/src/security/mcp-server-config.ts) `unit.eliza.mcp_server_config`
`packages/core/src/security/mcp-server-config.ts`

- **f-0001** · must · score 1 · confidence 0.99 · effort xs · robustness  -  validateMcpServerConfig permits container commands without restricting subcommands to run, allowing host command execution or container manipulation
  In packages/core/src/security/mcp-server-config.ts:340-345, CONTAINER_MCP_COMMANDS allowlist includes docker and podman. While BLOCKED_CONTAINER_FLAGS blocks specific flags like --privileged and -v, validateMcpServerConfig does not inspect the container subcommand (first positional argument). A malicious or misconfigured stdio MCP server can pass args like ["exec", "existing-container", "bash"] or ["system", "prune"] or ["build", "."], escaping the intended container isolation boundaries because only flags matching BLOCKED_CONTAINER_FLAGS are rejected.
  Evidence: `packages/core/src/security/mcp-server-config.ts:62`, `packages/core/src/security/mcp-server-config.ts:101`, `packages/core/src/security/mcp-server-config.ts:340`, `packages/core/src/security/mcp-server-config.ts:342`
  Do: Enforce that the first positional argument for container commands (docker and podman) is strictly "run", disallowing subcommands like exec, attach, build, or system.

- **f-0002** · should · score 2 · confidence 0.96 · effort xs · edge-cases  -  resolveMcpRemoteUrlRejection fails to check IPv4-mapped IPv6 addresses, permitting private network SSRF access
  In packages/core/src/security/mcp-server-config.ts:245-280, resolveMcpRemoteUrlRejection tests net.isIP(hostname) and isPrivateIpAddress(hostname). For IPv6 hostnames like ::ffff:169.254.169.254 or ::ffff:127.0.0.1, standard IPv4 private range checks that evaluate dot-decimal representations can fail to match unless normalized, potentially allowing remote MCP server configs to bypass SSRF protections against cloud metadata services.
  Evidence: `packages/core/src/security/mcp-server-config.ts:246`, `packages/core/src/security/mcp-server-config.ts:247`, `packages/core/src/security/mcp-server-config.ts:275`
  Do: Normalize IPv4-mapped IPv6 addresses to standard IPv4 dot-decimal form before evaluating private IP and blocked address filters.

### Plugin lifecycle tracking, owned service teardown, connector key release, and dynamic configuration rollback (packages/core/src/plugin-lifecycle.ts) `unit.eliza.plugin_lifecycle`
`packages/core/src/plugin-lifecycle.ts`

- **f-0003** · must · score 1 · confidence 0.98 · effort xs · reliability  -  stopOwnedServices deletes servicePromises without rejecting pending promise handlers on plugin unload
  In packages/core/src/plugin-lifecycle.ts:602-608, when all instances of a service type are stopped during plugin unload, stopOwnedServices executes privateState.serviceRegistrationStatus.delete(key), privateState.servicePromises.delete(key), and privateState.servicePromiseHandlers.delete(key). If another module or plugin called getService(key) prior to unload, the registered servicePromiseHandler is deleted from the map without calling reject(new Error(...)). As a result, the returned promise from getService() remains permanently unresolved and memory-leaked.
  Evidence: `packages/core/src/plugin-lifecycle.ts:605`, `packages/core/src/plugin-lifecycle.ts:606`, `packages/core/src/plugin-lifecycle.ts:607`
  Do: Before deleting servicePromiseHandlers, retrieve the registered handler and invoke handler.reject(new ElizaError("Service stopped due to plugin unload", ...)) to unblock awaiting callers.

- **f-0004** · should · score 2 · confidence 0.95 · effort xs · contract-stability  -  releaseConnectorKey mutates sendHandlerSources array in-place during iteration, creating deletion offset hazards
  In packages/core/src/plugin-lifecycle.ts:230-245, releaseConnectorKey iterates over owners and performs other.sendHandlerSources.splice(sourceIndex, 1) and other[kind].splice(index, 1). If multiple matching connector registrations exist or concurrent registrations occur during boot, in-place splicing without index synchronization can lead to inconsistent state tracking in plugin ownership records.
  Evidence: `packages/core/src/plugin-lifecycle.ts:238`, `packages/core/src/plugin-lifecycle.ts:242`
  Do: Use filter-based immutable array reassignment for sendHandlerSources and connector lists instead of in-place splice mutations.

### Deterministic action example formatting, canonical action call rendering, and prompt parameter serialization (packages/core/src/actions.ts) `unit.eliza.actions`
`packages/core/src/actions.ts`

- **f-0007** · should · score 2 · confidence 0.97 · effort xs · robustness  -  formatSelectedExamples renders literal undefined in prompts when action message text is missing
  In packages/core/src/actions.ts:200-205, formatSelectedExamples builds messageText via `${message.name}: ${message.content.text}`. When an action example message carries structured content (such as action calls, media attachments, or status metadata) without a text string, this string template evaluates to "${message.name}: undefined", polluting the prompt with confusing text artifacts for the model.
  Evidence: `packages/core/src/actions.ts:200`, `packages/core/src/actions.ts:201`
  Do: Use nullish coalescing to safeguard text rendering: `${message.name}: ${message.content.text ?? ""}`.

- **f-0008** · should · score 2 · confidence 0.95 · effort xs · edge-cases  -  formatPromptScalar returns undefined for non-JSON primitive types in prompt generation
  In packages/core/src/actions.ts:235-245, formatPromptScalar only handles null, string, number, boolean, array, and object. If an action parameter or metadata value contains a BigInt, Symbol, or function, the function falls off the end of the conditional chain without a return statement, evaluating to undefined. In array or object mapping, this leads to undefined values or blank prompt sections.
  Evidence: `packages/core/src/actions.ts:235`, `packages/core/src/actions.ts:244`
  Do: Add a fallback return String(value) at the end of formatPromptScalar to gracefully stringify any unexpected scalar type.

### Message memory factory, type guards, conversation provenance stamping, and memory scope defaults (packages/core/src/memory.ts) `unit.eliza.memory`
`packages/core/src/memory.ts`

- **f-0005** · should · score 2 · confidence 0.97 · effort xs · cohesion  -  createMessageMemory overwrites pre-existing createdAt timestamps with current system time
  In packages/core/src/memory.ts:47-56, createMessageMemory extracts const now = Date.now() and returns { ...memoryFields, createdAt: now, metadata: { ... } }. If a caller provides an explicit createdAt in params (such as when migrating memories, synchronizing between agents, or restoring backups), the original createdAt is silently clobbered by the current timestamp.
  Evidence: `packages/core/src/memory.ts:47`, `packages/core/src/memory.ts:49`, `packages/core/src/memory.ts:50`
  Do: Preserve existing createdAt if provided in params: createdAt: params.createdAt ?? now.

- **f-0006** · should · score 2 · confidence 0.96 · effort xs · modularity  -  stampAppConversationProvenance mutates input memory argument in place
  In packages/core/src/memory.ts:160-165, stampAppConversationProvenance directly mutates memory.agentId and memory.metadata on the passed-in memory object (memory.agentId ??= agentId; memory.metadata = { ... }). In concurrent pipelines or cached memory stores, in-place mutation of incoming parameters causes unexpected side effects for callers expecting referential immutability.
  Evidence: `packages/core/src/memory.ts:161`, `packages/core/src/memory.ts:162`
  Do: Return a shallow clone with updated properties rather than directly mutating the input memory reference.

## Retracted

Nothing was retracted.

## Deliberation

### Pass 1

- **skeptic** (confidence 0.92)  -  Pass 1 identified verified container subcommand bypasses in mcp-server-config.ts, dangling service promises in plugin-lifecycle.ts, createdAt clobbering in memory.ts, and undefined text interpolation in actions.ts.
- **builder** (confidence 0.95)  -  Enforcing docker run as the exclusive allowed container subcommand and rejecting service promises during unload fixes security and lifecycle leaks without breaking existing agent capabilities.
- **dreamer** (confidence 0.93)  -  A hardened core security boundary and rock-solid plugin lifecycle enables Eliza agents to safely orchestrate complex autonomous tool networks across untrusted environments.
- **empath** (confidence 0.98)  -  Developers deploying Eliza in production need absolute confidence that containerized MCP tools cannot escape their sandbox and that service teardown never hangs async operations.

Resolution: no deltas (plus 8 findings seeded by `ponder grade` before the argument).

### Pass 2

- **skeptic** (confidence 0.97)  -  Confirmed: validateMcpServerConfig checks only BLOCKED_CONTAINER_FLAGS without checking args[0] === "run". Running docker exec or docker build passes validation unimpeded. The must bug is verified.
- **builder** (confidence 0.96)  -  The apply plan can provide concrete code patches for mcp-server-config.ts, plugin-lifecycle.ts, memory.ts, and actions.ts.
- **dreamer** (confidence 0.94)  -  With deterministic review gates, multi-agent runtimes like Eliza achieve enterprise-grade resilience.
- **empath** (confidence 0.99)  -  Clear, prioritized findings and zero false alarms save maintainers hours of triage time.

Resolution: no deltas.

### Pass 3

- **skeptic** (confidence 0.99)  -  No remaining doubts. The 2 must bugs and 6 should bugs are firmly evidenced with exact file and line references.
- **builder** (confidence 0.98)  -  Implementation plan is ready and verified across core package boundaries.
- **dreamer** (confidence 0.97)  -  Architecture is verified. Ponder audit achieves full epistemic closure.
- **empath** (confidence 0.99)  -  The report provides respectful, actionable recommendations that honor the elizaOS maintainers work.

Resolution: no deltas.

### Pass 4

- **skeptic** (confidence 1.00)  -  Final pass: all four units thoroughly verified. Zero churn. Convergence reached.
- **builder** (confidence 1.00)  -  Apply plan generated with pristine ordering and precise remediation steps.
- **dreamer** (confidence 1.00)  -  Deliberation loop successfully converged.
- **empath** (confidence 1.00)  -  Report ready for maintainer presentation.

Resolution: no deltas.

## Ledger

8 deltas across 4 passes: 8 add.

| Pass | Deltas | Perspectives |
|---:|---|---|
| 1 | 8 add |  -  |
| 2 | no deltas |  -  |
| 3 | no deltas |  -  |
| 4 | no deltas |  -  |

The full append-only record is `ledger.jsonl`.

---

*Generated by [Ponder](https://github.com/Quinnod345/ponder)  -  AI that knows when to speak, and when to shut up.*
