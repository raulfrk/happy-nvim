-- Ambient status for registered projects.
--
-- Renders compact indicators (✓ idle / ⟳ working / ? stale / ✗ dead)
-- for each project in the registry, truncated to 5 w/ "…+N" suffix.
-- Two consumers:
--   * lualine component (lua/plugins/lualine.lua) — redrawn on every
--     statusline refresh.
--   * tmux status-right format helper — optional; user wires via
--     `run-shell` or a periodic timer.
--
-- `M.poll` walks `tmux list-sessions`, checks @claude_idle for each
-- session, updates an internal STATE map keyed by project id. Poll
-- errors (no tmux server) leave prior state untouched and return early.
local registry = require('happy.projects.registry')
local M = {}

local ICONS = { idle = '✓', working = '⟳', stale = '?', dead = '✗' }
local STATE = {} -- { [id] = 'idle'|'working'|'stale'|'dead' }

local function session_for(entry)
  if entry.kind == 'remote' then
    return 'remote-' .. entry.id
  end
  return 'cc-' .. entry.id
end

-- Ask tmux whether a given session is idle. Relies on the @claude_idle
-- user-option written by lua/tmux/idle.lua — '1' means the pane has
-- been quiet for DEBOUNCE_SECS, anything else means working.
local function is_session_idle(name)
  local res = vim
    .system({ 'tmux', 'show-options', '-t', name, '-v', '@claude_idle' }, { text = true })
    :wait()
  if res.code ~= 0 then
    return false
  end
  local val = (res.stdout or ''):gsub('%s+$', '')
  return val == '1'
end

function M.poll()
  local res = vim.system({ 'tmux', 'list-sessions', '-F', '#S' }, { text = true }):wait()
  if res.code ~= 0 then
    return
  end
  local alive = {}
  for s in (res.stdout or ''):gmatch('[^\n]+') do
    alive[s] = true
  end
  for _, entry in ipairs(registry.list()) do
    local name = session_for(entry)
    if not alive[name] then
      STATE[entry.id] = 'dead'
    elseif is_session_idle(name) then
      STATE[entry.id] = 'idle'
    else
      STATE[entry.id] = 'working'
    end
  end
end

function M.format_for_statusline()
  local entries = registry.sorted_by_score()
  if #entries == 0 then
    return ''
  end
  local parts = {}
  local shown = 0
  for _, e in ipairs(entries) do
    if shown >= 5 then
      break
    end
    local s = STATE[e.id] or 'stale'
    table.insert(parts, (ICONS[s] or '?') .. ' ' .. e.id)
    shown = shown + 1
  end
  local extra = #entries - shown
  if extra > 0 then
    table.insert(parts, ('…+%d'):format(extra))
  end
  return table.concat(parts, ' · ')
end

function M.tmux_status_right()
  return M.format_for_statusline()
end

function M.start_timer()
  if M._timer then
    return
  end
  M._timer = vim.uv.new_timer()
  M._timer:start(
    0,
    2000,
    vim.schedule_wrap(function()
      M.poll()
    end)
  )
end

function M.stop_timer()
  if M._timer then
    M._timer:stop()
    M._timer:close()
    M._timer = nil
  end
end

-- test hook
function M._set_state_for_test(tbl)
  STATE = tbl
end

return M
