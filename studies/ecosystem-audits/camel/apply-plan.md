# Apply Plan: camel-ai/camel Architectural Hardening

## Priority 1: Add cycle detection to TaskManager.topological_sort
- **Target:** `camel/tasks/task.py:660-689`
- **Action:** Add recursion tracking sets to detect cycles:
```python
    @staticmethod
    def topological_sort(tasks: List[Task]) -> List[Task]:
        stack = []
        visited = set()
        visiting = set()

        def visit(task: Task):
            if task.id in visiting:
                raise ValueError(f"Cyclic dependency detected in task graph involving task '{task.id}'.")
            if task.id in visited:
                return

            visiting.add(task.id)
            for sub_task in task.subtasks:
                visit(sub_task)
            visiting.remove(task.id)
            visited.add(task.id)
            stack.append(task)

        for task in tasks:
            visit(task)

        return stack
```

---

## Priority 2: Replace assert statements with explicit ValueError in TaskManager.add_tasks
- **Target:** `camel/tasks/task.py:726-728`
- **Action:** Replace production assert with explicit exception check:
```python
        for task in tasks:
            if self.exist(task.id):
                raise ValueError(f"Task with id '{task.id}' already exists in TaskManager.")
```

---

## Priority 3: Guard Workforce.process_task against active event loop thread blocking
- **Target:** `camel/societies/workforce/workforce.py:2840-2875`
- **Action:** Prevent blocking the active event loop with synchronous `future.result()`:
```python
        try:
            current_loop = asyncio.get_running_loop()
            raise RuntimeError(
                "Workforce.process_task() cannot be called from an active event loop "
                "as it blocks the loop thread. Use 'await workforce.process_task_async(task)' instead."
            )
        except RuntimeError as e:
            if "cannot be called from an active event loop" in str(e):
                raise
            return asyncio.run(self.process_task_async(task))
```

---

## Priority 4: Prevent ChatAgent.step timeout shutdown wait hang
- **Target:** `camel/agents/chat_agent.py:2940-2955`
- **Action:** Shut down the executor without waiting when a step timeout occurs:
```python
        if self.step_timeout is not None:
            executor = concurrent.futures.ThreadPoolExecutor(max_workers=1)
            future = executor.submit(self._step_impl, input_message, response_format)
            try:
                return future.result(timeout=self.step_timeout)
            except concurrent.futures.TimeoutError:
                future.cancel()
                executor.shutdown(wait=False, cancel_futures=True)
                raise TimeoutError(f"Step timed out after {self.step_timeout}s")
            finally:
                executor.shutdown(wait=False)
```

---

## Priority 5: Atomic chat history replacement in ChatHistoryMemory.clean_tool_calls
- **Target:** `camel/memories/agent_memories.py:146-149`
- **Action:** Overwrite storage atomically or catch write errors before clearing:
```python
        # Save pruned records safely without permanent data loss on failure
        if hasattr(self._chat_history_block.storage, "replace"):
            self._chat_history_block.storage.replace(record_dicts)
        else:
            # Fallback with safe in-memory staging
            original_records = self._chat_history_block.storage.load()
            try:
                self._chat_history_block.storage.clear()
                self._chat_history_block.storage.save(record_dicts)
            except Exception:
                self._chat_history_block.storage.save(original_records)
                raise
```
