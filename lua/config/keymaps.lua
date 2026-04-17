-- lua/config/keymaps.lua
-- Core keymaps (non-namespaced). Plugin-specific leader-prefixed keymaps
-- are registered in lua/plugins/<plugin>.lua via which-key.add (spec §BUG-2).

local map = vim.keymap.set

-- Move visual selections up/down preserving indent
map('v', 'J', ":m '>+1<CR>gv=gv", { silent = true })
map('v', 'K', ":m '<-2<CR>gv=gv", { silent = true })

-- Keep cursor centered on half-page scroll + n/N search
map('n', 'J', 'mzJ`z')
map('n', '<C-d>', '<C-d>zz')
map('n', '<C-u>', '<C-u>zz')
map('n', 'n', 'nzzzv')
map('n', 'N', 'Nzzzv')

-- Paste over visual without clobbering register (classic)
map('x', '<leader>p', [["_dP]], { desc = 'paste without yank' })

-- System-clipboard yank (single, authoritative binding per spec §BUG-2)
map({ 'n', 'v' }, '<leader>y', [["+y]], { desc = 'yank to system clipboard' })
map('n', '<leader>Y', [["+Y]], { desc = 'yank line to system clipboard' })

-- Delete without clobbering unnamed register
map({ 'n', 'v' }, '<leader>d', [["_d]], { desc = 'delete without yank' })

-- Ergonomics
map('i', '<C-c>', '<Esc>', { desc = 'Esc via C-c (intentional)' })
map('n', 'Q', '<nop>', { desc = 'disable Ex mode' })

-- Clear search highlight on <Esc>
map('n', '<Esc>', '<cmd>nohlsearch<CR>')

-- Quickfix / loclist navigation
map('n', '<C-k>', '<cmd>cnext<CR>zz')
map('n', '<C-j>', '<cmd>cprev<CR>zz')

-- Make current file executable
map('n', '<leader>x', '<cmd>!chmod +x %<CR>', { silent = true, desc = 'chmod +x current file' })
