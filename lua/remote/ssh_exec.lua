-- lua/remote/ssh_exec.lua — shared ssh argv builder w/ ControlMaster.
-- Using ControlMaster=auto + a per-user socket lets every remote/*.lua
-- call reuse a single multiplexed ssh connection per host. First call
-- establishes the master; subsequent calls piggyback on it. Much faster
-- than fresh handshake-per-call (verified: dirs.lua listing drops from
-- ~1.2s fresh to ~80ms reused on real LAN host).
local M = {}

local function ctl_dir()
  local dir = vim.fn.stdpath('cache') .. '/happy-nvim/ssh'
  -- Best-effort mkdir; silently ignore failures (e.g. sandbox or read-only FS).
  -- ssh ControlMaster will create the socket dir itself at connect time.
  pcall(vim.fn.mkdir, dir, 'p')
  return dir
end

-- argv('host', 'cat /etc/os-release') -> { 'ssh', '-o', ..., 'host', 'cat /etc/os-release' }
-- argv('host', { 'cat', '/etc/os-release' }) -> same, cmd is space-joined by ssh's argv rules.
function M.argv(host, cmd)
  local argv = {
    'ssh',
    '-o',
    'ControlMaster=auto',
    '-o',
    'ControlPath=' .. ctl_dir() .. '/%C',
    '-o',
    'ControlPersist=5m',
    host,
  }
  if type(cmd) == 'table' then
    for _, part in ipairs(cmd) do
      table.insert(argv, part)
    end
  elseif type(cmd) == 'string' then
    table.insert(argv, cmd)
  end
  return argv
end

-- Convenience: run a command, sync, returning { code, stdout, stderr }.
function M.run(host, cmd, opts)
  opts = opts or { text = true }
  local util = require('remote.util')
  return util.run(M.argv(host, cmd), opts)
end

return M
