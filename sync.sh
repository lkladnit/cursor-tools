#!/usr/bin/env bash
# cursor-tools sync.sh — bidirectional sync between project repos and ~/.cursor/
# Usage:
#   ./sync.sh harvest [--ns <namespace>] [--force]
#   ./sync.sh deploy  [--ns <namespace>] [--force]
#   ./sync.sh status

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACES_DIR="$SCRIPT_DIR/namespaces"
REGISTRY="$SCRIPT_DIR/registry.json"
CURSOR_RULES="$HOME/.cursor/rules"
CURSOR_COMMANDS="$HOME/.cursor/commands"
CURSOR_SKILLS="$HOME/.cursor/skills"
CURSOR_SKILLS_CURSOR="$HOME/.cursor/skills-cursor"
SEP="--"

# ── helpers ──────────────────────────────────────────────────────────────────

red()    { printf '\033[31m%s\033[0m\n' "$*"; }
green()  { printf '\033[32m%s\033[0m\n' "$*"; }
yellow() { printf '\033[33m%s\033[0m\n' "$*"; }
info()   { printf '  %s\n' "$*"; }

expandpath() { echo "${1/\~/$HOME}"; }

# Copy file only if src is newer than dst (or --force)
copy_if_newer() {
  local src="$1" dst="$2" force="${3:-false}"
  if [[ ! -f "$src" ]]; then return; fi
  if [[ "$force" == "true" ]] || [[ ! -f "$dst" ]] || [[ "$src" -nt "$dst" ]]; then
    cp "$src" "$dst"
    echo "  copied: $(basename "$src")"
  fi
}

# Copy directory recursively if src is newer
copy_dir_if_newer() {
  local src="$1" dst="$2" force="${3:-false}"
  if [[ ! -d "$src" ]]; then return; fi
  mkdir -p "$dst"
  if [[ "$force" == "true" ]]; then
    cp -r "$src/." "$dst/"
    echo "  copied dir: $(basename "$src")"
  else
    rsync -a --update "$src/" "$dst/"
    echo "  synced dir: $(basename "$src")"
  fi
}

# ── harvest ──────────────────────────────────────────────────────────────────
# Copy tools from a project's .cursor/ into namespaces/<ns>/

