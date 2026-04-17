-- lua/plugins/tmux.lua — static registration of <leader>c* and <leader>t*
-- so which-key shows them immediately on <leader>. Keys lazy-load the
-- tmux module on first press.
local function lazy_cmd(mod, fn)
  return function()
    require(mod)[fn]()
  end
end

return {
  dir = vim.fn.stdpath('config'),
  name = 'happy-tmux',
  lazy = false,
  keys = {
    { '<leader>cc', lazy_cmd('tmux.claude', 'open_guarded'), desc = 'Claude: open/attach pane' },
    { '<leader>cf', lazy_cmd('tmux.claude', 'send_file_guarded'), desc = 'Claude: send @file ref' },
    {
      '<leader>cs',
      lazy_cmd('tmux.claude', 'send_selection_guarded'),
      mode = 'v',
      desc = 'Claude: send selection',
    },
    {
      '<leader>ce',
      lazy_cmd('tmux.claude', 'send_errors_guarded'),
      desc = 'Claude: send diagnostics',
    },
    {
      '<leader>cp',
      lazy_cmd('tmux.claude_popup', 'open'),
      desc = 'Claude: toggle popup (detached session)',
    },
    {
      '<leader>cC',
      lazy_cmd('tmux.claude', 'open_fresh_guarded'),
      desc = 'Claude: fresh pane (kill + respawn)',
    },
    {
      '<leader>cP',
      lazy_cmd('tmux.claude_popup', 'fresh'),
      desc = 'Claude: fresh popup (kill + respawn)',
    },
    { '<leader>tg', lazy_cmd('tmux.popup', 'lazygit'), desc = 'tmux popup: lazygit' },
    { '<leader>tt', lazy_cmd('tmux.popup', 'scratch'), desc = 'tmux popup: shell (git root)' },
    { '<leader>tb', lazy_cmd('tmux.popup', 'btop'), desc = 'tmux popup: btop' },
  },
}
