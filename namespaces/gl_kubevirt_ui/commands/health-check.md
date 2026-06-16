# Health Check: Test Suite Status Against Target Cluster

Run a test suite against the target cluster and produce a read-only report of pass/fail/skip status. No fixes, no code changes — purely diagnostic.

## Input

The user provides a test tag, spec path, or `all` after the `/health-check` command:

- **Tag group**: `/health-check '@gating'`, `/health-check '@tier1'` (tags must be wrapped in single quotes)
- **Spec path**: `/health-check playwright/tests/tier1/catalog/`
- **Full suite**: `/health-check all`
- **Optional workers**: append `--workers=N` (default: 4)

Examples:
```
/health-check '@gating'
/health-check '@tier1' --workers=4
/health-check playwright/tests/gating/ --workers=3
/health-check all --workers=6
```

## Workflow

---

### Phase 1: Pre-Flight

1. **Cluster health check via kubevirt-qe MCP** (preferred — structured, comprehensive):
   - Call `check_cluster_health` — verifies API server, CNV operator, virt-api, storage classes, node readiness, stale namespace count
   - Call `get_cluster_info` — captures cluster URL, Kubernetes/KubeVirt/CNV/CDI versions, node count
   - If `healthy: false` → report the failing checks and **STOP** — no point running tests on an unhealthy cluster
   - If stale namespaces > 20 → call `cleanup_stale_namespaces` with `older_than_hours: 4`
   - **Fallback** (if MCP unavailable):
     ```bash
     source playwright/.env 2>/dev/null
     curl -sk -o /dev/null -w "%{http_code}" "${CLUSTER_URL:-https://api.cluster.local:6443}/healthz"
     ```
2. **Verify setup artifacts exist** (`.test-configs/`, `.storage-states/`, `.kubeconfigs/`):
   - If missing, run global setup first:
     ```bash
     SKIP_GLOBAL_TEARDOWN=true npx playwright test \
       --config=playwright/playwright.config.ts \
       tests/gating/scenario-virtualization-pages.spec.ts \
       -g "Virtualization pages" --workers=1 --reporter=list 2>&1 | tail -5
     ```
3. **Record cluster info** for the report header:
   - Use `get_cluster_info` output from step 1 (already captured)
   - **Fallback**:
     ```bash
     cat .test-configs/*.json 2>/dev/null | python3 -c "
     import sys,json
     d=json.load(sys.stdin)
     for k in ['clusterUrl','webConsoleUrl','testNamespace','cnvVersion']:
       print(f'{k}: {d.get(k,\"N/A\")}')
     " 2>/dev/null
     ```

---

### Phase 2: Execute Tests (read-only)

1. **Build the command** based on input:
   - Tag: `npx playwright test --config=playwright/playwright.config.ts --grep "<tag>" --workers=<N> --retries=0`
   - Path: `npx playwright test --config=playwright/playwright.config.ts <path> --workers=<N> --retries=0`
   - All: `npx playwright test --config=playwright/playwright.config.ts playwright/tests/ --workers=<N> --retries=0`
2. **Always use** `PLAYWRIGHT_RETRIES=0` — no retries, raw pass/fail signal
3. **Capture full output** to `/tmp/health-check.log`:
   ```bash
   PLAYWRIGHT_RETRIES=0 npx playwright test ... 2>&1 | tee /tmp/health-check.log
   ```
4. **Wait for completion** — monitor progress periodically

---

### Phase 3: Parse Results

1. **Extract summary line** (e.g., `42 passed`, `3 failed`, `5 skipped`)
2. **List every test** with its status:
   - Parse each `✓` (passed), `✘` (failed), `-` (skipped) line
   - Extract: test number, spec file, test name, duration
3. **For failures**, extract the error summary (first meaningful error line)
4. **For skips**, extract the skip reason from the test output or code

---

### Phase 4: Classify Failures

For each failure, provide a **probable cause** without modifying any code:

| Classification | Indicators |
|---------------|------------|
| **Selector/UI Change** | `Timeout waiting for selector`, `locator resolved to hidden` |
| **Timing/Flaky** | Passes sometimes, timeout on `waitFor`, `element not yet visible` |
| **Auth/Token Expired** | `401 Unauthorized`, `403 Forbidden`, `system:anonymous` |
| **Cluster/Infra** | `ERR_CONNECTION_REFUSED`, `ECONNRESET`, resource not found |
| **Missing Feature** | `test.skip` triggered, feature flag absent, operator not installed |
| **Functional Regression** | Assertion failed on valid selector — UI behavior changed |
| **Test Code Bug** | Wrong destructuring, incorrect assertion, missing await |

---

### Phase 5: Report

Output the full report in this format:

#### Header

```
## Health Check Report
- **Date**: YYYY-MM-DD HH:MM
- **Cluster**: <cluster URL>
- **Console**: <web console URL>
- **CNV Version**: <version>
- **Scope**: <tag or path>
- **Workers**: <N>
- **Duration**: <total time>
```

#### Summary

| Metric | Count |
|--------|-------|
| **Total** | N |
| **Passed** | N |
| **Failed** | N |
| **Skipped** | N |
| **Pass Rate** | XX% |

#### Failures (if any)

| # | Test | File | Duration | Probable Cause |
|---|------|------|----------|---------------|
| 1 | ID(CNV-XXXXX) Test name | `spec-file.ts` | 2m 30s | Selector changed — `[data-test="old"]` not found |
| 2 | Scenario: Feature X | `spec-file.ts` | 5m 01s | Timeout — cluster under load |

#### Skipped Tests (if any)

| # | Test | File | Reason |
|---|------|------|--------|
| 1 | ID(CNV-YYYYY) GPU test | `spec-file.ts` | Requires GPU-enabled node |
| 2 | Scenario: Migration | `spec-file.ts` | Multi-node cluster required |

#### Passed Tests

| # | Test | File | Duration |
|---|------|------|----------|
| 1 | ID(CNV-ZZZZZ) Overview widgets | `spec-file.ts` | 45s |
| ... | ... | ... | ... |

#### Recommendations

Based on the results, provide a brief summary:
- Which test groups are fully healthy
- Which groups have issues and what kind (selector drift, infra, functional)
- Whether the failures look systemic (auth, cluster) or isolated (individual tests)
- Suggested next action: `/test-fix-cycle <command>` to stabilize, or infrastructure investigation needed

---

## Important Rules

- **READ-ONLY** — do NOT modify any test files, page objects, step drivers, or configuration
- **No fixes** — classify and report only
- **No skips** — do not add `test.skip()` to any test
- **No commits** — no git operations
- **No retries** — always `PLAYWRIGHT_RETRIES=0` for an honest signal
- **Preserve output** — keep `/tmp/health-check.log` for reference
- If the cluster is unreachable, report that immediately and stop
