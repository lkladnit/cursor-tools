# Cursor Tools Centralization — Analysis

Full inventory of rules, commands, and skills across all repos in `~/dev/`, user global `~/.cursor/`,
and installed plugins. Mapped to namespace names for centralization into `cursor-tools`.

_Scanned: 2026-06-16 · ~/dev/ (12 .cursor dirs · 7 active namespaces) + ~/.cursor/ (cursor_meta + 3 plugins)_

---

## Summary

| Metric | Count |
|---|---|
| Repo namespaces | 7 |
| Repo rules (total) | 53 |
| Repo commands (union, deduped) | 24 |
| Repo skills | 9 |
| User meta-skills (`cursor_meta`) | 19 |
| Plugin-managed tools | 13 |
| **Gaps to fill in `~/.cursor/`** | **6** |

---

## Namespace Naming Convention

- **Repos**: `forge_org_repo` — `gl_` for GitLab, `gh_` for GitHub, `local_` for no-remote
- **User global**: `cursor_meta` — tools in `~/.cursor/` that are user-managed and universal
- **Plugins**: `plugin_name` — Cursor plugin marketplace installs
- **Multiple local clones of the same remote** collapse to one namespace (e.g. three `kubevirt-ui` clones → `gl_kubevirt_ui`)
- **Workspace-level `.cursor/`** spanning sub-projects uses `_ws` suffix (e.g. `local_ai_ws`)

---

## Namespace Registry

### Repos

| Namespace | Forge | Remote repo | Local dir(s) | Rules | Cmds | Skills | MCP | Notes |
|---|---|---|---|---:|---:|---:|:---:|---|
| `gl_kubevirt_ui` | GitLab RH | `cnv-qe/kubevirt-ui` | kubevirt-ui, kubevirt-ui-cursor, kubevirt-ui-pw | 18 | 20 | 3 | ✔ | 3 local clones — commands drifted (20 in union) |
| `gl_cnv` | GitLab RH | `contra/cnv` | cnv | — | — | 6 | — | Skills only — none in `~/.cursor/` yet |
| `gh_kubevirt_plugin` | GitHub | `kubevirt-ui/kubevirt-plugin` | kubevirt-plugin | 22 | 2 | — | — | Uses `rules/agents/` + `rules/workflows/` subdirs |
| `gh_ninja_agents` | GitHub | `ninja-agents/ninja-agents` | ninja-agents | 5 | — | — | ✔ | 1 context rule + 4 deployable role rules |
| `gh_networking_console` | GitHub | `openshift/networking-console-plugin` | networking-console-plugin | 1 | — | — | — | Single `alwaysApply:true` context rule — keep in repo |
| `gh_nmstate_console` | GitHub | `openshift/nmstate-console-plugin` | nmstate-console-plugin | 1 | — | — | — | Single `alwaysApply:true` context rule — keep in repo |
| `local_ai_ws` | local workspace | `/dev/ai` (workspace-level) | `dev/ai/.cursor/` | 6 | 2 | — | — | Cypress, playwright, TS, google-sheets-mcp conventions |

### User Global + Plugins

| Namespace | Kind | Forge | Path | Rules | Cmds | Skills | MCP | Notes |
|---|---|---|---|---:|---:|---:|:---:|---|
| `cursor_meta` | **user** | `~/.cursor/` | `~/.cursor/` | 1 | — | 19 | — | `karpathy-guidelines.mdc` + 18 `skills-cursor` meta-skills + `universal-skills-manager` |
| `plugin_gitlab` | plugin | Cursor Plugin | `~/.cursor/plugins/cache/cursor-public/gitlab/` | 1 | 6 | 1 | — | `gitlab-workflow.mdc` + 6 commands + `gitlab-ci-author` skill |
| `plugin_atlassian` | plugin | Cursor Plugin | `~/.cursor/plugins/cache/cursor-public/atlassian/` | — | — | 5 | — | 5 Jira/Confluence skills (capture-tasks, generate-status-report, triage-issue…) |
| `plugin_slack` | plugin | Cursor Plugin | `~/.cursor/plugins/cache/cursor-public/slack/` | — | — | — | ✔ | MCP server only |

