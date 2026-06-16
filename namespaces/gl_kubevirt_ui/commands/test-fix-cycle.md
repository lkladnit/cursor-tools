# Test Fix Cycle: Run, Analyze, Fix, Repeat

Run a test suite via `./playwright-runner.sh`, analyze failures, apply fixes or skips, and iterate until stable.

## Input

The user provides a `playwright-runner.sh` sub-command (or a spec path) after `/test-fix-cycle`:

- **Shell runner command**: any command from `./playwright-runner.sh --help`
- **Spec path**: a directory or file under `playwright/tests/`
- **Optional extra flags**: appended after the command (e.g. `--workers=N`)
- **Optional scope**: append `--only-failing` to re-run only previously failed tests

### Available runner commands

| Command | Description |
|---------|-------------|
| `test` | Run all Playwright tests |
| `test-gating` | Gating tests (project: Gating) |
| `test-tier1` | Tier1 tests (project: Tier 1) |
| `test-migrations` | Migration tests (project: Migrations) |
| `test-tag <tag>` | Run tests matching a tag (e.g. `@tier1`, `@gating`) |
| `test-nonpriv` | Non-priv UI tests (project: Non-Priv; sets `NON_PRIV=1`) |
| `test-nonpriv-api` | Non-priv API tests (project: Non-Priv API; sets `NON_PRIV=1`) |
| `test-api` | Privileged API tests browserlessly (project: API Tests) |
| `test-settings` | CNV settings tests (`@cnv-settings`, 1 worker default) |
| `test-visual` | Visual regression tests against existing baselines |
| `test-file <path>` | Run a specific test file |

Examples:
```
/test-fix-cycle test-gating
/test-fix-cycle test-tier1 --workers=4
/test-fix-cycle test-migrations
/test-fix-cycle test-file playwright/tests/tier1/virtualmachines/vm-tabs/vm-overview-lifecycle.spec.ts
/test-fix-cycle test-api
/test-fix-cycle test-nonpriv
/test-fix-cycle test-tag '@gating' --only-failing
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

1. **Build the command** using the shell runner:
   ```bash
   PLAYWRIGHT_RETRIES=0 ./playwright-runner.sh <command> [extra-flags] 2>&1 | tee /tmp/test-fix-cycle.log
   ```
   - The runner handles `NON_PRIV=1`, `SKIP_BROWSER_SETUP=1`, project selection, and config paths automatically
   - Extra flags (e.g. `--workers=3`) are passed through to Playwright
2. **Always set** `PLAYWRIGHT_RETRIES=0` during the fix cycle (development mode)
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
3. **Classify each failure**:

| Classification | Criteria | Action |
|---------------|----------|--------|
| **Selector Changed** | `Timeout waiting for selector`, element not found | Fix in page object — use MCP to find new selector |
| **Timing Issue** | Intermittent timeout, element not yet visible | Add `waitFor()`, `scrollIntoViewIfNeeded()`, increase timeout |
| **Click Intercepted** | `element intercepted by another element` | Use `dispatchEvent('click')` or `force: true` |
| **API/Auth Failure** | 401/403 errors, `system:anonymous` | Infrastructure issue — report, don't fix test |
| **Functional Regression** | Assertion fails on correct selector, UI behavior changed | Check if this is a real product change — update test or skip with note |
| **Infrastructure/Cluster** | Connection refused, cluster timeout, resource unavailable | Skip with descriptive message |
| **Test Code Bug** | Wrong assertion, incorrect destructuring, missing cleanup | Fix the test code |

---

### Phase 3: Fix Cycle (iterate per failure)

For each fixable failure, execute this loop:

1. **Read the failing test** and its related step driver / page object
2. **Diagnose root cause**:
   - For selector issues: use MCP (`Playwright-browser_snapshot`) to inspect the live page
   - For timing issues: review `waitFor` / timeout values
   - For logic bugs: read the code and fix
3. **Apply the fix** following project rules:
   - Selectors → page objects only (inline if single-use)
   - Clicks → `robustClick()` or `dispatchEvent('click')` for overlay issues
   - Timeouts → use `TestTimeouts.*` constants
   - Navigation → UI-first, URL as fallback in catch blocks
4. **Run the individual test** to verify:
   ```bash
   PLAYWRIGHT_RETRIES=0 ./playwright-runner.sh test-tag "ID(CNV-XXXXX)" --workers=1
   ```
5. **If fixed**: move to next failure
6. **If still failing after 2 attempts**: classify as unfixable and apply skip:
   ```typescript
   test.skip(true, 'Descriptive reason — what fails and what would fix it');
   ```

---

### Phase 4: Skip Policy

When a test must be skipped, follow these rules:

- **Always include a detailed reason** explaining what fails and what's needed to fix it
- **Categorize the skip**:
  - Cluster limitation: `'Requires multi-node cluster / specific operator / GPU'`
  - UI regression: `'UI element X removed/changed in CNV Y.Z — needs selector update for new UX'`
  - Functional blocker: `'Feature X not working on current cluster version'`
  - Timeout/performance: `'Test exceeds N min timeout — requires optimization of VM boot / multi-tab flow'`
- **Never skip silently** — every skip must be traceable

---

### Phase 5: Validation Run

After all fixes and skips are applied:

1. **Re-run the full suite** with the same parameters as Phase 1
2. **Verify all tests pass** (including previously passing tests — ensure no regressions)
3. **If new failures appear**: return to Phase 3 for those
4. **Repeat** until a clean run is achieved

---

### Phase 6: Summary

Output a results table:

| Test | Status | Action Taken |
|------|--------|-------------|
| ID(CNV-XXXXX) Test name | PASS | Fixed: updated selector in `page-object.ts` |
| ID(CNV-YYYYY) Test name | SKIP | Skipped: requires multi-node cluster |
| ID(CNV-ZZZZZ) Test name | PASS | No change needed |

And a summary:

| Metric | Value |
|--------|-------|
| **Tag/Path** | '@gating' |
| **Workers** | 4 |
| **Total Tests** | N |
| **Passed** | N |
| **Skipped** | N |
| **Fixed** | N (list) |
| **Newly Skipped** | N (list with reasons) |
| **Duration** | X min |
| **Runs to Stabilize** | N |

---

## Important Rules

- **Development mode**: always use `PLAYWRIGHT_RETRIES=0` during the cycle
- **MCP for debugging**: use Playwright browser tools to inspect live UI before guessing at selectors
- **Fix in the right layer**: selectors in page objects, logic in step drivers, assertions in tests
- **Don't fix application bugs**: if the product is broken, skip the test with a note — don't make the test pass on broken behavior
- **Lint after fixes**: run `npx eslint --fix` on modified files
- **Type check**: run `npx tsc --noEmit` after fixes
- **Post-cycle cleanup**: after fixes are applied, call `invalidate_cache` so subsequent coverage queries reflect the updated codebase
- **DO NOT commit** — the user handles git operations separately
