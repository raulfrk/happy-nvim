#!/usr/bin/env bash
# scripts/migrate.sh — install happy-nvim over existing nvim config safely.
#
# Safe to re-run. Each invocation:
#   1. Checks nvim >= 0.11 (winborder, vim.lsp.config)
#   2. Backs up ~/.config/nvim to ~/.config/nvim.myhappyplace.bak.<epoch>
#      (skipped if $CONFIG is already a happy-nvim checkout)
#   3. Clones the repo or pulls latest if already present
#   4. Wipes ~/.local/share/nvim/lazy so plugins re-clone at the
#      branches/commits declared in the spec (harpoon2, treesitter master)
#   5. Wipes stale plugin state files that collide with v2 formats
#   6. Runs Lazy! sync headlessly (installs + compiles parsers via TSUpdate)
#   7. Prints follow-up instructions
set -euo pipefail

CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/nvim"
DATA="${XDG_DATA_HOME:-$HOME/.local/share}/nvim"
REPO='https://github.com/raulfrk/happy-nvim'

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m==>\033[0m %s\n' "$*" >&2; }
die() { printf '\033[1;31m==>\033[0m %s\n' "$*" >&2; exit 1; }

# 1. Preflight — nvim 0.11+ required
if ! command -v nvim >/dev/null 2>&1; then
  die "nvim not found on \$PATH. Install Neovim 0.11+ first."
fi

if ! nvim --headless --clean -c 'lua if vim.fn.has("nvim-0.11") == 0 then vim.cmd("cq") end' -c 'qa!' 2>/dev/null; then
  cur=$(nvim --version | head -1)
  die "happy-nvim requires nvim >= 0.11. Found: $cur
Upgrade: https://github.com/neovim/neovim/releases/tag/stable
Debian/Ubuntu: curl -L https://github.com/neovim/neovim/releases/download/stable/nvim-linux-x86_64.tar.gz -o /tmp/nvim.tar.gz && sudo tar -C /opt -xzf /tmp/nvim.tar.gz && sudo ln -sf /opt/nvim-linux-x86_64/bin/nvim /usr/local/bin/nvim"
fi

# 1b. Preflight — tree-sitter CLI required by nvim-treesitter@main for parser builds.
#
# Recent npm `tree-sitter-cli` (0.25+) ships a prebuilt binary linked against
# GLIBC 2.39 (Ubuntu 24.04 build host). Hosts with older glibc (Debian 12
# bookworm = 2.36, Ubuntu 22.04 = 2.35) get a crash:
#
#   /lib/x86_64-linux-gnu/libc.so.6: version `GLIBC_2.39' not found
#
# So: (a) verify the binary actually runs, don't just check $PATH, and
# (b) on GLIBC mismatch, fall back through pinned older npm → cargo.
ts_works() {
  command -v tree-sitter >/dev/null 2>&1 && tree-sitter --version >/dev/null 2>&1
}

ts_fail_reason() {
  command -v tree-sitter >/dev/null 2>&1 || { echo "not on \$PATH"; return 0; }
  local out
  out=$(tree-sitter --version 2>&1 || true)
  printf '%s' "$out" | tr '\n' ' ' | sed 's/[[:space:]]\+$//'
  return 0
}

npm_install_ts() {
  local spec="$1"
  npm install -g "$spec" 2>/dev/null && return 0
  warn "global npm install ($spec) failed — retrying with sudo"
  sudo npm install -g "$spec"
}

# Probe host glibc. Empty string = couldn't detect, treat optimistically.
host_glibc=$(ldd --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+' | head -1 || true)
glibc_ge_239() {
  [[ -z "$host_glibc" ]] && return 0
  local major minor
  IFS=. read -r major minor <<<"$host_glibc"
  [[ -z "${major:-}" || -z "${minor:-}" ]] && return 0
  (( major > 2 )) && return 0
  (( major == 2 && minor >= 39 )) && return 0
  return 1
}

if ts_works; then
  :
else
  if command -v tree-sitter >/dev/null 2>&1; then
    warn "existing tree-sitter unusable: $(ts_fail_reason)"
  fi
  if ! command -v npm >/dev/null 2>&1; then
    die "npm not found. Install Node.js (includes npm) then re-run: https://nodejs.org/en/download"
  fi

  # If host glibc is old, skip the wasted "latest" install and go straight to
  # the last version built against Ubuntu 22.04 (glibc 2.35).
  if glibc_ge_239; then
    log "installing tree-sitter CLI via npm (latest)"
    npm_install_ts tree-sitter-cli || warn "npm install tree-sitter-cli failed"
  else
    log "host glibc=${host_glibc} < 2.39 — pinning tree-sitter-cli@0.24 (latest npm prebuild needs glibc 2.39)"
    npm_install_ts 'tree-sitter-cli@0.24' || warn "npm install tree-sitter-cli@0.24 failed"
  fi

  # If the primary install path didn't produce a working binary, try the
  # pinned older npm version (covers the case where latest is still ABI-newer
  # than our probe suggested).
  if ! ts_works && glibc_ge_239; then
    warn "latest tree-sitter unusable ($(ts_fail_reason)); trying pinned tree-sitter-cli@0.24"
    npm_install_ts 'tree-sitter-cli@0.24' || warn "pinned npm install failed"
  fi

  # Last resort: build from source with cargo.
  if ! ts_works; then
    if command -v cargo >/dev/null 2>&1; then
      warn "npm prebuilds unusable ($(ts_fail_reason)); building from source via cargo"
      cargo install tree-sitter-cli || warn "cargo install tree-sitter-cli failed"
    else
      warn "cargo not found — skipping source build fallback"
    fi
  fi

  if ! ts_works; then
    die "could not install a working tree-sitter CLI.
  host: $(ldd --version 2>/dev/null | head -1)
  last error: $(ts_fail_reason)
  fixes:
    1. install Rust (https://rustup.rs) then: cargo install tree-sitter-cli
    2. download the static binary from https://github.com/tree-sitter/tree-sitter/releases
       and place it on \$PATH as 'tree-sitter'"
  fi
fi
log "tree-sitter: $(tree-sitter --version 2>&1 | head -1)"

# 1c. Preflight — Nerd Font detection (warning only, not fatal)
if command -v fc-list >/dev/null 2>&1; then
  if ! fc-list 2>/dev/null | grep -qi 'nerd font'; then
    warn "No Nerd Font detected in fc-list. Icons will render as '?' or boxes."
    warn "Install one: https://github.com/ryanoasis/nerd-fonts/releases"
    warn "Then set your terminal font to e.g. 'JetBrainsMono Nerd Font'."
  fi
fi

is_happy_nvim() {
  [[ -f "$1/init.lua" ]] && grep -q 'happy-nvim' "$1/README.md" 2>/dev/null
}

# 2. Backup existing config (unless it's already happy-nvim)
if [[ -e "$CONFIG" ]] && ! is_happy_nvim "$CONFIG"; then
  BACKUP="${CONFIG}.myhappyplace.bak.$(date +%s)"
  log "Backing up existing config to $BACKUP"
  mv "$CONFIG" "$BACKUP"
fi

# 3. Clone or pull
if [[ -d "$CONFIG/.git" ]]; then
  log "Updating existing happy-nvim at $CONFIG"
  git -C "$CONFIG" pull --ff-only
else
  log "Cloning happy-nvim into $CONFIG"
  git clone "$REPO" "$CONFIG"
fi

# 4. Wipe lazy plugin dir so plugins re-clone at locked branches/commits.
if [[ -d "$DATA/lazy" ]]; then
  log "Clearing stale plugin install at $DATA/lazy"
  rm -rf "$DATA/lazy"
fi

# 5. Remove stale plugin state files that may collide with v2 formats
for stale in "$DATA/harpoon.json" "$DATA/harpoon2.json"; do
  [[ -e "$stale" ]] && rm -f "$stale" && log "Removed stale state: $stale"
done

# 6. Install plugins + build treesitter parsers headlessly
log "Running Lazy! sync (clone plugins)"
nvim --headless -c 'Lazy! sync' -c 'qa!' 2>&1 | tail -5

log "Running TSUpdateSync (build treesitter parsers for this nvim ABI)"
nvim --headless -c 'Lazy load nvim-treesitter' -c 'TSUpdateSync' -c 'qa!' 2>&1 | tail -5 || \
  warn "TSUpdateSync failed — parsers may already be up to date, check manually"

# 7. Done
cat <<'EOF'

==> Install complete.

Next:
  * Open nvim. Mason will auto-install LSP servers / formatters / linters
    (ruff, gopls, pyright, lua_ls, stylua, shellcheck, etc.) on first open.
  * Run `:checkhealth happy-nvim` to verify prereqs (tmux, ssh, ripgrep, fd).
  * Discover keymaps by pressing <Space> and waiting (which-key popup).

Known limitations (v1):
  * Markdown treesitter highlighting disabled (vim regex fallback).
  * Text objects (af/if/ac/ic) disabled pending upstream 0.11 fix.
EOF
