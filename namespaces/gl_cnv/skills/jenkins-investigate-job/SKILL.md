---
name: jenkins-investigate-job
description: Investigate Jenkins jobs by link, identify failures, and debug with related clusters and repos. Use when the user shares a Jenkins job/build URL or asks why a Jenkins pipeline failed.
---

# jenkins-investigate-job

## Prerequisites

- **Jenkins:** No token needed for read-only access (consoleText, testReport are public on CNV QE Jenkins). Token required only for triggering builds.
- **JIRA:** For ticket creation, uses `jira-create-ticket` skill (see [skills/README.md](../README.md#prerequisites-jira-token-skills-56)).

## Instructions

When the user provides a Jenkins job or build link:

### Step 1: Check build status via API

Fetch `<job_url>/api/json?tree=result,displayName,duration,timestamp,actions[causes[*],triggeredBuilds[*],parameters[*]]`.
Extract `result`, `displayName`, `duration`, `timestamp`.
- `SUCCESS` — report and stop.
- `null` — build is still running; report and stop.
- `UNSTABLE` — tests ran but some failed; start with Step 2.
- `FAILURE` or `ABORTED` — pipeline broke; Step 3 is often more useful than Step 2.

Extract from `actions`: upstream cause, parameters, and cluster name (if present).

Identify the job type — wrapper vs leaf — from two signals:

**Signal 1: Job name.**
Wrapper names contain `-scheduled`, `-wrapper`, `-in-production`, or `-regression-`
(e.g. `test-cdi-cnv-4.16-scheduled`, `verify-cnv-4.16.z-build-tier1-tier2-wrapper`).
Leaf test jobs are named like `test-pytest-cnv-4.16-compute-virt-gating`.

**Signal 2: Jenkinsfile path in the console log header** (first few lines):
`Checking out git ... to read <path>`.

| Path | Type |
|------|------|
| `.../execution-wrapper/Jenkinsfile` | YAML execution wrapper (deploy + many test tasks) |
| `.../verify-cnv-build-tier1-tier2-wrapper/Jenkinsfile` | Gating wrapper (tier1/tier2/upgrade in parallel) |
| `.../verify-cnv-build/Jenkinsfile` or `.../verify-cnv-build-tier1/Jenkinsfile` | Gating verify job (runs tests directly) |
| `.../cnv-tests/Jenkinsfile-cnv-tests` or `Jenkinsfile-v*` | Individual test job |
| `.../bm-ipi/Jenkinsfile-cnv-*` or `.../rhos-ipi/Jenkinsfile-cnv-*` | Deployment job |

For wrapper jobs, failures cascade: a deploy failure causes all downstream tasks to show
"0 tests were passed" with missing JUnit. Always trace back to the wrapper's own log first.

### Step 2: Check test report via API

Fetch `<job_url>/testReport/api/json` to decide next step (do not dump raw counts to the user):
- If `failCount > 0` — extract each failing test: `className`, `name`, `errorDetails`, `status`.
- If `passCount == 0` and `skipCount == 0` — no tests ran at all (test execution failure).
- If 404 — no test report exists; failure happened before tests. Go to Step 3.

### Step 3: Download console log for root cause

Create a temp directory with `mktemp -d /tmp/jenkins-logs.XXXXXX` (once per session, reuse for subsequent downloads).
Download `<job_url>/consoleText` into that directory as `<job_name>.<build_number>.consoleText`.

Scan for error patterns (search all, not just first match).
Use `rg` (ripgrep) for large logs; fall back to `grep -E` if `rg` is not installed.

| Category | Patterns |
|----------|----------|
| Checkout/SCM | `Could not resolve host`, `fatal: unable to access`, `fatal: repository.*not found` |
| Deploy failures | `Error while trying to Deploy OCP`, `Error while trying to Deploy CNV`, `Deploy storage class.*failed` |
| Cluster state | `failed to get the Bundle Image used to install HCO`, `No stable or candidate previous version found` |
| Cluster DNS | `Failed to resolve.*Name or service not known` for `api.<cluster>` — cluster does not exist or DNS not published |
| OLM/Install | `timed out waiting.*catalogsources/hco-catalogsource`, `timed out waiting.*machineconfigpools/master` |
| Missing tools | `command not found`, `No such file or directory` (exit code 127) |
| KUBECONFIG | `Missing or incomplete configuration`, `oc login.*failed` |
| Quota/Pods | `exceeded quota`, `Failed to provision agent` |
| Jenkins K8s agent | `JENKINS-30600.*ContainerExecDecorator`, `Failed to start websocket connection`, `KubernetesClientException` |
| Stash/Artifacts | `No such saved stash`, `Could not unstash` — upstream stage failed, trace upward |
| Test selection | `deselected / 0 selected`, `No JUnit results`, `0 tests were passed` |
| Test failures | `FAILED.*test`, `TimeoutExpiredError`, `timed out waiting` |
| Operators | `InstallPlan.*timeout`, `CSV.*Failed`, `HCO.*not.*ready`, `SSP.*error` |
| Registry/Auth | `unauthorized`, `--registry-config=`, `no such host` |
| Registry content | `manifest unknown` (skopeo) — tag/image does not exist in Brew/proxy |
| Infra/Network | `PXE`, `DHCP`, `Error reading SSH protocol banner`, `connection refused` |
| TLS/CA | `x509: certificate`, `tls: failed to verify`, `SSLEOFError.*UNEXPECTED_EOF` (may be missing CA, proxy, or LB issue) |
| External services | `Timed out searching for UMB message`, `DataGrepper`, `ResultsDB verification timed out`, `HTTP request.*Status code 4` |
| Jenkins JVM | `MissingContextVariableException`, `MissingPropertyException`, `OutOfMemoryError` |
| Image pull | `ErrImagePull`, `ImagePullBackOff` |
| Reporting (not a test bug) | `Unable to read rp_out.file`, `Invalid import file.*Project id`, `Unable to post result XML` |
| Process killed | `script returned exit code 143` — SIGTERM (timeout, abort, or OOM kill, not a logic error) |

If no predefined patterns match, fall back to generic search:
`rg -i 'ERROR|FATAL|Exception|Traceback' <log_file> | tail -30`.
If still nothing, report the build result and the last 50 lines before `Finished:` as evidence,
and ask the user for guidance.

### Step 4: Follow downstream builds

Check `actions` in the API response for `triggeredBuilds`, or search the log
for `Building job:` lines (from `infraUtils.scheduleBuild`). Repeat Steps 1-3
for each downstream job until the first real root cause is found.

For wrapper jobs, check the trigger chain at the top of the log:
```
Started by upstream project "verify-cnv-4.16.z-build-tier1-tier2-wrapper" build number 838
 originally caused by:
  Started by upstream project "kargo-event" build number 4335
```
Trace upward to find the orchestrator, then downward to find the failing leaf job.

### Step 5: Classify and report

| Type | When |
|------|------|
| **Test failure** | Test ran, failed on assert/timeout/feature mismatch |
| **Test execution failure** | Failed before tests ran (0 selected, missing tools, bad params) |
| **Environment failure** | Deploy, cluster, network, registry, DNS, quota, JVM OOM |

If cluster diagnostics needed, use `cluster-activate` skill.
If Environment failure, use `jira-create-ticket` skill (search first, create if none found).

Output format:
```
Job:    <job_name>
Build:  <build_number>
URL:    <job_url>
Logs:   /tmp/jenkins-logs.XXXXXX/<job_name>.<build_number>.consoleText

Type:   Test failure | Test execution failure | Environment failure
Cause:  <one short sentence>

Evidence:
  - <log line 1>
  - <log line 2>

Downstream trace (if used):
  - /tmp/jenkins-logs.XXXXXX/<downstream_job>.<build>.consoleText
  - Root cause found in: <job/build>

Action:
  - Test failure:           Note failing test name. Create ticket if new or recurring.
  - Test execution failure: Suggest fix in one sentence.
  - Environment failure:    JIRA ticket draft or existing ticket reference.
```

## Wrapper-specific failures

Detect wrappers using the job name and Jenkinsfile path table in Step 1.
Another runtime signal: the log contains multiple `Building job:` lines (one per downstream task).

Wrapper failure modes:

| Signal | Meaning |
|--------|---------|
| `Deployment validation failed` | Metadata/cluster requirements mismatch — check `JOB_METADATA` param |
| `Deploy job is not defined for this wrapper` | Missing deploy job name in execution plan YAML |
| `Cluster health check failed` | Pre-task health check returned FAILURE — cluster unusable |
| `Vital task ... failed; aborting` | A task marked `vital: true` failed; wrapper aborted remaining tasks |
| `Building job: <name>` repeated many times | Normal wrapper behavior — each line is a downstream test job |
| All downstream jobs show `0 tests were passed` | Deploy stage failed; no cluster was available for tests |

When a wrapper fails, check the **deploy stage first** — if deploy failed, downstream test failures are likely a cascade.

## Notes

- CNV QE Jenkins: `https://jenkins-csb-cnvqe-main.dno.corp.redhat.com/`
- Console logs can be large (10k+ lines). Use `rg` or `grep -E` to search, do not read line by line.
- Always check `Started by` lines at the top of the log to understand trigger chain.
- `UNSTABLE` ≠ `FAILURE`: UNSTABLE means tests ran but some failed; FAILURE means the pipeline itself broke.
- If multiple users report the same symptom at once, check Jenkins health first
  (`<jenkins_url>/api/json` for master, queue size, executor count) before debugging individual jobs.
- If a GitHub required check (e.g. `tox:verify-tc-requirement-polarion:passed`) never appears
  even after rebase, the problem is likely `github-events-listener` or the downstream executor
  job not being triggered — not the PR itself.
- Job `ABORTED` at an exact round timeout (e.g. 2h) usually means an external dependency
  (Beaker provisioning, Ansible playbook) exceeded the pipeline timeout — not a test or Jenkins failure.

## JIRA integration

For ticket search and creation, use the [jira-create-ticket](../jira-create-ticket/SKILL.md) skill.
