-- lua/tmux/claude_popup.lua — per-project detached tmux session + popup attach.
--
-- Every independent repo (or worktree) keyed by tmux.project.session_name()
-- gets its own hidden 'cc:<slug>' tmux session running claude in that
-- project's cwd. <leader>cp from nvim inside project A attaches to cc:A;
-- from project B attaches to cc:B. No crosstalk.
local M = {}
local project = require('tmux.project')

-- Defaults; override via M.setup({ popup = { width = ..., height = ... } }).
M._config = {
  popup = {
    width = '85%',
    height = '85%',
  },
}

-- Merge user overrides shallowly into _config. Backwards-compatible: if
-- setup is never called, popup dimensions stay at the defaults above.
function M.setup(opts)
  opts = opts or {}
  if opts.popup then
    M._config.popup.width = opts.popup.width or M._config.popup.width
    M._config.popup.height = opts.popup.height or M._config.popup.height
  end
end

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
  -- New session is busy by definition (we just spawned claude)
  local ok_idle, idle = pcall(require, 'tmux.idle')
  if ok_idle then
    idle.mark_busy(session())
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
  -- Async contract: see lua/tmux/_popup.lua + commit ebf0846.
  require('tmux._popup').open(
    M._config.popup.width,
    M._config.popup.height,
    'tmux attach -t ' .. session(),
    function()
      -- Popup closed. User was typing in there; mark the session busy
      -- so the next idle flip needs a fresh DEBOUNCE_SECS of quiet.
      local ok_idle, idle = pcall(require, 'tmux.idle')
      if ok_idle then
        idle.mark_busy(session())
      end
    end
  )
end

function M.fresh()
  if M.exists() then
    sys({ 'tmux', 'kill-session', '-t', session() })
  end
  M.open()
end

-- Kill a session by name (defaults to current project's). Returns true on
-- success or if the session already didn't exist.
function M.kill(name)
  name = name or session()
  local res = sys({ 'tmux', 'has-session', '-t', name })
  if res.code ~= 0 then
    return true -- already gone
  end
  local r = sys({ 'tmux', 'kill-session', '-t', name })
  return r.code == 0
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
