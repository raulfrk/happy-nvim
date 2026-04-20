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
    {
      '<leader>sB',
      lazy_cmd('remote.ssh_buffer', 'browse_prompt'),
      desc = 'ssh:// buffer (host picker → path, RO default)',
    },
    {
      '<leader>sw',
      lazy_cmd('remote.ssh_buffer', 'toggle_writable'),
      desc = 'ssh:// toggle write',
    },
    { '<leader>sf', lazy_cmd('remote.browse', 'find'), desc = 'find remote files (ssh find)' },
    { '<leader>sg', lazy_cmd('remote.grep', 'prompt'), desc = 'remote grep (niced ssh grep)' },
    { '<leader>sO', lazy_cmd('remote.browse', 'force_binary'), desc = 'override binary guard' },
    {
      '<leader>sL',
      lazy_cmd('remote.tail', 'tail_log'),
      desc = 'ssh: log tail (watch-aware, detachable)',
    },
    {
      '<leader>sT',
      function()
        vim.notify('<leader>sT is deprecated — use <leader>sL (log tail).', vim.log.levels.WARN)
        require('remote.tail').tail_log()
      end,
      desc = '[deprecated] use <leader>sL',
    },
    {
      '<leader>sp',
      function()
        local host = vim.b.happy_tail_host
        local path = vim.b.happy_tail_path
        if not host or not path then
          vim.notify('<leader>sp only works inside a tail scratch buffer', vim.log.levels.WARN)
          return
        end
        require('remote.watch_editor').open(host, path)
      end,
      desc = 'ssh: edit watch patterns (in tail scratch)',
    },
    {
      '<leader>sP',
      lazy_cmd('remote.tails_picker', 'open'),
      desc = 'ssh: tails picker (reattach/kill)',
    },
  },
  init = function()
    vim.api.nvim_create_user_command('HappyHostsPrune', function()
      local n = require('remote.hosts').prune()
      vim.notify(string.format('pruned %d stale hosts', n or 0))
    end, { desc = 'prune stale hosts (>90 days unused) from frecency DB' })
  end,
}
