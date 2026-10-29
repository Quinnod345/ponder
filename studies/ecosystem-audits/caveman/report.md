# Ponder - Audit JuliusBrussee/caveman standalone hook installers and OpenCode plugin config resolution

`caveman-hooks-opencode` · lens **architecture** · status **stopped** · 4 passes of a 6-pass budget · generated 2026-10-29T19:15:20.502Z

| | |
|---|---|
| Subject | Audit JuliusBrussee/caveman standalone hook installers and OpenCode plugin config resolution |
| Lens | architecture - unit = module, 11 dimensions |
| Project | `/Users/quinnodonnell/.gemini/antigravity/scratch/caveman` |
| Passes | 4 run · min 2 · max 6 |
| Coverage | 1.00 - 5 of 5 modules graded |
| Findings | 6 total · 5 open · 0 resolved · 0 deferred · 1 retracted |
| Final verdict | continue (default) → decided **stop** |
| OCA | enabled but unreachable |

## Convergence

| Pass | Coverage | Novelty | Churn | Thrash | Surprise | Stall | Conf-floor | Voices | Advice | Decision |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|---|
| 1 | 1.00 | - | - | - | - | 0 | 0.00 | 4 | continue (min-passes) | continue |
| 2 | 1.00 | 0.20 | 0.40 | 0.00 | 0.15 | 0 | 0.00 | 4 | continue (default) | continue |
| 3 | 1.00 | 0.00 | 0.20 | 0.00 | 0.10 | 0 | 0.00 | 4 | continue (default) | continue |
| 4 | 1.00 | 0.00 | 0.00 | 0.00 | 0.00 | 1 | 0.00 | 4 | continue (default) | stop |

`-` on pass 1 is not a zero. Novelty, churn, thrash and surprise measure change against a previous pass, and pass 1 has none.

## Overrides

- **Pass 4** - advice `continue` (default), decided `stop`.
  > Converged across 4 passes after retracting 1 false positive in Pass 2 and verifying 3 must findings with deterministic reproducers.

## Prediction vs reality

| Pass | Predicted churn | Actual churn | Surprise | Claim |
|---:|---:|---:|---:|---|
| 1 | 0.45 | - | - | Pass 1 will find JSONC parser divergence in install.sh/install.ps1 ALREADY_INSTALLED probes and missing projectDir + defaultMode=off guard in OpenCode plugin.js |
| 2 | 0.25 | 0.40 | 0.15 | Pass 2 will falsify f-0004 (path.dirname on path.resolve is strictly decreasing in segment count) and replace it with a verified note on hooks.config. |
| 3 | 0.10 | 0.20 | 0.10 | Pass 3 will refine f-0001 recommendation with the exact regression test target in tests/hooks/standalone-install-safety.test.mjs and approach convergence. |
| 4 | 0.00 | 0.00 | 0.00 | Pass 4 will produce zero deltas as all 3 must findings and 2 clean module grades have converged. |

## Coverage

5 modules enumerated, 5 graded.

## Findings

### Standalone PowerShell hook installer (src/hooks/install.ps1) `hooks.install_ps1`
`src/hooks/install.ps1`

- **f-0002** · must · score 1 · confidence 0.95 · effort xs · failure-modes - install.ps1 ALREADY_INSTALLED probe uses PowerShell ConvertFrom-Json instead of CAVEMAN_SETTINGS_HELPER, failing on JSONC comments in Windows PowerShell 5.1
  src/hooks/install.ps1 uses node with CAVEMAN_SETTINGS_HELPER for both the preflight check (lines 36-59) and the settings merge step (lines 150-222), but lines 80-112 use Get-Content $SettingsFile -Raw \| ConvertFrom-Json for the ALREADY_INSTALLED check. In Windows PowerShell 5.1 (powershell.exe), ConvertFrom-Json rejects // comments and trailing commas, throwing inside the try/catch block so $alreadyInstalled stays $false and the merge step overwrites settings.json as plain JSON.
  Evidence: `src/hooks/install.ps1:36-59`, `src/hooks/install.ps1:80-112`, `src/hooks/install.ps1:150-166`
  Do: Replace the ConvertFrom-Json ALREADY_INSTALLED check in src/hooks/install.ps1:80-112 with a node probe that uses CAVEMAN_SETTINGS_HELPER.

