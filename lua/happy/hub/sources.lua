-- lua/happy/hub/sources.lua — source aggregators for happy.hub.
--
-- Each source returns a list of entries shaped:
--   { kind, id, label, status, raw_score, on_pivot }
--
-- Sources are PURE READERS — never mutate registry / hosts / tmux state.
local M = {}

local run_tmux = function(args)
  local out = vim.fn.system(args)
  if vim.v.shell_error ~= 0 then
    return ''
  end
  return out
end

function M._set_tmux_fn_for_test(fn)
  run_tmux = fn
end

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

function M.project_rows()
  local ok, registry = pcall(require, 'happy.projects.registry')
  if not ok then
    return {}
  end
  local rows = {}
  for _, entry in ipairs(registry.list()) do
    local label
    if entry.kind == 'remote' then
      label = ('%s:%s'):format(entry.host or '?', entry.path or '?')
    else
      label = entry.path or '?'
    end
    local id = entry.id
    table.insert(rows, {
      kind = 'project',
      id = id,
      label = label,
      status = fmt_age(entry.last_opened),
      raw_score = registry.score(id) or 0,
      on_pivot = function()
        require('happy.projects.pivot').pivot(id)
      end,
    })
  end
  return rows
end

function M.host_rows()
  local ok, hosts = pcall(require, 'remote.hosts')
  if not ok then
    return {}
  end
  local rows = {}
  for _, entry in ipairs(hosts.list()) do
    if entry.marker ~= 'add' then
      local host = entry.host
      table.insert(rows, {
        kind = 'host',
        id = host,
        label = 'ssh ' .. host,
        status = '',
        raw_score = entry.score or 0,
        on_pivot = function()
          hosts.record(host)
          local mosh = vim.fn.executable('mosh') == 1 and 'mosh' or 'ssh'
          vim.system({ 'tmux', 'new-window', mosh .. ' ' .. host }):wait()
        end,
      })
    end
  end
  return rows
end

function M.session_rows()
  local raw = run_tmux({ 'tmux', 'list-sessions', '-F', '#S' })
  if raw == '' then
    return {}
  end
  local ok_reg, registry = pcall(require, 'happy.projects.registry')
  local rows = {}
  for name in raw:gmatch('[^\n]+') do
    local id = name:match('^cc%-(.+)') or name:match('^remote%-(.+)')
    if id then
      local in_registry = ok_reg and registry.get(id) or nil
      if not in_registry then
        table.insert(rows, {
          kind = 'session',
          id = name,
          label = '(orphan)',
          status = 'alive',
          raw_score = 0.5,
          on_pivot = function()
            if vim.env.TMUX and vim.env.TMUX ~= '' then
              vim.system({ 'tmux', 'switch-client', '-t', name }):wait()
            else
              vim.notify(
                name .. ' is alive — attach via `tmux attach -t ' .. name .. '`.',
                vim.log.levels.INFO
              )
            end
          end,
        })
      end
    end
  end
  return rows
end

return M
