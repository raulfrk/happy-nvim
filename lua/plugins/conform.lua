-- lua/plugins/conform.lua — single source of truth for formatting (spec §BUG-1)
return {
  'stevearc/conform.nvim',
  event = { 'BufWritePre' },
  cmd = 'ConformInfo',
  opts = {
    formatters_by_ft = {
      lua = { 'stylua' },
      python = { 'ruff_format', 'ruff_organize_imports' },
      go = { 'goimports', 'gofumpt' },
      javascript = { 'biome' },
      typescript = { 'biome' },
      sh = { 'shfmt' },
      yaml = { 'yamlfmt' },
      cpp = { 'clang-format' },
      c = { 'clang-format' },
    },
    format_on_save = { timeout_ms = 500, lsp_fallback = true },
  },
  keys = {
    {
      '<leader>lf',
      function()
        require('conform').format({ async = true, lsp_fallback = true })
      end,
      mode = { 'n', 'v' },
      desc = 'format buffer',
    },
  },
}
