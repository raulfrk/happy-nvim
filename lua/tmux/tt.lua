-- lua/tmux/tt.lua — named+persistent tmux shell popups (tt-* family).
-- Mirrors lua/tmux/claude_popup.lua almost exactly; diffs: session prefix
-- ('tt-' vs 'cc-') and the command launched ($SHELL -l vs 'claude').
local M = {}
local project = require('tmux.project')

M._config = { popup = { width = '85%', height = '85%' } }

function M.setup(opts)
  opts = opts or {}
  if opts.popup then
    M._config.popup.width = opts.popup.width or M._config.popup.width
    M._config.popup.height = opts.popup.height or M._config.popup.height
  end
end

local function sys(args)
  return vim.system(args, { text = true }):wait()
end

local function shell()
  local s = os.getenv('SHELL')
  if s and s ~= '' and vim.fn.executable(s) == 1 then
    return s
  end
  for _, cand in ipairs({ 'zsh', 'bash', 'sh' }) do
    if vim.fn.executable(cand) == 1 then
      return cand
    end
  end
  return nil
end

-- cc-<slug> → tt-<slug>. Keeps the tt family keyed on the same project
-- slug semantics so the session list is easy to reason about.
function M.session_name(slug_override)
  if slug_override then
    return 'tt-' .. slug_override
  end
  local cc = project.session_name() -- 'cc-<slug>'
  return 'tt-' .. cc:sub(4)
end

function M.exists(name)
  return sys({ 'tmux', 'has-session', '-t', name or M.session_name() }).code == 0
end

function M.ensure(name)
  name = name or M.session_name()
  if M.exists(name) then
    return true
  end
  local sh = shell()
  if not sh then
    vim.notify('no shell found on $PATH (tried $SHELL, zsh, bash, sh)', vim.log.levels.ERROR)
    return false
  end
  local cwd = vim.fn.getcwd()
  local res = sys({ 'tmux', 'new-session', '-d', '-s', name, '-c', cwd, sh .. ' -l' })
  if res.code ~= 0 then
    vim.notify('failed to spawn ' .. name .. ': ' .. (res.stderr or ''), vim.log.levels.ERROR)
    return false
  end
  return true
end

function M.open()
  if vim.env.TMUX == nil or vim.env.TMUX == '' then
    vim.notify('tt shell popup requires $TMUX', vim.log.levels.WARN)
    return
  end
  local name = M.session_name()
  if not M.ensure(name) then
    return
  end
  require('tmux._popup').open(M._config.popup.width, M._config.popup.height, 'tmux attach -t ' .. name)
end

function M.new_named()
  vim.ui.input({ prompt = 'Shell slug: ' }, function(slug)
    if not slug or slug == '' then
      return
    end
    local safe = slug:gsub('[^%w%-]', '-'):gsub('%-+', '-')
    local name = 'tt-' .. safe
    if not M.ensure(name) then
      return
    end
    require('tmux._popup').open(M._config.popup.width, M._config.popup.height, 'tmux attach -t ' .. name)
  end)
end

function M.kill(name)
  name = name or M.session_name()
  local r = sys({ 'tmux', 'has-session', '-t', name })
  if r.code ~= 0 then
    return true
  end
  return sys({ 'tmux', 'kill-session', '-t', name }).code == 0
end

function M.reset()
  if M.exists() then
    M.kill()
  end
  M.open()
end

-- List sessions matching '^tt-' — used by M.list picker.
function M._list_sessions()
  local res = sys({ 'tmux', 'list-sessions', '-F', '#{session_name}|#{session_created}' })
  if res.code ~= 0 then
    return {}
  end
  local out = {}
  for line in (res.stdout or ''):gmatch('[^\n]+') do
    local name, created = line:match('^([^|]+)|([^|]+)$')
    if name and name:sub(1, 3) == 'tt-' then
      table.insert(out, { name = name, slug = name:sub(4), created_ts = tonumber(created) or 0 })
    end
  end
  table.sort(out, function(a, b)
    return a.created_ts > b.created_ts
  end)
  return out
end

function M.list()
  local sessions = M._list_sessions()
  if #sessions == 0 then
    vim.notify('no tt-* shells open (<leader>tt to start one)', vim.log.levels.INFO)
    return
  end
  local pickers = require('telescope.pickers')
  local finders = require('telescope.finders')
  local actions = require('telescope.actions')
  local action_state = require('telescope.actions.state')
  local conf = require('telescope.config').values
  pickers
    .new({}, {
      prompt_title = 'tt shells',
      finder = finders.new_table({
        results = sessions,
        entry_maker = function(s)
          return { value = s, display = s.slug, ordinal = s.slug }
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
          require('tmux._popup').open(
            M._config.popup.width,
            M._config.popup.height,
            'tmux attach -t ' .. entry.value.name
          )
        end)
        map({ 'i', 'n' }, '<C-x>', function()
          local entry = action_state.get_selected_entry()
          if not entry then
            return
          end
          M.kill(entry.value.name)
          actions.close(bufnr)
          vim.schedule(M.list)
        end)
        return true
      end,
    })
    :find()
end

return M
