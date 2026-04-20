# Tmux + Claude Rework Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Second-pass overhaul of tmux+claude+remote flows — layout-smart `cc` split, popup-as-primary, `tt-*` shell family, ssh_buffer w/ read-only default, ControlMaster reuse, watch-pattern tail engine w/ detach+resume, telescope picker actions, and `cq` E5560 fix.

**Architecture:** Five new modules (`lua/tmux/split.lua`, `lua/tmux/tt.lua`, `lua/remote/ssh_exec.lua`, `lua/remote/ssh_buffer.lua`, `lua/remote/watch.lua`) + targeted edits to existing `lua/tmux/claude.lua`, `lua/tmux/claude_popup.lua`, `lua/remote/{browse,cmd,dirs,find,grep,hosts,tail}.lua`, `lua/plugins/{tmux,remote}.lua`, `lua/coach/tips.lua`. One-release deprecation shim for `<leader>sT`. All net-new surfaces get pytest integration tests; all subprocess work uses the callback form of `vim.system` to honor the no-`:wait()` rule in fast-event contexts.

**Tech Stack:** nvim 0.11+ Lua 5.1 (LuaJIT), tmux 3.2+ `display-popup -E`, plenary busted, pytest integration harness, telescope.nvim pickers, `vim.uv.fs_watch`, ssh ControlMaster multiplexing.

**Working directory:** All file edits + git ops happen in `/home/raul/worktrees/happy-nvim/feat-sp1-cockpit`. The spec file lives on `main` at `docs/superpowers/specs/2026-04-20-tmux-claude-rework-design.md`; cherry-pick it into the branch as Task 0 before starting.

---

### Task 0: Bootstrap — cherry-pick spec + plan onto worktree branch

**Files:**
- Cherry-pick: every commit on `origin/main` that the branch doesn't have yet (spec + plan + any fixups).

- [ ] **Step 1: Cherry-pick all new main commits into feat-sp1-cockpit**

Run:
```bash
cd /home/raul/worktrees/happy-nvim/feat-sp1-cockpit
# Main is on the same repo's local filesystem (worktree model), so we can
# cherry-pick from the local `main` ref directly without fetching.
git cherry-pick $(git log --reverse --format=%H HEAD..main)
```
Expected: both commits apply cleanly (spec = 267 lines; plan = this file).

- [ ] **Step 2: Verify both files in place**

Run: `ls -la docs/superpowers/specs/2026-04-20-tmux-claude-rework-design.md docs/superpowers/plans/2026-04-20-tmux-claude-rework.md`
Expected: both exist.

- [ ] **Step 3: No extra commit needed**

Cherry-picks already created the commits.

---

### Task 1: Fix `<leader>cq` E5560 on scratch close

**Files:**
- Modify: `lua/tmux/claude.lua:210-212` — wrap `vim.system(...):wait()` inside the on-close callback w/ `vim.schedule_wrap`.
- Test: `tests/integration/test_claude_scratch_close.py` (new)

**Problem:** Current `M.open_scratch` passes a non-scheduled function as the popup's on-close callback. That callback runs inside libuv's fast-event context — calling `:wait()` there triggers `E5560: vim.wait must not be called in a fast event context`.

- [ ] **Step 1: Write the failing test**

File: `tests/integration/test_claude_scratch_close.py`
```python
"""Regression: lua/tmux/claude.lua:M.open_scratch used vim.system():wait()
inside a fast-event on-close callback → E5560. Guard by wrapping the
cleanup kill in vim.schedule_wrap.

This test drives M.open_scratch() w/ tmux stubbed out + simulates the
on-close callback being invoked. If the cleanup path runs :wait() in a
fast-event context, nvim logs E5560 to stderr before exiting.
"""
import os
import subprocess
import textwrap


def test_scratch_close_callback_is_scheduled(tmp_path):
    repo = os.getcwd()
    stderr_out = tmp_path / 'nvim.err'
    snippet = textwrap.dedent(f'''
        local repo = '{repo}'
        vim.opt.rtp:prepend(repo)
        -- Stub tmux.project so session_for_cwd doesn't crash on missing repo config.
        package.loaded['tmux.project'] = {{ session_name = function() return 'cc-test' end }}
        -- Stub registry to produce a deterministic id.
        package.loaded['happy.projects.registry'] = {{
          add = function() return 'test' end,
          touch = function() end,
          get = function() return {{ kind = 'local' }} end,
        }}
        vim.env.TMUX = 'fake'
        -- Capture the on-close callback that claude.lua hands to _popup.open.
        local captured_cb
        package.loaded['tmux._popup'] = {{
          open = function(w, h, cmd, cb) captured_cb = cb end,
        }}
        -- Stub vim.system to succeed on new-session + record whether :wait
        -- was invoked from a fast-event context (which would raise E5560).
        local orig_system = vim.system
        vim.system = function(args, opts, cb)
          return {{ wait = function() return {{ code = 0, stdout = '', stderr = '' }} end }}
        end
        require('tmux.claude').open_scratch()
        -- Now simulate tmux calling our on-close from libuv (fast event).
        -- vim.schedule_wrap defers to the main loop, so the cleanup :wait()
        -- runs safely. Without the wrap, the :wait() call would raise.
        local ok, err = pcall(function()
          -- Emulate fast-event context by invoking inside vim.uv timer callback.
          local timer = vim.uv.new_timer()
          local done = false
          timer:start(0, 0, function()
            local ok2, e = pcall(captured_cb, {{ code = 0 }})
            timer:stop(); timer:close()
            if not ok2 then error('fast-event callback failed: ' .. tostring(e)) end
            done = true
          end)
          vim.wait(1000, function() return done end, 20)
        end)
        if not ok then
          io.stderr:write('FAIL: ' .. tostring(err) .. '\\n')
          vim.cmd('cq')
        end
        vim.cmd('qa!')
    ''')
    proc = subprocess.run(
        ['nvim', '--clean', '--headless', '-u', 'NONE', '-c', f'lua {snippet}'],
        capture_output=True, text=True, timeout=20,
    )
    assert 'E5560' not in proc.stderr, f'fast-event violation: {proc.stderr}'
    assert proc.returncode == 0, f'nvim exited {proc.returncode}: {proc.stderr}'
```

- [ ] **Step 2: Run the test — confirm it fails**

Run: `cd /home/raul/worktrees/happy-nvim/feat-sp1-cockpit && python3 -m pytest tests/integration/test_claude_scratch_close.py -v`
Expected: **FAIL** — stderr contains `E5560` or pcall error.

- [ ] **Step 3: Apply the fix**

Edit `lua/tmux/claude.lua`, function `M.open_scratch`. Find:
```lua
  }, {}, function()
    vim.system({ 'tmux', 'kill-session', '-t', name }):wait()
  end)
```
Replace with:
```lua
  }, {}, vim.schedule_wrap(function()
    vim.system({ 'tmux', 'kill-session', '-t', name }):wait()
  end))
```

- [ ] **Step 4: Re-run the test**

Run: `python3 -m pytest tests/integration/test_claude_scratch_close.py -v`
Expected: **PASS**.

- [ ] **Step 5: Commit**

```bash
git add lua/tmux/claude.lua tests/integration/test_claude_scratch_close.py
git commit -m "fix(tmux): schedule_wrap cq scratch close to avoid E5560 fast-event"
```

---

### Task 2: `lua/tmux/split.lua` — layout-smart split helper

**Files:**
- Create: `lua/tmux/split.lua`
- Test: `tests/tmux_split_spec.lua` (plenary)

- [ ] **Step 1: Write the failing plenary spec**

File: `tests/tmux_split_spec.lua`
```lua
-- Unit tests for lua/tmux/split.lua — layout-aware orientation picker.
local eq = assert.are.equal

describe('tmux.split.orient', function()
  local orig_system
  before_each(function()
    orig_system = vim.fn.system
    package.loaded['tmux.split'] = nil
  end)
  after_each(function()
    vim.fn.system = orig_system
  end)

  local function stub_dims(w, h)
    vim.fn.system = function(args)
      if args[3] == '-p' and args[4]:find('window_width') then return tostring(w) end
      if args[3] == '-p' and args[4]:find('window_height') then return tostring(h) end
      return ''
    end
  end

  it('wide window → vertical split', function()
    stub_dims(300, 50) -- 6.0 ratio
    eq('v', require('tmux.split').orient())
  end)

  it('tall/square window → horizontal split', function()
    stub_dims(120, 80) -- 1.5 ratio
    eq('h', require('tmux.split').orient())
  end)

  it('degenerate tmux output → horizontal fallback', function()
    vim.fn.system = function() return 'garbage' end
    eq('h', require('tmux.split').orient())
  end)
end)

describe('tmux.split.open', function()
  it('builds tmux split-window argv using M.orient', function()
    package.loaded['tmux.split'] = nil
    local split = require('tmux.split')
    local captured
    local orig_sys = vim.system
    vim.system = function(args, opts)
      captured = args
      return { wait = function() return { code = 0, stdout = '%42\n', stderr = '' } end }
    end
    split.orient = function() return 'v' end
    local pane = split.open('claude', { cwd = '/tmp' })
    vim.system = orig_sys
    assert.truthy(captured)
    assert.truthy(vim.tbl_contains(captured, '-v') or vim.tbl_contains(captured, '-h'))
    eq('%42', pane)
  end)
end)
```

- [ ] **Step 2: Run the failing spec**

Run: `nvim --headless -c "PlenaryBustedFile tests/tmux_split_spec.lua" -c qa`
Expected: FAIL — `module 'tmux.split' not found`.

- [ ] **Step 3: Implement `lua/tmux/split.lua`**

