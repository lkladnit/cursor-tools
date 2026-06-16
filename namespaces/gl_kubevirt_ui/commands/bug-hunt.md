# Bug Hunt: Test-Driven UI Exploration for Bug Discovery

Replay test-mapped workflows on the live cluster via Playwright MCP to find visual, functional, and data issues. Cross-reference each finding with Jira to determine if it's already reported.

## Input

The user provides a module name after the `/bug-hunt` command:

- **Single module**: `/bug-hunt bootable-volumes`
- **Multiple modules**: `/bug-hunt templates settings`

```
/bug-hunt virtualmachines
/bug-hunt vm-detail
/bug-hunt catalog
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

Follow the `bug-hunter.mdc` rule for full instructions. Summary of phases:

---

### Phase 1: Build the Interaction Plan from Test Cases

Before touching the browser, study the module's test coverage:

1. **Get coverage baseline via kubevirt-qe MCP** (preferred — deterministic file discovery):
   - Call `get_coverage_for_feature` with the module keyword — returns all spec files, step drivers, page objects, and Jira IDs for the module
   - **Fallback**: find spec files manually using the mapping in `cnv-exploration.mdc § Test Spec Directories by Module`
2. **Find spec files** for the module (use the module→directory mapping from `cnv-exploration.mdc`)
3. **Read spec files** — extract every `test()` and `test.step()` as user workflows. If 3+ spec files, launch parallel sub-agents (one per file, `model: "fast"`) to read concurrently.
4. **Read the STD** (`playwright/docs/`) for workflow descriptions
5. **Read page objects and step drivers** to understand interactions (clicks, fills, assertions)
6. **Build an ordered Interaction Plan** — table of workflows to replay, with source test ID and key interactions

---

### Phase 2: Replay Workflows via Playwright MCP

For each workflow in the plan:

1. **Navigate** to the starting page
2. **Verify Virtualization view** is active (not core platform)
3. **Replay each step** — snapshot before/after, click, type, interact
4. **At each step, check for:**
   - **Functional**: action doesn't work, wrong navigation, form doesn't submit
   - **Visual**: broken layout, missing content, truncated text
   - **Data**: empty cells, wrong values, stale data, unexpected NO_DATA_DASH (—)
   - **Error**: console JS errors, network 4xx/5xx, error boundaries
   - **UX**: confusing flow, missing feedback, slow response, unclear errors
5. **When an issue is found**: screenshot it, snapshot the DOM, check console/network, document it

---

### Phase 3: Issue Documentation

For each issue, document:
- **Category** (Functional/Visual/Data/Error/UX)
- **Severity** (Critical/Major/Minor/Cosmetic)
- **Steps to reproduce** (numbered)
- **Expected vs Actual result**
- **Evidence** (screenshot, console errors, network failures, DOM state)

---

### Phase 4: Jira Cross-Reference (Parallel)

When 2+ issues are found, launch **one sub-agent per issue** (Task tool, `model: "fast"`) to query Jira concurrently. Each sub-agent:

1. **Searches Jira** for matching CNV UI tickets using the REST API
2. **Checks GitHub PRs** linked to matching tickets — understands if a fix exists
3. **Classifies**: Exact match / Related / Fixed but not deployed / No match (new finding)
4. **Returns**: Jira key, status, fix version, PR link, classification

All sub-agents launch in a single message for maximum parallelism.

---

### Phase 5: Bug Hunt Report

Produce a consolidated report with:
- Summary (workflows replayed, issues found, Jira matches, new findings)
- Per-issue detail table (category, severity, expected/actual, Jira match, PR, fix status)
- New findings section — issues with no existing Jira ticket (candidates for filing)
- Already reported section — issues matching existing tickets
- Recommendations (file new bugs, verify fixes, coverage gaps)

## Rules

- **Read-only** — do NOT modify code, create branches, or commit
- **Test-driven** — replay workflows from actual test cases, don't randomly click around
- **Virtualization view** — always verify you're in the Virtualization plugin, not core platform
- **Evidence-first** — every issue needs at least a screenshot + snapshot
- **Don't fix** — report issues, don't modify tests or application
- **Console + network** — always check for JS errors and failed API calls
- **Cluster state awareness** — call `get_cluster_info` (kubevirt-qe MCP) to capture cluster/CNV version for the report header. **Fallback**: note versions from the console UI footer.

## Primary Directive: CRUD + API-Level Coverage

For every module, all CRUD operations are a **mandatory** part of the replay plan:

1. **Exercise Create, Read, Update, Delete** in the UI — these are the workflows most likely to surface functional regressions
2. **After each CRUD action**, run `playwright-cli requests` + `playwright-cli request <n>` to inspect the network request
3. **Unexpected status codes, empty payloads, or UI/API response mismatches** are bug findings — document them with full network evidence
4. **Note API gaps** in the Recommendations section — CRUD operations with no matching `playwright/tests/api/` coverage are candidates for `/api-cross-check`

See `bug-hunter.mdc § CRUD + API-Level Coverage` for the full procedure.
