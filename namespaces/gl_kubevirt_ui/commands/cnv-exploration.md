# CNV Exploration: UI Coverage Discovery

Explore a UI module on the live cluster via Playwright MCP, identify untested features, and cross-reference Jira tickets for test coverage gaps.

## Input

The user provides one or more module names after the `/cnv-exploration` command:

- **Single module**: `/cnv-exploration bootable-volumes`
- **Multiple modules**: `/cnv-exploration bootable-volumes checkups`

### Options

| Option | Effect |
|--------|--------|
| *(none)* | **Read-only** — produce a gap report without modifying any code |
| `--implement` | After the gap report, implement tests for the highest-priority untested Jira tickets found |

Examples:
```
/cnv-exploration bootable-volumes
/cnv-exploration storage-migration --implement
/cnv-exploration checkups settings --implement
```

### Available Modules

| Module | UI area |
|--------|---------|
| `virtualmachines` | VM list, tree view, overview tab, filters, bulk actions |
| `vm-detail` | VM detail page tabs (overview, config, events, console, snapshots, disks, network) |
| `catalog` | Template and instance-type VM creation wizard |
| `templates` | Template list, detail, boot source management |
| `bootable-volumes` | Bootable volume list, upload, clone, detail |
| `instance-types` | Cluster/user instance types, YAML, detail |
| `networking` | Virtual machine networks, NADs, UDNs, policies, services, routes |
| `migration-policies` | Migration policy list, create form, detail |
| `checkups` | Network latency, storage, self-validation checkups |
| `settings` | Virtualization settings, cluster config |
| `overview` | Virtualization overview dashboard, widgets, health, top consumers |
| `storage-migration` | Storage migration plans list, migration wizard |

## Workflow

Follow the `cnv-exploration.mdc` rule for full instructions. Summary of phases:

---

### Phase 1: UI Discovery (Playwright MCP)

For each requested module:

1. **Navigate to the module page** using Playwright MCP browser tools
2. **Verify the Virtualization view is active** — confirm the sidebar shows the "Virtualization" heading (not core OpenShift platform). Some modules (Templates, Networking, Storage) exist in both views.
3. **Snapshot the accessibility tree** — document all interactive elements, tabs, buttons, widgets, forms, `data-test` and `data-test-id` attributes
4. **Explore sub-pages and tabs** — click through each tab, open action menus, open modals/forms
5. **Build a Feature Map** listing all discovered features, user workflows, and testable selectors

---

### Phase 2: Test Coverage Analysis

1. **Query coverage via kubevirt-qe MCP** (preferred — deterministic structured results):
   - Call `get_coverage_for_feature` with the module keyword — returns spec files, step drivers, page objects, Jira IDs, and step driver usage data
   - Call `get_tier_distribution` for overall test balance context
   - **Fallback** (if MCP unavailable): search manually with `rg "<module>" playwright/tests/ --type ts -l`
2. **Read relevant spec files** to understand current coverage depth (use the file list from step 1)
3. **Build a Coverage Map** — mark each discovered feature as Tested / Partial / Untested

---

### Phase 3: Jira Cross-Reference

1. **Query Jira** for matching CNV UI tickets using the search API (`/rest/api/3/search/jql`)
2. **Run two queries**: actionable tickets (Verified/ON_QA/Closed) and in-flight (In Progress/Code Review)
3. **Cross-reference** each ticket against existing test coverage
4. **Classify** as: Untested / Partially tested / Covered / In-flight / Not testable via UI

---

### Phase 4: Gap Report

Produce a consolidated report with:
- Executive summary (features discovered, coverage %, gaps found)
- Untested features table
- Jira tickets needing test coverage table
- Recommended next steps (quick wins, new spec files, framework gaps)

---

### Phase 5: Implementation Planning (only with `--implement`) — CNV Explorer

The CNV Explorer prepares a detailed plan but does **not** write code. After user approval, the Automation Implementer takes over.

1. **Prioritize** — select up to 3 untested Jira tickets from the gap report (prefer Verified/Closed bugs with merged PRs, then stories with clear UI changes)

2. **Route each ticket — Expand vs. New** (deterministic via MCP):
   - Call `find_tests_by_jira` with the ticket ID — if `found: true`, use returned spec files → **Expand**
   - Call `get_coverage_for_feature` with feature keyword — if `totalTests > 0`, use returned spec files → **Expand**
   - If both return zero results → **New**
   - **Fallback** (if MCP unavailable): use manual grep and apply these rules:

   | Condition | Route |
   |-----------|-------|
   | Existing `test()` in a spec file covers the feature → can absorb | **Expand** — add `test.step()` blocks |
   | Existing spec file covers the area but no single test fits | **Expand** — add new `test()` in existing `test.describe` |
   | No existing spec or test covers the feature | **New** — create new spec file + STD |

3. **Determine tier placement** (same criteria as `qa-architect.mdc`):

   | Tier | Criteria |
   |------|----------|
   | **Gating** | No resource creation, < 2 min, smoke checks, parallelizable |
   | **Tier1** | Creates 1–2 VMs, < 6 min, CRUD workflows, isolated namespaces |
   | **Tier2** | Multi-resource setups, < 6 min, complex dependencies |

   Jira labels (`TIER-1`, `gating`) override default heuristics.

4. **Present the plan** with route + tier + framework gaps for each ticket — **wait for user approval**

5. **Create a branch** — `<git-user>/cnv-exploration-<module>-tests`

---

### Phase 6: Implementation — Automation Implementer

After user approval, the **Automation Implementer** (`automation-implementer.mdc`) takes over and implements all code changes based on the plan from Phase 5.

- **Expand-routed**: validate locators via MCP → add PO/SD methods → add `test.step()` or `test()` → update existing STD
- **New-routed**: QA Architect gap analysis → PO methods → SD wrappers → new spec file (in correct tier dir) → new STD
- Run lint and type checks on all changed files
- Produce implementation summary with ticket, route, tier, spec file, files changed, status

## Rules

- Without `--implement`: **read-only** — do not modify code, create branches, or commit
- With `--implement`: the **CNV Explorer** handles discovery, analysis, routing, tier placement, and plan presentation (Phases 1–5). The **Automation Implementer** handles all code changes (Phase 6). Each agent stays in its domain.
- **Expand before create** — always check if an existing test or STD can absorb the validation before creating new files
- Use MCP snapshots (not screenshots) for element discovery and locator validation
- Cross-reference every feature with existing tests before classifying as untested
- URL-encode JQL queries via `python3 -c "import urllib.parse; ..."`
- Focus on actionable tickets (Verified, ON_QA, Closed) — these have merged PRs and can be tested
- When implementing, present the prioritized ticket list with route + tier to the user for approval before switching to the Automation Implementer

## Primary Directive: CRUD + API-Level Coverage

For every module, exploring full CRUD operations is **mandatory**, not optional. For each resource type in the module:

1. **Exercise Create, Read, Update, Delete** end-to-end in the UI
2. **Capture the network request for each operation** using `playwright-cli requests` + `playwright-cli request <n>`
3. **Record the endpoint pattern and status code** in the Feature Map under a `### CRUD — <Resource>` section
4. **Flag any API gaps** — CRUD operations with UI coverage but no matching test in `playwright/tests/api/` are candidates for `/api-cross-check`

See `cnv-exploration.mdc § CRUD + API-Level Coverage` for the full procedure.
