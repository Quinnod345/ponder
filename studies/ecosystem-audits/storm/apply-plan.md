# Apply Plan: stanford-oval/storm (Case Study 41)

**Target Repository:** `stanford-oval/storm`  
**Target Branch:** `main`  
**Scope:** 5 modules, 7 verified fixes  

---

## Priority 1: Correct Reference Pruning Bounds in `update_section`
- **Target:** `knowledge_storm/storm_wiki/modules/storm_dataclass.py:274-278`
- **Action:** Start deletion range at `len(current_section_info_list) + 1`:
```python
            if len(references) > 0:
                max_ref_num = max(references)
                if max_ref_num > len(current_section_info_list):
                    for i in range(len(current_section_info_list) + 1, max_ref_num + 1):
                        current_section_content = current_section_content.replace(
                            f"[{i}]", ""
                        )
                        if i in references:
                            references.remove(i)
```

---

## Priority 2: Fix Markdown Level Counting and Trailing Hash Trimming
- **Target:** `knowledge_storm/utils.py:578-583`
- **Action:** Count only leading `#` characters and strip only leading hashes:
```python
            if line.startswith("#"):
                stripped_left = line.lstrip("#")
                level = len(line) - len(stripped_left)
                title = stripped_left.strip()
                new_section = {"content": "", "subsections": {}}
```

---

## Priority 3: Forward `self.args.disable_perspective` in Runner
- **Target:** `knowledge_storm/storm_wiki/engine.py:214`
- **Action:** Pass `disable_perspective=self.args.disable_perspective`:
```python
        (
            information_table,
            conversation_log,
        ) = self.storm_knowledge_curation_module.research(
            topic=self.topic,
            ground_truth_url=ground_truth_url,
            callback_handler=callback_handler,
            max_perspective=self.args.max_perspective,
            disable_perspective=self.args.disable_perspective,
            return_conversation_log=True,
        )
```

---

## Priority 4: Strip Only Leading List Bullets in `TopicExpert.forward`
- **Target:** `knowledge_storm/storm_wiki/modules/knowledge_curation.py:209-213`
- **Action:** Use regex to strip leading bullet markers while preserving word hyphens:
```python
            import re
            queries = [
                re.sub(r"^\s*[-*\d.]+\s*", "", q).strip().strip('"')
                for q in queries.split("\n")
            ]
            queries = [q for q in queries if q]
            queries = queries[: self.max_search_queries]
```

---

## Priority 5: Harden `YouRM.forward` Query Encoding, Timeout, and Hits Check
- **Target:** `knowledge_storm/rm.py:50-60`
- **Action:** URL-encode parameters, pass timeout, and guard `hits` access:
```python
        for query in queries:
            try:
                headers = {"X-API-Key": self.ydc_api_key}
                response = requests.get(
                    "https://api.ydc-index.io/search",
                    headers=headers,
                    params={"query": query},
                    timeout=15,
                )
                results = response.json()

                authoritative_results = []
                if isinstance(results, dict) and "hits" in results:
                    for r in results["hits"]:
                        if self.is_valid_source(r.get("url", "")) and r.get("url") not in exclude_urls:
                            authoritative_results.append(r)
                    collected_results.extend(authoritative_results[: self.k])
            except Exception as e:
                logging.error(f"Error occurs when searching query {query}: {e}")
```

---

## Priority 6: Remove Unexpected `persona` Parameter in `AskQuestion`
- **Target:** `knowledge_storm/storm_wiki/modules/knowledge_curation.py:123-126`
- **Action:** Call `self.ask_question` with only `topic` and `conv`:
```python
            else:
                question = self.ask_question(
                    topic=topic, conv=conv
                ).question
```
