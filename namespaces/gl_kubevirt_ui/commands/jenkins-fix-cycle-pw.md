# Jenkins Fix Cycle (Playwright): Fetch CI Failures, Analyze, Fix, Validate

Fetch test results from a Jenkins build, extract failed and quarantined tests, and fix them using a fully MCP-native workflow — from parsing through live UI diagnosis to validation.

> **CI Safe Mode**: The test framework quarantines failures as `skipped` with a `Quarantined: <reason>` message instead of hard-failing. This means Jenkins reports these as `SKIPPED` (not `FAILED`). The fix cycle must inspect **both** `FAILED` and quarantined `SKIPPED` tests to find everything that needs fixing.

> **CORE RULE — No Error Data? Reproduce Locally.**
> When Jenkins test cases have **empty** `errorDetails`, `errorStackTrace`, and `skippedMessage` (common with CI Safe Mode quarantine), **DO NOT guess at skip reasons or blindly re-apply old skips**. Instead:
>
> 1. **Determine the tier tag** from the Jenkins job name (e.g., `t1-cnv-4.22` → `@tier1`, `gating-cnv-4.22` → `@gating`)
> 2. **Run a pre-flight cluster check** (Phase 3) — a healthy cluster is **mandatory** for this path. If the cluster is unreachable, **stop and inform the user** — do not proceed with speculative skips.
> 3. **Use `get_reproduce_command`** (`kubevirt-ui-mcp`) to get the exact reproduction command, then run it with `CI_SAFE_MODE=0 PLAYWRIGHT_RETRIES=0`.
> 4. **Use the local error output** to classify and fix each failure — never the empty Jenkins fields.
> 5. After fixing, **re-run the same test** to confirm the fix. If still failing after 2 fix attempts, **then** apply `test.skip()` with the **observed** error as the reason.
>
> The agent must **never** apply `test.skip()` based on speculation — only based on error output it has actually observed (from Jenkins error fields OR local reproduction).

## Input

Provide **either** a Jenkins testReport URL **or** a console log (not both required in one invocation):

| Mode | Required | Optional |
|------|----------|----------|
| **testReport API** | Jenkins `testReport` / `testReport/api/json` URL (or build URL the agent normalises) | `--branch=<name>`, `--workers=N`, `--age=N`, `--skip-only` |
| **Console log** | `--log=<path>` | `--branch=<name>`, `--spec=<path>`, `--workers=N` |

- **`--branch`**: Git branch to checkout before fixing (feature branch or `main`). Optional for testReport; use when the fix targets code not on your current branch.
- **`--log`**: Path to a downloaded Jenkins **console** log (e.g. `.cluster-logs/t1-cnv-4.22-18.log`). Use when VPN/MCP cannot reach `testReport`, or you only saved `consoleText`. Download with `./fetch-jenkins-log.sh <jenkins-build-url>` when available.
- **`--spec`**: (console log only) Limit to one file under `playwright/tests/` (e.g. `playwright/tests/tier1/catalog/templates/template.spec.ts`).
- **`--workers=N`**: (default: 4) Parallel workers for validation runs.
- **`--age=N`**: (testReport only) Only fix tests failing for N+ consecutive builds.
- **`--skip-only`**: (testReport only) Skip all failures without fix attempts.

### Examples

```
# testReport API (preferred — MCP triage)
/jenkins-fix-cycle-pw https://jenkins-csb-cnvqe-main.dno.corp.redhat.com/job/test-kubevirt-console-t1-cnv-4.22-ocs/18/testReport/api/json
/jenkins-fix-cycle-pw https://jenkins-csb-cnvqe-main.dno.corp.redhat.com/job/test-kubevirt-console-t1-cnv-4.22-ocs/18/testReport --workers=2 --age=3
/jenkins-fix-cycle-pw https://jenkins-csb-cnvqe-main.dno.corp.redhat.com/job/test-kubevirt-console-gating-cnv-4.22-ocs/5/testReport --skip-only

# testReport + checkout branch before fixing
/jenkins-fix-cycle-pw https://jenkins-csb-cnvqe-main.dno.corp.redhat.com/job/test-kubevirt-console-t1-cnv-4.22-ocs/18/testReport --branch=lkladnit/cnv-12345-test

# Console log (no testReport URL)
/jenkins-fix-cycle-pw --log=.cluster-logs/t1-cnv-4.22-18.log
/jenkins-fix-cycle-pw --log=.cluster-logs/gating-cnv-4.22-5.log --spec=playwright/tests/gating/catalog-gating.spec.ts --workers=2
```

