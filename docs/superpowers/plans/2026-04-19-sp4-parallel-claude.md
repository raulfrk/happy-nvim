# SP4 Parallel Claude Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `<leader>cq` — spawn an ephemeral `cc-<id>-scratch-<ts>` claude session in a popup that dies on close.

**Architecture:** Two new fns in `lua/tmux/claude.lua` reuse existing `session_for_cwd` and `guard`. On popup close, async callback kills the scratch session. Remote-project cwd = SP1 sandbox dir.

**Tech Stack:** Lua 5.1 (LuaJIT via Neovim 0.11+), tmux 3.2+ (`display-popup -E`), pytest integration harness.

**Reference:** `docs/superpowers/specs/2026-04-19-sp4-parallel-claude-design.md`

**Working branch:** Reuse `/home/raul/worktrees/happy-nvim/feat-sp1-cockpit`. HEAD matches remote `main` post-SP2.

---

## File Plan

**Modified:**
- `lua/tmux/claude.lua` — add `scratch_name_for`, `scratch_cwd_for`, `M.open_scratch`, `M.open_scratch_guarded`
- `lua/plugins/tmux.lua` — register `<leader>cq` keymap
- `lua/coach/tips.lua` — append entry
- `docs/manual-tests.md` — new §14 with 4 rows

**New:**
- `tests/integration/test_claude_scratch.py` — regression

---

## Task 1: `M.open_scratch` + regression test

**Files:**
- Modify: `lua/tmux/claude.lua`
- Create: `tests/integration/test_claude_scratch.py`

- [ ] **Step 1: Write failing integration test**

`tests/integration/test_claude_scratch.py`:

```python
import os
import re
import subprocess
import textwrap


def test_scratch_spawns_kills_on_close(tmp_path):
    argv_log = tmp_path / 'argv.log'
    snippet = textwrap.dedent(f'''
        local repo = '{os.getcwd()}'
        vim.opt.rtp:prepend(repo)
        vim.env.TMUX = 'dummy'

        local calls = {{}}
        local saved_cb
        vim.system = function(cmd, opts, cb)
          table.insert(calls, table.concat(cmd, ' '))
          if cb then saved_cb = cb end
          return {{
            wait = function() return {{ code = 0, stdout = '', stderr = '' }} end,
            is_closing = function() return false end,
            kill = function() end,
          }}
        end

        -- Stub projects registry (scratch must not pollute it).
        package.loaded['happy.projects.registry'] = {{
          add = function() return 'proj-test' end,
          get = function() return {{ kind = 'local', path = '/tmp' }} end,
          touch = function() end,
          score = function() return 0 end,
        }}

        vim.fn.getcwd = function() return '/tmp' end
        local claude = require('tmux.claude')
        claude.open_scratch()

        -- Fire the display-popup close callback to trigger kill.
        if saved_cb then saved_cb() end

        local fh = io.open('{argv_log}', 'w')
        for _, c in ipairs(calls) do fh:write(c .. '\\n') end
        fh:close()
        vim.cmd('qa!')
    ''')
    subprocess.run(
        ['nvim', '--clean', '--headless', '-u', 'NONE', '-c', f'lua {snippet}'],
        check=True, timeout=15,
    )
    log = argv_log.read_text()
    m = re.search(r'tmux new-session -d -s (cc-[\w\-]+-scratch-\d+)', log)
    assert m, f'scratch new-session missing: {log}'
    scratch = m.group(1)
    assert 'tmux display-popup' in log and f'tmux attach -t {scratch}' in log, log
    assert f'tmux kill-session -t {scratch}' in log, log


def test_scratch_uses_sandbox_for_remote_project(tmp_path):
    argv_log = tmp_path / 'argv.log'
    snippet = textwrap.dedent(f'''
        local repo = '{os.getcwd()}'
        vim.opt.rtp:prepend(repo)
        vim.env.TMUX = 'dummy'

        local calls = {{}}
        vim.system = function(cmd, opts, cb)
          table.insert(calls, table.concat(cmd, ' '))
          return {{
            wait = function() return {{ code = 0, stdout = '', stderr = '' }} end,
            is_closing = function() return false end,
            kill = function() end,
          }}
        end

        package.loaded['happy.projects.registry'] = {{
          add = function() return 'logs-prod01' end,
          get = function() return {{ kind = 'remote', host = 'prod01', path = '/var/log' }} end,
          touch = function() end,
          score = function() return 0 end,
        }}
        package.loaded['happy.projects.remote'] = {{
          sandbox_dir = function(id) return '/tmp/sandboxes/' .. id end,
        }}

        vim.fn.getcwd = function() return '/does/not/matter' end
        require('tmux.claude').open_scratch()

        local fh = io.open('{argv_log}', 'w')
        for _, c in ipairs(calls) do fh:write(c .. '\\n') end
        fh:close()
        vim.cmd('qa!')
    ''')
    subprocess.run(
        ['nvim', '--clean', '--headless', '-u', 'NONE', '-c', f'lua {snippet}'],
        check=True, timeout=15,
    )
    log = argv_log.read_text()
    assert '/tmp/sandboxes/logs-prod01' in log, \
        f'remote scratch must use sandbox dir as cwd: {log}'
```

- [ ] **Step 2: Run test to verify failure**

```bash
cd /home/raul/worktrees/happy-nvim/feat-sp1-cockpit
pytest tests/integration/test_claude_scratch.py -v
```

Expected: FAIL — `open_scratch` not defined.

- [ ] **Step 3: Extend `lua/tmux/claude.lua`**

Read the file first to locate existing `session_for_cwd` + `guard` helpers. Append the new fns just before `return M`:

