# QE Dev: General QE Test Development

A general-purpose test development command. Takes any free-form prompt describing a QE task and routes it through the full agent stack — planning first, then implementation — using every available role, MCP tool, and framework convention.

## Input

```
/qe-dev <free-form prompt>
```

The prompt can describe anything test-development related:

- "add coverage for snapshot restore error state"
- "the bootable volumes table is showing stale data after clone — add a regression test"
- "our tier1 catalog tests are flaky when the cluster is slow, investigate and stabilize"
- "CNV-91234 is marked Done — write the tests"
- "we need visual regression coverage for the migration policies page"
- "clean up the networking fixture — too many unused imports"
- "extract the repeated VM creation setup from 3 tier1 specs into a shared helper"

No specific format is required. The command interprets intent, assembles a plan, confirms it, then implements.

---

## Phase 0: Intent Classification

Read the prompt and classify the intent into one or more of the following **work types**. A single prompt can contain multiple work types.

| Work Type | Signals in prompt | Primary roles | Key MCP tools |
|-----------|-------------------|---------------|---------------|
| **New test** | "add test", "write test", "CNV-XXXXX", "add coverage", "regression test for" | BA → QA Architect → Implementer → Reviewer | `get_ticket`, `find_tests_by_jira`, `get_coverage_for_feature`, `scaffold_test` |
| **Expand existing test** | "add validation", "add step", "extend", "missing assertion" | BA → QA Architect → Implementer → Reviewer | `find_tests_by_jira`, `get_class_surface`, `lint_spec_file` |
| **Fix/stabilize test** | "flaky", "failing", "broken", "investigate", "fix" | Test Executor → Implementer → Reviewer | `get_failure_summary`, `classify_failures`, `get_reproduce_command` |
| **Visual regression** | "visual", "screenshot", "pixel", "layout", "baseline" | Visual Regression Handler | `get_coverage_for_feature`, `get_selector_map` |
| **Code cleanup** | "clean up", "remove unused", "dead code", "unused imports", "extract", "refactor" | Code Cleanup → Reviewer | `get_orphan_page_object_methods`, `lint_spec_file`, `check_api_ui_parity` |
| **Framework / infra** | "fixture", "page object", "helper", "factory", "config", "env var" | QA Architect → Implementer → Reviewer | `get_fixture_api`, `get_base_patterns`, `get_class_surface` |
| **Exploration** | "explore", "discover", "what's untested", "coverage gap" | CNV Explorer | `get_coverage_for_feature`, `get_tier_distribution` |
| **Debugging** | "debug", "trace", "reproduce", "root cause", "why is X failing" | Test Executor | `classify_failures`, `get_reproduce_command`, `get_allure_failures` |
| **Live UI validation** | "validate on cluster", "does this work", "check if X is visible" | MCP Tester | Playwright MCP / playwright-cli |

For each detected work type, note:
- **Affected feature area** (derived from the prompt)
- **Affected files** (spec, page object, fixture, STD) — to be confirmed via MCP in Phase 1
- **Roles needed** (in execution order)
- **Whether a branch is needed** (yes for any code change)

---

## Phase 1: Context Gathering

Run all context queries in parallel before planning. Use `kubevirt-ui-mcp` tools — never read files directly unless MCP returns no results.

### 1.1 Existing coverage
```
get_coverage_for_feature(feature: <keyword from prompt>)
find_tests_by_jira(ticket_id: <ticket ID if present in prompt>)
search_tests(query: <keyword from prompt>)
```

### 1.2 Framework surface for affected area
```
get_class_surface(<PageObject class name>) — for each relevant page object
get_selector_map(<PageObject class name>) — for affected page objects
get_fixture_map() — to identify the correct per-folder fixture
get_fixture_api() — if fixture changes are needed
```

### 1.3 Ticket data (if a Jira key is in the prompt)
```
get_ticket(key: <CNV-XXXXX>)
```
If the ticket is not in the cache, fall back to the Jira REST API:
```bash
curl -s "https://redhat.atlassian.net/rest/api/3/issue/{TICKET_KEY}" | python3 -c "
import sys, json
data = json.load(sys.stdin)
fields = data.get('fields', {})
print(f'Key: {data[\"key\"]}')
print(f'Summary: {fields[\"summary\"]}')
print(f'Status: {fields[\"status\"][\"name\"]}')
print(f'Description: {str(fields.get(\"description\", \"\"))[:500]}')
"
```