> **Console log vs CORE RULE:** Log mode discovers *which* specs/tests failed. If the log lacks stack traces (common with CI Safe Mode), still run **`get_reproduce_command`** + local execution with `CI_SAFE_MODE=0` before any `test.skip()` — same as empty Jenkins JSON fields.

---

## Workflow

---

### Phase -1: Branch setup (when `--branch` is set)

1. Checkout `--branch=<name>` (or create a worktree if switching away from dirty work).
2. Confirm `.env` matches the cluster used in CI (`WEB_CONSOLE_URL`, credentials).
3. `npm install` / Playwright browsers only if the branch differs from your current tree.

If `--branch` is omitted, use the current checkout.

---

### Phase 0: Discover failures

#### Mode A — testReport API (preferred)

**Use `kubevirt-ui-mcp` CI triage tools — never raw `curl` + `python3` unless MCP times out (VPN).**

1. **`parse_jenkins_report(source)`** — pass the raw URL (the tool appends `/api/json` automatically):
   - Returns structured list of test results with status, error messages, spec paths, and Jira IDs
   - If the tool errors with a connection timeout → inform the user they need to connect to VPN; do not proceed

2. **`get_failure_summary()`** — call with the same source URL:
   - Returns pass/fail/skip counts, top 5 failure signatures, and per-tier breakdown
   - Reports quarantined count (subset of skipped — real failures caught by CI Safe Mode)

3. **`merge_quarantined()`** — recover error messages hidden by CI Safe Mode:
   - Merges FAILED tests with matching `Quarantined:` SKIPPED entries into a unified failure list
   - Surfaces the original error text that CI Safe Mode suppressed; this is what you diagnose against

4. Apply `--age=N` filter now if specified: discard entries with `age < N`.

5. **Print the CI summary**:

   | Metric | Value |
   |--------|-------|
   | **Job** | `<job-name>` (extracted from URL) |
   | **Build** | `#N` |
   | **Pass / Fail / Skip** | N / N / N |
   | **Quarantined** | N (real failures hidden by CI Safe Mode) |
   | **Duration** | X min |
   | **Unique specs needing fixes** | N files |

#### Mode B — console log

Use when no testReport URL is available or MCP cannot reach Jenkins.

1. Read `--log` from `.cluster-logs/` or the path given.
2. Parse Playwright/Jenkins output for failures:
   - `✗` / failed `it` or `test` lines, `ID(CNV-XXXXX)` in titles
   - Spec paths: `playwright/tests/**/*.spec.ts` (grep log for `tests/` + `.spec.ts`)
   - Error blocks: `TimeoutError`, `locator.waitFor`, `expect(`, first stack line with `page-objects/` or `.spec.ts`
3. Infer tier tag from log filename or job name in log header (e.g. `t1-cnv-4.22` → `@tier1`).
4. If `--spec` is set, restrict to that file only.
5. Build the same failure table as Mode A (Source = `CONSOLE_LOG`); **age** unknown unless noted in log — sort by spec path.
6. If the log has **no usable error text** for a failure → mark for local reproduction (CORE RULE); do not skip from log alone.

**MCP optional in Mode B:** If VPN allows, you may still call `classify_failures` after building a minimal failure list from the log, or skip straight to Phase 3 + `get_reproduce_command` per test.

---

### Phase 1: Map Failures to Local Code + Jira Enrichment

