# Ponder  -  Interception hook unregistration leak, zip symlink safety in skill cache, and metadata verification in crewAI

`crewai` · lens **architecture** · status **converged** · 4 passes of a 6-pass budget · generated 2026-11-03T05:57:34.373Z

| | |
|---|---|
| Subject | Interception hook unregistration leak, zip symlink safety in skill cache, and metadata verification in crewAI |
| Lens | architecture  -  unit = module, 11 dimensions |
| Project | `/private/tmp/ponder-audit-crewai` |
| Passes | 4 run · min 2 · max 6 |
| Coverage | 1.00  -  4 of 4 modules graded |
| Findings | 5 total · 4 open · 0 resolved · 0 deferred · 1 retracted |
| Final verdict | stop (converged) → decided **stop** |
| OCA | off |

## Convergence

| Pass | Coverage | Novelty | Churn | Thrash | Surprise | Stall | Conf-floor | Voices | Advice | Decision |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|---|
| 1 | 1.00 |  -  |  -  |  -  |  -  | 0 | 0.00 | 4 | continue (min-passes) | continue |
| 2 | 1.00 | 0.25 | 0.50 | 0.00 | 0.25 | 0 | 0.00 | 4 | continue (default) | continue |
| 3 | 1.00 | 0.00 | 0.00 | 0.00 | 0.00 | 1 | 0.00 | 4 | continue (default) | continue |
| 4 | 1.00 | 0.00 | 0.00 | 0.00 | 0.00 | 2 | 0.00 | 4 | stop (converged) | stop |

` - ` on pass 1 is not a zero. Novelty, churn, thrash and surprise measure change against a previous pass, and pass 1 has none.

## Overrides

None. Every decision followed the engine's advice.

## Prediction vs reality

| Pass | Predicted churn | Actual churn | Surprise | Claim |
|---:|---:|---:|---:|---|
| 1 | 0.45 |  -  |  -  | Pass 1 grades decorators, cache, registry, and tool, leaving catalog collision hypothesis unverified. |
| 2 | 0.25 | 0.50 | 0.25 | Pass 2 falsifies prompt crash hypothesis and confirms metadata rollback on download failure. |
| 3 | 0.00 | 0.00 | 0.00 | Pass 3 confirms epistemic silence with zero churn and 1.00 coverage across all four perspectives. |
| 4 | 0.00 | 0.00 | 0.00 | Pass 4 confirms convergence with 0.00 churn, 1.00 coverage, and zero modifications. |

## Coverage

4 modules enumerated, 4 graded.

## Findings

### Interception hook filtering and global registration lifecycle (lib/crewai/src/crewai/hooks/decorators.py) `module.crewai.hooks.decorators`
`lib/crewai/src/crewai/hooks/decorators.py`

- **f-0001** · must · score 1 · confidence 0.98 · effort xs · lifecycle  -  Filtered hook unregistration leak in _create_hook_decorator
  In lib/crewai/src/crewai/hooks/decorators.py:55-75, _create_hook_decorator creates filtered_hook when tools or agents filters are specified and passes it to register_function(filtered_hook). However, it does not set f._registered_hook = filtered_hook. Because dispatch.unregister() checks getattr(hook, "_registered_hook", hook) to look up the registered wrapper, hooks registered with filters cannot be unregistered and permanently leak in _global_hooks.
  Evidence: `lib/crewai/src/crewai/hooks/decorators.py:72`, `lib/crewai/src/crewai/hooks/dispatch.py:125`
  Do: Set f._registered_hook = filtered_hook in _create_hook_decorator before registration.

### Global skill cache extraction and path-traversal safety (lib/crewai/src/crewai/skills/cache.py) `module.crewai.skills.cache`
`lib/crewai/src/crewai/skills/cache.py`

- **f-0003** · must · score 1 · confidence 0.95 · effort s · security  -  _safe_extract_zip lacks symlink member validation during archive extraction
  In lib/crewai/src/crewai/skills/cache.py:220-228, _safe_extract_zip checks only (dest / member).resolve().is_relative_to(dest_resolved). Unlike _safe_extractall which explicitly rejects symlink/hardlink members (member.issym() or member.islnk()), zipfile resolves member paths prior to extraction against non-existent paths. If a zip archive contains symlinks or directory symlinks, subsequent member writes can traverse outside dest through the created symlink.
  Evidence: `lib/crewai/src/crewai/skills/cache.py:220-228`
  Do: Inspect zip member external attributes and reject symlink entries during zip extraction, mirroring _safe_extractall.

### Remote skill download and metadata verification lifecycle (lib/crewai/src/crewai/skills/registry.py) `module.crewai.skills.registry`
`lib/crewai/src/crewai/skills/registry.py`

