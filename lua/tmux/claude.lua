-- lua/tmux/claude.lua — <leader>c* commands
local M = {}
local send = require('tmux.send')
local registry = require('happy.projects.registry')

local function session_for_cwd()
  local cwd = vim.fn.getcwd()
  local id = registry.add({ kind = 'local', path = cwd })
  return id, 'cc-' .. id, cwd
end

local function session_alive(name)
  vim.fn.system({ 'tmux', 'has-session', '-t', name })
  return vim.v.shell_error == 0
end

function M._build_cf_payload(rel_path)
  return '@' .. rel_path
end

function M._build_cs_payload(rel_path, lstart, lend, ft, lines)
  local content = table.concat(lines, '\n')
  local fence = content:find('```', 1, true) and '~~~' or '```'
  return string.format('@%s:%d-%d\n%s%s\n%s\n%s', rel_path, lstart, lend, fence, ft, content, fence)
end

local SEVERITY_NAMES = { 'ERROR', 'WARN', 'INFO', 'HINT' }

function M._build_ce_payload(rel_path, diags)
  local bullets = {}
  for _, d in ipairs(diags) do
    -- vim.diagnostic emits 0-based lnum; user-visible line numbers are
    -- 1-based. Previous `d.lnum + (d.lnum == 0 and 0 or 0)` was a no-op
    -- (both branches = 0) — reported line N-1 to Claude (#22).
    local name = SEVERITY_NAMES[d.severity]
    if not name then
      -- Out-of-range severity — log once so :messages captures the
      -- anomaly instead of silently mapping it to 'UNKNOWN'. #29.
      vim.schedule(function()
        vim.notify(
          'happy-nvim: diagnostic with unknown severity=' .. tostring(d.severity),
          vim.log.levels.DEBUG
        )
      end)
      name = 'UNKNOWN'
    end
    table.insert(bullets, string.format('- %s: %s (line %d)', name, d.message, d.lnum + 1))
  end
  return string.format('@%s\nDiagnostics:\n%s\n\nFix these.', rel_path, table.concat(bullets, '\n'))
end

-- Returns the buffer's path relative to cwd, or nil for nameless buffers
-- (scratch, :enew, terminal). Callers that send @<path> to Claude must
-- handle nil by notifying the user instead of sending `@.`. #26.
local function buf_rel_path()
  local name = vim.api.nvim_buf_get_name(0)
  if name == '' then
    return nil
  end
  return vim.fn.fnamemodify(name, ':.')
end

local function guard_buf_rel_path()
  local p = buf_rel_path()
  if not p then
    vim.notify(
      'No file associated with this buffer. Save it first or use <leader>cs on a selection.',
      vim.log.levels.WARN
    )
  end
  return p
end

function M.open()
  local id, session, cwd = session_for_cwd()
  if not session_alive(session) then
    local res = vim
      .system({ 'tmux', 'new-session', '-d', '-s', session, '-c', cwd, 'claude' }, { text = true })
      :wait()
    if res.code ~= 0 then
      vim.notify('failed to spawn Claude session: ' .. (res.stderr or ''), vim.log.levels.ERROR)
      return
    end
    vim.system({ 'tmux', 'set-env', '-t', session, 'HAPPY_PROJECT_PATH', cwd }):wait()
  end
  registry.touch(id)
  if vim.env.TMUX and vim.env.TMUX ~= '' then
    vim.system({ 'tmux', 'switch-client', '-t', session }):wait()
  else
    vim.notify(
      session .. ' is up. Attach via `tmux attach -t ' .. session .. '`.',
      vim.log.levels.INFO
    )
  end
end

function M.send_file()
  local p = guard_buf_rel_path()
  if not p then
    return
  end
  send.send_to_claude(M._build_cf_payload(p))
end

function M.send_selection()
  local p = guard_buf_rel_path()
  if not p then
    return
  end
  local lstart = vim.fn.getpos("'<")[2]
  local lend = vim.fn.getpos("'>")[2]
  local lines = vim.api.nvim_buf_get_lines(0, lstart - 1, lend, false)
  local ft = vim.bo.filetype
  send.send_to_claude(M._build_cs_payload(p, lstart, lend, ft, lines))
end

function M.send_errors()
  local p = guard_buf_rel_path()
  if not p then
    return
  end
  local diags = vim.diagnostic.get(0)
  send.send_to_claude(M._build_ce_payload(p, diags))
end

-- Keymaps registered statically in lua/plugins/tmux.lua so which-key
-- sees them on <leader> before the module is loaded. Handlers notify
-- when called outside a tmux session instead of silently no-opping.
local function guard()
  if vim.env.TMUX == nil or vim.env.TMUX == '' then
    vim.notify('tmux integration requires $TMUX (run nvim inside tmux)', vim.log.levels.WARN)
    return false
  end
  return true
end

function M.setup() end

function M.open_guarded()
  if guard() then
    M.open()
  end
end

function M.open_fresh_guarded()
  if not guard() then
    return
  end
  local _, session, _ = session_for_cwd()
  if session_alive(session) then
    vim.system({ 'tmux', 'kill-session', '-t', session }):wait()
  end
  M.open()
end
function M.send_file_guarded()
  if guard() then
    M.send_file()
  end
end
function M.send_selection_guarded()
  if guard() then
    M.send_selection()
  end
end
function M.send_errors_guarded()
  if guard() then
    M.send_errors()
  end
end

return M
