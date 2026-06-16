# Expand Tests: Add Validations for a Jira Task to Existing Tests

Analyze a Jira task and expand existing test coverage by adding new validations, `test.step()` blocks, or new tests that fit naturally into current spec files and test groups.

## Input

The user provides one or more Jira task IDs after the `/expand-tests` command, optionally with scope:

- **Single ticket**: `/expand-tests CNV-82213`
- **Multiple tickets** (comma-separated): `/expand-tests CNV-82213, CNV-83178`
- **Scoped to tier**: `/expand-tests CNV-82213 --tier=gating`
- **Scoped to file**: `/expand-tests CNV-82213 --file=scenario-virtualization-pages.spec.ts`
- **Dry run (no code changes)**: `/expand-tests CNV-82213 --dry-run`

## Workflow

---

### Phase 1: Jira Exploration (Business Analyst)

Follow `business-analyst.mdc` rules.

**For each Jira ticket** provided in the input:

1. **Fetch the Jira ticket from the REST API** (MANDATORY — never skip, never rely on user-provided summaries):
   ```bash
   curl -s "https://redhat.atlassian.net/rest/api/3/issue/{TICKET_KEY}" | python3 -c "
   import sys, json
   data = json.load(sys.stdin)
   fields = data.get('fields', {})
   print(f'Key: {data.get(\"key\")}')
   print(f'Summary: {fields.get(\"summary\")}')
   print(f'Type: {fields.get(\"issuetype\", {}).get(\"name\")}')
   print(f'Status: {fields.get(\"status\", {}).get(\"name\")}')
   print(f'Labels: {fields.get(\"labels\", [])}')
   print(f'Description: {fields.get(\"description\", \"N/A\")[:500]}')
   subtasks = fields.get('subtasks', [])
   print(f'Subtasks ({len(subtasks)}): {[s.get(\"key\") for s in subtasks]}')
   "
   ```
2. **Extract**: summary, description, subtasks, linked PRs, fix versions, labels
3. **Fetch subtasks** to understand the full scope of changes
4. **Identify what changed in the UI** — the Jira description and linked PRs tell you what's new or modified
5. **Output**: list of validatable behaviors introduced or changed by this ticket (grouped by Jira key when multiple tickets)

---

### Phase 2: Existing Coverage Audit (QA Architect)

Follow `qa-architect.mdc` rules.

1. **Query coverage via kubevirt-qe MCP** (preferred — deterministic structured results):
   - Call `find_tests_by_jira` with the ticket ID — returns exact spec files, tier, and test names
   - Call `get_coverage_for_feature` with a feature keyword from the ticket summary — returns all related spec files, step drivers, page objects, and Jira IDs
   - **Fallback** (if MCP unavailable):
     ```bash
     rg "CNV-XXXXX" playwright/tests/ playwright/docs/
     rg "overview|migration|widget" playwright/tests/ --type ts -l
     ```
2. **Map existing coverage**: for each related spec file from step 1, list:
   - Current test cases and what they validate
   - Which aspects of the Jira ticket are already covered
   - Which aspects are NOT covered (gaps)
3. **Identify expansion targets** — existing tests that can absorb new validations:
   - Same spec file, same `test.describe` block → add `test.step()` blocks
   - Same spec file, different concern → add a new `test()` within the describe
   - Different spec file, same tier → add a new test to the existing file
   - No existing file fits → create a new spec file (last resort)
4. **Output**: coverage gap table

| Jira Aspect | Current Coverage | Gap | Expansion Target |
|-------------|-----------------|-----|-----------------|
| Widget X renamed | `scenario-vm-management.spec.ts:L45` | None | Already covered |
| New "View all" link | Not covered | Missing | Add step to `CNV-81836` test |
| Section reorder | Not covered | Missing | New `test.step()` in overview test |

---

### Phase 3: Locator Validation (via MCP)

When the Jira ticket introduces UI changes, validate the current state:

1. **Navigate to affected pages** using Playwright MCP browser
2. **Snapshot the accessibility tree** — find actual element names, roles, data-test attributes
3. **Compare with existing selectors** in page objects — flag any that no longer match
4. **Record correct selectors** for new elements introduced by the ticket
5. **Screenshot key states** for reference

---

### Phase 4: Implementation (Automation Implementer)

Follow `automation-implementer.mdc` rules.

For each gap identified in Phase 2:

#### 4a. Expand existing test with new `test.step()`:

