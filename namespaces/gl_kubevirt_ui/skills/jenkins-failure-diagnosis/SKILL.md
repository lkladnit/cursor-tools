---
name: jenkins-failure-diagnosis
description: Diagnose failures in Jenkins CI/CD pipelines and generate HTML reports with errors, stack traces, screenshots, and videos. Use when the user provides a Jenkins job URL, asks to analyze a failed build, or wants a failure report from Jenkins.
---

# Jenkins Failure Diagnosis

Analyze failed Jenkins builds and produce self-contained HTML reports with error descriptions, stack traces, screenshots, and videos.

## Prerequisites

This skill requires the **jenkins-failure-diagnosis** MCP server. See [setup.md](setup.md) for installation and Cursor configuration.

**Skill location in this repo:** `.cursor/skills/jenkins-failure-diagnosis` (use this path as `<skill-dir>` below).

The MCP server must have these env vars set:
- `JENKINS_URL` — base URL of the Jenkins instance
- `JENKINS_USER` — username for authentication
- `JENKINS_TOKEN` — API token (generate at `$JENKINS_URL/user/<you>/configure`)
- `JENKINS_VERIFY_SSL` — optional, set to `false` for self-signed certs

## Workflow

When the user provides a Jenkins job URL or references a job by short name (e.g. "4.20 t1 gating"),
look up the full URL in [jobs.md](jobs.md) if needed.

### Scan Mode

If the user says **"scan"** instead of providing a URL, run the scan script to refresh all job data:

```bash
<skill-dir>/regenerate_report.sh
```

Equivalent manual command:

```bash
JENKINS_VERIFY_SSL=false <skill-dir>/mcp-server/.venv/bin/python <skill-dir>/scan_jobs.py
```

This fetches the latest build count, last run date, and test results for every job in [jobs.md](jobs.md),
then regenerates `jobs.md` and a new `jobs/jobs-YYYY-MM-DD-HH-MM-SS.html` with a scan timestamp in the HTML header.
`regenerate_report.sh` opens the newest HTML in the default browser (macOS `open`).

**After editing [scan_jobs.py](scan_jobs.py):** run `<skill-dir>/regenerate_report.sh` (or `./regenerate_report.sh --watch` to poll `scan_jobs.py` and `jobs.md` every 2s and regenerate + open on change).

If the scan fails (e.g. network unreachable), neither file is modified.

### Option A: Full Report (default)

Call the `generate_failure_report` MCP tool with the job URL. This single call:
1. Fetches build metadata and test report via Jenkins API
2. Downloads and extracts the artifact archive
3. Matches screenshots and videos to failed tests by name
4. Generates a self-contained HTML file with all failures, media embedded as base64

Report is saved to `~/jenkins-reports/` by default. Tell the user the path and offer to open it.

### Option B: Step-by-Step Investigation

For deeper analysis, use individual MCP tools:

1. `get_build_info` — build status, duration, agent, artifact list
2. `get_test_report` — all failed tests with error messages and stack traces
3. `get_console_log` — raw console output for pipeline-level failures
4. `download_artifacts` — extract logs, screenshots, videos for inspection

Then apply the diagnosis workflow below before generating the report.

## Diagnosis Logic

### Classify the failure

| Category | Signals |
|----------|---------|
| **Test** | Assertion failures, timeouts, flaky tests |
| **Build** | Compilation errors, dependency resolution |
| **Infrastructure** | Agent offline, OOM, disk full, Docker issues |
| **Pipeline Config** | Jenkinsfile syntax, missing credentials, bad DSL |
| **Permissions** | 401/403, token expired, SSH key mismatch |

### Analyze test failures

- Compare error messages to known patterns (see [common-errors.md](common-errors.md))
- Check if stack trace points to test code vs application code
- Flag potential flaky tests: `SocketTimeoutException`, `ConnectionRefused`, or tests that pass on retry
- Look for environment-specific issues: DB not started, port conflicts

### Match media to failures

Screenshots and videos are matched to failures by comparing file names against test class and method names. Unmatched media is shown in a separate section of the report.

## Report Contents

The HTML report includes:
- Build summary header with result badge, duration, Jenkins link
- Failure count summary cards
- Per-failure cards with:
  - Test class and method name
  - Error message (highlighted)
  - Expandable stack trace
  - Matched screenshots (embedded)
  - Matched videos (embedded with controls)
- Section for unmatched media artifacts
- Dark theme, responsive layout, self-contained (no external dependencies)

## Additional Resources

- For common error patterns and fixes, see [common-errors.md](common-errors.md)
- For MCP setup instructions, see [setup.md](setup.md)
- For the full list of Jenkins job URLs, see [jobs.md](jobs.md)
- For the scan script that refreshes all jobs, see [scan_jobs.py](scan_jobs.py)