### 1.4 Framework health (for cleanup / refactor tasks)
```
get_orphan_page_object_methods() — if the task involves dead code
lint_spec_file(path: <affected spec>) — if the task targets a specific spec
check_api_ui_parity() — if the task adds new write operations
```

### 1.5 Cluster / CI state (for fix/debug tasks)
```
check_cluster_health()
get_failure_summary(path: <results path if available>)
classify_failures(path: <results path if available>)
```

---

## Phase 2: Planning

Produce a **structured plan** before writing a single line of code. The plan must include:

```
## QE Dev Plan

### Work Type(s)
- <type 1>: <1-line description>
- <type 2>: <1-line description>  [if multiple]

### Branch
- Name: <git-user>/<slug>
- Base: main

### Roles (in order)
1. <Role> — <what it will do>
2. <Role> — ...

### Files to change
| File | Action | Reason |
|------|--------|--------|
| playwright/tests/<tier>/<feature>.spec.ts | Create / Modify | ... |
| playwright/src/page-objects/<feature>-page.ts | Create / Modify | ... |
| playwright/src/fixtures/<feature>-fixture.ts | Modify | ... |
| playwright/docs/<tier>/<feature>.md | Create / Modify | ... |

### Test design (for new/expanded tests)
For each proposed test:
- **Title**: <functional description — no ticket IDs>
- **Tier**: Gating / Tier 1 / Tier 2
- **Tag**: `@gating` / `@tier1` / `@tier2`
- **Fixture**: <per-folder fixture to import from>
- **Pre-conditions**: <cluster state, resources needed>
- **Steps**: numbered action → assertion pairs
- **Cleanup**: what gets tracked via `cleanup.track*()`
- **`ID(CNV-XXXXX)` annotations**: which `test.step()` blocks carry regression guard IDs

### Framework gaps
| Gap | Resolution |
|-----|-----------|
| Missing PO method `X` | Add to `<class>-page.ts` |
| Missing fixture property | Extend `<fixture>.ts` |

### Risks / open questions
- <anything that needs user confirmation before implementation>
```

**Stop here and present the plan to the user.**

Ask: *"Does this plan look correct? Any adjustments before I proceed with implementation?"*

Wait for approval. Do not begin implementation until the user confirms (or says "go", "yes", "looks good", "proceed", etc.).

---

## Phase 3: Implementation

Execute the approved plan, operating as each role in turn. Apply the full rule set for each role.

### Role execution order

Follow the role sequence defined in the plan. Standard sequences by work type:

| Work type | Role sequence |
|-----------|--------------|
| New test | **QA Architect** (gaps) → **Automation Implementer** (PO + spec + STD) → **Code Reviewer** (lint + conventions) |
| Expand test | **QA Architect** (routing) → **Automation Implementer** (expand spec + STD) → **Code Reviewer** |
| Fix/stabilize | **Test Executor** (reproduce + diagnose) → **Automation Implementer** (fix) → **Test Executor** (verify) |
| Visual regression | **Visual Regression Handler** (mock → spec → baseline) |
| Code cleanup | **Code Cleanup** (analyze + apply + validate) → **Code Reviewer** |
| Framework / infra | **QA Architect** (design) → **Automation Implementer** (implement) → **Code Reviewer** |
| Exploration | **CNV Explorer** (UI exploration + gap report) |
| Debugging | **Test Executor** (reproduce + diagnose + MCP inspect) → **Automation Implementer** (fix) |
| Live validation | **MCP Tester** (playwright-cli session + screenshots + report) |

### Per-role rules

