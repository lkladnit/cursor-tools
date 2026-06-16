# Jira Task: End-to-End Test Implementation

Orchestrate the full test implementation workflow for one or more Jira tasks — from exploration through implementation — stopping before commit and PR creation. All work is done on a new branch.

## Input

The user provides one or more Jira task IDs after the `/jira-task` command.

- **Single ticket**: `/jira-task CNV-78882`
- **Multiple tickets** (comma-separated): `/jira-task CNV-78882, CNV-83178, CNV-82506`
- **Multiple tickets** (space-separated): `/jira-task CNV-78882 CNV-83178`
- **Pre-validated**: `/jira-task CNV-78882 --validated`

All Jira keys provided are parsed and processed together in a single workflow.

### Options

| Option | Effect |
|--------|--------|
| *(none)* | Full workflow: Jira fetch → PR analysis → MCP exploration → implementation |
| `--validated` | Load pre-validated data from `playwright/mcp-validations/<TICKET>/` (produced by `/mcp-validate`). Skips live MCP exploration in Phase 1 and Phase 2 — uses pre-discovered selectors, STD draft, and validation screenshots instead. |
| `--scaffold` | **New framework test basis only** — produce a fully scaffolded but unannotated spec file + STD + page object skeleton. No test execution, no recording, no `ID(CNV-XXXXX)` step assertions yet. Intended as the starting point for a developer to extend with step implementations. Stops after Phase 3 (implementation scaffold). |
| `--explore` | **Live exploration only — no framework output** — replay the ticket's feature workflow via `playwright-cli`, record the full session (video + trace), inspect network requests, and produce a structured exploration report. No spec files, page objects, or STDs are created. Stops after the exploration; the recording and report are written to `playwright/mcp-validations/<TICKET>/explore/`. |

## Workflow

Execute these phases sequentially, operating as each agent role per the orchestrator rules.

---

### `--scaffold` Workflow (abbreviated)

When `--scaffold` is provided, run only **Phase 0 → Phase 1 (scenarios only) → Phase 2 (gap analysis) → Phase 3 (scaffold only)** and then stop.

**Phase 3 scaffold mode** differs from the standard Phase 3:
1. Use `scaffold_test`, `scaffold_page_object`, and `scaffold_std` to generate all boilerplate files
2. Fill in the `test.describe` name, Allure metadata, and import wiring
3. Leave individual `test()` blocks as **empty stubs** with a `// TODO: implement` comment and a `test.skip()` guard — do not write step implementations
4. Leave page object methods as stubs (`async methodName() { /* TODO */ }`) — declare the method signature and locator property, leave the body empty
5. Run `npx tsc --noEmit` to confirm the skeleton compiles cleanly
6. **Do NOT run the tests** — they are stubs
7. Output a scaffold summary: files created, class names, method stubs, and the `ID(CNV-XXXXX)` annotations to fill in

The result is a compilable, lint-passing file set ready for a developer to flesh out without any architectural decisions remaining.

---

### `--explore` Workflow (browser-only, no framework output)

When `--explore` is provided, skip Phases 0, 1.5, 2, 3, and 4 entirely. Run only:

**Step 1 — Ticket fetch** (same as Phase 1 standard workflow steps 1–4): fetch Jira data and linked PRs to understand what the ticket changes in the UI.

**Step 2 — Session setup**:
```bash
playwright-cli --version 2>/dev/null && echo ok || echo unavailable
playwright-cli state-load playwright/mcp-validations/.auth/openshift-state.json
playwright-cli resize 1920 1080
mkdir -p playwright/mcp-validations/<TICKET>/explore
playwright-cli video-start playwright/mcp-validations/<TICKET>/explore/session.webm
playwright-cli tracing-start
```
If `openshift-state.json` is missing, log in manually and save it first.

