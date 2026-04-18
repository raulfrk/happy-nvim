#!/usr/bin/env bash
# scripts/wt-claude-provision.sh — pre-warm a Claude tmux session for a
# git worktree path. Derives the same `cc-<repo>-wt-<branch>` name as
# lua/tmux/project.lua so happy-nvim's <leader>cp inside that worktree
# attaches to the existing session instead of spawning a new one.
#
# Usage:
#   scripts/wt-claude-provision.sh /path/to/worktrees/myrepo/feat-x
#
# Idempotent: no-op if the session already exists.
set -euo pipefail

WT_PATH="${1:?usage: $0 <worktree-path>}"

if [[ ! -d "$WT_PATH" ]]; then
  echo "wt-claude-provision: not a directory: $WT_PATH" >&2
  exit 2
fi

slug() {
  local s="$1"
  s="${s//[^a-zA-Z0-9-]/-}"
  while [[ "$s" == *--* ]]; do s="${s//--/-}"; done
  s="${s#-}"
  s="${s%-}"
  printf '%s' "$s"
}

# Derive project id matching lua/tmux/project.lua _derive_id.
toplevel=$(git -C "$WT_PATH" rev-parse --show-toplevel 2>/dev/null || true)
git_dir=$(git -C "$WT_PATH" rev-parse --git-dir 2>/dev/null || true)
common_dir=$(git -C "$WT_PATH" rev-parse --git-common-dir 2>/dev/null || true)

if [[ -z "$toplevel" ]]; then
  # Not a git repo — fall back to cwd basename
  base=$(slug "$(basename "$WT_PATH")")
  session="cc-$base"
else
  # Resolve relative .git paths against worktree
  case "$git_dir" in
    /*) ;;
    *) git_dir="$WT_PATH/$git_dir" ;;
  esac
  case "$common_dir" in
    /*) ;;
    *) common_dir="$WT_PATH/$common_dir" ;;
  esac
  base=$(slug "$(basename "$toplevel")")
  if [[ "$git_dir" != "$common_dir" ]]; then
    leaf=""
    if [[ "$git_dir" == */worktrees/* ]]; then
      leaf="${git_dir##*/worktrees/}"
      leaf="${leaf%%/*}"
    fi
    if [[ -n "$leaf" ]]; then
      # Repo name from common_dir (e.g. /path/to/repo/.git -> repo),
      # matching lua/tmux/project.lua _derive_id behaviour.
      repo=""
      if [[ "$common_dir" == */.git ]]; then
        repo=$(slug "$(basename "$(dirname "$common_dir")")")
      fi
      repo="${repo:-$base}"
      session="cc-$(slug "${repo}-wt-${leaf}")"
    else
      session="cc-$base"
    fi
  else
    session="cc-$base"
  fi
fi

if tmux has-session -t "$session" 2>/dev/null; then
  echo "wt-claude-provision: $session already exists"
  exit 0
fi

tmux new-session -d -s "$session" -c "$WT_PATH" claude
echo "wt-claude-provision: spawned $session in $WT_PATH"
