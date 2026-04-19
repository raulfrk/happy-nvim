-- Remote project provisioning.
--
-- Creates an on-disk sandbox dir for a remote project and writes a
-- `.claude/settings.local.json` that:
--   * denies outbound network egress (ssh/scp/sftp/rsync/mosh/curl/wget/
--     nc/socat/ssh-*) and WebFetch,
--   * denies filesystem-wide Read/Edit/Write,
--   * allows Read/Edit/Write scoped to the sandbox dir.
--
-- Sandbox base dir is `HAPPY_REMOTE_SANDBOX_BASE` or
-- `stdpath('data')/happy/remote-sandboxes` as a fallback. After
-- provisioning, flips `sandbox_written = true` on the registry entry.
local registry = require('happy.projects.registry')

local M = {}

local function sandbox_root()
  local override = os.getenv('HAPPY_REMOTE_SANDBOX_BASE')
  if override and override ~= '' then return override end
  return vim.fn.stdpath('data') .. '/happy/remote-sandboxes'
end

function M.sandbox_dir(id)
  return sandbox_root() .. '/' .. id
end

function M.provision(id)
  local entry = registry.get(id)
  if not entry or entry.kind ~= 'remote' then return end

  local dir = M.sandbox_dir(id)
  vim.fn.mkdir(dir .. '/.claude', 'p')

  local settings = {
    permissions = {
      deny = {
        'Bash(ssh:*)',
        'Bash(scp:*)',
        'Bash(sftp:*)',
        'Bash(rsync:*)',
        'Bash(mosh:*)',
        'Bash(curl:*)',
        'Bash(wget:*)',
        'Bash(nc:*)',
        'Bash(socat:*)',
        'Bash(ssh-*)',
        'WebFetch(*)',
        'Read(/**)',
        'Edit(/**)',
        'Write(/**)',
      },
      allow = {
        ('Read(%s/**)'):format(dir),
        ('Write(%s/**)'):format(dir),
        ('Edit(%s/**)'):format(dir),
      },
    },
  }

  local path = dir .. '/.claude/settings.local.json'
  local fh = assert(io.open(path, 'w'))
  fh:write(vim.json.encode(settings))
  fh:close()

  registry.update(id, { sandbox_written = true })
end

-- spawn_ssh(entry): create a tmux session `remote-<id>` running the ssh cmd.
--
-- Resolves id from entry.id; if absent (e.g. caller passed a registry.get()
-- result, which does not attach .id), falls back to scanning registry.list()
-- for a matching host+path pair.
--
-- HAPPY_REMOTE_SSH_CMD overrides the ssh binary. When set to the literal
-- 'cat', runs `cat` instead of building an ssh command — used by integration
-- tests to keep the session alive without real network.
function M.spawn_ssh(entry)
  local id = entry.id
  if not id then
    for _, v in ipairs(registry.list()) do
      if v.path == entry.path and v.host == entry.host then
        id = v.id
        break
      end
    end
  end
  local name = 'remote-' .. id
  local ssh_cmd = os.getenv('HAPPY_REMOTE_SSH_CMD') or 'ssh'
  local cmd
  if ssh_cmd == 'cat' then
    cmd = 'cat' -- test mode: keep the session alive without a real ssh
  else
    cmd = ('%s %s -t "cd %s; exec $SHELL"'):format(ssh_cmd, entry.host, entry.path)
  end
  vim.fn.system({ 'tmux', 'new-session', '-d', '-s', name, cmd })
  vim.fn.system({ 'tmux', 'set-env', '-t', name, 'HAPPY_REMOTE_HOST', entry.host })
  vim.fn.system({ 'tmux', 'set-env', '-t', name, 'HAPPY_REMOTE_PATH', entry.path })
end

local function ts() return os.date('!%Y%m%dT%H%M%SZ') end

function M.capture(id)
  local entry = registry.get(id); if not entry or entry.kind ~= 'remote' then return end
  local name = 'remote-' .. id
  local out = vim.fn.system({ 'tmux', 'capture-pane', '-t', name, '-p', '-S', '-500' })
  if vim.v.shell_error ~= 0 then
    vim.notify('capture failed: no remote pane', vim.log.levels.WARN); return
  end
  local path = M.sandbox_dir(id) .. '/capture-' .. ts() .. '.log'
  local fh = assert(io.open(path, 'w')); fh:write(out); fh:close()
  vim.notify('captured -> ' .. path, vim.log.levels.INFO)
  return path
end

function M.toggle_tail(id)
  local entry = registry.get(id); if not entry or entry.kind ~= 'remote' then return end
  local name = 'remote-' .. id
  local live = M.sandbox_dir(id) .. '/live.log'
  local pipe_state = vim.fn.system({ 'tmux', 'show-options', '-t', name, '-p', '-v', '@happy-tail' })
  if pipe_state:find('on') then
    vim.fn.system({ 'tmux', 'pipe-pane', '-t', name })  -- toggle off
    vim.fn.system({ 'tmux', 'set-option', '-t', name, '-p', '@happy-tail', 'off' })
    vim.notify('tail OFF', vim.log.levels.INFO)
  else
    vim.fn.system({ 'tmux', 'pipe-pane', '-t', name, '-o', 'cat >> ' .. live })
    vim.fn.system({ 'tmux', 'set-option', '-t', name, '-p', '@happy-tail', 'on' })
    vim.notify('tail ON -> ' .. live, vim.log.levels.INFO)
  end
end

function M.pull(id, remote_path)
  local entry = registry.get(id); if not entry or entry.kind ~= 'remote' then return end
  local dest = M.sandbox_dir(id) .. '/' .. vim.fs.basename(remote_path)
  vim.fn.system({ 'scp', entry.host .. ':' .. remote_path, dest })
  if vim.v.shell_error == 0 then
    vim.notify('pulled -> ' .. dest, vim.log.levels.INFO)
  else
    vim.notify('scp failed', vim.log.levels.ERROR)
  end
end

function M.send_selection(id)
  local entry = registry.get(id); if not entry or entry.kind ~= 'remote' then return end
  local reg = vim.fn.getreg('+')
  if reg == '' then reg = vim.fn.getreg('"') end
  local path = M.sandbox_dir(id) .. '/selection-' .. ts() .. '.txt'
  local fh = assert(io.open(path, 'w')); fh:write(reg); fh:close()
  vim.notify('selection -> ' .. path, vim.log.levels.INFO)
end

return M
