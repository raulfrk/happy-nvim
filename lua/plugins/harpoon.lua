-- lua/plugins/harpoon.lua
return {
  'ThePrimeagen/harpoon',
  branch = 'harpoon2',
  event = 'VeryLazy',
  dependencies = { 'nvim-lua/plenary.nvim' },
  config = function()
    local harpoon = require('harpoon')
    harpoon:setup()
    local map = vim.keymap.set
    map('n', '<leader>ha', function()
      harpoon:list():add()
    end, { desc = 'harpoon add' })
    map('n', '<C-e>', function()
      harpoon.ui:toggle_quick_menu(harpoon:list())
    end, { desc = 'harpoon menu' })
    map('n', '<C-h>', function()
      harpoon:list():select(1)
    end)
    map('n', '<C-t>', function()
      harpoon:list():select(2)
    end)
    map('n', '<C-n>', function()
      harpoon:list():select(3)
    end)
    map('n', '<C-s>', function()
      harpoon:list():select(4)
    end)
  end,
}