### Standalone POSIX hook installer (src/hooks/install.sh) `hooks.install_sh`
`src/hooks/install.sh`

- **f-0001** · must · score 1 · confidence 0.95 · effort xs · contract-stability - install.sh ALREADY_INSTALLED probe omits CAVEMAN_SETTINGS_HELPER and calls bare JSON.parse, overwriting JSONC settings.json on re-run without --force
  src/hooks/install.sh loads installer/lib/settings.js via CAVEMAN_SETTINGS_HELPER in the JSONC preflight check (lines 54-75) and the settings merge step (lines 173-181), allowing // comments, /* */ comments, and trailing commas in settings.json. However, the ALREADY_INSTALLED fast-path check at lines 93-114 omits CAVEMAN_SETTINGS_HELPER and calls bare JSON.parse(fs.readFileSync(process.env.CAVEMAN_SETTINGS, 'utf8')). If a user with caveman hooks already wired adds a JSONC comment or trailing comma to settings.json and re-runs install.sh without --force, JSON.parse throws inside the silenced >/dev/null 2>&1 block, ALREADY_INSTALLED falls back to 0, and the merge step rewrites settings.json via JSON.stringify, destroying all comments without updating .bak if settings.json.bak already exists.
  Evidence: `src/hooks/install.sh:54-75`, `src/hooks/install.sh:93-114`, `src/hooks/install.sh:173-181`
  Do: Pass CAVEMAN_SETTINGS_HELPER to the ALREADY_INSTALLED node probe in src/hooks/install.sh:95-106 and parse via helper.parseSettingsText(raw).data before falling back to JSON.parse, and add a JSONC idempotency regression test in tests/hooks/standalone-install-safety.test.mjs.
  _Revised: p3 edit recommendation_

### OpenCode plugin runtime & system prompt transform (src/plugins/opencode/plugin.js) `opencode.plugin`
`src/plugins/opencode/plugin.js`

