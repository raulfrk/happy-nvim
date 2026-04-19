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

return M
