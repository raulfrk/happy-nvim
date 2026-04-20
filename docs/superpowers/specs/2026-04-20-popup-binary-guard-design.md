# tmux Popup Binary Guard (Design Spec)

**Status:** approved 2026-04-20

**Problem:** `<leader>tg` (lazygit) + `<leader>tb` (btop) popups flash in-and-out when the underlying binary isn't installed. Root cause: `lua/tmux/popup.lua` spawns `tmux display-popup -E lazygit` / `btop` without checking `vim.fn.executable()`. When the child process exits immediately (command not found), tmux closes the popup — user sees a 50ms flash + no feedback.

**Fix:** `guard(bin, hint)` helper checks `vim.fn.executable(bin) == 1` before spawning. If missing → `vim.notify` w/ an install hint + return. `M.scratch` also gets a safer shell pick (`$SHELL` → `zsh` → `bash` → `sh` fallback).

**Files:**
- `lua/tmux/popup.lua` — add guard + wrap `M.lazygit` / `M.btop`. Harden `M.scratch` shell selection.
- `tests/integration/test_popup_guard.py` — new, asserts notify fires + `_popup.open` NOT called when binary missing.
- `docs/manual-tests.md` §4 — update rows for `<leader>tg` / `<leader>tb` to note graceful fallback.

**Architecture:** One file modified, one new test file, one docs row tweak. No new modules. Behavior change is additive — existing flow (binary present) unchanged; missing-binary case now surfaces a warning instead of a silent flash.

**Testing:**
- Integration: stub `vim.fn.executable → 0` + stub `tmux._popup.open`, call `M.lazygit()`, assert notify msg + `open` never called.
- Same pattern for `M.btop`.
- Regression: full pytest + plenary green.

**Rollout:** single push, CI watch. No behavior change for users w/ lazygit/btop installed.

**Out of scope:**
- Adding lazygit/btop to the mason-tool-installer — those are TUI apps, not LSP/formatters; Mason doesn't handle them.
- `<leader>cp` / `<leader>cq` claude popups — separate code path (`claude_popup.ensure` creates a detached session first; if claude itself exits, that's a different "claude not installed or not authenticated" issue tracked as manual-test prerequisite).
