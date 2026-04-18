-- lua/config/options.lua
-- Option tweaks. termguicolors is set in plugins/colorscheme.lua BEFORE the
-- theme loads (per spec BUG-3 fix).

-- Defensive wrapper around vim.treesitter.get_range.
--
-- Root cause (nvim 0.12.1, 2026-04-18): runtime/lua/vim/treesitter.lua:196
-- unconditionally calls `node:range(true)` after metadata.range / .offset
-- fallthrough. With nvim-treesitter master's injection queries on certain
-- languages, a capture can produce a nil `node` alongside a truthy but
-- non-informative `metadata` table, crashing the async parse loop
-- (languagetree.lua:215 inside tcall). Stack trace on the user's nvim:
--
--   languagetree.lua:596: tcall(parse, ...)
--   languagetree.lua:215: local r = { f(...) }
--   treesitter.lua:196: return { node:range(true) }
--     -> attempt to call method 'range' (a nil value)
--
-- Wrap get_range so nil nodes yield an empty Range6 instead of
-- crashing. The highlighter skips empty ranges silently. Upstream
-- can safely restore the direct call when the injection query contract
-- is tightened; this wrapper is a no-op in the happy path.
do
  local ts = vim.treesitter
  local orig = ts.get_range
  ts.get_range = function(node, source, metadata)
    if metadata and metadata.range then
      return ts._range.add_bytes(assert(source), metadata.range)
    end
    if node == nil then
      return { 0, 0, 0, 0, 0, 0 }
    end
    return orig(node, source, metadata)
  end
end

local o = vim.opt

-- Line numbers
o.number = true
o.relativenumber = true

-- Indent — 4-space soft tabs; smart-indent on
o.tabstop = 4
o.softtabstop = 4
o.shiftwidth = 4
o.expandtab = true
o.smartindent = true

-- No wrap
o.wrap = false

-- No swap / backup; undo persisted in XDG state dir (BUG fix: not ~/.vim)
o.swapfile = false
o.backup = false
o.undofile = true
o.undodir = vim.fn.stdpath('state') .. '/undo'

-- Search
o.hlsearch = true -- BUG-3: was false, disorienting
o.incsearch = true

-- Cursor — always a block in normal, bar in insert (BUG-3 fix for kitty/alacritty)
o.guicursor = 'n-v-c-sm:block,i-ci-ve:ver25,r-cr-o:hor20'

-- Scroll context
o.scrolloff = 8
o.signcolumn = 'yes'

-- Clipboard — VM clipboard via xclip/wl-copy. OSC 52 hook added in Phase 5.
o.clipboard = 'unnamedplus'

-- Filenames containing @- are valid
o.isfname:append('@-@')

-- Faster updatetime (CursorHold, gitsigns, etc.)
o.updatetime = 50

-- Splits open to the right / below
o.splitright = true
o.splitbelow = true

-- True color — required by theme
o.termguicolors = true

-- Leader
vim.g.mapleader = ' '
vim.g.maplocalleader = ' '

-- Diagnostic display
vim.diagnostic.config({
  virtual_text = true,
  signs = true,
  update_in_insert = false,
  severity_sort = true,
})
