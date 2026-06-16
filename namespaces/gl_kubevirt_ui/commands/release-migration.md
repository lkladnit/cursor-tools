# Release Migration: Pre-4.22 CRUD Test Migration

Migrate CRUD-focused tests for pre-4.22 CNV releases into the mainline Playwright architecture.
Each release gets its own branch, Playwright project, and spec directory under `playwright/tests/releases/`.

## Input

```
/release-migration <version> [module...] [--scaffold] [--explore-only]
```

| Input | Example | Meaning |
|---|---|---|
| Version only | `/release-migration 4.19` | Migrate all 7 modules for CNV 4.19 |
| Version + modules | `/release-migration 4.20 virtualmachines bootable-volumes` | Specific modules only |
| Scaffold | `/release-migration 4.18 catalog --scaffold` | Compilable stubs only, no step logic |
| Explore only | `/release-migration 4.17 --explore-only` | MCP exploration + gap report, no code output |

`<version>` is **required**. It drives the branch name, Playwright project name, spec file names, and tags.

### Available Modules

| Module | UI Area |
|---|---|
| `overview` | Virtualization overview dashboard |
| `catalog` | Template and instance-type VM creation wizard |
| `virtualmachines` | VM list, detail, actions |
| `bootable-volumes` | Bootable volume list, upload, clone, detail |
| `templates` | Template list, detail, boot source management |
| `instance-types` | Cluster/user instance types |
| `vm-networks` | VM NICs, NADs, hotplug |

---

## Workflow

Read and follow `release-migration.mdc` for the full agent instructions. Below is the phase summary.

---

### Phase 0 — Branch + Config Setup

**Starting point**: always branch from `main`. The mainline Playwright architecture (Tier1, Tier2, Gating, NonPriv) is the baseline. Only these four suites are relevant for release migration — any other projects (API Tests, Visual Regression, ACM, CNV Settings) are out of scope and must not be added to the release Playwright project.

1. Resolve git username: `GIT_USER=$(git config user.email | cut -d@ -f1)`
2. Create or switch to `${GIT_USER}/version-release-migration-4.XX` branched from `main`:
   ```bash
   git fetch origin
   git checkout ${GIT_USER}/version-release-migration-4.XX 2>/dev/null \
     || git checkout -b ${GIT_USER}/version-release-migration-4.XX origin/main
   ```
3. Add `Release-4.XX` project to `playwright/playwright.config.ts` (if not already present).
   The project covers only Gating, Tier1, Tier2, and NonPriv test directories — no other suites:
   ```typescript
   {
     // Release migration tests for CNV 4.XX — mainline PO + fixture architecture.
     // Starts from mainline Chrome config; per-release deviations documented below.
     // PatternFly era: pf-c-* (4.12–4.14) | pf-v5-c-* (4.15–4.18) | pf-v6-c-* (4.19–4.21)
     // Suites in scope: gating, tier1, tier2, nonpriv. All other projects excluded.
     // <DEVIATIONS: none yet — updated after Phase 1 exploration>
     name: 'Release-4.XX',
     testMatch: [
       '**/tests/releases/4.XX/gating/**/*.spec.ts',
       '**/tests/releases/4.XX/tier1/**/*.spec.ts',
       '**/tests/releases/4.XX/tier2/**/*.spec.ts',
       '**/tests/releases/4.XX/nonpriv/**/*.spec.ts',
     ],
     grep: /@release-4\.XX/,
     use: {
       ...devices['Desktop Chrome'],
       viewport: { width: 1920, height: 1080 },
       launchOptions: {
         args: chromeArgs,
         headless: !EnvVariables.isDebugMode && !process.env.HEADED,
       },
     },
   },
   ```