**Step 3 — Replay the feature workflow**:
- Navigate to each relevant page using the URLs from the ticket/PR analysis
- Perform each CRUD operation the ticket introduces or modifies
- After each operation: `playwright-cli requests` + `playwright-cli request <n>` to capture the API call (URL, method, status, request/response body)
- Take a screenshot at each significant state: `playwright-cli screenshot playwright/mcp-validations/<TICKET>/explore/<step-N>-<description>.png`
- For each CRUD operation, record a separate video chapter:
  ```bash
  playwright-cli video-chapter "Create <resource>"
  # ... perform the operation ...
  playwright-cli video-chapter "Verify <resource> in list"
  ```
- Capture console errors throughout: `playwright-cli console error`

**Step 4 — Session teardown**:
```bash
playwright-cli tracing-stop playwright/mcp-validations/<TICKET>/explore/trace.zip
playwright-cli video-stop
playwright-cli close
```

**Step 5 — Write the exploration report** to `playwright/mcp-validations/<TICKET>/explore/exploration-report.md`:

```markdown
# Exploration Report: <TICKET>

## Ticket Summary
- **Key**: CNV-XXXXX
- **Summary**: <summary>
- **Status**: <status>
- **Linked PRs**: <list>

## Workflows Explored

### Workflow 1: <action> (e.g. "Create migration policy")
- **URL**: <starting URL>
- **Steps**:
  1. <step description> → screenshot: `step-1-<desc>.png`
  2. ...
- **Network Requests**:
  | # | Method | Endpoint | Status | Notes |
  |---|--------|----------|--------|-------|
  | 1 | POST | /apis/.../migrationpolicies | 201 | Body: {...} |
- **Console errors**: <none / list>
- **Result**: <Pass / Fail / Partial — describe what worked and what didn't>

### Workflow 2: ...

## CRUD Coverage Summary

| Operation | Endpoint | Status | Request Body Fields | Response Shape |
|-----------|----------|--------|---------------------|----------------|
| Create    | POST ... | 201    | name, spec.selectors | metadata, spec |
| Read      | GET  ... | 200    | —                   | items[]        |
| Update    | PATCH ... | 200   | spec.bandwidth      | metadata, spec |
| Delete    | DELETE ... | 200  | —                   | {}             |

## Automation Notes
- Selectors found: `[data-test="..."]`, `[data-test-id="..."]`
- Potential assertions: <list>
- Framework gaps: <missing PO methods, missing API test endpoints>

## Recordings
- Video: `session.webm` (chapters: <list>)
- Trace: `trace.zip` (open with `npx playwright show-trace`)
- Screenshots: `step-N-*.png`
```

**Step 6** — Print the report path and inform the user they can:
- Review the exploration at `playwright/mcp-validations/<TICKET>/explore/`
- Use `/jira-task <TICKET> --validated` to implement the framework test using this data
- Use `/jira-task <TICKET> --scaffold` to generate the file skeleton without step implementations

**No spec files, page objects, STDs, or branches are created** in `--explore` mode.

---

### Phase 0: Branch Setup

1. Fetch and rebase on `origin/main`
2. Resolve the current git username from the email prefix:
   ```bash
   GIT_USER=$(git config user.email | cut -d@ -f1)
   ```
3. Create a new branch following the naming convention:
   - Single ticket: `<git-user>/<jira-key-lowercase>-test` (e.g., `bmaio/cnv-78882-test`)
   - Multiple tickets: `<git-user>/test-automation-<first-jira-key-lowercase>` (e.g., `bmaio/test-automation-cnv-78882`)
4. Confirm the branch is clean and ready

---

### Phase 1: Business Analyst — Exploration & Scenario Design

Follow `business-analyst.mdc` rules.

#### With `--validated` flag

When `--validated` is specified, **for each ticket**, check if a validation report exists at `playwright/mcp-validations/<TICKET>/validation-report.md`. If found:

1. **Read the validation report** — extract ticket summary, validated steps, selectors discovered, issues found, and automation notes
2. **Read the STD draft** at `playwright/mcp-validations/<TICKET>/std-draft.md` — use as the basis for STD creation/updates
3. **Review validation screenshots** at `playwright/mcp-validations/<TICKET>/screenshots/` — use as visual context for scenario design
4. **Skip Jira API fetch** — the validation report already contains ticket metadata
5. **Skip PR exploration** — the validation report already captures selectors and UI changes
6. **Design scenarios from validated steps** — map each validated step to StepDriver methods, using the pre-discovered selectors from the report
7. **Use the STD draft** as the starting point for STD documents — adapt rather than create from scratch

