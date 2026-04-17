-- tests/minimal_init.lua
local plugin_root = vim.fn.stdpath('data') .. '/site/pack/vendor/start'
local plenary_path = plugin_root .. '/plenary.nvim'

if vim.fn.isdirectory(plenary_path) == 0 then
  vim.fn.system({
    'git',
    'clone',
    '--depth',
    '1',
    'https://github.com/nvim-lua/plenary.nvim',
    plenary_path,
  })
end

vim.opt.rtp:prepend(plenary_path)
vim.opt.rtp:prepend(vim.fn.getcwd())
vim.cmd('runtime plugin/plenary.vim')

require('plenary.busted')
