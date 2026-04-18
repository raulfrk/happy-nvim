-- lua/plugins/telescope.lua
return {
  {
    'nvim-telescope/telescope.nvim',
    branch = '0.1.x',
    cmd = 'Telescope',
    keys = {
      { '<leader>ff', '<cmd>Telescope find_files<cr>', desc = 'find files' },
      { '<leader>fg', '<cmd>Telescope git_files<cr>', desc = 'git files' },
      { '<leader>fb', '<cmd>Telescope buffers<cr>', desc = 'buffers' },
      { '<leader>fh', '<cmd>Telescope help_tags<cr>', desc = 'help tags' },
      { '<leader>fr', '<cmd>Telescope oldfiles<cr>', desc = 'recent files' },
      {
        '<leader>fs',
        function()
          require('telescope.builtin').grep_string({
            search = vim.fn.input('Grep > '),
          })
        end,
        desc = 'grep string',
      },
      { '<leader>fw', '<cmd>Telescope live_grep<cr>', desc = 'live grep' },
    },
    dependencies = {
      'nvim-lua/plenary.nvim',
      { 'nvim-telescope/telescope-fzf-native.nvim', build = 'make' },
    },
    config = function()
      local telescope = require('telescope')
      telescope.setup({
        defaults = {
          path_display = { 'truncate' },
          sorting_strategy = 'ascending',
          layout_config = { prompt_position = 'top' },
        },
      })
      telescope.load_extension('fzf')
    end,
  },
}
