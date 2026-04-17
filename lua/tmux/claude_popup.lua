-- lua/tmux/claude_popup.lua — hidden detached tmux session + popup attach.
-- Single global Claude instance reachable from any nvim via <leader>cp.
-- Conversation persists across popup toggles and nvim restarts.
local M = {}

local SESSION = 'claude-happy'
local POPUP_W = '85%'
local POPUP_H = '85%'

local function sys(args)
  return vim.system(args, { text = true }):wait()
end

function M.exists()
  return sys({ 'tmux', 'has-session', '-t', SESSION }).code == 0
end

function M.ensure()
  if M.exists() then
    return true
  end
  local cwd = vim.fn.expand('%:p:h')
  if cwd == '' then
    cwd = vim.fn.getcwd()
  end
  local res = sys({ 'tmux', 'new-session', '-d', '-s', SESSION, '-c', cwd, 'claude' })
  if res.code ~= 0 then
    vim.notify('failed to spawn claude-happy session: ' .. (res.stderr or ''), vim.log.levels.ERROR)
    return false
  end
  return true
end

function M.open()
  if vim.env.TMUX == nil or vim.env.TMUX == '' then
    vim.notify('Claude popup requires $TMUX (run nvim inside tmux)', vim.log.levels.WARN)
    return
  end
  if not M.ensure() then
    return
  end
  -- -E closes the popup when inner command exits; user detaches via prefix+d
  sys({
    'tmux',
    'display-popup',
    '-E',
    '-w',
    POPUP_W,
    '-h',
    POPUP_H,
    'tmux attach -t ' .. SESSION,
  })
end

function M.fresh()
  if M.exists() then
    sys({ 'tmux', 'kill-session', '-t', SESSION })
  end
  M.open()
end

-- Returns the pane ID of the (single) pane inside claude-happy, or nil.
-- Used by lua/tmux/send.lua when no @claude_pane_id is set.
function M.pane_id()
  if not M.exists() then
    return nil
  end
  local res = sys({
    'tmux',
    'list-panes',
    '-t',
    SESSION,
    '-F',
    '#{pane_id}',
  })
  if res.code ~= 0 then
    return nil
  end
  local id = (res.stdout or ''):gsub('%s+$', '')
  if id == '' then
    return nil
  end
  return id
end

return M
