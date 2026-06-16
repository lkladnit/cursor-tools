# JIRA template: Infrastructure / Environment failure

Use when: deploy failure, cluster issue, DNS, registry auth, quota, Jenkins OOM, missing tools in container, CI trigger not firing.

## Fields

- **Project:** CNV
- **Type:** Bug
- **Component:** based on failure area (use team names from `cnv-tasks-*.yaml` `x-team-attributes`):
  - Jenkins agent/pod/OOM/quota → `CNV QE DevOps`
  - CI trigger not firing (e.g. `github-events-listener`, `cnv-tests-tox-executor`) → `CNV QE DevOps`
  - OCP deploy failure → `CNV Install, Upgrade and Operators`
  - Registry/auth → `CNV Install, Upgrade and Operators`
  - Network/DNS/PXE → `CNV Network`
  - Cluster infra (bare-metal, IPI executor) → `CNV Infrastructure`
  - Missing tools in test container → component of the affected test (look up `team` in `cnv-tasks-*.yaml`)
- **Labels:** job name, tier if applicable
- **Assignee:** component owner or look up `team` in `src/resources/test-jobs-metadata/`

## Description structure

Use Atlassian Document Format (ADF) via api/3. The logical structure:

1. **Summary** — one sentence: what failed and where. Include: job name, build number, cluster name (if applicable).
2. **Evidence** — 2-5 key error lines from the log (in `codeBlock` ADF node).
3. **Affected builds** — bullet list with links to failed builds. If reproduced multiple times, list all.
4. **Impact** — one sentence: what is blocked (e.g. "No T2 tests executed", "Release checklist signal invalid", "PRs blocked by missing required check").
5. **Suggested fix** — one sentence with a concrete action (e.g. "Increase Metaspace limit", "Add git+jq to container image", "Restart github-events-listener job").

## Examples

| Failure | Summary pattern |
|---------|-----------------|
| DNS on agent | `Jenkins agent cannot resolve gitlab.cee.redhat.com (job #N)` |
| OOM Metaspace | `verify-cnv-4.16.z-build-tier2 #887: OutOfMemoryError Metaspace, all stages skipped` |
| Missing git/jq | `HCO tests fail: git/jq missing in test container (test-hco-cnv-4.16 #303)` |
| Registry auth | `oc adm catalog mirror fails: unauthorized (verify-cnv-4.12.z-build #2026)` |
| Quota exceeded | `Jenkins agent pods cannot launch: CPU quota exceeded (test-upgrade-cnv-4.16 #150)` |
| CI trigger broken | `cnv-tests-tox-executor is not triggered, blocking tox:verify-tc-requirement-polarion:passed check on PRs` |
