# Fix: claude popup blocks idle watcher → no notification

> **For agentic workers:** REQUIRED SUB-SKILL: `superpowers:subagent-driven-development`. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Idle-flip notifications (`Claude (<slug>) idle`) must fire while the user has the `<leader>cp` popup open. Currently they don't — popup freezes the watcher.

## Context (root cause)

`lua/tmux/claude_popup.lua:73` does:

```lua
sys({'tmux', 'display-popup', '-E', ..., 'tmux attach -t '..session()})
```

where `sys = function(args) return vim.system(args, { text = true }):wait() end`.

`tmux display-popup -E` blocks until its inner command exits (user detaches via `prefix+d`). So `vim.system():wait()` blocks nvim's main thread until then.

**Empirical proof (2026-04-18, nvim 0.12.1):**

```lua
local fired = 0
local timer = vim.uv.new_timer()
timer:start(300, 300, vim.schedule_wrap(function() fired = fired + 1 end))
vim.system({'sleep', '2'}, { text = true }):wait()
print('fired=', fired)   -- prints: fired= 0
```

`vim.uv.timer` does NOT fire while `vim.system():wait()` is blocked. `vim.schedule`-wrapped callbacks queue but don't execute. Consequence for `tmux.idle`:

1. User hits `<leader>cp` → popup opens → nvim blocked in sys call
2. `idle.watch_all()` timer doesn't fire for the duration of the popup
3. When popup closes → `mark_busy` runs → state reset (stable_since = now)
4. Next poll tick needs 2s more of stable output → flip delayed
5. User sees no notification because they expect it WHILE popup is open

## Approach

Make `claude_popup.open()` use the async form of `vim.system`:

```lua
function M.open()
  if vim.env.TMUX == nil or vim.env.TMUX == '' then
    vim.notify('Claude popup requires $TMUX (run nvim inside tmux)', vim.log.levels.WARN)
    return
  end
  if not M.ensure() then return end
  vim.system({
    'tmux', 'display-popup', '-E',
    '-w', M._config.popup.width,
    '-h', M._config.popup.height,
    'tmux attach -t ' .. session(),
  }, { text = true }, vim.schedule_wrap(function(_)
    -- User just detached. Mark busy so next idle-flip needs fresh DEBOUNCE_SECS.
    local ok_idle, idle = pcall(require, 'tmux.idle')
    if ok_idle then
      idle.mark_busy(session())
    end
  end))
end
```

Drop `:wait()`. `vim.system(cmd, opts, on_exit)` returns immediately; the on_exit callback fires when the subprocess ends. Wrap in `vim.schedule_wrap` so the callback runs in a vim-API-safe context.

**Why async works here:**
- `ensure()` still runs synchronously (tmux new-session is fast, returns instantly).
- `open()` no longer blocks — nvim's event loop stays live.
- `idle.watch_all()` timer keeps polling every 1s.
- When claude finishes output → 2s stable → flip → alert fires **while popup still open**.
- When user detaches → `mark_busy` runs (state reset) → ready for next interaction.

## Files

**Modify:**
- `lua/tmux/claude_popup.lua` — replace blocking sys call with async `vim.system(..., callback)`. Keep `sys()` helper (still used by `ensure`, `kill`, `pane_id`).

**Create:**
- `tests/integration/test_popup_nonblocking.py` — headless nvim: registers a `vim.uv.timer` that increments a counter, then spawns a long-running async `vim.system({'sleep','1.5'})`. Asserts the counter advances during the sleep. Regression-guards the entire async-timer contract that the fix depends on.
- `tests/integration/test_idle_alert_during_popup.py` — spawns real `cc-popup-test` tmux session, starts `tmux.idle.watch_all()` inside headless nvim, kicks off a simulated-popup async `vim.system` that blocks for ~4s, asserts `NOTIFY:` line surfaces in nvim stderr before the "popup" exits.

**Modify (optional docs):**
- `docs/manual-tests.md` — append row under section 8 "Idle alerts": `<leader>cp`, prompt → notification fires WHILE popup still open.

## Verification

```bash
cd /home/raul/worktrees/happy-nvim/fix-popup-blocks-idle-watcher

# New integration tests
python3 -m pytest \
  tests/integration/test_popup_nonblocking.py \
  tests/integration/test_idle_alert_during_popup.py \
  tests/integration/test_idle_alert.py \
  tests/integration/test_claude_popup.py -v

# Full assess
bash scripts/assess.sh
# Expect: ASSESS: ALL LAYERS PASS

# Push
git push git@github.com:raulfrk/happy-nvim.git fix/popup-blocks-idle-watcher:main
```

Manual smoke (user-driven, separate from CI):
- In tmux, `<leader>cp` → popup opens
- Type prompt in popup, Enter
- Wait for Claude to finish — notification fires **without detaching**
- Detach (`prefix+d`) → mark_busy resets state, next interaction starts fresh

## Manual Test Additions

- `[ ] Notification fires while <leader>cp popup is still open (after Claude finishes output)`
