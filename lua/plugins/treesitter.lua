-- lua/plugins/treesitter.lua
-- Keep the plugin for :TSInstall (parsers are used by some plugins like
-- noice for markdown rendering) but DISABLE highlight. Master branch is
-- stale and crashes on nvim 0.11 core ("attempt to call method 'range' on
-- nil"). Fallback: vim's builtin regex syntax highlighting.
return {
  {
    'nvim-treesitter/nvim-treesitter',
    branch = 'master',
    event = { 'BufReadPre', 'BufNewFile' },
    build = ':TSUpdate',
    dependencies = {},
    config = function()
      require('nvim-treesitter.configs').setup({
        ensure_installed = {
          'lua',
          'vim',
          'vimdoc',
          'query',
          'python',
          'go',
          'c',
          'cpp',
          'bash',
          'yaml',
          'json',
          'toml',
        },
        highlight = { enable = false },
        indent = { enable = false },
      })
    end,
  },
}
