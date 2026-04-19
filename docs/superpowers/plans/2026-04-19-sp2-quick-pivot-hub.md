# SP2 Quick-Pivot Hub Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `<leader><leader>` quick-pivot hub — one picker merging projects + hosts + orphan claude sessions, frecency-weighted.

**Architecture:** New module `lua/happy/hub/` reads from SP1 registry + SP3 hosts + tmux list-sessions. Pure aggregator — no mutations. One telescope picker, per-kind `on_pivot` closures reuse existing pivot/ssh/switch-client actions.

**Tech Stack:** Lua 5.1 (LuaJIT via Neovim 0.11+), telescope.nvim, plenary + pytest integration.

**Reference:** `docs/superpowers/specs/2026-04-19-sp2-quick-pivot-hub-design.md`

**Working branch:** Reuse `/home/raul/worktrees/happy-nvim/feat-sp1-cockpit` (branch `feat-sp1-cockpit`). HEAD matches remote `main` post-SP3. New commits push to `main`.

---

## File Plan

**New files:**
- `lua/happy/hub/init.lua` — `M.setup()`, `M.open()`, weight/sort logic
- `lua/happy/hub/sources.lua` — `project_rows()`, `host_rows()`, `session_rows()`
- `tests/happy_hub_sources_spec.lua` — plenary unit tests for source fns + merge
- `tests/integration/test_hub_pivot.py` — end-to-end smoke (optional; covered by plenary)

**Modified files:**
- `init.lua` — add `'happy.hub'` to module list (line 33)
- `lua/coach/tips.lua` — append `<leader><leader>` entry
- `docs/manual-tests.md` — new `§ 13` with 4 rows

---

## Task 1: `happy.hub.sources` — project / host / session rows

**Files:**
- Create: `lua/happy/hub/sources.lua`
- Create: `tests/happy_hub_sources_spec.lua`

- [ ] **Step 1: Write failing plenary test**

`tests/happy_hub_sources_spec.lua`:

```lua
local sources = require('happy.hub.sources')

describe('happy.hub.sources.project_rows', function()
  local orig_registry
  before_each(function()
    orig_registry = package.loaded['happy.projects.registry']
    package.loaded['happy.projects.registry'] = {
      list = function()
        return {
          { id = 'proj-a', kind = 'local', path = '/p/a', last_opened = os.time() - 60 },
          { id = 'proj-b', kind = 'remote', host = 'h', path = '/p/b', last_opened = os.time() - 120 },
        }
      end,
      score = function(id) return id == 'proj-a' and 10 or 5 end,
      get = function(id)
        if id == 'proj-a' then return { kind = 'local', path = '/p/a' } end
        if id == 'proj-b' then return { kind = 'remote', host = 'h', path = '/p/b' } end
        return nil
      end,
    }
  end)
  after_each(function()
    package.loaded['happy.projects.registry'] = orig_registry
  end)

  it('emits one row per registered project with correct kind', function()
    local rows = sources.project_rows()
    assert.equals(2, #rows)
    local kinds = {}
    for _, r in ipairs(rows) do kinds[r.kind] = true end
    assert.is_true(kinds['project'])
  end)

  it('attaches on_pivot closure that calls projects.pivot.pivot', function()
    local called_with
    package.loaded['happy.projects.pivot'] = {
      pivot = function(id) called_with = id end,
    }
    local rows = sources.project_rows()
    rows[1].on_pivot()
    assert.equals(rows[1].id, called_with)
    package.loaded['happy.projects.pivot'] = nil
  end)
end)

describe('happy.hub.sources.host_rows', function()
  local orig_hosts
  before_each(function()
    orig_hosts = package.loaded['remote.hosts']
    package.loaded['remote.hosts'] = {
      list = function()
        return {
          { host = '[+ Add host]', marker = 'add' },
          { host = 'prod01', score = 8.2 },
          { host = 'dev02', score = 3.1 },
        }
      end,
      record = function(_) end,
    }
  end)
  after_each(function()
    package.loaded['remote.hosts'] = orig_hosts
  end)

  it('drops the add-marker entry', function()
    local rows = sources.host_rows()
    assert.equals(2, #rows)
    for _, r in ipairs(rows) do
      assert.is_nil(r.id:match('^%['))
    end
  end)

  it('emits kind=host with id=host-name', function()
    local rows = sources.host_rows()
    assert.equals('host', rows[1].kind)
    assert.equals('prod01', rows[1].id)
  end)
end)

describe('happy.hub.sources.session_rows', function()
  local orig_registry
  before_each(function()
    orig_registry = package.loaded['happy.projects.registry']
    package.loaded['happy.projects.registry'] = {
      get = function(id)
        if id == 'proj-a' then return { kind = 'local' } end
        return nil
      end,
    }
  end)
  after_each(function()
    package.loaded['happy.projects.registry'] = orig_registry
  end)

  it('emits orphan sessions only (not in registry)', function()
    sources._set_tmux_fn_for_test(function(args)
      if args[2] == 'list-sessions' then
        return 'cc-proj-a\ncc-legacy\nremote-orphan\nrandom-other'
      end
      return ''
    end)
    local rows = sources.session_rows()
    -- cc-proj-a is in registry → suppressed
    -- cc-legacy + remote-orphan → kept
    -- random-other → does not match cc- / remote- prefix → dropped
    assert.equals(2, #rows)
    local ids = {}
    for _, r in ipairs(rows) do ids[r.id] = true end
    assert.is_true(ids['cc-legacy'])
    assert.is_true(ids['remote-orphan'])
    assert.is_nil(ids['cc-proj-a'])
  end)
end)
```

