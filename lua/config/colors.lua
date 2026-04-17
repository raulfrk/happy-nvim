-- lua/config/colors.lua
-- Highlight-group overrides. Applied after the theme loads via ColorScheme
-- autocmd so overrides survive `:colorscheme` swaps.

local aug = vim.api.nvim_create_augroup('happy_colors', { clear = true })

vim.api.nvim_create_autocmd('ColorScheme', {
  group = aug,
  callback = function()
    -- placeholder — overrides added in Task 12
  end,
})
