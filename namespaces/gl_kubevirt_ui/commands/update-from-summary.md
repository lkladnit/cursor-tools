# Update From Summary: Explore and Update Tests Based on a Change Description

Receive a plain-text summary of UI or feature changes, explore the codebase and live UI to identify affected tests, and apply updates across all relevant layers.

## Input

The user provides a change description after the `/update-from-summary` command. The description can be free-form text, a release note excerpt, a PR description, a bullet list of changes, and/or one or more Jira ticket IDs for additional context.

- **Free-form**: `/update-from-summary The Create dropdown on the VM list now shows "New VirtualMachine" instead of "From wizard"`
- **Multi-change**: `/update-from-summary The overview page was restructured: Top Consumers and Migrations are now sections on the VM list Overview tab instead of separate sub-tabs. The URL /virtualization-overview no longer exists.`
- **With Jira reference**: `/update-from-summary CNV-82213 The storage migration page is now a standalone page under Virtualization`
- **Jira only (summary fetched from API)**: `/update-from-summary CNV-82506`
- **Multiple Jira + description**: `/update-from-summary CNV-82213, CNV-83178 Overview and wizard restructured in 4.22`
- **With scope hint**: `/update-from-summary --scope=gating The settings page "Preview features" section was renamed to "Technology preview"`
- **Dry run**: `/update-from-summary --dry-run The template catalog now groups templates by provider`

Optional flags:
- `--scope=gating|tier1|all` — limit the search to a specific tier (default: `all`)
- `--dry-run` — produce the impact report without making code changes

### Jira Ticket Handling

When the input contains one or more Jira ticket IDs (pattern `CNV-\d+`):

1. **Fetch each ticket from the REST API** (mandatory — same as `/jira-task`):
   ```bash
   curl -s "https://redhat.atlassian.net/rest/api/3/issue/{TICKET_KEY}" | python3 -c "
   import sys, json
   data = json.load(sys.stdin)
   fields = data.get('fields', {})
   print(f'Key: {data.get(\"key\")}')
   print(f'Summary: {fields.get(\"summary\")}')
   print(f'Status: {fields.get(\"status\", {}).get(\"name\")}')
   print(f'Description: {fields.get(\"description\", \"N/A\")[:500]}')
   subtasks = fields.get('subtasks', [])
   print(f'Subtasks ({len(subtasks)}): {[s.get(\"key\") for s in subtasks]}')
   "
   ```
2. **Merge ticket data with the user-provided summary** — the Jira description supplements the free-form text, it does not replace it
3. If only Jira IDs are provided (no free-form text), the ticket summary and description become the change description
4. Search the codebase for existing references to the ticket IDs:
   ```bash
   rg "CNV-XXXXX" playwright/tests/ playwright/docs/ playwright/src/ --type ts --type md
   ```

## Workflow

---

### Phase 1: Change Parsing (Orchestrator)

1. **Extract change items** from the summary — each distinct UI or behavior change becomes a separate item
2. **Derive search keywords** for each item (page names, element names, URL fragments, feature names)
3. **Output**: numbered list of change items with keywords

Example:
```
Change 1: "From wizard" menu item renamed to "New VirtualMachine"
  Keywords: wizard, From wizard, New VirtualMachine, Create dropdown, vm-creation-wizard
Change 2: Overview sub-tabs removed, content moved to VM list Overview tab
  Keywords: overview, sub-tabs, Top Consumers, Migrations, virtualization-overview
```

---

### Phase 2: Impact Analysis (QA Architect)

Follow `qa-architect.mdc` rules.

For each change item:

1. **Search the codebase** for affected files:
   ```bash
   rg "<keyword>" playwright/src/page-objects/ playwright/src/step-drivers/ playwright/tests/ --type ts -l
   rg "<keyword>" playwright/docs/ --type md -l
   ```
2. **Map affected components** — for each matching file, identify:
   - Page object methods that use the changed selector/text/URL
   - Step driver methods that wrap those page object methods
   - Tests that call those step driver methods
   - STD documents that describe those tests
3. **Classify the impact** per component:

| Impact | Criteria | Action |
|--------|----------|--------|
| **Selector update** | Element text, `data-test` attr, or role changed | Update locator in page object |
| **Navigation update** | URL path changed or removed | Update `goTo()` calls and fallback URLs in page object |
| **Logic update** | Behavior changed (e.g., sub-tabs → sections) | Update page object methods + step driver logic |
| **Assertion update** | Expected values changed (labels, headings, counts) | Update assertions in tests or step drivers |
| **Removal** | Feature/element removed entirely | Remove or skip affected tests |

4. **Output**: impact report table

