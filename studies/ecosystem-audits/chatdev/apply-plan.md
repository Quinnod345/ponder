# ChatDev Remediation Plan

## Priority 1: Serialize Human nodes in ParallelExecutor.execute_nodes_parallel
- **Target:** `workflow/executor/parallel_executor.py:65-72`
- **Action:** Check node type and serialize interactive nodes:
```python
        def has_blocking_func(node_id: str) -> bool:
            node = self.nodes_dict.get(node_id)
            if not node:
                return False
            # Serialize Human and interactive prompt nodes
            node_type = getattr(node, "node_type", None) or getattr(node, "type", None)
            return node_type in {"human", "human_prompt", "interactive"}
```

---

## Priority 2: Cancel pending futures in _execute_parallel_batch on failure
- **Target:** `workflow/executor/parallel_executor.py:125-133`
- **Action:** Cancel pending futures when an exception occurs:
```python
        with concurrent.futures.ThreadPoolExecutor(max_workers=len(items)) as executor:
            futures = []
            for item in items:
                future = executor.submit(executor_func, item)
                futures.append((item, future))
            
            try:
                for item, future in futures:
                    future.result()
                    self.log_manager.debug(f"{item_desc_func(item)} completed successfully")
            except Exception as e:
                for _, f in futures:
                    f.cancel()
                self.log_manager.error(f"Batch execution failed: {str(e)}")
                raise
```

---

## Priority 3: Deterministic Cycle IDs in CycleManager
- **Target:** `workflow/cycle_manager.py:133-138`
- **Action:** Sort cycle node IDs before string formatting:
```python
        for i, cycle_nodes in enumerate(cycles):
            sorted_nodes = sorted(cycle_nodes)
            cycle_id = f"cycle_{i}_{sorted_nodes}"
            cycle_info = CycleInfo(
                cycle_id=cycle_id,
                nodes=set(cycle_nodes),
                entry_nodes=set(),
                exit_edges=[]
            )
```

---

## Priority 4: Complete iteration in judge_entry_predecessor
- **Target:** `workflow/cycle_manager.py:157-166`
- **Action:** Continue iterating until all matching edges are inspected:
```python
        def judge_entry_predecessor(_predecessor: Node, _predecessor_id: str) -> bool:
            if _predecessor_id in cycle_nodes:
                return False
            for _edge_link in _predecessor.iter_outgoing_edges():
                if _edge_link.target.id == node_id and _edge_link.trigger:
                    return True
            return False
```

---

## Priority 5: Guard against workspace root deletion in delete_path
- **Target:** `functions/function_calling/file.py:284-290`
- **Action:** Prevent recursive deletion of the workspace root:
```python
    ctx = FileToolContext(_context)
    target = ctx.resolve_under_workspace(path)

    if target == ctx.workspace_root:
        raise ValueError("Cannot delete workspace root directory")
```

---

## Priority 6: Validate positive start_line in apply_text_edits
- **Target:** `functions/function_calling/file.py:940-950`
- **Action:** Enforce 1-based line indexing:
```python
    if start_line < 1:
        raise ValueError("start_line must be an integer >= 1")
```

---

## Priority 7: Ensure directory exists in GraphContext.record
- **Target:** `workflow/graph_context.py:104-106`
- **Action:** Uncomment directory creation:
```python
        self.directory.mkdir(parents=True, exist_ok=True)
```
