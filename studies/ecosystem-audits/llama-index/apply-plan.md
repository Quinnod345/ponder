# Apply Plan: run-llama/llama_index (52.8k★)

## Priority 1: Prevent In-Place Mutation of TextBlock in Memory Store
- **Target:** `llama-index-core/llama_index/core/agent/workflow/multi_agent_workflow.py:452-458` (and `base_agent.py:448-454`)
- **Action:** Clone the target ChatMessage or TextBlock before formatting state prompt:
```python
        if state and not formatted_input_with_state:
            # update last message with current state without mutating memory
            last_msg = llm_input[-1]
            new_blocks = []
            formatted = False
            for block in last_msg.blocks[::-1]:
                if isinstance(block, TextBlock) and not formatted:
                    new_text = self.state_prompt.format(state=state, msg=block.text)
                    new_blocks.append(TextBlock(text=new_text))
                    formatted = True
                else:
                    new_blocks.append(block)
            new_blocks.reverse()
            llm_input[-1] = ChatMessage(role=last_msg.role, blocks=new_blocks)
            await ctx.store.set("formatted_input_with_state", True)
```

---

## Priority 2: Prevent User Message Duplication on Parse Error Retries
- **Target:** `llama-index-core/llama_index/core/agent/workflow/base_agent.py:553-568`
- **Action:** Do not re-append the user message when history already contains it:
```python
        if ev.retry_messages:
            # Retry with the given messages to let the LLM fix potential errors
            history = await memory.aget()

            return AgentInput(
                input=[
                    *history,
                    *ev.retry_messages,
                ],
                current_agent_name=self.name,
            )
```

---

## Priority 3: Fix Handoff Role Inversion and Falsy Context Checks
- **Target:** `llama-index-core/llama_index/core/agent/workflow/multi_agent_workflow.py:83-87, 299`
- **Action:** Correct agent orientation in rejection message and use explicit `is None` checks:
```python
    if can_handoff_to.get(
        current_agent_name, []
    ) is not None and to_agent not in can_handoff_to.get(current_agent_name, []):
        return f"Agent {current_agent_name} cannot hand off to {to_agent}. Please select a valid agent to hand off to."
```
And in `_init_context`:
```python
        if await ctx.store.get("state", default=None) is None:
            await ctx.store.set("state", copy.deepcopy(self.initial_state))
        if await ctx.store.get("can_handoff_to", default=None) is None:
            await ctx.store.set(
                "can_handoff_to",
                {
                    agent: agent_cfg.can_handoff_to
                    for agent, agent_cfg in self.agents.items()
                },
            )
```

---

## Priority 4: Preserve System Prompts in ReActAgent.take_step
- **Target:** `llama-index-core/llama_index/core/agent/workflow/react_agent.py:130-148`
- **Action:** Guard against empty `llm_input` and incorporate `system_prompt` into formatter context:
```python
        if llm_input and llm_input[0].role == "system":
            system_prompt = llm_input[0].content or ""
            llm_input = llm_input[1:]
        else:
            system_prompt = ""

        output_parser = self.output_parser
        react_chat_formatter = self.formatter
        if system_prompt and react_chat_formatter.context != system_prompt:
            react_chat_formatter = ReActChatFormatter.from_defaults(context=system_prompt)
```

---

## Priority 5: Guard Multi-Tool Truncation and Multimodal Content in ChatMemoryBuffer
- **Target:** `llama-index-core/llama_index/core/memory/chat_memory_buffer.py:132-154, 168`
- **Action:** Truncate on user turn boundaries and include block text in token counting:
```python
        while token_count > self.token_limit and message_count > 1:
            message_count -= 1
            # Step back to the preceding user turn boundary
            while message_count > 1 and chat_history[-message_count].role != MessageRole.USER:
                message_count -= 1

            cur_messages = chat_history[-message_count:]
            token_count = (
                self._token_count_for_messages(cur_messages) + initial_token_count
            )
```