```typescript
// BEFORE: existing test
test('ID(CNV-XXXXX) Overview widgets', async ({ steps }) => {
  await test.step('Verify cluster status', async () => { /* existing */ });
  await test.step('Verify VM health', async () => { /* existing */ });
});

// AFTER: expanded with new validation from Jira ticket
test('ID(CNV-XXXXX) Overview widgets', async ({ steps }) => {
  await test.step('Verify cluster status', async () => { /* existing */ });
  await test.step('Verify VM health', async () => { /* existing */ });
  // NEW: added for CNV-YYYYY
  await test.step('ID(CNV-YYYYY) Verify new resource allocation section', async () => {
    const visible = await steps.virtualMachines.isResourceAllocationVisible();
    expect(visible, 'Resource allocation section should be visible').toBe(true);
  });
});
```

#### 4b. Add new test to existing describe block:

```typescript
test.describe('VM Overview (gating)', { tag: ['@gating'] }, () => {
  // ... existing tests ...

  // NEW: added for CNV-YYYYY
  test('ID(CNV-YYYYY) New feature validation', async ({ steps, utils }) => {
    utils.withAllure({ suite: 'VM Overview', feature: 'Gating', tags: ['@gating', 'cnv-yyyyy'] });
    // test body
  });
});
```

#### 4c. Add supporting page object / step driver methods if needed:

- New page object method → inline locators, `robustClick`, proper waits
- New step driver wrapper → `this.step()`, context-aware params, auto-store
- Register in `scenario-test-fixture.ts` if new step driver class

#### 4d. Consolidation rules:

- **Same Jira ticket** → consolidate into one `test()` with `test.step()` blocks
- **Related to existing test** → extend that test rather than creating a new one
- **Truly independent validation** → new `test()` in the same spec file
- **New spec file** → only if no existing file covers this feature area

---

### Phase 5: STD Update (Business Analyst)

1. **Find the canonical STD** for the affected feature area
2. **Append new test cases** following the existing numbering scheme
3. **Update the Requirements Traceability Matrix** with new Jira ID mappings
4. **Mark status**: `Automated` for implemented tests, `TODO` for planned-only

---

### Phase 6: Validation

1. **Run lint and type check**:
   ```bash
   npx eslint --fix <modified-files>
   npx tsc --noEmit
   ```
2. **Run affected tests** to verify they pass:
   ```bash
   PLAYWRIGHT_RETRIES=0 npx playwright test --config=playwright/playwright.config.ts --grep "CNV-XXXXX|CNV-YYYYY" --workers=1
   ```
3. **Run the full tag group** to verify no regressions:
   ```bash
   PLAYWRIGHT_RETRIES=0 npx playwright test --config=playwright/playwright.config.ts --grep "'@<tier>'" --workers=4
   ```
4. **Fix any failures** before completing
5. **Post-implementation verification** (kubevirt-qe MCP):
   - Call `invalidate_cache` to refresh the scanner
   - Call `find_tests_by_jira` for each ticket — verify `found: true` confirms the `ID(CNV-XXXXX)` annotations registered correctly

---

### Phase 7: Summary

Output a results table:

| Action | File | Details |
|--------|------|---------|
| **Expanded** | `scenario-vm-management.spec.ts` | Added 2 `test.step()` blocks to `ID(CNV-XXXXX)` |
| **New test** | `scenario-virtualization-pages.spec.ts` | Added `ID(CNV-YYYYY)` with 3 steps |
| **New PO method** | `overview-page.ts` | `verifyResourceAllocation()` |
| **New SD method** | `overview-step-driver.ts` | `isResourceAllocationVisible()` |
| **STD updated** | `playwright/docs/gating/virtualization-pages.md` | Added test case 015 |

And coverage summary:

| Jira Aspect | Status |
|-------------|--------|
| Widget rename | Covered (existing test updated) |
| New section | Covered (new test.step added) |
| Link navigation | Covered (new test added) |
| Edge case X | TODO (requires specific cluster config) |

---

## Important Rules

- **ALWAYS fetch ticket data from the Jira REST API** — never rely on user-provided summaries, cached descriptions, or assumptions about ticket content. The API call is mandatory for every ticket.
- **Expand first, create second** — always try to add to existing tests before creating new spec files
- **Consolidate by Jira ticket** — all validations for one ticket should live in one `test()` with `test.step()` blocks
- **Use MCP** to validate selectors against the live UI before writing page object methods
- **Follow the locator rule** — inline for single-use, class property for 2+ methods
- **Update STDs** — every new or expanded test must be reflected in the relevant STD document
- **Dry run mode** — when `--dry-run` is specified, output the plan without making code changes
- **DO NOT commit** — the user handles git operations separately
- When multiple tickets are provided, process all tickets in a single workflow — group coverage gaps and expansions by ticket for traceability
