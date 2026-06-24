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

# ── shared helpers (Python) ───────────────────────────────────────────────────

_py_helpers='
import subprocess, re
from pathlib import Path

def get_remote(path):
    try:
        r = subprocess.run(["git","-C",str(path),"remote","get-url","origin"],
                           capture_output=True, text=True, timeout=3)
        raw = r.stdout.strip()
        if not raw: return ""
        if "oauth2:" in raw:
            raw = re.sub(r"oauth2:[^@]+@", "", raw)
        return raw
    except Exception:
        return ""

def suggest_ns(path, remote):
    name = Path(path).name.replace("-","_").replace(".","_")
    if not remote:
        return f"local_{name}"
    if "github.com" in remote:
        repo = re.sub(r"[.]git$","", remote.split("/")[-1]).replace("-","_")
        return f"gh_{repo}"
    if "gitlab" in remote:
        repo = re.sub(r"[.]git$","", remote.split("/")[-1]).replace("-","_")
        return f"gl_{repo}"
    return f"local_{name}"

def count_tools(cursor_dir):
    p = Path(cursor_dir)
    rules  = len(list((p/"rules").rglob("*.mdc")))  if (p/"rules").exists()    else 0
    cmds   = len(list((p/"commands").glob("*.md")))  if (p/"commands").exists() else 0
    skills = sum(1 for x in (p/"skills").iterdir() if x.is_dir()) \
             if (p/"skills").exists() else 0
    mcp    = (p/"mcp.json").exists()
    return rules, cmds, skills, mcp

def known_dirs(registry):
    s = set()
    for ns, cfg in registry["namespaces"].items():
        for d in cfg.get("local_dirs", []):
            s.add(str(Path(d.replace("~", str(Path.home()))).resolve()))
    return s

def rel_path(p):
    return "~" + str(p)[len(str(Path.home())):]
'

# ── scan ─────────────────────────────────────────────────────────────────────
# Scan a directory (default ~/dev/) for .cursor/ dirs and report unregistered ones.
# Usage: ./sync.sh scan [path] [--force]
#   path     : directory to scan (default ~/dev/)
#   --force  : auto-register unregistered dirs in registry.json

scan_dev() {
  local scan_path="${1:-$HOME/dev}"
  local do_register="${2:-false}"
  scan_path=$(expandpath "$scan_path")

  python3 - "$SCRIPT_DIR" "$scan_path" "$do_register" << PYEOF
import sys, os, json
from pathlib import Path
exec("""$_py_helpers""")

SCRIPT_DIR  = Path(sys.argv[1])
SCAN_PATH   = Path(sys.argv[2]).expanduser()
DO_REGISTER = sys.argv[3] == "true"
REGISTRY    = SCRIPT_DIR / "registry.json"

registry = json.load(open(REGISTRY))
known    = known_dirs(registry)

found = []
for depth in [1, 2]:
    pattern = "/".join(["*"] * depth) + "/.cursor"
    for cursor_dir in SCAN_PATH.glob(pattern):
        proj_dir = cursor_dir.parent
        resolved = str(proj_dir.resolve())
        rules, cmds, skills, mcp = count_tools(cursor_dir)
        remote = get_remote(proj_dir)
        ns     = suggest_ns(proj_dir, remote)
        tools_label = f"R={rules} C={cmds} S={skills}" + (" mcp" if mcp else "")
        found.append({
            "path": str(proj_dir), "resolved": resolved,
            "remote": remote or "(no remote)", "ns": ns,
            "rules": rules, "cmds": cmds, "skills": skills, "mcp": mcp,
            "registered": resolved in known,
        })

new_entries = {}
print()
print(f"  {'Path':<45} {'Namespace':<28} {'R':>3} {'C':>3} {'S':>3}  {'MCP':<5}  Status")
print(f"  {'-'*45} {'-'*28} {'-'*3} {'-'*3} {'-'*3}  {'-'*5}  ------")
for item in sorted(found, key=lambda x: x["path"]):
    status = "ok" if item["registered"] else "NEW"
    marker = "  " if item["registered"] else "→ "
    short  = rel_path(Path(item["path"]))
    mcp_s  = "yes" if item["mcp"] else ""
    print(f"  {marker}{short:<43} {item['ns']:<28} {item['rules']:>3} {item['cmds']:>3} {item['skills']:>3}  {mcp_s:<5}  {status}")
    if not item["registered"]:
        new_entries[item["ns"]] = item
print()

if not new_entries:
    print("  All .cursor workspaces are already registered.")
    sys.exit(0)

if not DO_REGISTER:
    print(f"  {len(new_entries)} unregistered workspace(s).")
    print("  Run:  make register           — auto-register all")
    print("  Run:  ./sync.sh add <path>    — register one with full control")
    sys.exit(0)

print("  Registering...")
for ns, item in new_entries.items():
    tools = [t for t, v in [("rules",item["rules"]),("commands",item["cmds"]),("skills",item["skills"])] if v]
    registry["namespaces"][ns] = {
        "remote": None if item["remote"]=="(no remote)" else item["remote"],
        "local_dirs": [rel_path(Path(item["path"]))],
        "canonical_dir": rel_path(Path(item["path"])),
        "scope": "deployable",
        "tools": tools or ["rules","commands","skills"],
        "note": "auto-registered by scan"
    }
    print(f"    + {ns}  ({rel_path(Path(item['path']))})")
with open(REGISTRY,"w") as f:
    json.dump(registry, f, indent=2)
print()
print("  registry.json updated. Run 'make harvest' to pull tools.")
PYEOF
}

# ── add ───────────────────────────────────────────────────────────────────────
# Register one project in registry.json.
# Usage: ./sync.sh add <path> [--ns <name>] [--scope deployable|project-only]

