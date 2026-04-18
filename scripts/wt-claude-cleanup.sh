#!/usr/bin/env bash
# scripts/wt-claude-cleanup.sh — counterpart to wt-claude-provision.sh.
# Kills the cc-<slug> tmux session for a worktree path. Wire into your
# worktree-removal flow.
#
# Usage:
#   scripts/wt-claude-cleanup.sh /path/to/worktrees/myrepo/feat-x
#
# Safe no-op if the session doesn't exist.
set -euo pipefail

WT_PATH="${1:?usage: $0 <worktree-path>}"

slug() {
  local s="$1"
  s="${s//[^a-zA-Z0-9-]/-}"
  while [[ "$s" == *--* ]]; do s="${s//--/-}"; done
  s="${s#-}"
  s="${s%-}"
  printf '%s' "$s"
}

# Worktree may already be deleted by the time we run; tolerate that
# by reading the same git refs from the parent repo if available.
toplevel=""
git_dir=""
common_dir=""
if [[ -d "$WT_PATH" ]]; then
  toplevel=$(git -C "$WT_PATH" rev-parse --show-toplevel 2>/dev/null || true)
  git_dir=$(git -C "$WT_PATH" rev-parse --git-dir 2>/dev/null || true)
  common_dir=$(git -C "$WT_PATH" rev-parse --git-common-dir 2>/dev/null || true)
fi

if [[ -z "$toplevel" ]]; then
  # Worktree gone or non-git — derive from path basename
  base=$(slug "$(basename "$WT_PATH")")
  session="cc-$base"
else
  case "$git_dir" in /*) ;; *) git_dir="$WT_PATH/$git_dir" ;; esac
  case "$common_dir" in /*) ;; *) common_dir="$WT_PATH/$common_dir" ;; esac
  base=$(slug "$(basename "$toplevel")")
  if [[ "$git_dir" != "$common_dir" && "$git_dir" == */worktrees/* ]]; then
    leaf="${git_dir##*/worktrees/}"
    leaf="${leaf%%/*}"
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
fi

if tmux has-session -t "$session" 2>/dev/null; then
  tmux kill-session -t "$session"
  echo "wt-claude-cleanup: killed $session"
else
  echo "wt-claude-cleanup: no session $session"
fi
