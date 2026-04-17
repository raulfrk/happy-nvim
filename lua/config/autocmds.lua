-- lua/config/autocmds.lua

local aug = vim.api.nvim_create_augroup('happy_autocmds', { clear = true })

-- Highlight yanked text briefly
vim.api.nvim_create_autocmd('TextYankPost', {
  group = aug,
  callback = function()
    vim.highlight.on_yank({ higroup = 'IncSearch', timeout = 150 })
  end,
})

-- Re-check files changed on disk when nvim regains focus
vim.api.nvim_create_autocmd({ 'FocusGained', 'BufEnter' }, {
  group = aug,
  command = 'checktime',
})

-- Per-filetype colorcolumn (BUG-3 fix: was hardcoded 80 globally)
local cc_map = {
  markdown = '80', text = '80',
  lua = '120', go = '120', python = '120',
  c = '120', cpp = '120', sh = '120', yaml = '120',
}
vim.api.nvim_create_autocmd('FileType', {
  group = aug,
  callback = function(ev)
    if vim.bo[ev.buf].buftype ~= '' then
      return
    end
    vim.opt_local.colorcolumn = cc_map[ev.match] or ''
  end,
})

-- Strip trailing whitespace on save (excluding markdown where it matters for line breaks)
vim.api.nvim_create_autocmd('BufWritePre', {
  group = aug,
  callback = function(ev)
    if vim.bo[ev.buf].filetype == 'markdown' then
      return
    end
    local view = vim.fn.winsaveview()
    vim.cmd([[keeppatterns %s/\s\+$//e]])
    vim.fn.winrestview(view)
  end,
})
