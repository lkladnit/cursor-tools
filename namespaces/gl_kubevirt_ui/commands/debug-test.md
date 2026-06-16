# Debug Test: Focused Single-Test Debugging

Debug a specific failing test case using Playwright MCP as the primary tool, with diagnostic scripts as fallback. Faster and more targeted than `/test-fix-cycle`.

## Input

The user provides a test identifier after the `/debug-test` command:

- **By Jira ID**: `/debug-test CNV-9118`
- **By test name**: `/debug-test "Filter default templates"`
- **By spec file + grep**: `/debug-test scenario-virtualization-pages.spec.ts -g "Filter default"`
- **By spec file (all tests)**: `/debug-test scenario-cluster-settings.spec.ts`

Examples:
```
/debug-test CNV-74220
/debug-test "Memory density toggle and percentage"
/debug-test scenario-cluster-settings.spec.ts -g "Hide YAML tab"
```

## Workflow

---

### Phase 1: Reproduce the Failure

1. **Locate the test** via kubevirt-qe MCP (preferred — deterministic file lookup):
   - If input is a Jira ID: call `find_tests_by_jira` with the ticket ID — returns the exact spec file, tier, and test name
   - If input is a test name or spec file: use as-is
   - **Fallback** (if MCP unavailable): `rg "CNV-XXXXX" playwright/tests/ --type ts -l`
2. **Build the run command** from the resolved test:
   ```bash
   PLAYWRIGHT_RETRIES=0 npx playwright test \
     --config=playwright/playwright.config.ts \
     --grep "ID(CNV-XXXXX)" --workers=1 --reporter=list
   ```
3. **Run the test once** and capture full output to `/tmp/debug-test.log`
4. **Parse the result**:
   - If it **passes**: report success and stop — the test is not currently failing
   - If it **fails**: continue to Phase 2

---

### Phase 2: Diagnose with MCP (Primary)

Use Playwright MCP browser tools to inspect the live application. This is the **primary** debugging method.

**Attempt to connect:**
1. Resize viewport to match Playwright config: `Playwright-browser_resize` → 1920×1080
2. Navigate to the target page using `Playwright-browser_navigate` with the `WEB_CONSOLE_URL` from `.env`
3. If MCP is available and responsive, proceed with the full MCP workflow below
4. If MCP errors out (closed session, connection refused), fall back to **Phase 2b**

**MCP Debugging Workflow:**

1. **Navigate** to the page where the test fails:
   - Read the failing test to identify which page/action fails
   - Use `Playwright-browser_navigate` to go there
   
2. **Snapshot** the accessibility tree:
   ```
   Playwright-browser_snapshot → find elements, data-test attrs, roles
   ```
   - Compare with selectors used in the test's page object
   - Flag any selectors that no longer match

3. **Interact** — reproduce the failing action:
   - Click buttons, fill forms, navigate tabs as the test would
   - Use `Playwright-browser_click`, `Playwright-browser_type`, `Playwright-browser_fill_form`

4. **Inspect state** after the action:
   - `Playwright-browser_snapshot` — verify expected elements appeared
   - `Playwright-browser_take_screenshot` — visual capture
   - `Playwright-browser_console_messages` (level: "error") — JS errors
   - `Playwright-browser_network_requests` — failed API calls (4xx/5xx)
   - `Playwright-browser_evaluate` — query DOM for specific attributes

5. **Identify root cause** from MCP evidence:

| Evidence | Probable Cause | Fix Location |
|----------|---------------|-------------|
| Selector not in snapshot | UI changed, selector drift | Page object |
| Element present but hidden | Overlay, modal, scroll issue | Step driver — add dismiss/scroll |
| API 4xx/5xx in network | Backend error, auth issue | Infrastructure / skip |
| Console JS error | Application bug | Report, don't fix test |
| Element appears after delay | Timing / race condition | Page object — add `waitFor`, `waitForResponse` |
| Toggle state doesn't match | Async state update | Page object — poll state after action |

---

### Phase 2b: Diagnose with Scripts (Fallback)

If MCP is unavailable, use diagnostic scripts:

1. **Run the test headed** to see the browser:
   ```bash
   DEBUG=1 PLAYWRIGHT_RETRIES=0 npx playwright test \
     --config=playwright/playwright.config.ts \
     --grep "ID(CNV-XXXXX)" --workers=1
   ```

2. **Inspect failure artifacts**:
   ```bash
   ls -la test-results/
   ```
   - Screenshots: `test-results/<test-name>/failure-screenshot.png`
   - Videos: `test-results/<test-name>/*.webm`

3. **Write a one-off diagnostic script** if needed:
   ```bash
   npx playwright test --config=playwright/playwright.config.ts \
     playwright/scripts/diagnostic-<feature>.ts --workers=1
   ```
   The script should navigate to the page and dump element info (selectors, visibility, text content).

4. **Clean up diagnostic scripts** after use — they are debugging artifacts.

---

### Phase 3: Apply the Fix

Once the root cause is identified:

1. **Fix in the correct layer**:
   - Selectors → page objects only
   - Waits / timing → page objects (`waitFor`, `waitForResponse`, polling loops)
   - Click issues → `robustClick()` or `force: true`
   - Logic bugs → step drivers or test spec
   - Timeouts → use `TestTimeouts.*` constants
   - State cleanup → `try/finally` with API-level resets

2. **Follow project patterns**:
   - Inline locators for single-use, class properties for 2+ uses
   - `this.locator()` not `this.page.locator()` in page objects
   - `this.step()` wrappers in step drivers
   - `expect.toPass()` with `intervals` for eventual consistency
   - `page.waitForResponse()` before asserting on async backend state

3. **Run lint**:
   ```bash
   npx eslint --fix <modified-files>
   ```

---

### Phase 4: Verify

1. **Run the fixed test** (3 consecutive passes for confidence):
   ```bash
   for i in 1 2 3; do
     echo "=== Run $i ==="
     PLAYWRIGHT_RETRIES=0 npx playwright test \
       --config=playwright/playwright.config.ts \
       --grep "ID(CNV-XXXXX)" --workers=1 --reporter=list
   done
   ```
2. **If all 3 pass**: report the fix
3. **If intermittent**: the fix is incomplete — return to Phase 2 for deeper analysis
4. **If still failing after 2 fix attempts**: report the issue as unfixable with the evidence collected

---

### Phase 5: Summary

Output a concise report:

| Item | Details |
|------|---------|
| **Test** | `ID(CNV-XXXXX) Test name` |
| **File** | `scenario-file.spec.ts` |
| **Root Cause** | Selector drift / race condition / timing / etc. |
| **Evidence** | MCP snapshot showed X / network request failed with Y |
| **Fix Applied** | Updated selector in `page-object.ts` / added waitForResponse / etc. |
| **Files Changed** | List of modified files |
| **Verification** | 3/3 passes |

---

## Important Rules

- **MCP first** — always try Playwright MCP browser tools before falling back to scripts
- **Single test focus** — this command debugs one test at a time, not a suite
- **Development mode** — always use `PLAYWRIGHT_RETRIES=0`
- **Fix in the right layer** — selectors in page objects, logic in step drivers, assertions in tests
- **Don't fix application bugs** — if the product is broken, report it, don't make the test pass on broken behavior
- **Clean up artifacts** — delete any diagnostic scripts or screenshots created during debugging
- **DO NOT commit** — the user handles git operations separately
