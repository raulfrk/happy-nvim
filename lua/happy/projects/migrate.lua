-- Migrate legacy `cc-*` tmux sessions into the projects registry.
--
-- Pre-SP1 happy-nvim scripts spawned one tmux session per project named
-- `cc-<slug>` and set `HAPPY_PROJECT_PATH` on the session environment.
-- This module walks the live tmux server, discovers those sessions, and
-- backfills the registry so users don't lose their existing work when
-- upgrading to the cockpit.
local registry = require('happy.projects.registry')
local M = {}

local run_tmux = function(args)
  local out = vim.fn.system(args)
  if vim.v.shell_error ~= 0 then return '' end
  return out
end

-- test hook: swap the tmux runner for a fake
function M._set_tmux_fn_for_test(fn) run_tmux = fn end

function M.run()
  local raw = run_tmux({ 'tmux', 'list-sessions', '-F', '#S' })
  local sessions = {}
  for s in raw:gmatch('[^\n]+') do
    if s:match('^cc%-') then table.insert(sessions, s) end
  end
  local before = #registry.list()
  for _, s in ipairs(sessions) do
    local env = run_tmux({ 'tmux', 'show-env', '-t', s, 'HAPPY_PROJECT_PATH' })
    local path = env:match('^HAPPY_PROJECT_PATH=(.+)')
    if path then
      -- tmux show-env output carries a trailing newline; trim before add
      -- so the idempotent path-match in registry.add works byte-for-byte.
      path = path:gsub('%s+$', '')
      if path ~= '' then
        registry.add({ kind = 'local', path = path })
      end
    end
  end
  local added = #registry.list() - before
  if added > 0 then
    vim.schedule(function()
      vim.notify(
        ('Migrated %d existing claude sessions to projects registry.'):format(added),
        vim.log.levels.INFO
      )
    end)
  end
  return added
end

return M