4. Add `test-release-4.XX`, `test-release-4.XX-gating`, and `test-release-4.XX-nonpriv` cases to `playwright-runner.sh`:
   ```bash
   test-release-4.XX)
     npx playwright test \
       --config=playwright/playwright.config.ts \
       --project="Release-4.XX" \
       "${@:2}"
     ;;
   test-release-4.XX-gating)
     npx playwright test \
       --config=playwright/playwright.config.ts \
       --project="Release-4.XX" \
       --grep "@gating-4.XX" \
       "${@:2}"
     ;;
   test-release-4.XX-nonpriv)
     npx playwright test \
       --config=playwright/playwright.config.ts \
       --project="Release-4.XX" \
       --grep "@nonpriv-4.XX" \
       "${@:2}"
     ;;
   ```
   Update the `show_help` block to list all three commands.
5. Create the directory structure:
   ```
   playwright/tests/releases/4.XX/gating/
   playwright/tests/releases/4.XX/tier1/
   playwright/tests/releases/4.XX/tier2/
   playwright/tests/releases/4.XX/nonpriv/   ← only if mainline has nonpriv coverage for a module
   ```

---

### Phase 1 — MCP Exploration (CNV Explorer role)

**MCP tools are mandatory — use them before any browser interaction.**

For each module:

1. Pre-flight cluster checks:
   - `check_cluster_health` — API server, CNV operator, virt-api, storage, nodes
   - `get_cluster_info` — confirm CNV version matches the requested release
   - `get_hco_status` — check for degraded components affecting this module
2. Check `playwright-cli` availability:
   ```bash
   playwright-cli --version 2>/dev/null && echo "available" || echo "unavailable"
   ```
3. Browser session (prefer `playwright-cli`; fall back to Playwright MCP if unavailable):
   - Load auth state: `playwright-cli state-load playwright/mcp-validations/.auth/openshift-state.json`
   - Navigate to the module page using the URL from `.env`
   - Snapshot every sub-page, tab, action menu, and form
   - Perform all CRUD operations; capture network requests:
     ```bash
     playwright-cli requests
     playwright-cli request <n>   # for each mutation (POST/PUT/PATCH/DELETE)
     ```
   - Use `playwright-cli console error` after each page load to detect JS errors
   - Take screenshots at each significant state
4. Cluster state inspection:
   - `list_vms` — existing VMs in the test namespace
   - `get_resource` — inspect relevant CRDs (DataVolumes, Templates, InstanceTypes, etc.)
5. Save all output (screenshots, network log) to:
   `playwright/mcp-validations/release-migration/4.XX/<module>/`
6. Build a **Feature Map** documenting: all UI interactions, selectors (`data-test`, `data-test-id`), CRUD endpoints, and per-release deviations from 4.22

---

### Phase 2 — Coverage Gap Analysis (QA Architect role)

**Use `kubevirt-ui-mcp` context tools — never read source files directly.**

1. `get_coverage_for_feature(<module>)` — existing specs, page objects, Jira IDs
2. `get_class_surface(<PageObjectClass>)` — public methods of relevant page objects
3. `get_selector_map(<PageObjectClass>)` — existing `data-test` selectors; compare against Phase 1 discoveries
4. `get_task_context("migrate <module> tests for release 4.XX")` — full method + import set
5. Classify each discovered feature: **Covered** / **Partial** / **Gap**
6. Identify:
   - Missing PO methods (with suggested locators from Phase 1 and Cypress source — see below)
   - New legacy POs needed for features absent in 4.22 → `playwright/src/page-objects/legacy/<module>-legacy-page.ts`
   - Missing fixture properties
   - Per-release selector/navigation deviations from mainline (document for Phase 0 config comment)

**Cypress locator lookup (mandatory when a selector is not found via `get_selector_map`):**

The `kubevirt-ui-old-releases` repository contains the Cypress test source for each pre-4.22 release. Before inventing or guessing a locator, search the Cypress code for the target release:

```bash
# Find the release branch or directory for the target version
ls playwright/tests/releases/   # check if a release-specific directory exists

# Search Cypress source for selectors related to the module
rg "data-test\|data-test-id\|cy\.get\|cy\.contains" \
  --include="*.ts" --include="*.js" -n \
  <cypress-source-path-for-release>/<module>/ | head -60
```

