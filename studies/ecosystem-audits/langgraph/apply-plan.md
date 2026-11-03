# Apply Plan: langchain-ai/langgraph (44.4k★)

## Priority 1: Prevent Event Loop Stalls in `ToolNode._arun_one`
- **Target:** `libs/prebuilt/langgraph/prebuilt/tool_node.py:1238-1244`
- **Action:** Offload synchronous tool wrapper execution to `asyncio.to_thread`:
```python
        # Call wrapper with request and execute callable
        try:
            if self._awrap_tool_call is not None:
                return await self._awrap_tool_call(tool_request, execute)
            # None check was performed above already
            self._wrap_tool_call = cast("ToolCallWrapper", self._wrap_tool_call)
            return await asyncio.to_thread(self._wrap_tool_call, tool_request, _sync_execute)
```

---

## Priority 2: Safely Index Tool Call Identifiers in `_validate_chat_history`
- **Target:** `libs/prebuilt/langgraph/prebuilt/chat_agent_executor.py:255-265`
- **Action:** Use `.get("id")` with fallback to prevent `KeyError`:
```python
    tool_calls_without_results = [
        tool_call
        for tool_call in all_tool_calls
        if tool_call.get("id") not in tool_call_ids_with_results
    ]
```

---

## Priority 3: Guard Empty Messages List in `should_continue`
- **Target:** `libs/prebuilt/langgraph/prebuilt/chat_agent_executor.py:832-835`
- **Action:** Return `END` if messages list is empty:
```python
    def should_continue(state: StateSchema) -> str | list[Send]:
        messages = _get_state_value(state, "messages")
        if not messages:
            return END
        last_message = messages[-1]
```

---

## Priority 4: Avoid In-Place State Mutation in `_get_model_input_state`
- **Target:** `libs/prebuilt/langgraph/prebuilt/chat_agent_executor.py:654-658`
- **Action:** Return a copy of the state structure:
```python
        # Create shallow copy to prevent cross-branch mutation
        if isinstance(state_schema, type) and issubclass(state_schema, BaseModel):
            state = state.model_copy(update={"messages": messages})
        else:
            state = {**state, "messages": messages}

        return state
```

---

## Priority 5: Replace Object Identity Check with Explicit Parameter in `_put_checkpoint`
- **Target:** `libs/langgraph/langgraph/pregel/_loop.py:1248-1250`
- **Action:** Add explicit `exiting: bool = False` parameter to `_put_checkpoint`:
```python
    def _put_checkpoint(self, metadata: CheckpointMetadata, *, exiting: bool = False) -> None:
        if exiting and self.checkpoint["id"] == self.checkpoint_id_saved:
            return
```

---

## Priority 6: Clean Up Redundant Method Token in `_msgpack_default`
- **Target:** `libs/checkpoint/langgraph/checkpoint/serde/jsonplus.py:335-343`
- **Action:** Remove dead `"model_validate_json"` string from serialization tuple:
```python
    elif hasattr(obj, "model_dump") and callable(obj.model_dump):  # pydantic v2
        return ormsgpack.Ext(
            EXT_PYDANTIC_V2,
            _msgpack_enc(
                (
                    obj.__class__.__module__,
                    obj.__class__.__name__,
                    obj.model_dump(),
                ),
            ),
        )
```
