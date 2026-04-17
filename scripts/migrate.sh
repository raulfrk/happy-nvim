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

# 1b. Preflight — tree-sitter CLI required by nvim-treesitter@main for parser builds
if ! command -v tree-sitter >/dev/null 2>&1; then
  log "tree-sitter CLI not found — installing via npm-global"
  if ! command -v npm >/dev/null 2>&1; then
    die "npm not found. Install Node.js (includes npm) then re-run: https://nodejs.org/en/download"
  fi
  if ! npm install -g tree-sitter-cli 2>/dev/null; then
    warn "global npm install failed — retrying with sudo"
    sudo npm install -g tree-sitter-cli || die "npm install -g tree-sitter-cli failed. Install manually: cargo install tree-sitter-cli"
  fi
  command -v tree-sitter >/dev/null 2>&1 || die "tree-sitter still not on \$PATH after install. Check npm global prefix: npm config get prefix"
fi
log "tree-sitter: $(tree-sitter --version 2>&1 | head -1)"

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
