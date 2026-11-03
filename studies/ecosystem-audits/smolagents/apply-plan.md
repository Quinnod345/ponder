# Apply Plan: huggingface/smolagents Audit

Generated from Ponder deliberation audit session `smolagents` (4 passes, 1.00 coverage, 0.00 churn).

## Priority 1: Prevent ThreadPoolExecutor context manager from blocking on timeout in timeout decorator
- **Target:** `src/smolagents/local_python_executor.py:304-320`
- **Action:** Instantiate `ThreadPoolExecutor` directly rather than using a `with` context manager, and shut down without waiting upon `FuturesTimeoutError`:
```python
def timeout(timeout_seconds: int):
    def decorator(func):
        @wraps(func)
        def wrapper(*args, **kwargs):
            executor = ThreadPoolExecutor(max_workers=1)
            future = executor.submit(func, *args, **kwargs)
            try:
                result = future.result(timeout=timeout_seconds)
                executor.shutdown(wait=False, cancel_futures=True)
                return result
            except FuturesTimeoutError:
                executor.shutdown(wait=False, cancel_futures=True)
                raise ExecutionTimeoutError(
                    f"Code execution exceeded the maximum execution time of {timeout_seconds} seconds"
                )
            except Exception:
                executor.shutdown(wait=False, cancel_futures=True)
                raise

        return wrapper

    return decorator
```
- **Impact:** Ensures the caller thread actually regains control immediately upon timeout instead of hanging until the worker thread finishes.

## Priority 2: Reset self.state on reset=True in MultiStepAgent.run()
- **Target:** `src/smolagents/agents.py:478-482`
- **Action:** Clear `self.state` when `reset=True` so variables and media do not leak across runs:
```python
        self.memory.system_prompt = SystemPromptStep(system_prompt=self.system_prompt)
        if reset:
            self.memory.reset()
            self.monitor.reset()
            self.state = {}
```
- **Impact:** Prevents memory leakage and state contamination between consecutive tasks.

## Priority 3: Support list of dicts in MCPClient server parameters and clean up tools on disconnect
- **Target:** `src/smolagents/mcp_client.py:115-125`, `139-145`
- **Action:** Normalize parameters for both single dicts and lists of dicts, and invalidate `self._tools` on disconnect:
```python
        def _normalize_dict_param(params: dict[str, Any]):
            if "transport" not in params:
                params["transport"] = "streamable-http"
            if params["transport"] not in {"sse", "streamable-http"}:
                raise ValueError(
                    f"Unsupported transport: {params['transport']}. Supported transports are 'streamable-http' and 'sse'."
                )

        if isinstance(server_parameters, dict):
            _normalize_dict_param(server_parameters)
        elif isinstance(server_parameters, list):
            for param in server_parameters:
                if isinstance(param, dict):
                    _normalize_dict_param(param)

        # in disconnect():
        self._adapter.__exit__(exc_type, exc_value, exc_traceback)
        self._tools = None
```
- **Impact:** Eliminates transport errors for multi-server MCP configurations and prevents dangling closed tool handles.

## Priority 4: Ensure ActionStep.dict() produces JSON-serializable image representations
- **Target:** `src/smolagents/memory.py:84-86`
- **Action:** Encode image bytes as base64 strings or format objects:
```python
            "observations_images": [
                make_json_serializable(image) for image in self.observations_images
            ]
            if self.observations_images
            else None,
```
- **Impact:** Prevents `TypeError: Object of type bytes is not JSON serializable` during step serialization.
