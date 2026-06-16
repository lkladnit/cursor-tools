# Cypress Cherry-Pick: Cross-Branch Fix Propagation

Propagate Cypress test fixes across version-specific branches, adapting PatternFly selectors to each branch's PF era.

## Input

```
/cypress-cherry-pick <source-branch> --to=<target-branches> [options]
```

### Parameters

| Parameter | Required | Description |
|-----------|----------|-------------|
| `<source-branch>` | Yes | Branch where the fix was applied (e.g., `release-4.21`) |
| `--to=<targets>` | Yes | Target branches (comma-separated, or `all`, or a range like `4.15-4.20`) |
| `--commit=<sha>` | No | Specific commit to cherry-pick (defaults to latest on source branch) |
| `--dry-run` | No | Show what would be done without applying changes |

### Examples

```
/cypress-cherry-pick release-4.21 --to=release-4.20,release-4.19
/cypress-cherry-pick release-4.21 --to=4.15-4.20
/cypress-cherry-pick release-4.21 --to=all
/cypress-cherry-pick release-4.21 --to=release-4.14-t1,release-4.14-t2 --commit=abc123
/cypress-cherry-pick release-4.18 --to=4.15-4.17 --dry-run
```

### Target Resolution

| Shorthand | Expands To |
|-----------|-----------|
| `all` | All active branches except source |
| `4.15-4.20` | `release-4.15`, `release-4.16`, ..., `release-4.20` |
| `release-4.14` | `release-4.14-t1`, `release-4.14-t1-gating`, `release-4.14-t2`, `release-4.14-t2-gating` |
| `release-4.13` | `release-4.13-gating`, `release-4.13-t1`, `release-4.13-t2`, `release-4.13-t2-gating` |
| `release-4.12` | `release-4.12-gating`, `release-4.12-t1`, `release-4.12-t1-nonpriv`, `release-4.12-t2`, `release-4.12-t2-nonpriv` |

---

## Workflow

### Phase 0: Analyze Source Changes

1. **Read the source commit** to understand what changed:
   ```bash
   git log origin/<source-branch> -1 --format='%H %s'
   git diff origin/<source-branch>~1..origin/<source-branch> -- cypress/
   ```

2. **Classify changed files**:
   | File Type | Adaptation Needed |
   |-----------|------------------|
   | `views/selector-*.ts` | PF prefix translation |
   | `views/*-flow.ts` | PF prefix translation + logic review |
   | `support/*.ts` | Usually PF-agnostic — direct cherry-pick |
   | `utils/const/*.ts` | Usually PF-agnostic — direct cherry-pick |
   | `tests/**/*.cy.ts` | Check if test exists on target branch |

3. **Identify PF-specific changes**:
   ```bash
   # Find all PF class references in the diff
   git diff origin/<source-branch>~1..origin/<source-branch> -- cypress/ | grep -E '\.pf-(v[56]-)?c-'
   ```

### Phase 1: Build Adaptation Plan

For each target branch:

1. **Determine PF era** (same mapping as cypress-handler.mdc)
2. **Check if target files exist** on the branch:
   ```bash
   git ls-tree origin/<target-branch> -- cypress/views/selector-common.ts
   ```
3. **Check if target tests exist** — some tests may not exist on older branches
4. **Build the adaptation map**:

| Source Selector | Source Era | Target Branch | Target Era | Adapted Selector |
|----------------|-----------|---------------|-----------|-----------------|
| `.pf-v6-c-modal-box` | PF6 | release-4.18 | PF5 | `.pf-v5-c-modal-box` |
| `.pf-v6-c-modal-box` | PF6 | release-4.14-t1 | Legacy | `.pf-c-modal-box` |
| `[data-test="x"]` | (agnostic) | release-4.15 | PF5 | `[data-test="x"]` (no change) |

### Phase 2: Apply to Each Target

For each target branch (newest to oldest):

1. **Create a working branch**:
   ```bash
   git checkout -B cypress-fix/<target-branch> origin/<target-branch>
   ```

2. **Apply the changes manually** (NOT git cherry-pick — PF adaptation needed):
   - For each changed file, read the source version and target version
   - Apply the logical change with PF-adapted selectors
   - If the target file structure differs significantly, adapt manually

3. **Validate PF consistency** — no selectors from the wrong era:
   ```bash
   # Example for PF5 branch
   rg '\.pf-v6-c-' cypress/views/ --type ts  # should find 0 matches
   rg '\.pf-c-[a-z]' cypress/views/ --type ts  # should find 0 matches (no legacy)
   ```

4. **Lint**:
   ```bash
   npx eslint --fix cypress/
   ```

5. **Commit** with reference to source:
   ```bash
   git commit -m "$(cat <<'EOF'
   fix(cypress): <description>

   Cherry-picked from <source-branch> (<commit-sha-short>)
   Adapted PF selectors from <source-era> to <target-era>
   EOF
   )"
   ```

### Phase 3: Handle Tier-Split Branches

For tier-split versions (4.12–4.14), apply the fix to all sub-branches:

1. **Determine which sub-branches need the fix**:
   - If the fix is in `views/` or `support/` → all sub-branches need it
   - If the fix is in `tests/tier1/` → only `-t1` branches
   - If the fix is in `tests/gating/` → only `-gating` branches
   - If the fix is in `tests/tier2/` → only `-t2` branches

2. **Apply the same fix** to each relevant sub-branch
3. **The PF era is the same** across all sub-branches of the same version

### Phase 4: Summary

```markdown
## Cherry-Pick Summary

| # | Target Branch | PF Era | Status | PF Adaptations | Files Changed |
|---|--------------|--------|--------|----------------|---------------|
| 1 | release-4.20 | PF6 | Applied | None (same era) | 2 |
| 2 | release-4.19 | PF6 | Applied | None (same era) | 2 |
| 3 | release-4.18 | PF5 | Applied | 3 selectors | 2 |
| 4 | release-4.17 | PF5 | Applied | 3 selectors | 2 |
| 5 | release-4.16 | PF5 | Applied | 3 selectors | 2 |
| 6 | release-4.15 | PF5 | Applied | 3 selectors | 2 |
| 7 | release-4.14-t1 | Legacy | Skipped | Test doesn't exist | 0 |
| 8 | release-4.13-t1 | Legacy | Applied | 3 selectors | 2 |
| 9 | release-4.12-t1 | Legacy | Applied | 3 selectors | 2 |
```

---

## Important Rules

- **Never use `git cherry-pick` directly** — PF selectors must be adapted per branch
- **Apply from newest to oldest** — fixes are easier to adapt downward
- **Skip branches where the test doesn't exist** — don't add tests to old branches
- **Validate PF consistency** after each application
- **For tier-split branches**, determine which sub-branches are affected based on the changed file paths
- **DO NOT push** unless the user explicitly requests it
- **Commit each branch separately** — one commit per target branch
- **Reference the source** in commit messages for traceability
