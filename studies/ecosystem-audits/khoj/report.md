# Ponder Deliberation Audit Report: khoj-ai/khoj

**Repository:** `khoj-ai/khoj` (38.0k stars)
**Session Slug:** `khoj`
**Target Scope:** `src/khoj/processor/tools/run_code.py`, `src/khoj/processor/operator/grounding_agent.py`, `src/khoj/processor/tools/mcp.py`, `src/khoj/processor/operator/operator_environment_browser.py`
**Final Verdict:** `stop (converged)` (1.00 coverage, 0.00 churn over 4 passes)

---

## Executive Summary

We performed a 4-pass Ponder deliberation audit on `khoj-ai/khoj` (the leading open-source AI second brain and autonomous agent application). The audit converged with 1.00 unit coverage and 0.00 churn, identifying 6 verified findings (4 Must, 2 Should) while retracting an initial missing-close lifecycle hypothesis during Pass 2 Skeptic falsification.

---

## Pass-by-Pass Deliberation Summary

| Pass | Coverage | Churn | Actions Taken |
| :--- | :---: | :---: | :--- |
| **Pass 1** | `1.00` (`4/4`) | `0.45` | Enumerated 4 units across code sandbox execution, grounding agent telemetry, MCP server connectivity, and browser operator tab management. Identified 5 initial candidate findings including a hypothesis on Playwright process leaks. |
| **Pass 2** | `1.00` (`4/4`) | `0.25` | **Skeptic Falsification:** Retracted missing-close hypothesis via `op: "delete"` after verifying `BrowserEnvironment.close()` explicitly stops `self.browser` and `self.playwright`. Added verified findings for `npx` headless hangs and popup tab premature closure. |
| **Pass 3** | `1.00` (`4/4`) | `0.00` | Verification pass confirmed zero new deltas across all four perspectives (`skeptic`, `builder`, `dreamer`, `empath`). |
| **Pass 4** | `1.00` (`4/4`) | `0.00` | Reached final epistemic silence (`stop (converged)`) with 1.00 coverage and 0.00 churn. |

---

## Verified Findings

### 1. execute_e2b creates AsyncSandbox without finally kill or close block, leaking remote VM instances
- **Location:** `src/khoj/processor/tools/run_code.py:236-324`
- **Severity:** Must (Reliability / Resource Leak)
- **Detail:** In `execute_e2b`, `sandbox = await AsyncSandbox.create(...)` provisions a remote sandbox container on E2B. The execution logic runs inside a `try...except Exception:` construct, but lacks a `finally` block calling `await sandbox.kill()` or `await sandbox.close()`. Every code run permanently leaks an active cloud VM until its server-side timeout expires.

### 2. execute_terrarium crashes with AttributeError when output files have unrecognized extensions
- **Location:** `src/khoj/processor/tools/run_code.py:337-339`
- **Severity:** Must (Correctness)
- **Detail:** In `execute_terrarium`, the return handler calls `mimetypes.guess_type(output_file["filename"])[0].startswith("text/")`. When output files lack standard extensions (e.g. `.lock`, `.cfg`, `.env`, or extensionless files), `guess_type` returns `(None, None)`. Invoking `[0].startswith("text/")` immediately triggers `AttributeError: 'NoneType' object has no attribute 'startswith'`, crashing the execution pipeline.

### 3. GroundingAgent.act crashes with TypeError when tracer defaults to None
- **Location:** `src/khoj/processor/operator/grounding_agent.py:44,69-74`
- **Severity:** Must (Reliability)
- **Detail:** In `GroundingAgent.__init__`, `self.tracer = tracer` where `tracer: dict = None`. In `act()`, `self.tracer["usage"] = get_chat_usage_metrics(..., usage=self.tracer.get("usage"))` unconditionally subscripts `self.tracer`. When initialized with default parameters, this raises `TypeError: 'NoneType' object does not support item assignment` on the very first grounding step.

### 4. _connect_to_sse_server manages contexts outside exit_stack, leaking connections on initialization failure
- **Location:** `src/khoj/processor/tools/mcp.py:77-86`
- **Severity:** Must (Reliability / Resource Leak)
- **Detail:** In `_connect_to_sse_server`, `streams` and `self.session` enter async contexts directly via `__aenter__()` without registering into `self.exit_stack`. If `await self.session.initialize()` raises an error (such as an auth failure or network timeout), the underlying SSE stream and HTTP connection contexts are never closed or unwound.

### 5. _connect_to_stdio_server executes npx without -y, causing interactive install hangs in headless environments
- **Location:** `src/khoj/processor/tools/mcp.py:97-101,112`
- **Severity:** Should (Reliability)
- **Detail:** When launching an npm package via stdio, `_connect_to_stdio_server` passes `command = "npx"` and `args = [self.path]`. If the package is not preinstalled in the local cache, npx prompts interactively: `Need to install the following packages: ... Ok to proceed? (y)`. In headless stdio transport mode, the subprocess hangs indefinitely on stdin.

### 6. handle_new_page immediately closes new tabs before popup URLs finish resolving
- **Location:** `src/khoj/processor/operator/operator_environment_browser.py:73-84`
- **Severity:** Should (Correctness)
- **Detail:** `handle_new_page` listens for new pages spawned in the browser context. When links with `target="_blank"` are clicked, Chromium initially creates a tab with `target_url = "about:blank"`. The handler immediately executes `await new_page.close()` and only navigates if `target_url != "about:blank"`, prematurely terminating popup links before their destination URL resolves.