Each role must read and follow its full rule file before acting:
- QA Architect → `.cursor/rules/qa-architect.mdc`
- Business Analyst → `.cursor/rules/business-analyst.mdc`
- Automation Implementer → `.cursor/rules/automation-implementer.mdc`
- Code Reviewer → `.cursor/rules/code-reviewer.mdc`
- Test Executor → `.cursor/rules/test-executor.mdc`
- Infrastructure Handler → `.cursor/rules/infrastructure-handler.mdc`
- Code Cleanup → `.cursor/rules/code-cleanup.mdc`
- CNV Explorer → `.cursor/rules/cnv-exploration.mdc`
- MCP Tester → `.cursor/rules/mcp-tester.mdc`
- Git Handler → `.cursor/rules/git-handler.mdc`
- Visual Regression Handler → `.cursor/rules/visual-regression-handler.mdc`

### Implementation checklist (Automation Implementer)

Before considering implementation complete, verify all of the following:

- [ ] All new/modified files pass `npx tsc --noEmit`
- [ ] All new/modified files pass `npm run lint:fix`
- [ ] `lint_spec_file` run on every new/modified `.spec.ts` — zero blockers
- [ ] `invalidate_cache` called after file changes
- [ ] Every new spec has a matching STD entry (or the existing STD is updated)
- [ ] `validate_std_coverage` run — no untracked Jira IDs
- [ ] All new K8s resources use `pw-` prefix via `generateRandom*` helpers
- [ ] All new resources registered with `cleanup.track*()`
- [ ] No hardcoded timeouts — `TestTimeouts.*` constants used throughout
- [ ] No `page.*` calls in spec files — all interactions via page object methods
- [ ] Tests run and pass at least once with `PLAYWRIGHT_RETRIES=0`

### Branch management

- Create a branch before any code changes: `<git-user>/<slug>`
- Resolve git username: `git config user.email | cut -d@ -f1`
- Branch naming:
  - Single Jira ticket: `<git-user>/<cnv-xxxxx-lowercase>-test`
  - Multiple tickets: `<git-user>/test-automation-<first-ticket-lowercase>`
  - No ticket: `<git-user>/qe-dev-<feature-slug>`
- **Never commit to `main`**
- **Never push** unless the user explicitly requests it

---

## Phase 4: Review & Summary

### Code Reviewer pass

Follow `.cursor/rules/code-reviewer.mdc`. Run on all changed files:
- Page encapsulation policy (no `page.*` in specs)
- Navigation policy (UI-first, `*ViaUI()` methods)
- Functionality-first test naming (no `ID(CNV-XXXXX)` in `test()` titles)
- Selector strategy (`data-test` preferred)
- Allure metadata completeness
- Cleanup tracking completeness

### Final summary

Output a results table:

| Item | Details |
|------|---------|
| **Branch** | `<branch-name>` |
| **Work type(s)** | <list> |
| **Files changed** | <count> — list of paths |
| **Tests created** | <count> — names and tiers |
| **Tests expanded** | <count> — names and what was added |
| **Tests fixed** | <count> — names and root cause |
| **Framework changes** | New PO methods, fixture changes, factory additions |
| **STDs created/updated** | File paths |
| **Lint** | ✅ Pass / ⚠️ warnings |
| **Type check** | ✅ Pass |
| **Test run** | ✅ Pass / ❌ Fail (with details) / ⏭️ Skipped (with reason) |
| **Known issues / TODOs** | Any blockers or deferred items |

Inform the user the branch is ready for review. Remind them:
- Run `git log --oneline` to see all changes
- Create a PR with `gh pr create` when satisfied
- Any TODOs or skipped items are listed in the table above

---

## Important Rules

- **Plan before code** — always present the plan and wait for approval before implementing
- **MCP-first** — use `kubevirt-ui-mcp` tools before reading any file in `playwright/src/`
- **Expand before create** — check for existing tests/STDs that can absorb new coverage before creating new files
- **Functionality-first naming** — test titles describe what the system does, not which ticket introduced it
- **No commits, no pushes** — unless the user explicitly requests it
- **No `page.*` in specs** — all interactions through page object methods
- **No hardcoded timeouts** — `TestTimeouts.*` only
- **`pw-` prefix on all resources** — via `generateRandom*` helpers
- **Lint and type-check after every change** — never leave a broken build
- **One role at a time** — complete each role's work before switching; state which role is active