add_ns() {
  local proj_path="$1" override_ns="$2" scope="${3:-deployable}"
  proj_path=$(expandpath "$proj_path")

  python3 - "$SCRIPT_DIR" "$proj_path" "$override_ns" "$scope" << PYEOF
import sys, json
from pathlib import Path
exec("""$_py_helpers""")

SCRIPT_DIR   = Path(sys.argv[1])
PROJ         = Path(sys.argv[2]).resolve()
OVERRIDE_NS  = sys.argv[3]
SCOPE        = sys.argv[4]
REGISTRY     = SCRIPT_DIR / "registry.json"

if not PROJ.exists():
    print(f"  error: path does not exist: {PROJ}")
    sys.exit(1)

registry = json.load(open(REGISTRY))
known    = known_dirs(registry)

if str(PROJ) in known:
    # Find which ns already owns it
    for ns, cfg in registry["namespaces"].items():
        for d in cfg.get("local_dirs", []):
            if str(Path(d.replace("~",str(Path.home()))).resolve()) == str(PROJ):
                print(f"  already registered as '{ns}'")
                sys.exit(0)

remote = get_remote(PROJ)
ns     = OVERRIDE_NS if OVERRIDE_NS else suggest_ns(PROJ, remote)
cursor_dir = PROJ / ".cursor"
rules, cmds, skills, mcp = count_tools(cursor_dir) if cursor_dir.exists() else (0,0,0,False)
tools  = [t for t,v in [("rules",rules),("commands",cmds),("skills",skills)] if v]
rel    = rel_path(PROJ)

registry["namespaces"][ns] = {
    "remote": remote if remote else None,
    "local_dirs": [rel],
    "canonical_dir": rel,
    "scope": SCOPE,
    "tools": tools or ["rules","commands","skills"],
}
with open(REGISTRY,"w") as f:
    json.dump(registry, f, indent=2)

print(f"  added: {ns}")
print(f"    path:   {rel}")
print(f"    remote: {remote or '(none)'}")
print(f"    scope:  {SCOPE}")
print(f"    tools:  R={rules} C={cmds} S={skills}" + (" + mcp.json" if mcp else ""))
print()
print(f"  Run: ./sync.sh harvest --ns {ns}")
PYEOF
}

# ── remove ────────────────────────────────────────────────────────────────────
# Remove a namespace from registry.json.
# Usage: ./sync.sh remove <ns> [--clean]
#   --clean : also delete namespaces/<ns>/ directory

remove_ns() {
  local ns="$1" clean="${2:-false}"

  python3 - "$SCRIPT_DIR" "$ns" << PYEOF
import sys, json
from pathlib import Path
import shutil

SCRIPT_DIR = Path(sys.argv[1])
NS         = sys.argv[2]
REGISTRY   = SCRIPT_DIR / "registry.json"

registry = json.load(open(REGISTRY))
if NS not in registry["namespaces"]:
    print(f"  error: namespace '{NS}' not found in registry")
    sys.exit(1)

cfg = registry["namespaces"].pop(NS)
with open(REGISTRY,"w") as f:
    json.dump(registry, f, indent=2)
print(f"  removed: {NS}  ({cfg.get('canonical_dir','')})")
PYEOF

  # Optionally remove namespaces/ dir
  if [[ -d "$NAMESPACES_DIR/$ns" ]]; then
    if [[ "$clean" == "true" ]]; then
      rm -rf "$NAMESPACES_DIR/$ns"
      green "  deleted: namespaces/$ns/"
    else
      info "note: namespaces/$ns/ still exists (use --clean to delete)"
    fi
  fi
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
EXTRA_ARG=""
SCOPE="deployable"
CLEAN=false

shift || true
while [[ $# -gt 0 ]]; do
  case "$1" in
    --ns)    FILTER_NS="$2"; shift 2 ;;
    --force) FORCE=true; shift ;;
    --scope) SCOPE="$2"; shift 2 ;;
    --clean) CLEAN=true; shift ;;
    -*)      shift ;;
    *)       EXTRA_ARG="$1"; shift ;;
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
    scan_dev "${EXTRA_ARG:-$HOME/dev}" "$FORCE"
    ;;
  add)
    if [[ -z "$EXTRA_ARG" ]]; then
      red "Usage: ./sync.sh add <path> [--ns <name>] [--scope deployable|project-only]"
      exit 1
    fi
    add_ns "$EXTRA_ARG" "$FILTER_NS" "$SCOPE"
    ;;
  remove)
    NS="${FILTER_NS:-$EXTRA_ARG}"
    if [[ -z "$NS" ]]; then
      red "Usage: ./sync.sh remove <ns>  OR  ./sync.sh remove --ns <ns> [--clean]"
      exit 1
    fi
    remove_ns "$NS" "$CLEAN"
    ;;
  status)
    show_status
    ;;
  *)
    echo "Usage:"
    echo "  ./sync.sh scan [path]                              # discover unregistered .cursor/ dirs (default ~/dev/)"
    echo "  ./sync.sh scan [path] --force                      # discover + auto-register all new"
    echo "  ./sync.sh add <path> [--ns <name>] [--scope ...]  # register one project"
    echo "  ./sync.sh remove <ns> [--clean]                    # unregister (--clean also removes namespaces/<ns>/)"
    echo "  ./sync.sh harvest [--ns <ns>] [--force]            # project .cursor/ → namespaces/"
    echo "  ./sync.sh deploy  [--ns <ns>] [--force]            # namespaces/ → ~/.cursor/"
    echo "  ./sync.sh status                                    # show namespace tool counts"
    ;;
esac
