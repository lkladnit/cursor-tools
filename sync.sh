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

  # Rules: deploy with SHORT name (no prefix) — Cursor surfaces them by filename in / menu
  # Collisions: last namespace deployed wins (see registry.json deploy order)
  if [[ -d "$ns_dir/rules" ]]; then
    mkdir -p "$CURSOR_RULES"
    for f in "$ns_dir/rules/"*.mdc; do
      [[ -f "$f" ]] || continue
      fname=$(basename "$f")
      copy_if_newer "$f" "$CURSOR_RULES/$fname" "$force"
      # Remove any stale prefixed version from a previous deploy
      [[ -f "$CURSOR_RULES/${ns}${SEP}${fname}" ]] && rm "$CURSOR_RULES/${ns}${SEP}${fname}" && echo "  removed stale prefixed: ${ns}${SEP}${fname}"
    done
    # Subdirs (agents/, workflows/, flat/)
    for subdir in "$ns_dir/rules/"/*/; do
      [[ -d "$subdir" ]] || continue
      for f in "$subdir"*.mdc; do
        [[ -f "$f" ]] || continue
        fname=$(basename "$f")
        copy_if_newer "$f" "$CURSOR_RULES/$fname" "$force"
        [[ -f "$CURSOR_RULES/${ns}${SEP}${fname}" ]] && rm "$CURSOR_RULES/${ns}${SEP}${fname}" && echo "  removed stale prefixed: ${ns}${SEP}${fname}"
      done
    done
  fi

  # Commands: deploy with SHORT name (no prefix) — humans type these via /
  # Collisions: last namespace deployed wins (see registry.json deploy order)
  if [[ -d "$ns_dir/commands" ]]; then
    mkdir -p "$CURSOR_COMMANDS"
    for f in "$ns_dir/commands/"*.md; do
      [[ -f "$f" ]] || continue
      fname=$(basename "$f")
      copy_if_newer "$f" "$CURSOR_COMMANDS/$fname" "$force"
      # Remove any stale prefixed version that may exist from a previous deploy
      [[ -f "$CURSOR_COMMANDS/${ns}${SEP}${fname}" ]] && rm "$CURSOR_COMMANDS/${ns}${SEP}${fname}" && echo "  removed stale prefixed: ${ns}${SEP}${fname}"
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

# ── scan ─────────────────────────────────────────────────────────────────────
# Discover all .cursor/ dirs under ~/dev/ and report unregistered ones.
# --register  : auto-add unregistered dirs to registry.json (scope=deployable)

scan_dev() {
  local do_register="${1:-false}"

  python3 - "$SCRIPT_DIR" "$do_register" << 'PYEOF'
import sys, os, json, subprocess, re
from pathlib import Path

SCRIPT_DIR  = Path(sys.argv[1])
DO_REGISTER = sys.argv[2] == "true"
REGISTRY    = SCRIPT_DIR / "registry.json"
DEV         = Path.home() / "dev"

registry = json.load(open(REGISTRY))
known_dirs = set()
for ns, cfg in registry["namespaces"].items():
    for d in cfg.get("local_dirs", []):
        known_dirs.add(str(Path(d.replace("~", str(Path.home()))).resolve()))

def get_remote(path):
    try:
        r = subprocess.run(["git","-C",str(path),"remote","get-url","origin"],
                           capture_output=True, text=True, timeout=3)
        return r.stdout.strip().replace("oauth2:"+r.stdout.split("@")[0].split("oauth2:")[1]+"@", "") \
               if "oauth2:" in r.stdout else r.stdout.strip()
    except Exception:
        return ""

def suggest_ns(path, remote):
    name = Path(path).name.replace("-","_").replace(".","_")
    if not remote:
        return f"local_{name}"
    if "github.com" in remote:
        repo = re.sub(r"\.git$","", remote.split("/")[-1]).replace("-","_")
        return f"gh_{repo}"
    if "gitlab" in remote:
        repo = re.sub(r"\.git$","", remote.split("/")[-1]).replace("-","_")
        return f"gl_{repo}"
    return f"local_{name}"

def count_tools(cursor_dir):
    p = Path(cursor_dir)
    rules  = len(list((p/"rules").rglob("*.mdc")))  if (p/"rules").exists()    else 0
    cmds   = len(list((p/"commands").glob("*.md")))  if (p/"commands").exists() else 0
    skills = sum(1 for x in (p/"skills").iterdir() if x.is_dir()) \
             if (p/"skills").exists() else 0
    return rules, cmds, skills

# Find all .cursor dirs up to depth 3
found = []
for depth in [1, 2]:
    pattern = "/".join(["*"] * depth) + "/.cursor"
    for cursor_dir in DEV.glob(pattern):
        proj_dir = cursor_dir.parent
        resolved = str(proj_dir.resolve())
        rules, cmds, skills = count_tools(cursor_dir)
        if rules + cmds + skills == 0:
            continue  # skip empty .cursor dirs
        remote = get_remote(proj_dir)
        ns = suggest_ns(proj_dir, remote)
        registered = resolved in known_dirs
        found.append({
            "path": str(proj_dir),
            "resolved": resolved,
            "remote": remote or "(no remote)",
            "ns": ns,
            "rules": rules, "cmds": cmds, "skills": skills,
            "registered": registered,
        })

new_entries = {}

print()
print(f"  {'Path':<45} {'Namespace':<28} {'R':>3} {'C':>3} {'S':>3}  Status")
print(f"  {'-'*45} {'-'*28} {'-'*3} {'-'*3} {'-'*3}  ------")
for item in sorted(found, key=lambda x: x["path"]):
    status = "registered" if item["registered"] else "NEW"
    marker = "  " if item["registered"] else "→ "
    short  = item["path"].replace(str(Path.home()), "~")
    print(f"  {marker}{short:<43} {item['ns']:<28} {item['rules']:>3} {item['cmds']:>3} {item['skills']:>3}  {status}")
    if not item["registered"]:
        new_entries[item["ns"]] = item

print()

if not new_entries:
    print("  All .cursor workspaces are already registered.")
    sys.exit(0)

if not DO_REGISTER:
    print(f"  {len(new_entries)} unregistered workspace(s). Run with --register to add them.")
    sys.exit(0)

# Register new entries
print("  Registering new namespaces...")
for ns, item in new_entries.items():
    rel = "~" + item["path"][len(str(Path.home())):]
    tools = []
    if item["rules"]:  tools.append("rules")
    if item["cmds"]:   tools.append("commands")
    if item["skills"]: tools.append("skills")
    registry["namespaces"][ns] = {
        "remote": None if item["remote"] == "(no remote)" else item["remote"],
        "local_dirs": [rel],
        "canonical_dir": rel,
        "scope": "deployable",
        "tools": tools,
        "note": "auto-registered by scan"
    }
    print(f"    added: {ns}  ({rel})")

with open(REGISTRY, "w") as f:
    json.dump(registry, f, indent=2)
print()
print("  registry.json updated. Run 'make harvest' to pull tools.")
PYEOF
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
  scan)
    scan_dev "$FORCE"
    ;;
  status)
    show_status
    ;;
  *)
    echo "Usage:"
    echo "  ./sync.sh scan                             # discover unregistered .cursor/ dirs in ~/dev/"
    echo "  ./sync.sh scan --force                     # discover + register new ones in registry.json"
    echo "  ./sync.sh harvest [--ns <ns>] [--force]   # project .cursor/ → namespaces/"
    echo "  ./sync.sh deploy  [--ns <ns>] [--force]   # namespaces/ → ~/.cursor/"
    echo "  ./sync.sh status                           # show namespace tool counts"
    ;;
esac
