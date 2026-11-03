# Apply Plan: langgenius/dify Audit

Generated from Ponder deliberation audit session `dify` (4 passes, 1.00 coverage, 0.00 churn).

## Priority 1: Move database session closing outside parallel tool execution loop in FunctionCallAgentRunner
- **Target:** `api/core/agent/fc_agent_runner.py:348-368`
- **Action:** Move `session.commit()` and `session.close()` outside the `for tool_call_id, tool_call_name, tool_call_args in tool_calls:` loop, ensuring `_build_dataset_tool_image_contents(session=session, ...)` and subsequent tool iterations operate on a valid open database session:
```python
            # call tools
            tool_responses = []
            for tool_call_id, tool_call_name, tool_call_args in tool_calls:
                tool_instance = tool_instances.get(tool_call_name)
                if not tool_instance:
                    tool_response = {
                        "tool_call_id": tool_call_id,
                        "tool_call_name": tool_call_name,
                        "tool_response": f"there is not a tool named {tool_call_name}",
                        "meta": ToolInvokeMeta.error_instance(f"there is not a tool named {tool_call_name}").to_dict(),
                    }
                else:
                    # invoke tool
                    with use_credit_usage_metadata({"app_type": CreditUsageAppType.AGENT}):
                        tool_invoke_response, message_files, tool_invoke_meta = ToolEngine.agent_invoke(
                            session=session,
                            tool=tool_instance,
                            tool_parameters=tool_call_args,
                            user_id=self.user_id,
                            tenant_id=self.tenant_id,
                            message=self.message,
                            invoke_from=self.application_generate_entity.invoke_from,
                            agent_tool_callback=self.agent_callback,
                            trace_scope=trace_scope,
                            app_id=self.application_generate_entity.app_config.app_id,
                            message_id=self.message.id,
                            conversation_id=self.conversation.id,
                        )

                    # publish files
                    for message_file_id in message_files:
                        self.queue_manager.publish(
                            QueueMessageFileEvent(message_file_id=message_file_id), PublishFrom.APPLICATION_MANAGER
                        )
                        message_file_ids.append(message_file_id)

                    tool_response = {
                        "tool_call_id": tool_call_id,
                        "tool_call_name": tool_call_name,
                        "tool_response": tool_invoke_response,
                        "meta": tool_invoke_meta.to_dict(),
                    }

                tool_responses.append(tool_response)
                if tool_response["tool_response"] is not None:
                    tool_response_text = str(tool_response["tool_response"])
                    dataset_image_contents = self._build_dataset_tool_image_contents(
                        session=session,
                        tool_response=tool_response_text,
                        tool_instance=tool_instance,
                    )
                    self._current_thoughts.append(
                        ToolPromptMessage(
                            content=tool_response_text,
                            tool_call_id=tool_call_id,
                            name=tool_call_name,
                        )
                    )
                    if dataset_image_contents:
                        self._current_thoughts.append(
                            UserPromptMessage(
                                name=_KNOWLEDGE_RETRIEVAL_PROMPT_NAME,
                                content=[
                                    *dataset_image_contents,
                                    TextPromptMessageContent(data=self.query or tool_response_text),
                                ],
                            )
                        )

            # Release session after completing all tool invocations and queries
            session.commit()
            session.close()
```
- **Impact:** Eliminates SQLAlchemy `InvalidRequestError` and connection pool checkout failures during parallel tool calling.

## Priority 2: Key observation and meta dictionaries by tool_call_id rather than tool_call_name
- **Target:** `api/core/agent/fc_agent_runner.py:387-399`
- **Action:** Retain distinct observations for each parallel tool execution rather than overwriting matching tool names:
```python
            if len(tool_responses) > 0:
                # save agent thought
                self.save_agent_thought(
                    agent_thought_id=agent_thought_id,
                    tool_name="",
                    tool_input="",
                    thought="",
                    tool_invoke_meta={
                        f"{tool_response['tool_call_name']}:{tool_response['tool_call_id']}": tool_response["meta"]
                        for tool_response in tool_responses
                    },
                    observation={
                        f"{tool_response['tool_call_name']}:{tool_response['tool_call_id']}": tool_response["tool_response"]
                        for tool_response in tool_responses
                    },
                    answer="",
                    messages_ids=message_file_ids,
                )
```
- **Impact:** Prevents observation clobbering when an agent makes multiple parallel invocations of the same tool in a single turn.

## Priority 3: Eliminate duplicate thought concatenation in CotAgentRunner
- **Target:** `api/core/agent/cot_agent_runner.py:250-262`
- **Action:** Pass `thought=""` in the second `save_agent_thought` invocation after tool execution to avoid doubling the scratchpad thought:
```python
                    self.save_agent_thought(
                        agent_thought_id=agent_thought_id,
                        tool_name=scratchpad.action.action_name,
                        tool_input={scratchpad.action.action_name: scratchpad.action.action_input},
                        thought="",
                        observation={scratchpad.action.action_name: tool_invoke_response},
                        tool_invoke_meta={scratchpad.action.action_name: tool_invoke_meta.to_dict()},
                        answer=scratchpad.agent_response,
                        messages_ids=message_file_ids,
                        llm_usage=usage_dict["usage"],
                    )
```
- **Impact:** Keeps the persisted database thought clean and prevents redundant duplicate string repeats.

## Priority 4: Handle list actions safely and qualify key matching in CotAgentOutputParser
- **Target:** `api/core/agent/output_parser/cot_output_parser.py:20-40`
- **Action:** Safeguard against multi-item lists and check explicit action keys:
```python
        def parse_action(action) -> str | AgentScratchpadUnit.Action:
            action_name = None
            action_input = None
            if isinstance(action, str):
                try:
                    action = json.loads(action, strict=False)
                except json.JSONDecodeError:
                    return action or ""

            if isinstance(action, list):
                if not action:
                    return ""
                action = action[0]

            if isinstance(action, dict):
                for key, value in action.items():
                    k_lower = key.lower()
                    if "input" in k_lower or "param" in k_lower or "arg" in k_lower:
                        action_input = value
                    elif "action" in k_lower or "name" in k_lower or "tool" in k_lower:
                        action_name = value

            if action_name is not None and action_input is not None:
                return AgentScratchpadUnit.Action(
                    action_name=action_name,
                    action_input=action_input,
                )
            else:
                return json.dumps(action)
```
- **Impact:** Prevents `AttributeError: 'list' object has no attribute 'items'` and accidental overwriting of `action_name`.

## Priority 5: Maintain conversational turn pair integrity and bound single-message size in TokenBufferMemory
- **Target:** `api/core/memory/token_buffer_memory.py:110-120`
- **Action:** Pop conversational pairs or ensure turn starts with User message, and truncate if a single message exceeds the token budget:
```python
        curr_message_tokens = model_instance.get_llm_num_tokens(prompt_messages)
        while curr_message_tokens > max_token_limit and len(prompt_messages) > 1:
            prompt_messages.pop(0)
            while prompt_messages and prompt_messages[0].role != PromptMessageRole.USER and len(prompt_messages) > 1:
                prompt_messages.pop(0)
            curr_message_tokens = model_instance.get_llm_num_tokens(prompt_messages)
```
- **Impact:** Prevents provider API validation errors from orphaned assistant turns at the head of prompt messages.
