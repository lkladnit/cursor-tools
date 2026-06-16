# MCP Validate: Live UI Validation with Evidence

Validate a Jira ticket's feature or bugfix on the live cluster via Playwright MCP. Produces numbered screenshots at each validation point, a structured validation report, and an STD draft for automation — all saved to a gitignored folder for optional consumption by `/jira-task --validated`.

## Input

The user provides one or more Jira task IDs after the `/mcp-validate` command:

- **Single ticket**: `/mcp-validate CNV-83937`
- **Multiple tickets**: `/mcp-validate CNV-83937, CNV-82506`

### Options

| Option | Effect |
|--------|--------|
| *(none)* | Full validation: Jira fetch → PR analysis → live UI walk-through → report + STD draft |
| `--quick` | Skip STD draft generation — only produce screenshots and validation report |
| `--revalidate` | Clear previous output for this ticket and re-run from scratch |

Examples:
```
/mcp-validate CNV-83937
/mcp-validate CNV-83937 --quick
/mcp-validate CNV-83937 --revalidate
/mcp-validate CNV-83937, CNV-82506
```

## Workflow

Follow the `mcp-tester.mdc` rule for full instructions. Summary of phases:

---

### Phase 0: Setup

1. **Fetch the Jira ticket** from the REST API (MANDATORY — never skip)
2. **Fetch linked PRs** — find the implementation PR to understand what changed
3. **Create output directory**: `playwright/mcp-validations/<TICKET>/screenshots/`
4. **Get cluster context** via kubevirt-qe MCP (`get_cluster_info`, `check_cluster_health`)
5. **Check existing test coverage** (`find_tests_by_jira`, `get_coverage_for_feature`)

If the Jira API is unreachable, ask the user for the ticket description, acceptance criteria, and PR link.

---

### Phase 1: Build Validation Plan

From the Jira ticket and PR changes, build an ordered table of validation steps:

| # | Action | Expected Result | Screenshot Name |
|---|--------|-----------------|-----------------|
| 1 | Navigate to \<page\> | Page loads with \<elements\> | `01-page-loaded.png` |
| 2 | Click \<element\> | \<expected behavior\> | `02-action-result.png` |
| ... | ... | ... | ... |

Present the plan to the user before proceeding with live validation.

---

### Phase 2: Live UI Validation (Playwright MCP)

For each step in the Validation Plan:

1. **Set viewport** to 1920×1080 (first step only)
2. **Navigate** to the target page
3. **Snapshot** the accessibility tree — discover selectors
4. **Perform the action** — click, type, fill
5. **Verify the result** — snapshot again, compare with expected
6. **Take a numbered screenshot** saved to `playwright/mcp-validations/<TICKET>/screenshots/`
7. **Record selectors** — `data-test`, `data-test-id`, roles, labels
8. **Check for errors** — console messages, network failures

For complex validations with multiple states, take sub-numbered screenshots (e.g., `03a-`, `03b-`).

---

### Phase 3: Generate Validation Report

Write `playwright/mcp-validations/<TICKET>/validation-report.md` containing:

- **Ticket summary** — key, summary, type, status, PR link
- **Cluster context** — versions for reproducibility
- **Validation results table** — step, expected, actual, status (✅/❌), screenshot link
- **Selectors discovered** — element, selector, type, usage
- **Issues found** — any bugs, UX problems, or discrepancies
- **Notes for automation** — timing, prerequisites, parallel safety

---

### Phase 4: Generate STD Draft (skip with `--quick`)

Write `playwright/mcp-validations/<TICKET>/std-draft.md`:

- If an existing STD covers this feature → generate an **append section** with continued numbering
- If no existing STD → generate a **full STD** from the project template
- Map validated steps to test case actions and expected results
- Include the Requirements Traceability Matrix entry

---

### Phase 5: Summary

Output to the user:

| Item | Details |
|------|---------|
| **Validation Result** | PASS / PARTIAL / FAIL |
| **Steps Validated** | N steps, N screenshots |
| **Selectors Discovered** | N unique selectors |
| **Issues Found** | N (list if any) |
| **STD Draft** | New / Append to \<existing\> |
| **Output Location** | `playwright/mcp-validations/<TICKET>/` |

Inform the user they can now run `/jira-task <TICKET> --validated` to implement tests using this data.

---

## Output Location

All files are written to `playwright/mcp-validations/<TICKET>/` which is gitignored. Structure:

```
playwright/mcp-validations/CNV-83937/
├── validation-report.md
├── std-draft.md
└── screenshots/
    ├── 01-initial-state.png
    ├── 02-action-performed.png
    └── ...
```

## Integration with /jira-task

After validation, run:
```
/jira-task CNV-83937 --validated
```

The `--validated` flag tells `/jira-task` to:
1. Load the validation report from `playwright/mcp-validations/CNV-83937/`
2. Use pre-discovered selectors instead of doing MCP exploration
3. Use the STD draft as the starting point for STD creation/updates
4. Reference validation screenshots for visual context during implementation

## Important Rules

- **Read-only (code)** — do NOT modify test code, page objects, step drivers, or spec files
- **Evidence-first** — every validation step MUST have a screenshot
- **Virtualization view** — always verify you're in the Virtualization plugin, not core platform
- **Viewport** — always resize to 1920×1080 before first interaction
- **Console + network** — check for JS errors and failed API calls at each step
- **Jira API fallback** — if unreachable, ask the user for ticket details before proceeding
- **DO NOT commit** — output goes to a gitignored folder only
