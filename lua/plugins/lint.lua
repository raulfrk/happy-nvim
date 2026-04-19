-- lua/plugins/lint.lua
return {
  'mfussenegger/nvim-lint',
  event = { 'BufReadPre', 'BufNewFile' },
  config = function()
    local lint = require('lint')
    lint.linters_by_ft = {
      lua = { 'selene' },
    }
    vim.api.nvim_create_autocmd({ 'BufWritePost', 'BufReadPost' }, {
      group = vim.api.nvim_create_augroup('happy_lint', { clear = true }),
      callback = function()
        local linters = lint.linters_by_ft[vim.bo.filetype] or {}
        local runnable = vim.tbl_filter(function(l)
          return vim.fn.executable(l) == 1
        end, linters)
        if #runnable > 0 then
          lint.try_lint(runnable)
        end
      end,
    })
  end,
}
