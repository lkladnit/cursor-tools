---
name: api-cross-check
description: >
  Given a UI test report (Jenkins URL, JUnit XML, Allure results dir, or free-text
  feature areas / spec names), identifies the corresponding API tests and executes
  them to cross-check HTTP endpoint stability against the reported UI failures.
  Use when the user says "/api-cross-check", "cross-check API", "run API tests for
  failing UI tests", or provides a test report and asks to validate API stability.
---

# `/api-cross-check` — UI→API Cross-Check Command

Validate API endpoint stability against a UI test report. Given any supported input
format, this command resolves the matching API specs, runs them, and produces a
side-by-side verdict report.

---

## Quick Start

```
/api-cross-check <source>
```

**Examples:**
```
/api-cross-check https://jenkins.example.com/job/test-kubevirt-console-tier1/42/
/api-cross-check test-results/junit.xml
/api-cross-check vm-actions, templates, bootable-volumes
/api-cross-check vm-lifecycle-actions.spec.ts vm-overview-lifecycle.spec.ts
/api-cross-check all
```

---

## Step 0 — Identify Input Format

Classify the source the user provided:

| Input | Format | Parser to use |
|-------|--------|---------------|
| URL starting with `http` | Jenkins job URL | § Step 1A |
| File path ending in `.xml` | JUnit XML | § Step 1B |
| Directory path (allure) | Allure results | § Step 1C |
| Comma/space-separated spec names or feature words | Text | § Step 1D |
| `all` | Run everything | § Step 1E |

---

## Step 1 — Extract Affected UI Spec Files

### 1A — Jenkins URL

Use the `jenkins-failure-diagnosis` MCP tool if available:
```
get_test_report(<jenkins_url>)
```
From the returned failed test list, extract `className` values — these typically
contain the spec file name (e.g. `vm-lifecycle-actions > Should stop VM`).

**Fallback** (if MCP unavailable): fetch the JSON test report directly:
```bash
curl -sk "<jenkins_url>/testReport/api/json?tree=suites[cases[className,name,status]]" \
  | python3 -c "
import json,sys
data=json.load(sys.stdin)
failed={c['className'] for s in data.get('suites',[]) for c in s.get('cases',[]) if c['status'] in ('FAILED','REGRESSION')}
print('\n'.join(sorted(failed)))
"
```
If the job uses `consoleText`, fetch that instead and grep for `FAILED` or `✗`:
```bash
curl -sk "<jenkins_url>/consoleText" | grep -oE '[a-z-]+\.spec\.ts' | sort -u
```

### 1B — JUnit XML

```bash
python3 -c "
import xml.etree.ElementTree as ET, sys
tree = ET.parse('$FILE')
specs = set()
for tc in tree.iter('testcase'):
    cn = tc.get('classname','')
    if '.spec.' in cn:
        specs.add(cn.split(' > ')[0].strip())
    for _ in tc.iter('failure'):
        specs.add(cn.split(' > ')[0].strip())
print('\n'.join(sorted(specs)))
"
```

Or using `kubevirt-ui-mcp`:
```
get_test_results(source: "junit")
```
then extract spec names from the `failed` list.

### 1C — Allure Results Directory

```
get_test_results(source: "allure")
```
Extract the spec file names from the `suite` or `parentSuite` fields of failed
results.

### 1D — Free Text (spec names / feature words)

Map each word/phrase to a canonical UI spec file using the keyword table below:

| Keyword(s) | UI spec file(s) |
|------------|----------------|
| `vm-list`, `vm list`, `list` | `vm-list.spec.ts` |
| `vm-actions`, `vm actions`, `lifecycle` | `vm-lifecycle-actions.spec.ts` |
| `vm-overview`, `vm overview`, `vm detail` | `vm-overview-lifecycle.spec.ts` |
| `vm-migration`, `migration actions` | `vm-migration-actions.spec.ts` |
| `vm-resource`, `save as template`, `clone` | `vm-resource-actions.spec.ts` |
| `catalog` | `catalog.spec.ts` |
| `bootable`, `bootable-volumes`, `datasource` | `bootable-volumes.spec.ts` |
| `templates`, `template` | `templates.spec.ts` |
| `instance-types`, `instancetype` | `instanceType.spec.ts` |
| `migration-policies`, `migration policy` | `migration-policies.spec.ts` |
| `migrations`, `overview migrations` | `migrations.spec.ts` |
| `snapshots`, `snapshot` | `vm-overview-lifecycle.spec.ts` |
| `folders`, `folder` | `vm-list.spec.ts` |

If a value already ends in `.spec.ts`, use it directly — no mapping needed.

### 1E — All

Include all UI spec files listed in the mapping table in § Step 2.

---

## Step 2 — Map UI Specs → API Specs

Use this authoritative mapping table (maintained in `playwright/docs/api/api-tests.md`):

| UI spec file | API spec file(s) |
|-------------|-----------------|
| `vm-list.spec.ts` | `vm-list-api.spec.ts`, `vm-folders-api.spec.ts` |
| `vm-lifecycle-actions.spec.ts` | `vm-crud-api.spec.ts`, `vm-vmi-lifecycle-api.spec.ts` |
| `vm-overview-lifecycle.spec.ts` | `vm-detail-api.spec.ts`, `vm-crud-api.spec.ts`, `vm-vmi-lifecycle-api.spec.ts`, `snapshots-crud-api.spec.ts`, `vm-snapshots-extended-api.spec.ts` |
| `vm-migration-actions.spec.ts` | `vm-migration-api.spec.ts` |
| `vm-resource-actions.spec.ts` | `vm-save-as-template-api.spec.ts` |
| `catalog.spec.ts` | `catalog-api.spec.ts` |
| `bootable-volumes.spec.ts` | `bootable-volumes-api.spec.ts`, `bootable-volumes-crud-api.spec.ts` |
| `templates.spec.ts` | `templates-crud-api.spec.ts` |
| `instanceType.spec.ts` | `instance-types-crud-api.spec.ts` |
| `migration-policies.spec.ts` | `migration-policies-crud-api.spec.ts` |
| `migrations.spec.ts` | `vm-migration-api.spec.ts` |