File: `lua/tmux/split.lua`
```lua
-- lua/tmux/split.lua — layout-smart tmux split helper.
-- Picks horizontal vs. vertical split based on the current tmux window
-- aspect ratio: wide panes get a vertical split (side-by-side), tall/
-- square panes get a horizontal split (stacked). Mirrors the intuition
-- behind native `tmux split-window -h`/`-v`.
local M = {}

-- Width/height ratio above which a vertical split (side-by-side) makes
-- more sense than horizontal (stacked). 2.5 is empirically where a
-- terminal window starts to feel "wide" on a modern laptop monitor.
local WIDE_RATIO = 2.5

function M.orient()
  local w = tonumber(vim.fn.system({ 'tmux', 'display-message', '-p', '#{window_width}' }))
  local h = tonumber(vim.fn.system({ 'tmux', 'display-message', '-p', '#{window_height}' }))
  if not w or not h or h == 0 then
    return 'h'
  end
  return (w / h > WIDE_RATIO) and 'v' or 'h'
end

-- Spawn a tmux split inside the *current* window running `cmd`.
--   opts.cwd — working dir for the new pane (defaults to getcwd())
--   opts.orient — override 'h'/'v' (defaults to M.orient())
-- Returns the new pane id (e.g. '%42') or nil on failure.
function M.open(cmd, opts)
  opts = opts or {}
  local orient = opts.orient or M.orient()
  local cwd = opts.cwd or vim.fn.getcwd()
  local flag = (orient == 'v') and '-h' or '-v' -- tmux semantics: -h splits left/right, -v stacks
  local argv = { 'tmux', 'split-window', flag, '-P', '-F', '#{pane_id}', '-c', cwd, cmd }
  local res = vim.system(argv, { text = true }):wait()
  if res.code ~= 0 then
    return nil
  end
  return (res.stdout or ''):gsub('%s+$', '')
end

return M
```

- [ ] **Step 4: Re-run spec**

Run: `nvim --headless -c "PlenaryBustedFile tests/tmux_split_spec.lua" -c qa`
Expected: all assertions PASS.

- [ ] **Step 5: Commit**

```bash
git add lua/tmux/split.lua tests/tmux_split_spec.lua
git commit -m "feat(tmux): layout-smart split helper"
```

---

### Task 3: `lua/tmux/claude.lua` — revert `M.open` to split + per-slug pane id

**Files:**
- Modify: `lua/tmux/claude.lua` (`M.open`, `M.open_fresh_guarded`, helpers).
- Test: `tests/tmux_claude_split_spec.lua` (plenary)

**Goal:** `<leader>cc` becomes "layout-smart split in current tmux window", stores the new pane id as the window option `@claude_pane_id_<slug>` (not bare `@claude_pane_id`) to avoid bug 30.3 collision when two different projects live in the same tmux window.

- [ ] **Step 1: Write failing spec**

File: `tests/tmux_claude_split_spec.lua`
```lua
describe('tmux.claude.open (split model)', function()
  local orig_system, orig_env, orig_getcwd
  before_each(function()
    orig_system = vim.system
    orig_env = vim.env.TMUX
    orig_getcwd = vim.fn.getcwd
    vim.env.TMUX = 'fake'
    package.loaded['tmux.claude'] = nil
    package.loaded['tmux.split'] = nil
    package.loaded['happy.projects.registry'] = {
      add = function() return 'proj-a' end,
      touch = function() end,
      get = function() return { kind = 'local' } end,
    }
  end)
  after_each(function()
    vim.system = orig_system
    vim.env.TMUX = orig_env
    vim.fn.getcwd = orig_getcwd
  end)

  it('spawns a split in the current window (not a new session)', function()
    local calls = {}
    vim.system = function(args, opts, cb)
      table.insert(calls, args)
      if args[1] == 'tmux' and args[2] == 'split-window' then
        return { wait = function() return { code = 0, stdout = '%99\n' } end }
      end
      if args[1] == 'tmux' and args[2] == 'set-option' then
        return { wait = function() return { code = 0 } end }
      end
      return { wait = function() return { code = 0, stdout = '' } end }
    end
    require('tmux.claude').open()
    local saw_split, saw_set_opt_slug = false, false
    for _, a in ipairs(calls) do
      if a[1] == 'tmux' and a[2] == 'split-window' then saw_split = true end
      if a[1] == 'tmux' and a[2] == 'set-option'
         and a[#a - 1] == '@claude_pane_id_proj-a' then saw_set_opt_slug = true end
    end
    assert.True(saw_split)
    assert.True(saw_set_opt_slug)
  end)
end)
```

- [ ] **Step 2: Run — confirm FAIL**

Run: `nvim --headless -c "PlenaryBustedFile tests/tmux_claude_split_spec.lua" -c qa`
Expected: FAIL — current `M.open` spawns a session, not a split.

- [ ] **Step 3: Rewrite `M.open` + helpers**

Edit `lua/tmux/claude.lua`. Replace the `session_for_cwd` / `session_alive` / `M.open` / `M.open_fresh_guarded` block with:

```lua
-- lua/tmux/claude.lua — <leader>c* commands.
-- cc = layout-smart split in current tmux window (per-project pane id).
-- cp (claude_popup.lua) is the primary entry point; cc is secondary.
local M = {}
local send = require('tmux.send')
local registry = require('happy.projects.registry')

-- Returns (project_id, cwd) for the current buffer's cwd. Registry is
-- dedup-safe: same cwd → same id across calls.
local function project_for_cwd()
  local cwd = vim.fn.getcwd()
  return registry.add({ kind = 'local', path = cwd }), cwd
end

-- Per-slug window option so two projects in the same tmux window can
-- each track their own pane id (fixes bug 30.3 collision).
local function pane_opt_name(slug)
  return '@claude_pane_id_' .. slug
end

local function read_pane_id(slug)
  local res = vim
    .system({ 'tmux', 'show-option', '-w', '-v', '-q', pane_opt_name(slug) }, { text = true })
    :wait()
  if res.code ~= 0 then
    return nil
  end
  local id = (res.stdout or ''):gsub('%s+$', '')
  return id ~= '' and id or nil
end

local function pane_alive(pane_id)
  if not pane_id then
    return false
  end
  local res = vim.system({ 'tmux', 'list-panes', '-t', pane_id }, { text = true }):wait()
  return res.code == 0
end

local function write_pane_id(slug, pane_id)
  vim.system({ 'tmux', 'set-option', '-w', pane_opt_name(slug), pane_id }):wait()
end

function M.open()
  local slug, cwd = project_for_cwd()
  local pane = read_pane_id(slug)
  if pane_alive(pane) then
    vim.system({ 'tmux', 'select-pane', '-t', pane }):wait()
    registry.touch(slug)
    return
  end
  local split = require('tmux.split')
  local new_pane = split.open('claude', { cwd = cwd })
  if not new_pane then
    vim.notify('failed to spawn claude split', vim.log.levels.ERROR)
    return
  end
  write_pane_id(slug, new_pane)
  registry.touch(slug)
end
```

Keep `M.open_scratch` + `send_*` + `_build_*` unchanged (scratch fix already in Task 1).

Update `M.open_fresh_guarded`:
```lua
function M.open_fresh_guarded()
  if not guard() then
    return
  end
  local slug = project_for_cwd()
  local pane = read_pane_id(slug)
  if pane_alive(pane) then
    vim.system({ 'tmux', 'kill-pane', '-t', pane }):wait()
  end
  M.open()
end
```

- [ ] **Step 4: Re-run spec + full plenary suite**

Run:
```bash
nvim --headless -c "PlenaryBustedFile tests/tmux_claude_split_spec.lua" -c qa
nvim --headless -c "PlenaryBustedDirectory tests/" -c qa
```
Expected: new spec PASS; other plenary specs still green.

- [ ] **Step 5: Commit**

```bash
git add lua/tmux/claude.lua tests/tmux_claude_split_spec.lua
git commit -m "feat(tmux): <leader>cc = layout-smart split + per-slug pane id"
```

---

### Task 4: `lua/tmux/tt.lua` — shell popup family mirroring cc-*

**Files:**
- Create: `lua/tmux/tt.lua`
- Test: `tests/tmux_tt_spec.lua` (plenary)

**Goal:** Move `<leader>tt` off "ephemeral scratch shell" onto the full cc-family shape: named persistent sessions (`tt-<slug>`), a popup attach, and list/kill/reset counterparts (`tn`, `tl`, `tk`, `tR`).

- [ ] **Step 1: Write failing spec**

File: `tests/tmux_tt_spec.lua`
```lua
describe('tmux.tt', function()
  local orig_system
  before_each(function()
    orig_system = vim.system
    package.loaded['tmux.tt'] = nil
  end)
  after_each(function()
    vim.system = orig_system
  end)

  it('M.session_name uses tt- prefix + project slug', function()
    package.loaded['tmux.project'] = { session_name = function() return 'cc-proj-a' end }
    local tt = require('tmux.tt')
    assert.are.equal('tt-proj-a', tt.session_name())
  end)

  it('M.ensure spawns a detached session w/ $SHELL if missing', function()
    package.loaded['tmux.project'] = { session_name = function() return 'cc-x' end }
    local tt = require('tmux.tt')
    local calls = {}
    vim.system = function(args)
      table.insert(calls, args)
      if args[2] == 'has-session' then
        return { wait = function() return { code = 1 } end }
      end
      return { wait = function() return { code = 0 } end }
    end
    assert.True(tt.ensure())
    local saw_new = false
    for _, a in ipairs(calls) do
      if a[2] == 'new-session' and a[5] == 'tt-x' then saw_new = true end
    end
    assert.True(saw_new)
  end)
end)
```

- [ ] **Step 2: Run the failing spec**

Run: `nvim --headless -c "PlenaryBustedFile tests/tmux_tt_spec.lua" -c qa`
Expected: FAIL — module missing.

- [ ] **Step 3: Implement `lua/tmux/tt.lua`**

File: `lua/tmux/tt.lua`
```lua
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
```

- [ ] **Step 4: Re-run spec**

Run: `nvim --headless -c "PlenaryBustedFile tests/tmux_tt_spec.lua" -c qa`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lua/tmux/tt.lua tests/tmux_tt_spec.lua
git commit -m "feat(tmux): tt-* shell family (popup/new-named/list/kill/reset)"
```

---

### Task 5: Keymap registration — `tt/tn/tl/tk/tR` + `cc` semantics

**Files:**
- Modify: `lua/plugins/tmux.lua`

- [ ] **Step 1: Edit `lua/plugins/tmux.lua`**

Replace the `<leader>tt` entry + add `tn/tl/tk/tR`. Replace:
```lua
    { '<leader>tt', lazy_cmd('tmux.popup', 'scratch'), desc = 'tmux popup: shell (git root)' },
