# Ponder - Cookie fetch exception safety, eventbus listener preservation, and PDF storage resolution in browser-use

`browser-use` · lens **architecture** · status **converged** · 4 passes of a 6-pass budget · generated 2026-11-03T05:03:30.702Z

| | |
|---|---|
| Subject | Cookie fetch exception safety, eventbus listener preservation, and PDF storage resolution in browser-use |
| Lens | architecture - unit = module, 11 dimensions |
| Project | `/private/tmp/ponder-audit-browser-use` |
| Passes | 4 run · min 2 · max 6 |
| Coverage | 1.00 - 4 of 4 modules graded |
| Findings | 5 total · 4 open · 0 resolved · 0 deferred · 1 retracted |
| Final verdict | stop (converged) → decided **stop** |
| OCA | off |

## Convergence

| Pass | Coverage | Novelty | Churn | Thrash | Surprise | Stall | Conf-floor | Voices | Advice | Decision |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|---|
| 1 | 1.00 | - | - | - | - | 0 | 0.00 | 4 | continue (min-passes) | continue |
| 2 | 1.00 | 0.25 | 0.75 | 0.00 | 0.50 | 0 | 0.00 | 4 | continue (default) | continue |
| 3 | 1.00 | 0.00 | 0.00 | 0.00 | 0.00 | 1 | 0.00 | 4 | continue (default) | continue |
| 4 | 1.00 | 0.00 | 0.00 | 0.00 | 0.00 | 2 | 0.00 | 4 | stop (converged) | stop |

`-` on pass 1 is not a zero. Novelty, churn, thrash and surprise measure change against a previous pass, and pass 1 has none.

## Overrides

None. Every decision followed the engine's advice.

## Prediction vs reality

| Pass | Predicted churn | Actual churn | Surprise | Claim |
|---:|---:|---:|---:|---|
| 1 | 0.45 | - | - | Pass 1 grades skill cookie fetch, eventbus recreation, and PDF path resolution, leaving 1 module unverified. |
| 2 | 0.25 | 0.75 | 0.50 | Pass 2 falsifies YAML unparseability hypothesis, refines strict JSON trailing comma finding, and brings coverage to 1.00. |
| 3 | 0.00 | 0.00 | 0.00 | Pass 3 holds epistemic silence with zero modifications and confirms ledger convergence. |
| 4 | 0.00 | 0.00 | 0.00 | Pass 4 confirms convergence with 0.00 churn, 1.00 coverage, and zero modifications. |

## Coverage

4 modules enumerated, 4 graded.

## Findings

### EventBus recreation in add_new_task drops registered listeners and handlers (browser_use/agent/service.py) `module.browser_use.add_new_task_eventbus_recreation`
`browser_use/agent/service.py`

- **f-0002** · must · score 1 · confidence 0.97 · effort s · cohesion - add_new_task instantiates new EventBus without re-registering core event and action listeners
  In browser_use/agent/service.py:1008-1014, add_new_task prepares the agent for follow-up task execution after previous completion. It sets self.state.follow_up_task = True and recreates the event bus via self.eventbus = EventBus(name=f"Agent_{agent_id_suffix}"). However, the core event listeners, tool handlers, and telemetry subscriptions attached during agent initialization remain bound to the previous closed EventBus instance. Creating a new EventBus without re-subscribing those listeners causes subsequent events dispatched on self.eventbus during the follow-up task to be silently ignored.
  Evidence: `browser_use/agent/service.py:1008-1014`
  Do: Re-register core event and action listeners on the newly instantiated EventBus or implement an eventbus reset/restart lifecycle method.

### Unhandled browser cookie fetch exception in skill action handler (browser_use/agent/service.py) `module.browser_use.skill_action_cookie_exception`
`browser_use/agent/service.py`

- **f-0001** · must · score 1 · confidence 0.98 · effort xs · failure-modes - make_skill_handler executes cookies() outside try-except block causing unhandled crash on browser disconnect
  In browser_use/agent/service.py:877-882, the make_skill_handler closure fetches browser cookies via _cookies = await self.browser_session.cookies() directly above the try block that executes self.skill_service.execute_skill. If the browser target crashed, closed, or dropped its DevTools WebSocket connection, browser_session.cookies() throws an exception (such as ConnectionClosed or TargetClosed). Because the call is placed outside the try block, the exception bubbles out of the action handler and terminates the entire agent step instead of being captured into an ActionResult(error=...) response.
  Evidence: `browser_use/agent/service.py:877-882`
  Do: Wrap the cookie fetch in a try block that intercepts target disconnection and returns an informative ActionResult error.
  _Revised: p2 edit recommendation_

### save_as_pdf path resolution assumes active FileSystem directory (browser_use/tools/service.py) `module.browser_use.save_as_pdf_filesystem_dir`
`browser_use/tools/service.py`

