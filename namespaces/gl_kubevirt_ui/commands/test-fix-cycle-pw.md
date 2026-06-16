# Test Fix Cycle (Playwright): Run, Analyze, Fix, Repeat

Run a Playwright test suite by tag group, analyze failures, apply fixes or skips, and iterate until stable.

## Input

The user provides a test tag or spec path after the `/test-fix-cycle-pw` command:

- **Tag group**: `'@gating'`, `'@tier1'`, `'@tier1-templates'`, `'@catalog-it'`, `'@nonpriv'`, etc. (tags must be wrapped in single quotes)
- **Spec path**: `playwright/tests/tier1/catalog/` or a specific file
- **Optional workers**: append `--workers=N` (default: 4)
- **Optional scope**: append `--only-failing` to re-run only previously failed tests

Examples:
```
/test-fix-cycle-pw '@gating'
/test-fix-cycle-pw '@tier1' --workers=3
/test-fix-cycle-pw playwright/tests/tier1/virtualmachines/ --workers=2
/test-fix-cycle-pw '@gating' --only-failing
```

## Workflow

---

### Phase 0: Pre-flight Cluster Check

Before running any tests, verify the cluster is healthy:

1. Call `check_cluster_health` — verifies API server, CNV operator, virt-api, storage, nodes
2. If `healthy: false` → **STOP** and report the failing checks to the user. Do not proceed with a test run against an unhealthy cluster.
3. If stale test namespaces > 20 → call `cleanup_stale_namespaces` with `older_than_hours: 4`
4. **Fallback** (if MCP unavailable): proceed directly to Phase 1; cluster issues will surface as test failures

---

### Phase 1: Initial Run

1. **Build the command** based on input:
   - Tag: `npx playwright test --config=playwright/playwright.config.ts --grep "<tag>" --workers=<N> --retries=0`
   - Path: `npx playwright test --config=playwright/playwright.config.ts <path> --workers=<N> --retries=0`
2. **Always use** `PLAYWRIGHT_RETRIES=0` during the fix cycle (development mode)
3. **Save output** to `/tmp/test-fix-cycle.log` via `tee` for analysis
4. **Wait for completion** — monitor progress periodically

---

### Phase 2: Result Analysis

1. **Parse results**: extract pass/fail/skip counts and total duration
2. **List all failures** with:
   - Test name and ID
   - Spec file path
   - Error message (first meaningful line)
   - Duration (to detect timeouts vs fast failures)
3. **Classify each failure** and pick the appropriate fix action.

---

### Phase 3: Fix Cycle (iterate per failure)

For each fixable failure, execute this loop:

1. **Read the failing test** and its related step driver / page object
2. **Diagnose root cause** (selectors/timing/assertions/code bugs)
3. **Apply the fix** in the correct layer
4. **Run the individual test** to verify:
   ```bash
   PLAYWRIGHT_RETRIES=0 npx playwright test --config=playwright/playwright.config.ts --grep "ID(CNV-XXXXX)" --workers=1
   ```
5. **If still failing after 2 attempts**: apply a traceable `test.skip(...)` with reason

---

### Phase 4: Validation Run

Re-run the full suite with the same parameters as Phase 1 until stable.

---

## Important Rules

- **Development mode**: always use `PLAYWRIGHT_RETRIES=0`
- **MCP for debugging**: use Playwright browser tools to inspect live UI before guessing at selectors
- **DO NOT commit** — user handles git operations separately

