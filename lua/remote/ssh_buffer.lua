-- lua/remote/ssh_buffer.lua — ssh://<host>/<path> buffers (RO by default).
-- Replaces `edit scp://...` (which has netrw config quirks + no control
-- master). We pipe content via ssh cat on read and ssh 'cat > path' on
-- write. Writes are refused unless `<leader>sw` has flipped
-- `vim.b.happy_ssh_writable = true` on the buffer.
local M = {}

local CONFIG = { default_writable = false }

function M.setup(opts)
  opts = opts or {}
  if opts.ssh_writable_by_default ~= nil then
    CONFIG.default_writable = opts.ssh_writable_by_default and true or false
  end
end

-- bufname convention: ssh://<host>/<path>. Host has no '/'; path keeps
-- whatever the caller supplied (absolute or ~-prefixed).
function M._parse_bufname(name)
  local host, rest = name:match('^ssh://([^/]+)/(.*)$')
  if not host then
    return nil, nil
  end
  -- Re-prepend the '/' for absolute paths; strip when the caller passed ~/.
  if rest:sub(1, 1) == '~' then
    return host, rest
  end
  return host, '/' .. rest
end

local function bufname_for(host, path)
  if path:sub(1, 1) == '~' then
    return ('ssh://%s/%s'):format(host, path)
  end
  return ('ssh://%s%s'):format(host, path)
end

local function exec()
  return require('remote.ssh_exec')
end
local function hosts()
  return require('remote.hosts')
end
local function util()
  return require('remote.util')
end
local function browse()
  return require('remote.browse')
end

-- Fetch remote file contents → list of lines. Returns (lines, err).
function M._fetch(host, abs_path)
  local q = util().shellquote(abs_path)
  local res = exec().run(host, 'cat ' .. q)
  if res.code ~= 0 then
    return nil, 'ssh cat failed: ' .. (res.stderr or '')
  end
  local body = res.stdout or ''
  -- Preserve a trailing empty line if the remote file ended with \n.
  local lines = vim.split(body, '\n', { plain = true })
  if #lines > 0 and lines[#lines] == '' then
    table.remove(lines)
  end
  return lines
end

-- Pipe buffer lines → `ssh host 'cat > path'`. Returns (ok, err).
function M._push(host, abs_path, lines)
  local q = util().shellquote(abs_path)
  local body = table.concat(lines, '\n') .. '\n'
  local done, result = false, nil
  vim.system(exec().argv(host, 'cat > ' .. q), { text = true, stdin = body }, function(r)
    result = r
    done = true
  end)
  vim.wait(60000, function()
    return done
  end, 50)
  if not done then
    return false, 'timeout'
  end
  if result.code ~= 0 then
    return false, result.stderr or 'push failed'
  end
  return true
end

function M.open(host, path)
  local home_ok = hosts().ensure_home_dir(host)
  local abs = home_ok and hosts().expand_path(host, path) or path

  if browse()._is_binary(host, abs) then
    vim.notify(('%s is binary; use <leader>sO to force'):format(abs), vim.log.levels.WARN)
    return nil
  end

  local name = bufname_for(host, path)
  -- Reuse an existing buffer w/ that name so :e ssh://... is idempotent.
  local existing = vim.fn.bufnr(name)
  if existing ~= -1 then
    vim.api.nvim_set_current_buf(existing)
    return existing
  end

  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(buf, name)

  local lines, err = M._fetch(host, abs)
  if not lines then
    vim.notify(err, vim.log.levels.ERROR)
    vim.api.nvim_buf_delete(buf, { force = true })
    return nil
  end
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  vim.bo[buf].buftype = 'acwrite'
  vim.bo[buf].modified = false
  vim.b[buf].happy_ssh_writable = CONFIG.default_writable or nil
  vim.bo[buf].readonly = not CONFIG.default_writable

  -- Infer filetype from the remote path.
  local ft = vim.filetype.match({ filename = abs, buf = buf })
  if ft then
    vim.bo[buf].filetype = ft
  end

  -- Bind BufWriteCmd once per buffer so it uses the right (host, abs).
  vim.api.nvim_create_autocmd('BufWriteCmd', {
    buffer = buf,
    callback = function()
      if not vim.b[buf].happy_ssh_writable then
        vim.notify('ssh buffer is read-only; <leader>sw to enable writes', vim.log.levels.WARN)
        return
      end
      local content = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      local ok, perr = M._push(host, abs, content)
      if ok then
        vim.bo[buf].modified = false
        vim.notify(('wrote %s:%s'):format(host, abs), vim.log.levels.INFO)
      else
        vim.notify('push failed: ' .. tostring(perr), vim.log.levels.ERROR)
      end
    end,
  })

  vim.api.nvim_set_current_buf(buf)
  return buf
end

function M.toggle_writable()
  local buf = vim.api.nvim_get_current_buf()
  local name = vim.api.nvim_buf_get_name(buf)
  if not name:find('^ssh://') then
    vim.notify('not an ssh:// buffer', vim.log.levels.WARN)
    return
  end
  local cur = vim.b[buf].happy_ssh_writable
  local nv = not cur
  vim.b[buf].happy_ssh_writable = nv or nil
  vim.bo[buf].readonly = not nv
  vim.notify(('ssh buffer %s'):format(nv and 'WRITABLE' or 'read-only'), vim.log.levels.INFO)
end

-- Prompt flow: host picker → path input → open RO.
function M.browse_prompt()
  require('remote.hosts').pick(function(host)
    vim.ui.input({ prompt = 'Remote path: ' }, function(path)
      if not path or path == '' then
        return
      end
      M.open(host, path)
    end)
  end)
end

return M
