-- lua/remote/init.lua
local M = {}

function M.setup()
  require('remote.hosts').setup()
  require('remote.dirs').setup()
  require('remote.browse').setup()
  require('remote.grep').setup()
  vim.keymap.set('n', '<leader>sc', function()
    require('remote.cmd').run_cmd()
  end, { desc = 'Remote: ad-hoc cmd (streams to scratch)' })
  vim.keymap.set('n', '<leader>sT', function()
    require('remote.tail').tail_log()
  end, { desc = 'Remote: log tail (tail -F)' })
  vim.keymap.set('n', '<leader>sf', function()
    require('remote.find').find_file()
  end, { desc = 'Remote: find file (find + telescope)' })
end

return M