- [ ] **Step 2: Run to verify failure**

```bash
cd /home/raul/worktrees/happy-nvim/feat-sp1-cockpit
export XDG_DATA_HOME=$TMPDIR/happy-t1
mkdir -p $XDG_DATA_HOME/nvim/site/pack/vendor/start
ln -sfn /home/raul/.local/share/nvim/lazy/plenary.nvim \
  $XDG_DATA_HOME/nvim/site/pack/vendor/start/plenary.nvim
nvim --clean --headless -u tests/minimal_init.lua \
  -c "PlenaryBustedFile tests/happy_hub_sources_spec.lua" -c "qa!"
```

Expected: FAIL — `module 'happy.hub.sources' not found`.

- [ ] **Step 3: Create `lua/happy/hub/sources.lua`**

```lua
-- lua/happy/hub/sources.lua — source aggregators for happy.hub.
--
-- Each source returns a list of entries shaped:
--   { kind, id, label, status, raw_score, on_pivot }
--
-- The hub (happy.hub.init) merges and weights these into a single
-- telescope picker. Sources must be PURE READERS — never mutate
-- registry/hosts/tmux state.
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
```

- [ ] **Step 4: Run test to verify pass**

Expected: 3 describe blocks, 6 `it` assertions — all PASS.

- [ ] **Step 5: Commit**

```bash
git add lua/happy/hub/sources.lua tests/happy_hub_sources_spec.lua
git commit -m "feat(hub): sources — projects/hosts/sessions aggregators"
```

---

## Task 2: `happy.hub.init` — merge + weight + picker

**Files:**
- Create: `lua/happy/hub/init.lua`
- Extend: `tests/happy_hub_sources_spec.lua` (add merge test)

- [ ] **Step 1: Append merge test**

Add to `tests/happy_hub_sources_spec.lua`:

```lua
describe('happy.hub merge + weight', function()
  it('sorts merged entries by weighted normalized score', function()
    local sources = require('happy.hub.sources')
    -- Stub sources w/ known raw scores.
    sources.project_rows = function()
      return {
        { kind = 'project', id = 'p-hot', raw_score = 10, on_pivot = function() end },
        { kind = 'project', id = 'p-cold', raw_score = 1, on_pivot = function() end },
      }
    end
    sources.host_rows = function()
      return { { kind = 'host', id = 'h-hot', raw_score = 10, on_pivot = function() end } }
    end
    sources.session_rows = function()
      return { { kind = 'session', id = 's-hot', raw_score = 1, on_pivot = function() end } }
    end

    local hub = require('happy.hub')
    hub._reset_weights_for_test()
    local merged = hub._merge_for_test()
    -- Default weights: project=1.0, session=0.8, host=0.6
    -- Normalized raw_score within kind (divide by kind max):
    --   p-hot: 10/10=1.0 * 1.0 = 1.0
    --   p-cold: 1/10=0.1 * 1.0 = 0.1
    --   h-hot: 10/10=1.0 * 0.6 = 0.6
    --   s-hot: 1/1=1.0 * 0.8 = 0.8
    -- Expected sort: p-hot (1.0) > s-hot (0.8) > h-hot (0.6) > p-cold (0.1)
    assert.equals('p-hot', merged[1].id)
    assert.equals('s-hot', merged[2].id)
    assert.equals('h-hot', merged[3].id)
    assert.equals('p-cold', merged[4].id)
  end)

  it('applies user-supplied weight overrides', function()
    local sources = require('happy.hub.sources')
    sources.project_rows = function()
      return { { kind = 'project', id = 'p', raw_score = 1, on_pivot = function() end } }
    end
    sources.host_rows = function()
      return { { kind = 'host', id = 'h', raw_score = 1, on_pivot = function() end } }
    end
    sources.session_rows = function() return {} end

    local hub = require('happy.hub')
    hub.setup({ weights = { project = 0.1, host = 2.0 } })
    local merged = hub._merge_for_test()
    -- p: 1.0 * 0.1 = 0.1 ; h: 1.0 * 2.0 = 2.0
    assert.equals('h', merged[1].id)
    assert.equals('p', merged[2].id)
    hub._reset_weights_for_test()
  end)
end)
```

- [ ] **Step 2: Create `lua/happy/hub/init.lua`**

```lua
-- lua/happy/hub/init.lua — <leader><leader> quick-pivot hub.
--
-- Merges projects (SP1) + hosts (SP3) + orphan claude sessions into a
-- single frecency-weighted picker. Sources in `sources.lua` are pure
-- readers; this module does the weight + sort + picker.
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

  -- Normalize per-kind, apply weight.
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
  project = '',  -- local default; overridden for remote below
  host = '󰢹',
  session = '󰚩',
}

local function icon_for(row)
  local ok, registry = pcall(require, 'happy.projects.registry')
  if row.kind == 'project' and ok then
    local entry = registry.get(row.id)
    if entry and entry.kind == 'remote' then
      return ''
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
```

- [ ] **Step 3: Run merged test file**

```bash
nvim --clean --headless -u tests/minimal_init.lua \
  -c "PlenaryBustedFile tests/happy_hub_sources_spec.lua" -c "qa!"
```

Expected: all PASS (6 source tests + 2 merge tests = 8).

- [ ] **Step 4: Regression**

Re-run all `happy_*_spec.lua` + integration to confirm no regression.

- [ ] **Step 5: Commit**

```bash
git add lua/happy/hub/init.lua tests/happy_hub_sources_spec.lua
git commit -m "feat(hub): merge sources w/ per-kind normalized weights + telescope picker"
```

---

## Task 3: Wire into `init.lua` + coach tips

**Files:**
- Modify: `init.lua` (project root, line 33)
- Modify: `lua/coach/tips.lua`

- [ ] **Step 1: Edit project-root `init.lua`**

Current line 33:

```lua
for _, mod in ipairs({ 'coach', 'clipboard', 'tmux', 'remote', 'happy.assess', 'happy.projects' }) do
```

Change to:

```lua
for _, mod in ipairs({ 'coach', 'clipboard', 'tmux', 'remote', 'happy.assess', 'happy.projects', 'happy.hub' }) do
```

- [ ] **Step 2: Append to `lua/coach/tips.lua`**

Insert before the closing `}` (match stylua column-width=100 multi-line form since the entry is >100 chars):

```lua
  {
    keys = '<leader><leader>',
    desc = 'quick-pivot hub: projects + hosts + sessions (SP2)',
    category = 'projects',
  },
```

- [ ] **Step 3: Smoke test**

