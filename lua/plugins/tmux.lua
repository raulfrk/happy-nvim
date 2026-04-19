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
    {
      '<leader>cl',
      lazy_cmd('tmux.picker', 'open'),
      desc = 'Claude: list + attach sessions',
    },
    {
      '<leader>cn',
      function()
        vim.ui.input({ prompt = 'Project slug for new Claude: ' }, function(slug)
          if not slug or slug == '' then
            return
          end
          local safe = slug:gsub('[^%w%-]', '-'):gsub('%-+', '-')
          local name = 'cc-' .. safe
          local cwd = vim.fn.expand('%:p:h')
          if cwd == '' then
            cwd = vim.fn.getcwd()
          end
          vim.system({ 'tmux', 'new-session', '-d', '-s', name, '-c', cwd, 'claude' }):wait()
          vim
            .system({
              'tmux',
              'display-popup',
              '-E',
              '-w',
              '85%',
              '-h',
              '85%',
              'tmux attach -t ' .. name,
            })
            :wait()
        end)
      end,
      desc = 'Claude: new named session (prompts for slug)',
    },
    {
      '<leader>ck',
      function()
        local popup = require('tmux.claude_popup')
        if not popup.exists() then
          vim.notify('no Claude session for this project', vim.log.levels.INFO)
          return
        end
        if vim.fn.confirm("Kill current project's Claude session?", '&Yes\n&No') == 1 then
          popup.kill()
          vim.notify('killed ' .. require('tmux.project').session_name(), vim.log.levels.INFO)
        end
      end,
      desc = "Claude: kill current project's session",
    },
    {
      '<leader>cq',
      function()
        require('tmux.claude').open_scratch_guarded()
      end,
      desc = 'Claude: quick scratch popup (single-shot)',
    },
    { '<leader>tg', lazy_cmd('tmux.popup', 'lazygit'), desc = 'tmux popup: lazygit' },
    { '<leader>tt', lazy_cmd('tmux.popup', 'scratch'), desc = 'tmux popup: shell (git root)' },
    { '<leader>tb', lazy_cmd('tmux.popup', 'btop'), desc = 'tmux popup: btop' },
  },
}
