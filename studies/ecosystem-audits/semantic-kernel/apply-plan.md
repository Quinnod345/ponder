# Apply Plan: microsoft/semantic-kernel (Case Study 46)

## Priority 1: Fix Operator Precedence in OrchestrationHandoffs.add
- **Target:** `python/semantic_kernel/agents/orchestration/handoffs.py:72-87`
- **Action:** Add explicit parentheses to prevent ternary operator from overriding explicit descriptions when `target_agent` is a string:
```python
    def add(self, source_agent: str | Agent, target_agent: str | Agent, description: str | None = None) -> "Self":
        """Add a handoff connection to the source agent."""
        resolved_description = (
            description
            or (target_agent.description if isinstance(target_agent, Agent) else "")
            or ""
        )
        return self._add(
            source_agent=source_agent if isinstance(source_agent, str) else source_agent.name,
            target_agent=target_agent if isinstance(target_agent, str) else target_agent.name,
            description=resolved_description,
        )
```

---

## Priority 2: Add Bounds Checking in RoundRobinGroupChatManager
- **Target:** `python/semantic_kernel/agents/orchestration/group_chat.py:220-238`
- **Action:** Guard against empty message history and empty participant descriptions:
```python
    @override
    async def select_next_agent(
        self,
        chat_history: ChatHistory,
        participant_descriptions: dict[str, str],
    ) -> StringResult:
        """Select the next agent to speak."""
        if not participant_descriptions:
            raise AgentExecutionException("No participants available in group chat.")
        participants = list(participant_descriptions.keys())
        self.current_index = self.current_index % len(participants)
        next_agent = participants[self.current_index]
        self.current_index = (self.current_index + 1) % len(participants)
        return StringResult(result=next_agent, reason="Round-robin selection.")

    @override
    async def filter_results(
        self,
        chat_history: ChatHistory,
    ) -> MessageResult:
        """Filter the results of the group chat."""
        if not chat_history.messages:
            raise AgentExecutionException("Chat history is empty; cannot filter results.")
        return MessageResult(
            result=chat_history.messages[-1],
            reason="The last message in the chat history is the result in the default round-robin group chat manager.",
        )
```

---

## Priority 3: Retain Multi-Turn Intermediate Messages in HandoffAgentActor Cache
- **Target:** `python/semantic_kernel/agents/orchestration/handoffs.py:290-315`
- **Action:** Append intermediate human responses and agent responses to `self._message_cache`:
```python
            if self._human_response_function:
                human_response = await self._call_human_response_function()
                self._message_cache.add_message(human_response)
                await self.publish_message(
                    HandoffResponseMessage(body=human_response),
                    TopicId(self._internal_topic_type, self.id.key),
                    cancellation_token=cts.cancellation_token,
                )
                response = await self._invoke_agent_with_potentially_no_response(
                    additional_messages=human_response,
                    kernel=self._kernel,
                )
                if response:
                    self._message_cache.add_message(response)
```

---

## Priority 4: Warn When User Input Is Requested Without Configured Handler
- **Target:** `python/semantic_kernel/agents/orchestration/group_chat.py:305-325`
- **Action:** Log warning if user input is requested but no callback is present:
```python
        should_request_user_input = await self._manager.should_request_user_input(
            self._chat_history.model_copy(deep=True)
        )
        if should_request_user_input.result:
            if self._manager.human_response_function:
                logger.debug(f"Group chat manager requested user input. Reason: {should_request_user_input.reason}")
                user_input_message = await self._call_human_response_function()
                self._chat_history.add_message(user_input_message)
                await self.publish_message(
                    GroupChatResponseMessage(body=user_input_message),
                    TopicId(self._internal_topic_type, self.id.key),
                    cancellation_token=cancellation_token,
                )
                logger.debug("User input received and added to chat history.")
            else:
                logger.warning(
                    f"User input requested by group chat manager (reason: {should_request_user_input.reason}) "
                    "but no human_response_function is configured on the manager."
                )
```

---

## Priority 5: Wrap Completion Check in Lock Critical Section
- **Target:** `python/semantic_kernel/agents/orchestration/concurrent.py:120-135`
- **Action:** Evaluate completed count and copy results inside the lock:
```python
    @message_handler
    async def _handle_message(self, message: ConcurrentResponseMessage, _: MessageContext) -> None:
        async with self._lock:
            self._results.append(message.body)
            is_complete = len(self._results) == self._expected_answer_count
            results_snapshot = list(self._results) if is_complete else None

        if is_complete and results_snapshot is not None:
            logger.debug(f"Collection actor (Actor ID: {self.id}) finished processing all responses.")
            if self._result_callback:
                await self._result_callback(results_snapshot)
```

---

## Priority 6: Guard None Agent Variable Name in KernelFunctionSelectionStrategy
- **Target:** `python/semantic_kernel/agents/strategies/selection/kernel_function_selection_strategy.py:70-90`
- **Action:** Only populate `filtered_arguments` with non-None keys:
```python
        filtered_arguments: dict[str, Any] = {}
        if self.agent_variable_name:
            filtered_arguments[self.agent_variable_name] = ",".join(agent.name for agent in agents)
        if self.history_variable_name:
            filtered_arguments[self.history_variable_name] = messages
```
