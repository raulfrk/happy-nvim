-- lua/plugins/notify.lua
return {
  'rcarriga/nvim-notify',
  lazy = true,
  opts = {
    timeout = 3000,
    render = 'wrapped-compact',
    stages = 'fade',
  },
  init = function()
    vim.notify = function(...)
      return require('notify')(...)
    end
  end,
}
