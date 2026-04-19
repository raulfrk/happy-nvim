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

return M
