-- lua/plugins/treesitter.lua
return {
  {
    'nvim-treesitter/nvim-treesitter',
    branch = 'master', -- v1.0 (main) removed nvim-treesitter.configs API
    event = { 'BufReadPre', 'BufNewFile' },
    build = ':TSUpdate',
    -- textobjects disabled until they fix the nvim 0.11 range() nil crash
    -- (Re-add once upstream tags a compatible release.)
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
          'markdown',
          'markdown_inline',
          'json',
          'toml',
        },
        highlight = { enable = true },
        indent = { enable = true },
      })
    end,
  },
}