If the validation report does NOT exist for a ticket, fall back to the standard Phase 1 workflow below.

#### Standard workflow (no `--validated` or validation data not found)

**For each Jira ticket** provided in the input:

1. **Fetch the Jira ticket from the REST API** (MANDATORY — never skip this step, never rely on user-provided summaries or cached data):
   ```bash
   curl -s "https://redhat.atlassian.net/rest/api/3/issue/{TICKET_KEY}" | python3 -c "
   import sys, json
   data = json.load(sys.stdin)
   fields = data.get('fields', {})
   print(f'Key: {data.get(\"key\")}')
   print(f'Summary: {fields.get(\"summary\")}')
   print(f'Type: {fields.get(\"issuetype\", {}).get(\"name\")}')
   print(f'Status: {fields.get(\"status\", {}).get(\"name\")}')
   print(f'Priority: {fields.get(\"priority\", {}).get(\"name\")}')
   print(f'Labels: {fields.get(\"labels\", [])}')
   print(f'Components: {[c.get(\"name\") for c in fields.get(\"components\", [])]}')
   print(f'Fix Versions: {[v.get(\"name\") for v in fields.get(\"fixVersions\", [])]}')
   print(f'Parent: {fields.get(\"parent\", {}).get(\"key\", \"N/A\")}')
   subtasks = fields.get('subtasks', [])
   print(f'Subtasks ({len(subtasks)}): {[s.get(\"key\") for s in subtasks]}')
   print(f'Description: {fields.get(\"description\", \"N/A\")[:500]}')
   "
   ```
2. **Extract key fields**: summary, type, status, labels, components, fix versions, description, parent, subtasks
3. **Fetch subtasks** (if any) to understand the full scope — each subtask must also be fetched from the API
4. **Explore attached PRs / GitHub links** — fetch remote links from the Jira ticket to find implementation PRs:
   ```bash
   curl -s "https://redhat.atlassian.net/rest/api/3/issue/{TICKET_KEY}/remotelink" | python3 -c "
   import sys, json
   links = json.load(sys.stdin)
   for link in links:
       obj = link.get('object', {})
       url = obj.get('url', '')
       title = obj.get('title', '')
       if 'github.com' in url or 'pull' in url or 'merge_request' in url:
           print(f'PR: {title} — {url}')
   "
   ```
   For each PR found:
   - Use `gh` CLI or `WebFetch` to read the PR description and changed files list
   - Identify new UI components, actions, selectors (`data-test`, `data-test-id`), routes, or API endpoints introduced by the PR
   - Note any new `data-test-id` values — these become locators for the test framework
   - This informs scenario design, locator strategy, and gap analysis in later phases
5. **Search the codebase** for existing test references:
   - Call `find_tests_by_jira` with the ticket ID — returns spec files, tier, test names (structured, deterministic)
   - Call `get_coverage_for_feature` with a feature keyword derived from the ticket summary — returns spec files, step drivers, page objects, all Jira IDs in that area
   - **Fallback** (if kubevirt-qe MCP unavailable): `rg "CNV-XXXXX" playwright/tests/ playwright/docs/`
6. **Design test scenarios** using the BA scenario template — map steps to existing StepDriver methods
7. **Determine tier placement** (gating vs tier1 vs tier2) based on complexity and resource needs

After processing all tickets:

8. **Output**: A consolidated scenario document listing all proposed test cases across all tickets, with steps, assertions, tags, and cleanup. Group scenarios by ticket for traceability.

---

### Phase 1.5: Routing Decision — Expand vs. New

Before proceeding to Phase 2, classify each proposed test case from Phase 1 using the kubevirt-qe MCP for deterministic routing:

