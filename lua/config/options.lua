-- lua/config/options.lua
-- Option tweaks. termguicolors is set in plugins/colorscheme.lua BEFORE the
-- theme loads (per spec BUG-3 fix).

-- Defensive wrapper around vim.treesitter.get_range.
--
-- Root cause (nvim 0.12.1, 2026-04-18): runtime/lua/vim/treesitter.lua:196
-- unconditionally calls `node:range(true)` after metadata.range / .offset
-- fallthrough. With nvim-treesitter master's injection queries on certain
-- languages, a capture can produce a value where `node.range` is nil
-- (not a TSNode — could be nil, a plain table, or some stale reference),
-- crashing the async parse loop (languagetree.lua:215 inside tcall):
--
--   languagetree.lua:596: tcall(parse, ...)
--   languagetree.lua:215: local r = { f(...) }
--   treesitter.lua:196: return { node:range(true) }
--     -> attempt to call method 'range' (a nil value)
--
-- Type-check AND pcall the original: if the argument isn't a TSNode
-- userdata, or the underlying call errors for any reason, return an
-- empty Range6 so the highlighter silently skips the capture. Upstream
-- can restore the direct call once the injection query contract is
-- tightened; this wrapper is a no-op in the happy path.
do
  local EMPTY_RANGE = { 0, 0, 0, 0, 0, 0 }
  local ts = vim.treesitter
  local orig = ts.get_range
  ts.get_range = function(node, source, metadata)
    if metadata and metadata.range then
      if source == nil then
        return EMPTY_RANGE
      end
      local ok, r = pcall(ts._range.add_bytes, source, metadata.range)
      return ok and r or EMPTY_RANGE
    end
    -- TSNodes are userdata; anything else (nil, table, string) would
    -- crash line 196 of runtime/treesitter.lua on node:range(true).
    if type(node) ~= 'userdata' then
      return EMPTY_RANGE
    end
    local ok, r = pcall(orig, node, source, metadata)
    return ok and r or EMPTY_RANGE
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
