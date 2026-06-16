# JIRA template: Test failure

Use when: a test ran and failed on assert, timeout, or unexpected behavior. The environment was healthy — the problem is in the product or test code.

## Fields

- **Project:** CNV
- **Type:** Bug
- **Component:** based on test team (use `team` from `cnv-tasks-*.yaml` `x-team-attributes`):
  - Compute/Virt tests → `CNV Virtualization` (or `CNV Virt-Cluster` / `CNV Virt-Node` if specific)
  - Storage tests → `Storage Platform` (or `Storage Ecosystem`)
  - Network tests → `CNV Network`
  - HCO/SSP/IUO tests → `CNV Install, Upgrade and Operators`
  - Upgrade tests → `CNV Install, Upgrade and Operators`
  - Infrastructure tests → `CNV Infrastructure`
  - UI/Console tests → `CNV User Interface`
  - If unsure, look up the job in `src/resources/test-jobs-metadata/` and use the `team` value.
- **Labels:** tier as JIRA convention (e.g. `TIER-1`, `TIER-2`, `UPGRADE`), job name, `gate` if gating job
- **Assignee:** test owner from `cnv-tasks-*.yaml` (`owner` field) or component owner

## Description structure

Use Atlassian Document Format (ADF) via api/3. The logical structure:

1. **Summary** — one sentence: test name + what it expected vs what happened. Include: job name, build number.
2. **Failing test** — full test path: `className :: testName`. Error: `errorDetails` from testReport.
3. **Evidence** — 2-5 lines from the log showing the failure context (in `codeBlock` ADF node). Include: stack trace summary, timeout value, expected vs actual.
4. **Affected builds** — bullet list with links. Note if reproducible (multiple builds) or one-time flake.
5. **Impact** — one sentence: which release signal is affected.
6. **Analysis** — brief root cause hypothesis based on log analysis. If flaky (SSH timeout, transient network), note that retry may pass.

## Examples

| Failure | Summary pattern |
|---------|-----------------|
| Upgrade timeout | `Upgrade gating: automatic workload update (opt-in) times out after 3h (#170, #171)` |
| Image pull | `Guestfs test fails: libguestfs-tools:latest not pullable (test-kubevirt-cnv-4.12 #111)` |
| SSH flake | `test_vhostmd_disk fails: SSH "No existing session" (test-infrastructure-gating #761)` — no ticket, flake |
| Deselected tests | `Post-upgrade network full-cap runs 0 tests: dependency marker unresolved (#2)` |
| SSP timeout | `SSP status should be deploying: timed out (test-ssp-cnv-4.16 #783)` |

## When NOT to create a ticket

- **SSH banner timeout** (paramiko flake) — retry first, only ticket if 3+ consecutive failures.
- **Quota exceeded** — this is infra, use [infra-failure template](infra-failure.md).
- **0 tests selected** — this is test execution failure, check marker/dependency config first before filing.
- **ReportPortal upload failure** — not a test bug; use [infra-failure template](infra-failure.md).
