-- lua/plugins/treesitter.lua
-- nvim-treesitter main branch (1.0 API). Uses nvim 0.11's
-- vim.treesitter.start() via FileType autocmd — no custom highlighter,
-- so the 'range() on nil' crash on master branch is gone.
--
-- We tried pinning master (commit 5e07f60, 2026-04-18) to restore TS
-- highlighting in telescope previewer, but the `range() on nil` crash
-- from languagetree.lua:215 returned immediately. Reverted to main.
-- Telescope compat shims restored in lua/plugins/telescope.lua to
-- muzzle telescope 0.1.x's legacy-API requires; preview falls back to
-- vim regex highlighting. That's the tradeoff we're stuck with until
-- we either migrate pickers (snacks.picker / fzf-lua) or telescope
-- ships a 1.0-compatible release.
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

    -- Start TS on every file that has a parser (bundled or installed).
    vim.api.nvim_create_autocmd('FileType', {
      callback = function(ev)
        local ft = ev.match
        if ft == '' then
          return
        end
        -- Bundled or previously-installed → just start.
        if pcall(vim.treesitter.language.get_lang, ft) then
          pcall(vim.treesitter.start, ev.buf)
          return
        end
        -- Not installed. Kick off an async install + start on completion.
        -- Skip filetypes treesitter doesn't know about at all (no parser exists).
        local ok, parsers = pcall(require, 'nvim-treesitter.parsers')
        if not ok or not parsers[ft] then
          return
        end
        ts.install({ ft })
        -- Re-check after a short delay; start if install finished.
        vim.defer_fn(function()
          if pcall(vim.treesitter.language.get_lang, ft) then
            pcall(vim.treesitter.start, ev.buf)
          end
        end, 3000)
      end,
    })
  end,
}