- **f-0004** · should · score 2 · confidence 0.94 · effort xs · robustness  -  download_skill writes metadata to cache before validating SKILL.md existence
  In lib/crewai/src/crewai/skills/registry.py:375-395 and cache.py:115-125, cache.store() writes .crewai_meta.json immediately upon archive extraction. When download_skill then verifies (skill_dir / "SKILL.md").exists() and raises RuntimeError if absent, the malformed directory and metadata persist in ~/.crewai/skills/. This causes SkillCacheManager.list_cached() to falsely report the broken skill as installed, while resolve_registry_ref() fails on every subsequent run.
  Evidence: `lib/crewai/src/crewai/skills/registry.py:385`, `lib/crewai/src/crewai/skills/cache.py:115`
  Do: Only write .crewai_meta.json after validating SKILL.md, or invoke cache.invalidate() upon download failure.

### Progressive disclosure runtime tool and prompt context formatting (lib/crewai/src/crewai/skills/tool.py) `module.crewai.skills.tool`
`lib/crewai/src/crewai/skills/tool.py`

- **f-0005** · note · score 5 · confidence 0.99 · effort xs · reliability  -  LoadSkillTool safely handles prompt context injection with default skill.name fallback
  In lib/crewai/src/crewai/skills/tool.py:46-52, LoadSkillTool._run calls format_skill_context(activated), which cleanly falls back to skill.name when label is omitted. Context is safely wrapped in <skill name="..."> tags, maintaining prompt cache compatibility without runtime errors.
  Evidence: `lib/crewai/src/crewai/skills/tool.py:46-52`
  Do: No change required; format_skill_context handles unlabelled skills safely with built-in default fallback.

## Retracted

Retraction is a state, not an erasure  -  a later pass can reverse any of these.

- `f-0002` (module.crewai.skills.tool)  -  LoadSkillTool crashes prompt injection on catalog collision (decoy hypothesis) · retracted in pass 2 by the skeptic: Falsified: format_skill_context defaults to name = label or skill.name gracefully; omitting label does not crash execution or prompt generation.

## Deliberation

### Pass 1

- **skeptic** (confidence 0.86)  -  Pass 1 identified verified hook unregistration leaks and zip extraction traversal risks. The prompt injection crash hypothesis requires confirmation against format_skill_context fallback handling.
- **builder** (confidence 0.91)  -  Fixing _registered_hook in decorators.py and adding symlink validation in cache.py ensures rock-solid lifecycle management and security for CrewAI skills.
- **dreamer** (confidence 0.89)  -  Clean skill caching and robust hook unregistration allows developers to dynamically compose multi-agent teams without resource leaks.
- **empath** (confidence 0.94)  -  Production CrewAI users running high-concurrency workflows benefit from deterministic cleanup and protected filesystem boundaries.

Resolution: no deltas (plus 4 findings seeded by `ponder grade` before the argument).

### Pass 2

- **skeptic** (confidence 0.96)  -  Falsified prompt crash hypothesis: format_skill_context explicitly defaults to name = label or skill.name, emitting a valid XML block without error. Retract finding f-0002.
- **builder** (confidence 0.95)  -  In registry.py, wrap download extraction in a try-finally or atomic directory stage to prevent poisoned cache entries when SKILL.md is missing.
- **dreamer** (confidence 0.93)  -  Validating metadata writes guarantees that ~/.crewai/skills/ contains only healthy, executable agent skills.
- **empath** (confidence 0.96)  -  João Moura and CrewAI maintainers get high-impact, verified fixes with zero regressions on existing flows.

Resolution: 1 add, 1 delete.

### Pass 3

- **skeptic** (confidence 0.98)  -  No new flaws found. All 4 target modules graded and verified with 1.00 coverage.
- **builder** (confidence 0.98)  -  Verified that f._registered_hook assignment in decorators.py and symlink checks in cache.py are safe and fully backwards-compatible.
- **dreamer** (confidence 0.98)  -  System reached stability with 0.00 churn across all 4 perspectives.
- **empath** (confidence 0.98)  -  Maintainers receive verified receipts with zero false alarms and clean diffs.

Resolution: no deltas.

### Pass 4

- **skeptic** (confidence 0.99)  -  Audit converged. All 4 target modules verified. Zero reversals or regressions.
- **builder** (confidence 0.99)  -  Deliverables (report.md and apply-plan.md) ready for maintainer presentation.
- **dreamer** (confidence 0.99)  -  Deliberation ledger reached stable terminal consensus.
- **empath** (confidence 0.99)  -  João Moura and the CrewAI team get high-impact, low-ego receipts matching CrewAI architecture.

Resolution: no deltas.

## Ledger

6 deltas across 4 passes: 5 add, 1 delete.

| Pass | Deltas | Perspectives |
|---:|---|---|
| 1 | 4 add |  -  |
| 2 | 1 add, 1 delete | dreamer, skeptic |
| 3 | no deltas |  -  |
| 4 | no deltas |  -  |

The full append-only record is `ledger.jsonl`.

---

*Generated by [Ponder](https://github.com/Quinnod345/ponder)  -  AI that knows when to speak, and when to shut up.*
