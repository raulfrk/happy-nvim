-- lua/remote/find.lua — <leader>sf remote file-name finder.
local M = {}

local function shell_escape(s)
  return "'" .. s:gsub("'", "'\\''") .. "'"
end

function M._list_then_pick(host, dir)
  local util = require('remote.util')
  local cmd = {
    'ssh',
    host,
    ('find %s -type f -maxdepth 6 2>/dev/null'):format(shell_escape(dir)),
  }
  local result = util.run(cmd, { text = true }, 30000)
  if result.code ~= 0 then
    vim.notify('remote find failed: ' .. (result.stderr or ''), vim.log.levels.ERROR)
    return
  end
  local paths = vim.split(result.stdout or '', '\n', { trimempty = true })
  if #paths == 0 then
    vim.notify('no files under ' .. dir, vim.log.levels.INFO)
    return
  end
  local pickers = require('telescope.pickers')
  local finders = require('telescope.finders')
  local conf = require('telescope.config').values
  local actions = require('telescope.actions')
  local action_state = require('telescope.actions.state')
  pickers
    .new({}, {
      prompt_title = ('remote find: %s:%s'):format(host, dir),
      finder = finders.new_table({ results = paths }),
      sorter = conf.generic_sorter({}),
      attach_mappings = function(bufnr)
        actions.select_default:replace(function()
          local sel = action_state.get_selected_entry()
          actions.close(bufnr)
          if sel and sel[1] then
            vim.cmd('edit scp://' .. host .. '/' .. sel[1])
          end
        end)
        return true
      end,
    })
    :find()
end

function M.find_file()
  require('remote.hosts').pick(function(host)
    vim.ui.input({
      prompt = 'Remote dir to search (default: /): ',
      default = '/',
    }, function(dir)
      if not dir or dir == '' then
        return
      end
      M._list_then_pick(host, dir)
    end)
  end)
end

return M
