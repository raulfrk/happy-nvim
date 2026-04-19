-- lua/happy/projects/picker.lua
local registry = require('happy.projects.registry')

local M = {}

local function fmt_age(ts)
  if not ts or ts == 0 then
    return 'never'
  end
  local d = os.time() - ts
  if d < 60 then
    return ('%ds ago'):format(d)
  end
  if d < 3600 then
    return ('%dm ago'):format(math.floor(d / 60))
  end
  if d < 86400 then
    return ('%dh ago'):format(math.floor(d / 3600))
  end
  return ('%dd ago'):format(math.floor(d / 86400))
end

local function entry_line(entry)
  local icon = entry.kind == 'remote' and '' or ''
  local label
  if entry.kind == 'remote' then
    label = ('%s:%s'):format(entry.host, entry.path)
  else
    label = entry.path
  end
  return ('%s %s · %s · %s'):format(icon, entry.id, label, fmt_age(entry.last_opened))
end

local function parse_add_input(text)
  -- host:path (remote) vs /path or ~/path (local)
  if text:sub(1, 1) == '/' or text:sub(1, 1) == '~' then
    return { kind = 'local', path = vim.fn.expand(text) }
  end
  local host, path = text:match('^([^:]+):(.+)$')
  if host and path then
    return { kind = 'remote', host = host, path = path }
  end
  return nil
end

function M.open(opts)
  local pickers = require('telescope.pickers')
  local finders = require('telescope.finders')
  local conf = require('telescope.config').values
  local actions = require('telescope.actions')
  local action_state = require('telescope.actions.state')
  opts = opts or {}
  local filter = opts.filter or function()
    return true
  end
  local entries = vim.tbl_filter(filter, registry.sorted_by_score())

  pickers
    .new(opts, {
      prompt_title = opts.title or 'Projects [<C-a> add] [<C-d> forget] [<C-p> peek]',
      finder = finders.new_table({
        results = entries,
        entry_maker = function(e)
          return { value = e, display = entry_line(e), ordinal = entry_line(e), id = e.id }
        end,
      }),
      sorter = conf.generic_sorter(opts),
      attach_mappings = function(prompt_bufnr, map)
        actions.select_default:replace(function()
          local sel = action_state.get_selected_entry()
          actions.close(prompt_bufnr)
          if sel then
            require('happy.projects.pivot').pivot(sel.value.id)
          end
        end)
        map('i', '<C-a>', function()
          local line = action_state.get_current_line()
          local spec = parse_add_input(line)
          if not spec then
            vim.notify('cannot parse: need /path or host:path', vim.log.levels.WARN)
            return
          end
          local id = registry.add(spec)
          if spec.kind == 'remote' then
            require('happy.projects.remote').provision(id)
          end
          actions.close(prompt_bufnr)
          vim.schedule(function()
            M.open(opts)
          end)
        end)
        map('i', '<C-d>', function()
          local sel = action_state.get_selected_entry()
          if sel then
            registry.forget(sel.value.id)
            actions.close(prompt_bufnr)
            vim.schedule(function()
              M.open(opts)
            end)
          end
        end)
        map('i', '<C-p>', function()
          local sel = action_state.get_selected_entry()
          if sel then
            require('happy.projects.pivot').peek(sel.value.id)
          end
        end)
        return true
      end,
    })
    :find()
end

return M
