-- lua/config/options.lua
-- Option tweaks. termguicolors is set in plugins/colorscheme.lua BEFORE the
-- theme loads (per spec BUG-3 fix).

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
