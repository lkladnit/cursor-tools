# Commit: Clean, Squash, and Commit Changes

Clean up debugging artifacts, squash all work into a single commit, and optionally push. Follows the Git Handler rules for the kubevirt-ui test repository.

## Input

The user invokes `/commit` with optional flags:

- **Default**: `/commit` — clean up, squash, commit
- **With push**: `/commit --push` — also push to remote after commit
- **With branch**: `/commit --branch=<name>` — create a new branch before committing
- **Amend last**: `/commit --amend` — amend the previous commit (only if unpushed and created in this session)

Examples:
```
/commit
/commit --push
/commit --branch=bmaio/fix-template-filters
/commit --push --branch=bmaio/cnv-82156-test
```

## Workflow

---

### Phase 1: Branch Guard and Setup

1. **Check current branch**:
   ```bash
   git branch --show-current
   ```
2. **If on `main`**: You MUST NOT commit to main. Either:
   - Use the `--branch` flag to create a new branch, OR
   - **Stop and ask** the user for a branch name before proceeding
3. **Resolve the git username**:
   ```bash
   GIT_USER=$(git config user.email | cut -d@ -f1)
   ```
4. **If `--branch` is provided**, create and switch to the new branch:
   ```bash
   git checkout -b <branch-name>
   ```
5. **If no branch flag and not on `main`**, stay on the current branch

---

### Phase 2: Pre-Commit Cleanup

Scan for and remove files that must not be committed. Use `git status` to identify candidates.

#### Artifacts to DELETE (always):

| Pattern | Description |
|---------|-------------|
| `playwright/scripts/validation-output/` | MCP validation recordings, screenshots |
| `playwright/scripts/cnv-*-validation.ts` | One-off validation/diagnostic scripts |
| `playwright/scripts/diagnostic-*.ts` | Debugging diagnostic scripts |
| `debug-screenshots/`, `retry-videos/` | Failure debugging media |
| `*.webm`, `*.png` under non-source dirs | Generated media in `allure-results/`, `test-results/` |
| `.test-config.json`, `.pids/` | Runtime state files |
| `blob-report/`, `playwright-report/` | Generated reports |
| `allure-results/`, `allure-report/` | Generated Allure output |
| `test-results/` | Playwright test output |
| `/tmp/debug-test.log`, `/tmp/health-check.log` | Command output logs |

#### Files to NEVER delete:

| Pattern | Description |
|---------|-------------|
| `playwright/src/**` | Source code (page objects, step drivers, clients, fixtures) |
| `playwright/tests/**` | Test specifications |
| `playwright/docs/**` | STD documentation |
| `playwright/project-dependencies/**` | Global setup/teardown |
| `playwright/playwright.config.ts` | Playwright configuration |
| `playwright/tsconfig.json` | TypeScript configuration |
| `.cursor/rules/*.mdc` | Agent rules |
| `.cursor/commands/*.md` | Agent commands |
| `CLAUDE.md`, `package.json`, `package-lock.json` | Project files |
| `.gitignore`, `.env.example` | Configuration templates |

#### Cleanup procedure:
1. Run `git status` to identify all untracked and modified files
2. Delete any artifacts found using the Delete tool
3. Verify `.gitignore` covers the artifact patterns — add entries if missing
4. Report what was cleaned up

---

### Phase 3: Lint and Auto-Fix

Run the linter **scoped to `playwright/`** with auto-fix to ensure all code passes formatting and style checks **before** committing. This prevents CI lint failures after push. Never run `npm run lint` unscoped — it includes the legacy `cypress/` directory which takes 10+ minutes and is irrelevant when only Playwright files have changed.

1. **Run `npx eslint playwright/ --fix`**:
   ```bash
   npx eslint playwright/ --fix
   ```
