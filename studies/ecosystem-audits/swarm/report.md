# Ponder Ecosystem Audit: openai/swarm (22.1k stars)

## Executive Summary

We performed a verified 4-pass deliberation audit using **Ponder** (`npx @quinnod345/ponder`) on **`openai/swarm`** (OpenAI's educational multi-agent orchestration framework, `22.1k` stars).

The deliberation audit evaluated 5 core units across `swarm/core.py`, `swarm/types.py`, `swarm/util.py`, and `swarm/repl/repl.py` against correctness, reliability, robustness, and maintainability lenses. Across 4 passes, the deliberation converged with **1.00 unit coverage** and **0.00 churn**, verifying 4 `must` severity bugs and 3 `should` severity improvements, with 1 skeptic hypothesis retracted in Pass 2.

---

## Convergence Trajectory

```
Pass 1: Coverage 1.00 (5/5 units) | 8 candidate findings | Initial discovery
Pass 2: Coverage 1.00 (5/5 units) | Churn 0.125 | Retracted shared tool dict mutation hypothesis
Pass 3: Coverage 1.00 (5/5 units) | Churn 0.000 | 4-voice stabilization (Skeptic, Builder, Dreamer, Empath)
Pass 4: Coverage 1.00 (5/5 units) | Churn 0.000 | Convergence verified -> decide stop
```

---

## Verified Findings

### 1. `swarm/core.py:119-122` - `co_varnames` Local Variable Collision in Tool Parameter Injection
- **Severity:** `must`
- **Dimension:** Correctness
- **Finding:** `handle_tool_calls` checks if `__CTX_VARS_NAME__ in func.__code__.co_varnames` to determine whether to inject `context_variables`. In Python, `co_varnames` contains all local variables declared inside the function body, not just formal parameter names. If an agent tool defines a local variable named `context_variables` inside its body, the check evaluates to `True`, injecting `args["context_variables"] = context_variables` into `func(**args)` and raising `TypeError: func() got an unexpected keyword argument 'context_variables'`.
- **Fix:** Use `inspect.signature(func).parameters` to test parameter acceptance.

### 2. `swarm/core.py:114` - Unhandled `JSONDecodeError` on Malformed Tool Arguments
- **Severity:** `must`
- **Dimension:** Robustness
- **Finding:** `args = json.loads(tool_call.function.arguments)` executes without error handling. When models produce truncated tokens or invalid JSON, `json.decoder.JSONDecodeError` crashes the entire Swarm run instead of returning a tool error message to the agent.
- **Fix:** Wrap `json.loads` in a `try/except json.JSONDecodeError` block and append an error message to `partial_response.messages`.

### 3. `swarm/core.py:270-274` - `message.sender` Property Dropped by Pydantic `model_dump_json()`
- **Severity:** `must`
- **Dimension:** Correctness
- **Finding:** `Swarm.run` assigns `message.sender = active_agent.name` on the OpenAI `ChatCompletionMessage` instance, then immediately executes `json.loads(message.model_dump_json())`. In Pydantic v2 and the official OpenAI SDK, `model_dump_json()` only serializes declared schema fields; arbitrary assigned attributes are dropped. Downstream callers like `repl.py:43` (`message["sender"]`) raise `KeyError: 'sender'`.
- **Fix:** Dump the model to a dictionary first, then inject `"sender": active_agent.name`.

### 4. `swarm/util.py:25-29` - Streaming Parallel Tool Call Truncation in `merge_chunk`
- **Severity:** `must`
- **Dimension:** Reliability
- **Finding:** `merge_chunk` reads `tool_calls = delta.get("tool_calls")` and only processes `tool_calls[0]`. When the OpenAI API streams completion chunks containing multiple parallel tool calls in a single delta array, all tool calls at index 1 and beyond are silently dropped from `final_response["tool_calls"]`.
- **Fix:** Iterate over all items in `delta["tool_calls"]` instead of only `tool_calls[0]`.

### 5. `swarm/core.py:158` - Streamed Sender Attribute Frozen to Starting Agent
- **Severity:** `should`
- **Dimension:** Correctness
- **Finding:** `run_and_stream` initializes `message["sender"] = agent.name` using the initial agent reference rather than `active_agent.name`. During multi-turn handoffs, subsequent assistant chunks and completions continue reporting the original agent name.
- **Fix:** Update `message["sender"] = active_agent.name` on each turn loop.

### 6. `swarm/util.py:61-68` - Typing Generic Annotation Degradation in `function_to_json`
- **Severity:** `should`
- **Dimension:** Maintainability
- **Finding:** `type_map.get(param.annotation, "string")` defaults all typing generics (e.g. `List[str]`, `Optional[int]`) to type `"string"`. In addition, the `try/except KeyError` block is dead code because `dict.get()` never raises `KeyError`.
- **Fix:** Unwrap generic annotations via `typing.get_origin` and remove dead `KeyError` handler.

### 7. `swarm/repl/repl.py:56-57` - REPL Naive Colon Substitution in Argument Values
- **Severity:** `should`
- **Dimension:** Correctness
- **Finding:** `arg_str = json.dumps(json.loads(args)).replace(":", "=")` naively replaces colons inside string values (such as URLs `https://...` or timestamps), corrupting output strings in the interactive CLI.
- **Fix:** Format argument string from parsed dictionary key-value pairs.
