# Skipped-Test Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Factor 6 helpers public (unblocks 6 pytest skips) + replace `test_lsp_format.py` with a `test_conform_format_once.py` that skirts the Mason race.

**Architecture:** 4 small edits across `lua/{tmux/picker,remote/browse,remote/dirs,remote/hosts}.lua`, 6 test-file edits removing `pytest.skip()` guards, 1 test-file delete + 1 new test file.

**Tech Stack:** Lua 5.1, pytest integration harness.

**Reference:** `docs/superpowers/specs/2026-04-20-skipped-test-cleanup-design.md`

**Working branch:** `/home/raul/worktrees/happy-nvim/feat-sp1-cockpit`.

---

## Task 1: Factor helpers public

**Files:**
- Modify: `lua/tmux/picker.lua`
- Modify: `lua/remote/browse.lua`
- Modify: `lua/remote/dirs.lua`
- Modify: `lua/remote/hosts.lua`

### 1a. `tmux.picker._kill_session`

READ `lua/tmux/picker.lua` — find the `<C-x>` map block (around line
107 which calls `require('tmux.claude_popup').kill(entry.value.name)`).
Extract into a public helper:

Insert before `function M.open()`:

```lua
function M._kill_session(name)
  require('tmux.claude_popup').kill(name)
end
```

Change the `<C-x>` mapping body FROM:

```lua
require('tmux.claude_popup').kill(entry.value.name)
```

TO:

```lua
M._kill_session(entry.value.name)
```

Keeps same behavior; test hooks into `_kill_session` directly.

### 1b. `remote.browse.open_path`, `_is_binary`, `_set_override`

READ `lua/remote/browse.lua`. Find `M.open(host, rpath)` (around line
76). Add:

```lua
-- Public alias matching test expectations.
M.open_path = M.open

function M._is_binary(host, rpath)
  if vim.b.happy_force_binary then return false end
  if M._fast_path_ext(rpath) then return false end
  local run = require('remote.util').run
  local mime = run(M._build_mime_probe_cmd(host, rpath), { text = true })
  return mime.code == 0 and M._is_binary_mime(mime.stdout or '')
end

function M._set_override(on)
  vim.b.happy_force_binary = on and true or nil
end
```

Place these AFTER `M.force_binary` or wherever the related block lives.
Don't modify `M.open`'s logic — the new `_is_binary` helper re-uses
existing building blocks.

### 1c. `remote.dirs._list_remote`

Append to `lua/remote/dirs.lua` (after `M._fetch_sync`):

```lua
-- Public alias matching test expectations.
M._list_remote = M._fetch_sync
```

### 1d. `remote.hosts.prune`

Append to `lua/remote/hosts.lua` (near other public fns):

```lua
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
    local dir = _G._happy_hosts_db_path and _G._happy_hosts_db_path:match('(.*/)')
      or (vim.fn.stdpath('data') .. '/happy-nvim/')
    -- Write back via the same atomic approach used elsewhere
    local path = (function()
      local h = M._set_db_path_for_test
      -- Read the current path by inspecting the closure — simplest fix:
      -- expose a _get_db_path helper.
      return M._get_db_path and M._get_db_path() or
        (vim.fn.stdpath('data') .. '/happy-nvim/hosts.json')
    end)()
    vim.fn.mkdir(path:match('(.*/)'), 'p')
    local f = io.open(path, 'w')
    if f then f:write(vim.json.encode(db)); f:close() end
  end
  return removed
end
```

**Simpler approach:** refactor `hosts.lua` to store `DB_PATH` as a
module-local variable (like SP3 did) then both `prune` and
`_set_db_path_for_test` share it. READ the file — if `DB_PATH` is
already module-local (it should be from SP3), the above simplifies to:

```lua
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
    if dir then vim.fn.mkdir(dir, 'p') end
    local f = io.open(DB_PATH, 'w')
    if f then f:write(vim.json.encode(db)); f:close() end
  end
  return removed
end
```

This version assumes `DB_PATH` is a file-local variable — which it is
post-SP3 (see `M._set_db_path_for_test`).

### 1e. Commit

```bash
cd /home/raul/worktrees/happy-nvim/feat-sp1-cockpit
# No tests run yet — next task unskips the tests that exercise these.
git add lua/tmux/picker.lua lua/remote/browse.lua lua/remote/dirs.lua lua/remote/hosts.lua
git commit -m "feat(tmux,remote): factor public helpers (picker._kill_session, browse._is_binary, browse._set_override, browse.open_path, dirs._list_remote, hosts.prune)"
```

---

## Task 2: Unskip the 6 conversion tests

**Files:**
- Modify: `tests/integration/test_manual_s4_tmux_claude.py` (1 skip)
- Modify: `tests/integration/test_manual_s6_remote.py` (5 skips)

For each test: remove the `pytest.skip(...)` guard + the conditional
that wraps it. The tests already contain the full pass-path logic.

Example pattern — BEFORE:

```python
if text.strip() == 'NIL':
    import pytest; pytest.skip('remote.dirs._list_remote not factored as helper')
assert 'ssh' in text and 'prod01' in text
```

AFTER:

```python
assert 'ssh' in text and 'prod01' in text, text
```

