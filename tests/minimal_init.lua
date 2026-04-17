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

-- For keymap_spec.lua: load the real user config so registrations happen.
-- Guard with HAPPY_NVIM_LOAD_CONFIG so other specs stay minimal.
if vim.env.HAPPY_NVIM_LOAD_CONFIG == '1' then
  -- Point XDG_CONFIG_HOME at the repo root; nvim will pick up init.lua.
  -- CI + local callers must export HAPPY_NVIM_LOAD_CONFIG=1 and set
  -- XDG_CONFIG_HOME to a scratch dir that contains the repo as ./nvim.
  dofile(vim.fn.getcwd() .. '/init.lua')
  vim.api.nvim_exec_autocmds('VimEnter', {})
end
