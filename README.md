# cursor-tools

Centralized store for Cursor rules, commands, and skills across all repos.
Single source of truth — one `make` command to sync everything to `~/.cursor/`.

## What this solves

Cursor tools (rules, commands, skills) drift across multiple repos and local clones.
This repo:
- **Harvests** tools from each project repo into versioned namespaces
- **Deploys** them to `~/.cursor/` with `ns--` prefixed filenames so they're available in every workspace
- **Bootstraps** a fresh machine in one command

## Quick start

```bash
git clone https://github.com/lkladnit/cursor-tools.git ~/dev/ai/cursor-tools
cd ~/dev/ai/cursor-tools
make setup        # clone external repos, build binaries, set env vars
make harvest      # pull latest tools from all project repos
make deploy       # push everything to ~/.cursor/
```

Then restart Cursor.

## Namespaces

Each namespace maps to one upstream repo. Tools are stored under `namespaces/<ns>/`.

| Namespace | Repo | Rules | Cmds | Skills |
|---|---|---:|---:|---:|
| `gl_kubevirt_ui` | `gitlab.cee.redhat.com/cnv-qe/kubevirt-ui` | 18 | 20 | 3 |
| `gl_cnv` | `gitlab.cee.redhat.com/contra/cnv` | — | — | 6 |
| `gh_kubevirt_plugin` | `github.com/kubevirt-ui/kubevirt-plugin` | 21 | 2 | — |
| `gh_ninja_agents` | `github.com/ninja-agents/ninja-agents` | 4 | — | — |
| `local_ai_ws` | `~/dev/ai` (workspace-level) | 6 | 2 | — |
| `cursor_meta` | `~/.cursor/` (user global) | 1 | — | 19 |

Naming convention: `forge_org_repo` — `gl_` GitLab · `gh_` GitHub · `local_` no-remote.

## Commands

```bash
make setup              # one-time bootstrap (safe to re-run)
make harvest            # all repos → namespaces/
make harvest NS=gl_cnv  # single namespace
make deploy             # namespaces/ → ~/.cursor/
make deploy NS=gl_cnv   # single namespace
make status             # show tool counts per namespace
```

## How deploy works

Rules and commands are copied to `~/.cursor/` with a namespace prefix:

```
namespaces/gl_kubevirt_ui/rules/orchestrator.mdc  →  ~/.cursor/rules/gl_kubevirt_ui--orchestrator.mdc
namespaces/gl_kubevirt_ui/commands/jira-task.md   →  ~/.cursor/commands/gl_kubevirt_ui--jira-task.md
namespaces/gl_cnv/skills/cluster-activate/        →  ~/.cursor/skills/gl_cnv/cluster-activate/
```

Universal rules (e.g. `karpathy-guidelines.mdc`) deploy without a prefix.

## External dependencies

Some MCP servers require additional repos to be cloned and built. `make setup` handles this automatically using `external_repos` entries in `registry.json`.

Currently:

| Dependency | Repo | Purpose |
|---|---|---|
| `kubevirt-ui-mcp` | `github.com/bmaio-redhat/kubevirt-ui-mcp` | Unified MCP server for kubevirt-ui (coverage, context, CI triage, cluster ops) |

After setup, add your tokens to `~/.bash_profile`:

```bash
export GITHUB_PAT=github_pat_...      # GitHub fine-grained PAT
export GITLAB_PAT=glpat-...           # gitlab.cee.redhat.com token (api scope)
```

## Deploy policy

| Rule type | Deployed globally? |
|---|---|
| `alwaysApply: false` role/agent rules | ✅ yes — with `ns--` prefix |
| `alwaysApply: true` project-context rules | ❌ no — stay in repo only |
| Cursor plugin tools | ❌ no — managed by Cursor plugin system |
| `mcp.json`, `settings.json` | ❌ no — always project-local |

See `ANALYSIS.md` for the full inventory and gap analysis.
