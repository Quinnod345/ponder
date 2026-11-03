# Khoj Remediation Plan

## Priority 1: Ensure Sandbox Kill in execute_e2b
- **Target:** `src/khoj/processor/tools/run_code.py:236-324`
- **Action:** Enclose sandbox execution in a `try...finally` block ensuring remote instances are always terminated:
```python
    sandbox = await AsyncSandbox.create(
        api_key=os.getenv("E2B_API_KEY"),
        template=os.getenv("E2B_TEMPLATE", DEFAULT_E2B_TEMPLATE),
        timeout=120,
        request_timeout=30,
    )

    try:
        # Upload input files, run code, and collect output files
        ...
        return {
            "code": code,
            "success": success,
            "std_out": stdout,
            "std_err": errors,
            "output_files": output_files,
        }
    except Exception as e:
        return {
            "code": code,
            "success": False,
            "std_err": f"Sandbox failed to execute code: {str(e)}",
            "output_files": [],
        }
    finally:
        try:
            await sandbox.kill()
        except Exception as e:
            logger.debug(f"Failed to kill E2B sandbox: {e}")
```

---

## Priority 2: Safe Mimetype Guard in execute_terrarium
- **Target:** `src/khoj/processor/tools/run_code.py:337-339`
- **Action:** Guard against `None` mimetype before calling `.startswith()`:
```python
                for output_file in result["output_files"]:
                    guessed_type = mimetypes.guess_type(output_file["filename"])[0]
                    is_text = (guessed_type and guessed_type.startswith("text/")) or Path(
                        output_file["filename"]
                    ).suffix in [".org", ".md", ".json"]
                    if is_text:
                        output_file["b64_data"] = base64.b64decode(output_file["b64_data"]).decode("utf-8")
```

---

## Priority 3: Default Tracer Dictionary in GroundingAgent
- **Target:** `src/khoj/processor/operator/grounding_agent.py:44,69-74`
- **Action:** Default `self.tracer` to a dictionary or check for `None` before updating usage:
```python
        self.tracer = tracer if tracer is not None else {}
```

---

## Priority 4: Register SSE Contexts in exit_stack in MCPClient
- **Target:** `src/khoj/processor/tools/mcp.py:77-86`
- **Action:** Manage SSE client streams and session in `self.exit_stack`:
```python
    async def _connect_to_sse_server(self):
        """Connect to the MCP server using Server-Sent Events (SSE)."""
        self._streams_context = sse_client(url=self.path)
        streams = await self.exit_stack.enter_async_context(self._streams_context)

        self._session_context = ClientSession(*streams)
        self.session = await self.exit_stack.enter_async_context(self._session_context)

        # Initialize
        await self.session.initialize()
```

---

## Priority 5: Add -y Flag to npx Command in _connect_to_stdio_server
- **Target:** `src/khoj/processor/tools/mcp.py:97-101`
- **Action:** Automatically confirm package installation in headless environments:
```python
        if self.path.startswith("@") or "/" not in self.path:
            # Assume it's an npm package
            is_javascript = True
            command = "npx"
            args = ["-y", self.path]
```

---

## Priority 6: Wait for Navigation in handle_new_page
- **Target:** `src/khoj/processor/operator/operator_environment_browser.py:73-84`
- **Action:** Wait for initial URL resolution before closing popup tab:
```python
        async def handle_new_page(new_page: Page):
            try:
                if new_page.url == "about:blank":
                    await new_page.wait_for_load_state(timeout=5000)
                target_url = new_page.url
            except Exception:
                target_url = new_page.url
            finally:
                if not new_page.is_closed():
                    await new_page.close()
            if target_url and target_url != "about:blank" and self.page:
                logger.debug(f"Load {target_url} in current page instead of new tab.")
                await self.page.goto(target_url)
```
