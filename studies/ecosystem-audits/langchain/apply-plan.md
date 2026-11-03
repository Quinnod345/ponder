# Ponder Apply Plan: langchain-ai/langchain

This apply plan provides minimal, verified patches for findings identified during the 4-pass deliberation audit of `langchain-ai/langchain`.

---

## Priority 1: Dispatch Both Inline and Non-Inline Handlers in `on_llm_start`
- **Target:** `libs/core/langchain_core/callbacks/manager.py:1912-1941`
- **Action:** Remove the mutually exclusive `else:` branch so non-inline handlers are dispatched alongside inline handlers:
```python
            if inline_handlers:
                inline_tasks.append(
                    ahandle_event(
                        inline_handlers,
                        "on_llm_start",
                        "ignore_llm",
                        serialized,
                        [prompt],
                        run_id=run_id_,
                        parent_run_id=self.parent_run_id,
                        tags=self.tags,
                        metadata=self.metadata,
                        **kwargs,
                    )
                )
            if non_inline_handlers:
                non_inline_tasks.append(
                    ahandle_event(
                        non_inline_handlers,
                        "on_llm_start",
                        "ignore_llm",
                        serialized,
                        [prompt],
                        run_id=run_id_,
                        parent_run_id=self.parent_run_id,
                        tags=self.tags,
                        metadata=self.metadata,
                        **kwargs,
                    )
                )
```

---

## Priority 2: Preserve Batch Output Cardinality on Uncaught Exception
- **Target:** `libs/core/langchain_core/runnables/base.py:3622-3624`
- **Action:** Return exception across all batch inputs rather than the pruned `inputs` slice:
```python
        except BaseException as e:
            for rm in run_managers:
                rm.on_chain_error(e)
            if return_exceptions:
                return cast("list[Output]", [e for _ in configs])
            raise
```

---

## Priority 3: Preserve Artifacts in Direct Tool Invocations
- **Target:** `libs/core/langchain_core/tools/base.py:1416-1418`
- **Action:** Return tuple `(content, artifact)` when tool call ID is omitted:
```python
    if isinstance(content, ToolOutputMixin):
        return content
    if tool_call_id is None:
        if artifact is not None:
            return (content, artifact)
        return content
```

---

## Priority 4: Shallow Copy `AgentFinish.return_values`
- **Target:** `libs/langchain/langchain_classic/agents/agent.py:1248, 1265`
- **Action:** Shallow copy dictionary before attaching intermediate steps:
```python
    def _return(
        self,
        output: AgentFinish,
        intermediate_steps: list,
        run_manager: CallbackManagerForChainRun | None = None,
    ) -> dict[str, Any]:
        if run_manager:
            run_manager.on_agent_finish(output, color="green", verbose=self.verbose)
        final_output = output.return_values.copy()
        if self.return_intermediate_steps:
            final_output["intermediate_steps"] = intermediate_steps
        return final_output
```

---

## Priority 5: Use Monotonic Time for Execution Timeouts
- **Target:** `libs/langchain/langchain_classic/agents/agent.py:1586-1617`
- **Action:** Measure elapsed time using `time.monotonic()`:
```python
        time_elapsed = 0.0
        start_time = time.monotonic()
        while self._should_continue(iterations, time_elapsed):
            next_step_output = self._take_next_step(...)
            ...
            time_elapsed = time.monotonic() - start_time
```
