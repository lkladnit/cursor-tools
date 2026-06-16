# Jenkins Fix Cycle (Cypress): Fetch CI Failures, Analyze, Fix, Validate

Diagnose and fix broken Cypress tests on a release branch. Two CI inputs are supported: Jenkins **testReport API** (structured JUnit) or a downloaded **console log** file.

## Input

Provide **either** a Jenkins URL **or** a console log (not both required in one invocation):

| Mode | Required | Optional |
|------|----------|----------|
| **testReport API** | Jenkins `testReport` / `testReport/api/json` URL | `--branch=<name>`, `--age=N`, `--skip-only`, `--cypress-root=cypress` |
| **Console log** | `--branch=<name>` **and** `--log=<path>` | `--spec=<path>` (single spec only) |

- **`--branch`**: Target branch (e.g. `release-4.21`). Required for console-log mode; recommended for testReport mode on release maintenance.
- **`--log`**: Path to Jenkins console log (e.g. `.cluster-logs/t1-cnv-4.21-68.log`). Download first with `./fetch-jenkins-log.sh <jenkins-url>` when you only have the build page, not testReport JSON.
- **`--age=N`**: (testReport only) Only fix tests failing for N+ consecutive builds.
- **`--skip-only`**: (testReport only) Skip all failures without fix attempts.
- **`--spec`**: (console log only) Limit to one spec under `cypress/tests/`.

### Examples

```
# testReport API
/jenkins-fix-cycle-cy https://jenkins-csb-cnvqe-main.dno.corp.redhat.com/job/test-kubevirt-console-t1-cnv-4.21-ocs/68/testReport/api/json --branch=release-4.21
/jenkins-fix-cycle-cy https://jenkins-csb-cnvqe-main.dno.corp.redhat.com/job/test-kubevirt-console-gating-cnv-4.18-ocs/42/testReport --age=3 --skip-only

# Console log (no testReport URL)
/jenkins-fix-cycle-cy --branch=release-4.21 --log=.cluster-logs/t1-cnv-4.21-68.log
/jenkins-fix-cycle-cy --branch=release-4.14-t1 --log=.cluster-logs/t1-cnv-4.14-10.log --spec=cypress/tests/tier1/catalog-templates/catalog.cy.ts
```

## Prerequisites

1. **Release branch** checked out (or use `--branch` in Phase -1).
2. **Local console** for MCP + Cypress verification: `yarn start-console` → `http://localhost:9000`; set `BRIDGE_BASE_ADDRESS` as needed.
3. **`.env`** cluster credentials (`OPENSHIFT_PASSWORD`, `CLUSTER_URL`) — never hardcode passwords.
4. **Cypress MCP** (`cypress` server, `@tms-cymcp/cypress-mcp`) for UI inspection on localhost.

---

## Workflow

### Phase -1: Branch setup

1. If `--branch=<name>`: checkout the branch (or use a worktree for parallel release work).
2. Determine the branch **PatternFly era** (see `cypress-handler` conventions) before changing selectors.
3. `oc login` using `.env` credentials; install deps if needed.
4. If no `--branch`, operate on the current branch (console-log mode still requires `--branch`).

### Phase 0: Discover failures

#### Mode A — testReport API

1. Normalize URL to end with `/api/json` if needed.
2. Fetch and parse JUnit JSON (`curl` or MCP if available); filter to `.cy.ts` failures.
3. Sort by `age` (longest-failing first). Apply `--age=N` if set.
4. Print CI summary: job, build, pass/fail/skip, unique failing specs.

#### Mode B — console log

1. Read `--log` file from `.cluster-logs/` (or path given).
2. Parse for `✗` markers, error blocks, and failing selectors; map to `cypress/tests/**/*.cy.ts`.
3. If `--spec` set, restrict to that file only.
4. Run lint baseline on affected specs.

Present a failure table before fixing:

| # | Spec | Test title | ID | Source | Error type |
|---|------|------------|-----|--------|------------|

### Phase 1: Classify

| Type | Signals | Action |
|------|---------|--------|
| Selector changed | Timeout, element not found | Fix in `cypress/views/` |
| Assertion | `expected` / `assert` mismatch | Update test or skip after UI check |
| Command / flow | Custom command, flow helper | `cypress/support/`, `*-flow.ts` |
| Timeout / resource | VM/DV not ready | Increase wait or skip with reason |
| Auth / infra | 401/403, connection refused | Report; do not patch product URLs |
| Import / code bug | `TypeError`, missing import | Fix spec or support file |

### Phase 2: Pre-flight

1. Confirm `http://localhost:9000` is serving the plugin (console started).
2. Call `check_cluster_health` when MCP is available.
3. **PF validation mindset**: every selector fix must match the branch PF prefix.

### Phase 3: Fix cycle (per failure, oldest first)

1. Read spec + `cypress/views/*` + `cypress/support/*` referenced by the failure.
2. **Cypress MCP** (`browser_*` tools) on localhost:9000 — snapshot, confirm selectors; translate findings to branch PF era.
3. Apply minimal fix in the correct layer (selectors in `views/`, flows in `*-flow.ts`, commands in `support/`).
4. Re-run the spec:

```bash
cd cypress && node --max-old-space-size=4096 ../node_modules/cypress/bin/cypress run \
  --config-file ./cypress.config.js \
  --env openshift=true \
  --headless \
  --spec "tests/<relative-path>.cy.ts"
```

5. **Passes** → next failure. **Fails after 2 attempts** → `it.skip(...)` with observed error and Jenkins build/log reference.

### Skip-only mode (`--skip-only`, testReport only)

For each failed test, add `it.skip(true, '<reason>')` as the first line in the `it` body using the Jenkins error text.

### Phase 4: Validation

Re-run the **full tier** glob when fixes span multiple specs (e.g. `tests/tier1/*`) so login/setup runs first. Evaluate pass/fail; return to Phase 3 for new failures.

### Phase 5: Summary

| Status | Meaning |
|--------|---------|
| FIXED (verified) | Re-run passed |
| FIXED (unverified) | Code change only; no re-run |
| SKIPPED | `it.skip` with traceable reason |
| NOT ACTIONABLE | Infra/auth; no code change |

---

## Key rules

- **localhost:9000** for MCP debugging and Cypress runs against the local bridge.
- **Only commit `cypress/` changes** — remove debug artifacts before commit.
- **PF era governs selectors** — do not copy PF5 selectors onto a PF4 release branch.
- **VPN** may be required for Jenkins fetch and cluster API.
- **DO NOT commit** from this command — user uses `/commit-cnv-tests` or manual git.

---

## Related commands

| Command | Use when |
|---------|----------|
| `/jenkins-fix-cycle-pw` | Same inputs (testReport or `--log`) for Playwright `.spec.ts` failures |
| `/test-fix-cycle-cy` | No Jenkins input — run a spec/tier locally and fix |