> **Plugins are Cursor-managed.** Do **not** version them in `cursor-tools` — update via Cursor's plugin system.

---

## Gap Analysis — What's Missing from `~/.cursor/`

Legend: ✅ deployed · ❌ missing · ⚠ partial · — intentionally excluded

| Tool set | Type | In `~/.cursor/`? | Action |
|---|---|:---:|---|
| `gl_kubevirt_ui` rules (18) | rules | ✅ | None — already present |
| `gl_kubevirt_ui` commands — 16 of 20 | commands | ⚠ | Add 4 drifted: `cypress-cherry-pick`, `expand-tests`, `release-migration`, `update-from-summary` |
| `gl_kubevirt_ui` skills (3) | skills | ✅ | None — api-cross-check, jenkins-failure-diagnosis, release-spec present |
| **`gl_cnv` skills (6)** | skills | ❌ | Copy to `~/.cursor/skills/gl_cnv/` ← biggest gap |
| **`gh_kubevirt_plugin` role rules (21 of 22)** | rules | ❌ | Deploy `agents/` + `workflows/` rules with `gh_kubevirt_plugin--` prefix; keep `project-context.mdc` in repo |
| **`gh_kubevirt_plugin` commands (2)** | commands | ❌ | Copy `review.md`, `triage.md` with `gh_kubevirt_plugin--` prefix |
| **`gh_ninja_agents` role rules (4 of 5)** | rules | ❌ | Deploy `jira-qe-story`, `repo-contextification`, `sprint-review`, `weekly-team-update`; keep `ninja-agents.mdc` in repo |
| `gh_networking_console` rule (1) | rules | — | Intentionally skip — `alwaysApply:true` project context |
| `gh_nmstate_console` rule (1) | rules | — | Intentionally skip — `alwaysApply:true` project context |
| **`local_ai_ws` rules (6)** | rules | ❌ | Copy with `local_ai_ws--` prefix |
| `local_ai_ws` commands (2) | commands | ⚠ | Review vs existing `jenkins-fix-cycle-cy.md` before adding |
| `cursor_meta` — `karpathy-guidelines` | rules | ✅ | Version in `cursor-tools/namespaces/cursor_meta/rules/` |
| `cursor_meta` — `skills-cursor` (18) | skills | ✅ | Version in `cursor-tools/namespaces/cursor_meta/skills-cursor/` |
| `plugin_*` (all) | mixed | — | Cursor-managed — do not version in cursor-tools |

---

## Command Drift — `gl_kubevirt_ui` (3 clones)

12 commands fully synced. 4 missing from global (in cursor/pw clones only). 4 in kubevirt-ui+global but not the other clones.

| Command | kubevirt-ui | kubevirt-ui-cursor | kubevirt-ui-pw | `~/.cursor/` | Status |
|---|:---:|:---:|:---:|:---:|---|
| `bug-hunt.md` | ✔ | ✔ | ✔ | ✔ | synced |
| `cnv-exploration.md` | ✔ | ✔ | ✔ | ✔ | synced |
| `code-cleanup.md` | ✔ | ✔ | ✔ | ✔ | synced |
| `commit-cnv-tests.md` | ✔ | ✔ | ✔ | ✔ | synced |
| `debug-test.md` | ✔ | ✔ | ✔ | ✔ | synced |
| `health-check.md` | ✔ | ✔ | ✔ | ✔ | synced |
| `jenkins-fix-cycle-cy.md` | ✔ | ✔ | ✔ | ✔ | synced |
| `jenkins-fix-cycle-pw.md` | ✔ | ✔ | ✔ | ✔ | synced |
| `jira-task.md` | ✔ | ✔ | ✔ | ✔ | synced |
| `mcp-validate.md` | ✔ | ✔ | ✔ | ✔ | synced |
| `test-fix-cycle-cy.md` | ✔ | ✔ | ✔ | ✔ | synced |
| `test-fix-cycle-pw.md` | ✔ | ✔ | ✔ | ✔ | synced |
| `qe-dev.md` | ✔ | — | ✔ | ✔ | partial |
| `product-analysis.md` | ✔ | — | — | ✔ | partial |
| `test-fix-cycle.md` | ✔ | — | — | ✔ | partial |
| `ticket-lifecycle.md` | ✔ | — | — | ✔ | partial |
| `cypress-cherry-pick.md` | — | ✔ | ✔ | — | **missing from global** |
| `expand-tests.md` | — | ✔ | ✔ | — | **missing from global** |
| `release-migration.md` | — | ✔ | ✔ | — | **missing from global** |
| `update-from-summary.md` | — | ✔ | ✔ | — | **missing from global** |

