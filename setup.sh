#!/usr/bin/env bash
# cursor-tools setup.sh — one-time bootstrap for a fresh machine
# Run once after cloning cursor-tools. Safe to re-run (idempotent).
#
# What it does:
#   1. Clones + builds external tool repos (kubevirt-ui-mcp, etc.)
#   2. Ensures required env vars are in ~/.bash_profile
#   3. Runs initial harvest + deploy

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

red()    { printf '\033[31m%s\033[0m\n' "$*"; }
green()  { printf '\033[32m%s\033[0m\n' "$*"; }
yellow() { printf '\033[33m%s\033[0m\n' "$*"; }
info()   { printf '  %s\n' "$*"; }

ensure_env_var() {
  local name="$1" value="$2" comment="${3:-}"
  if grep -q "export ${name}=" ~/.bash_profile 2>/dev/null; then
    info "$name already in ~/.bash_profile — skipping"
  else
    echo "" >> ~/.bash_profile
    [[ -n "$comment" ]] && echo "# $comment" >> ~/.bash_profile
    echo "export ${name}=\"${value}\"" >> ~/.bash_profile
    green "  added $name to ~/.bash_profile"
  fi
}

# ── 1. Rust toolchain ─────────────────────────────────────────────────────────

echo ""
yellow "── Rust toolchain"
if command -v cargo &>/dev/null || [[ -f "$HOME/.cargo/bin/cargo" ]]; then
  info "cargo already installed"
else
  info "installing Rust via rustup..."
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
  source "$HOME/.cargo/env"
  green "  Rust installed: $(cargo --version)"
fi

source "$HOME/.cargo/env" 2>/dev/null || true
ensure_env_var "PATH" '"$HOME/.cargo/bin:$PATH"' "Rust/cargo"

# ── 2. External repos ─────────────────────────────────────────────────────────

echo ""
yellow "── External repos"

# Read external deps from registry.json
while IFS='|' read -r name repo local_dir build_cmd build_check; do
  [[ -z "$name" ]] && continue
  local_dir="${local_dir/\~/$HOME}"

  echo ""
  info "[$name]  $repo"

  # Clone if missing
  if [[ ! -d "$local_dir" ]]; then
    info "cloning → $local_dir ..."
    git clone "$repo" "$local_dir"
    green "  cloned"
  else
    info "already cloned at $local_dir"
    # Pull latest
    git -C "$local_dir" pull --ff-only 2>/dev/null && info "pulled latest" || info "up to date"
  fi

  # Build if needed
  if [[ -n "$build_cmd" ]]; then
    build_artifact="${local_dir}/${build_check}"
    if [[ -f "$build_artifact" ]]; then
      info "binary already built: $build_check"
    else
      info "building ($build_cmd)..."
      (cd "$local_dir" && eval "$build_cmd")
      green "  built"
    fi
  fi
done < <(python3 - "$SCRIPT_DIR/registry.json" << 'PYEOF'
import json, sys
d = json.load(open(sys.argv[1]))
for name, cfg in d.get('external_repos', {}).items():
    print(f"{name}|{cfg['repo']}|{cfg['local_dir']}|{cfg.get('build_cmd','')}|{cfg.get('build_check','')}")
PYEOF
)

# ── 3. Env vars ───────────────────────────────────────────────────────────────

echo ""
yellow "── Env vars (~/.bash_profile)"

while IFS='|' read -r var value comment; do
  [[ -z "$var" ]] && continue
  ensure_env_var "$var" "$value" "$comment"
done < <(python3 - "$SCRIPT_DIR/registry.json" << 'PYEOF'
import json, sys
d = json.load(open(sys.argv[1]))
for var, cfg in d.get('env_vars', {}).items():
    print(f"{var}|{cfg['value']}|{cfg.get('comment','')}")
PYEOF
)

# MCP tokens reminder
echo ""
if ! grep -q "GITHUB_PAT" ~/.bash_profile 2>/dev/null; then
  yellow "  REMINDER: add GITHUB_PAT to ~/.bash_profile (GitHub fine-grained PAT)"
fi
if ! grep -q "GITLAB_PAT" ~/.bash_profile 2>/dev/null; then
  yellow "  REMINDER: add GITLAB_PAT to ~/.bash_profile (gitlab.cee.redhat.com token)"
fi

# ── 4. Initial harvest + deploy ───────────────────────────────────────────────

echo ""
yellow "── Initial harvest + deploy"
read -r -p "  Run harvest + deploy now? [y/N] " answer
if [[ "$answer" == "y" || "$answer" == "Y" ]]; then
  "$SCRIPT_DIR/sync.sh" harvest
  "$SCRIPT_DIR/sync.sh" deploy
  green "Done. Restart Cursor to pick up all tools."
else
  info "skipped — run 'make harvest && make deploy' when ready"
fi

echo ""
green "Setup complete. Restart your shell or run: source ~/.bash_profile"
