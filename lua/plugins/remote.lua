-- lua/plugins/remote.lua — static registration of <leader>s* so which-key
-- shows them immediately on <leader>. Keys lazy-load the remote modules
-- on first press.
local function lazy_cmd(mod, fn)
  return function()
    require(mod)[fn]()
  end
end

return {
  dir = vim.fn.stdpath('config'),
  name = 'happy-remote',
  lazy = false,
  keys = {
    { '<leader>ss', lazy_cmd('remote.hosts', 'pick'), desc = 'ssh host picker (frecency)' },
    { '<leader>sd', lazy_cmd('remote.dirs', 'pick'), desc = 'remote dir picker (zoxide-like)' },
    { '<leader>sD', lazy_cmd('remote.dirs', 'refresh'), desc = 'refresh remote dir cache' },
    { '<leader>sB', lazy_cmd('remote.browse', 'browse'), desc = 'browse remote path (scp://)' },
    { '<leader>sf', lazy_cmd('remote.browse', 'find'), desc = 'find remote files (ssh find)' },
    { '<leader>sg', lazy_cmd('remote.grep', 'prompt'), desc = 'remote grep (niced ssh grep)' },
    { '<leader>sO', lazy_cmd('remote.browse', 'force_binary'), desc = 'override binary guard' },
  },
  init = function()
    vim.api.nvim_create_user_command('HappyHostsPrune', function()
      require('remote.hosts').prune()
    end, { desc = 'prune unresolvable hosts from frecency DB' })
  end,
}
