# Convert remote/*.lua ssh calls to async vim.system (#17)

> **For agentic workers:** REQUIRED SUB-SKILL: `superpowers:subagent-driven-development`. Steps use checkbox syntax.

## Context

Five blocking `vim.system(cmd):wait()` call sites in `lua/remote/*.lua` run
ssh subprocesses that can take several seconds over the network. Each
freezes nvim's main thread for that time: `vim.uv.timer` callbacks
don't fire, `vim.schedule` fns don't drain, keystrokes queue but don't
render. The idle watcher (`lua/tmux/idle.lua`) is the clearest
victim — its poll timer misses its cadence and notifications get
delayed or dropped entirely during remote ops.

Same pattern bit us in `claude_popup.open` (2026-04-18 ebf0846). That
fix used the async callback form of `vim.system`. The `remote/*`
call sites are trickier because each result feeds downstream state
(picker entries, binary-guard decision, quickfix). Direct callback
refactor would ripple through several pickers.

## Approach

Introduce a small helper `lua/remote/util.lua` with one function:

```lua
function M.run(cmd, opts, timeout_ms)
  local done = false
  local result = { code = -1, stdout = '', stderr = '' }
  vim.system(cmd, opts or { text = true }, function(r)
    result = r
    done = true
  end)
  vim.wait(timeout_ms or 60000, function() return done end, 50)
  if not done then
    return { code = 124, stdout = '', stderr = 'timeout' }
  end
  return result
end
```

`vim.wait(ms, predicate, interval_ms)` pumps nvim's event loop while
waiting — timer callbacks fire, other scheduled fns run, the UI stays
partially responsive. The caller still gets a synchronous return, so
`dirs.lua`, `browse.lua`, `grep.lua` don't need to restructure their
picker-building code. Best-of-both:

- Async enough to not starve the event loop.
- Sync enough to keep the existing picker-population code readable.

All 5 blocking call sites swap their `vim.system(...):wait()` for
`require('remote.util').run(...)`. No further refactor needed.

## Files

**Create**
- `lua/remote/util.lua` — `run()` helper.
- `tests/remote_util_spec.lua` — plenary unit tests.
- `tests/integration/test_remote_async_nonblocking.py` — asserts a
  `vim.uv.timer` keeps firing during a `util.run({'sleep','2'})`
  call. Parallel to `test_idle_alert_during_popup.py`.

**Modify**
- `lua/remote/dirs.lua:50` (`_fetch_sync` — renamed to `_fetch` since
  it's no longer blocking, though kept synchronous-ish from caller's
  POV).
- `lua/remote/browse.lua:58,62` (`check_remote_binary` — two sequential
  remote probes).
- `lua/remote/browse.lua:128` (`M.find`).
- `lua/remote/grep.lua:95` (`M.prompt` — passes `opts.timeout*1000+5000`
  as the util.run timeout so the outer wait exceeds the server-side
  `timeout N` command).

## Verification

```bash
cd /home/raul/worktrees/happy-nvim/fix-remote-async-17

# Plenary unit tests (util + existing remote specs)
XDG_DATA_HOME="$PWD/.tests" XDG_CONFIG_HOME="$PWD/.tests/config" \
  XDG_CACHE_HOME="$PWD/.tests/cache" XDG_STATE_HOME="$PWD/.tests/state" \
  nvim --headless -u tests/minimal_init.lua \
  -c "PlenaryBustedFile tests/remote_util_spec.lua" \
  -c "PlenaryBustedFile tests/remote_dirs_spec.lua" \
  -c "PlenaryBustedFile tests/remote_browse_spec.lua" \
  -c "PlenaryBustedFile tests/remote_grep_spec.lua" \
  -c 'qa!' 2>&1 | tail -10

# Integration tests
python3 -m pytest tests/integration/test_remote_async_nonblocking.py -v
python3 -m pytest tests/integration/test_remote_grep.py tests/integration/test_remote_hosts.py -v

# Full assess
bash scripts/assess.sh
# Expect: ASSESS: ALL LAYERS PASS

# Push + CI
git push git@github.com:raulfrk/happy-nvim.git fix/remote-async-17:main
```

Manual smoke (user-driven, separate from CI):
- `<leader>sd` (remote dir picker) on a real ssh host — during the
  ssh find, idle-alert notifications from active `cc-*` sessions
  continue to fire.
- `<leader>sg` (remote grep) over a large repo — same.

## Manual Test Additions

- `[ ] (CI-covered) remote.util.run keeps vim.uv.timer firing during subprocess`
- `[ ] <leader>sd over real ssh: idle notifications from cc-* sessions still fire during the find`
