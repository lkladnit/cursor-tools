# Test Fix Cycle (Cypress): Run, Analyze, Fix, Repeat

Local-run fix loop for Cypress, mirroring the Playwright `/test-fix-cycle-pw` split (run locally → analyze → fix → rerun).

## Input

The user provides a Cypress spec (or tier directory) after the `/test-fix-cycle-cy` command:

- **Spec path**: `cypress/tests/tier1/catalog.cy.ts` or `cypress/tests/gating/`
- **Optional branch**: append `--branch=<name>` to target a specific branch (default: current branch)
- **Optional mode**: append `--headed` to run headed (default: headless)

Examples:
```
/test-fix-cycle-cy cypress/tests/gating/
/test-fix-cycle-cy cypress/tests/tier1/catalog-templates/create-vm-from-catalog.cy.ts
/test-fix-cycle-cy cypress/tests/tier1/catalog.cy.ts --branch=release-4.21
```

## Workflow

---

### Phase 0: Branch + Pre-flight

1. If `--branch=<name>` provided, checkout the branch (or worktree).
2. Determine PF era (see `cypress-handler` conventions) before changing selectors.
3. Ensure console is running (typical: `yarn start-console` → `http://localhost:9000`) and `BRIDGE_BASE_ADDRESS` is set as needed.
4. Call `check_cluster_health` when available.

---

### Phase 1: Initial Run

Run the spec or directory (Cypress does not use Playwright-style workers here):

```bash
cd cypress && node --max-old-space-size=4096 ../node_modules/cypress/bin/cypress run \
  --config-file ./cypress.config.js \
  --env openshift=true \
  --headless \
  --spec "tests/<relative>.cy.ts"
```

If the input is a directory, pass it as the `--spec` glob root (Cypress will discover matching specs).

Save output to `/tmp/test-fix-cycle-cy.log` for analysis.

---

### Phase 2: Analyze Failures

1. Summarize pass/fail/skip counts and duration.
2. List each failing `it(...)` with:
   - Spec file
   - Test title (prefer `ID(CNV-XXXXX)` when present)
   - First meaningful error line and source location
3. Classify (selector, timing, click covered, auth/infra, assertion, code bug).

---

### Phase 3: Fix Cycle

For each failure:

1. Read the spec + referenced `cypress/views/*` + `cypress/support/*`.
2. Use **Cypress MCP** (`cypress` server `browser_*` tools) to snapshot/navigate and confirm selectors.
3. Apply the minimal fix in the correct layer (selectors in `views/`, flows in `*-flow.ts`, commands in `support/`).
4. Re-run the same spec to verify.
5. After 2 unsuccessful fix attempts, apply `it.skip(...)` with a traceable reason.

---

### Phase 4: Validation Run

Re-run the original spec/dir until stable.

---

## Related Commands

| Command | Use when |
|---------|----------|
| `/test-fix-cycle-pw` | Playwright local-run fix loop |
| `/jenkins-fix-cycle-cy` | Jenkins `testReport/api/json` or `--log` + `--branch` for Cypress CI failures |