**Resolution:** `cursor-tools` holds the canonical union of all 20. All three clones sync from there.

---

## Proposed `cursor-tools` Layout

### Source of truth (cursor-tools repo)

```
cursor-tools/
  namespaces/
    gl_kubevirt_ui/
      rules/            # 18 files
      commands/         # 20 files (union of 3 clones)
      skills/
        api-cross-check/
        jenkins-failure-diagnosis/
        release-spec/
    gl_cnv/
      skills/           # 6 dirs
    gh_kubevirt_plugin/
      rules/
        agents/         # 5 role rules
        workflows/      # 8 workflow rules
        flat/           # 9 flat rules
      commands/         # review.md, triage.md
    gh_ninja_agents/
      rules/            # 4 role rules (excl. ninja-agents.mdc context rule)
    local_ai_ws/
      rules/            # 6 convention files
      commands/         # 2 jenkins commands
    cursor_meta/
      rules/            # karpathy-guidelines.mdc
      skills-cursor/    # 18 Cursor meta-skills
      skills/           # universal-skills-manager
  registry.json         # namespace → local dir(s) + scope flags
  sync.sh               # harvest + deploy implementation
  Makefile              # user-facing targets
```

### `~/.cursor/` after full deploy

```
~/.cursor/
  rules/
    # Universal (alwaysApply:true, no ns prefix)
    karpathy-guidelines.mdc
    # Auto-injected by plugins
    gitlab-workflow.mdc                          ← plugin_gitlab

    # Namespaced role rules (alwaysApply:false, agent-requestable)
    gl_kubevirt_ui--orchestrator.mdc
    gl_kubevirt_ui--qa-architect.mdc             # … 18 total
    gh_kubevirt_plugin--developer.mdc
    gh_kubevirt_plugin--feature-development.mdc  # … 21 total
    gh_ninja_agents--sprint-review.mdc
    gh_ninja_agents--jira-qe-story.mdc           # … 4 total
    local_ai_ws--cypress-conventions.mdc
    local_ai_ws--typescript-patterns.mdc         # … 6 total

  commands/
    gl_kubevirt_ui--jira-task.md
    gl_kubevirt_ui--cypress-cherry-pick.md       ← new
    gl_kubevirt_ui--expand-tests.md              ← new
    gl_kubevirt_ui--release-migration.md         ← new
    gl_kubevirt_ui--update-from-summary.md       ← new
    gh_kubevirt_plugin--review.md
    gh_kubevirt_plugin--triage.md
    local_ai_ws--jenkins-fix-cycle-cy.md
    # + 6 from plugin_gitlab (auto-injected)

  skills/
    gl_kubevirt_ui/                              # 3 skills
    gl_cnv/                                      ← new (6 skills)
  skills-cursor/                                 # 18 meta-skills (unchanged)
  plugins/                                       # Cursor-managed, never touched
```

---

## Sync Strategy — Bidirectional, User-Triggered

### `harvest`  (repo `.cursor/` → `cursor-tools/namespaces/`)

Reads `registry.json` to find the authoritative local dir for each namespace, copies
`.cursor/rules/`, `commands/`, `skills/` into `namespaces/<ns>/`.
- Conflict: newer mtime wins (or `--force`)
- Multi-clone namespaces (`gl_kubevirt_ui`): takes union, warns on conflicts