harvest_ns() {
  local ns="$1" force="${2:-false}"
  local ns_dir="$NAMESPACES_DIR/$ns"

  # Read registry for this namespace
  local canonical_dir scope
  canonical_dir=$(python3 -c "import json; d=json.load(open('$REGISTRY')); print(d['namespaces']['$ns']['canonical_dir'])" 2>/dev/null || echo "")
  scope=$(python3 -c "import json; d=json.load(open('$REGISTRY')); print(d['namespaces']['$ns']['scope'])" 2>/dev/null || echo "")

  if [[ -z "$canonical_dir" ]]; then
    red "Unknown namespace: $ns"
    return 1
  fi

  canonical_dir=$(expandpath "$canonical_dir")
  local cursor_dir="$canonical_dir/.cursor"

  echo ""
  yellow "harvest $ns  ← $cursor_dir"

  # Rules
  if [[ -d "$cursor_dir/rules" ]]; then
    local project_only_rules
    project_only_rules=$(python3 -c "
import json
d = json.load(open('$REGISTRY'))
ns = d['namespaces'].get('$ns', {})
print(' '.join(ns.get('project_only_rules', [])))" 2>/dev/null || echo "")

    mkdir -p "$ns_dir/rules"
    for f in "$cursor_dir/rules/"*.mdc; do
      [[ -f "$f" ]] || continue
      fname=$(basename "$f")
      # Skip project-only rules from versioning
      if echo "$project_only_rules" | grep -qw "$fname"; then
        info "skip (project-only): $fname"
        continue
      fi
      copy_if_newer "$f" "$ns_dir/rules/$fname" "$force"
    done
    # Handle subdirs (gh_kubevirt_plugin uses agents/ and workflows/)
    for subdir in "$cursor_dir/rules/"/*/; do
      [[ -d "$subdir" ]] || continue
      subdirname=$(basename "$subdir")
      mkdir -p "$ns_dir/rules/$subdirname"
      for f in "$subdir"*.mdc; do
        [[ -f "$f" ]] || continue
        copy_if_newer "$f" "$ns_dir/rules/$subdirname/$(basename "$f")" "$force"
      done
    done
  fi

  # Commands
  if [[ -d "$cursor_dir/commands" ]]; then
    mkdir -p "$ns_dir/commands"
    for f in "$cursor_dir/commands/"*.md; do
      [[ -f "$f" ]] || continue
      copy_if_newer "$f" "$ns_dir/commands/$(basename "$f")" "$force"
    done
  fi

  # Skills
  if [[ -d "$cursor_dir/skills" ]]; then
    mkdir -p "$ns_dir/skills"
    for skill_dir in "$cursor_dir/skills/"/*/; do
      [[ -d "$skill_dir" ]] || continue
      skill_name=$(basename "$skill_dir")
      copy_dir_if_newer "$skill_dir" "$ns_dir/skills/$skill_name" "$force"
    done
  fi

  # cursor_meta special case: harvest from ~/.cursor directly
  if [[ "$ns" == "cursor_meta" ]]; then
    # karpathy-guidelines.mdc
    [[ -f "$HOME/.cursor/rules/karpathy-guidelines.mdc" ]] && \
      copy_if_newer "$HOME/.cursor/rules/karpathy-guidelines.mdc" "$ns_dir/rules/karpathy-guidelines.mdc" "$force"
    # skills-cursor
    copy_dir_if_newer "$HOME/.cursor/skills-cursor" "$ns_dir/skills-cursor" "$force"
    # universal-skills-manager
    [[ -d "$HOME/.cursor/skills/universal-skills-manager" ]] && \
      copy_dir_if_newer "$HOME/.cursor/skills/universal-skills-manager" "$ns_dir/skills/universal-skills-manager" "$force"
  fi

  # gl_kubevirt_ui: union from all 3 clones
  if [[ "$ns" == "gl_kubevirt_ui" ]]; then
    for extra_dir in "$HOME/dev/kubevirt-ui-cursor" "$HOME/dev/kubevirt-ui-pw"; do
      if [[ -d "$extra_dir/.cursor/commands" ]]; then
        echo "  merging commands from $(basename "$extra_dir")..."
        for f in "$extra_dir/.cursor/commands/"*.md; do
          [[ -f "$f" ]] || continue
          fname=$(basename "$f")
          if [[ ! -f "$ns_dir/commands/$fname" ]] || [[ "$force" == "true" ]]; then
            cp "$f" "$ns_dir/commands/$fname"
            info "added from $(basename "$extra_dir"): $fname"
          fi
        done
      fi
    done
  fi

  green "done: $ns"
}

# ── deploy ────────────────────────────────────────────────────────────────────
# Copy tools from namespaces/<ns>/ into ~/.cursor/

deploy_ns() {
  local ns="$1" force="${2:-false}"
  local ns_dir="$NAMESPACES_DIR/$ns"
  local scope
  scope=$(python3 -c "import json; d=json.load(open('$REGISTRY')); print(d['namespaces'].get('$ns',{}).get('scope',''))" 2>/dev/null || echo "")

  if [[ "$scope" == "project-only" ]]; then
    info "skip $ns (project-only scope)"
    return
  fi

  echo ""
  yellow "deploy $ns  → ~/.cursor/"

  # Rules: prefix each file with ns-- and remove any stale unprefixed duplicate
  if [[ -d "$ns_dir/rules" ]]; then
    mkdir -p "$CURSOR_RULES"
    for f in "$ns_dir/rules/"*.mdc; do
      [[ -f "$f" ]] || continue
      fname=$(basename "$f")
      if [[ "$fname" == "karpathy-guidelines.mdc" ]]; then
        copy_if_newer "$f" "$CURSOR_RULES/$fname" "$force"
      else
        copy_if_newer "$f" "$CURSOR_RULES/${ns}${SEP}${fname}" "$force"
        # Remove stale unprefixed duplicate if it exists
        [[ -f "$CURSOR_RULES/$fname" ]] && rm "$CURSOR_RULES/$fname" && echo "  removed stale unprefixed: $fname"
      fi
    done
    # Subdirs (agents/, workflows/, flat/)
    for subdir in "$ns_dir/rules/"/*/; do
      [[ -d "$subdir" ]] || continue
      for f in "$subdir"*.mdc; do
        [[ -f "$f" ]] || continue
        fname=$(basename "$f")
        copy_if_newer "$f" "$CURSOR_RULES/${ns}${SEP}${fname}" "$force"
        [[ -f "$CURSOR_RULES/$fname" ]] && rm "$CURSOR_RULES/$fname" && echo "  removed stale unprefixed: $fname"
      done
    done
  fi

  # Commands: prefix each file with ns-- and remove any stale unprefixed duplicate
  if [[ -d "$ns_dir/commands" ]]; then
    mkdir -p "$CURSOR_COMMANDS"
    for f in "$ns_dir/commands/"*.md; do
      [[ -f "$f" ]] || continue
      fname=$(basename "$f")
      copy_if_newer "$f" "$CURSOR_COMMANDS/${ns}${SEP}${fname}" "$force"
      [[ -f "$CURSOR_COMMANDS/$fname" ]] && rm "$CURSOR_COMMANDS/$fname" && echo "  removed stale unprefixed: $fname"
    done
  fi

  # Skills: copy flat as ns--skill-name/ (1 level deep — required for Cursor discovery)
  # Universal namespaces (cursor_meta) keep the original skill name without prefix
  if [[ -d "$ns_dir/skills" ]]; then
    for skill_dir in "$ns_dir/skills/"/*/; do
      [[ -d "$skill_dir" ]] || continue
      skill_name=$(basename "$skill_dir")
      if [[ "$ns" == "cursor_meta" ]]; then
        copy_dir_if_newer "$skill_dir" "$CURSOR_SKILLS/$skill_name" "$force"
      else
        copy_dir_if_newer "$skill_dir" "$CURSOR_SKILLS/${ns}${SEP}${skill_name}" "$force"
      fi
    done
  fi

  # cursor_meta: skills-cursor goes to ~/.cursor/skills-cursor/
  if [[ "$ns" == "cursor_meta" ]] && [[ -d "$ns_dir/skills-cursor" ]]; then
    copy_dir_if_newer "$ns_dir/skills-cursor" "$CURSOR_SKILLS_CURSOR" "$force"
  fi

  # Remove stale ns-subdir if it exists (from old deploy layout)
  [[ -d "$CURSOR_SKILLS/$ns" ]] && rm -rf "$CURSOR_SKILLS/$ns" && echo "  cleaned stale dir: skills/$ns"

  green "done: $ns"
}

# ── status ────────────────────────────────────────────────────────────────────

show_status() {
  echo ""
  yellow "cursor-tools namespace status"
  echo ""
  python3 - "$NAMESPACES_DIR" "$REGISTRY" << 'PYEOF'
import sys, os, json
from pathlib import Path

ns_dir = Path(sys.argv[1])
registry = json.load(open(sys.argv[2]))

print(f"  {'Namespace':<30} {'Scope':<12} {'Rules':>6} {'Cmds':>6} {'Skills':>7}")
print(f"  {'-'*30} {'-'*12} {'-'*6} {'-'*6} {'-'*7}")
for ns in sorted(os.listdir(ns_dir)):
    d = ns_dir / ns
    if not d.is_dir():
        continue
    scope = registry['namespaces'].get(ns, {}).get('scope', '?')
    rules  = sum(1 for _ in (d / 'rules').rglob('*.mdc')) if (d / 'rules').exists() else 0
    cmds   = len(list((d / 'commands').glob('*.md'))) if (d / 'commands').exists() else 0
    skills = sum(1 for p in (d / 'skills').iterdir() if p.is_dir()) if (d / 'skills').exists() else 0
    print(f"  {ns:<30} {scope:<12} {rules:>6} {cmds:>6} {skills:>7}")
print()
PYEOF
}

# ── main ──────────────────────────────────────────────────────────────────────

CMD="${1:-help}"
FILTER_NS=""
FORCE=false

shift || true
while [[ $# -gt 0 ]]; do
  case "$1" in
    --ns)   FILTER_NS="$2"; shift 2 ;;
    --force) FORCE=true; shift ;;
    *)      shift ;;
  esac
