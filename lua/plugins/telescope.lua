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
      -- main branch (1.0 API). main dropped the legacy module surface:
      --   * parsers is now a plain config table (no ft_to_lang)
      --   * configs module is gone entirely (no is_enabled / get_module)
      -- Telescope's treesitter_attach calls all three. Strategy:
      --   * parsers exists → mutate cached require() table to add ft_to_lang.
      --   * configs missing → preload package.loaded with a stub table so
      --     telescope's `pcall(require, 'nvim-treesitter.configs')` returns it.
      -- is_enabled returning false makes treesitter_attach early-return; the
      -- previewer falls back to vim regex syntax (still colored, no TS).
      local ok_p, ts_parsers = pcall(require, 'nvim-treesitter.parsers')
      if ok_p and type(ts_parsers) == 'table' and not ts_parsers.ft_to_lang then
        ts_parsers.ft_to_lang = vim.treesitter.language.get_lang
      end

      if not package.loaded['nvim-treesitter.configs'] then
        package.loaded['nvim-treesitter.configs'] = {
          is_enabled = function()
            return false
          end,
          get_module = function()
            return {}
          end,
        }
      else
        local ts_configs = package.loaded['nvim-treesitter.configs']
        if type(ts_configs) == 'table' then
          ts_configs.is_enabled = ts_configs.is_enabled
            or function()
              return false
            end
          ts_configs.get_module = ts_configs.get_module
            or function()
              return {}
            end
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