1. **Query coverage via MCP** (preferred — produces deterministic routing):
   - Call `find_tests_by_jira` with the ticket ID
   - Call `get_coverage_for_feature` with the feature keyword from the ticket summary
   - **Decision tree** (apply in order):
     1. If `find_tests_by_jira` returns `found: true` → use the returned spec files as expansion targets → **Expand**
     2. If `get_coverage_for_feature` returns `totalTests > 0` → use the returned spec files as expansion targets → **Expand**
     3. If both return zero results → **New**
   - **Fallback** (if MCP unavailable):
     ```bash
     rg "CNV-XXXXX" playwright/tests/ playwright/docs/
     rg "<feature-keyword>" playwright/tests/ --type ts -l
     ```
2. **For each proposed test case**, determine:

| Condition | Action |
|-----------|--------|
| An existing `test()` in the same spec file covers the same feature and can absorb the new validation | **Expand** — add `test.step()` blocks to the existing test, append to the existing STD |
| An existing spec file covers the same feature area but no single test fits | **Expand** — add a new `test()` inside the existing `test.describe`, append to the existing STD |
| No existing spec file or test covers this feature area | **New** — create a new spec file and a new STD document (Phase 2 + Phase 3 below) |

3. **For test cases routed to Expand**: add validations to existing tests, update existing STDs, validate with MCP, run and verify.
4. **For test cases routed to New**: continue to Phase 2 below.
5. **Mixed scenarios are expected** — some test cases from a ticket may expand existing tests while others require new spec files. Both paths can run in the same workflow.

---

### Phase 2: QA Architect — Framework Gap Analysis

Follow `qa-architect.mdc` rules. This phase applies only to test cases routed as **New** in Phase 1.5 (expand-routed cases are handled inline).

1. **Evaluate each scenario** from Phase 1 against existing framework components
2. **Identify reusable components**: existing StepDriver methods, PageObject methods, data factories
3. **Identify gaps**: missing page object methods (with suggested locators), missing step driver wrappers, missing data factories
4. **Validate locators via MCP** (Playwright browser) when possible — navigate to the relevant pages and inspect element structure
   - **With `--validated`**: Skip live MCP locator validation — use the selectors from the validation report's "Selectors Discovered" table instead. These have already been verified against the live UI.
5. **Confirm tier placement** based on technical constraints (duration, parallelism, CI budget)
6. **Output**: Framework gap report with reusable components, missing components, and new component designs

---

### Phase 3: Automation Implementer — Implementation

Follow `automation-implementer.mdc` rules. This phase applies only to test cases routed as **New** in Phase 1.5.

1. **Implement framework gaps** identified in Phase 2:
   - New page object methods (inline locators for single-use, class properties for 2+ use)
   - New step driver wrappers (context-aware params, auto-store on create)
   - New data factories (if needed)
   - Register any new StepDrivers in `scenario-test-fixture.ts`
   - When creating new files, use the kubevirt-qe MCP scaffolders (`scaffold_page_object`, `scaffold_step_driver`) to generate boilerplate — then customize. **Fallback**: copy from existing files.
