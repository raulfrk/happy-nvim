-- lua/config/colors.lua
local aug = vim.api.nvim_create_augroup('happy_colors', { clear = true })

vim.api.nvim_create_autocmd('ColorScheme', {
  group = aug,
  callback = function()
    -- Bump LineNr contrast
    vim.api.nvim_set_hl(0, 'LineNr', { fg = '#565f89' })
    vim.api.nvim_set_hl(0, 'CursorLineNr', { fg = '#c0caf5', bold = true })
    -- Softer float borders
    vim.api.nvim_set_hl(0, 'FloatBorder', { fg = '#565f89', bg = 'NONE' })
  end,
})
