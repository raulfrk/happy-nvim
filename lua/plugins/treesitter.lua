-- lua/plugins/treesitter.lua
-- nvim-treesitter master branch (legacy 0.x API). Pinned to master so
-- telescope.nvim 0.1.x's previewer — which calls the legacy module
-- surface (nvim-treesitter.parsers.ft_to_lang, configs.is_enabled,
-- configs.get_module) — gets real TS-highlighted previews.
--
-- The historical "range() on nil" crash from languagetree.lua:215 is
-- muzzled by a defensive wrapper around `vim.treesitter.get_range` in
-- lua/config/options.lua: when a query capture yields a nil node with
-- non-informative metadata, the wrapper returns an empty Range6 so the
-- highlighter skips the capture instead of crashing.
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
  branch = 'master',
  build = ':TSUpdate',
  lazy = false,
  config = function()
    require('nvim-treesitter.configs').setup({
      ensure_installed = LANGS,
      auto_install = true,
      highlight = { enable = true },
      indent = { enable = true },
    })
  end,
}
