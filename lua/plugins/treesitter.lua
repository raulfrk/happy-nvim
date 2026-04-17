-- lua/plugins/treesitter.lua
return {
  {
    'nvim-treesitter/nvim-treesitter',
    branch = 'master', -- v1.0 (main) removed nvim-treesitter.configs API
    event = { 'BufReadPre', 'BufNewFile' },
    build = ':TSUpdate',
    dependencies = {
      { 'nvim-treesitter/nvim-treesitter-textobjects', branch = 'master' },
    },
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
        textobjects = {
          select = {
            enable = true,
            lookahead = true,
            keymaps = {
              ['af'] = '@function.outer',
              ['if'] = '@function.inner',
              ['ac'] = '@class.outer',
              ['ic'] = '@class.inner',
              ['ap'] = '@parameter.outer',
              ['ip'] = '@parameter.inner',
            },
          },
          move = {
            enable = true,
            set_jumps = true,
            goto_next_start = { [']f'] = '@function.outer' },
            goto_previous_start = { ['[f'] = '@function.outer' },
          },
        },
      })
    end,
  },
}