For each failed or quarantined test case (from `merge_quarantined` **or** console log parsing):

1. **Map to local spec file**:
   - Jenkins `className` format: `tier1/catalog/templates/template.spec.ts`
   - Local path: `playwright/tests/<className>`
   - Verify the file exists — if not, warn (test may have been renamed/moved)

2. **Extract Jira IDs** — `parse_jenkins_report` already extracts `ID(CNV-XXXXX)` from test names; use those directly

3. **Enrich with Jira context** via `get_ticket("CNV-XXXXX")` (`kubevirt-ui-mcp`):
   - Returns ticket summary, status, labels, and linked kubevirt-plugin commits
   - A ticket status of `Closed` means the fix was merged upstream — the test may need an assertion update
   - A status of `Won't Fix` / `Obsolete` means the feature changed intentionally — skip with reference
   - If `get_ticket` returns nothing → call `refresh_store()` once, then retry

4. **Record the error signature and age**:
   - `FAILED` tests: use `errorStackTrace` from `parse_jenkins_report` output
   - `QUARANTINED` tests: use the recovered message from `merge_quarantined`
   - `age` = consecutive builds this test has been failing (sort descending — fix oldest first)

5. **Build the failure list** — present to user before proceeding:

   | # | Spec File | Test Name | ID | Age | Source | Error Type | Jira Status | Duration |
   |---|-----------|-----------|-----|-----|--------|------------|-------------|----------|
   | 1 | `template.spec.ts` | Create VM from catalog... | CNV-11678 | 2 | FAILED | Timeout | In Progress | 127.8s |
   | 2 | `migrations.spec.ts` | Migrations tab, live migration... | CNV-9297 | 7 | QUARANTINED | Timeout | Closed | 521.9s |

---

### Phase 2: Classify Failures via MCP

**Always use `classify_failures()` (`kubevirt-ui-mcp`) — never manually pattern-match error strings.**

> **Check the CORE RULE first.** If the failure list has empty `errorDetails`, `errorStackTrace`, AND recovered `skippedMessage`, skip this phase. Jump to Phase 3 (cluster check), then reproduce locally. Classification comes from observed error output, not empty fields.

`classify_failures` labels each failure as one of:

| Label | Meaning | Action |
|-------|---------|--------|
| `test_bug` | Wrong selector, import error, type error in test code | Fix the test or page object |
| `product_bug` | Assertion on UI element or API response that changed | Verify via live UI, then update assertion or skip |
| `infrastructure` | Timeout, network error, cluster unreachable | Report; don't fix code unless it's a hardcoded URL/timeout |
| `flaky` | Intermittent / retry pattern | Add `waitFor()`, robustify, or quarantine |

The MCP output is the authoritative classification. If `infrastructure` failures dominate, run Phase 3 cluster checks before touching any code — a broken cluster will make every test fail regardless of fixes.

---

### Phase 3: Pre-flight Cluster Check

Before any local test execution:

1. **`check_cluster_health()`** (`kubevirt-ui-mcp`) — verifies API server, CNV operator, virt-api, storage, nodes
   - If `healthy: false` → drill deeper:
     - `get_hco_status()` — operator conditions, degraded components, feature gates
     - `get_node_status()` — NotReady nodes explain resource-creation timeouts
     - `get_storage_class_info()` — missing storage class explains DV failures
   - If `infrastructure` classification dominates AND cluster is unhealthy → stop; report to user; code fixes will not help
   - If stale test namespaces > 20 → call `cleanup_stale_namespaces(older_than_hours: 4)` before running anything

2. **Fallback** (if `kubevirt-ui-mcp` unavailable): proceed; cluster issues will surface when running tests

---

### Phase 4: Fix Cycle (per failure, sorted by age descending)

#### 4a. Get the Exact Reproduction Command

**Always use `get_reproduce_command(spec_path, [test_name], [jira_id])`** (`kubevirt-ui-mcp`) — never construct the command manually. The tool returns the correct `yarn test-playwright` command with the right `--grep`. Prepend `CI_SAFE_MODE=0 PLAYWRIGHT_RETRIES=0` when running.

