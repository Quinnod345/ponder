# Apply Plan: microsoft/autogen Audit

Generated from Ponder deliberation audit session `autogen` (4 passes, 1.00 coverage, 0.00 churn).

## Priority 1: Add task_done() on message drops and handler errors in SingleThreadedAgentRuntime
- **Target:** `python/packages/autogen-core/src/autogen_core/_single_threaded_agent_runtime.py:704-718`, `743-755`, and `786-798`
- **Action:** Ensure `self._message_queue.task_done()` is called whenever a message is dropped or an intervention handler raises an exception before returning:
```python
except BaseException as e:
    self._message_queue.task_done()
    future.set_exception(e)
    return
if temp_message is DropMessage or isinstance(temp_message, DropMessage):
    self._message_queue.task_done()
    event_logger.info(...)
    future.set_exception(MessageDroppedException())
    return
```
- **Impact:** Eliminates permanent deadlocks during `stop_when_idle()` where `_message_queue.join()` hangs indefinitely after messages are filtered out by intervention handlers.

## Priority 2: Unregister cancellation callbacks upon Future completion in CancellationToken
- **Target:** `python/packages/autogen-core/src/autogen_core/_cancellation_token.py:42-53`
- **Action:** Attach an `add_done_callback` to linked futures to remove their cancel closure from `self._callbacks` once the future finishes:
```python
def link_future(self, future: Future[Any]) -> Future[Any]:
    with self._lock:
        if self._cancelled:
            future.cancel()
        else:
            def _cancel() -> None:
                future.cancel()
            self._callbacks.append(_cancel)
            def _remove(f: Future[Any]) -> None:
                with self._lock:
                    if _cancel in self._callbacks:
                        self._callbacks.remove(_cancel)
            future.add_done_callback(_remove)
    return future
```
- **Impact:** Prevents unbounded memory leaks of completed futures and their result buffers when using session-level or long-lived cancellation tokens.

## Priority 3: Strip all leading orphan FunctionExecutionResultMessage instances after compaction
- **Target:** `python/packages/autogen-core/src/autogen_core/model_context/_token_limited_chat_completion_context.py:65-72`
- **Action:** Replace the single `if` statement with a `while` loop to discard all consecutive tool result messages whose preceding assistant tool call was removed during compaction:
```python
while messages and isinstance(messages[0], FunctionExecutionResultMessage):
    messages = messages[1:]
```
- **Impact:** Prevents invalid message sequences and API rejection errors from LLM providers when parallel tool calls are partially truncated.
