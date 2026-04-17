-- lua/plugins/colorscheme.lua
return {
  'folke/tokyonight.nvim',
  lazy = false, -- theme loads at startup
  priority = 1000, -- before anything that reads highlight groups
  config = function()
    require('tokyonight').setup({
      style = 'storm',
      styles = { comments = { italic = true } },
    })
    vim.cmd.colorscheme('tokyonight')
  end,
}