> **Always use `CI_SAFE_MODE=0`** — without it the quarantine wrapper converts failures to skips, hiding the real error.

#### 4b. Read Code Context via Context Proxy (never read page object files directly)

Use `kubevirt-ui-mcp` context tools in this order:

1. **`get_task_context("fix <feature> <error-type>")`** — most token-efficient start; returns only the relevant method signatures for the failure
2. **`get_selector_map("<PageObjectClass>")`** — get all current selectors for the PO involved; compare against the failing locator string from the error to spot what changed
3. **`get_class_surface("<ClassName>", "<method-keyword>")`** — filtered view of a class when you need to understand a specific method
4. **`search_methods("<keyword>")`** — cross-class keyword search when the failing locator belongs to an unknown PO
5. **`get_import_guide(["ClassName"])`** — resolve `@/` import paths before writing any fix

Only fall back to `Read` on the file directly if all context tools return no result.

#### 4c. Diagnose with playwright-cli (Selector / Assertion / Product Bug Failures)

For `test_bug` (selector changed) or `product_bug` (assertion changed), **inspect the live UI before touching any code**.

**Browser session setup — run once:**
```bash
playwright-cli --version 2>/dev/null && echo "available" || echo "unavailable"
playwright-cli state-load playwright/mcp-validations/.auth/openshift-state.json
playwright-cli resize 1920 1080
```

If `unavailable`, fall back to Playwright MCP (`Playwright-browser_navigate` + `Playwright-browser_snapshot`). Note: Playwright MCP lacks console error capture and request inspection.

