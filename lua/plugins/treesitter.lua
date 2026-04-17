-- lua/plugins/treesitter.lua
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
        highlight = {
          enable = true,
          -- Markdown injection crashes on nvim 0.11 treesitter core
          -- ("attempt to call method 'range' on nil"). Disable until
          -- nvim-treesitter tags a 0.11-compatible release.
          disable = { 'markdown', 'markdown_inline' },
          additional_vim_regex_highlighting = false,
        },
        indent = { enable = true },
      })
    end,
  },
}
