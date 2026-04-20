-- lua/tmux/split.lua — layout-smart tmux split helper.
-- Picks horizontal vs. vertical split based on the current tmux window
-- aspect ratio: wide panes get a vertical split (side-by-side), tall/
-- square panes get a horizontal split (stacked). Mirrors the intuition
-- behind native `tmux split-window -h`/`-v`.
local M = {}

-- Width/height ratio above which a vertical split (side-by-side) makes
-- more sense than horizontal (stacked). 2.5 is empirically where a
-- terminal window starts to feel "wide" on a modern laptop monitor.
local WIDE_RATIO = 2.5

function M.orient()
  local w = tonumber(vim.fn.system({ 'tmux', 'display-message', '-p', '#{window_width}' }))
  local h = tonumber(vim.fn.system({ 'tmux', 'display-message', '-p', '#{window_height}' }))
  if not w or not h or h == 0 then
    return 'h'
  end
  return (w / h > WIDE_RATIO) and 'v' or 'h'
end

-- Spawn a tmux split inside the *current* window running `cmd`.
--   opts.cwd — working dir for the new pane (defaults to getcwd())
--   opts.orient — override 'h'/'v' (defaults to M.orient())
-- Returns the new pane id (e.g. '%42') or nil on failure.
function M.open(cmd, opts)
  opts = opts or {}
  local orient = opts.orient or M.orient()
  local cwd = opts.cwd or vim.fn.getcwd()
  local flag = (orient == 'v') and '-h' or '-v' -- tmux semantics: -h splits left/right, -v stacks
  local argv = { 'tmux', 'split-window', flag, '-P', '-F', '#{pane_id}', '-c', cwd, cmd }
  local res = vim.system(argv, { text = true }):wait()
  if res.code ~= 0 then
    return nil
  end
  return (res.stdout or ''):gsub('%s+$', '')
end

return M
