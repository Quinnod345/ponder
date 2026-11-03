# Apply Plan: assafelovic/gpt-researcher Deliberation Audit Findings

## Priority 1: Prevent exponential context duplication in recursive DeepResearchSkill
- **Target:** `gpt_researcher/skills/deep_research.py:530-580`
- **Action:** Only update `self.context` and `self.research_sources` at the outer entry point, preventing repeated appending across recursive calls:
```python
        # Collect all results
        for result in results:
            all_learnings.extend(result['learnings'])
            all_visited_urls.update(result['visited_urls'])
            all_citations.update(result['citations'])
            if result['context']:
                ctx = result['context']
                if isinstance(ctx, list):
                    all_context.extend(ctx)
                else:
                    all_context.append(ctx)
            if result['sources']:
                all_sources.extend(result['sources'])

            # Continue deeper if needed
            if depth > 1:
                new_breadth = max(2, breadth // 2)
                new_depth = depth - 1

                # Create next query from research goal and follow-up questions
                next_query = f"""
                Previous research goal: {result['researchGoal']}
                Follow-up questions: {' '.join(result['followUpQuestions'])}
                """

                # Recursive research
                deeper_results = await self.deep_research(
                    query=next_query,
                    breadth=new_breadth,
                    depth=new_depth,
                    learnings=all_learnings,
                    citations=all_citations,
                    visited_urls=all_visited_urls,
                    on_progress=on_progress
                )

                all_learnings = deeper_results['learnings']
                all_visited_urls.update(deeper_results['visited_urls'])
                all_citations.update(deeper_results['citations'])
                if deeper_results.get('context'):
                    all_context.extend(deeper_results['context'])
                if deeper_results.get('sources'):
                    all_sources.extend(deeper_results['sources'])

        # Only mutate instance tracking at top-level caller
        trimmed_context = trim_context_to_word_limit(all_context)
        return {
            'learnings': list(set(all_learnings)),
            'visited_urls': list(all_visited_urls),
            'citations': all_citations,
            'context': trimmed_context,
            'sources': all_sources
        }
```

## Priority 2: Offload synchronous DocumentLoader.load calls to worker threads
- **Target:** `gpt_researcher/document/document.py:20-65`
- **Action:** Wrap synchronous `loader.load()` in `asyncio.to_thread`:
```python
            loader = loader_dict.get(file_extension, None)
            if loader:
                try:
                    ret_data = await asyncio.to_thread(loader.load)
                except Exception as e:
                    print(f"Failed to load {file_extension or 'unknown'} document: {file_path}")
                    print(e)
```

## Priority 3: Maintain relative path hierarchy in DocumentLoader url identifiers
- **Target:** `gpt_researcher/document/document.py:48-58`
- **Action:** Use relative path resolution to distinguish identically named files across subdirectories:
```python
                    meta = getattr(page, "metadata", None) or {}
                    source = meta.get("source") or meta.get("file_path") or ""
                    if source and isinstance(self.path, str) and os.path.isdir(self.path):
                        url = os.path.relpath(source, self.path)
                    else:
                        url = os.path.basename(source) if source else ""
```

## Priority 4: Correct depth counter advances in DeepResearchSkill progress reporting
- **Target:** `gpt_researcher/skills/deep_research.py:536-545`
- **Action:** Increment `current_depth` outside the breadth query loop and forward progress references:
```python
        if depth > 1:
            progress.current_depth += 1
            if on_progress:
                on_progress(progress)
```

## Priority 5: Await underlying transport teardown in MCPClientManager.close_client
- **Target:** `gpt_researcher/mcp/client.py:155-175`
- **Action:** Call `aclose()` on active client instances if supported by the adapter:
```python
    async def close_client(self):
        """Properly close the MCP client and clean up resources."""
        async with self._client_lock:
            if self._client is not None:
                try:
                    if hasattr(self._client, 'aclose'):
                        await self._client.aclose()
                    elif hasattr(self._client, 'close'):
                        self._client.close()
                    logger.debug("Released MCP client reference and closed active transports")
                except Exception as e:
                    logger.error(f"Error during MCP client cleanup: {e}")
                finally:
                    self._client = None
```
