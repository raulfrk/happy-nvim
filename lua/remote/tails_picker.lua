-- lua/remote/tails_picker.lua — <leader>sP: list detached/active tail
-- sessions; Enter reattaches (opens scratch tailing the state file);
-- C-x kills the tmux session entirely.
local M = {}

function M.open()
  local tail = require('remote.tail')
  local entries = tail.list_sessions()
  if #entries == 0 then
    vim.notify('no tail sessions (start one with <leader>sL)', vim.log.levels.INFO)
    return
  end
  local pickers = require('telescope.pickers')
  local finders = require('telescope.finders')
  local actions = require('telescope.actions')
  local action_state = require('telescope.actions.state')
  local conf = require('telescope.config').values
  pickers
    .new({}, {
      prompt_title = 'tail sessions',
      finder = finders.new_table({
        results = entries,
        entry_maker = function(e)
          return {
            value = e,
            display = ('%-40s  %s:%s'):format(e.name, e.host, e.path),
            ordinal = e.name,
          }
        end,
      }),
      sorter = conf.generic_sorter({}),
      attach_mappings = function(bufnr, map)
        actions.select_default:replace(function()
          local entry = action_state.get_selected_entry()
          actions.close(bufnr)
          if not entry then
            return
          end
          tail.reattach(entry.value.name)
        end)
        map({ 'i', 'n' }, '<C-x>', function()
          local entry = action_state.get_selected_entry()
          if not entry then
            return
          end
          tail.kill(entry.value.name)
          actions.close(bufnr)
          vim.schedule(M.open)
        end)
        return true
      end,
    })
    :find()
end

return M