done

# Collect active (deployable) namespace names
ALL_DEPLOYABLE_NS=$(python3 -c "
import json
d = json.load(open('$REGISTRY'))
for ns, cfg in d['namespaces'].items():
    if cfg.get('scope') in ('deployable',):
        print(ns)
" 2>/dev/null || echo "")

case "$CMD" in
  harvest)
    if [[ -n "$FILTER_NS" ]]; then
      harvest_ns "$FILTER_NS" "$FORCE"
    else
      for ns in $ALL_DEPLOYABLE_NS; do
        harvest_ns "$ns" "$FORCE"
      done
    fi
    ;;
  deploy)
    if [[ -n "$FILTER_NS" ]]; then
      deploy_ns "$FILTER_NS" "$FORCE"
    else
      for ns in $ALL_DEPLOYABLE_NS; do
        deploy_ns "$ns" "$FORCE"
      done
    fi
    ;;
  status)
    show_status
    ;;
  *)
    echo "Usage:"
    echo "  ./sync.sh harvest [--ns <ns>] [--force]   # project .cursor/ → namespaces/"
    echo "  ./sync.sh deploy  [--ns <ns>] [--force]   # namespaces/ → ~/.cursor/"
    echo "  ./sync.sh status                           # show namespace tool counts"
    ;;
esac