Deduplicate — if multiple UI specs map to the same API spec, include it only once.

Show the resolved list to the user before running:
```
Resolved API specs to run:
  playwright/tests/api/vm-crud-api.spec.ts
  playwright/tests/api/vm-vmi-lifecycle-api.spec.ts
  playwright/tests/api/vm-detail-api.spec.ts
```

---

## Step 3 — Pre-flight Check

Before executing, verify the cluster is reachable:
```
check_cluster_health()
```

If the health check fails, report the issue and ask the user whether to proceed.

Also confirm the API Tests project exists in the Playwright config:
```bash
grep -A3 '"API Tests"' playwright/playwright.config.ts | head -6
```

---

## Step 4 — Execute API Tests

Use the `run_tests` tool from `kubevirt-ui-mcp` for clean invocation:

```
run_tests(
  file: "<spec1> <spec2> ...",   // space-separated paths relative to playwright/
  grep: "@api",
  workers: 2,
  retries: 0                     // no retries — hard failures only
)
```

**Manual equivalent:**
```bash
SKIP_BROWSER_SETUP=1 CI_SAFE_MODE=0 npx playwright test \
  --config=playwright/playwright.config.ts \
  --project="API Tests" \
  --grep "@api" \
  --retries=0 \
  --workers=2 \
  playwright/tests/api/<spec1>.spec.ts \
  playwright/tests/api/<spec2>.spec.ts
```

> **Why `CI_SAFE_MODE=0`?** Cross-check runs need hard failures — CI Safe Mode would
> quarantine failures as skipped and mask real API regressions.

> **Why `retries=0`?** API calls are deterministic. A retry that passes masks a real
> intermittent endpoint problem and should be reported, not silently retried.

---

## Step 5 — Parse Results

After execution, collect results via:
```
get_test_results(source: "junit")
```

Or parse the Playwright list-reporter output directly from the shell output.

For each API spec that ran, record:
- Total tests
- Passed count
- Failed count (with test titles and error messages)
- Skipped count

---

## Step 6 — Produce the Cross-Check Report

Output a structured report in this format:

---

### API Cross-Check Report

**Date:** `<timestamp>`
**Source:** `<input source>`
**Cluster:** `<CLUSTER_NAME from .env>`
**API Project:** `API Tests`

#### Results by Feature

| UI Spec (source of failure) | API Spec | Passed | Failed | Skipped | Verdict |
|-----------------------------|----------|--------|--------|---------|---------|
| `vm-lifecycle-actions.spec.ts` | `vm-crud-api.spec.ts` | 5 | 0 | 0 | ✅ API stable |
| `vm-lifecycle-actions.spec.ts` | `vm-vmi-lifecycle-api.spec.ts` | 7 | 1 | 0 | ❌ API regression |
| `vm-overview-lifecycle.spec.ts` | `vm-detail-api.spec.ts` | 9 | 0 | 0 | ✅ API stable |
| `vm-overview-lifecycle.spec.ts` | `vm-snapshots-extended-api.spec.ts` | 10 | 0 | 0 | ✅ API stable |

#### Verdict Key

| Symbol | Meaning |
|--------|---------|
| ✅ API stable | All API tests passed — UI failure is likely a rendering/selector issue |
| ❌ API regression | API tests failed — HTTP contract broken, likely shared root cause with UI |
| ⚠️ API partial | Some tests passed, some failed — mixed signal, investigate individually |
| ⬜ Not covered | No API spec mapped to this UI spec — coverage gap |

#### Summary

- **UI specs analysed:** N
- **API specs executed:** N
- **API stable:** N
- **API regression:** N (list affected endpoints)
- **Not covered:** N (list gaps)

#### Failed API Tests Detail

For each failure:
```
❌ vm-vmi-lifecycle-api.spec.ts › START: call start subresource and wait for Running
   Error: HTTP 503 Service Unavailable — ...
   → Endpoint: PUT /kubernetes/apis/kubevirt.io/v1/namespaces/{ns}/virtualmachines/{name}/start
```

#### Recommendation

- If **API stable** for all mapped specs: UI failures are isolated to rendering/selectors.
  Run `Test Executor` to debug the UI tests with MCP.
- If **API regression** detected: the HTTP contract is broken. File a bug / investigate
  the cluster. Both UI and API tests share the same root cause.
- If **Not covered** gaps exist: run `/new-api-test <feature>` to add coverage.

---

## Notes for the Agent

- Always show the resolved spec list (Step 2 output) **before** running — let the user
  confirm or adjust.
- If the input is a Jenkins URL that requires authentication, check `.env` for
  `JENKINS_USER` / `JENKINS_TOKEN` before attempting the fetch.
- If `SKIP_BROWSER_SETUP=1` causes a missing session-cookie error, global setup must
  run first: execute one gating spec normally to prime `.test-configs/`.
- If a UI spec has no matching API spec (⬜ Not covered), note it clearly — do **not**
  skip it silently.
- After the run, call `cleanup_stale_namespaces` to remove `pw-*` namespaces left by
  the API tests.
