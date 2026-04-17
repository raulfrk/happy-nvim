-- lua/plugins/noice.lua
return {
  'folke/noice.nvim',
  event = 'VeryLazy',
  dependencies = {
    'MunifTanjim/nui.nvim',
    'rcarriga/nvim-notify',
  },
  opts = {
    lsp = {
      override = {
        ['vim.lsp.util.convert_input_to_markdown_lines'] = true,
        ['vim.lsp.util.stylize_markdown'] = true,
        ['cmp.entry.get_documentation'] = true,
      },
      signature = { enabled = true }, -- inline LSP signature popups (spec §5.1.5)
      hover = { enabled = true },
    },
    presets = {
      bottom_search = true,
      command_palette = true, -- center-screen cmdline popup
      long_message_to_split = true,
      lsp_doc_border = true,
    },
  },
}
