-- lua/tmux/init.lua
local M = {}

function M.setup(user_opts)
  if vim.env.TMUX == nil or vim.env.TMUX == '' then
    return -- spec §7.3: entire module no-ops outside tmux
  end
  user_opts = user_opts or {}
  require('tmux.claude').setup(user_opts.claude)
  require('tmux.popup').setup(user_opts.popup)
  require('tmux.idle').setup(user_opts.alert)
end

return M
