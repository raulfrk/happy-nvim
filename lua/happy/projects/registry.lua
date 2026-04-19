local M = {}

local default_path = vim.fn.stdpath('data') .. '/happy/projects.json'
local state_path = default_path
local state = nil

local function slugify(s)
  return (s:gsub('^.*/', ''):gsub('[^%w%-]', '-'):gsub('%-+', '-'):gsub('^%-', ''):gsub('%-$', ''))
end

local function load()
  if state then return state end
  state = { version = 1, projects = {} }
  local fh = io.open(state_path, 'r')
  if not fh then return state end
  local content = fh:read('*a')
  fh:close()
  local ok, parsed = pcall(vim.json.decode, content)
  if ok and type(parsed) == 'table' and type(parsed.projects) == 'table' then
    state = parsed
  end
  return state
end

local function save()
  local dir = state_path:match('(.*/)')
  if dir then vim.fn.mkdir(dir, 'p') end
  local tmp = state_path .. '.new'
  local fh = assert(io.open(tmp, 'w'))
  fh:write(vim.json.encode(state))
  fh:close()
  assert(os.rename(tmp, state_path))
end

local function make_id(spec, existing)
  local base
  if spec.kind == 'local' then
    base = slugify(spec.path)
  else
    base = slugify(spec.host) .. '-' .. slugify(spec.path)
  end
  if base == '' then base = 'proj' end
  if not existing[base] then return base end
  local n = 2
  while existing[base .. '-' .. n] do n = n + 1 end
  return base .. '-' .. n
end

local function identity_match(a, b)
  if a.kind ~= b.kind then return false end
  if a.kind == 'local' then return a.path == b.path end
  return a.host == b.host and a.path == b.path
end

function M.add(spec)
  assert(spec.kind == 'local' or spec.kind == 'remote', 'invalid kind')
  if spec.kind == 'local' then assert(spec.path, 'path required') end
  if spec.kind == 'remote' then
    assert(spec.host, 'host required')
    assert(spec.path, 'path required')
  end
  load()
  for id, entry in pairs(state.projects) do
    if identity_match(entry, spec) then return id end
  end
  local id = make_id(spec, state.projects)
  state.projects[id] = {
    kind = spec.kind,
    path = spec.path,
    host = spec.host,
    last_opened = os.time(),
    frecency = 0.5,
    open_count = 1,
    sandbox_written = false,
  }
  save()
  return id
end

function M.forget(id)
  load()
  state.projects[id] = nil
  save()
end

function M.get(id)
  load()
  return state.projects[id]
end

function M.list()
  load()
  local out = {}
  for id, entry in pairs(state.projects) do
    local copy = vim.deepcopy(entry)
    copy.id = id
    table.insert(out, copy)
  end
  return out
end

function M.touch(id)
  load()
  local entry = state.projects[id]
  if not entry then return end
  entry.open_count = (entry.open_count or 0) + 1
  entry.last_opened = os.time()
  save()
end

function M.update(id, patch)
  load()
  local entry = state.projects[id]
  if not entry then return end
  for k, v in pairs(patch) do entry[k] = v end
  save()
end

-- test hooks
function M._set_path_for_test(p) state_path = p end
function M._reset_for_test() state = nil; state_path = default_path end

return M
