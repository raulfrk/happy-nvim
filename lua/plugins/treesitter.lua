-- lua/plugins/treesitter.lua
-- nvim-treesitter master branch (legacy 0.x API). Pinned to master so
-- telescope.nvim 0.1.x's previewer — which calls the legacy module
-- surface (nvim-treesitter.parsers.ft_to_lang, configs.is_enabled,
-- configs.get_module) — gets real TS-highlighted previews instead of
-- the regex fallback forced by the previous compat shims.
--
-- Previously pinned to branch='main' (1.0 API) to dodge a 'range() on
-- nil' highlighter crash reported on an older master. Today's master
-- is believed stable again; we accept that risk in exchange for
-- restoring TS previews. If the crash resurfaces, revert to:
--   branch = 'main'
-- and re-add the shims in lua/plugins/telescope.lua from commit 7c8db88.
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