```bash
make harvest NS=gl_kubevirt_ui
make harvest-all
```

### `deploy`  (`cursor-tools/namespaces/` → `~/.cursor/`)

Copies all files from `namespaces/` into `~/.cursor/`, prefixing rule and command filenames
with `ns--`. Skills go into `~/.cursor/skills/<ns>/`. Rules flagged `project-only` and all
`plugin_*` namespaces are skipped.

```bash
make deploy
make deploy NS=gl_cnv
```

### Never harvested or deployed

| Tool | Reason |
|---|---|
| `gh_networking_console/networking-console-plugin.mdc` | `alwaysApply:true` project context |
| `gh_nmstate_console/nmstate-console-plugin.mdc` | Same |
| `gh_ninja_agents/ninja-agents.mdc` | Same |
| `gh_kubevirt_plugin/project-context.mdc` | Same |
| `plugin_*` (all) | Cursor-managed — never copy plugin cache |
| `.cursor/mcp.json`, `settings.json` | Always project-local |

---

## MCP Server Inventory

### Sources scanned

| Source | File |
|---|---|
| Global | `~/.cursor/mcp.json` |
| `gl_kubevirt_ui` | `kubevirt-ui/.cursor/mcp.json` |
| `gh_ninja_agents` | `ninja-agents/.cursor/mcp.json` |
| `plugin_atlassian` | `~/.cursor/plugins/cache/.../atlassian/.mcp.json` |
| `plugin_gitlab` | `~/.cursor/plugins/cache/.../gitlab/.mcp.json` |
| `plugin_slack` | `~/.cursor/plugins/cache/.../slack/mcp.json` |

### Full comparison matrix

| Server | Global | kubevirt-ui | ninja-agents | plugin_atlassian | plugin_gitlab | plugin_slack |
|---|:---:|:---:|:---:|:---:|:---:|:---:|
| `github` | ✔ http | — | ✔ http | — | — | — |
| `gitlab-rh` | ✔ stdio | — | ✔ stdio (was `gitlab`) | — | — | — |
| `GitLab` (gitlab.com) | — | — | — | — | ✔ http | — |
| `atlassian` | — | — | ✔ http | ✔ http | — | — |
| `slack` | — | — | — | — | — | ✔ http |
| `Playwright` (+ignore-https-errors) | — | ✔ stdio | — | — | — | — |
| `playwright` | ✔ stdio | — | — | — | — | — |
| `kubevirt-ui-mcp` | — | ✔ stdio | — | — | — | — |
| `jenkins-failure-diagnosis` | ✔ stdio | — | — | — | — | — |
| `reportportal` | ✔ stdio | — | — | — | — | — |
| `jira` | ✔ stdio | — | — | — | — | — |
| `confluence` | ✔ stdio | — | — | — | — | — |
| `polarion` | ✔ stdio | — | — | — | — | — |
| `google-sheets` | ✔ stdio | — | — | — | — | — |
| `gmail` | ✔ stdio | — | — | — | — | — |
| `google-docs` | ✔ stdio | — | — | — | — | — |
| `cypress` | ✔ stdio | — | — | — | — | — |

### Changes made

| Change | Reason |
|---|---|
| Added `github` to `~/.cursor/mcp.json` | Official GitHub MCP via `https://api.githubcopilot.com/mcp/`; PAT hardcoded in header (Cursor does not expand `${ENV_VAR}` in HTTP headers) |
| Added `gitlab-rh` to `~/.cursor/mcp.json` | Red Hat self-hosted GitLab at `gitlab.cee.redhat.com`; uses `${GITLAB_PAT}` via env block |

### Required env vars (`~/.bash_profile`)

| Env var | Server | Notes |
|---|---|---|
| `GITHUB_PAT` | `github` | Hardcoded in mcp.json header (HTTP servers don't expand env vars) |
| `GITLAB_PAT` | `gitlab-rh` | Expanded via `env` block (stdio servers do expand env vars) |
