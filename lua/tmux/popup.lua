-- lua/tmux/popup.lua — wrappers around `tmux display-popup`
--
-- Every popup here blocks inside the inner cmd (lazygit, btop, shell)
-- for as long as the user stays in it — typically minutes. Blocking
-- nvim's main thread that long freezes every timer and autocmd
-- (idle watcher, macro-nudge, precognition, LSP). Use the async form
-- of vim.system so the popup attaches without blocking the editor.
local M = {}

local function popup(cmd)
  vim.system({ 'tmux', 'display-popup', '-E', '-w', '80%', '-h', '80%', cmd }, {}, function() end)
end

function M.lazygit()
  popup('lazygit')
end

function M.scratch()
  local root = vim.fn.system({ 'git', 'rev-parse', '--show-toplevel' })
  root = root:gsub('%s+$', '')
  if root == '' then
    root = vim.fn.getcwd()
  end
  vim.system(
    { 'tmux', 'display-popup', '-E', '-w', '80%', '-h', '80%', '-d', root, 'zsh -l' },
    {},
    function() end
  )
end

function M.btop()
  popup('btop')
end

-- Keymaps registered statically in lua/plugins/tmux.lua so which-key
-- sees them on <leader> before the module is loaded.
function M.setup() end

return M
