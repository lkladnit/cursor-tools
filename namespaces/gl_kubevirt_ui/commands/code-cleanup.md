# Code Cleanup: Remove Dead Code, Fix Conventions, Report Changes

Perform systematic code cleanup across Playwright code — remove unused imports, dead methods, dead tests, eliminate duplication, enforce conventions, and produce a detailed report.

## Input

The user provides a scope after the `/code-cleanup` command:

- **Full sweep**: `/code-cleanup all`
- **Layer-specific**: `/code-cleanup page-objects`, `/code-cleanup step-drivers`, `/code-cleanup tests`
- **Specific path**: `/code-cleanup playwright/src/page-objects/bootable-volumes-page.ts`

Examples:
```
/code-cleanup all
/code-cleanup page-objects
/code-cleanup step-drivers
/code-cleanup tests
/code-cleanup playwright/src/page-objects/bootable-volumes-page.ts
```

## Workflow

### kubevirt-qe MCP Acceleration

When available, use the kubevirt-qe MCP Coverage Oracle tools to accelerate Phase 1 analysis:

- `get_untested_step_driver_methods` — instantly finds all public SD methods with zero spec file references (replaces manual method-by-method grep)
- `get_orphan_page_object_methods` — instantly finds all public PO methods with zero SD/test references (replaces manual grep)
- Both tools return exact file paths, line numbers, and coverage percentages for deterministic dead code detection

Call `invalidate_cache` after Phase 2 fixes so subsequent queries reflect the cleaned codebase.

**Fallback**: If MCP is unavailable, use the manual grep-based process described in `code-cleanup.mdc`.

---

### Phase 1: Static Analysis

Analyze the scope without making changes. Build a complete inventory of issues.

1. **Unused imports** — imports declared but never referenced in the file body
2. **Dead methods** — page object/step driver methods with zero references across the codebase
3. **Dead tests** — skipped without ticket, commented out, empty, or duplicate
4. **Code duplication** — identical methods across page objects, copy-pasted step driver logic, duplicated beforeEach blocks
5. **Convention violations** — wrong import source, locators in step drivers, missing step wrappers, raw `.click()`, redundant comments, misplaced locators

---

### Phase 2: Apply Fixes

Process in dependency order: page objects → step drivers → tests → utilities.

**Safety checks before each deletion:**
- Grep entire codebase for references
- Check git blame — flag recent code (< 7 days) for review instead of deleting
- Never silently remove tests with `ID(CNV-XXXXX)` — flag for user review

---

### Phase 3: Validation

1. **Lint**: `npx eslint --fix playwright/src/ playwright/tests/`
2. **Type check**: `npx tsc --project playwright/tsconfig.json --noEmit`
3. **Smoke test** (if tests were modified): run affected tier with `PLAYWRIGHT_RETRIES=0`

---

### Phase 4: Cleanup Report

Produce a structured report with tables for:
- Summary (files analyzed/modified, items removed/fixed, net lines removed)
- Unused imports removed (file + import names)
- Dead methods removed (file + method + reason)
- Dead tests removed (file + test name + reason)
- Duplications resolved (original + duplicate + resolution)
- Convention fixes (file + fix + category)
- Validation results (lint/typecheck/test status)

---

## Important Rules

- **Read before write** — always read a file before modifying it
- **Grep before delete** — search full codebase for references before removing code
- **Preserve test IDs** — never silently remove tests with `ID(CNV-XXXXX)`
- **Don't change test logic** — cleanup is structural, not behavioral
- **Scope boundary** — only touch files under `playwright/`
- **Lint after every file** — run `npx eslint --fix` on each modified file
- **Report everything** — every deletion, move, and fix in the final report
- **DO NOT commit** — the user handles git operations separately
