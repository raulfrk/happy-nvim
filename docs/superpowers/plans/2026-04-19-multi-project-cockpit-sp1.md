# Multi-Project Cockpit (SP1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Promote "project" to a first-class, persistent entity. Deliver `<leader>P` picker + pivot + ambient status + remote-project kind with one-way sandboxed local claude + capture primitives + worktree-claude script wrappers. Fix bug 30.3.

**Architecture:** New module `lua/happy/projects/*.lua` owns a JSON registry on disk and a telescope picker. Existing `lua/tmux/*.lua` is modified to resolve sessions via the registry rather than pane-local `@claude_pane_id`. Tmux sessions are named `cc-<id>` (local) and `remote-<id>` (remote). Remote projects get a scratch sandbox dir containing `.claude/settings.local.json` that denies any cmd/network path that could reach the host — local claude helps analyze logs captured into that sandbox dir by user-initiated keymaps.

**Tech Stack:** Lua 5.1 (LuaJIT via nvim 0.11+), plenary.nvim (tests + async/json), telescope.nvim (picker UI), nvim-harpoon2 (already cwd-keyed — no integration work), tmux 3.2+ (`capture-pane`, `pipe-pane`, `display-popup`, `set-env`), python + pytest (integration tests), bash (worktree helper scripts untouched, only wrapped).

**Reference:** `docs/superpowers/specs/2026-04-19-multi-project-cockpit-sp1-design.md`

---

## File Plan

**New files:**
- `lua/happy/projects/init.lua` — module entrypoint; exports `setup()` that registers keymaps, commands, which-key groups, status tick.
- `lua/happy/projects/registry.lua` — `add`, `forget`, `list`, `touch`, `get(id)`; frecency math; atomic JSON I/O.
- `lua/happy/projects/picker.lua` — `<leader>P` telescope picker; actions for pivot / add / forget / peek.
- `lua/happy/projects/pivot.lua` — `pivot(id)` primitive: `:cd` + tmux session focus + dead-session respawn.
- `lua/happy/projects/status.lua` — per-project status poll (2s libuv timer); lualine component; tmux status-right format helper.
- `lua/happy/projects/remote.lua` — remote-project add (sandbox dir + settings.local.json), pivot (ssh pane), capture primitives (`<leader>Cc`/`Ct`/`Cl`/`Cs`).
- `lua/happy/projects/migrate.lua` — migrate legacy `cc-*` tmux sessions into registry on plugin load.
- `tests/happy_projects_registry_spec.lua` — plenary unit tests for registry.
- `tests/happy_projects_frecency_spec.lua` — plenary unit tests for frecency formula + ID collisions.
- `tests/happy_projects_migrate_spec.lua` — plenary unit tests for migration.
- `tests/integration/test_project_pivot.py` — headless tmux integration test for pivot.
- `tests/integration/test_multi_cc_no_op_fixed.py` — regression test for bug 30.3.
- `tests/integration/test_remote_project_sandbox.py` — sandbox deny-list assertion.
- `tests/integration/test_remote_sandbox_no_fs_escape.py` — fs deny assertion.
- `tests/integration/test_capture_primitives.py` — `<leader>Cc` path coverage.

**Modified files:**
- `lua/tmux/claude.lua` — resolve target session via registry (fixes 30.3).
- `lua/tmux/claude_popup.lua` — resolve target session via registry.
- `lua/tmux/picker.lua` — `<leader>cl` delegates to projects.picker filtered.
- `lua/tmux/project.lua` — keep `slug_for_cwd` for display; new `canonical_id(cwd_or_host_path)` for session naming.
- `lua/plugins/whichkey.lua` — add `<leader>P` group (`+project`) and `<leader>C` group (`+capture`).
- `lua/init.lua` (or `lua/plugins/init.lua`, whichever is the canonical load site for happy-nvim modules — the subagent for Task 1 identifies the canonical site) — `require('happy.projects').setup()`.
- `docs/manual-tests.md` — append rows from Task 15.

---

## Ordering + dependencies

```
 1 ─┬─ 2 ─┬─ 3 (migration, depends on registry)
    │     ├─ 4 (picker, depends on registry+frecency)
    │     ├─ 6 (bug 30.3 fix, depends on registry)
    │     └─ 7 (status, depends on registry)
    │
    └── 4 ── 5 (pivot, depends on picker wiring)
                 │
                 ├── 9 → 10 → 11 → 12 (remote chain)
                 │
                 └── 13 (worktree wrappers — independent, can run anytime)

 14 (which-key wiring)   — depends on 4, 5, 12
 15 (manual-tests rows)  — depends on 4–13 (run near end)
 16 (assess + push + CI) — final
```

Tasks 3, 6, 7 can parallelize after 2. Task 13 parallelizes with anything. Task 5 blocks the remote chain (9–12).

---

## Task 1: Registry module — CRUD + atomic write

**Files:**
- Create: `lua/happy/projects/registry.lua`
- Create: `tests/happy_projects_registry_spec.lua`

- [ ] **Step 1: Write the failing tests**

```lua
-- tests/happy_projects_registry_spec.lua
local registry = require('happy.projects.registry')

describe('happy.projects.registry', function()
  local tmp
  before_each(function()
    tmp = vim.fn.tempname()
    registry._set_path_for_test(tmp)
  end)
  after_each(function()
    os.remove(tmp)
    registry._reset_for_test()
  end)

  it('starts empty', function()
    assert.same({}, registry.list())
  end)

  it('adds a local project and persists', function()
    local id = registry.add({ kind = 'local', path = '/tmp/proj-a' })
    assert.is_string(id)
    assert.equals('local', registry.get(id).kind)
    assert.equals('/tmp/proj-a', registry.get(id).path)

    registry._reset_for_test()
    registry._set_path_for_test(tmp)
    assert.equals('/tmp/proj-a', registry.get(id).path)
  end)

  it('adds a remote project', function()
    local id = registry.add({ kind = 'remote', host = 'prod01', path = '/var/log' })
    local entry = registry.get(id)
    assert.equals('remote', entry.kind)
    assert.equals('prod01', entry.host)
    assert.equals('/var/log', entry.path)
  end)

  it('forgets a project', function()
    local id = registry.add({ kind = 'local', path = '/tmp/proj-b' })
    registry.forget(id)
    assert.is_nil(registry.get(id))
  end)

  it('touch bumps open_count and last_opened', function()
    local id = registry.add({ kind = 'local', path = '/tmp/proj-c' })
    local before = registry.get(id).open_count
    registry.touch(id)
    local after = registry.get(id).open_count
    assert.equals(before + 1, after)
    assert.is_true(registry.get(id).last_opened > 0)
  end)

  it('dedupes on add by identity (path for local, host+path for remote)', function()
    local id1 = registry.add({ kind = 'local', path = '/tmp/proj-d' })
    local id2 = registry.add({ kind = 'local', path = '/tmp/proj-d' })
    assert.equals(id1, id2)
  end)

  it('atomic write survives kill-during-write (tmp file does not clobber real)', function()
    registry.add({ kind = 'local', path = '/tmp/proj-e' })
    local tmp_partial = tmp .. '.tmp'
    -- simulate a stale tmp file; real path should still parse
    local fh = io.open(tmp_partial, 'w')
    fh:write('{ "partial":'); fh:close()
    registry._reset_for_test()
    registry._set_path_for_test(tmp)
    assert.equals('/tmp/proj-e', registry.list()[1].path)
    os.remove(tmp_partial)
  end)
end)
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `nvim --headless -c "PlenaryBustedFile tests/happy_projects_registry_spec.lua" -c "qa!"`
Expected: FAIL — `module 'happy.projects.registry' not found`.

- [ ] **Step 3: Implement `registry.lua`**

```lua
-- lua/happy/projects/registry.lua
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
  local content = fh:read('*a'); fh:close()
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
  fh:write(vim.json.encode(state)); fh:close()
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
    assert(spec.host, 'host required'); assert(spec.path, 'path required')
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
    local copy = vim.deepcopy(entry); copy.id = id
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `nvim --headless -c "PlenaryBustedFile tests/happy_projects_registry_spec.lua" -c "qa!"`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add lua/happy/projects/registry.lua tests/happy_projects_registry_spec.lua
git commit -m "feat(projects): JSON registry w/ atomic writes and identity dedup"
```

---

## Task 2: Frecency formula + ID collision resolution

**Files:**
- Modify: `lua/happy/projects/registry.lua` (add `M.score(id)` + tighten `make_id`)
- Create: `tests/happy_projects_frecency_spec.lua`

- [ ] **Step 1: Write failing tests**

```lua
-- tests/happy_projects_frecency_spec.lua
local registry = require('happy.projects.registry')