2. **If the linter modifies files**, they will appear as unstaged changes — this is expected and they will be included in the commit via `git add -A` in Phase 5.
3. **If the linter reports unfixable errors**, stop and report them to the user before proceeding.
4. **Run `npx eslint playwright/`** (without `--fix`) to confirm zero errors remain:
   ```bash
   npx eslint playwright/
   ```
   If errors remain, fix them manually before continuing.

---

### Phase 4: Review Changes

1. **Run `git diff --stat`** to see all files that will be committed (including lint fixes)
2. **Run `git status`** to see untracked files
3. **Scan for sensitive files** — warn if any of these are staged:
   - `.env` (credentials)
   - `.kubeconfigs/` (cluster access)
   - `.storage-states/` (auth tokens)
   - `.test-configs/` (runtime config with tokens)
   - `credentials.json`, `*.pem`, `*.key`
4. **Present the file list** to confirm before committing

---

### Phase 5: Squash Commit

All changes since the branch diverged from `main` must be in **one commit**.

1. **Count existing unpushed commits**:
   ```bash
   git rev-list --count origin/main..HEAD
   ```
2. **If prior commits exist** (count > 0): soft reset and re-commit:
   ```bash
   git add -A
   git reset --soft origin/main
   git commit -m "$(cat <<'EOF'
   <commit message>
   EOF
   )"
   ```
3. **If no prior commits** (count = 0 or fresh branch): simple add and commit:
   ```bash
   git add -A
   git commit -m "$(cat <<'EOF'
   <commit message>
   EOF
   )"
   ```

### Commit Message Format

Follow the repository convention:

```
<type>: <summary in imperative mood, ≤72 chars>

- Bullet point for each logical change area
- Reference Jira IDs when applicable (CNV-XXXXX)
- Mention affected layers (PO, SD, spec, STD)
```

**Types**: `fix:`, `feat:`, `refactor:`, `test:`, `docs:`, `chore:`

**Examples**:
```
fix: stabilize CNV-74220 hideYamlTab toggle with API-level reset

- Add waitForResponse after toggle click in overview-page.ts
- Wrap test in try/finally with pre/post API reset
- Use expect.toPass polling for configmap verification
```

```
feat: add CNV-82156 storage migration plan redirect validation

- Extend virtual-machines-page.ts with migration plan navigation
- Add redirect URL assertion to vm-migrate-storage.spec.ts
- Update vm-actions STD with new test step
```

### Deriving the commit message

1. **Read the diff** — analyze what actually changed across all files
2. **Identify the primary intent** — is this a fix, feature, refactor, or test addition?
3. **Group changes by area** — page objects, step drivers, specs, docs
4. **Write the summary** — focus on the "why", not the "what"
5. **Add bullet points** — one per logical change, mention Jira IDs

---

### Phase 6: Post-Commit Verification

1. **Run `git status`** — verify clean working tree
2. **Run `git log --oneline -3`** — verify the commit looks correct
3. **Run `git diff --stat origin/main..HEAD`** — verify the full changeset

---

### Phase 7: Push (if `--push` specified)

Only if the user passed `--push`:

```bash
git push -u origin HEAD
```

Report the remote URL and any MR creation link.

---

## Safety Rules

- **NEVER commit directly to `main`** — always use a feature branch. If on `main`, stop and ask for a branch name.
- **NEVER force push to `main`** — no exceptions whatsoever. If a bad commit reaches `main`, revert it with a new commit.
- **NEVER force push** (`--force`, `--force-with-lease`) to any branch unless the user explicitly requests it
- **NEVER commit** `.env`, `.kubeconfigs/`, `.storage-states/`, `.test-configs/`, `allure-results/`
- **NEVER amend** a commit that has been pushed to remote
- **NEVER amend** a commit not created by you in this session
- **NEVER push** unless `--push` is specified or the user explicitly asks
- **NEVER update git config** (user.name, user.email, etc.)
- **NEVER skip hooks** (`--no-verify`)
- If in doubt about whether a file should be committed, ask the user
- If sensitive files are detected, warn and ask before proceeding
