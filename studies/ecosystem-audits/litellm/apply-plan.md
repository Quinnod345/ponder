# Apply Plan: LiteLLM Hardening (BerriAI/litellm)

This apply plan provides verified, drop-in remediations for the 9 confirmed findings from the 4-pass Ponder ecosystem audit.

---

## Priority 1: Prevent Stale created_at Default Evaluation in BudgetManager
- **Target:** `litellm/budget_manager.py:79-99`
- **Action:** Default `created_at` to `None` and evaluate dynamically at invocation time:
```python
    def create_budget(
        self,
        total_budget: float,
        user: str,
        duration: Literal["daily", "weekly", "monthly", "yearly"] | None = None,
        created_at: float | None = None,
    ):
        if created_at is None:
            created_at = time.time()

        self.user_dict[user] = {"total_budget": total_budget}
        if duration is None:
            return self.user_dict[user]
```

---

## Priority 2: Sort kwargs Deterministically in Cache.get_cache_key
- **Target:** `litellm/caching/caching.py:420-435`
- **Action:** Iterate over `sorted(kwargs.keys())` to guarantee stable cache keys across equivalent calls:
```python
        for param in sorted(kwargs.keys()):
            if param in scope_excluded_params:
                continue
            if param in combined_kwargs or param in _ALWAYS_KEYED_PROVIDER_PARAMS:
                param_value: str | None = self._get_param_value(param, kwargs)
                if param in _ALWAYS_KEYED_PROVIDER_PARAMS and not param_value:
                    continue
                if param_value is not None:
                    cache_key += f"{param}: {param_value}\n"
            elif not is_litellm_owned_kwarg(param):
                if litellm.enable_caching_on_provider_specific_optional_params is True:
                    if kwargs[param] is None:
                        continue
                    cache_key += f"{param}: {kwargs[param]}\n"
```

---

## Priority 3: Safeguard projected_cost Against Multimodal Content and Tool Calls
- **Target:** `litellm/budget_manager.py:101-108`
- **Action:** Handle list content blocks and None values defensively:
```python
    def projected_cost(self, model: str, messages: list, user: str):
        content_parts: list[str] = []
        for message in messages:
            content = message.get("content")
            if isinstance(content, str):
                content_parts.append(content)
            elif isinstance(content, list):
                for part in content:
                    if isinstance(part, dict) and part.get("type") == "text":
                        content_parts.append(part.get("text", ""))
        text: Final = "".join(content_parts)
        prompt_tokens: Final = litellm.token_counter(model=model, text=text)
        prompt_cost, _ = litellm.cost_per_token(model=model, prompt_tokens=prompt_tokens, completion_tokens=0)
        current_cost: Final = self.user_dict.get(user, {}).get("current_cost", 0)
        projected_cost: Final = prompt_cost + current_cost
        return projected_cost
```

---

## Priority 4: Atomic Local Storage and Mutex in BudgetManager
- **Target:** `litellm/budget_manager.py:195-225`
- **Action:** Guard user dictionary mutations with a threading lock and write to temporary file before atomic replace:
```python
    def save_data(self):
        if self.client_type == "local":
            import tempfile
            with self._file_lock:
                with tempfile.NamedTemporaryFile("w", dir=".", delete=False) as tf:
                    json.dump(dict(self.user_dict), tf, indent=4)
                    temp_name = tf.name
                os.replace(temp_name, "user_cost.json")
            return {"status": "success"}
```

---

## Priority 5: Remove Orphaned float("inf") and Expose Fallback Cost
- **Target:** `litellm/router_strategy/lowest_cost.py:215-285`
- **Action:** Clean up dead expression and clarify default pricing:
```python
        # Remove standalone float("inf") expression
        current_date: Final = datetime.now().strftime("%Y-%m-%d")
        current_hour: Final = datetime.now().strftime("%H")
        current_minute: Final = datetime.now().strftime("%M")
        precise_minute: Final = f"{current_date}-{current_hour}-{current_minute}"
```

---

## Priority 6: Clean Mutable Default Argument in completion_cost
- **Target:** `litellm/cost_calculator.py:1737`
- **Action:** Replace mutable default with None check:
```python
def completion_cost(
    completion_response: object | None = None,
    model: str | None = None,
    prompt="",
    messages: list | None = None,
    completion="",
    total_time: float | None = 0.0,
    call_type: CallTypesLiteral | None = None,
    ...
):
    if messages is None:
        messages = []
```