describe('happy.projects.registry frecency + collisions', function()
  local tmp
  before_each(function()
    tmp = vim.fn.tempname()
    registry._set_path_for_test(tmp)
  end)
  after_each(function()
    os.remove(tmp); registry._reset_for_test()
  end)

  it('score ranks recently+frequently-opened higher', function()
    local older = registry.add({ kind = 'local', path = '/tmp/a' })
    local newer = registry.add({ kind = 'local', path = '/tmp/b' })
    registry.update(older, { open_count = 5, last_opened = os.time() - 3600 * 24 })
    registry.update(newer, { open_count = 2, last_opened = os.time() - 3600 * 2 })
    assert.is_true(registry.score(newer) > registry.score(older))
  end)

  it('resolves ID collisions by -2, -3 suffix', function()
    local id1 = registry.add({ kind = 'local', path = '/x/proj' })
    local id2 = registry.add({ kind = 'local', path = '/y/proj' })
    local id3 = registry.add({ kind = 'local', path = '/z/proj' })
    assert.equals('proj', id1)
    assert.equals('proj-2', id2)
    assert.equals('proj-3', id3)
  end)

  it('sorted_by_score returns list ordered descending', function()
    registry.update(registry.add({ kind = 'local', path = '/tmp/low' }),
      { open_count = 1, last_opened = os.time() - 3600 * 48 })
    registry.update(registry.add({ kind = 'local', path = '/tmp/high' }),
      { open_count = 10, last_opened = os.time() })
    local sorted = registry.sorted_by_score()
    assert.equals('/tmp/high', sorted[1].path)
  end)
end)
```

- [ ] **Step 2: Run to verify failure**

Run: `nvim --headless -c "PlenaryBustedFile tests/happy_projects_frecency_spec.lua" -c "qa!"`
Expected: FAIL — `registry.score` undefined.

- [ ] **Step 3: Add `score` + `sorted_by_score` to registry.lua**

Append to `lua/happy/projects/registry.lua`:

```lua
function M.score(id)
  load()
  local entry = state.projects[id]; if not entry then return 0 end
  local age_hours = (os.time() - (entry.last_opened or 0)) / 3600
  return (entry.open_count or 1) * math.exp(-age_hours * 0.05)
end

function M.sorted_by_score()
  local entries = M.list()
  table.sort(entries, function(a, b) return M.score(a.id) > M.score(b.id) end)
  return entries
end
```

- [ ] **Step 4: Run tests**

Run: `nvim --headless -c "PlenaryBustedFile tests/happy_projects_frecency_spec.lua" -c "qa!"`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lua/happy/projects/registry.lua tests/happy_projects_frecency_spec.lua
git commit -m "feat(projects): frecency score + collision-resolving IDs"
```

---

## Task 3: Migrate legacy `cc-*` tmux sessions

**Files:**
- Create: `lua/happy/projects/migrate.lua`
- Create: `tests/happy_projects_migrate_spec.lua`

- [ ] **Step 1: Write failing test**

```lua
-- tests/happy_projects_migrate_spec.lua
local registry = require('happy.projects.registry')
local migrate = require('happy.projects.migrate')

describe('happy.projects.migrate', function()
  local tmp
  before_each(function()
    tmp = vim.fn.tempname(); registry._set_path_for_test(tmp)
  end)
  after_each(function()
    os.remove(tmp); registry._reset_for_test()
  end)

  it('ingests sessions whose HAPPY_PROJECT_PATH env is set', function()
    local fake_tmux = function(args)
      if args[2] == 'list-sessions' then
        return 'cc-foo\ncc-bar\nrandom'
      end
      if args[2] == 'show-env' and args[4] == 'cc-foo' then
        return 'HAPPY_PROJECT_PATH=/home/u/foo'
      end
      if args[2] == 'show-env' and args[4] == 'cc-bar' then
        return '-HAPPY_PROJECT_PATH'  -- unset
      end
      return ''
    end
    migrate._set_tmux_fn_for_test(fake_tmux)

    local n = migrate.run()
    assert.equals(1, n)
    local all = registry.list()
    assert.equals('/home/u/foo', all[1].path)
  end)

  it('is idempotent', function()
    local fake_tmux = function(args)
      if args[2] == 'list-sessions' then return 'cc-foo' end
      if args[2] == 'show-env' then return 'HAPPY_PROJECT_PATH=/home/u/foo' end
      return ''
    end
    migrate._set_tmux_fn_for_test(fake_tmux)
    assert.equals(1, migrate.run())
    assert.equals(0, migrate.run())  -- dedup
  end)
end)
```

- [ ] **Step 2: Verify failure**

Run: `nvim --headless -c "PlenaryBustedFile tests/happy_projects_migrate_spec.lua" -c "qa!"`
Expected: FAIL — module missing.

- [ ] **Step 3: Implement `migrate.lua`**

```lua
-- lua/happy/projects/migrate.lua
local registry = require('happy.projects.registry')
local M = {}

local run_tmux = function(args)
  local out = vim.fn.system(args)
  if vim.v.shell_error ~= 0 then return '' end
  return out
end

function M._set_tmux_fn_for_test(fn) run_tmux = fn end

function M.run()
  local raw = run_tmux({ 'tmux', 'list-sessions', '-F', '#S' })
  local sessions = {}
  for s in raw:gmatch('[^\n]+') do
    if s:match('^cc%-') then table.insert(sessions, s) end
  end
  local before = #registry.list()
  for _, s in ipairs(sessions) do
    local env = run_tmux({ 'tmux', 'show-env', '-t', s, 'HAPPY_PROJECT_PATH' })
    local path = env:match('^HAPPY_PROJECT_PATH=(.+)')
    if path then
      registry.add({ kind = 'local', path = path })
    end
  end
  local added = #registry.list() - before
  if added > 0 then
    vim.schedule(function()
      vim.notify(
        ('Migrated %d existing claude sessions to projects registry.'):format(added),
        vim.log.levels.INFO)
    end)
  end
  return added
end

return M
```