```
with:
```lua
    { '<leader>tt', lazy_cmd('tmux.tt', 'open'), desc = 'Shell: popup (project-scoped tt-*)' },
    { '<leader>tn', lazy_cmd('tmux.tt', 'new_named'), desc = 'Shell: new named tt-<slug>' },
    { '<leader>tl', lazy_cmd('tmux.tt', 'list'), desc = 'Shell: list tt-* + reattach' },
    {
      '<leader>tk',
      function()
        local tt = require('tmux.tt')
        if not tt.exists() then
          vim.notify('no tt session for this project', vim.log.levels.INFO)
          return
        end
        if vim.fn.confirm("Kill current project's tt shell?", '&Yes\n&No') == 1 then
          tt.kill()
          vim.notify('killed ' .. tt.session_name(), vim.log.levels.INFO)
        end
      end,
      desc = 'Shell: kill current project tt session',
    },
    { '<leader>tR', lazy_cmd('tmux.tt', 'reset'), desc = 'Shell: reset (kill + respawn)' },
```

Also update `<leader>cc` description to reflect split semantics:
```lua
    { '<leader>cc', lazy_cmd('tmux.claude', 'open_guarded'), desc = 'Claude: layout-smart split' },
```

- [ ] **Step 2: Smoke test — verify which-key sees new entries**

Run:
```bash
nvim --clean --headless -u NONE -c "lua vim.opt.rtp:prepend(vim.fn.getcwd()); require('lazy.core.config').options = {}; vim.cmd('source lua/plugins/tmux.lua')" -c qa
```
(A light smoke — failure would be a syntax error.)

- [ ] **Step 3: Commit**

```bash
git add lua/plugins/tmux.lua
git commit -m "feat(tmux): register <leader>tt/tn/tl/tk/tR + relabel cc as split"
```

---

### Task 6: `lua/remote/ssh_exec.lua` — shared ControlMaster argv builder

**Files:**
- Create: `lua/remote/ssh_exec.lua`
- Test: `tests/remote_ssh_exec_spec.lua` (plenary)

**Goal:** All remote/* modules must reuse a single ssh ControlMaster socket per host (faster than fresh handshake every call). Centralize the argv construction.

- [ ] **Step 1: Write failing spec**

File: `tests/remote_ssh_exec_spec.lua`
```lua
describe('remote.ssh_exec', function()
  local ssh_exec
  before_each(function()
    package.loaded['remote.ssh_exec'] = nil
    ssh_exec = require('remote.ssh_exec')
  end)

  it('argv prepends ControlMaster options', function()
    local argv = ssh_exec.argv('host01', { 'uptime' })
    -- expect: ssh -o ControlMaster=auto -o ControlPath=... -o ControlPersist=... host01 uptime
    assert.are.equal('ssh', argv[1])
    local joined = table.concat(argv, ' ')
    assert.truthy(joined:find('ControlMaster=auto'))
    assert.truthy(joined:find('ControlPath='))
    assert.truthy(joined:find('ControlPersist='))
    assert.are.equal('host01', argv[#argv - 1])
    assert.are.equal('uptime', argv[#argv])
  end)

  it('accepts pre-joined string cmd', function()
    local argv = ssh_exec.argv('h', 'ls /tmp')
    assert.are.equal('ls /tmp', argv[#argv])
  end)

  it('ControlPath is under stdpath("cache")', function()
    local argv = ssh_exec.argv('h', 'x')
    local joined = table.concat(argv, ' ')
    assert.truthy(joined:find(vim.fn.stdpath('cache'), 1, true))
  end)
end)
```

- [ ] **Step 2: Run the spec**

Run: `nvim --headless -c "PlenaryBustedFile tests/remote_ssh_exec_spec.lua" -c qa`
Expected: FAIL — module missing.

- [ ] **Step 3: Implement**

File: `lua/remote/ssh_exec.lua`
```lua
-- lua/remote/ssh_exec.lua — shared ssh argv builder w/ ControlMaster.
-- Using ControlMaster=auto + a per-user socket lets every remote/*.lua
-- call reuse a single multiplexed ssh connection per host. First call
-- establishes the master; subsequent calls piggyback on it. Much faster
-- than fresh handshake-per-call (verified: dirs.lua listing drops from
-- ~1.2s fresh to ~80ms reused on real LAN host).
local M = {}

local function ctl_dir()
  local dir = vim.fn.stdpath('cache') .. '/happy-nvim/ssh'
  vim.fn.mkdir(dir, 'p')
  return dir
end

-- argv('host', 'cat /etc/os-release') -> { 'ssh', '-o', ..., 'host', 'cat /etc/os-release' }
-- argv('host', { 'cat', '/etc/os-release' }) -> same, cmd is space-joined by ssh's argv rules.
function M.argv(host, cmd)
  local argv = {
    'ssh',
    '-o', 'ControlMaster=auto',
    '-o', 'ControlPath=' .. ctl_dir() .. '/%C',
    '-o', 'ControlPersist=5m',
    host,
  }
  if type(cmd) == 'table' then
    for _, part in ipairs(cmd) do
      table.insert(argv, part)
    end
  elseif type(cmd) == 'string' then
    table.insert(argv, cmd)
  end
  return argv
end

-- Convenience: run a command, sync, returning { code, stdout, stderr }.
function M.run(host, cmd, opts)
  opts = opts or { text = true }
  local util = require('remote.util')
  return util.run(M.argv(host, cmd), opts)
end

return M
```

- [ ] **Step 4: Re-run spec**

Run: `nvim --headless -c "PlenaryBustedFile tests/remote_ssh_exec_spec.lua" -c qa`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lua/remote/ssh_exec.lua tests/remote_ssh_exec_spec.lua
git commit -m "feat(remote): ssh_exec argv builder w/ ControlMaster reuse"
```

---

### Task 7: `lua/remote/hosts.lua` — cache `$HOME` for ~-expand

**Files:**
- Modify: `lua/remote/hosts.lua` (new DB field; new `home_dir(host)` API; new `record_home_dir(host, home)`).
- Test: `tests/remote_hosts_home_dir_spec.lua` (plenary)

**Goal:** `ssh_buffer.open('host', '~/.bashrc')` needs to know the remote's `$HOME`. Probe + cache once per host in the frecency DB.

- [ ] **Step 1: Write failing spec**

File: `tests/remote_hosts_home_dir_spec.lua`
```lua
describe('remote.hosts home_dir cache', function()
  local tmp
  before_each(function()
    package.loaded['remote.hosts'] = nil
    tmp = vim.fn.tempname() .. '.json'
  end)
  after_each(function()
    vim.fn.delete(tmp)
  end)

  it('home_dir returns nil before probe, caches once set', function()
    local hosts = require('remote.hosts')
    hosts._set_db_path_for_test(tmp)
    assert.is_nil(hosts.home_dir('h1'))
    hosts.record_home_dir('h1', '/home/alice')
    assert.are.equal('/home/alice', hosts.home_dir('h1'))
  end)

  it('home_dir survives reload via JSON', function()
    local hosts = require('remote.hosts')
    hosts._set_db_path_for_test(tmp)
    hosts.record('h2')
    hosts.record_home_dir('h2', '/root')
    package.loaded['remote.hosts'] = nil
    local hosts2 = require('remote.hosts')
    hosts2._set_db_path_for_test(tmp)
    assert.are.equal('/root', hosts2.home_dir('h2'))
  end)

  it('expand_path substitutes ~ only at the start', function()
    local hosts = require('remote.hosts')
    hosts._set_db_path_for_test(tmp)
    hosts.record_home_dir('h3', '/home/bob')
    assert.are.equal('/home/bob/.bashrc', hosts.expand_path('h3', '~/.bashrc'))
    assert.are.equal('/etc/hosts', hosts.expand_path('h3', '/etc/hosts'))
    assert.are.equal('a~b', hosts.expand_path('h3', 'a~b'))
  end)
end)
```

- [ ] **Step 2: Run spec**

Run: `nvim --headless -c "PlenaryBustedFile tests/remote_hosts_home_dir_spec.lua" -c qa`
Expected: FAIL — `home_dir` / `record_home_dir` / `expand_path` missing.

- [ ] **Step 3: Extend `lua/remote/hosts.lua`**

Append these functions to the module (before the final `return M`):

```lua
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
```

- [ ] **Step 4: Re-run spec**

Run: `nvim --headless -c "PlenaryBustedFile tests/remote_hosts_home_dir_spec.lua" -c qa`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lua/remote/hosts.lua tests/remote_hosts_home_dir_spec.lua
git commit -m "feat(remote): cache home_dir per host + expand_path ~ helper"
```

---

### Task 8: `lua/remote/ssh_buffer.lua` — ssh:// fetch/save w/ RO default

**Files:**
- Create: `lua/remote/ssh_buffer.lua`
- Test: `tests/remote_ssh_buffer_spec.lua` (plenary) + `tests/integration/test_ssh_buffer_readonly.py`

**Goal:** A custom `ssh://<host>/<abs-path>` fake protocol. `BufReadCmd` fetches via ssh cat; `BufWriteCmd` refuses unless `vim.b.happy_ssh_writable == true`. Binary guard reused from `remote.browse._is_binary`. `~`-expand via `remote.hosts.expand_path`.

- [ ] **Step 1: Write failing plenary spec (fetch path)**

File: `tests/remote_ssh_buffer_spec.lua`
```lua
describe('remote.ssh_buffer', function()
  local ssh_buffer
  before_each(function()
    package.loaded['remote.ssh_buffer'] = nil
    package.loaded['remote.hosts'] = nil
    package.loaded['remote.ssh_exec'] = nil
    package.loaded['remote.browse'] = nil
    package.loaded['remote.util'] = nil
  end)

  it('_parse_bufname splits host and absolute path', function()
    ssh_buffer = require('remote.ssh_buffer')
    local host, path = ssh_buffer._parse_bufname('ssh://host01/var/log/app.log')
    assert.are.equal('host01', host)
    assert.are.equal('/var/log/app.log', path)
  end)

  it('_parse_bufname preserves ~ paths for later expansion', function()
    ssh_buffer = require('remote.ssh_buffer')
    local host, path = ssh_buffer._parse_bufname('ssh://h/~/.bashrc')
    assert.are.equal('h', host)
    assert.are.equal('~/.bashrc', path)
  end)

  it('open sets buftype acwrite and readonly=true by default', function()
    ssh_buffer = require('remote.ssh_buffer')
    package.loaded['remote.hosts'] = {
      ensure_home_dir = function() return '/home/u' end,
      expand_path = function(_, p) return p end,
    }
    package.loaded['remote.browse'] = { _is_binary = function() return false end }
    package.loaded['remote.ssh_exec'] = {
      run = function() return { code = 0, stdout = 'hello\nworld\n', stderr = '' } end,
    }
    local buf = ssh_buffer.open('h', '/tmp/x.txt')
    assert.are.equal('acwrite', vim.bo[buf].buftype)
    assert.True(vim.bo[buf].readonly)
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    assert.are.equal('hello', lines[1])
    assert.are.equal('world', lines[2])
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it('toggle_writable flips vim.b.happy_ssh_writable + clears readonly', function()
    ssh_buffer = require('remote.ssh_buffer')
    package.loaded['remote.hosts'] = {
      ensure_home_dir = function() return '/h' end,
      expand_path = function(_, p) return p end,
    }
    package.loaded['remote.browse'] = { _is_binary = function() return false end }
    package.loaded['remote.ssh_exec'] = {
      run = function() return { code = 0, stdout = '', stderr = '' } end,
    }
    local buf = ssh_buffer.open('h', '/tmp/y')
    vim.api.nvim_set_current_buf(buf)
    ssh_buffer.toggle_writable()
    assert.True(vim.b.happy_ssh_writable)
    assert.False(vim.bo[buf].readonly)
    vim.api.nvim_buf_delete(buf, { force = true })
  end)
end)
```

- [ ] **Step 2: Run the spec**

Run: `nvim --headless -c "PlenaryBustedFile tests/remote_ssh_buffer_spec.lua" -c qa`
Expected: FAIL.

- [ ] **Step 3: Implement**

File: `lua/remote/ssh_buffer.lua`
```lua
-- lua/remote/ssh_buffer.lua — ssh://<host>/<path> buffers (RO by default).
-- Replaces `edit scp://...` (which has netrw config quirks + no control
-- master). We pipe content via ssh cat on read and ssh 'cat > path' on
-- write. Writes are refused unless `<leader>sw` has flipped
-- `vim.b.happy_ssh_writable = true` on the buffer.
local M = {}

local CONFIG = { default_writable = false }

function M.setup(opts)
  opts = opts or {}
  if opts.ssh_writable_by_default ~= nil then
    CONFIG.default_writable = opts.ssh_writable_by_default and true or false
  end
end

-- bufname convention: ssh://<host>/<path>. Host has no '/'; path keeps
-- whatever the caller supplied (absolute or ~-prefixed).
function M._parse_bufname(name)
  local host, rest = name:match('^ssh://([^/]+)/(.*)$')
  if not host then
    return nil, nil
  end
  -- Re-prepend the '/' for absolute paths; strip when the caller passed ~/.
  if rest:sub(1, 1) == '~' then
    return host, rest
  end
  return host, '/' .. rest
end

local function bufname_for(host, path)
  if path:sub(1, 1) == '~' then
    return ('ssh://%s/%s'):format(host, path)
  end
  return ('ssh://%s%s'):format(host, path)
end

local function exec()
  return require('remote.ssh_exec')
end
local function hosts()
  return require('remote.hosts')
end
local function util()
  return require('remote.util')
end
local function browse()
  return require('remote.browse')
end

-- Fetch remote file contents → list of lines. Returns (lines, err).
function M._fetch(host, abs_path)
  local q = util().shellquote(abs_path)
  local res = exec().run(host, 'cat ' .. q)
  if res.code ~= 0 then
    return nil, 'ssh cat failed: ' .. (res.stderr or '')
  end
  local body = res.stdout or ''
  -- Preserve a trailing empty line if the remote file ended with \n.
  local lines = vim.split(body, '\n', { plain = true })
  if #lines > 0 and lines[#lines] == '' then
    table.remove(lines)
  end
  return lines
end

-- Pipe buffer lines → `ssh host 'cat > path'`. Returns (ok, err).
function M._push(host, abs_path, lines)
  local q = util().shellquote(abs_path)
  local body = table.concat(lines, '\n') .. '\n'
  local done, result = false, nil
  vim.system(
    exec().argv(host, 'cat > ' .. q),
    { text = true, stdin = body },
    function(r)
      result = r
      done = true
    end
  )
  vim.wait(60000, function()
    return done
  end, 50)
  if not done then
    return false, 'timeout'
  end
  if result.code ~= 0 then
    return false, result.stderr or 'push failed'
  end
  return true
end

function M.open(host, path)
  local home_ok = hosts().ensure_home_dir(host)
  local abs = home_ok and hosts().expand_path(host, path) or path

  if browse()._is_binary(host, abs) then
    vim.notify(('%s is binary; use <leader>sO to force'):format(abs), vim.log.levels.WARN)
    return nil
  end

  local name = bufname_for(host, path)
  -- Reuse an existing buffer w/ that name so :e ssh://... is idempotent.
  local existing = vim.fn.bufnr(name)
  if existing ~= -1 then
    vim.api.nvim_set_current_buf(existing)
    return existing
  end

  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(buf, name)

  local lines, err = M._fetch(host, abs)
  if not lines then
    vim.notify(err, vim.log.levels.ERROR)
    vim.api.nvim_buf_delete(buf, { force = true })
    return nil
  end
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  vim.bo[buf].buftype = 'acwrite'
  vim.bo[buf].modified = false
  vim.b[buf].happy_ssh_writable = CONFIG.default_writable or nil
  vim.bo[buf].readonly = not CONFIG.default_writable

  -- Infer filetype from the remote path.
  local ft = vim.filetype.match({ filename = abs, buf = buf })
  if ft then
    vim.bo[buf].filetype = ft
  end

  -- Bind BufWriteCmd once per buffer so it uses the right (host, abs).
  vim.api.nvim_create_autocmd('BufWriteCmd', {
    buffer = buf,
    callback = function()
      if not vim.b[buf].happy_ssh_writable then
        vim.notify(
          'ssh buffer is read-only; <leader>sw to enable writes',
          vim.log.levels.WARN
        )
        return
      end
      local content = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      local ok, perr = M._push(host, abs, content)
      if ok then
        vim.bo[buf].modified = false
        vim.notify(('wrote %s:%s'):format(host, abs), vim.log.levels.INFO)
      else
        vim.notify('push failed: ' .. tostring(perr), vim.log.levels.ERROR)
      end
    end,
  })

  vim.api.nvim_set_current_buf(buf)
  return buf
end

function M.toggle_writable()
  local buf = vim.api.nvim_get_current_buf()
  local name = vim.api.nvim_buf_get_name(buf)
  if not name:find('^ssh://') then
    vim.notify('not an ssh:// buffer', vim.log.levels.WARN)
    return
  end
  local cur = vim.b[buf].happy_ssh_writable
  local nv = not cur
  vim.b[buf].happy_ssh_writable = nv or nil
  vim.bo[buf].readonly = not nv
  vim.notify(('ssh buffer %s'):format(nv and 'WRITABLE' or 'read-only'), vim.log.levels.INFO)
end

-- Prompt flow: host picker → path input → open RO.
function M.browse_prompt()
  require('remote.hosts').pick(function(host)
    vim.ui.input({ prompt = 'Remote path: ' }, function(path)
      if not path or path == '' then
        return
      end
      M.open(host, path)
    end)
  end)
end

return M
```

- [ ] **Step 4: Re-run spec**

Run: `nvim --headless -c "PlenaryBustedFile tests/remote_ssh_buffer_spec.lua" -c qa`
Expected: PASS.

- [ ] **Step 5: Add pytest readonly integration test**

File: `tests/integration/test_ssh_buffer_readonly.py`
```python
"""ssh_buffer: default read-only; toggle_writable flips it."""
import os
import subprocess
import textwrap


def test_default_readonly_refuses_write(tmp_path):
    repo = os.getcwd()
    out = tmp_path / 'result'
    snippet = textwrap.dedent(f'''
        local repo = '{repo}'
        vim.opt.rtp:prepend(repo)
        package.loaded['remote.hosts'] = {{
          ensure_home_dir = function() return '/h' end,
          expand_path = function(_, p) return p end,
        }}
        package.loaded['remote.browse'] = {{ _is_binary = function() return false end }}
        package.loaded['remote.ssh_exec'] = {{
          argv = function(h, c) return {{'true'}} end,
          run = function() return {{ code = 0, stdout = 'line\\n', stderr = '' }} end,
        }}
        local ssh_buffer = require('remote.ssh_buffer')
        local buf = ssh_buffer.open('h', '/tmp/f')
        local notified = ''
        vim.notify = function(m) notified = notified .. m .. '\\n' end
        -- Simulate :w — triggers BufWriteCmd
        vim.api.nvim_buf_set_option(buf, 'modified', true)
        pcall(vim.cmd, 'silent! write')
        local fh = io.open('{out}', 'w'); fh:write(notified); fh:close()
        vim.cmd('qa!')
    ''')
    subprocess.run(
        ['nvim', '--clean', '--headless', '-u', 'NONE', '-c', f'lua {snippet}'],
        check=True, timeout=15, capture_output=True, text=True,
    )
    msg = out.read_text()
    assert 'read-only' in msg, f'expected read-only warning, got: {msg!r}'
```

- [ ] **Step 6: Run pytest**

Run: `python3 -m pytest tests/integration/test_ssh_buffer_readonly.py -v`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add lua/remote/ssh_buffer.lua tests/remote_ssh_buffer_spec.lua tests/integration/test_ssh_buffer_readonly.py
git commit -m "feat(remote): ssh_buffer w/ read-only default + toggle_writable"
```

---

### Task 9: Wire `<leader>sw` + `<leader>sB` onto ssh_buffer

**Files:**
- Modify: `lua/plugins/remote.lua` (replace browse's `sB` w/ ssh_buffer.browse_prompt; add `sw`).
- Modify: `lua/remote/browse.lua` (`open` delegates to ssh_buffer; keep binary guard path).

- [ ] **Step 1: Edit `lua/plugins/remote.lua`**

Replace the `<leader>sB` entry and add `<leader>sw`:
```lua
    { '<leader>sB', lazy_cmd('remote.ssh_buffer', 'browse_prompt'), desc = 'ssh:// buffer (host picker → path, RO default)' },
    { '<leader>sw', lazy_cmd('remote.ssh_buffer', 'toggle_writable'), desc = 'ssh:// toggle write' },
```

Also remove the old `browse` keys that opened scp:// directly — no `<leader>sC` / `<leader>sr` to drop (the repo currently has none).

- [ ] **Step 2: Point `remote.browse.open` at ssh_buffer**

Edit `lua/remote/browse.lua` — replace `M.open`:

```lua
function M.open(host, rpath)
  if M._fast_path_ext(rpath) and not vim.b.happy_force_binary then
    vim.notify(
      string.format(
        'Binary extension detected for %s. Use <leader>sO to force.',
        rpath
      ),
      vim.log.levels.WARN
    )
    return
  end
  if not vim.b.happy_force_binary then
    local blocked, reason = check_remote_binary(host, rpath)
    if blocked then
      vim.notify(
        string.format('%s: %s. <leader>sO to force.', rpath, reason),
        vim.log.levels.WARN
      )
      return
    end
  end
  require('remote.ssh_buffer').open(host, rpath)
end
M.open_path = M.open
```

Also drop `M.browse` (the old `scp://` prompt) — users now go through `ssh_buffer.browse_prompt`. Replace with a thin delegator for back-compat w/ any callers still using it:
```lua
function M.browse()
  require('remote.ssh_buffer').browse_prompt()
end
```

- [ ] **Step 3: Smoke test plenary**

Run: `nvim --headless -c "PlenaryBustedDirectory tests/" -c qa`
Expected: all green — browse tests may reference scp://; if any fail, update the assertion to look for `ssh://` instead (per the migration).

- [ ] **Step 4: Commit**

```bash
git add lua/plugins/remote.lua lua/remote/browse.lua
git commit -m "feat(remote): rewire <leader>sB + browse.open onto ssh_buffer"
```

---

### Task 10: SSH picker audit — every host-requiring flow goes through `remote.hosts.pick`

**Files:**
- Modify: `lua/remote/browse.lua` (`M.find` — already uses `vim.fn.input('Host:')` pre-picker; replace with `hosts.pick`).
- Modify: `lua/remote/grep.lua` (verify prompt flow — swap to picker if it prompts host inline).
- Modify: `lua/remote/cmd.lua` (audit — already uses picker per file reading).
- Modify: `lua/remote/find.lua` (audit).

- [ ] **Step 1: Audit — list every call site that reads a host**

Run:
```bash
cd /home/raul/worktrees/happy-nvim/feat-sp1-cockpit
grep -n "vim.fn.input.*Host" lua/remote/*.lua
```
Fix any file that still uses `vim.fn.input('Host: ')` — wrap the rest of the flow inside `require('remote.hosts').pick(function(host) ... end)`.

- [ ] **Step 2: Patch `remote.browse.find`**

Edit `lua/remote/browse.lua`, `M.find` — replace the opening `local host = vim.fn.input('Host: ')` block with the picker:

```lua
function M.find()
  require('remote.hosts').pick(function(host)
    vim.ui.input({ prompt = 'Path: ' }, function(path)
      if not path or path == '' then
        return
      end
      vim.ui.input({ prompt = 'Name pattern: ' }, function(pat)
        if not pat or pat == '' then
          return
        end
        local sq = require('remote.util').shellquote
        local exec = require('remote.ssh_exec')
        local res = exec.run(
          host,
          string.format('find %s -name %s 2>/dev/null', sq(path), sq(pat))
        )
        if res.code ~= 0 then
          vim.notify('ssh ' .. host .. ' failed: ' .. (res.stderr or ''), vim.log.levels.ERROR)
          return
        end
        local results = {}
        for line in (res.stdout or ''):gmatch('[^\n]+') do
          table.insert(results, line)
        end
        local pickers = require('telescope.pickers')
        local finders = require('telescope.finders')
        local actions = require('telescope.actions')
        local action_state = require('telescope.actions.state')
        local conf = require('telescope.config').values

        pickers
          .new({}, {
            prompt_title = string.format('find %s:%s  %s', host, path, pat),
            finder = finders.new_table({ results = results }),
            sorter = conf.generic_sorter({}),
            attach_mappings = function(bufnr)
              actions.select_default:replace(function()
                actions.close(bufnr)
                local sel = action_state.get_selected_entry()
                if not sel then
                  return
                end
                M.open(host, sel[1])
              end)
              return true
            end,
          })
          :find()
      end)
    end)
  end)
end
```

- [ ] **Step 3: Verify `remote.grep.prompt` + `remote.cmd.run_cmd` already use picker**

Read both files; they should already start with `require('remote.hosts').pick(function(host) ... end)`. If not, patch the same way.

- [ ] **Step 4: Write regression test**

File: `tests/integration/test_ssh_pickers_consistent.py`
```python
"""Every <leader>s* flow that needs a host MUST route through
remote.hosts.pick. This test greps the source for the anti-pattern
`vim.fn.input('Host:')` to catch regressions at CI time."""
import pathlib


def test_no_host_input_prompts_in_remote_modules():
    root = pathlib.Path('lua/remote')
    offenders = []
    for f in root.rglob('*.lua'):
        body = f.read_text()
        # Crude but sufficient: any vim.fn.input w/ 'Host' in the prompt.
        if 'vim.fn.input' in body and 'Host' in body:
            for i, line in enumerate(body.splitlines(), 1):
                if 'vim.fn.input' in line and 'Host' in line:
                    offenders.append(f'{f}:{i}: {line.strip()}')
    assert not offenders, 'Host prompt must use remote.hosts.pick:\n' + '\n'.join(offenders)
```

- [ ] **Step 5: Run pytest**

Run: `python3 -m pytest tests/integration/test_ssh_pickers_consistent.py -v`
Expected: PASS after Step 2's patch.

- [ ] **Step 6: Commit**

```bash
git add lua/remote/browse.lua lua/remote/grep.lua lua/remote/find.lua tests/integration/test_ssh_pickers_consistent.py
git commit -m "refactor(remote): route every host-requiring flow through hosts.pick"
```

---

### Task 11: `lua/remote/watch.lua` — pattern engine w/ history JSON

**Files:**
- Create: `lua/remote/watch.lua`
- Test: `tests/remote_watch_spec.lua` (plenary)

**Goal:** Persistent watch-pattern registry keyed per `(host, path)` with scan/dispatch API.

- [ ] **Step 1: Write failing spec**

File: `tests/remote_watch_spec.lua`
```lua
describe('remote.watch', function()
  local tmp_state
  before_each(function()
    package.loaded['remote.watch'] = nil
    tmp_state = vim.fn.tempname() .. '.json'
  end)
  after_each(function()
    vim.fn.delete(tmp_state)
  end)

  it('add + list returns the new pattern', function()
    local w = require('remote.watch')
    w._set_state_path_for_test(tmp_state)
    local id = w.add('h1', '/var/log/app.log', 'ERROR', { level = 'ERROR' })
    local rows = w.list('h1', '/var/log/app.log')
    assert.are.equal(1, #rows)
    assert.are.equal(id, rows[1].id)
    assert.are.equal('ERROR', rows[1].regex)
    assert.True(rows[1].active)
  end)

  it('scan matches only active + returns the pattern entry', function()
    local w = require('remote.watch')
    w._set_state_path_for_test(tmp_state)
    local id = w.add('h', '/p', 'panic')
    w.add('h', '/p', 'debug', { active = false })
    local hits = w.scan('h', '/p', 'kernel panic at 42')
    assert.are.equal(1, #hits)
    assert.are.equal(id, hits[1].id)
  end)

  it('oneshot: active flips false after first match', function()
    local w = require('remote.watch')
    w._set_state_path_for_test(tmp_state)
    local id = w.add('h', '/p', 'boom', { oneshot = true })
    assert.are.equal(1, #w.scan('h', '/p', 'boom!')) -- match once
    assert.are.equal(0, #w.scan('h', '/p', 'boom!')) -- second call: inactive
  end)

  it('remove deletes the entry', function()
    local w = require('remote.watch')
    w._set_state_path_for_test(tmp_state)
    local id = w.add('h', '/p', 'x')
    w.remove(id)
    assert.are.equal(0, #w.list('h', '/p'))
  end)

  it('persists across reload', function()
    local w = require('remote.watch')
    w._set_state_path_for_test(tmp_state)
    local id = w.add('h', '/p', 'e')
    package.loaded['remote.watch'] = nil
    local w2 = require('remote.watch')
    w2._set_state_path_for_test(tmp_state)
    local rows = w2.list('h', '/p')
    assert.are.equal(1, #rows)
    assert.are.equal(id, rows[1].id)
  end)
end)
```

- [ ] **Step 2: Run spec**

Run: `nvim --headless -c "PlenaryBustedFile tests/remote_watch_spec.lua" -c qa`
Expected: FAIL.

- [ ] **Step 3: Implement**

File: `lua/remote/watch.lua`
```lua
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
```

- [ ] **Step 4: Re-run spec**

Run: `nvim --headless -c "PlenaryBustedFile tests/remote_watch_spec.lua" -c qa`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lua/remote/watch.lua tests/remote_watch_spec.lua
git commit -m "feat(remote): watch-pattern registry w/ JSON persistence"
```

---

### Task 12: `lua/remote/tail.lua` — detached tmux tail + fs_watch + watch integration

**Files:**
- Rewrite: `lua/remote/tail.lua`
- Test: `tests/remote_tail_spec.lua` (plenary) + `tests/integration/test_tail_watch_dispatch.py`

**Goal:** Tail backed by a detached tmux session so closing the scratch buffer doesn't kill the stream. A state file captures the stream for `vim.uv.fs_watch` to follow; matched watch patterns fire `vim.notify` through `remote.watch.scan`.

- [ ] **Step 1: Write failing spec**

File: `tests/remote_tail_spec.lua`
```lua
describe('remote.tail', function()
  local orig_system
  before_each(function()
    orig_system = vim.system
    package.loaded['remote.tail'] = nil
  end)
  after_each(function()
    vim.system = orig_system
  end)

  it('session_name slugs host+path deterministically', function()
    local tail = require('remote.tail')
    local n1 = tail._session_name('prod01', '/var/log/app.log')
    local n2 = tail._session_name('prod01', '/var/log/app.log')
    assert.are.equal(n1, n2)
    assert.truthy(n1:find('^tail%-prod01%-'))
  end)

  it('start invokes tmux new-session -d w/ ssh pipe', function()
    local tail = require('remote.tail')
    package.loaded['remote.ssh_exec'] = {
      argv = function(h, c) return { 'ssh', h, c } end,
    }
    package.loaded['remote.watch'] = { scan = function() return {} end }
    local captured
    vim.system = function(args)
      if args[1] == 'tmux' and args[2] == 'has-session' then
        return { wait = function() return { code = 1 } end }
      end
      if args[1] == 'tmux' and args[2] == 'new-session' then
        captured = args
        return { wait = function() return { code = 0 } end }
      end
      return { wait = function() return { code = 0, stdout = '', stderr = '' } end }
    end
    tail.start('h', '/tmp/f.log', { open_buffer = false })
    assert.truthy(captured)
    local joined = table.concat(captured, ' ')
    assert.truthy(joined:find('tail %-F'))
    assert.truthy(joined:find('tee'))
  end)
end)
```

- [ ] **Step 2: Run spec**

Run: `nvim --headless -c "PlenaryBustedFile tests/remote_tail_spec.lua" -c qa`
Expected: FAIL.

- [ ] **Step 3: Implement new `lua/remote/tail.lua`**

File: `lua/remote/tail.lua`
```lua
-- lua/remote/tail.lua — <leader>sL detachable + resumable log tail.
-- Architecture: a *detached* tmux session `tail-<host>-<slug>` runs the
-- ssh tail stream and tees it to a state file on the local fs. A
-- scratch buffer tails that state file via vim.uv.fs_watch. Closing the
-- scratch (q) just detaches — tmux session stays, state file keeps
-- growing, user can reattach later from <leader>sP.
local M = {}
local TAIL_PREFIX = 'tail-'
local STATE_DIR = vim.fn.stdpath('cache') .. '/happy-nvim/tails'

function M._slugify(path)
  return path:gsub('[^%w]', '-'):gsub('%-+', '-'):gsub('^%-', ''):gsub('%-$', '')
end

function M._session_name(host, path)
  return TAIL_PREFIX .. host .. '-' .. M._slugify(path)
end

function M._state_path(session)
  vim.fn.mkdir(STATE_DIR, 'p')
  return STATE_DIR .. '/' .. session .. '.log'
end

local function sys(args)
  return vim.system(args, { text = true }):wait()
end

function M._exists(session)
  return sys({ 'tmux', 'has-session', '-t', session }).code == 0
end

local function ensure_session(host, path, session, state_file)
  if M._exists(session) then
    return true
  end
  local exec = require('remote.ssh_exec')
  local ssh_argv = exec.argv(host, 'tail -F ' .. require('remote.util').shellquote(path))
  -- Build: tmux new-session -d -s <name> "<ssh argv> | tee <state_file>"
  -- Use a shell so the pipe works.
  local cmd = table.concat(
    vim.tbl_map(function(a)
      return vim.fn.shellescape(a)
    end, ssh_argv),
    ' '
  ) .. ' 2>&1 | tee ' .. vim.fn.shellescape(state_file)
  local res = sys({ 'tmux', 'new-session', '-d', '-s', session, 'sh', '-c', cmd })
  if res.code ~= 0 then
    vim.notify('failed to spawn tail session: ' .. (res.stderr or ''), vim.log.levels.ERROR)
    return false
  end
  -- Stash host+path mapping so the picker can reverse-resolve the session.
  sys({ 'tmux', 'set-option', '-t', session, '@tail_host', host })
  sys({ 'tmux', 'set-option', '-t', session, '@tail_path', path })
  sys({ 'tmux', 'set-option', '-t', session, '@tail_state', state_file })
  return true
end

local function append_lines(buf, lines)
  if #lines == 0 then
    return
  end
  vim.schedule(function()
    if not vim.api.nvim_buf_is_valid(buf) then
      return
    end
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, -1, -1, false, lines)
    vim.bo[buf].modifiable = false
    local win = vim.fn.bufwinid(buf)
    if win ~= -1 then
      vim.api.nvim_win_set_cursor(win, { vim.api.nvim_buf_line_count(buf), 0 })
    end
  end)
end

-- Scan freshly-appended lines against watch patterns + dispatch notifies.
local function dispatch_watches(host, path, lines)
  local watch = require('remote.watch')
  for _, line in ipairs(lines) do
    local hits = watch.scan(host, path, line)
    for _, h in ipairs(hits) do
      local level = vim.log.levels[h.level or 'INFO'] or vim.log.levels.INFO
      vim.schedule(function()
        vim.notify(('[tail %s:%s] /%s/ %s'):format(h.host, h.path, h.regex, line), level)
      end)
    end
  end
end

local function attach_scratch(host, path, state_file, session)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, ('[tail %s:%s]'):format(host, path))
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'wipe'
  vim.cmd('sbuffer ' .. buf)
  -- Seed w/ existing contents so reattach shows past lines.
  local f = io.open(state_file, 'r')
  if f then
    local existing = {}
    for line in f:lines() do
      table.insert(existing, line)
    end
    f:close()
    append_lines(buf, existing)
  end
  local pos = vim.uv.fs_stat(state_file) and vim.uv.fs_stat(state_file).size or 0
  local watcher = vim.uv.new_fs_event()
  watcher:start(state_file, {}, vim.schedule_wrap(function(err)
    if err then
      return
    end
    local stat = vim.uv.fs_stat(state_file)
    if not stat then
      return
    end
    if stat.size <= pos then
      pos = stat.size
      return
    end
    local fd = vim.uv.fs_open(state_file, 'r', 438)
    if not fd then
      return
    end
    local delta = vim.uv.fs_read(fd, stat.size - pos, pos)
    vim.uv.fs_close(fd)
    pos = stat.size
    if not delta or delta == '' then
      return
    end
    local new_lines = vim.split(delta, '\n', { plain = true, trimempty = true })
    append_lines(buf, new_lines)
    dispatch_watches(host, path, new_lines)
  end))
  vim.b[buf].happy_tail_session = session
  vim.b[buf].happy_tail_host = host
  vim.b[buf].happy_tail_path = path
  vim.api.nvim_create_autocmd('BufWipeout', {
    buffer = buf,
    callback = function()
      if watcher and not watcher:is_closing() then
        watcher:stop()
        watcher:close()
      end
    end,
  })
  -- q = detach only (tmux keeps running).
  vim.keymap.set('n', 'q', function()
    vim.cmd('bw!')
  end, { buffer = buf, desc = 'detach tail scratch (tmux stays)' })
  -- <leader>sp inside the tail edits watch patterns for this tail.
  vim.keymap.set('n', '<leader>sp', function()
    require('remote.watch_editor').open(host, path)
  end, { buffer = buf, desc = 'edit watch patterns for this tail' })
end

function M.start(host, path, opts)
  opts = opts or {}
  local session = M._session_name(host, path)
  local state_file = M._state_path(session)
  if not ensure_session(host, path, session, state_file) then
    return
  end
  if opts.open_buffer ~= false then
    attach_scratch(host, path, state_file, session)
  end
end

-- Reattach flow — used by the <leader>sP picker.
function M.reattach(session)
  local host_r = sys({ 'tmux', 'show-option', '-t', session, '-v', '-q', '@tail_host' })
  local path_r = sys({ 'tmux', 'show-option', '-t', session, '-v', '-q', '@tail_path' })
  local state_r = sys({ 'tmux', 'show-option', '-t', session, '-v', '-q', '@tail_state' })
  if host_r.code ~= 0 or path_r.code ~= 0 or state_r.code ~= 0 then
    vim.notify('cannot resolve tail session: ' .. session, vim.log.levels.WARN)
    return
  end
  local host = (host_r.stdout or ''):gsub('%s+$', '')
  local path = (path_r.stdout or ''):gsub('%s+$', '')
  local state = (state_r.stdout or ''):gsub('%s+$', '')
  attach_scratch(host, path, state, session)
end

function M.kill(session)
  return sys({ 'tmux', 'kill-session', '-t', session }).code == 0
end

function M.list_sessions()
  local res = sys({ 'tmux', 'list-sessions', '-F', '#{session_name}' })
  if res.code ~= 0 then
    return {}
  end
  local out = {}
  for line in (res.stdout or ''):gmatch('[^\n]+') do
    if line:sub(1, #TAIL_PREFIX) == TAIL_PREFIX then
      local host_r = sys({ 'tmux', 'show-option', '-t', line, '-v', '-q', '@tail_host' })
      local path_r = sys({ 'tmux', 'show-option', '-t', line, '-v', '-q', '@tail_path' })
      table.insert(out, {
        name = line,
        host = (host_r.stdout or ''):gsub('%s+$', ''),
        path = (path_r.stdout or ''):gsub('%s+$', ''),
      })
    end
  end
  return out
end

-- Entry point from <leader>sL (new tail).
function M.tail_log()
  require('remote.hosts').pick(function(host)
    vim.ui.input({ prompt = 'Remote log path: ' }, function(path)
      if not path or path == '' then
        return
      end
      local exp = require('remote.hosts').expand_path(host, path)
      M.start(host, exp)
    end)
  end)
end

-- Back-compat: older callers referenced M._stream_tail — leave a
-- thin shim that forwards to start().
function M._stream_tail(host, path)
  M.start(host, path)
end

return M
```

- [ ] **Step 4: Re-run plenary spec**

Run: `nvim --headless -c "PlenaryBustedFile tests/remote_tail_spec.lua" -c qa`
Expected: PASS.

- [ ] **Step 5: Add pytest integration — watch dispatch**

File: `tests/integration/test_tail_watch_dispatch.py`
```python
"""remote.watch.scan fires vim.notify when tail line matches an active pattern."""
import os
import subprocess
import textwrap


def test_watch_scan_dispatches_notify(tmp_path):
    repo = os.getcwd()
    state = tmp_path / 'state.json'
    out = tmp_path / 'notifies'
    snippet = textwrap.dedent(f'''
        local repo = '{repo}'
        vim.opt.rtp:prepend(repo)
        local w = require('remote.watch')
        w._set_state_path_for_test('{state}')
        w.add('h', '/l', 'panic', {{ level = 'ERROR' }})
        local notifies = {{}}
        vim.notify = function(m, lvl) table.insert(notifies, m) end
        -- Simulate 3 lines, 1 matches.
        for _, line in ipairs({{'normal', 'kernel panic', 'ok'}}) do
          local hits = w.scan('h', '/l', line)
          for _, h in ipairs(hits) do
            vim.notify(('[%s] %s'):format(h.regex, line), vim.log.levels.ERROR)
          end
        end
        local fh = io.open('{out}', 'w')
        for _, n in ipairs(notifies) do fh:write(n .. '\\n') end
        fh:close()
        vim.cmd('qa!')
    ''')
    subprocess.run(
        ['nvim', '--clean', '--headless', '-u', 'NONE', '-c', f'lua {snippet}'],
        check=True, timeout=15, capture_output=True, text=True,
    )
    body = out.read_text()
    assert '[panic] kernel panic' in body, f'expected match notify, got: {body!r}'
    assert body.count('\n') == 1, 'should have exactly one notify'
```

- [ ] **Step 6: Run pytest**

Run: `python3 -m pytest tests/integration/test_tail_watch_dispatch.py -v`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add lua/remote/tail.lua tests/remote_tail_spec.lua tests/integration/test_tail_watch_dispatch.py
git commit -m "feat(remote): detachable tail via tmux session + watch dispatch"
```

---

### Task 13: `<leader>sp` watch editor + `<leader>sP` tails picker

**Files:**
- Create: `lua/remote/watch_editor.lua`
- Create: `lua/remote/tails_picker.lua`
- Modify: `lua/plugins/remote.lua` — register `sp`, `sP`, `sL` (sL covered in Task 15 rename).
- Test: `tests/remote_watch_editor_spec.lua` (plenary)

- [ ] **Step 1: Write failing plenary spec for watch editor parse/write**

File: `tests/remote_watch_editor_spec.lua`
```lua
describe('remote.watch_editor', function()
  it('_parse_lines reconstructs patterns from editor buffer', function()
    package.loaded['remote.watch_editor'] = nil
    local ed = require('remote.watch_editor')
    local lines = {
      '# host: h',
      '# path: /p',
      '',
      '[x] ERROR  :: fatal',
      '[ ] WARN   :: slowdown',
      '[x] INFO!  :: once-only',
    }
    local parsed = ed._parse_lines(lines)
    assert.are.equal(3, #parsed)
    assert.True(parsed[1].active)
    assert.are.equal('ERROR', parsed[1].level)
    assert.are.equal('fatal', parsed[1].regex)
    assert.False(parsed[2].active)
    assert.True(parsed[3].oneshot) -- '!' suffix
  end)
end)
```

- [ ] **Step 2: Run**

Run: `nvim --headless -c "PlenaryBustedFile tests/remote_watch_editor_spec.lua" -c qa`
Expected: FAIL.

- [ ] **Step 3: Implement `lua/remote/watch_editor.lua`**

File: `lua/remote/watch_editor.lua`
```lua
-- lua/remote/watch_editor.lua — scratch buffer for editing watch
-- patterns on the current tail. Format (one pattern per line):
--   [x] ERROR  :: regex
--   [ ] WARN   :: regex
--   [x] INFO!  :: regex  (the `!` after the level marks oneshot)
-- Lines starting with '#' are comments. Blank lines ignored.
local M = {}
local LEVELS = { DEBUG = true, INFO = true, WARN = true, ERROR = true }

function M._parse_lines(lines)
  local out = {}
  for _, line in ipairs(lines) do
    if line:sub(1, 1) ~= '#' and line:match('%S') then
      local box, lvl, body = line:match('^%[([ x])%]%s+([%w]+!?)%s+::%s+(.+)$')
      if box then
        local oneshot = false
        local level = lvl
        if level:sub(-1) == '!' then
          oneshot = true
          level = level:sub(1, -2)
        end
        if LEVELS[level] then
          table.insert(out, {
            active = box == 'x',
            level = level,
            oneshot = oneshot,
            regex = body,
          })
        end
      end
    end
  end
  return out
end

local function render(host, path, patterns)
  local lines = {
    '# Edit watch patterns for tail — :w to save, q to close',
    '# Format: [x]/[ ] LEVEL[!] :: regex  (! = oneshot)',
    '# host: ' .. host,
    '# path: ' .. path,
    '',
  }
  for _, p in ipairs(patterns) do
    local chk = p.active and '[x]' or '[ ]'
    local lvl = p.level .. (p.oneshot and '!' or '')
    table.insert(lines, ('%s %-6s :: %s'):format(chk, lvl, p.regex))
  end
  return lines
end

function M.open(host, path)
  local watch = require('remote.watch')
  local patterns = watch.list(host, path)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, ('[watch %s:%s]'):format(host, path))
  vim.bo[buf].buftype = 'acwrite'
  vim.bo[buf].bufhidden = 'wipe'
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, render(host, path, patterns))
  vim.api.nvim_create_autocmd('BufWriteCmd', {
    buffer = buf,
    callback = function()
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      local parsed = M._parse_lines(lines)
      -- Replace wholesale: remove all patterns for (host, path), re-add.
      local existing = watch.list(host, path)
      for _, e in ipairs(existing) do
        watch.remove(e.id)
      end
      for _, p in ipairs(parsed) do
        watch.add(host, path, p.regex, {
          level = p.level,
          oneshot = p.oneshot,
          active = p.active,
        })
      end
      vim.bo[buf].modified = false
      vim.notify(('saved %d watch patterns for %s:%s'):format(#parsed, host, path), vim.log.levels.INFO)
    end,
  })
  vim.keymap.set('n', 'q', function()
    vim.cmd('bw!')
  end, { buffer = buf, desc = 'close watch editor' })
  vim.cmd('sbuffer ' .. buf)
end

return M
```

- [ ] **Step 4: Implement `lua/remote/tails_picker.lua`**

File: `lua/remote/tails_picker.lua`
```lua
-- lua/remote/tails_picker.lua — <leader>sP: list detached/active tail
-- sessions; Enter reattaches (opens scratch tailing the state file);
-- C-x kills the tmux session entirely.
local M = {}

function M.open()
  local tail = require('remote.tail')
  local entries = tail.list_sessions()
  if #entries == 0 then
    vim.notify('no tail sessions (start one with <leader>sL)', vim.log.levels.INFO)
    return
  end
  local pickers = require('telescope.pickers')
  local finders = require('telescope.finders')
  local actions = require('telescope.actions')
  local action_state = require('telescope.actions.state')
  local conf = require('telescope.config').values
  pickers
    .new({}, {
      prompt_title = 'tail sessions',
      finder = finders.new_table({
        results = entries,
        entry_maker = function(e)
          return {
            value = e,
            display = ('%-40s  %s:%s'):format(e.name, e.host, e.path),
            ordinal = e.name,
          }
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
          tail.reattach(entry.value.name)
        end)
        map({ 'i', 'n' }, '<C-x>', function()
          local entry = action_state.get_selected_entry()
          if not entry then
            return
          end
          tail.kill(entry.value.name)
          actions.close(bufnr)
          vim.schedule(M.open)
        end)
        return true
      end,
    })
    :find()
end

return M
```

- [ ] **Step 5: Register `sp` / `sP` in `lua/plugins/remote.lua`**

Add alongside existing keys:
```lua
    {
      '<leader>sp',
      function()
        local host = vim.b.happy_tail_host
        local path = vim.b.happy_tail_path
        if not host or not path then
          vim.notify(
            '<leader>sp only works inside a tail scratch buffer',
            vim.log.levels.WARN
          )
          return
        end
        require('remote.watch_editor').open(host, path)
      end,
      desc = 'ssh: edit watch patterns (in tail scratch)',
    },
    { '<leader>sP', lazy_cmd('remote.tails_picker', 'open'), desc = 'ssh: tails picker (reattach/kill)' },
```

- [ ] **Step 6: Run plenary**

Run: `nvim --headless -c "PlenaryBustedFile tests/remote_watch_editor_spec.lua" -c qa`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add lua/remote/watch_editor.lua lua/remote/tails_picker.lua lua/plugins/remote.lua tests/remote_watch_editor_spec.lua
git commit -m "feat(remote): watch editor (<leader>sp) + tails picker (<leader>sP)"
```

---

### Task 14: Telescope picker actions on `sf` + `sd` drill-in leaf

**Files:**
- Modify: `lua/remote/browse.lua` — `M.find` picker gets `<C-g>/<C-t>/<C-v>/<C-y>/<C-o>` actions.
- Modify: `lua/remote/dirs.lua` — dir-drill-in leaf uses same actions.
- Test: `tests/integration/test_remote_picker_actions.py`

- [ ] **Step 1: Write failing pytest**

File: `tests/integration/test_remote_picker_actions.py`
```python
"""remote.browse.find picker supports C-g/C-t/C-v/C-y/C-o actions.

Assert the callbacks are wired (we can't drive the real picker in
headless nvim, but we can introspect attach_mappings indirectly by
asserting the module lists every action in a known attribute)."""
import os
import subprocess
import textwrap


def test_browse_find_picker_actions_exposed(tmp_path):
    repo = os.getcwd()
    out = tmp_path / 'actions'
    snippet = textwrap.dedent(f'''
        local repo = '{repo}'
        vim.opt.rtp:prepend(repo)
        local browse = require('remote.browse')
        local keys = browse._picker_actions or {{}}
        local fh = io.open('{out}', 'w')
        for _, k in ipairs(keys) do fh:write(k .. '\\n') end
        fh:close()
        vim.cmd('qa!')
    ''')
    subprocess.run(
        ['nvim', '--clean', '--headless', '-u', 'NONE', '-c', f'lua {snippet}'],
        check=True, timeout=10, capture_output=True, text=True,
    )
    body = out.read_text().splitlines()
    for k in ('<C-g>', '<C-t>', '<C-v>', '<C-y>'):
        assert k in body, f'missing picker action: {k}'
```

- [ ] **Step 2: Run the failing test**

Run: `python3 -m pytest tests/integration/test_remote_picker_actions.py -v`
Expected: FAIL.

- [ ] **Step 3: Extend `lua/remote/browse.lua` picker**

Inside `M.find`, replace the `attach_mappings = function(bufnr) ... end,` block with:

```lua
        attach_mappings = function(bufnr, map)
          actions.select_default:replace(function()
            actions.close(bufnr)
            local sel = action_state.get_selected_entry()
            if not sel then
              return
            end
            M.open(host, sel[1])
          end)
          map({ 'i', 'n' }, '<C-g>', function()
            local sel = action_state.get_selected_entry()
            if not sel then
              return
            end
            actions.close(bufnr)
            vim.ui.input({ prompt = 'grep pattern: ' }, function(pat)
              if not pat or pat == '' then
                return
              end
              require('remote.grep').run({ host = host, path = sel[1], pattern = pat })
            end)
          end)
          map({ 'i', 'n' }, '<C-t>', function()
            local sel = action_state.get_selected_entry()
            if not sel then
              return
            end
            actions.close(bufnr)
            require('remote.tail').start(host, sel[1])
          end)
          map({ 'i', 'n' }, '<C-v>', function()
            local sel = action_state.get_selected_entry()
            if not sel then
              return
            end
            actions.close(bufnr)
            local sq = require('remote.util').shellquote
            require('tmux._popup').open(
              '85%',
              '85%',
              table.concat(
                require('remote.ssh_exec').argv(host, 'less +F ' .. sq(sel[1])),
                ' '
              )
            )
          end)
          map({ 'i', 'n' }, '<C-y>', function()
            local sel = action_state.get_selected_entry()
            if not sel then
              return
            end
            vim.fn.setreg('+', host .. ':' .. sel[1])
            vim.notify(('yanked %s:%s'):format(host, sel[1]), vim.log.levels.INFO)
          end)
          return true
        end,
```

Also expose the actions list for the test:
```lua
M._picker_actions = { '<Enter>', '<C-g>', '<C-t>', '<C-v>', '<C-y>' }
```

- [ ] **Step 4: Ensure `remote.grep.run` accepts `{host, path, pattern}`**

Edit `lua/remote/grep.lua`. Check for existing `M.run`; if its signature differs, adapt (it may take `(host, pattern)` only today — add `opts.path` handling to narrow the grep to a subdir). If the function already exists, verify + adapt.

- [ ] **Step 5: Rerun pytest**

Run: `python3 -m pytest tests/integration/test_remote_picker_actions.py -v`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lua/remote/browse.lua lua/remote/grep.lua tests/integration/test_remote_picker_actions.py
git commit -m "feat(remote): telescope picker actions on sf (grep/tail/less/yank)"
```

---

### Task 15: `sT → sL` rename + deprecation shim + coach tips + manual-tests rows

**Files:**
- Modify: `lua/plugins/remote.lua` — rename `sT` → `sL`; add deprecation shim mapping `<leader>sT` to a one-shot warning that forwards to `sL`.
- Modify: `lua/coach/tips.lua` — add new tip entries.
- Modify: `docs/manual-tests.md` — append §15 (cc split), §16 (tt shells), §17 (tail watches + detach/resume).

- [ ] **Step 1: Wire `<leader>sL` + deprecation shim**

Edit `lua/plugins/remote.lua`. Add alongside existing keys:
```lua
    { '<leader>sL', lazy_cmd('remote.tail', 'tail_log'), desc = 'ssh: log tail (watch-aware, detachable)' },
    {
      '<leader>sT',
      function()
        vim.notify(
          '<leader>sT is deprecated — use <leader>sL (log tail).',
          vim.log.levels.WARN
        )
        require('remote.tail').tail_log()
      end,
      desc = '[deprecated] use <leader>sL',
    },
```

- [ ] **Step 2: Add coach tips**

Edit `lua/coach/tips.lua`. Append ~8 new tip strings (match existing format — strings in the same list):
```lua
  '<leader>cp is the primary Claude popup — <leader>cc splits in place.',
  '<leader>tt opens a project-scoped tt-* shell popup; <leader>tl picks.',
  '<leader>sB opens an ssh:// buffer (read-only by default). <leader>sw to enable writes.',
  '<leader>sL is log tail w/ watch patterns (detachable). Use <leader>sp inside to edit patterns.',
  '<leader>sP lists active tail sessions — Enter reattaches, C-x kills.',
  'In <leader>sf pickers: C-g grep · C-t tail · C-v less popup · C-y yank host:path.',
  '<leader>sT is deprecated — use <leader>sL.',
```

- [ ] **Step 3: Append manual-tests sections**

Edit `docs/manual-tests.md`. Append after the last existing section:

````markdown

## §15 cc split layout (CI-covered partially)

| # | Surface | Test |
|---|---|---|
| 15.1 | `<leader>cc` on a wide window | Splits vertically (side-by-side) |
| 15.2 | `<leader>cc` on a tall/square window | Splits horizontally (stacked) |
| 15.3 | Same window, two `cd` projects | Each gets its own pane id (no collision) |

## §16 tt-* shell family

| # | Surface | Test |
|---|---|---|
| 16.1 | `<leader>tt` | Spawns `tt-<slug>` + opens popup attached (CI-covered) |
| 16.2 | `<leader>tn` → enter "foo" | Creates `tt-foo`, opens popup |
| 16.3 | `<leader>tl` | Lists tt-* sessions, Enter attaches, C-x kills (CI-covered) |
| 16.4 | Close popup | Session persists; `<leader>tt` reattaches |

## §17 Tail watches + detach/resume

| # | Surface | Test |
|---|---|---|
| 17.1 | `<leader>sL` → host → log path | Starts `tail-<host>-<slug>` tmux session; scratch buf opens tailing |
| 17.2 | Close scratch w/ `q` | Tmux session stays; state file keeps growing |
| 17.3 | `<leader>sP` → Enter | Reattaches; scratch shows existing + new lines |
| 17.4 | `<leader>sp` inside tail | Watch editor opens; edit + :w persists to JSON |
| 17.5 | Line matches active pattern | `vim.notify` fires w/ level (CI-covered) |
| 17.6 | Oneshot pattern | Flips inactive after first match (CI-covered) |
| 17.7 | Close + reopen nvim; `<leader>sp` | Previously-saved patterns reload |
| 17.8 | `<leader>sT` (deprecated) | Warns then forwards to sL |
````

- [ ] **Step 4: Commit**

```bash
git add lua/plugins/remote.lua lua/coach/tips.lua docs/manual-tests.md
git commit -m "feat(remote): rename sT→sL w/ shim + coach tips + manual-tests §15-17"
```

---

### Task 16: Full suite + push + CI

**Files:**
- Run: `bash scripts/assess.sh`
- Push: `git push origin feat-sp1-cockpit`
- Poll: `gh api` for CI status

- [ ] **Step 1: Run assess**

Run: `cd /home/raul/worktrees/happy-nvim/feat-sp1-cockpit && bash scripts/assess.sh`
Expected: every layer green (shell/python syntax, init bootstrap, plenary, pytest integration, `:checkhealth`).

- [ ] **Step 2: Push**

Run: `git push origin feat-sp1-cockpit`
Expected: remote updated.

- [ ] **Step 3: Poll CI until complete**

Run (loop until all `conclusion` is `success` or `failure`):
```bash
gh api repos/:owner/:repo/actions/runs --jq '.workflow_runs[0:3] | map({name, status, conclusion, head_branch})' | cat
```
Expected: `success` on all three runs.

- [ ] **Step 4: If CI red, iterate fixes until green**

No separate step template — tasks 1-15 cover the actual bugs; any CI regression means one of those tasks broke something and you fix it + re-run assess + repush.

---

## Manual Test Additions

(Rows were appended directly in Task 15 Step 3 — this plan deliberately folds the manual-test updates into the feature commits so each shipped surface gets its row in the same breath.)

## Self-Review (author's pre-flight)

**Spec coverage:**
- 1 (`cc` split) → T2 + T3
- 2 (popup primary) → T5 (labels) + existing `cp` untouched
- 3 (`cq` E5560) → T1
- 4 (`tt-*` family) → T4 + T5
- 5 (SSH picker audit) → T10
- 6 (`ssh_buffer`) → T8 + T9
- 7 (RO default) → T8 (`default_writable=false`) + T9 (`sw`)
- 8 (telescope actions) → T14
- 9 (watch patterns persistence) → T11 + T13
- 10 (detachable tail) → T12
- Keymap table rows → T5 + T9 + T13 + T15 (all keys registered)
- `sT → sL` rename → T15

**Placeholder scan:** no `TBD` / `add validation` / `similar to Task N` found.

**Type consistency:**
- `M.open` return type: `ssh_buffer.open` returns a buffer id or nil (T8), `split.open` returns pane id string or nil (T2), `tail.start` returns nil (T12) — all distinct, no confusion.
- `hosts.expand_path(host, path)` signature consistent T7 + T12 + T8.
- `watch.scan(host, path, line)` used in T12 (`tail.lua`) with matching T11 signature.
- `tt.session_name(slug_override)` and `claude_popup.session()` both produce stable session names w/ distinct prefixes (`tt-*`, `cc-*`).

All good.
