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
      signature = { enabled = true },
      hover = { enabled = true },
      -- skip progress messages (LSP spam in notify stack)
      progress = { enabled = false },
      message = { enabled = false },
    },
    -- don't replace cmdline / messages — keep nvim's native UI to
    -- avoid overlap with lualine + notify popups over mosh+tmux
    cmdline = { enabled = false },
    messages = { enabled = false },
    notify = { enabled = true },
    presets = {
      bottom_search = true,
      command_palette = false,
      long_message_to_split = true,
      lsp_doc_border = true,
    },
    routes = {
      -- drop "written", "lines yanked" etc. from floating notify
      {
        filter = { event = 'msg_show', any = {
          { find = '%d+L, %d+B' },
          { find = '; after #%d+' },
          { find = '; before #%d+' },
          { find = '%d+ lines yanked' },
        } },
        opts = { skip = true },
      },
    },
  },
}
