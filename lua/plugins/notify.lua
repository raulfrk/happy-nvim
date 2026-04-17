-- lua/plugins/notify.lua
return {
  'rcarriga/nvim-notify',
  lazy = true,
  opts = {
    timeout = 2500,
    render = 'compact',
    stages = 'static', -- no fade animation over mosh (avoids redraw storms)
    max_height = function()
      return math.floor(vim.o.lines * 0.4)
    end,
    max_width = function()
      return math.floor(vim.o.columns * 0.4)
    end,
    top_down = false, -- anchor bottom-right; less UI overlap
  },
  init = function()
    vim.notify = function(...)
      return require('notify')(...)
    end
  end,
}