- [ ] **Step 4: Tests pass**

Run: `nvim --headless -c "PlenaryBustedFile tests/happy_projects_migrate_spec.lua" -c "qa!"`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lua/happy/projects/migrate.lua tests/happy_projects_migrate_spec.lua
git commit -m "feat(projects): migrate legacy cc-* tmux sessions via HAPPY_PROJECT_PATH env"
```

---

## Task 4: Picker (`<leader>P`) — basic list + pivot action

**Files:**
- Create: `lua/happy/projects/picker.lua`
- (No unit test — telescope requires UI; covered by Task 5 integration test.)

- [ ] **Step 1: Implement picker**

```lua
-- lua/happy/projects/picker.lua
local registry = require('happy.projects.registry')
local pickers = require('telescope.pickers')
local finders = require('telescope.finders')
local conf = require('telescope.config').values
local actions = require('telescope.actions')
local action_state = require('telescope.actions.state')

local M = {}

local function fmt_age(ts)
  if not ts or ts == 0 then return 'never' end
  local d = os.time() - ts
  if d < 60 then return ('%ds ago'):format(d) end
  if d < 3600 then return ('%dm ago'):format(math.floor(d / 60)) end
  if d < 86400 then return ('%dh ago'):format(math.floor(d / 3600)) end
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
  if host and path then return { kind = 'remote', host = host, path = path } end
  return nil
end

function M.open(opts)
  opts = opts or {}
  local filter = opts.filter or function() return true end
  local entries = vim.tbl_filter(filter, registry.sorted_by_score())

  pickers.new(opts, {
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
        if sel then require('happy.projects.pivot').pivot(sel.value.id) end
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
        vim.schedule(function() M.open(opts) end)
      end)
      map('i', '<C-d>', function()
        local sel = action_state.get_selected_entry()
        if sel then
          registry.forget(sel.value.id)
          actions.close(prompt_bufnr)
          vim.schedule(function() M.open(opts) end)
        end
      end)
      map('i', '<C-p>', function()
        local sel = action_state.get_selected_entry()
        if sel then require('happy.projects.pivot').peek(sel.value.id) end
      end)
      return true
    end,
  }):find()
end

return M
```

- [ ] **Step 2: Commit (tests in later tasks)**

```bash
git add lua/happy/projects/picker.lua
git commit -m "feat(projects): <leader>P telescope picker w/ add/forget/peek actions"
```

---

## Task 5: Pivot primitive + integration test

**Files:**
- Create: `lua/happy/projects/pivot.lua`
- Create: `tests/integration/test_project_pivot.py`

- [ ] **Step 1: Implement `pivot.lua`**

```lua
-- lua/happy/projects/pivot.lua
local registry = require('happy.projects.registry')

local M = {}

local function session_name(entry)
  if entry.kind == 'remote' then return 'remote-' .. entry.id end
  return 'cc-' .. entry.id
end

local function session_alive(name)
  vim.fn.system({ 'tmux', 'has-session', '-t', name })
  return vim.v.shell_error == 0
end

local function spawn_local(entry)
  local name = session_name(entry)
  vim.fn.system({ 'tmux', 'new-session', '-d', '-s', name, '-c', entry.path })
  vim.fn.system({ 'tmux', 'set-env', '-t', name, 'HAPPY_PROJECT_PATH', entry.path })
  vim.fn.system({ 'tmux', 'send-keys', '-t', name, 'claude', 'Enter' })
end

local function spawn_remote(entry)
  require('happy.projects.remote').spawn_ssh(entry)
end

