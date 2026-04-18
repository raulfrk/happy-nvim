-- lua/remote/util.lua — shared async-subprocess helper for remote/*.lua.
--
-- Blocking vim.system(cmd):wait() freezes nvim's main thread for the
-- subprocess's full lifetime. When the subprocess is an ssh round-trip
-- (seconds), every timer-driven feature starves — the idle watcher
-- (lua/tmux/idle.lua) is the clearest victim. Using the callback form
-- of vim.system + vim.wait to pump the event loop keeps timers + other
-- scheduled fns live while we block for the result.
--
-- Callers still get a synchronous return value so dirs/browse/grep
-- don't need to restructure their picker-building code.
local M = {}

--- Run `cmd` asynchronously and wait for it to complete, pumping nvim's
--- event loop in the meantime. Returns the same SystemCompleted shape
--- as `vim.system(...):wait()` so callers can swap in-place.
---
--- @param cmd string[]         argv-style command list
--- @param opts table?          forwarded to vim.system (defaults to { text = true })
--- @param timeout_ms integer?  hard cap on wait time (defaults to 60000)
--- @return { code: integer, stdout: string?, stderr: string? }
function M.run(cmd, opts, timeout_ms)
  opts = opts or { text = true }
  timeout_ms = timeout_ms or 60000
  local done = false
  local result = { code = -1, stdout = '', stderr = '' }
  vim.system(cmd, opts, function(r)
    result = r
    done = true
  end)
  vim.wait(timeout_ms, function()
    return done
  end, 50)
  if not done then
    return {
      code = 124,
      stdout = '',
      stderr = 'remote.util.run: timeout after ' .. timeout_ms .. 'ms',
    }
  end
  return result
end

--- Escape a string for interpolation inside a POSIX-shell single-quoted
--- context. Wraps input in `'...'` with any embedded `'` replaced by the
--- standard `'\''` dance (close, escaped-quote, reopen). Callers should
--- embed the result directly — the returned string is already quoted.
---
--- Needed for the remote.grep / remote.browse commands where user
--- input is interpolated into an ssh-executed shell command: the
--- remote shell parses what ssh sends it, so any `'` in the input
--- breaks out of our wrapping quotes (command injection).
---
--- @param s string
--- @return string -- quoted, e.g. `shellquote("a'b") == "'a'\\''b'"`
function M.shellquote(s)
  return "'" .. s:gsub("'", "'\\''") .. "'"
end

return M
