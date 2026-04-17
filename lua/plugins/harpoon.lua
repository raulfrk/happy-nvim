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
    map('n', '<leader>h1', function() harpoon:list():select(1) end)
    map('n', '<leader>h2', function() harpoon:list():select(2) end)
    map('n', '<leader>h3', function() harpoon:list():select(3) end)
    map('n', '<leader>h4', function() harpoon:list():select(4) end)
  end,
}
