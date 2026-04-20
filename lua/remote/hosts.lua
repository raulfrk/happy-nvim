-- lua/remote/hosts.lua
local M = {}

local DB_PATH = vim.fn.stdpath('data') .. '/happy-nvim/hosts.json'
local SSH_CONFIG_PATH = vim.fn.expand('~/.ssh/config')

function M._set_db_path_for_test(p)
  DB_PATH = p
end

function M._set_ssh_config_path_for_test(p)
  SSH_CONFIG_PATH = p
end

function M._score(entry, now)
  local days_since = (now - entry.last_used) / 86400
  return entry.visits * math.exp(-days_since / 14)
end

function M._read_db()
  local f = io.open(DB_PATH, 'r')
  if not f then
    return {}
  end
  local raw = f:read('*a')
  f:close()
  local ok, db = pcall(vim.json.decode, raw)
  if not ok then
    vim.fn.delete(DB_PATH)
    return {}
  end
  return db or {}
end

function M._parse_ssh_config()
  local path = SSH_CONFIG_PATH
  if vim.fn.filereadable(path) == 0 then
    return {}
  end
  local hosts = {}
  for line in io.lines(path) do
    local h = line:match('^%s*[Hh]ost%s+(.+)$')
    if h then
      for part in h:gmatch('%S+') do
        if not part:find('[*?]') then
          table.insert(hosts, part)
        end
      end
    end
  end
  return hosts
end

function M._merge(db, config_hosts, now)
  local seen = {}
  local out = {}
  for host, entry in pairs(db) do
    table.insert(out, { host = host, score = M._score(entry, now) })
    seen[host] = true
  end
  for _, host in ipairs(config_hosts) do
    if not seen[host] then
      table.insert(out, { host = host, score = 0 })
    end
  end
  table.sort(out, function(a, b)
    return a.score > b.score
  end)
  return out
end

function M.list()
  local now = os.time()
  local db = M._read_db()
  local cfg = M._parse_ssh_config()
  local merged = M._merge(db, cfg, now)
  local out = { { host = '[+ Add host]', marker = 'add' } }
  for _, e in ipairs(merged) do
    table.insert(out, { host = e.host, score = e.score, marker = nil })
  end
  return out
end

function M.record(host)
  local db = M._read_db()
  db[host] = db[host] or { visits = 0, last_used = 0 }
  db[host].visits = db[host].visits + 1
  db[host].last_used = os.time()
  local dir = DB_PATH:match('(.*/)')
  if dir then
    vim.fn.mkdir(dir, 'p')
  end
  local f = io.open(DB_PATH, 'w')
  if f then
    f:write(vim.json.encode(db))
    f:close()
  end
end

function M.pick(callback)
  local entries = M.list()
  local pickers = require('telescope.pickers')
  local finders = require('telescope.finders')
  local actions = require('telescope.actions')
  local action_state = require('telescope.actions.state')
  local conf = require('telescope.config').values

  local function prompt_add(then_refresh)
    vim.ui.input({ prompt = 'Add host (user@host[:port]): ' }, function(input)
      if not input or input == '' then
        return
      end
      M.record(input)
      if then_refresh then
        vim.schedule(function()
          M.pick(callback)
        end)
      end
    end)
  end

  pickers
    .new({}, {
      prompt_title = 'ssh host',
      finder = finders.new_table({
        results = entries,
        entry_maker = function(e)
          local display
          if e.marker == 'add' then
            display = e.host
          else
            display = string.format('%-30s  %6.2f', e.host, e.score or 0)
          end
          return { value = e, display = display, ordinal = e.host }
        end,
      }),
      sorter = conf.generic_sorter({}),
      attach_mappings = function(bufnr, map)
        actions.select_default:replace(function()
          actions.close(bufnr)
          local sel = action_state.get_selected_entry()
          if not sel then
            return
          end
          local e = sel.value
          if e.marker == 'add' then
            prompt_add(true)
            return
          end
          if callback then
            callback(e.host)
          else
            local mosh = vim.fn.executable('mosh') == 1 and 'mosh' or 'ssh'
            vim.system({ 'tmux', 'new-window', mosh .. ' ' .. e.host }):wait()
          end
        end)
        map('i', '<C-a>', function()
          prompt_add(true)
        end)
        return true
      end,
    })
    :find()
end

function M.prune(max_age_days)
  max_age_days = max_age_days or 90
  local now = os.time()
  local cutoff = now - (max_age_days * 86400)
  local db = M._read_db()
  local removed = 0
  for host, entry in pairs(db) do
    if (entry.last_used or 0) < cutoff then
      db[host] = nil
      removed = removed + 1
    end
  end
  if removed > 0 then
    local dir = DB_PATH:match('(.*/)')
    if dir then
      vim.fn.mkdir(dir, 'p')
    end
    local f = io.open(DB_PATH, 'w')
    if f then
      f:write(vim.json.encode(db))
      f:close()
    end
  end
  return removed
end

function M.home_dir(host)
  local db = M._read_db()
  local entry = db[host]
  if not entry then
    return nil
  end
  return entry.home_dir
end

function M.record_home_dir(host, home)
  local db = M._read_db()
  db[host] = db[host] or { visits = 0, last_used = 0 }
  db[host].home_dir = home
  local dir = DB_PATH:match('(.*/)')
  if dir then
    vim.fn.mkdir(dir, 'p')
  end
  local f = io.open(DB_PATH, 'w')
  if f then
    f:write(vim.json.encode(db))
    f:close()
  end
end

-- Probe + cache $HOME for a host. Lazy; callers only trigger it when a
-- path they're about to use starts w/ '~/'. Runs via ssh_exec (so it
-- rides the ControlMaster socket once it's been established).
function M.ensure_home_dir(host)
  local cached = M.home_dir(host)
  if cached then
    return cached
  end
  local exec = require('remote.ssh_exec')
  local res = exec.run(host, 'printf %s "$HOME"')
  if res.code ~= 0 then
    return nil
  end
  local home = (res.stdout or ''):gsub('%s+$', '')
  if home == '' then
    return nil
  end
  M.record_home_dir(host, home)
  return home
end

-- Expand a single leading ~ against the cached $HOME for `host`. If the
-- path doesn't start with '~/' (or is just '~'), return unchanged.
function M.expand_path(host, path)
  if path == '~' then
    return M.home_dir(host) or path
  end
  if path:sub(1, 2) ~= '~/' then
    return path
  end
  local home = M.home_dir(host)
  if not home then
    return path
  end
  return home .. path:sub(2)
end

-- Keymaps + :HappyHostsPrune registered statically in lua/plugins/remote.lua.
function M.setup() end

return M
