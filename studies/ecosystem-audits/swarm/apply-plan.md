# Ponder Apply Plan: openai/swarm

This apply plan provides minimal, verified patches for findings identified during the 4-pass deliberation audit of `openai/swarm`.

---

## Priority 1: Safe Tool Parameter Inspection and JSON Argument Handling
- **Target:** `swarm/core.py:114-124`
- **Action:** Use `inspect.signature` to test parameter acceptance and catch invalid JSON tool arguments:
```python
        for tool_call in tool_calls:
            name = tool_call.function.name
            if name not in function_map:
                debug_print(debug, f"Tool {name} not found in function map.")
                partial_response.messages.append(
                    {
                        "role": "tool",
                        "tool_call_id": tool_call.id,
                        "tool_name": name,
                        "content": f"Error: Tool {name} not found.",
                    }
                )
                continue

            try:
                args = json.loads(tool_call.function.arguments or "{}")
            except (json.JSONDecodeError, TypeError) as e:
                debug_print(debug, f"Failed to parse arguments for tool {name}: {e}")
                partial_response.messages.append(
                    {
                        "role": "tool",
                        "tool_call_id": tool_call.id,
                        "tool_name": name,
                        "content": f"Error: Invalid JSON arguments: {str(e)}",
                    }
                )
                continue

            debug_print(
                debug, f"Processing tool call: {name} with arguments {args}")

            func = function_map[name]
            # pass context_variables to agent functions safely via inspect.signature
            try:
                sig = inspect.signature(func)
                accepts_ctx = __CTX_VARS_NAME__ in sig.parameters
            except (ValueError, TypeError):
                accepts_ctx = False

            if accepts_ctx:
                args[__CTX_VARS_NAME__] = context_variables
            raw_result = func(**args)
```

---

## Priority 2: Preserve Sender in ChatCompletionMessage Serialization
- **Target:** `swarm/core.py:270-274`
- **Action:** Inject sender attribute into dumped dictionary:
```python
            message = completion.choices[0].message
            debug_print(debug, "Received completion:", message)
            msg_dict = json.loads(message.model_dump_json())
            msg_dict["sender"] = active_agent.name
            history.append(msg_dict)
```

---

## Priority 3: Support Parallel Tool Calls in Streaming Chunk Merge
- **Target:** `swarm/util.py:25-30`
- **Action:** Iterate through all streamed tool call deltas:
```python
def merge_chunk(final_response: dict, delta: dict) -> None:
    delta.pop("role", None)
    merge_fields(final_response, delta)

    tool_calls = delta.get("tool_calls")
    if tool_calls and len(tool_calls) > 0:
        for tool_call in tool_calls:
            index = tool_call.get("index")
            if index is not None:
                cleaned_call = {k: v for k, v in tool_call.items() if k != "index"}
                merge_fields(final_response["tool_calls"][index], cleaned_call)
```

---

## Priority 4: Update Active Agent Sender in run_and_stream
- **Target:** `swarm/core.py:156-160`
- **Action:** Assign `active_agent.name` on each turn:
```python
        while len(history) - init_len < max_turns:

            message = {
                "content": "",
                "sender": active_agent.name,
                "role": "assistant",
                "function_call": None,
                "tool_calls": defaultdict(
                    lambda: {
                        "function": {"arguments": "", "name": ""},
                        "id": "",
                        "type": "",
                    }
                ),
            }
```

---

## Priority 5: Robust Argument Formatting in REPL
- **Target:** `swarm/repl/repl.py:54-58`
- **Action:** Format tool call arguments without global colon replacement:
```python
        for tool_call in tool_calls:
            f = tool_call["function"]
            name, args = f["name"], f["arguments"]
            try:
                parsed_args = json.loads(args)
                if isinstance(parsed_args, dict):
                    arg_str = ", ".join(f"{k}={repr(v)}" for k, v in parsed_args.items())
                else:
                    arg_str = str(parsed_args)
            except Exception:
                arg_str = args
            print(f"\033[95m{name}\033[0m({arg_str})")
```