2. **Create new STD documents** (only for test cases that don't fit any existing STD):
   - **With `--validated`**: Use the STD draft from `playwright/mcp-validations/<TICKET>/std-draft.md` as the starting point — adapt format, numbering, and content to match project conventions
   - **Without `--validated`**: Use `scaffold_std` to generate the initial document structure. **Fallback**: copy the STD template from `business-analyst.mdc`.
   - Gating tests → `playwright/docs/gating/<feature>.md`
   - Tier 1 tests → `playwright/docs/tier1/<feature>.md`
   - Update `playwright/docs/README.md` index when new documents are created
3. **Implement test spec files** (use `scaffold_test` for boilerplate, then customize):
   - Follow naming conventions: `ID(CNV-XXXXX) Descriptive name`
   - Use `utils.withAllure({ suite: '...', feature: 'Gating'|'Tier1', tags: [...] })`
   - Consolidate related validations into a single `test()` with `test.step()` blocks
   - Use `generateTestNamespace()` for resource-creating tests
   - Register cleanup with `cleanup.track*()`
   - Add `test.skip()` guards for optional prerequisites
4. **Run lint and type checks**:
   ```bash
   npx eslint --fix <new-files>
   npx tsc --noEmit
   ```
5. **Run the new tests** to verify they pass:
   ```bash
   npx playwright test --config=playwright/playwright.config.ts --grep "CNV-XXXXX" --workers=1 --retries=0
   ```
6. **Fix any failures** — iterate until tests pass or document functional blockers
7. **Post-implementation verification** (kubevirt-qe MCP):
   - Call `invalidate_cache` to refresh the scanner
   - Call `find_tests_by_jira` for each implemented ticket — verify `found: true` (confirms `ID(CNV-XXXXX)` annotations are correct)

---

### Phase 4: Code Reviewer — Final Review

Follow `code-reviewer.mdc` rules.

1. **Review all changes** for compliance with architectural rules:
   - Page encapsulation (no `page` in specs or step drivers)
   - UI-first navigation (no direct URLs in specs)
   - Context-aware step driver params
   - Proper cleanup tracking
   - Locator strategy (inline vs class property)
   - `pw-` prefix on all resource names
2. **Verify STD documents** match the implemented tests
3. **Report any issues** and fix them

---

### Phase 5: Summary

Output a final summary table (one row per Jira ticket when multiple are provided):

| Item | Details |
|------|---------|
| **Jira Key(s)** | CNV-XXXXX, CNV-YYYYY |
| **Branch** | `<git-user>/cnv-xxxxx-test` or `<git-user>/test-automation-cnv-xxxxx` |
| **Tests Expanded** | Count and list — existing tests that received new `test.step()` blocks or validations |
| **Tests Created** | Count and list — new tests in new or existing spec files |
| **Tier** | Gating / Tier1 / Tier2 |
| **STD Updated** | File paths (existing STDs that were appended to) |
| **STD Created** | File paths (new STDs, only when no existing STD fit) |
| **Framework Changes** | New PO methods, SD methods, factories |
| **Test Results** | Pass / Fail / Skipped |
| **Known Issues** | Any blockers or TODOs |

Inform the user that all changes are ready on the branch and they can review, commit, and create a PR when satisfied.

---

## Important Rules

- **ALWAYS fetch ticket data from the Jira REST API** — never rely on user-provided summaries, cached descriptions, or assumptions about ticket content. The API call is mandatory for every ticket.
- **DO NOT commit or push** — the user will handle git operations separately
- **DO NOT create a PR** — stop after implementation and review
- Always check existing implementations before creating new components
- Use MCP (Playwright browser) for locator validation when dealing with UI elements
- If the Jira ticket has subtasks, only implement tests for subtasks that are marked as done or in progress
- If a test cannot be implemented due to missing cluster features, create the STD entry and mark it as `TODO`
- When multiple tickets are provided, process all tickets in a single branch and workflow — consolidate tests into existing spec files where possible
- **Expand before create** — always check if an existing test or STD can absorb the new validation before creating new spec files or STD documents. When existing coverage fits, add `test.step()` blocks to existing tests and append to existing STDs. Only create new files when no existing test or STD covers the feature area.

### Flag-specific rules

| Flag | Branch created? | Spec/PO/STD created? | Tests run? | Recording? | Output location |
|------|----------------|----------------------|-----------|-----------|-----------------|
| *(none)* | Yes | Yes (full impl) | Yes | No | Framework files on branch |
| `--validated` | Yes | Yes (full impl) | Yes | No | Framework files on branch |
| `--scaffold` | Yes | Yes (stubs only) | No | No | Framework stubs on branch |
| `--explore` | **No** | **No** | **No** | **Yes** (video + trace) | `playwright/mcp-validations/<TICKET>/explore/` |

- **`--scaffold`**: Never write step implementations or locator-resolution logic — leave all `test()` bodies and page object method bodies as `// TODO` stubs. The goal is a compilable skeleton, not a working test.
- **`--explore`**: Never create any file outside `playwright/mcp-validations/<TICKET>/explore/`. Never create a branch. The session video, trace, screenshots, and exploration report are the only deliverables. Always record a video with named chapters (one per CRUD operation). Always capture network requests after each mutation (POST/PUT/PATCH/DELETE).
- Flags are mutually exclusive — `--scaffold` and `--explore` cannot be combined with each other or with `--validated`.
