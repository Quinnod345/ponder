# Apply Plan: geekan/MetaGPT Audit

Generated from Ponder deliberation audit session `metagpt` (4 passes, 1.00 coverage, 0.00 churn).

## Priority 1: Ensure project archival executes upon NoMoneyException in Team.run()
- **Target:** `metagpt/team.py:128-138`
- **Action:** Wrap the simulation round loop in a `try...finally` block so `self.env.archive(auto_archive)` is guaranteed to execute even if `_check_balance()` raises `NoMoneyException`:
```python
try:
    while n_round > 0:
        if self.env.is_idle:
            logger.debug("All roles are idle.")
            break
        n_round -= 1
        self._check_balance()
        await self.env.run()
        logger.debug(f"max {n_round=} left.")
finally:
    self.env.archive(auto_archive)
```
- **Impact:** Guarantees that completed intermediate role outputs, documents, and code generated prior to budget exhaustion are persisted and archived rather than lost.

## Priority 2: Cancel orphaned background tasks in SubscriptionRunner.run() and guard unsubscribe()
- **Target:** `metagpt/subscription.py:75-81`, `88-106`
- **Action:** Cancel active tasks in a `finally` block when an unhandled task exception is re-raised, and use `self.tasks.pop(role, None)` in `unsubscribe()`:
```python
async def unsubscribe(self, role: Role):
    task = self.tasks.pop(role, None)
    if task:
        task.cancel()

async def run(self, raise_exception: bool = True):
    try:
        while True:
            for role, task in list(self.tasks.items()):
                if task.done():
                    if task.exception():
                        if raise_exception:
                            raise task.exception()
                        logger.opt(exception=task.exception()).error(f"Task {task.get_name()} run error")
                    else:
                        logger.warning(
                            f"Task {task.get_name()} has completed. "
                            "If this is unexpected behavior, please check the trigger function."
                        )
                    self.tasks.pop(role, None)
                    break
            else:
                await asyncio.sleep(1)
    finally:
        for t in self.tasks.values():
            if not t.done():
                t.cancel()
```
- **Impact:** Eliminates orphaned background tasks leaking in the asyncio event loop and prevents unhandled KeyErrors on duplicate unsubscriptions.

## Priority 3: Guard Memory.delete() against absent messages and fix mutable default
- **Target:** `metagpt/memory/memory.py:23`, `59-66`
- **Action:** Guard the list removal with a presence check and declare `storage` using `Field(default_factory=list)`:
```python
storage: list[SerializeAsAny[Message]] = Field(default_factory=list)

def delete(self, message: Message):
    if self.ignore_id:
        message.id = IGNORED_MESSAGE_ID
    if message in self.storage:
        self.storage.remove(message)
    if message.cause_by and message in self.index.get(message.cause_by, []):
        self.index[message.cause_by].remove(message)
```
- **Impact:** Prevents unhandled `ValueError: list.remove(x): x not in list` exceptions during memory cleanups and removes mutable class-attribute defaults.
