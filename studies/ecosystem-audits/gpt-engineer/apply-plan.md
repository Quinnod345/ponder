# Apply Plan: AntonOsika/gpt-engineer (55.0k★)

## Priority 1: Prevent `OrderedDict` Line 0 Misplacement in `apply_diffs`
- **Target:** `gpt_engineer/core/chat_to_files.py:126-128`
- **Action:** Reassemble file by sorted line keys so prepended lines at line 0 are placed before line 1:
```python
            # Remove lines marked for removal and sort keys sequentially
            sorted_lines = [
                line_content
                for key, line_content in sorted(line_dict.items())
                if REMOVE_FLAG not in line_content
            ]
            # Reassemble the file content
            files[diff.filename_post] = "\n".join(sorted_lines)
```

---

## Priority 2: Support Single-Line Ranges and Signatures in `parse_hunk_header`
- **Target:** `gpt_engineer/core/chat_to_files.py:215-225`
- **Action:** Allow optional comma length specifiers and trailing function signatures:
```python
    pattern = re.compile(r"^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@")
    match = pattern.match(header_line)
    if not match:
        return 0, 0, 0, 0

    pre_start, pre_len, post_start, post_len = match.groups()
    start_line_pre_edit = int(pre_start)
    hunk_len_pre_edit = int(pre_len) if pre_len is not None else 1
    start_line_post_edit = int(post_start)
    hunk_len_post_edit = int(post_len) if post_len is not None else 1
    return (
        start_line_pre_edit,
        hunk_len_pre_edit,
        start_line_post_edit,
        hunk_len_post_edit,
    )
```

---

## Priority 3: Fix Quadratic Cost Calculation in `TokenUsageLog.usage_cost`
- **Target:** `gpt_engineer/core/token_usage.py:270-285`
- **Action:** Calculate cost from in-step tokens or once from cumulative totals:
```python
        try:
            result = 0
            for log in self.log():
                result += get_openai_token_cost_for_model(
                    self.model_name, log.in_step_prompt_tokens, is_completion=False
                )
                result += get_openai_token_cost_for_model(
                    self.model_name, log.in_step_completion_tokens, is_completion=True
                )
            return result
        except Exception as e:
            print(f"Error calculating usage cost: {e}")
            return None
```

---

## Priority 4: Strip Data URI Header in `num_tokens_for_base64_image`
- **Target:** `gpt_engineer/core/token_usage.py:122-126`
- **Action:** Extract raw base64 payload when data URI prefix is present:
```python
        if detail == "low":
            return 85  # Fixed cost for low detail images

        # Strip data URI prefix if present (e.g. data:image/png;base64,...)
        if "," in image_base64:
            image_base64 = image_base64.split(",", 1)[1]

        # Decode image from base64
        image_data = base64.b64decode(image_base64)
```

---

## Priority 5: Eliminate Subprocess Readline Deadlock in `DiskExecutionEnv.run`
- **Target:** `gpt_engineer/core/default/disk_execution_env.py:80-105`
- **Action:** Use non-blocking IO or `communicate(timeout=timeout)` to prevent pipe deadlocks and capture all buffered output:
```python
        try:
            stdout_full, stderr_full = p.communicate(timeout=timeout)
            if stdout_full:
                print(stdout_full, end="")
            if stderr_full:
                print(stderr_full, end="")
        except subprocess.TimeoutExpired:
            print("Timeout!")
            p.kill()
            stdout_full, stderr_full = p.communicate()
            raise TimeoutError()
        except KeyboardInterrupt:
            print()
            print("Stopping execution.")
            p.kill()
            stdout_full, stderr_full = p.communicate()
```

---

## Priority 6: Check Directory Existence in `DiskMemory.archive_logs`
- **Target:** `gpt_engineer/core/default/disk_memory.py:280-286`
- **Action:** Check directory path directly instead of delegating to `is_file`:
```python
    def archive_logs(self):
        """
        Moves all logs to archive directory based on current timestamp
        """
        logs_dir = self.path / "logs"
        if logs_dir.is_dir():
            archive_dir = (
                self.path / f"logs_{datetime.now().strftime('%Y-%m-%d-%H-%M-%S')}"
            )
            shutil.move(logs_dir, archive_dir)
```
