# Ponder Apply Plan: stanfordnlp/dspy

This apply plan provides minimal, verified patches for findings identified during the 4-pass deliberation audit of `stanfordnlp/dspy`.

---

## Priority 1: Prevent StopIteration in Completions.__len__ and Support Negative Indexing
- **Target:** `dspy/primitives/prediction.py:145-165`
- **Action:** Support empty completions gracefully and normalize negative indices:
```python
    def __getitem__(self, key):
        if isinstance(key, int):
            length = len(self)
            if key < 0:
                key += length
            if key < 0 or key >= length:
                raise IndexError("Index out of range")

            return Prediction(**{k: v[key] for k, v in self._completions.items()})

        return self._completions[key]

    def __len__(self):
        # Return 0 if completions store is empty
        if not self._completions:
            return 0
        return len(next(iter(self._completions.values())))
```

---

## Priority 2: Safe Async Coroutine Execution in _await_in_sync
- **Target:** `dspy/primitives/python_interpreter.py:170-182`
- **Action:** Guard against active event loops using a dedicated worker thread:
```python
def _await_in_sync(coroutine: Any) -> Any:
    """Run a coroutine to completion from a sync caller."""
    try:
        loop = asyncio.get_running_loop()
    except RuntimeError:
        loop = None

    if loop is None:
        return asyncio.run(coroutine)

    if loop.is_running():
        import concurrent.futures
        with concurrent.futures.ThreadPoolExecutor(max_workers=1) as pool:
            return pool.submit(asyncio.run, coroutine).result()

    return loop.run_until_complete(coroutine)
```

---

## Priority 3: Guard ReAct Extraction Against Context Window Exhaustion
- **Target:** `dspy/predict/react.py:130-145`
- **Action:** Catch ContextWindowExceededError during extraction fallback:
```python
        try:
            extract = self._call_with_potential_trajectory_truncation(self.extract, trajectory, **input_args)
        except ContextWindowExceededError as err:
            logger.warning(f"Extraction failed due to context limit: {format_error_for_lm(err, traceback_frames=5)}")
            extract = {}
        return dspy.Prediction(trajectory=trajectory, **extract)
```

---

## Priority 4: Exclude Internal dspy_ Metadata Fields from Example.labels()
- **Target:** `dspy/primitives/example.py:270-280`
- **Action:** Filter internal metadata fields during label dictionary generation:
```python
    def labels(self):
        """Return a new Example containing only the label (non-input) fields."""
        input_keys = set(self.inputs().keys())
        d = {
            key: self._store[key]
            for key in self._store
            if key not in input_keys and not key.startswith("dspy_")
        }
        return type(self)(d)
```

---

## Priority 5: Defensive Parent Directory Creation in Evaluate File Exports
- **Target:** `dspy/evaluate/evaluate.py:200-225`
- **Action:** Ensure parent directories exist before writing CSV or JSON export files:
```python
        if save_as_csv:
            metric_name = (
                metric.__name__
                if isinstance(metric, types.FunctionType)
                else metric.__class__.__name__
            )
            data = self._prepare_results_output(results, metric_name)
            csv_dir = os.path.dirname(os.path.abspath(save_as_csv))
            if csv_dir:
                os.makedirs(csv_dir, exist_ok=True)

            with open(save_as_csv, "w", newline="") as csvfile:
                fieldnames = list(dict.fromkeys(key for row in data for key in row))
                writer = csv.DictWriter(csvfile, fieldnames=fieldnames)
                writer.writeheader()
                for row in data:
                    writer.writerow(row)

        if save_as_json:
            metric_name = (
                metric.__name__
                if isinstance(metric, types.FunctionType)
                else metric.__class__.__name__
            )
            data = self._prepare_results_output(results, metric_name)
            json_dir = os.path.dirname(os.path.abspath(save_as_json))
            if json_dir:
                os.makedirs(json_dir, exist_ok=True)

            with open(save_as_json, "w") as f:
                json.dump(data, f)
```