- **f-0003** · must · score 1 · confidence 0.95 · effort s · boundary-integrity - OpenCode plugin ignores _ctx directory and injects caveman system prompt even when repo .caveman.json sets defaultMode to off
  In src/plugins/opencode/plugin.js:280-355, CavemanPlugin = async (_ctx) => discards the OpenCode plugin context (_ctx) instead of extracting projectDir (ctx?.location?.directory \|\| ctx?.directory \|\| ctx?.worktree), calls getDefaultMode() with no startDir at lines 291 and 332, and in experimental.chat.system.transform (lines 345-355) unconditionally appends buildActivationPrompt(mode) without checking whether getDefaultMode(projectDir) === 'off'. Unlike caveman-activate.js:305 and caveman-mode-tracker.js:372 (#634), OpenCode sessions ignore repo-level .caveman.json opt-out.
  Evidence: `src/plugins/opencode/plugin.js:280-355`, `src/hooks/caveman-activate.js:305`, `src/hooks/caveman-mode-tracker.js:372`
  Do: Extract projectDir from ctx in src/plugins/opencode/plugin.js:280, pass projectDir to getDefaultMode(projectDir), and in experimental.chat.system.transform strip any existing staleBlock and return early without injecting buildActivationPrompt(mode) when getDefaultMode(projectDir) === 'off'.
  _Revised: p1 edit recommendation_

### SessionStart activation hook & mode tracker (src/hooks/caveman-activate.js) `hooks.activate`
`src/hooks/caveman-activate.js`

- **f-0005** · note · score 5 · confidence 0.95 · effort xs · contract-stability - caveman-activate.js and caveman-mode-tracker.js consistently enforce getDefaultMode() === 'off' repo opt-out and safe mode flag writes
  Both Claude Code hooks check getDefaultMode() === 'off' before writing the flag or emitting activation rules (caveman-activate.js:305, caveman-mode-tracker.js:372).
  Evidence: `src/hooks/caveman-activate.js:305-315`, `src/hooks/caveman-mode-tracker.js:372-380`
  Do: No change needed.

### Shared caveman config & repo .caveman.json resolver (src/hooks/caveman-config.js) `hooks.config`
`src/hooks/caveman-config.js`

- **f-0006** · note · score 5 · confidence 0.95 · effort xs · failure-modes - getDefaultMode(startDir) safely traverses parent directories lexically and validates SAFE_MODES + 'off'
  src/hooks/caveman-config.js:116-140 resolves startDir lexically, walks up to the filesystem root, catches malformed .caveman.json files without throwing, and accepts both SAFE_MODES and 'off'.
  Evidence: `src/hooks/caveman-config.js:116-140`
  Do: No change needed.

## Retracted

Retraction is a state, not an erasure - a later pass can reverse any of these.

- `f-0004` (hooks.config) - getDefaultMode(startDir) symlink traversal could loop on cyclic directory trees if path.dirname does not converge · retracted in pass 2 by the skeptic: path.resolve(startDir) + path.dirname(dir) in src/hooks/caveman-config.js:119-138 is purely lexical and strictly decreases segment depth until parent === dir.

## Deliberation

### Pass 1

- **skeptic** (confidence 0.90) - All 3 must findings have concrete file:line evidence, while f-0004 (getDefaultMode lexical upward traversal loop) is likely falsifiable because path.resolve + path.dirname strips trailing segments purely lexically.
- **builder** (confidence 0.95) - install.sh:95-106 and install.ps1:80-112 can both use CAVEMAN_SETTINGS_HELPER just like preflight and merge already do, and opencode/plugin.js can extract projectDir from ctx and gate experimental.chat.system.transform on getDefaultMode(projectDir) !== 'off'.
- **dreamer** (confidence 0.90) - We should verify whether experimental.chat.system.transform also needs to strip any existing staleBlock when a user switches defaultMode to 'off' mid-session.
- **empath** (confidence 0.95) - A developer who adds // comments to ~/.claude/settings.json and re-runs install.sh without --force expects an idempotent 'already installed' skip, not silent comment deletion.

Resolution: 1 edit (plus 5 findings seeded by `ponder grade` before the argument).

### Pass 2

- **skeptic** (confidence 0.95) - In src/hooks/caveman-config.js:119, path.resolve(startDir) produces a canonical lexical path without resolving symlinks, and path.dirname(dir) strictly shortens the path until parent === dir, so it cannot loop.
- **builder** (confidence 0.95) - Retract f-0004 and record a clean grade on hooks.config so coverage remains 1.00 across all 5 units.
- **dreamer** (confidence 0.90) - Check tests/hooks/standalone-install-safety.test.mjs and tests/installer/opencode.test.mjs to see where regression tests for f-0001, f-0002, and f-0003 belong.
- **empath** (confidence 0.95) - Keeping only empirically reproducible findings avoids maintainer noise on JuliusBrussee/caveman.

Resolution: 1 add, 1 delete.

### Pass 3

- **skeptic** (confidence 0.95) - No additional defects exist in src/hooks/install.sh, src/hooks/install.ps1, or src/plugins/opencode/plugin.js beyond f-0001, f-0002, and f-0003.
- **builder** (confidence 0.95) - Pin the exact test file (tests/hooks/standalone-install-safety.test.mjs) in f-0001 so the fix and test are coupled.
- **dreamer** (confidence 0.95) - Both standalone-install-safety.test.mjs and opencode.test.mjs run under node --test and python3 tests/verify_repo.py.
- **empath** (confidence 0.95) - Actionable recommendations with exact test paths make the companion PR easy to review.

Resolution: 1 edit.

### Pass 4

- **skeptic** (confidence 0.99) - Zero remaining unverified claims; f-0004 was falsified and retracted in Pass 2, and all 3 must findings have deterministic reproducers.
- **builder** (confidence 0.99) - Diffs for src/hooks/install.sh, src/hooks/install.ps1, and src/plugins/opencode/plugin.js are minimal and self-contained.
- **dreamer** (confidence 0.99) - JSONC parsing and repo-level defaultMode=off behavior are now consistent across standalone hooks and OpenCode.
- **empath** (confidence 0.99) - Audit report is concise, evidence-backed, and ready for JuliusBrussee/caveman maintainers.

Resolution: no deltas.

## Ledger

9 deltas across 4 passes: 6 add, 2 edit, 1 delete.

| Pass | Deltas | Perspectives |
|---:|---|---|
| 1 | 5 add, 1 edit | builder |
| 2 | 1 add, 1 delete | dreamer, skeptic |
| 3 | 1 edit | builder |
| 4 | no deltas | - |

The full append-only record is `ledger.jsonl`.

---

*Generated by [Ponder](https://github.com/Quinnod345/ponder) - AI that knows when to speak, and when to shut up.*
