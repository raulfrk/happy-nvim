-- lua/remote/tail.lua — <leader>sL detachable + resumable log tail.
-- Architecture: a *detached* tmux session `tail-<host>-<slug>` runs the
-- ssh tail stream and tees it to a state file on the local fs. A
-- scratch buffer tails that state file via vim.uv.fs_watch. Closing the
-- scratch (q) just detaches — tmux session stays, state file keeps
-- growing, user can reattach later from <leader>sP.
local M = {}
local TAIL_PREFIX = 'tail-'
local _state_dir_override = nil

local function state_dir()
  if _state_dir_override then
    return _state_dir_override
  end
  return vim.fn.stdpath('cache') .. '/happy-nvim/tails'
end

-- Test escape hatch: redirect state files to a writable tmp dir.
function M._set_state_dir_for_test(dir)
  _state_dir_override = dir
end

function M._slugify(path)
  return path:gsub('[^%w]', '-'):gsub('%-+', '-'):gsub('^%-', ''):gsub('%-$', '')
end

function M._session_name(host, path)
  return TAIL_PREFIX .. host .. '-' .. M._slugify(path)
end

function M._state_path(session)
  local dir = state_dir()
  vim.fn.mkdir(dir, 'p')
  return dir .. '/' .. session .. '.log'
end

local function sys(args)
  return vim.system(args, { text = true }):wait()
end

function M._exists(session)
  return sys({ 'tmux', 'has-session', '-t', session }).code == 0
end

local function ensure_session(host, path, session, state_file)
  if M._exists(session) then
    return true
  end
  local exec = require('remote.ssh_exec')
  local ssh_argv = exec.argv(host, 'tail -F ' .. require('remote.util').shellquote(path))
  -- Build: tmux new-session -d -s <name> "<ssh argv> | tee <state_file>"
  -- Use a shell so the pipe works.
  local cmd = table.concat(
    vim.tbl_map(function(a)
      return vim.fn.shellescape(a)
    end, ssh_argv),
    ' '
  ) .. ' 2>&1 | tee ' .. vim.fn.shellescape(state_file)
  local res = sys({ 'tmux', 'new-session', '-d', '-s', session, 'sh', '-c', cmd })
  if res.code ~= 0 then
    vim.notify('failed to spawn tail session: ' .. (res.stderr or ''), vim.log.levels.ERROR)
    return false
  end
  sys({ 'tmux', 'set-option', '-t', session, '@tail_host', host })
  sys({ 'tmux', 'set-option', '-t', session, '@tail_path', path })
  sys({ 'tmux', 'set-option', '-t', session, '@tail_state', state_file })
  return true
end

local function append_lines(buf, lines)
  if #lines == 0 then
    return
  end
  vim.schedule(function()
    if not vim.api.nvim_buf_is_valid(buf) then
      return
    end
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, -1, -1, false, lines)
    vim.bo[buf].modifiable = false
    local win = vim.fn.bufwinid(buf)
    if win ~= -1 then
      vim.api.nvim_win_set_cursor(win, { vim.api.nvim_buf_line_count(buf), 0 })
    end
  end)
end

local function dispatch_watches(host, path, lines)
  local watch = require('remote.watch')
  for _, line in ipairs(lines) do
    local hits = watch.scan(host, path, line)
    for _, h in ipairs(hits) do
      local level = vim.log.levels[h.level or 'INFO'] or vim.log.levels.INFO
      vim.schedule(function()
        vim.notify(('[tail %s:%s] /%s/ %s'):format(h.host, h.path, h.regex, line), level)
      end)
    end
  end
end

