-- lua/tmux/claude_popup.lua — per-project detached tmux session + popup attach.
--
-- Every independent repo (or worktree) keyed by tmux.project.session_name()
-- gets its own hidden 'cc:<slug>' tmux session running claude in that
-- project's cwd. <leader>cp from nvim inside project A attaches to cc:A;
-- from project B attaches to cc:B. No crosstalk.
local M = {}
local project = require('tmux.project')

local POPUP_W = '85%'
local POPUP_H = '85%'

local function sys(args)
  return vim.system(args, { text = true }):wait()
end

local function session()
  return project.session_name()
end

function M.exists()
  return sys({ 'tmux', 'has-session', '-t', session() }).code == 0
end

function M.ensure()
  if M.exists() then
    return true
  end
  local cwd = vim.fn.expand('%:p:h')
  if cwd == '' then
    cwd = vim.fn.getcwd()
  end
  local res = sys({ 'tmux', 'new-session', '-d', '-s', session(), '-c', cwd, 'claude' })
  if res.code ~= 0 then
    vim.notify(
      'failed to spawn ' .. session() .. ' session: ' .. (res.stderr or ''),
      vim.log.levels.ERROR
    )
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
    'tmux attach -t ' .. session(),
  })
end

function M.fresh()
  if M.exists() then
    sys({ 'tmux', 'kill-session', '-t', session() })
  end
  M.open()
end

function M.pane_id()
  if not M.exists() then
    return nil
  end
  local res = sys({
    'tmux',
    'list-panes',
    '-t',
    session(),
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
