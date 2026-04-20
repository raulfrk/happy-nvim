-- lua/tmux/claude.lua — <leader>c* commands.
-- cc = layout-smart split in current tmux window (per-project pane id).
-- cp (claude_popup.lua) is the primary entry point; cc is secondary.
local M = {}
local send = require('tmux.send')
local registry = require('happy.projects.registry')

-- Returns (project_id, cwd) for the current buffer's cwd. Registry is
-- dedup-safe: same cwd → same id across calls.
local function project_for_cwd()
  local cwd = vim.fn.getcwd()
  return registry.add({ kind = 'local', path = cwd }), cwd
end

-- Per-slug window option so two projects in the same tmux window can
-- each track their own pane id (fixes bug 30.3 collision).
local function pane_opt_name(slug)
  return '@claude_pane_id_' .. slug
end

local function read_pane_id(slug)
  local res = vim
    .system({ 'tmux', 'show-option', '-w', '-v', '-q', pane_opt_name(slug) }, { text = true })
    :wait()
  if res.code ~= 0 then
    return nil
  end
  local id = (res.stdout or ''):gsub('%s+$', '')
  return id ~= '' and id or nil
end

local function pane_alive(pane_id)
  if not pane_id then
    return false
  end
  local res = vim.system({ 'tmux', 'list-panes', '-t', pane_id }, { text = true }):wait()
  return res.code == 0
end

local function write_pane_id(slug, pane_id)
  vim.system({ 'tmux', 'set-option', '-w', pane_opt_name(slug), pane_id }):wait()
end

function M.open()
  local slug, cwd = project_for_cwd()
  local pane = read_pane_id(slug)
  if pane_alive(pane) then
    vim.system({ 'tmux', 'select-pane', '-t', pane }):wait()
    registry.touch(slug)
    return
  end
  local split = require('tmux.split')
  local new_pane = split.open('claude', { cwd = cwd })
  if not new_pane then
    vim.notify('failed to spawn claude split', vim.log.levels.ERROR)
    return
  end
  write_pane_id(slug, new_pane)
  registry.touch(slug)
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
  local slug = project_for_cwd()
  local pane = read_pane_id(slug)
  if pane_alive(pane) then
    vim.system({ 'tmux', 'kill-pane', '-t', pane }):wait()
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

local function scratch_name_for(id)
  return ('cc-%s-scratch-%d'):format(id, os.time())
end

local function scratch_cwd_for(id, fallback_cwd)
  local ok_remote, remote = pcall(require, 'happy.projects.remote')
  local ok_reg, reg = pcall(require, 'happy.projects.registry')
  if ok_remote and ok_reg then
    local entry = reg.get(id)
    if entry and entry.kind == 'remote' then
      return remote.sandbox_dir(id)
    end
  end
  return fallback_cwd
end

function M.open_scratch()
  local id, cwd = project_for_cwd()
  local name = scratch_name_for(id)
  local effective_cwd = scratch_cwd_for(id, cwd)
  local res = vim
    .system({ 'tmux', 'new-session', '-d', '-s', name, '-c', effective_cwd, 'claude' }, { text = true })
    :wait()
  if res.code ~= 0 then
    vim.notify('failed to spawn scratch claude: ' .. (res.stderr or ''), vim.log.levels.ERROR)
    return
  end
  vim.system({
    'tmux',
    'display-popup',
    '-E',
    '-w',
    '85%',
    '-h',
    '85%',
    'tmux',
    'attach',
    '-t',
    name,
  }, {}, vim.schedule_wrap(function()
    vim.system({ 'tmux', 'kill-session', '-t', name }):wait()
  end))
end

function M.open_scratch_guarded()
  if guard() then
    M.open_scratch()
  end
end

return M
