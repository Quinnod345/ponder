# Ponder Apply Plan: agno-agi/agno (43.0k stars)

## Priority 1: Isolate session_state copies in Parallel workflows and reconcile with merge_parallel_session_states
- **Target:** `libs/agno/agno/workflow/parallel.py:334-344`, `436-437`, and `703-713`
- **Action:** Deepcopy `run_context.session_state` for each parallel branch and invoke `merge_parallel_session_states` to reconcile modifications:
```python
        # Create individual session_state copies for each step to prevent race conditions
        session_state_copies = []
        for _ in range(len(self.steps)):
            if run_context is not None and run_context.session_state is not None:
                session_state_copies.append(deepcopy(run_context.session_state))
            elif session_state is not None:
                session_state_copies.append(deepcopy(session_state))
            else:
                session_state_copies.append({})
```
- And in post-execution reconciliation:
```python
        if run_context is not None and run_context.session_state is not None:
            merge_parallel_session_states(run_context.session_state, modified_session_states)
        elif session_state is not None:
            merge_parallel_session_states(session_state, modified_session_states)
```

---

## Priority 2: Use non-waiting executor shutdown on cancellation in execute_tasks_parallel
- **Target:** `libs/agno/agno/team/_task_tools.py:928-1025`
- **Action:** When `RunCancelledException` is caught, cancel remaining futures and shut down executor without waiting:
```python
                except RunCancelledException:
                    executor.shutdown(wait=False, cancel_futures=True)
                    raise
```

---

## Priority 3: Order parallel task results by input task IDs sequence
- **Target:** `libs/agno/agno/team/_task_tools.py:924-950` and `1042`
- **Action:** Preserve the positional mapping of task results using a dictionary keyed by `task_id`:
```python
        results_by_id: Dict[str, str] = {}
        for future in as_completed(futures):
            # ... process future ...
            results_by_id[tid] = result_text

        ordered_results = [results_by_id.get(tid, f"Task [{tid}] did not produce a result.") for tid in task_ids]
        yield "\n".join(ordered_results)
```

---

## Priority 4: Offload synchronous database calls in async methods via asyncio.to_thread
- **Target:** `libs/agno/agno/agent/_storage.py:553-557`, `737-750`, and `783-785`
- **Action:** Wrap synchronous DB methods in `asyncio.to_thread`:
```python
        if _init.has_async_db(agent):
            await agent.db.upsert_run(run=run, session_id=session_id, user_id=user_id, run_index=run_index)
        else:
            await asyncio.to_thread(agent.db.upsert_run, run=run, session_id=session_id, user_id=user_id, run_index=run_index)
```

---

## Priority 5: Yield hook error event on unhandled exception in stream mode
- **Target:** `libs/agno/agno/team/_hooks.py:335-340` and `libs/agno/agno/team/_hooks.py:515-520`
- **Action:** Yield a failure event to stream consumers when an unhandled hook exception occurs:
```python
        except (InputCheckError, OutputCheckError) as e:
            raise e
        except Exception as e:
            log_exception(f"Pre-hook #{i + 1} execution failed")
            if stream_events:
                yield handle_event(
                    run_response=run_response,
                    event=create_team_pre_hook_completed_event(
                        from_run_response=run_response, run_input=run_input, pre_hook_name=get_hook_name(hook), error=str(e)
                    ),
                    events_to_skip=team.events_to_skip,
                    store_events=team.store_events,
                )
```
