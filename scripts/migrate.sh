#!/usr/bin/env bash
# scripts/migrate.sh — install happy-nvim over existing nvim config safely.
set -euo pipefail

CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/nvim"
BACKUP="${CONFIG}.myhappyplace.bak.$(date +%s)"

if [[ -e "$CONFIG" ]]; then
  echo "Backing up existing config to $BACKUP"
  mv "$CONFIG" "$BACKUP"
fi

echo "Cloning happy-nvim into $CONFIG"
git clone https://github.com/raulfrk/happy-nvim "$CONFIG"

echo "Done. Launch nvim — Lazy will sync plugins on first start."
echo "Your old config is preserved at $BACKUP (safe to delete after verifying)."
