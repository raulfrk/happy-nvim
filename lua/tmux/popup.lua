-- lua/tmux/popup.lua — wrappers around `tmux display-popup`.
-- Async subprocess contract lives in lua/tmux/_popup.lua; we just
-- bind the commands.
local M = {}
local _popup = require('tmux._popup')

function M.lazygit()
  _popup.open('80%', '80%', 'lazygit')
end

function M.scratch()
  local root = vim.fn.system({ 'git', 'rev-parse', '--show-toplevel' })
  root = root:gsub('%s+$', '')
  if root == '' then
    root = vim.fn.getcwd()
  end
  -- -d root handled via full arg list in _popup isn't exposed; pass the
  -- shell to run with `cd` prefix so we don't need yet another param.
  _popup.open('80%', '80%', 'cd ' .. vim.fn.shellescape(root) .. ' && zsh -l')
end

function M.btop()
  _popup.open('80%', '80%', 'btop')
end

-- Keymaps registered statically in lua/plugins/tmux.lua so which-key
-- sees them on <leader> before the module is loaded.
function M.setup() end

return M
