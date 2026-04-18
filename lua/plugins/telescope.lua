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
      -- Compat shims for telescope 0.1.x previewer against nvim-treesitter
      -- main branch (1.0 API). main dropped the legacy module: parsers is now
      -- a plain config table (no ft_to_lang) and configs/.is_enabled is gone.
      -- Telescope's treesitter_attach calls both — first ts_parsers.ft_to_lang,
      -- then ts_configs.is_enabled. Stubbing is_enabled to false makes the
      -- previewer return early, falling back to vim regex syntax (still
      -- highlighted, just not via treesitter). Mutating cached require()
      -- tables propagates because Lua caches them by reference.
      local ok_p, ts_parsers = pcall(require, 'nvim-treesitter.parsers')
      if ok_p and not ts_parsers.ft_to_lang then
        ts_parsers.ft_to_lang = vim.treesitter.language.get_lang
      end
      local ok_c, ts_configs = pcall(require, 'nvim-treesitter.configs')
      if ok_c and not ts_configs.is_enabled then
        ts_configs.is_enabled = function()
          return false
        end
      end

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
