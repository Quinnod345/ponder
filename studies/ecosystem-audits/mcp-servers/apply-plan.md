# Ponder Apply Plan: modelcontextprotocol/servers

This apply plan provides minimal, verified patches for findings identified during the 4-pass deliberation audit of `modelcontextprotocol/servers`.

---

## Priority 1: Ensure Parent Directory Exists in `KnowledgeGraphManager.saveGraph`
- **Target:** `src/memory/index.ts:544-555`
- **Action:** Ensure parent directory existence before creating temporary file:
```typescript
    const directory = path.dirname(this.memoryFilePath);
    await fs.mkdir(directory, { recursive: true });
    const tempFilePath = path.join(
      directory,
      `${path.basename(this.memoryFilePath)}.${randomBytes(16).toString("hex")}.tmp`,
    );
```

---

## Priority 2: Deduplicate Intra-Batch Observations in `KnowledgeGraphManager.addObservations`
- **Target:** `src/memory/index.ts:641-645`
- **Action:** Add index check to filter duplicates within the same batch item:
```typescript
        const newObservations = o.contents.filter(
          (content, idx) =>
            !entity.observations.includes(content) &&
            o.contents.indexOf(content) === idx,
        );
```

---

## Priority 3: Use O(1) Set Lookups in `KnowledgeGraphManager.deleteEntities`
- **Target:** `src/memory/index.ts:658-666`
- **Action:** Replace array includes with Set lookups:
```typescript
      const toDelete = new Set(entityNames);
      graph.entities = graph.entities.filter(
        (e) => !toDelete.has(e.name),
      );
      graph.relations = graph.relations.filter(
        (r) => !toDelete.has(r.from) && !toDelete.has(r.to),
      );
```

---

## Priority 4: Support Multiline Thoughts in `SequentialThinkingServer.formatThought`
- **Target:** `src/sequentialthinking/lib.ts:70-87`
- **Action:** Split thought lines and render each line within border boundaries:
```typescript
    const thoughtLines = thought.split("\n");
    const maxThoughtWidth = Math.max(...thoughtLines.map((l) => l.length));
    const contentWidth = Math.max(visibleHeader.length, maxThoughtWidth);
    const border = "─".repeat(contentWidth + 4);
    const padding = " ".repeat(border.length - 2 - visibleHeader.length);
    const header = `${colour(label)}${counts}${padding}`;

    const formattedLines = thoughtLines
      .map((line) => `│ ${line.padEnd(border.length - 4)} │`)
      .join("\n");

    return `
┌${border}┐
│ ${header} │
├${border}┤
${formattedLines}
└${border}┘`;
```