Cypress selectors map to Playwright locators as follows:
- `cy.get('[data-test="foo"]')` → `page.locator('[data-test="foo"]')` — use verbatim in the PO
- `cy.get('[data-test-id="foo"]')` → `page.getByTestId('foo')` or `page.locator('[data-test-id="foo"]')`
- `cy.contains('button', 'Start')` → `page.getByRole('button', { name: 'Start' })`
- PF class selectors (`.pf-c-*`, `.pf-v5-c-*`) — carry over only if no `data-test` equivalent exists

If the Cypress source for the target release is not in this repo, check `git branch -a` for a branch named `release-4.XX` or `cypress-4.XX`.

---

### Phase 3 — Scenario Design (Business Analyst role)

**Scope rule**: use mainline branch workflows as the baseline. Gating retains a similar number of assertions as mainline. Tier1 and Tier2 are reduced to ~1/3 of the mainline scenario count — select only the highest-value, most regression-risky scenarios (prefer CRUD happy paths over edge cases).

Map each selected scenario to a concrete test per tier:

| Tier | Pattern | Scope | Tags |
|---|---|---|---|
| Gating | Read-only assertions only, < 2 min, no resource creation | Similar count to mainline gating | `@release-4.XX`, `@gating-4.XX`, `@priv` |
| Tier1 | One resource created and verified, cleaned up | ~1/3 of mainline tier1 scenarios | `@release-4.XX`, `@tier1-4.XX`, `@priv` |
| Tier2 | `k8sClient` API setup → UI Read/Update/Delete | ~1/3 of mainline tier2 scenarios | `@release-4.XX`, `@tier2-4.XX`, `@priv` |

Selection criteria for Tier1/2 reduction:
- **Keep**: CRUD happy paths, navigation smoke, status checks, actions that changed between releases
- **Drop**: error-state handling, pagination edge cases, duplicate coverage of the same resource type
- **Keep non-priv variants** when the mainline has `@nonpriv` coverage for the module

For each scenario, specify: preconditions, steps, assertions, cleanup, and which PO methods are needed.

---

### Phase 4 — Implementation (Automation Implementer role)

**All implementation follows `automation-implementer.mdc` without exception.** Read that rule before writing any code. The same naming conventions, page encapsulation policy, `test.step()` discipline, timeout constants, Allure constants, TypeScript compliance, and lint gate apply identically to release specs.

**Use `kubevirt-ui-mcp` scaffolding tools — never copy-paste boilerplate manually.**

Pre-implementation queries (mandatory before writing any code):
- `get_import_guide([...symbols])` — correct `@/` import paths
- `get_fixture_map` — which fixture to import for the new test subfolder
- `get_allure_suite_map` — correct Allure tag constants for the tier
- `get_env_vars` — available env vars and defaults

Implementation steps:
1. New PO methods or legacy POs:
   - `scaffold_page_object` for new legacy POs → save to `playwright/src/page-objects/legacy/<module>-legacy-page.ts`
   - Add methods to existing POs using `get_class_surface` to avoid duplication
2. Fixture: add a new per-folder fixture if the module needs one not in `get_fixture_map` output
3. Spec files (one per tier):
   - `scaffold_test` → save to `playwright/tests/releases/4.XX/<tier>/<module>-4.XX.spec.ts`
   - Tags: `{ tag: ['@release-4.XX', '@gating-4.XX'] }` — release-versioned, never generic
   - Import from the per-folder fixture (NOT from `@playwright/test` or `scenario-test-fixture`)
   - Test titles: functional descriptions — no `ID(CNV-XXXXX)` in titles or step labels
   - `TestTimeouts` constants — no hardcoded `ms` values
   - `generateRandom*` helpers for all resource names (`pw-` prefix)
   - `cleanup.track*()` for every created resource
   - No `page.*` in spec files — everything through page objects