**Navigate to the failing page** (URL from the spec's navigation call via `get_task_context`):
```bash
playwright-cli goto <url>
playwright-cli snapshot --depth=4          # quick orientation — reduce noise
playwright-cli snapshot <section-ref>      # zoom into the relevant area
```

**For a missing selector** (`locator.waitFor: Timeout`):
```bash
playwright-cli eval "[...document.querySelectorAll('[data-test]')].map(e=>e.getAttribute('data-test'))"
playwright-cli generate-locator <ref> --raw   # converts snapshot ref → exact Playwright locator
playwright-cli highlight <ref>                # visually confirm the right element
```

**For a failed assertion** (`expect.toBe` / `expect.toContain`):
```bash
playwright-cli eval "el => el.textContent" <ref>  # check the actual value
playwright-cli console error                       # JS errors that corrupt the value
playwright-cli requests                            # look for 4xx/5xx API responses
playwright-cli request <n>                         # inspect a specific response body
```

**For a click-interception issue** (`element intercepted`, `not visible`):
```bash
playwright-cli eval "el => el.getBoundingClientRect()" <ref>  # off-screen check
playwright-cli highlight <ref> --style="outline: 3px solid red"
```

#### 4d. Apply the Fix (Correct Layer)

- **Selector changed** → update in the **page object only** (never inline in spec)
  - Inline if used by 1 method; class property if used by 2+ methods
- **Assertion value changed** → update in the **spec** — verify new value via `playwright-cli eval`
- **Click intercepted** → use `robustClick()` or `dispatchEvent('click')` in the PO method
- **Timeout too short** → use `TestTimeouts.*` constants (look up via `get_task_context("timeout constants")`)
- **Test code bug** (TypeError, import error) → fix the spec; `get_import_guide` for correct import path
- **Flaky wait** → add `waitFor({ state: 'visible' })` before the action in the PO method

**After every spec edit**, run `lint_spec_file(path)` (`kubevirt-ui-mcp`) to catch missing IDs, raw `page` usage, and hardcoded timeouts before running the test.

#### 4e. Run and Verify

```bash
CI_SAFE_MODE=0 PLAYWRIGHT_RETRIES=0 <command-from-get_reproduce_command>
```

- **Passes** → move to next failure
- **Still fails after 2 attempts** → apply skip (see Phase 5)

### Skip-Only Mode (`--skip-only`)

When `--skip-only` is specified, bypass diagnosis and all fix attempts. For every failed test:

1. Use `get_task_context` or `get_class_surface` to locate the `test(...)` body in the spec
2. Add `test.skip(true, '<reason from classify_failures output>')` as the first line inside the test body
3. Run `lint_spec_file(path)` on the modified file

---

### Phase 5: Skip Policy

When a test must be skipped (after failed fix attempts or in `--skip-only` mode):

- **Always include a detailed reason** — what fails, what the observed error was, what would fix it
- **Include the Jenkins build reference** and `classify_failures` label for traceability
- **Categorize**:
  - Selector stale: `'Selector [data-test="X"] not found — UI changed in CNV 4.22; use playwright-cli generate-locator to find new selector'`
  - Timing/performance: `'Timeout after Ns in CI — VM boot exceeds test timeout on shared cluster'`
  - Product regression: `'Feature X behavior changed in CNV 4.22 — CNV-XXXXX (Closed); assertion needs update'`
  - Infrastructure: `'Requires specific storage class / operator version not available in this CI environment'`
  - Unknown: `'Failing since build #N (age=X) — reproduce with CI_SAFE_MODE=0 and diagnose with playwright-cli console error'`
- **Never skip silently** — every skip must be traceable to an observed error

---

### Phase 6: Validation Run

After all fixes and skips are applied:

1. **`lint_spec_file(path)`** (`kubevirt-ui-mcp`) on every modified spec — catch any introduced violations
2. **Type check**: `npx tsc --noEmit` — catch import errors introduced by PO changes
3. **Run all modified specs** together:
   ```bash
   CI_SAFE_MODE=0 PLAYWRIGHT_RETRIES=0 npx playwright test --config=playwright/playwright.config.ts <spec-files...> --workers=<N> --retries=0
   ```
4. Fixed tests must pass; skipped tests must report as skipped; no new failures
5. **If new failures appear**: return to Phase 4 for those
6. **`invalidate_cache()`** (`kubevirt-ui-mcp`) — so coverage oracle queries reflect spec changes

---

### Phase 7: Summary

Output a results table:

| # | Test | Spec File | Jenkins Age | Jira | Classification | Status | Action Taken |
|---|------|-----------|-------------|------|----------------|--------|-------------|
| 1 | ID(CNV-XXXXX) Test name | `template.spec.ts` | 2 | In Progress | test_bug | FIXED | Updated `data-test` in `catalog-page.ts` (playwright-cli confirmed new locator) |
| 2 | ID(CNV-YYYYY) Test name | `migrations.spec.ts` | 7 | Closed | infrastructure | SKIPPED | VM migration timeout in CI — exceeds 8min on shared cluster |
| 3 | Test name (no ID) | `treeview.spec.ts` | 2 | — | flaky | FIXED | Added `waitFor({ state: 'visible' })` before tree node click in PO |

And a summary:

| Metric | Value |
|--------|-------|
| **Jenkins Job** | `test-kubevirt-console-t1-cnv-4.22-ocs #18` |
| **CI Results** | 80 pass / 51 fail / 13 skip (N quarantined) |
| **Failures Analyzed** | N (failed + quarantined, post age-filter) |
| **Fixed Locally** | N (list) |
| **Newly Skipped** | N (list with reasons) |
| **Not Actionable** | N (infrastructure classification + unhealthy cluster) |
| **Local Validation** | PASS / FAIL |
| **Spec Files Modified** | N |
| **Page Objects Modified** | N |

---

## MCP Tool Mapping — Quick Reference

All tools below come from `kubevirt-ui-mcp` unless noted otherwise.

| Phase | Task | Tool |
|-------|------|------|
| -1 | Checkout target branch | `git checkout <branch>` (when `--branch` set) |
| 0A | Parse Jenkins report | `parse_jenkins_report(source)` |
| 0A | Failure counts + top errors | `get_failure_summary()` |
| 0A | Recover quarantined error text | `merge_quarantined()` |
| 0B | Parse console log | Read `--log`; map to `playwright/tests/**/*.spec.ts` |
| 1 | Enrich with Jira ticket data | `get_ticket("CNV-XXXXX")` |
| 2 | Classify each failure | `classify_failures()` |
| 3 | Cluster health check | `check_cluster_health()` |
| 3 | HCO / operator deep-dive | `get_hco_status()` |
| 3 | Node readiness | `get_node_status()` |
| 3 | Storage class availability | `get_storage_class_info()` |
| 3 | Clean stale namespaces | `cleanup_stale_namespaces(4)` |
| 4a | Exact reproduction command | `get_reproduce_command(spec, name)` |
| 4b | Task-scoped method signatures | `get_task_context("fix <feature>")` |
| 4b | All selectors in a PO | `get_selector_map("<PO class>")` |
| 4b | Filtered class view | `get_class_surface("<Class>", "<keyword>")` |
| 4b | Cross-class method search | `search_methods("<keyword>")` |
| 4b | Import path resolution | `get_import_guide(["ClassName"])` |
| 4c | Live page snapshot + locator | `playwright-cli snapshot` + `generate-locator <ref> --raw` *(playwright-cli)* |
| 4c | Console JS errors | `playwright-cli console error` *(playwright-cli)* |
| 4c | Network request inspection | `playwright-cli requests` + `request <n>` *(playwright-cli)* |
| 4c | Element value / attribute | `playwright-cli eval "el => ..." <ref>` *(playwright-cli)* |
| 4c | Visual element confirmation | `playwright-cli highlight <ref>` *(playwright-cli)* |
| 4d | Convention check after edit | `lint_spec_file(path)` |
| 6 | Post-fix cache refresh | `invalidate_cache()` |

---

## Related Commands

| Command | Use when |
|---------|----------|
| `/jenkins-fix-cycle-cy` | Jenkins report or console log — Cypress `.cy.ts` failures |
| `/test-fix-cycle-pw` | Local Playwright tag/path fix loop (no Jenkins URL) |

---

## Important Rules

- **MCP-first for testReport** — `parse_jenkins_report`, `get_failure_summary`, `classify_failures`, and `merge_quarantined` replace manual `curl` + `python3`. Fall back to Shell `curl` only if MCP times out (VPN).
- **Console log is Mode B** — use `--log` when testReport is unavailable; still reproduce locally before speculative skips.
- **Both FAILED and quarantined SKIPPED** — `merge_quarantined` handles the union; use its output, not raw `parse_jenkins_report` alone.
- **`get_reproduce_command` is mandatory** — never manually construct test run commands. The tool knows the correct spec path, grep pattern, and flag format.
- **`playwright-cli` for selector diagnosis** — `generate-locator <ref> --raw` gives you the exact locator string; `console error` surfaces JS crashes; `requests` surfaces API failures. Do not guess at selectors from reading the DOM description alone.
- **Context proxy for code reading** — `get_selector_map` and `get_task_context` before reading any page object file. Saves 4–20× tokens on large POs.
- **Jira enrichment** — `get_ticket` for every `CNV-XXXXX` in the failure list. A ticket in `Closed` state with recent plugin commits means the UI changed intentionally.
- **Lint after every spec edit** — `lint_spec_file` catches missing IDs, raw `page` usage, and hardcoded timeouts before you spend time running a test that will be rejected in review.
- **Fix in the right layer** — selectors in page objects, timeouts via `TestTimeouts.*`, assertions in specs. Never put locators directly in spec files.
- **Never skip silently** — every `test.skip` must include the classification label, observed error text, and Jenkins build reference.
- **DO NOT commit** — the user handles git operations separately via `/commit`.
- **VPN required** — Jenkins and the cluster API are behind the corporate VPN. If `parse_jenkins_report` or `check_cluster_health` times out, stop and inform the user.