local function attach_scratch(host, path, state_file, session)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, ('[tail %s:%s]'):format(host, path))
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'wipe'
  vim.cmd('sbuffer ' .. buf)
  local f = io.open(state_file, 'r')
  if f then
    local existing = {}
    for line in f:lines() do
      table.insert(existing, line)
    end
    f:close()
    append_lines(buf, existing)
  end
  local pos = vim.uv.fs_stat(state_file) and vim.uv.fs_stat(state_file).size or 0
  local watcher = vim.uv.new_fs_event()
  watcher:start(
    state_file,
    {},
    vim.schedule_wrap(function(err)
      if err then
        return
      end
      local stat = vim.uv.fs_stat(state_file)
      if not stat then
        return
      end
      if stat.size <= pos then
        pos = stat.size
        return
      end
      local fd = vim.uv.fs_open(state_file, 'r', 438)
      if not fd then
        return
      end
      local delta = vim.uv.fs_read(fd, stat.size - pos, pos)
      vim.uv.fs_close(fd)
      pos = stat.size
      if not delta or delta == '' then
        return
      end
      local new_lines = vim.split(delta, '\n', { plain = true, trimempty = true })
      append_lines(buf, new_lines)
      dispatch_watches(host, path, new_lines)
    end)
  )
  vim.b[buf].happy_tail_session = session
  vim.b[buf].happy_tail_host = host
  vim.b[buf].happy_tail_path = path
  vim.api.nvim_create_autocmd('BufWipeout', {
    buffer = buf,
    callback = function()
      if watcher and not watcher:is_closing() then
        watcher:stop()
        watcher:close()
      end
    end,
  })
  vim.keymap.set('n', 'q', function()
    vim.cmd('bw!')
  end, { buffer = buf, desc = 'detach tail scratch (tmux stays)' })
  vim.keymap.set('n', '<leader>sp', function()
    require('remote.watch_editor').open(host, path)
  end, { buffer = buf, desc = 'edit watch patterns for this tail' })
end

function M.start(host, path, opts)
  opts = opts or {}
  local session = M._session_name(host, path)
  local state_file = M._state_path(session)
  if not ensure_session(host, path, session, state_file) then
    return
  end
  if opts.open_buffer ~= false then
    attach_scratch(host, path, state_file, session)
  end
end

function M.reattach(session)
  local host_r = sys({ 'tmux', 'show-option', '-t', session, '-v', '-q', '@tail_host' })
  local path_r = sys({ 'tmux', 'show-option', '-t', session, '-v', '-q', '@tail_path' })
  local state_r = sys({ 'tmux', 'show-option', '-t', session, '-v', '-q', '@tail_state' })
  if host_r.code ~= 0 or path_r.code ~= 0 or state_r.code ~= 0 then
    vim.notify('cannot resolve tail session: ' .. session, vim.log.levels.WARN)
    return
  end
  local host = (host_r.stdout or ''):gsub('%s+$', '')
  local path = (path_r.stdout or ''):gsub('%s+$', '')
  local state = (state_r.stdout or ''):gsub('%s+$', '')
  attach_scratch(host, path, state, session)
end

function M.kill(session)
  return sys({ 'tmux', 'kill-session', '-t', session }).code == 0
end

function M.list_sessions()
  local res = sys({ 'tmux', 'list-sessions', '-F', '#{session_name}' })
  if res.code ~= 0 then
    return {}
  end
  local out = {}
  for line in (res.stdout or ''):gmatch('[^\n]+') do
    if line:sub(1, #TAIL_PREFIX) == TAIL_PREFIX then
      local host_r = sys({ 'tmux', 'show-option', '-t', line, '-v', '-q', '@tail_host' })
      local path_r = sys({ 'tmux', 'show-option', '-t', line, '-v', '-q', '@tail_path' })
      table.insert(out, {
        name = line,
        host = (host_r.stdout or ''):gsub('%s+$', ''),
        path = (path_r.stdout or ''):gsub('%s+$', ''),
      })
    end
  end
  return out
end

function M.tail_log()
  require('remote.hosts').pick(function(host)
    vim.ui.input({ prompt = 'Remote log path: ' }, function(path)
      if not path or path == '' then
        return
      end
      local exp = require('remote.hosts').expand_path(host, path)
      M.start(host, exp)
    end)
  end)
end

function M._stream_tail(host, path)
  M.start(host, path)
end

return M
