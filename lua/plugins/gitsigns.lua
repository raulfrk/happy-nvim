return {
  'lewis6991/gitsigns.nvim',
  event = { 'BufReadPre', 'BufNewFile' },
  opts = {
    signs = {
      add = { text = '│' },
      change = { text = '│' },
      delete = { text = '_' },
      topdelete = { text = '‾' },
      changedelete = { text = '~' },
    },
    on_attach = function(bufnr)
      local gs = require('gitsigns')
      local map = function(m, l, r, desc)
        vim.keymap.set(m, l, r, { buffer = bufnr, desc = desc })
      end
      map('n', ']h', gs.next_hunk, 'next hunk')
      map('n', '[h', gs.prev_hunk, 'prev hunk')
      map('n', '<leader>gp', gs.preview_hunk, 'preview hunk')
      map('n', '<leader>gb', function()
        gs.blame_line({ full = true })
      end, 'blame line')
      map('n', '<leader>gr', gs.reset_hunk, 'reset hunk')
    end,
  },
}
