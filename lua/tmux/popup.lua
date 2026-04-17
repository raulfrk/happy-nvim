-- lua/tmux/popup.lua — wrappers around `tmux display-popup`
local M = {}

local function popup(cmd)
  vim.system({ 'tmux', 'display-popup', '-E', '-w', '80%', '-h', '80%', cmd }):wait()
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
  vim
    .system({ 'tmux', 'display-popup', '-E', '-w', '80%', '-h', '80%', '-d', root, 'zsh -l' })
    :wait()
end

function M.btop()
  popup('btop')
end

function M.setup()
  if vim.env.TMUX == nil or vim.env.TMUX == '' then
    return
  end
  local map = vim.keymap.set
  map('n', '<leader>tg', M.lazygit, { desc = 'lazygit popup' })
  map('n', '<leader>tt', M.scratch, { desc = 'scratch shell popup (git root)' })
  map('n', '<leader>tb', M.btop, { desc = 'btop popup' })
end

return M