```lua
local function scratch_name_for(id)
  return ('cc-%s-scratch-%d'):format(id, os.time())
end

local function scratch_cwd_for(id, fallback_cwd)
  local ok_remote, remote = pcall(require, 'happy.projects.remote')
  local ok_reg, registry = pcall(require, 'happy.projects.registry')
  if ok_remote and ok_reg then
    local entry = registry.get(id)
    if entry and entry.kind == 'remote' then
      return remote.sandbox_dir(id)
    end
  end
  return fallback_cwd
end

function M.open_scratch()
  local id, _, cwd = session_for_cwd()
  local name = scratch_name_for(id)
  local effective_cwd = scratch_cwd_for(id, cwd)
  local res = vim
    .system(
      { 'tmux', 'new-session', '-d', '-s', name, '-c', effective_cwd, 'claude' },
      { text = true }
    )
    :wait()
  if res.code ~= 0 then
    vim.notify(
      'failed to spawn scratch claude: ' .. (res.stderr or ''),
      vim.log.levels.ERROR
    )
    return
  end
  vim.system({
    'tmux',
    'display-popup',
    '-E',
    '-w',
    '85%',
    '-h',
    '85%',
    'tmux',
    'attach',
    '-t',
    name,
  }, {}, function()
    vim.system({ 'tmux', 'kill-session', '-t', name }):wait()
  end)
end

function M.open_scratch_guarded()
  if guard() then
    M.open_scratch()
  end
end
```

- [ ] **Step 4: Run test to verify pass**

Expected: 2/2 PASS.

- [ ] **Step 5: Regression**

```bash
pytest tests/integration/ -v 2>&1 | tail -5
```

- [ ] **Step 6: Commit**

```bash
git add lua/tmux/claude.lua tests/integration/test_claude_scratch.py
git commit -m "feat(tmux): <leader>cq spawns ephemeral scratch claude popup"
```

---

## Task 2: Wire keymap + tips + manual-tests

**Files:**
- Modify: `lua/plugins/tmux.lua`
- Modify: `lua/coach/tips.lua`
- Modify: `docs/manual-tests.md`

- [ ] **Step 1: Register keymap in `lua/plugins/tmux.lua`**

READ the file. Find where other `<leader>c*` keys are registered (around the existing `<leader>cc`/`<leader>cp` block). Add:

```lua
    {
      '<leader>cq',
      function()
        require('tmux.claude').open_scratch_guarded()
      end,
      desc = 'Claude: quick scratch popup (single-shot)',
    },
```

Match surrounding indentation and style.

- [ ] **Step 2: Append coach tip**

In `lua/coach/tips.lua`, insert before the closing `}`:

```lua
  {
    keys = '<leader>cq',
    desc = 'quick scratch claude popup (ephemeral, single-shot, SP4)',
    category = 'claude',
  },
```

- [ ] **Step 3: Append manual-tests §14**

In `docs/manual-tests.md`, replace the `---` + `Last updated:` trailer with:

```markdown
## 14. Parallel claude (SP4)

- [ ] `<leader>cq` opens a fresh claude popup. Session named `cc-<id>-scratch-<ts>`.
- [ ] Long-running `cc-<id>` session keeps running (unaffected).
- [ ] Popup close (`ctrl-d` / `prefix+d`) → `tmux ls` shows scratch session gone.
- [ ] Remote project: `<leader>cq` uses sandbox dir (claude inherits `.claude/settings.local.json`).

---

Last updated: SP4 parallel claude landed 2026-04-19.
```

- [ ] **Step 4: Commit**

```bash
git add lua/plugins/tmux.lua lua/coach/tips.lua docs/manual-tests.md
git commit -m "feat(tmux): wire <leader>cq keymap + cheatsheet entry + manual-tests §14"
```

---

## Task 3: Assess + push + CI + close 30.13

- [ ] **Step 1: Full assess**

```bash
cd /home/raul/worktrees/happy-nvim/feat-sp1-cockpit
bash scripts/assess.sh 2>&1 | tail -15
```

Expected: `ASSESS: ALL LAYERS PASS`. If stylua lint fails, fix formatting.

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

- [ ] **Step 4: Close 30.13 (parent todo)**

After CI green, SP2/3/4 are all landed → the tmux vision parent can close:

```
mcp__plugin_proj_proj__todo_complete --todo_id 30.13 --note "Tmux integration vision overhaul complete. SP1 multi-project cockpit + SP2 quick-pivot hub + SP3 fast remote ops + SP4 parallel claude all landed on main."
```

---

## Self-review

**Spec coverage:**
- §3 architecture → Task 1 ✓
- §4 components → Tasks 1 + 2 ✓
- §5 `M.open_scratch` impl → Task 1 ✓
- §6 keymap → Task 2 ✓
- §7 coach tips → Task 2 ✓
- §8 testing → Task 1 ✓ (2 pytest tests)
- §Manual Test Additions → Task 2 ✓

**Placeholder scan:** none.

**Type consistency:** `session_for_cwd`, `guard` are pre-existing from SP1 T6 — referenced but not redefined. `scratch_name_for`, `scratch_cwd_for`, `M.open_scratch`, `M.open_scratch_guarded` all defined in Task 1.

---

## Manual Test Additions

(Listed in Task 2 above.)

```markdown
## 14. Parallel claude (SP4)

- [ ] `<leader>cq` opens a fresh claude popup. Session named `cc-<id>-scratch-<ts>`.
- [ ] Long-running `cc-<id>` session keeps running (unaffected).
- [ ] Popup close (`ctrl-d` / `prefix+d`) → `tmux ls` shows scratch session gone.
- [ ] Remote project: `<leader>cq` uses sandbox dir (claude inherits `.claude/settings.local.json`).
```
