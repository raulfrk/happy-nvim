#!/usr/bin/env bash
# scripts/migrate.sh — install happy-nvim over existing nvim config safely.
#
# Safe to re-run. Each invocation:
#   1. Backs up ~/.config/nvim to ~/.config/nvim.myhappyplace.bak.<epoch>
#      (skipped if $CONFIG is already a happy-nvim checkout)
#   2. Re-clones the repo (or pulls latest if already present)
#   3. Wipes ~/.local/share/nvim/lazy so plugins re-install at the
#      branches/commits pinned in lazy-lock.json (fixes cross-version
#      plugin layout drift — e.g. harpoon v1 vs v2)
#   4. Wipes stale plugin state files that collide with v2 formats
set -euo pipefail

CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/nvim"
DATA="${XDG_DATA_HOME:-$HOME/.local/share}/nvim"
REPO='https://github.com/raulfrk/happy-nvim'

is_happy_nvim() {
  [[ -f "$1/init.lua" ]] && grep -q 'happy-nvim' "$1/README.md" 2>/dev/null
}

# 1. Backup existing config (unless it's already happy-nvim)
if [[ -e "$CONFIG" ]] && ! is_happy_nvim "$CONFIG"; then
  BACKUP="${CONFIG}.myhappyplace.bak.$(date +%s)"
  echo "Backing up existing config to $BACKUP"
  mv "$CONFIG" "$BACKUP"
fi

# 2. Clone or pull
if [[ -d "$CONFIG/.git" ]]; then
  echo "Updating existing happy-nvim at $CONFIG"
  git -C "$CONFIG" pull --ff-only
else
  echo "Cloning happy-nvim into $CONFIG"
  git clone "$REPO" "$CONFIG"
fi

# 3. Wipe lazy plugin dir so plugins re-clone at locked branches/commits.
# This fixes: user had harpoon v1 installed (different layout, wrong
# branch), lazy won't switch branches automatically after spec changes.
if [[ -d "$DATA/lazy" ]]; then
  echo "Clearing stale plugin install at $DATA/lazy"
  rm -rf "$DATA/lazy"
fi

# 4. Remove stale plugin state files that may collide with v2 formats
for stale in "$DATA/harpoon.json" "$DATA/harpoon2.json"; do
  [[ -e "$stale" ]] && rm -f "$stale" && echo "Removed stale state: $stale"
done

echo
echo "Done. Next:"
echo "  nvim --headless -c 'Lazy! sync' -c 'qa!'"
echo "  nvim  # Mason auto-installs LSP/formatter/linter tools on first open"
