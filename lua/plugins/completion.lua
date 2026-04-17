-- lua/plugins/completion.lua
return {
  {
    'saghen/blink.cmp',
    version = 'v0.7.*',
    event = 'InsertEnter',
    dependencies = { 'L3MON4D3/LuaSnip', version = 'v2.*' },
    opts = {
      keymap = { preset = 'default' },
      sources = {
        default = { 'lsp', 'path', 'snippets', 'buffer' },
      },
      completion = {
        documentation = { auto_show = true, auto_show_delay_ms = 300 },
      },
      snippets = { preset = 'luasnip' },
    },
  },
}