- **f-0003** · should · score 2 · confidence 0.95 · effort xs · failure-modes - save_as_pdf joins destination path against file_system.get_dir() without null validation
  In browser_use/tools/service.py:1652-1662, save_as_pdf constructs the destination path using file_path = file_system.get_dir() / file_name. If FileSystem is initialized without a managed data directory (get_dir() returning None), or if save_as_pdf is executed in an environment without configured filesystem storage, the path operation raises TypeError (unsupported operand type for /: NoneType and str), aborting the PDF export rather than returning a structured ActionResult error or writing to a fallback local temp path.
  Evidence: `browser_use/tools/service.py:1652-1662`
  Do: Verify file_system.get_dir() is non-None before joining, falling back to an OS temporary directory or returning an informative ActionResult error.

### Trailing commas in metadata flow mapping and cross-repo install links (skills/browser-use/SKILL.md) `module.browser_use.skill_frontmatter_metadata`
`skills/browser-use/SKILL.md`

- **f-0005** · should · score 2 · confidence 0.96 · effort xs · standards - Trailing commas in metadata flow mapping break strict JSON parsers and docs link points out of repo
  In skills/browser-use/SKILL.md:6-21, metadata is defined using a JSON-style flow mapping containing trailing commas ("label": "Install Browser Use CLI (uv)", and bins: ["browser-use"],). While standard YAML engines accept trailing commas in flow sequences, agent distribution tools that extract the metadata scalar and pass it to JSON.parse() fail with SyntaxError. Furthermore, lines 26-28 refer developers to browser-use/browser-harness/blob/main/install.md rather than the canonical browser-use/browser-use repository.
  Evidence: `skills/browser-use/SKILL.md:6-21`, `skills/browser-use/SKILL.md:26-28`
  Do: Remove trailing commas from the metadata block and update documentation links to point to canonical browser-use repository paths.

## Retracted

Retraction is a state, not an erasure - a later pass can reverse any of these.

- `f-0004` (module.browser_use.skill_frontmatter_metadata) - Unverified hypothesis: SKILL.md metadata block is entirely unparseable by all YAML tools · retracted in pass 2 by the skeptic: Falsified by Skeptic: YAML 1.2 specification permits flow mappings with curly braces in frontmatter.

## Deliberation

### Pass 1

- **skeptic** (confidence 0.88) - Browser cookie fetching before try block risks unhandled step crashes when targets close. The frontmatter unparseability claim requires verification against YAML flow mapping specs.
- **builder** (confidence 0.92) - Moving cookie retrieval inside the try block and checking get_dir() are zero-risk fixes with high reliability payoff.
- **dreamer** (confidence 0.90) - Agent sessions should support seamless follow-up tasks without listener loss or event disconnection.
- **empath** (confidence 0.91) - Users expect follow-up tasks to maintain full tool capabilities and browser disconnections to yield actionable error messages.

Resolution: no deltas (plus 4 findings seeded by `ponder grade` before the argument).

### Pass 2

- **skeptic** (confidence 0.98) - Falsified the claim that YAML parsers fail. YAML 1.2 flow mappings accept the block. However, strict JSON parsers (RFC 8259) fail on trailing commas in metadata.openclaw.install. Deleting decoy hypothesis.
- **builder** (confidence 0.97) - Anchor verified finding to skills/browser-use/SKILL.md:6-21 and update recommendation.
- **dreamer** (confidence 0.96) - Grading the frontmatter standard brings all 4 units to complete grading with 1.00 coverage.
- **empath** (confidence 0.97) - Clear, compliant metadata prevents installation errors when developers install the browser-use skill.

Resolution: 1 add, 1 edit, 1 delete.

### Pass 3

- **skeptic** (confidence 0.99) - All 4 modules verified. Zero new anomalies detected. Epistemic silence holds.
- **builder** (confidence 0.99) - Implementation plans and diffs are ready. All 4 target files mapped with line references.
- **dreamer** (confidence 0.99) - Deliberation ledger fully converged with 1.00 coverage and 0.00 churn.
- **empath** (confidence 0.99) - High signal audit ready for the browser-use maintainers and ecosystem documentation.

Resolution: no deltas.

### Pass 4

- **skeptic** (confidence 1.00) - Audit converged. All 4 target modules verified. Zero reversals or regressions.
- **builder** (confidence 1.00) - Ready to write final report and apply-plan.
- **dreamer** (confidence 1.00) - Convergence achieved across 4 passes with uncompromised coverage gate.
- **empath** (confidence 1.00) - browser-use team receives verified, reproducible receipts with zero hallucinated issues.

Resolution: no deltas.

## Ledger

7 deltas across 4 passes: 5 add, 1 edit, 1 delete.

| Pass | Deltas | Perspectives |
|---:|---|---|
| 1 | 4 add | - |
| 2 | 1 add, 1 edit, 1 delete | builder, skeptic |
| 3 | no deltas | - |
| 4 | no deltas | - |

The full append-only record is `ledger.jsonl`.

---

*Generated by [Ponder](https://github.com/Quinnod345/ponder) - AI that knows when to speak, and when to shut up.*