| # | Change | Affected Files | Impact Type | Action Needed |
|---|--------|---------------|-------------|--------------|
| 1 | "From wizard" → "New VirtualMachine" | `vm-creation-wizard-page.ts`, `vm-creation-wizard-step-driver.ts`, `scenario-vm-creation-wizard.spec.ts` | Selector update | Update menu item text in page object |
| 2 | Overview sub-tabs removed | `overview-page.ts`, `overview-step-driver.ts`, `scenario-virtualization-pages.spec.ts` | Logic update | Refactor navigation and verification methods |

---

### Phase 3: MCP Validation (Test Executor)

Follow `test-executor.mdc` rules. Use the Playwright MCP browser to verify the current state of the UI.

For each change item:

1. **Navigate to the affected page** using `Playwright-browser_navigate`
2. **Snapshot the accessibility tree** using `Playwright-browser_snapshot` — confirm the new UI structure
3. **Verify the change matches the summary**:
   - Find the new selector/text/element
   - Confirm the old selector/text/element is gone
   - Record the correct `data-test` attributes, roles, and text for the new state
4. **If the summary is inaccurate** (UI doesn't match the description), report the discrepancy and ask the user before proceeding
5. **Screenshot key states** for reference if needed
6. **Output**: validated selector/locator mapping for each change

| Change | Old Locator | New Locator (verified via MCP) |
|--------|------------|-------------------------------|
| Create menu item | `button:has-text("From wizard")` | `button:has-text("New VirtualMachine")` |
| Overview navigation | `goTo('/virtualization-overview')` | Navigate to VM list + click Overview tab |

---

### Phase 4: Implementation (Automation Implementer)

Follow `automation-implementer.mdc` rules. If `--dry-run` was specified, skip this phase.

Apply updates in the correct layer, working bottom-up:

#### 4a. Page Objects (selectors, navigation, element interactions)
- Update locator strings (inline or class property)
- Update navigation methods (URLs, UI click paths)
- Update verification methods (expected text, element structure)
- Follow the locator rule: inline for single-use, class property for 2+ methods

#### 4b. Step Drivers (logic, orchestration)
- Update any step driver methods that depend on changed page object behavior
- Update step descriptions in `this.step()` calls if the action description changed
- Ensure context-aware params still work with the new flow

#### 4c. Tests (assertions, skip guards)
- Update assertion expected values if labels/headings/counts changed
- Update or remove `test.skip()` guards if feature availability changed
- Update `test.step()` descriptions if they reference changed UI elements

#### 4d. STD Documents
- Update test case descriptions and step tables to reflect the new UI
- Update the Requirements Traceability Matrix if test scope changed

#### 4e. Lint and type check
```bash
npx eslint --fix <modified-files>
npx tsc --noEmit
```

---

### Phase 5: Verification (Test Executor)

Follow `test-executor.mdc` rules. If `--dry-run` was specified, skip this phase.

1. **Run affected tests** individually to verify each fix:
   ```bash
   PLAYWRIGHT_RETRIES=0 npx playwright test --config=playwright/playwright.config.ts --grep "test-name-or-id" --workers=1
   ```
2. **Run the full scope** to check for regressions:
   ```bash
   PLAYWRIGHT_RETRIES=0 npx playwright test --config=playwright/playwright.config.ts --grep "@<scope>" --workers=4
   ```
3. **If failures occur**: return to Phase 4 for that specific test, use MCP to debug
4. **Iterate** until all affected tests pass

---

### Phase 6: Summary

Output a results table:

| # | Change | Files Modified | What Changed | Test Status |
|---|--------|---------------|-------------|-------------|
| 1 | Menu item renamed | `wizard-page.ts`, `wizard-step-driver.ts` | Selector `"From wizard"` → `"New VirtualMachine"` | PASS |
| 2 | Sub-tabs removed | `overview-page.ts`, `overview-step-driver.ts`, `virt-pages.spec.ts` | Refactored navigation + verification | PASS |
| 3 | URL removed | `overview-page.ts` | Removed `/virtualization-overview` fallback | PASS |

And a summary:

| Metric | Value |
|--------|-------|
| **Changes processed** | N |
| **Files modified** | N (list) |
| **Tests affected** | N |
| **Tests passing** | N |
| **STDs updated** | N (list) |

---

## Important Rules

- **Always validate with MCP** before changing code — never assume the summary is 100% accurate
- **Fix in the correct layer** — selectors in page objects, logic in step drivers, assertions in tests
- **Follow all Automation Implementer rules** — page encapsulation, UI-first navigation, locator strategy, etc.
- **Do not create new tests** — this command updates existing tests. Use `/jira-task` or `/expand-tests` for new coverage.
- **Do not modify application code** — only test framework code
- **Dry run mode** — when `--dry-run` is specified, output the impact report (Phases 1-3) without making code changes
- **DO NOT commit** — the user handles git operations separately
- If a change makes a test permanently invalid (feature removed), apply `test.skip()` with a descriptive reason rather than deleting the test
