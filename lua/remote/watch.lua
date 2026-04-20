-- lua/remote/watch.lua — watch-pattern registry for remote tails.
-- Persisted at ~/.local/share/nvim/happy-nvim/tail_patterns.json so
-- patterns survive nvim restarts. The tail reader calls M.scan(host,
-- path, line) per line and dispatches notifies on match.
local M = {}

local STATE_PATH = vim.fn.stdpath('data') .. '/happy-nvim/tail_patterns.json'

function M._set_state_path_for_test(p)
  STATE_PATH = p
end

local function next_id(state)
  local max_id = 0
  for _, p in ipairs(state.patterns) do
    local n = tonumber(p.id) or 0
    if n > max_id then
      max_id = n
    end
  end
  return tostring(max_id + 1)
end

local function read_state()
  local f = io.open(STATE_PATH, 'r')
  if not f then
    return { version = 1, patterns = {} }
  end
  local raw = f:read('*a')
  f:close()
  local ok, dec = pcall(vim.json.decode, raw)
  if not ok or type(dec) ~= 'table' then
    return { version = 1, patterns = {} }
  end
  dec.version = dec.version or 1
  dec.patterns = dec.patterns or {}
  return dec
end

local function write_state(state)
  local dir = STATE_PATH:match('(.*/)')
  if dir then
    vim.fn.mkdir(dir, 'p')
  end
  local f = io.open(STATE_PATH, 'w')
  if not f then
    return
  end
  f:write(vim.json.encode(state))
  f:close()
end

function M.list_all()
  return read_state().patterns
end

function M.list(host, path)
  local out = {}
  for _, p in ipairs(read_state().patterns) do
    if p.host == host and p.path == path then
      table.insert(out, p)
    end
  end
  return out
end

function M.add(host, path, regex, opts)
  opts = opts or {}
  local state = read_state()
  local entry = {
    id = next_id(state),
    host = host,
    path = path,
    regex = regex,
    level = opts.level or 'INFO',
    oneshot = opts.oneshot and true or false,
    created_at = os.time(),
    last_matched_at = 0,
    active = (opts.active == nil) and true or (opts.active and true or false),
  }
  table.insert(state.patterns, entry)
  write_state(state)
  return entry.id
end

function M.update(id, patch)
  local state = read_state()
  for _, p in ipairs(state.patterns) do
    if p.id == id then
      for k, v in pairs(patch) do
        p[k] = v
      end
      write_state(state)
      return true
    end
  end
  return false
end

function M.remove(id)
  local state = read_state()
  for i, p in ipairs(state.patterns) do
    if p.id == id then
      table.remove(state.patterns, i)
      write_state(state)
      return true
    end
  end
  return false
end

function M.set_active(host, path, ids)
  local want = {}
  for _, id in ipairs(ids) do
    want[id] = true
  end
  local state = read_state()
  for _, p in ipairs(state.patterns) do
    if p.host == host and p.path == path then
      p.active = want[p.id] == true
    end
  end
  write_state(state)
end

-- Match one line against active patterns for (host, path). Returns a
-- list of matched pattern entries. Side effect: bumps last_matched_at
-- + (for oneshot) flips active=false.
function M.scan(host, path, line)
  local state = read_state()
  local hits = {}
  local dirty = false
  for _, p in ipairs(state.patterns) do
    if p.host == host and p.path == path and p.active then
      local ok, matched = pcall(string.find, line, p.regex)
      if ok and matched then
        table.insert(hits, p)
        p.last_matched_at = os.time()
        if p.oneshot then
          p.active = false
        end
        dirty = true
      end
    end
  end
  if dirty then
    write_state(state)
  end
  return hits
end

return M