```bash
nvim --headless -c "lua require('happy.hub').setup(); print(vim.fn.hasmapto('happy.hub'))" -c "qa!" 2>&1 | tail -5
```

Or simpler: load the setup + check `<leader><leader>` is mapped:

```bash
nvim --headless -c "lua require('happy.hub').setup(); print(vim.fn.maparg(' ', 'n'))" -c "qa!"
```

(The leader-leader mapping should be visible as a registered normal-mode keymap.)

- [ ] **Step 4: Commit**

```bash
git add init.lua lua/coach/tips.lua
git commit -m "feat(hub): wire <leader><leader> keymap + cheatsheet entry"
```

---

## Task 4: Manual-tests rows

**Files:**
- Modify: `docs/manual-tests.md`

- [ ] **Step 1: Append `§ 13` before the `---` trailer**

```markdown
## 13. Quick-pivot hub (SP2)

- [ ] `<leader><leader>` opens a single picker merging projects + hosts + orphan claude sessions. Entries show kind icon + id + label + status + age.
- [ ] Pivot to a project entry → same effect as `<leader>P` → Enter (cwd cd + tmux session focus).
- [ ] Pivot to a host entry → same effect as `<leader>ss` → Enter (ssh in tmux split).
- [ ] Sessions whose slug matches a registered project are suppressed from the session source (no duplicate row).
```

Update `Last updated:` trailer to `Last updated: SP2 quick-pivot hub landed 2026-04-19.`

- [ ] **Step 2: Commit**

```bash
git add docs/manual-tests.md
git commit -m "docs: manual-tests rows for SP2 quick-pivot hub"
```

---

## Task 5: Assess + push + CI

- [ ] **Step 1: Full assess**

```bash
cd /home/raul/worktrees/happy-nvim/feat-sp1-cockpit
bash scripts/assess.sh 2>&1 | tail -15
```

Expected: `ASSESS: ALL LAYERS PASS`. Fix stylua formatting if lint fails.

- [ ] **Step 2: Push**

```bash
git push https://github.com/raulfrk/happy-nvim.git feat-sp1-cockpit:main
```

- [ ] **Step 3: Poll CI**

```bash
mkdir -p $TMPDIR/gh-cache
XDG_CACHE_HOME=$TMPDIR/gh-cache gh run list --repo raulfrk/happy-nvim --branch main --limit 1
XDG_CACHE_HOME=$TMPDIR/gh-cache gh run watch <RUN_ID> --repo raulfrk/happy-nvim --exit-status
```

- [ ] **Step 4: No todos to close**

SP2 has no tracking todos (30.13 parent stays open until SP4 lands).

---

## Self-review

**Spec coverage:**
- §3 architecture → Tasks 1 + 2 ✓
- §4 components → Tasks 1 + 2 + 3 ✓
- §5 scoring → Task 2 (merge + weight test) ✓
- §6 pivot actions → Task 1 (on_pivot closures per kind) ✓
- §7 session-orphan detection → Task 1 (session_rows test) ✓
- §8 display → Task 2 (picker entry_maker) ✓
- §9 keymap + tips → Task 3 ✓
- §10 testing → Tasks 1 + 2 (plenary) ✓
- §Manual Test Additions → Task 4 ✓

**Placeholder scan:** none. Every code block is complete.

**Type consistency:** row shape `{ kind, id, label, status, raw_score, on_pivot }` is defined in Task 1 `sources.lua` header comment, used in Task 2 `init.lua` merge + picker. Consistent.

---

## Manual Test Additions

(Listed in Task 4. Appended to `docs/manual-tests.md` by the
implementing subagent as part of Task 4's commit.)

```markdown
## 13. Quick-pivot hub (SP2)

- [ ] `<leader><leader>` opens a single picker merging projects + hosts + orphan claude sessions. Entries show kind icon + id + label + status + age.
- [ ] Pivot to a project entry → same effect as `<leader>P` → Enter (cwd cd + tmux session focus).
- [ ] Pivot to a host entry → same effect as `<leader>ss` → Enter (ssh in tmux split).
- [ ] Sessions whose slug matches a registered project are suppressed from the session source (no duplicate row).
```