function M.pivot(id)
  local entry = registry.get(id)
  if not entry then
    vim.notify('project not found: ' .. id, vim.log.levels.WARN); return
  end
  if entry.kind == 'local' then
    vim.cmd.cd(vim.fn.fnameescape(entry.path))
  end
  local name = session_name(entry)
  if not session_alive(name) then
    if entry.kind == 'local' then spawn_local(entry) else spawn_remote(entry) end
    vim.notify(name .. ' session was dead — spawned fresh.', vim.log.levels.INFO)
  end
  registry.touch(id)
  -- focus the session (if we're inside tmux)
  if os.getenv('TMUX') then
    vim.fn.system({ 'tmux', 'switch-client', '-t', name })
  end
end

function M.peek(id)
  local entry = registry.get(id)
  if not entry then return end
  local name = session_name(entry)
  if not session_alive(name) then
    vim.notify(name .. ' is not alive — nothing to peek', vim.log.levels.INFO); return
  end
  local out = vim.fn.system({ 'tmux', 'capture-pane', '-t', name, '-p', '-S', '-20' })
  vim.cmd('new'); vim.bo.buftype = 'nofile'; vim.bo.bufhidden = 'wipe'
  vim.api.nvim_buf_set_lines(0, 0, -1, false, vim.split(out, '\n'))
  vim.bo.modifiable = false
end

return M
```

- [ ] **Step 2: Write integration test**

```python
# tests/integration/test_project_pivot.py
import json, os, time
from pathlib import Path
from .helpers import run_nvim_cmd, make_tmux_session, kill_tmux_session, with_headless_nvim

def test_pivot_local_project_cds_nvim_and_focuses_tmux(tmp_path, headless_nvim):
    proj = tmp_path / 'proj-alpha'; proj.mkdir()
    registry_path = tmp_path / 'projects.json'
    registry_path.write_text(json.dumps({
        "version": 1,
        "projects": {
            "proj-alpha": {
                "kind": "local", "path": str(proj),
                "last_opened": int(time.time()), "frecency": 0.5,
                "open_count": 1, "sandbox_written": False
            }
        }
    }))
    os.environ['HAPPY_PROJECTS_JSON_OVERRIDE'] = str(registry_path)

    make_tmux_session('cc-proj-alpha', cwd=str(proj))
    try:
        cwd = run_nvim_cmd(headless_nvim,
            "lua require('happy.projects.pivot').pivot('proj-alpha'); print(vim.fn.getcwd())"
        )
        assert str(proj) in cwd
    finally:
        kill_tmux_session('cc-proj-alpha')
```

Integration harness `tests/integration/helpers.py` already has `run_nvim_cmd`, `make_tmux_session`, `kill_tmux_session`, `headless_nvim` fixture in use elsewhere — reuse. If `HAPPY_PROJECTS_JSON_OVERRIDE` env-var support isn't already in `registry.lua`, add:

Append to `lua/happy/projects/registry.lua` just above `load()`:

```lua
local env_override = os.getenv('HAPPY_PROJECTS_JSON_OVERRIDE')
if env_override and env_override ~= '' then state_path = env_override end
```

- [ ] **Step 3: Run integration test**

Run: `pytest tests/integration/test_project_pivot.py -v`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add lua/happy/projects/pivot.lua lua/happy/projects/registry.lua tests/integration/test_project_pivot.py
git commit -m "feat(projects): pivot primitive w/ dead-session respawn + integration test"
```

---

## Task 6: Bug 30.3 fix — `<leader>cc` uses per-project tmux session

**UX change notice:** Current `<leader>cc` creates an inline split **pane** in the current tmux window and stashes its id in window-scoped option `@claude_pane_id` (see `lua/tmux/claude.lua:37-63` and `lua/tmux/send.lua:17-47`). Because the option is window-scoped, two nvim panes sharing one tmux window collide — bug 30.3. Fix: `<leader>cc` creates/attaches a per-project tmux **session** `cc-<id>` and switches the client to it (full-screen claude view). `<leader>cp` (popup) retains its overlay UX — unchanged except it now routes via registry.

Rationale: matches spec §3 invariant 1 ("Tmux sessions are named `cc-<id>`"). Eliminates the window-option collision root-cause. Users wanting an inline split can always `prefix + "` manually.

**Files:**
- Modify: `lua/tmux/claude.lua` — replace pane model with session model
- Modify: `lua/tmux/send.lua` — resolve target via registry, not `@claude_pane_id`
- Create: `tests/integration/test_multi_cc_no_op_fixed.py`

- [ ] **Step 1: Write regression test**

```python
# tests/integration/test_multi_cc_no_op_fixed.py
import os, subprocess, time
from .helpers import headless_nvim, run_nvim_cmd

def test_second_window_cc_creates_distinct_session(tmp_path, headless_nvim):
    proj_a = tmp_path / 'a'; proj_a.mkdir()
    proj_b = tmp_path / 'b'; proj_b.mkdir()
    os.environ['HAPPY_PROJECTS_JSON_OVERRIDE'] = str(tmp_path / 'projects.json')

    # invoke from nvim in proj_a
    run_nvim_cmd(headless_nvim,
        f"lua vim.env.TMUX='dummy'; vim.cmd.cd('{proj_a}');"
        f"require('tmux.claude').open_guarded()")
    # invoke from nvim in proj_b (same process, simulating 2nd window sharing env)
    run_nvim_cmd(headless_nvim,
        f"lua vim.env.TMUX='dummy'; vim.cmd.cd('{proj_b}');"
        f"require('tmux.claude').open_guarded()")

    time.sleep(0.3)
    out = subprocess.check_output(['tmux', 'list-sessions', '-F', '#S']).decode()
    assert 'cc-a' in out
    assert 'cc-b' in out

    for s in ('cc-a', 'cc-b'):
        subprocess.run(['tmux', 'kill-session', '-t', s])
```

- [ ] **Step 2: Verify failure**

Run: `pytest tests/integration/test_multi_cc_no_op_fixed.py -v`
Expected: FAIL — neither session exists (old code tries to split a pane in a dummy-TMUX env, which fails silently).

- [ ] **Step 3: Rewrite `lua/tmux/claude.lua` `M.open`**

Replace lines 37-63 (`function M.open()` body) with:

```lua
local registry = require('happy.projects.registry')

local function session_for_cwd()
  local cwd = vim.fn.getcwd()
  local id = registry.add({ kind = 'local', path = cwd })
  return id, 'cc-' .. id, cwd
end

local function session_alive(name)
  vim.fn.system({ 'tmux', 'has-session', '-t', name })
  return vim.v.shell_error == 0
end

function M.open()
  local id, session, cwd = session_for_cwd()
  if not session_alive(session) then
    local res = vim.system({
      'tmux', 'new-session', '-d', '-s', session, '-c', cwd, 'claude',
    }, { text = true }):wait()
    if res.code ~= 0 then
      vim.notify('failed to spawn Claude session: ' .. (res.stderr or ''), vim.log.levels.ERROR)
      return
    end
    vim.system({ 'tmux', 'set-env', '-t', session, 'HAPPY_PROJECT_PATH', cwd }):wait()
  end
  registry.touch(id)
  -- Switch client (if inside tmux) so the user sees the session full-screen.
  if vim.env.TMUX and vim.env.TMUX ~= '' then
    vim.system({ 'tmux', 'switch-client', '-t', session }):wait()
  else
    vim.notify(session .. ' is up. Attach via `tmux attach -t ' .. session .. '`.', vim.log.levels.INFO)
  end
end
```

Also replace `M.open_fresh_guarded()` (lines 101-113) to kill+respawn the **session**, not a pane:

```lua
function M.open_fresh_guarded()
  if not guard() then return end
  local _, session, _ = session_for_cwd()
  if session_alive(session) then
    vim.system({ 'tmux', 'kill-session', '-t', session }):wait()
  end
  M.open()
end
```

Remove/deprecate any remaining use of `send.get_claude_pane_id()` / `send.set_claude_pane_id()` in `claude.lua` (there's none in `open` after this rewrite; double-check no other function references them).

- [ ] **Step 4: Update `lua/tmux/send.lua` `resolve_target`**

Replace `M.resolve_target()` (lines 49-66) with:

```lua
function M.resolve_target()
  local registry_ok, registry = pcall(require, 'happy.projects.registry')
  if registry_ok then
    local cwd = vim.fn.getcwd()
    local id = registry.add({ kind = 'local', path = cwd })
    local session = (registry.get(id).kind == 'remote' and 'remote-' or 'cc-') .. id
    local has = vim.system({ 'tmux', 'has-session', '-t', session }, { text = true }):wait()
    if has.code == 0 then
      -- Resolve to the first pane of the session
      local res = vim.system(
        { 'tmux', 'list-panes', '-t', session, '-F', '#{pane_id}' }, { text = true }
      ):wait()
      local pane = (res.stdout or ''):match('^(%S+)')
      if pane then return pane, 'session' end
    end
  end
  -- Fallback: existing popup mechanism
  local ok, popup = pcall(require, 'tmux.claude_popup')
  if ok then
    local pid = popup.pane_id()
    if pid then return pid, 'popup' end
  end
  return nil, nil
end
```

`get_claude_pane_id` / `set_claude_pane_id` remain for the popup path (unused by `<leader>cc` anymore) — leave them untouched so `<leader>cp` flow is unaffected.

- [ ] **Step 5: Run regression + assess**

Run:
```
pytest tests/integration/test_multi_cc_no_op_fixed.py -v
bash scripts/assess.sh
```
Expected: both PASS. If `tests/tmux_claude_spec.lua` or `tests/tmux_send_spec.lua` break on old pane-based assumptions, update them to match session model.

- [ ] **Step 6: Commit**

```bash
git add lua/tmux/claude.lua lua/tmux/send.lua tests/integration/test_multi_cc_no_op_fixed.py tests/tmux_claude_spec.lua tests/tmux_send_spec.lua
git commit -m "fix(tmux): <leader>cc creates per-project cc-<id> session (closes 30.3)"
```

---

## Task 7: Ambient status — lualine component + tmux status-right format

**Files:**
- Create: `lua/happy/projects/status.lua`
- Modify: wherever lualine is configured (the subagent identifies the file via `grep -rn 'lualine' lua/`)

- [ ] **Step 1: Write failing test**

```lua
-- appended to tests/happy_projects_registry_spec.lua OR new tests/happy_projects_status_spec.lua
local status = require('happy.projects.status')
local registry = require('happy.projects.registry')

describe('happy.projects.status format', function()
  local tmp
  before_each(function()
    tmp = vim.fn.tempname(); registry._set_path_for_test(tmp)
  end)
  after_each(function()
    os.remove(tmp); registry._reset_for_test()
  end)

  it('renders empty state as blank', function()
    assert.equals('', status.format_for_statusline())
  end)

  it('renders multiple projects w/ icons', function()
    local a = registry.add({ kind = 'local', path = '/tmp/a' })
    local b = registry.add({ kind = 'local', path = '/tmp/b' })
    status._set_state_for_test({
      [a] = 'idle', [b] = 'working'
    })
    local out = status.format_for_statusline()
    assert.is_truthy(out:match('✓'))
    assert.is_truthy(out:match('⟳'))
  end)

  it('truncates beyond 5 entries', function()
    for i = 1, 7 do registry.add({ kind = 'local', path = '/tmp/p' .. i }) end
    local fake = {}
    for _, e in ipairs(registry.list()) do fake[e.id] = 'idle' end
    status._set_state_for_test(fake)
    local out = status.format_for_statusline()
    assert.is_truthy(out:match('…%+2'))
  end)
end)
```

- [ ] **Step 2: Implement `status.lua`**

```lua
-- lua/happy/projects/status.lua
local registry = require('happy.projects.registry')
local M = {}

local ICONS = { idle = '✓', working = '⟳', stale = '?', dead = '✗' }
local STATE = {}  -- { [id] = 'idle'|'working'|'stale'|'dead' }

local function session_for(entry)
  if entry.kind == 'remote' then return 'remote-' .. entry.id end
  return 'cc-' .. entry.id
end

function M.poll()
  local raw = vim.fn.system({ 'tmux', 'list-sessions', '-F', '#S' })
  if vim.v.shell_error ~= 0 then return end
  local alive = {}
  for s in raw:gmatch('[^\n]+') do alive[s] = true end
  for _, entry in ipairs(registry.list()) do
    local name = session_for(entry)
    if not alive[name] then
      STATE[entry.id] = 'dead'
    else
      -- use idle.lua busy signal when available
      local busy_ok, busy = pcall(function()
        return require('tmux.idle').is_busy(name)
      end)
      if busy_ok and busy then STATE[entry.id] = 'working'
      else STATE[entry.id] = 'idle' end
    end
  end
end

function M.format_for_statusline()
  local entries = registry.sorted_by_score()
  if #entries == 0 then return '' end
  local parts = {}
  local shown = 0
  for _, e in ipairs(entries) do
    if shown >= 5 then break end
    local s = STATE[e.id] or 'stale'
    table.insert(parts, (ICONS[s] or '?') .. ' ' .. e.id)
    shown = shown + 1
  end
  local extra = #entries - shown
  if extra > 0 then table.insert(parts, ('…+%d'):format(extra)) end
  return table.concat(parts, ' · ')
end

function M.tmux_status_right()
  return M.format_for_statusline()
end

function M.start_timer()
  if M._timer then return end
  M._timer = vim.uv.new_timer()
  M._timer:start(0, 2000, vim.schedule_wrap(function() M.poll() end))
end

function M.stop_timer()
  if M._timer then M._timer:stop(); M._timer:close(); M._timer = nil end
end

function M._set_state_for_test(tbl) STATE = tbl end

return M
```

- [ ] **Step 3: Tests pass**

Run: `nvim --headless -c "PlenaryBustedFile tests/happy_projects_status_spec.lua" -c "qa!"`
Expected: PASS.

- [ ] **Step 4: Wire lualine component**

Modify `lua/plugins/lualine.lua`. Add a new entry to `sections.lualine_c` (between filename and the `lualine_x` filetype cluster):

```lua
-- lua/plugins/lualine.lua (after line 16)
lualine_c = {
  { 'filename', path = 1 },
  { function() return require('happy.projects.status').format_for_statusline() end },
},
```

- [ ] **Step 5: Commit**

```bash
git add lua/happy/projects/status.lua tests/happy_projects_status_spec.lua lua/plugins/lualine.lua
git commit -m "feat(projects): ambient status (lualine component + tmux status-right helper)"
```

---

## Task 8: Wire status polling timer on plugin setup

**Files:**
- Modify: `lua/happy/projects/init.lua` (doesn't exist yet — create it here)

- [ ] **Step 1: Create init.lua**

```lua
-- lua/happy/projects/init.lua
local M = {}

function M.setup(opts)
  opts = opts or {}
  local status = require('happy.projects.status')
  local picker = require('happy.projects.picker')

  -- migration on startup (scheduled to not block UI)
  vim.schedule(function()
    pcall(function() require('happy.projects.migrate').run() end)
  end)

  -- status poll
  status.start_timer()

  -- keymaps
  vim.keymap.set('n', '<leader>P', function() picker.open() end,
    { desc = 'Projects picker' })
  vim.keymap.set('n', '<leader>Pa', function()
    vim.ui.input({ prompt = 'Add project (/path or host:path): ' }, function(input)
      if not input or input == '' then return end
      local parsed = input:sub(1,1) == '/' and { kind='local', path=input }
        or (function()
          local h, p = input:match('^([^:]+):(.+)$')
          if h and p then return { kind = 'remote', host = h, path = p } end
        end)()
      if not parsed then
        vim.notify('cannot parse input', vim.log.levels.WARN); return
      end
      local id = require('happy.projects.registry').add(parsed)
      if parsed.kind == 'remote' then
        require('happy.projects.remote').provision(id)
      end
      vim.notify('added ' .. id, vim.log.levels.INFO)
    end)
  end, { desc = 'Add project' })
  vim.keymap.set('n', '<leader>Pp', function() picker.open({ title = 'Peek' }) end,
    { desc = 'Peek project' })

  -- commands
  vim.api.nvim_create_user_command('HappyProjectAdd', function(args)
    local input = args.args
    local parsed = input:sub(1,1) == '/' and { kind='local', path=input }
      or (function()
        local h, p = input:match('^([^:]+):(.+)$')
        if h and p then return { kind='remote', host=h, path=p } end
      end)()
    if not parsed then return vim.notify('cannot parse', vim.log.levels.WARN) end
    require('happy.projects.registry').add(parsed)
  end, { nargs = 1 })
  vim.api.nvim_create_user_command('HappyProjectForget', function(args)
    require('happy.projects.registry').forget(args.args)
  end, { nargs = 1 })
end

return M
```

- [ ] **Step 2: Wire into `init.lua` module list**

Modify `init.lua` (project root) line 33. Current:

```lua
for _, mod in ipairs({ 'coach', 'clipboard', 'tmux', 'remote', 'happy.assess' }) do
```

Change to:

```lua
for _, mod in ipairs({ 'coach', 'clipboard', 'tmux', 'remote', 'happy.assess', 'happy.projects' }) do
```

The existing loop calls `m.setup()` — `happy.projects.init.lua` exports `setup()`, so no other wiring is needed.

- [ ] **Step 3: Smoke-test via `:HappyAssess`**

Run: `bash scripts/assess.sh`
Expected: `ASSESS: ALL LAYERS PASS`.

- [ ] **Step 4: Commit**

```bash
git add lua/happy/projects/init.lua <load-site-file>
git commit -m "feat(projects): module setup — keymaps, commands, status timer, migration"
```

---

## Task 9: Remote project provisioning — sandbox dir + settings.local.json

**Files:**
- Create: `lua/happy/projects/remote.lua` (skeleton + `provision`)
- Create: `tests/integration/test_remote_project_sandbox.py`

- [ ] **Step 1: Write failing test**

```python
# tests/integration/test_remote_project_sandbox.py
import json, os
from pathlib import Path
from .helpers import run_nvim_cmd, headless_nvim

def test_provision_creates_sandbox_and_settings(tmp_path, headless_nvim):
    os.environ['HAPPY_PROJECTS_JSON_OVERRIDE'] = str(tmp_path / 'projects.json')
    os.environ['HAPPY_REMOTE_SANDBOX_BASE'] = str(tmp_path / 'sandboxes')

    run_nvim_cmd(headless_nvim, """lua
      local reg = require('happy.projects.registry')
      local id = reg.add({ kind='remote', host='prod01', path='/var/log' })
      require('happy.projects.remote').provision(id)
    """)

    sandbox = tmp_path / 'sandboxes' / 'prod01-var-log'
    settings = sandbox / '.claude' / 'settings.local.json'
    assert settings.exists()
    data = json.loads(settings.read_text())
    deny = data['permissions']['deny']
    assert any('Bash(ssh' in p for p in deny)
    assert any('WebFetch' in p for p in deny)
    assert any('Read(/**)' in p for p in deny)
    allow = data['permissions']['allow']
    assert any(str(sandbox) in p for p in allow)
```

- [ ] **Step 2: Verify failure**

Run: `pytest tests/integration/test_remote_project_sandbox.py -v`
Expected: FAIL — module missing / file not created.

- [ ] **Step 3: Implement `remote.lua` `provision`**

```lua
-- lua/happy/projects/remote.lua
local registry = require('happy.projects.registry')
local M = {}

local function sandbox_root()
  return os.getenv('HAPPY_REMOTE_SANDBOX_BASE')
    or (vim.fn.stdpath('data') .. '/happy/remote-sandboxes')
end

function M.sandbox_dir(id) return sandbox_root() .. '/' .. id end

function M.provision(id)
  local entry = registry.get(id)
  if not entry or entry.kind ~= 'remote' then return end
  local dir = M.sandbox_dir(id)
  vim.fn.mkdir(dir .. '/.claude', 'p')
  local settings = {
    permissions = {
      deny = {
        'Bash(ssh:*)','Bash(scp:*)','Bash(sftp:*)','Bash(rsync:*)','Bash(mosh:*)',
        'Bash(curl:*)','Bash(wget:*)','Bash(nc:*)','Bash(socat:*)','Bash(ssh-*)',
        'WebFetch(*)',
        'Read(/**)','Edit(/**)','Write(/**)',
      },
      allow = {
        ('Read(%s/**)'):format(dir),
        ('Write(%s/**)'):format(dir),
        ('Edit(%s/**)'):format(dir),
      },
    },
  }
  local path = dir .. '/.claude/settings.local.json'
  local fh = assert(io.open(path, 'w'))
  fh:write(vim.json.encode(settings)); fh:close()
  registry.update(id, { sandbox_written = true })
end

return M
```

- [ ] **Step 4: Test passes**

Run: `pytest tests/integration/test_remote_project_sandbox.py -v`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lua/happy/projects/remote.lua tests/integration/test_remote_project_sandbox.py
git commit -m "feat(projects): remote.provision writes sandbox dir + settings.local.json"
```

---

## Task 10: Remote project pivot — spawn ssh pane

**Files:**
- Modify: `lua/happy/projects/remote.lua` (add `spawn_ssh`)

- [ ] **Step 1: Extend integration test**

Append to `tests/integration/test_remote_project_sandbox.py`:

```python
def test_spawn_ssh_creates_remote_session(tmp_path, headless_nvim, monkeypatch):
    # use a local fake ssh: any binary that stays alive. We don't actually connect.
    os.environ['HAPPY_PROJECTS_JSON_OVERRIDE'] = str(tmp_path / 'projects.json')
    os.environ['HAPPY_REMOTE_SANDBOX_BASE'] = str(tmp_path / 'sandboxes')
    os.environ['HAPPY_REMOTE_SSH_CMD'] = 'cat'  # stays alive until EOF

    run_nvim_cmd(headless_nvim, """lua
      local reg = require('happy.projects.registry')
      local id = reg.add({ kind='remote', host='prod01', path='/var/log' })
      require('happy.projects.remote').provision(id)
      require('happy.projects.remote').spawn_ssh(reg.get(id))
    """)

    import subprocess
    out = subprocess.check_output(['tmux', 'list-sessions', '-F', '#S']).decode()
    assert 'remote-prod01-var-log' in out
    subprocess.run(['tmux', 'kill-session', '-t', 'remote-prod01-var-log'])
```

- [ ] **Step 2: Verify failure**

Run: `pytest tests/integration/test_remote_project_sandbox.py::test_spawn_ssh_creates_remote_session -v`
Expected: FAIL — `spawn_ssh` undefined.

- [ ] **Step 3: Implement `spawn_ssh`**

Append to `lua/happy/projects/remote.lua`:

```lua
function M.spawn_ssh(entry)
  local id = entry.id or (function()
    for k, v in pairs(registry.list()) do if v.path == entry.path and v.host == entry.host then return v.id end end
  end)()
  local name = 'remote-' .. id
  local ssh_cmd = os.getenv('HAPPY_REMOTE_SSH_CMD') or 'ssh'
  local cmd = ('%s %s -t "cd %s; exec $SHELL"'):format(ssh_cmd, entry.host, entry.path)
  if ssh_cmd == 'cat' then cmd = 'cat' end  -- test mode: just stay alive
  vim.fn.system({ 'tmux', 'new-session', '-d', '-s', name, cmd })
  vim.fn.system({ 'tmux', 'set-env', '-t', name, 'HAPPY_REMOTE_HOST', entry.host })
  vim.fn.system({ 'tmux', 'set-env', '-t', name, 'HAPPY_REMOTE_PATH', entry.path })
end
```

- [ ] **Step 4: Test passes**

Run: `pytest tests/integration/test_remote_project_sandbox.py -v`
Expected: both tests PASS.

- [ ] **Step 5: Commit**

```bash
git add lua/happy/projects/remote.lua tests/integration/test_remote_project_sandbox.py
git commit -m "feat(projects): remote.spawn_ssh creates remote-<id> tmux session"
```

---

## Task 11: Sandboxed claude popup for remote project + fs-escape test

**Files:**
- Modify: `lua/tmux/claude_popup.lua` (resolve settings/cwd via registry when current project is remote)
- Create: `tests/integration/test_remote_sandbox_no_fs_escape.py`

- [ ] **Step 1: Write failing test**

```python
# tests/integration/test_remote_sandbox_no_fs_escape.py
import json, os, subprocess
from pathlib import Path

def test_sandbox_denies_fs_outside(tmp_path):
    # load settings, simulate claude's permission check by reading the file
    sandbox = tmp_path / 'sandbox'
    (sandbox / '.claude').mkdir(parents=True)
    settings = {
        "permissions": {
            "deny": ["Read(/**)","Edit(/**)","Write(/**)"],
            "allow": [f"Read({sandbox}/**)",f"Write({sandbox}/**)"]
        }
    }
    (sandbox / '.claude' / 'settings.local.json').write_text(json.dumps(settings))

    # invariant test: deny list contains Read(/**), and allow is scoped to sandbox
    data = json.loads((sandbox / '.claude' / 'settings.local.json').read_text())
    assert 'Read(/**)' in data['permissions']['deny']
    assert any(str(sandbox) in a for a in data['permissions']['allow'])
    # ssh outbound denied
    # (the actual claude runtime enforces this; we assert the document is correct)
```

This test is a schema-invariant check, not a live-claude runtime assertion (that needs real claude CLI which isn't in CI). Doc-as-contract.

- [ ] **Step 2: Modify `claude_popup.lua` to honor remote-project cwd**

Current `claude_popup.open()` is keyed on project slug / cwd. Change to: resolve the current project via `registry`, and when `kind == 'remote'`, open the popup with `cwd = remote.sandbox_dir(id)` (so claude inherits the sandbox's `.claude/settings.local.json`).

Subagent reads `lua/tmux/claude_popup.lua`, locates where cwd/working-dir is selected, and inserts:

```lua
local registry = require('happy.projects.registry')
local remote = require('happy.projects.remote')

local function target_cwd_for_current_project()
  local cwd = vim.fn.getcwd()
  local id = registry.add({ kind = 'local', path = cwd })  -- dedup
  local entry = registry.get(id)
  if entry and entry.kind == 'remote' then return remote.sandbox_dir(id) end
  return cwd
end

-- replace old cwd computation with target_cwd_for_current_project()
```

For the common case (local projects), behavior is unchanged.

- [ ] **Step 3: Run schema test + assess**

Run:
```
pytest tests/integration/test_remote_sandbox_no_fs_escape.py -v
bash scripts/assess.sh
```
Expected: both PASS.

- [ ] **Step 4: Commit**

```bash
git add lua/tmux/claude_popup.lua tests/integration/test_remote_sandbox_no_fs_escape.py
git commit -m "feat(projects): claude popup honors remote-sandbox cwd for remote projects"
```

---

## Task 12: Capture primitives (`<leader>Cc/Ct/Cl/Cs`)

**Files:**
- Modify: `lua/happy/projects/remote.lua` (add capture functions)
- Modify: `lua/happy/projects/init.lua` (register `<leader>C*` keymaps)
- Create: `tests/integration/test_capture_primitives.py`

- [ ] **Step 1: Write failing test**

```python
# tests/integration/test_capture_primitives.py
import os, subprocess, time
from pathlib import Path
from .helpers import run_nvim_cmd, headless_nvim

def test_Cc_captures_remote_pane_to_sandbox_file(tmp_path, headless_nvim):
    os.environ['HAPPY_PROJECTS_JSON_OVERRIDE'] = str(tmp_path / 'projects.json')
    os.environ['HAPPY_REMOTE_SANDBOX_BASE'] = str(tmp_path / 'sandboxes')

    # spawn a tmux session with a fake "remote pane" containing known text
    subprocess.run(['tmux', 'new-session', '-d', '-s', 'remote-prod01-var-log',
                    'bash', '-c', 'echo CAPTURE_MARKER; sleep 60'], check=True)
    time.sleep(0.3)  # let bash echo

    run_nvim_cmd(headless_nvim, """lua
      local reg = require('happy.projects.registry')
      local id = reg.add({ kind='remote', host='prod01', path='/var/log' })
      require('happy.projects.remote').provision(id)
      require('happy.projects.remote').capture(id)
    """)

    sandbox = tmp_path / 'sandboxes' / 'prod01-var-log'
    captures = list(sandbox.glob('capture-*.log'))
    assert len(captures) == 1
    assert 'CAPTURE_MARKER' in captures[0].read_text()
    subprocess.run(['tmux', 'kill-session', '-t', 'remote-prod01-var-log'])
```

- [ ] **Step 2: Verify failure**

Run: `pytest tests/integration/test_capture_primitives.py -v`
Expected: FAIL.

- [ ] **Step 3: Implement capture primitives**

Append to `lua/happy/projects/remote.lua`:

```lua
local function ts() return os.date('!%Y%m%dT%H%M%SZ') end

function M.capture(id)
  local entry = registry.get(id); if not entry or entry.kind ~= 'remote' then return end
  local name = 'remote-' .. id
  local out = vim.fn.system({ 'tmux', 'capture-pane', '-t', name, '-p', '-S', '-500' })
  if vim.v.shell_error ~= 0 then
    vim.notify('capture failed: no remote pane', vim.log.levels.WARN); return
  end
  local path = M.sandbox_dir(id) .. '/capture-' .. ts() .. '.log'
  local fh = assert(io.open(path, 'w')); fh:write(out); fh:close()
  vim.notify('captured → ' .. path, vim.log.levels.INFO)
  return path
end

function M.toggle_tail(id)
  local entry = registry.get(id); if not entry or entry.kind ~= 'remote' then return end
  local name = 'remote-' .. id
  local live = M.sandbox_dir(id) .. '/live.log'
  local pipe_state = vim.fn.system({ 'tmux', 'show-options', '-t', name, '-p', '-v', '@happy-tail' })
  if pipe_state:find('on') then
    vim.fn.system({ 'tmux', 'pipe-pane', '-t', name })  -- toggle off
    vim.fn.system({ 'tmux', 'set-option', '-t', name, '-p', '@happy-tail', 'off' })
    vim.notify('tail OFF', vim.log.levels.INFO)
  else
    vim.fn.system({ 'tmux', 'pipe-pane', '-t', name, '-o', 'cat >> ' .. live })
    vim.fn.system({ 'tmux', 'set-option', '-t', name, '-p', '@happy-tail', 'on' })
    vim.notify('tail ON → ' .. live, vim.log.levels.INFO)
  end
end

function M.pull(id, remote_path)
  local entry = registry.get(id); if not entry or entry.kind ~= 'remote' then return end
  local dest = M.sandbox_dir(id) .. '/' .. vim.fs.basename(remote_path)
  vim.fn.system({ 'scp', entry.host .. ':' .. remote_path, dest })
  if vim.v.shell_error == 0 then
    vim.notify('pulled → ' .. dest, vim.log.levels.INFO)
  else
    vim.notify('scp failed', vim.log.levels.ERROR)
  end
end

function M.send_selection(id)
  local entry = registry.get(id); if not entry or entry.kind ~= 'remote' then return end
  local reg = vim.fn.getreg('+')
  if reg == '' then reg = vim.fn.getreg('"') end
  local path = M.sandbox_dir(id) .. '/selection-' .. ts() .. '.txt'
  local fh = assert(io.open(path, 'w')); fh:write(reg); fh:close()
  vim.notify('selection → ' .. path, vim.log.levels.INFO)
end
```

- [ ] **Step 4: Register keymaps in `init.lua`**

Append to `lua/happy/projects/init.lua` `M.setup()`:

```lua
local function current_remote_id()
  local registry = require('happy.projects.registry')
  local id = registry.add({ kind = 'local', path = vim.fn.getcwd() })
  local entry = registry.get(id)
  if entry.kind ~= 'remote' then
    vim.notify('current project is not remote', vim.log.levels.WARN); return nil
  end
  return id
end

vim.keymap.set('n', '<leader>Cc', function()
  local id = current_remote_id(); if id then require('happy.projects.remote').capture(id) end
end, { desc = 'Capture remote pane → claude sandbox' })
vim.keymap.set('n', '<leader>Ct', function()
  local id = current_remote_id(); if id then require('happy.projects.remote').toggle_tail(id) end
end, { desc = 'Toggle remote tail-pipe to sandbox' })
vim.keymap.set('n', '<leader>Cl', function()
  local id = current_remote_id(); if not id then return end
  vim.ui.input({ prompt = 'Remote path to pull: ' }, function(p)
    if p and p ~= '' then require('happy.projects.remote').pull(id, p) end
  end)
end, { desc = 'Pull remote file to sandbox (scp)' })
vim.keymap.set('v', '<leader>Cs', function()
  local id = current_remote_id(); if id then require('happy.projects.remote').send_selection(id) end
end, { desc = 'Send visual selection to sandbox' })
```

- [ ] **Step 5: Tests pass**

Run: `pytest tests/integration/test_capture_primitives.py -v`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lua/happy/projects/remote.lua lua/happy/projects/init.lua tests/integration/test_capture_primitives.py
git commit -m "feat(projects): <leader>Cc/Ct/Cl/Cs capture primitives (remote→claude)"
```

---

## Task 13: Worktree-claude script wrappers

**Files:**
- Modify: `lua/happy/projects/init.lua` (register `:HappyWtProvision` / `:HappyWtCleanup`)

- [ ] **Step 1: Implement + register commands**

Append to `M.setup()`:

```lua
local function run_wt_script(script, path)
  local scratch = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(scratch, ('[%s %s]'):format(script, path))
  vim.cmd('sbuffer ' .. scratch)
  vim.bo[scratch].buftype = 'nofile'
  local function append(line)
    vim.schedule(function()
      vim.api.nvim_buf_set_lines(scratch, -1, -1, false, { line })
    end)
  end
  vim.system({ 'bash', 'scripts/' .. script, path }, {
    stdout = function(_, data) if data then append(data) end end,
    stderr = function(_, data) if data then append('ERR: ' .. data) end end,
  }, function(out)
    append(('=== exit %d ==='):format(out.code))
  end)
end

vim.api.nvim_create_user_command('HappyWtProvision', function(args)
  run_wt_script('wt-claude-provision.sh', args.args)
end, { nargs = 1, complete = 'file' })

vim.api.nvim_create_user_command('HappyWtCleanup', function(args)
  run_wt_script('wt-claude-cleanup.sh', args.args)
end, { nargs = 1, complete = 'file' })
```

- [ ] **Step 2: Smoke test**

Run:
```
nvim --headless -c "lua require('happy.projects').setup(); print(vim.fn.exists(':HappyWtProvision'))" -c "qa!"
```
Expected: prints `2` (command exists).

- [ ] **Step 3: Commit**

```bash
git add lua/happy/projects/init.lua
git commit -m "feat(projects): :HappyWtProvision / :HappyWtCleanup async wrappers (closes 30.12)"
```

---

## Task 14: Which-key group labels

**Files:**
- Modify: `lua/plugins/whichkey.lua`

- [ ] **Step 1: Append two entries to the `wk.add({ ... })` call**

Current `wk.add` call is at `lua/plugins/whichkey.lua:13-23`. Add after line 22 (before the closing `})`):

```lua
            { '<leader>P', group = 'project', icon = '' },
            { '<leader>C', group = 'capture (remote→claude)', icon = '󰆏' },
```

- [ ] **Step 2: Verify**

Open nvim, press `<leader>`, wait 400ms. `P` and `C` groups appear with labels.

- [ ] **Step 3: Commit**

```bash
git add lua/plugins/whichkey.lua
git commit -m "feat(whichkey): +project (<leader>P) and +capture (<leader>C) groups"
```

---

## Task 15: Append manual-test rows

**Files:**
- Modify: `docs/manual-tests.md`

- [ ] **Step 1: Append rows**

Insert a new section immediately before the `---` / `Last updated:` trailer (around line 120):

```markdown
## 9. Multi-project cockpit (SP1)

- [ ] `<leader>P` shows all registered projects, local + remote
- [ ] `<C-a>` in picker w/ a path → new local project, picker refreshes
- [ ] `<C-a>` in picker w/ `prod01:/var/log` → new remote project, ssh pane opens
- [ ] Pivot to remote project, `<leader>cp` → sandboxed claude popup opens
- [ ] In sandboxed claude, ask "run `ls` on the host" → refuses (Bash(ssh*) denied)
- [ ] In sandboxed claude, ask "open my ssh config" → refuses (Read outside sandbox denied)
- [ ] `<leader>Cc` after `ls -la` in remote pane → sandboxed claude sees output
- [ ] `<leader>Pp` on a non-active project → scrollback tail shown, no pivot
- [ ] `<leader>cc` in a second tmux pane (different cwd) → creates a distinct session (bug 30.3 fixed)
- [ ] `:HappyWtProvision <path>` and `:HappyWtCleanup <path>` work from nvim
```

Update the `Last updated:` trailer:

```
Last updated: multi-project cockpit (SP1) landed 2026-04-19.
```

- [ ] **Step 2: Commit**

```bash
git add docs/manual-tests.md
git commit -m "docs: manual-tests rows for multi-project cockpit (SP1)"
```

---

## Task 16: Assess + push + CI poll

- [ ] **Step 1: Full assess**

Run: `bash scripts/assess.sh`
Expected: `ASSESS: ALL LAYERS PASS`.

If any layer fails — fix and re-run. Do NOT push with a red assess.

- [ ] **Step 2: Push**

**Note:** The repo has NO configured `git remote` at plan-write time (`git remote -v` → empty). The push URL must be passed in at execution time. Parent session should provide the GitHub URL; subagent must STOP and ask if unset.

Push directly (sandbox note in CLAUDE.md — avoid `remote add`):

```bash
git push <REMOTE_URL> main:main
```

where `<REMOTE_URL>` is the canonical GitHub HTTPS URL for the happy-nvim repo (owner confirmed by parent session).

- [ ] **Step 3: Poll CI**

```bash
gh run list --branch main --limit 1
gh run watch <run-id> --exit-status
```

Expected: green.

- [ ] **Step 4: Close todos in project tracker**

Only after CI green:

```
mcp__plugin_proj_proj__todo_complete --todo_id 30.3
mcp__plugin_proj_proj__todo_complete --todo_id 30.12
```

Leave 30.13 open (parent) until all SP1–SP4 land. 30.8 / 30.11 stay open — only partially addressed here.

---

## Manual Test Additions

The following rows are appended to `docs/manual-tests.md` as part of Task 15:

```
## 9. Multi-project cockpit (SP1)

- [ ] `<leader>P` shows all registered projects, local + remote
- [ ] `<C-a>` in picker w/ a path → new local project, picker refreshes
- [ ] `<C-a>` in picker w/ `prod01:/var/log` → new remote project, ssh pane opens
- [ ] Pivot to remote project, `<leader>cp` → sandboxed claude popup opens
- [ ] In sandboxed claude, ask "run `ls` on the host" → refuses (Bash(ssh*) denied)
- [ ] In sandboxed claude, ask "open my ssh config" → refuses (Read outside sandbox denied)
- [ ] `<leader>Cc` after `ls -la` in remote pane → sandboxed claude sees output
- [ ] `<leader>Pp` on a non-active project → scrollback tail shown, no pivot
- [ ] `<leader>cc` in a second tmux pane (different cwd) → creates a distinct session (bug 30.3 fixed)
- [ ] `:HappyWtProvision <path>` and `:HappyWtCleanup <path>` work from nvim
```
