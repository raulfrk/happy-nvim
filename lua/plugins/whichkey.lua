-- lua/plugins/whichkey.lua — namespace table enforcement (spec §BUG-2)
return {
  'folke/which-key.nvim',
  event = 'VeryLazy',
  config = function()
    local wk = require('which-key')
    wk.setup({
      preset = 'modern',
      delay = 400, -- spec §5.1.5: 400ms to not interrupt muscle memory
      notify = false,
    })

    wk.add({
      { '<leader>f', group = 'find / files (telescope)' },
      { '<leader>g', group = 'git' },
      { '<leader>l', group = 'LSP' },
      { '<leader>d', group = 'diagnostics' },
      { '<leader>h', group = 'harpoon' },
      { '<leader>s', group = 'ssh / remote' },
      { '<leader>c', group = 'Claude (tmux)' },
      { '<leader>t', group = 'tmux popups' },
      { '<leader>?', group = 'cheatsheet / coach' },
    })

    -- Visual-mode text-object hints (spec §5.1.5)
    wk.add({
      mode = 'v',
      { 'iw', desc = 'inside word' },
      { 'aw', desc = 'a word' },
      { 'ip', desc = 'inside paragraph' },
      { 'ap', desc = 'a paragraph' },
      { 'it', desc = 'inside tag' },
      { 'at', desc = 'a tag' },
      { 'i"', desc = 'inside double-quotes' },
      { "i'", desc = 'inside single-quotes' },
      { 'i(', desc = 'inside parens' },
      { 'i[', desc = 'inside brackets' },
      { 'i{', desc = 'inside braces' },
    })
  end,
}
