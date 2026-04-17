-- lua/plugins/treesitter.lua
-- nvim-treesitter main branch (1.0 API). Uses nvim 0.11's
-- vim.treesitter.start() via FileType autocmd — no custom highlighter,
-- so the 'range() on nil' crash on master branch is gone.
local LANGS = {
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
}

return {
  'nvim-treesitter/nvim-treesitter',
  branch = 'main',
  lazy = false, -- install+start eagerly; highlighter is cheap
  config = function()
    local ts = require('nvim-treesitter')
    ts.install(LANGS)

    vim.api.nvim_create_autocmd('FileType', {
      pattern = LANGS,
      callback = function(ev)
        pcall(vim.treesitter.start, ev.buf)
      end,
    })
  end,
}