READ each test file + remove:
- `test_cl_picker_ctrl_x_kills_selected_session`: remove the `if 'kill-session' not in log: pytest.skip(...)` block.
- `test_remote_dirs_picker_reads_from_util_run`: remove the NIL skip.
- `test_remote_browse_opens_scp_buffer`: remove the NIL skip.
- `test_remote_browse_refuses_binary`: remove the NIL skip.
- `test_remote_browse_override_skips_binary_check`: remove the NIL skip.
- `test_happy_hosts_prune_reports_count`: remove the NIL skip.

Run tests after each section to verify flips from skip to pass:

```bash
pytest tests/integration/test_manual_s4_tmux_claude.py tests/integration/test_manual_s6_remote.py -v
```

Expected: `test_cl_picker_ctrl_x_kills_selected_session` + 5 remote tests flip skip → pass.

Commit:

```bash
git add tests/integration/test_manual_s4_tmux_claude.py tests/integration/test_manual_s6_remote.py
git commit -m "test: unskip 6 conversion tests now that helpers are public"
```

---

## Task 3: Replace `test_lsp_format.py` with `test_conform_format_once.py`

**Files:**
- Delete: `tests/integration/test_lsp_format.py`
- Create: `tests/integration/test_conform_format_once.py`

### 3a. Delete

```bash
git rm tests/integration/test_lsp_format.py
```

### 3b. Create new test

```python
# tests/integration/test_conform_format_once.py
"""BUG-1 regression (replaces the Mason-race test_lsp_format.py).

conform.nvim must be the SOLE format-on-save owner — :w fires conform
exactly once, never twice via competing autocmds or LSP formatProvider.
Uses stylua on .lua to sidestep Mason (stylua is a system binary, skip-
if-missing)."""

import os
import shutil
import subprocess
import textwrap


def test_conform_fires_once_on_save(tmp_path):
    if not shutil.which('stylua'):
        import pytest; pytest.skip('stylua not installed')

    work = tmp_path / 'w'; work.mkdir()
    probe = work / 'probe.lua'
    probe.write_text('local x   =   1\n')

    counter = tmp_path / 'fires.out'
    counter.write_text('0')

    snippet = textwrap.dedent(f'''
        local repo = '{os.getcwd()}'
        vim.opt.rtp:prepend(repo)
        vim.api.nvim_exec_autocmds('VimEnter', {{}})
        vim.wait(5000, function() return pcall(require, 'conform') end, 100)

        local orig_format = require('conform').format
        require('conform').format = function(opts, cb)
          local fh = io.open('{counter}', 'r')
          local n = tonumber(fh:read('*a')) or 0
          fh:close()
          fh = io.open('{counter}', 'w')
          fh:write(tostring(n + 1))
          fh:close()
          return orig_format(opts, cb)
        end

        vim.cmd('edit {probe}')
        vim.cmd('silent! write')
        vim.wait(2000, function() return false end, 100)
        vim.cmd('qa!')
    ''')

    env = os.environ.copy()
    scratch = tmp_path / 'xdg'
    (scratch / 'cfg').mkdir(parents=True, exist_ok=True)
    (scratch / 'data' / 'nvim').mkdir(parents=True, exist_ok=True)
    env['XDG_CONFIG_HOME'] = str(scratch / 'cfg')
    env['XDG_DATA_HOME'] = str(scratch / 'data')
    env['XDG_CACHE_HOME'] = str(scratch / 'cache')
    env['XDG_STATE_HOME'] = str(scratch / 'state')
    if not (scratch / 'cfg' / 'nvim').exists():
        os.symlink(os.getcwd(), scratch / 'cfg' / 'nvim')

    subprocess.run(
        ['nvim', '--headless', '-c', f'lua {snippet}'],
        env=env, check=True, timeout=60,
    )

    fires = int(counter.read_text().strip())
    assert fires == 1, f'conform.format fired {fires} times (expected 1)'
```

### 3c. Run + commit

```bash
pytest tests/integration/test_conform_format_once.py -v
# Expect: 1 pass (or skip if stylua unavailable in sandbox — parent CI has it)
git add tests/integration/test_conform_format_once.py
git rm tests/integration/test_lsp_format.py
git commit -m "test: replace test_lsp_format.py w/ test_conform_format_once.py (sidesteps Mason race)"
```

---

## Task 4: Full regression + push + CI

- [ ] **Step 1: assess**

```bash
cd /home/raul/worktrees/happy-nvim/feat-sp1-cockpit
bash scripts/assess.sh 2>&1 | tail -15
```

Expected: ALL LAYERS PASS. Fix stylua formatting if needed.

- [ ] **Step 2: push**

```bash
git push https://github.com/raulfrk/happy-nvim.git feat-sp1-cockpit:main
```

- [ ] **Step 3: poll CI**

```bash
mkdir -p $TMPDIR/gh-cache
RUNID=$(XDG_CACHE_HOME=$TMPDIR/gh-cache gh run list --repo raulfrk/happy-nvim --branch main --limit 1 --json databaseId -q '.[0].databaseId')
XDG_CACHE_HOME=$TMPDIR/gh-cache gh run watch $RUNID --repo raulfrk/happy-nvim --exit-status
```

Expected: green. Net: +7 passing tests (-1 skipped-lsp-format deleted, +1 new conform-once, +6 unskipped).

---

## Self-review

**Spec coverage:** §1a public helpers → Task 1 ✓. §1b test rewrite → Task 3 ✓. §4 testing → Task 4 ✓.
**Placeholders:** none.
**Type consistency:** `M._list_remote = M._fetch_sync` is an alias — no new signature.

## Manual Test Additions

None. All new tests are CI-only; no user-facing surface changes.