4. Post-write validation (mandatory — same gate as mainline):
   ```bash
   npx tsc --noEmit
   npm run lint:fix
   ```
   Then `lint_spec_file` on each new spec — fix all violations before proceeding.
5. Run tests:
   ```bash
   npx playwright test --config=playwright/playwright.config.ts \
     --project="Release-4.XX" --grep "@<module>" --workers=1 --retries=0
   ```
6. Fix failures, iterate until clean.
7. Post-implementation:
   - `invalidate_cache` — refresh scanner after new files
   - `get_reproduce_command` for any remaining failures

---

### `--scaffold` Mode

When `--scaffold` is specified, run Phases 0–3 then stop after generating compilable stubs:
- All `test()` bodies: empty with `test.skip('TODO: implement')` guard
- All PO method bodies: `/* TODO */`
- Goal: compilable skeleton that passes `npx tsc --noEmit`
- Do NOT run tests

---

### `--explore-only` Mode

When `--explore-only` is specified, run only Phases 0 (branch only, no config changes) and 1.
- No spec files, POs, or STDs are created
- Output: `playwright/mcp-validations/release-migration/4.XX/<module>/exploration-report.md`
- Report format: Feature Map, CRUD Coverage Summary, Selector Discoveries, Automation Notes

---

### Phase 5 — STD Documents (Business Analyst role)

1. `scaffold_std` for each new module → save to `playwright/docs/releases/<module>-4.XX.md`
2. `validate_std_coverage` — confirm Jira IDs in STD docs match spec annotations

---

### Phase 6 — Code Review (Code Reviewer role)

Run `kubevirt-ui-mcp` linter tools on all new specs:
- `lint_spec_file <path>` — raw `page` usage, hardcoded timeouts, missing cleanup, direct API calls
- `check_api_ui_parity` — UI write ops without API spec counterparts
- `validate_std_coverage` — Jira IDs in specs missing from STD docs

Manual review checklist:
- [ ] Page encapsulation: no `page.*` in spec files
- [ ] Release-versioned tags on every `test.describe`
- [ ] Cleanup tracked for every created resource
- [ ] Locator strategy: `data-test`/`data-test-id` preferred; no `.pf-*` classes
- [ ] `TestTimeouts` constants (no hardcoded ms values)
- [ ] `pw-` prefix on all resource names

---

### Phase 7 — Summary

Output a final table:

| Module | Gating | Tier1 | Tier2 | New PO Methods | STD File | Status |
|---|---|---|---|---|---|---|
| `virtualmachines` | N tests | N tests | N tests | list | path | Pass/Fail |
| ... | | | | | | |

Inform the user: all changes are on branch `${GIT_USER}/version-release-migration-4.XX`, ready to review and commit with `/commit-cnv-tests`.

---

## Important Rules

- **Architecture**: mainline PO + per-folder fixture + KubernetesClient — NOT procedural/inline selectors
- **Branch from main**: always start from `origin/main`; the mainline Playwright architecture is the baseline
- **Scope**: only Gating, Tier1, Tier2, NonPriv — no other projects (API Tests, Visual, ACM, CNV Settings)
- **Tier1/2 scope reduction**: ~1/3 of mainline scenario count; keep CRUD happy paths, drop edge cases
- **Gating scope**: similar count to mainline gating — no reduction
- **Branch**: one per release version; accumulates modules across multiple runs
- **Tags**: always release-versioned (`@release-4.XX`, `@gating-4.XX`, `@tier1-4.XX`, `@tier2-4.XX`, `@nonpriv-4.XX`)
- **Tier2 Create**: always via `k8sClient` (API), never via UI wizard
- **Legacy POs**: only when a UI feature is absent in the 4.22 mainline POs
- **Cypress locators**: when a selector is not found via `get_selector_map`, search the Cypress source for the target release branch before guessing
- **`kubevirt-ui-mcp` first**: use MCP tools for all exploration, coverage, scaffolding, and linting — direct file reads are last resort
- **Do NOT commit or push** — the user commits separately with `/commit-cnv-tests`
