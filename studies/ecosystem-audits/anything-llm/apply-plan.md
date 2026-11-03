# Ponder Ecosystem Apply Plan: Mintplex-Labs/anything-llm

## Priority 1: Wrap Tool Handler in try...catch in handleExecution
- **Target:** `server/utils/agents/aibitat/index.js:1256-1262`
- **Action:** Safely catch tool handler exceptions and return error text for LLM recovery:
```javascript
      let result;
      try {
        result = await fn.handler(args);
      } catch (error) {
        this.handlerProps?.log?.(`[error]: ${fn.caller} tool call ${name} failed: ${error.message}`);
        result = `Error executing tool ${name}: ${error.message}`;
      }
```

---

## Priority 2: Hard-Stop Runaway Tool Chains When Depth Exceeds maxToolCalls
- **Target:** `server/utils/agents/aibitat/index.js:1225-1235`
- **Action:** Return early when depth strictly exceeds maximum tool calls:
```javascript
      if (depth > this.maxToolCalls) {
        this.handlerProps?.log?.(
          `[warning]: Maximum tool call limit (${this.maxToolCalls}) exceeded. Refusing additional tool call ${name}.`
        );
        return "Maximum tool call limit reached. I am now generating the final response.";
      }
```

---

## Priority 3: Replace Monotonic Promise Array with Tail Promise Chain in CLI Plugin
- **Target:** `server/utils/agents/aibitat/plugins/cli.js:20-39`
- **Action:** Replace unbounded array with linear promise sequencing and error recovery:
```javascript
        let printingQueue = Promise.resolve();

        aibitat.onStart(() => {
          console.log();
          console.log("🚀 starting chat ...\n");
          printingQueue = Promise.resolve();
        });

        aibitat.onMessage(async (message) => {
          printingQueue = printingQueue.then(async () => {
            try {
              await this.print(message, simulateStream);
            } catch (err) {
              console.error("Printing stream error:", err);
            }
          });
        });

        aibitat.onTerminate(async () => {
          await printingQueue;
          console.log("🚀 chat finished");
        });
```

---

## Priority 4: Only Track Successful Runs in RAG Memory Deduplicator
- **Target:** `server/utils/agents/aibitat/plugins/memory.js:70-80`
- **Action:** Skip tracking when search or store operations fail:
```javascript
              let response = "There was nothing to do.";
              let succeeded = false;
              if (action === "search") {
                response = await this.search(content);
                succeeded = !response.startsWith("An error was raised");
              }
              if (action === "store") {
                response = await this.store(content);
                succeeded = !response.includes("error was raised") && !response.includes("failed to be embedded");
              }

              if (succeeded) {
                this.tracker.trackRun(this.name, { action, content });
              }
              return response;
```

---

## Priority 5: Generate Unique Document URLs and Titles in memory.store
- **Target:** `server/utils/agents/aibitat/plugins/memory.js:140-165`
- **Action:** Append UUID to document url and title:
```javascript
              const docId = v4();
              const { error } = await vectorDB.addDocumentToNamespace(
                workspace.slug,
                {
                  docId,
                  id: docId,
                  url: `file://embed-via-agent-${docId}.txt`,
                  title: `agent-memory-${docId.slice(0, 8)}.txt`,
                  docAuthor: "@agent",
                  description: "Stored by workspace agent",
                  docSource: "a text file stored by the workspace agent.",
                  chunkSource: "",
                  published: new Date().toLocaleString(),
                  wordCount: content.split(" ").length,
                  pageContent: content,
                  token_count_estimate: 0,
                },
                null
              );
```

---

## Priority 6: Add AbortSignal.timeout to DeepSeek Web Search fetch
- **Target:** `server/utils/agents/aibitat/plugins/web-browsing.js:780-820`
- **Action:** Pass AbortSignal.timeout(15000) to fetch:
```javascript
            const { response, error } = await fetch(
              "https://api.deepseek.com/v1/tools/search",
              {
                method: "POST",
                signal: AbortSignal.timeout(15000),
                headers: {
                  "Content-Type": "application/json",
                  Authorization: `Bearer ${apiKey}`,
                },
                body: JSON.stringify({ query: String(query), count: 10 }),
              }
            )
```
