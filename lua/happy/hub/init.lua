-- lua/happy/hub/init.lua — <leader><leader> quick-pivot hub.
local M = {}

local DEFAULT_WEIGHTS = { project = 1.0, session = 0.8, host = 0.6 }
local WEIGHTS = vim.deepcopy(DEFAULT_WEIGHTS)

function M.setup(opts)
  opts = opts or {}
  if opts.weights then
    for k, v in pairs(opts.weights) do
      WEIGHTS[k] = v
    end
  end
  vim.keymap.set('n', '<leader><leader>', function()
    M.open()
  end, { desc = 'Quick pivot: projects + hosts + sessions' })
end

function M._reset_weights_for_test()
  WEIGHTS = vim.deepcopy(DEFAULT_WEIGHTS)
end

local function kind_max(rows, kind)
  local m = 0
  for _, r in ipairs(rows) do
    if r.kind == kind and r.raw_score > m then
      m = r.raw_score
    end
  end
  return m
end

function M._merge_for_test()
  local sources = require('happy.hub.sources')
  local rows = {}
  vim.list_extend(rows, sources.project_rows())
  vim.list_extend(rows, sources.host_rows())
  vim.list_extend(rows, sources.session_rows())

  local maxes = {}
  for kind, _ in pairs(WEIGHTS) do
    maxes[kind] = kind_max(rows, kind)
  end
  for _, r in ipairs(rows) do
    local max = maxes[r.kind] or 0
    local norm = (max > 0) and (r.raw_score / max) or 0
    r.score = norm * (WEIGHTS[r.kind] or 0)
  end
  table.sort(rows, function(a, b)
    return a.score > b.score
  end)
  return rows
end

local KIND_ICONS = {
  project = '',
  host = '󰢹',
  session = '󰚩',
}

local function icon_for(row)
  if row.kind == 'project' then
    local ok, registry = pcall(require, 'happy.projects.registry')
    if ok then
      local entry = registry.get(row.id)
      if entry and entry.kind == 'remote' then
        return ''
      end
    end
    return ''
  end
  return KIND_ICONS[row.kind] or '?'
end

function M.open()
  local rows = M._merge_for_test()
  local pickers = require('telescope.pickers')
  local finders = require('telescope.finders')
  local actions = require('telescope.actions')
  local action_state = require('telescope.actions.state')
  local conf = require('telescope.config').values

  pickers
    .new({}, {
      prompt_title = 'Quick pivot: projects + hosts + sessions',
      finder = finders.new_table({
        results = rows,
        entry_maker = function(r)
          local display = string.format(
            '%s %-24s  %s  %s',
            icon_for(r),
            r.id:sub(1, 24),
            r.label or '',
            r.status or ''
          )
          return {
            value = r,
            display = display,
            ordinal = r.kind .. ' ' .. r.id .. ' ' .. (r.label or ''),
          }
        end,
      }),
      sorter = conf.generic_sorter({}),
      attach_mappings = function(bufnr)
        actions.select_default:replace(function()
          actions.close(bufnr)
          local sel = action_state.get_selected_entry()
          if sel and sel.value and sel.value.on_pivot then
            sel.value.on_pivot()
          end
        end)
        return true
      end,
    })
    :find()
end

return M
