-- lua/plugins/hardtime.lua
return {
  'm4xshen/hardtime.nvim',
  event = 'VeryLazy',
  dependencies = { 'MunifTanjim/nui.nvim' },
  opts = {
    disable_mouse = false,
    max_count = 3, -- after 3 hjkl/arrows in a row, suggest {count}j / }
    restriction_mode = 'hint', -- not 'block' — start softly; upgrade later
    hint = true,
  },
}
