-- lua/plugins/lsp.lua
return {
  {
    'williamboman/mason.nvim',
    cmd = 'Mason',
    build = ':MasonUpdate',
    opts = {},
  },
  {
    'williamboman/mason-lspconfig.nvim',
    event = { 'BufReadPre', 'BufNewFile' },
    dependencies = { 'williamboman/mason.nvim' },
  },
  {
    'WhoIsSethDaniel/mason-tool-installer.nvim',
    event = 'VeryLazy',
    dependencies = { 'williamboman/mason.nvim' },
    opts = {
      ensure_installed = {
        -- formatters
        'stylua',
        'ruff',
        'goimports',
        'gofumpt',
        'shfmt',
        'yamlfmt',
        'clang-format',
        -- linters
        'selene',
      },
    },
  },
  {
    'neovim/nvim-lspconfig',
    event = { 'BufReadPre', 'BufNewFile' },
    dependencies = {
      'williamboman/mason-lspconfig.nvim',
      'saghen/blink.cmp',
    },
    config = function()
      local lspconfig = require('lspconfig')
      local capabilities = require('blink.cmp').get_lsp_capabilities()

      -- LspAttach keymaps (spec §BUG-2 namespace: <leader>l*, diagnostics d*)
      vim.api.nvim_create_autocmd('LspAttach', {
        group = vim.api.nvim_create_augroup('happy_lsp_attach', { clear = true }),
        callback = function(ev)
          local map = function(lhs, rhs, desc)
            vim.keymap.set('n', lhs, rhs, { buffer = ev.buf, desc = desc })
          end
          map('gd', vim.lsp.buf.definition, 'goto definition')
          map('gD', vim.lsp.buf.declaration, 'goto declaration')
          map('gi', vim.lsp.buf.implementation, 'goto implementation')
          map('go', vim.lsp.buf.type_definition, 'goto type def')
          map('gr', vim.lsp.buf.references, 'references')
          map('K', vim.lsp.buf.hover, 'hover')
          map('<leader>la', vim.lsp.buf.code_action, 'code action')
          map('<leader>lr', vim.lsp.buf.rename, 'rename')
          map('<leader>de', vim.diagnostic.open_float, 'diag float')
          map('<leader>dn', function()
            vim.diagnostic.goto_next()
          end, 'next diag')
          map('<leader>dp', function()
            vim.diagnostic.goto_prev()
          end, 'prev diag')
        end,
      })

      vim.api.nvim_create_user_command('HappyLspInfo', function()
        local clients = vim.lsp.get_clients({ bufnr = 0 })
        if #clients == 0 then
          vim.notify('No LSP clients attached to this buffer.', vim.log.levels.INFO)
          return
        end
        for _, c in ipairs(clients) do
          print(('• %s (id=%d, root=%s)'):format(c.name, c.id, c.config.root_dir or '?'))
        end
      end, { desc = 'Show attached LSP clients (0.12-safe replacement for :LspInfo)' })

      -- Server setup via mason-lspconfig
      require('mason-lspconfig').setup({
        ensure_installed = {
          'lua_ls',
          'pylsp',
          'gopls',
          'bashls',
          'yamlls',
          'marksman',
          'clangd',
        },
        handlers = {
          function(server)
            lspconfig[server].setup({ capabilities = capabilities })
          end,
          ['pylsp'] = function()
            lspconfig.pylsp.setup({
              capabilities = capabilities,
              settings = {
                pylsp = {
                  plugins = {
                    mypy = { enabled = true, live_mode = false },
                    ruff = { enabled = true },
                  },
                },
              },
            })
          end,
          ['lua_ls'] = function()
            lspconfig.lua_ls.setup({
              capabilities = capabilities,
              settings = {
                Lua = {
                  workspace = { checkThirdParty = false },
                  diagnostics = { globals = { 'vim' } },
                  telemetry = { enable = false },
                },
              },
            })
          end,
        },
      })
    end,
  },
}
