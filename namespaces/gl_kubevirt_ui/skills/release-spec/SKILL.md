# /release-spec Skill

**Trigger**: User types `/release-spec` followed by version(s) and optional flags.

## What this skill does

Reads and follows the `release-migration-handler.mdc` agent rule to update release-specific Playwright spec files under `playwright/tests/releases/`. All 10 spec files (4.12–4.21) already exist and are the source of truth. Updates are driven by live cluster failures and UI changes — never by re-reading Cypress source branches.

---

## Step 1: Read the agent rule

**Immediately** read the full rule file before doing anything else:

```
Read: /home/bmaio/Developer/Projects/kubevirt-ui/.cursor/rules/release-migration-handler.mdc
```

Follow all instructions in that rule for the rest of this session.

---

## Step 2: Parse the command

Extract from the user's message:

| Input pattern | Meaning |
|---|---|
| `/release-spec 4.21` | Update `release-4.21.spec.ts` |
| `/release-spec 4.19 4.20 4.21` | Update three spec files |
| `/release-spec --all` | Update all 10 spec files (4.12–4.21) |
| `/release-spec 4.21 --run` | Update then execute |
| `/release-spec 4.21 --diff` | Show git diff since last commit before updating |

The `--all` flag expands to versions: `4.12 4.13 4.14 4.15 4.16 4.17 4.18 4.19 4.20 4.21`.

---

## Step 3: Create/switch to a feature branch

**Before writing any file**, create or switch to a feature branch:

```bash
# Get username
git config user.email | cut -d@ -f1

# Single release
git checkout -b <username>/release-4.XX-update

# Multiple releases
git checkout -b <username>/release-update-4.XX-4.XX

# If the branch already exists
git checkout <branch-name>
```

Never modify spec files while on `main`.

---

## Step 4: For each requested version

All specs already exist — the update workflow always applies.

1. Read `.env` to confirm the cluster identity (`WEB_CONSOLE_URL`, `CLUSTER_URL`)
2. If `--diff` was passed, run `git diff HEAD playwright/tests/releases/release-4.XX.spec.ts` and present the report before making any changes
3. Run the spec against the live cluster to collect failures:
   ```bash
   npx playwright test --project="Release Specs" --grep "@release-4.XX" --config=playwright/playwright.config.ts
   ```
4. For each failure, use Playwright MCP to inspect the live UI:
   - Resize to 1920×1080
   - Navigate to the failing page
   - Take a snapshot to identify the current selector or behaviour
5. Fix the failing tests in the spec using what the live cluster shows — never re-sync from a Cypress branch
6. Re-run to verify fixes pass

---

## Step 5: Handle `--run`

After updating the spec file(s), execute:

```bash
npx playwright test \
  --project="Release Specs" \
  --grep "@release-4.XX" \
  --config=playwright/playwright.config.ts \
  --workers=1
```

Report pass/fail. If failures remain, continue the MCP inspection → fix → re-run cycle.

---

## Constraints (enforced by this skill)

- Output files: `playwright/tests/releases/release-4.XX.spec.ts` only
- One optional edit: `playwright/src/data-models/constants.ts`
- No new fixture files, no new helper files, no new page objects
- No imports from `@/page-objects/`
- Cypress test IDs (e.g., `ID(CNV-8839)`) preserved verbatim in test names
- Skipped tests stay as `test.skip` / `test.describe.skip` with a reason comment — never deleted
- **Never read from Cypress branches** — the spec file is the source of truth
