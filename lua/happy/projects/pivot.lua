-- Project pivot primitive.
--
-- Given a project id: cd nvim to its path (if local), ensure the tmux
-- session `cc-<id>` (local) or `remote-<id>` (remote) is alive — spawning
-- fresh if dead — and focus it when we're inside tmux.
local registry = require('happy.projects.registry')

local M = {}

local function session_name(entry)
  if entry.kind == 'remote' then
    return 'remote-' .. entry.id
  end
  return 'cc-' .. entry.id
end

local function session_alive(name)
  vim.fn.system({ 'tmux', 'has-session', '-t', name })
  return vim.v.shell_error == 0
end

local function spawn_local(entry)
  local name = session_name(entry)
  vim.fn.system({ 'tmux', 'new-session', '-d', '-s', name, '-c', entry.path })
  vim.fn.system({ 'tmux', 'set-env', '-t', name, 'HAPPY_PROJECT_PATH', entry.path })
  vim.fn.system({ 'tmux', 'send-keys', '-t', name, 'claude', 'Enter' })
end

local function spawn_remote(entry)
  require('happy.projects.remote').spawn_ssh(entry)
end

-- pivot(id): cd nvim (local), ensure tmux session, focus it.
function M.pivot(id)
  local entry = registry.get(id)
  if not entry then
    vim.notify('project not found: ' .. id, vim.log.levels.WARN)
    return
  end
  entry.id = id
  if entry.kind == 'local' then
    vim.cmd.cd(vim.fn.fnameescape(entry.path))
  end
  local name = session_name(entry)
  if not session_alive(name) then
    if entry.kind == 'local' then
      spawn_local(entry)
    else
      spawn_remote(entry)
    end
    vim.notify(name .. ' session was dead — spawned fresh.', vim.log.levels.INFO)
  end
  registry.touch(id)
  if os.getenv('TMUX') then
    vim.fn.system({ 'tmux', 'switch-client', '-t', name })
  end
end

-- peek(id): show tail of the session's pane in a scratch buffer.
function M.peek(id)
  local entry = registry.get(id)
  if not entry then
    return
  end
  entry.id = id
  local name = session_name(entry)
  if not session_alive(name) then
    vim.notify(name .. ' is not alive — nothing to peek', vim.log.levels.INFO)
    return
  end
  local out = vim.fn.system({ 'tmux', 'capture-pane', '-t', name, '-p', '-S', '-20' })
  vim.cmd('new')
  vim.bo.buftype = 'nofile'
  vim.bo.bufhidden = 'wipe'
  vim.api.nvim_buf_set_lines(0, 0, -1, false, vim.split(out, '\n'))
  vim.bo.modifiable = false
end

return M
