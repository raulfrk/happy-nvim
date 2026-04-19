# UX Micro-Batch Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship five small UX polish fixes from the 2026-04-19 revdiff pass — confirm dialog for `<leader>ck` (30.4), precognition off-by-default (30.7), cheatsheet coverage for undotree + fugitive + the happy-nvim keymap clusters (30.9, 30.10, 30.11).

**Architecture:** Three file edits (`lua/plugins/tmux.lua`, `lua/plugins/precognition.lua`, `lua/coach/tips.lua`) + three pytest integration tests. No new modules. Additive — the only behavior flip is precognition default-off, which is restored per-session via the existing `<leader>?p` toggle.

**Tech Stack:** Lua 5.1 (LuaJIT via Neovim 0.11+), `tris203/precognition.nvim`, `mbbill/undotree`, `tpope/vim-fugitive`, pytest integration harness.

**Reference:** `docs/superpowers/specs/2026-04-19-ux-micro-batch-design.md`

**Working branch:** Reuse worktree at `/home/raul/worktrees/happy-nvim/feat-sp1-cockpit` (branch `feat-sp1-cockpit`). HEAD already equals remote `main` post-P1-batch. New commits push to `main` directly.

---

## File Plan

**New files:**
- `tests/integration/test_claude_ck_no_loop.py` — 30.4 regression
- `tests/integration/test_precognition_default_off.py` — 30.7 smoke (file-content assertion)
- `tests/integration/test_coach_tips_coverage.py` — 30.9 + 30.10 + 30.11 coverage audit

**Modified files:**
- `lua/plugins/tmux.lua` — replace `vim.ui.select` with `vim.fn.confirm` in `<leader>ck` callback
- `lua/plugins/precognition.lua` — `startVisible = false`
- `lua/coach/tips.lua` — append 31 entries across 6 categories (undo, git, remote, claude, projects, capture)
- `docs/manual-tests.md` — append `§ 11. UX micro-batch 2026-04-19` with 3 rows

---

## Ordering + dependencies

All 5 fixes are independent. Linear order below for subagent-driven execution. Tasks 4 (manual-tests rows) and 5 (assess + push) last.

---

## Task 1: 30.4 — `<leader>ck` confirm (no prompt loop)

**Files:**
- Modify: `lua/plugins/tmux.lua:78-96`
- Create: `tests/integration/test_claude_ck_no_loop.py`

- [ ] **Step 1: Read current lua/plugins/tmux.lua**

Use Read tool on `lua/plugins/tmux.lua`. Locate the `<leader>ck` keymap entry (around lines 78-96). Confirm it matches the spec:

```lua
{
  '<leader>ck',
  function()
    local popup = require('tmux.claude_popup')
    if not popup.exists() then
      vim.notify('no Claude session for this project', vim.log.levels.INFO)
      return
    end
    vim.ui.select({ 'Yes, kill it', 'No, cancel' }, {
      prompt = "Kill current project's Claude session?",
    }, function(choice)
      if choice == 'Yes, kill it' then
        popup.kill()
        vim.notify('killed ' .. require('tmux.project').session_name(), vim.log.levels.INFO)
      end
    end)
  end,
  desc = "Claude: kill current project's session",
},
```

If the code differs, read the surrounding 40 lines and adjust the Edit tool call accordingly — preserve whatever the current code does for the "no session" branch.

- [ ] **Step 2: Write failing integration test**

Create `tests/integration/test_claude_ck_no_loop.py`:

```python
# tests/integration/test_claude_ck_no_loop.py
"""Regression for 30.4: <leader>ck must NOT call vim.ui.select (whose
default inputlist backend loops on blank Enter). It must use
vim.fn.confirm + run popup.kill only when confirm returns 1."""

import os
import subprocess
import textwrap


def _run_nvim(snippet, cwd=None, env_extra=None, timeout=30):
    env = os.environ.copy()
    env.setdefault('XDG_CONFIG_HOME', '/tmp/happy-ux-t1-cfg')
    env.setdefault('XDG_DATA_HOME', '/tmp/happy-ux-t1-data')
    env.setdefault('XDG_CACHE_HOME', '/tmp/happy-ux-t1-cache')
    env.setdefault('XDG_STATE_HOME', '/tmp/happy-ux-t1-state')
    if env_extra:
        env.update(env_extra)
    return subprocess.run(
        ['nvim', '--clean', '--headless', '-u', 'NONE', '-c', f'lua {snippet}'],
        cwd=cwd or os.getcwd(), env=env, check=True, timeout=timeout,
    )


def test_ck_callback_uses_confirm_not_ui_select(tmp_path):
    """Invoke the <leader>ck keymap callback directly (via the Lazy spec
    table) with vim.ui.select + vim.fn.confirm both stubbed. Assert
    confirm was called, ui.select was NOT, and popup.kill was called when
    confirm returns 1."""
    confirm_path = tmp_path / 'confirm.out'
    select_path = tmp_path / 'select.out'
    kill_path = tmp_path / 'kill.out'

    snippet = textwrap.dedent(f'''
        local repo = '{os.getcwd()}'
        vim.opt.rtp:prepend(repo)

        -- Seed counter files to 0 before stubbing.
        for _, p in ipairs({{ '{confirm_path}', '{select_path}', '{kill_path}' }}) do
          local fh = io.open(p, 'w'); fh:write('0'); fh:close()
        end

        local function bump(path)
          local fh = io.open(path, 'r'); local n = tonumber(fh:read('*a') or '0') or 0; fh:close()
          fh = io.open(path, 'w'); fh:write(tostring(n + 1)); fh:close()
        end

        -- Stub vim.ui.select + vim.fn.confirm.
        vim.ui.select = function(...) bump('{select_path}'); return nil end
        vim.fn.confirm = function(...) bump('{confirm_path}'); return 1 end

        -- Stub tmux.claude_popup so .exists() = true, .kill() counted.
        package.loaded['tmux.claude_popup'] = {{
          exists = function() return true end,
          kill = function() bump('{kill_path}') end,
        }}
        package.loaded['tmux.project'] = {{
          session_name = function() return 'cc-probe' end,
        }}

        -- Load the plugin spec and find the <leader>ck entry.
        local spec = dofile(repo .. '/lua/plugins/tmux.lua')
        local ck
        for _, e in ipairs(spec.keys or {{}}) do
          if e[1] == '<leader>ck' then ck = e break end
        end
        assert(ck, '<leader>ck keymap entry not found in lua/plugins/tmux.lua')
        -- Invoke the callback.
        ck[2]()

        vim.cmd('qa!')
    ''')

    _run_nvim(snippet)

    assert confirm_path.read_text().strip() == '1', \
        f'vim.fn.confirm should have been called once; got {confirm_path.read_text()}'
    assert select_path.read_text().strip() == '0', \
        f'vim.ui.select should NOT have been called; got {select_path.read_text()}'
    assert kill_path.read_text().strip() == '1', \
        f'popup.kill should have run (confirm returned 1); got {kill_path.read_text()}'


def test_ck_callback_skips_kill_when_confirm_says_no(tmp_path):
    """Confirm returns 2 (No) → popup.kill NOT called."""
    confirm_path = tmp_path / 'confirm.out'
    kill_path = tmp_path / 'kill.out'

    snippet = textwrap.dedent(f'''
        local repo = '{os.getcwd()}'
        vim.opt.rtp:prepend(repo)

        for _, p in ipairs({{ '{confirm_path}', '{kill_path}' }}) do
          local fh = io.open(p, 'w'); fh:write('0'); fh:close()
        end
        local function bump(path)
          local fh = io.open(path, 'r'); local n = tonumber(fh:read('*a') or '0') or 0; fh:close()
          fh = io.open(path, 'w'); fh:write(tostring(n + 1)); fh:close()
        end

        vim.fn.confirm = function(...) bump('{confirm_path}'); return 2 end
        package.loaded['tmux.claude_popup'] = {{
          exists = function() return true end,
          kill = function() bump('{kill_path}') end,
        }}
        package.loaded['tmux.project'] = {{
          session_name = function() return 'cc-probe' end,
        }}

        local spec = dofile(repo .. '/lua/plugins/tmux.lua')
        local ck
        for _, e in ipairs(spec.keys or {{}}) do
          if e[1] == '<leader>ck' then ck = e break end
        end
        ck[2]()

        vim.cmd('qa!')
    ''')

    _run_nvim(snippet)

    assert confirm_path.read_text().strip() == '1'
    assert kill_path.read_text().strip() == '0', \
        'popup.kill must NOT run when confirm returns 2'
```

- [ ] **Step 3: Run test to verify failure**

```bash
cd /home/raul/worktrees/happy-nvim/feat-sp1-cockpit
pytest tests/integration/test_claude_ck_no_loop.py -v
```

Expected: FAIL — `vim.ui.select` counter is `1`, `vim.fn.confirm` counter is `0`.

- [ ] **Step 4: Patch lua/plugins/tmux.lua**

Use Edit tool. Replace the existing `<leader>ck` entry's function body:

```lua
      function()
        local popup = require('tmux.claude_popup')
        if not popup.exists() then
          vim.notify('no Claude session for this project', vim.log.levels.INFO)
          return
        end
        vim.ui.select({ 'Yes, kill it', 'No, cancel' }, {
          prompt = "Kill current project's Claude session?",
        }, function(choice)
          if choice == 'Yes, kill it' then
            popup.kill()
            vim.notify('killed ' .. require('tmux.project').session_name(), vim.log.levels.INFO)
          end
        end)
      end,
```

With:

```lua
      function()
        local popup = require('tmux.claude_popup')
        if not popup.exists() then
          vim.notify('no Claude session for this project', vim.log.levels.INFO)
          return
        end
        if vim.fn.confirm("Kill current project's Claude session?", '&Yes\n&No') == 1 then
          popup.kill()
          vim.notify('killed ' .. require('tmux.project').session_name(), vim.log.levels.INFO)
        end
      end,
```

Match the surrounding indentation exactly.

- [ ] **Step 5: Run test to verify pass**

```bash
pytest tests/integration/test_claude_ck_no_loop.py -v
```

Expected: both tests PASS.

- [ ] **Step 6: Run full integration regression**

```bash
pytest tests/integration/ -v 2>&1 | tail -10
```

Expected: prior count (40 passed + 1 skipped) + 2 new = 42 passed + 1 skipped.

- [ ] **Step 7: Commit**

```bash
git add lua/plugins/tmux.lua tests/integration/test_claude_ck_no_loop.py
git commit -m "fix(tmux): <leader>ck uses confirm, not ui.select (closes 30.4)"
```

---

## Task 2: 30.7 — precognition off by default

**Files:**
- Modify: `lua/plugins/precognition.lua:6`
- Create: `tests/integration/test_precognition_default_off.py`

- [ ] **Step 1: Write failing test**

Create `tests/integration/test_precognition_default_off.py`:

```python
# tests/integration/test_precognition_default_off.py
"""30.7: precognition must NOT auto-enable on cold nvim boot. Users
opt in via <leader>?p. Invariant: lua/plugins/precognition.lua sets
opts.startVisible = false."""

from pathlib import Path


def test_precognition_spec_default_off():
    spec = Path('lua/plugins/precognition.lua').read_text()
    assert 'startVisible = false' in spec, \
        'lua/plugins/precognition.lua must set startVisible = false'
    assert 'startVisible = true' not in spec, \
        'lua/plugins/precognition.lua must NOT set startVisible = true'
```

- [ ] **Step 2: Run test to verify failure**

```bash
cd /home/raul/worktrees/happy-nvim/feat-sp1-cockpit
pytest tests/integration/test_precognition_default_off.py -v
```

Expected: FAIL — current file has `startVisible = true`.

- [ ] **Step 3: Patch lua/plugins/precognition.lua**

Use Edit tool. Change line 6:

Old: `    startVisible = true,`
New: `    startVisible = false,`

- [ ] **Step 4: Run test to verify pass**

```bash
pytest tests/integration/test_precognition_default_off.py -v
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lua/plugins/precognition.lua tests/integration/test_precognition_default_off.py
git commit -m "fix(precognition): default off, opt-in via <leader>?p (closes 30.7)"
```

---

## Task 3: 30.9 + 30.10 + 30.11 — cheatsheet coverage

**Files:**
- Modify: `lua/coach/tips.lua`
- Create: `tests/integration/test_coach_tips_coverage.py`

- [ ] **Step 1: Read lua/coach/tips.lua**

Use Read tool. Count existing entries (for the "grew" assertion) and note the last `return { ... }` line so the Edit tool insertion is unambiguous.

- [ ] **Step 2: Write failing coverage test**

Create `tests/integration/test_coach_tips_coverage.py`:

```python
# tests/integration/test_coach_tips_coverage.py
"""30.9 + 30.10 + 30.11: the coach cheatsheet must cover undotree,
fugitive, remote, claude, projects, and capture keymap clusters.

Coverage audit — catches future regressions where a new keymap cluster
lands without a corresponding tips entry."""

import os
import subprocess
import textwrap
import json


def _dump_tips(tmp_path):
    """Load lua/coach/tips.lua in headless nvim, serialize to JSON."""
    out = tmp_path / 'tips.json'
    snippet = textwrap.dedent(f'''
        local repo = '{os.getcwd()}'
        vim.opt.rtp:prepend(repo)
        local tips = dofile(repo .. '/lua/coach/tips.lua')
        local fh = io.open('{out}', 'w')
        fh:write(vim.json.encode(tips)); fh:close()
        vim.cmd('qa!')
    ''')
    subprocess.run(
        ['nvim', '--clean', '--headless', '-u', 'NONE', '-c', f'lua {snippet}'],
        check=True, timeout=15,
    )
    return json.loads(out.read_text())


def test_tips_include_new_categories(tmp_path):
    tips = _dump_tips(tmp_path)
    categories = {t.get('category') for t in tips}
    required = {'undo', 'git', 'remote', 'claude', 'projects', 'capture'}
    missing = required - categories
    assert not missing, f'tips missing categories: {missing}. Present: {categories}'


def test_tips_include_required_keymaps(tmp_path):
    """Specific keymaps that MUST be surfaced in the cheatsheet so users
    can discover them."""
    tips = _dump_tips(tmp_path)
    keys_present = {t.get('keys') for t in tips}
    required_keys = {
        '<leader>u',           # 30.9
        '<leader>gs',          # 30.10
        '<leader>ss',          # 30.11 remote
        '<leader>cc',          # 30.11 claude
        '<leader>ck',          # 30.11 claude
        '<leader>P',           # 30.11 projects (SP1)
        '<leader>Cc',          # 30.11 capture (SP1)
    }
    missing = required_keys - keys_present
    assert not missing, (
        f'tips missing required keymaps: {missing}. '
        f'Tips count: {len(tips)}.'
    )


def test_tips_grew(tmp_path):
    """Baseline: pre-patch tips had ~30-40 entries. After this batch,
    must grow. Exact count is brittle — just assert at least 55."""
    tips = _dump_tips(tmp_path)
    assert len(tips) >= 55, f'tips count {len(tips)} < 55, batch not applied'
```

- [ ] **Step 3: Run tests to verify failure**

```bash
pytest tests/integration/test_coach_tips_coverage.py -v
```

Expected: FAIL — categories like `remote`, `claude`, `projects`, `capture` are missing; required keymaps missing.

- [ ] **Step 4: Append entries to lua/coach/tips.lua**

Use Edit tool. `old_string` should be the last two lines of the file (whatever the final entry + closing `}` pattern looks like). Read the current file first to get the exact bytes of the tail.

Insert BEFORE the closing `}` of the returned table:

```lua
  -- undotree (<leader>u) — 30.9
  { keys = '<leader>u', desc = 'open undotree panel', category = 'undo' },
  { keys = '? (in undotree)', desc = 'show undotree help', category = 'undo' },
  { keys = 'j/k (in undotree)', desc = 'navigate revisions up/down', category = 'undo' },
  { keys = '<Enter> (in undotree)', desc = 'jump buffer to selected revision', category = 'undo' },
  { keys = 'd (in undotree)', desc = 'diff selected revision vs current', category = 'undo' },

  -- fugitive (<leader>gs / :Git) — 30.10
  { keys = '<leader>gs', desc = 'open Git status split (fugitive)', category = 'git' },
  { keys = 's (in :Git)', desc = 'stage file under cursor', category = 'git' },
  { keys = 'u (in :Git)', desc = 'unstage file under cursor', category = 'git' },
  { keys = '= (in :Git)', desc = 'toggle inline diff under cursor', category = 'git' },
  { keys = 'cc (in :Git)', desc = 'start commit (opens commit msg buffer)', category = 'git' },
  { keys = 'ca (in :Git)', desc = 'commit --amend', category = 'git' },

  -- remote (<leader>s*) — 30.11
  { keys = '<leader>ss', desc = 'ssh host picker (frecency-ordered)', category = 'remote' },
  { keys = '<leader>sd', desc = 'remote dir picker (zoxide-like, 7d cache)', category = 'remote' },
  { keys = '<leader>sB', desc = 'open remote file as scp:// buffer', category = 'remote' },
  { keys = '<leader>sg', desc = 'remote grep (nice/ionice over ssh) -> quickfix', category = 'remote' },

  -- claude tmux (<leader>c*) — 30.11
  { keys = '<leader>cc', desc = 'open/attach project claude session (cc-<id>)', category = 'claude' },
  { keys = '<leader>cp', desc = 'popup claude (SP1: remote-sandboxed if remote)', category = 'claude' },
  { keys = '<leader>cf', desc = 'send current file as @path to claude', category = 'claude' },
  { keys = '<leader>cs', desc = 'send visual selection (fenced w/ file:L-L header)', category = 'claude' },
  { keys = '<leader>ce', desc = 'send LSP diagnostics for current buffer', category = 'claude' },
  { keys = '<leader>cl', desc = 'list claude sessions (telescope picker)', category = 'claude' },
  { keys = '<leader>cn', desc = 'new named claude session (prompts for slug)', category = 'claude' },
  { keys = '<leader>ck', desc = "kill current project's claude session (Y/N confirm)", category = 'claude' },

  -- projects / cockpit (<leader>P*) — 30.11 (SP1)
  { keys = '<leader>P', desc = 'projects picker — pivot / peek / add / forget', category = 'projects' },
  { keys = '<leader>Pa', desc = 'add project (prompt for /path or host:path)', category = 'projects' },
  { keys = '<leader>Pp', desc = 'peek project scrollback (no pivot)', category = 'projects' },
  { keys = ':HappyWtProvision <path>', desc = 'provision worktree claude (async)', category = 'projects' },
  { keys = ':HappyWtCleanup <path>', desc = 'cleanup worktree claude (async)', category = 'projects' },

  -- capture (<leader>C*) — SP1 remote->claude one-way data flow
  { keys = '<leader>Cc', desc = 'capture remote pane -> sandbox file', category = 'capture' },
  { keys = '<leader>Ct', desc = 'toggle tail-pipe from remote pane -> sandbox live.log', category = 'capture' },
  { keys = '<leader>Cl', desc = 'pull remote file via scp -> sandbox dir', category = 'capture' },
  { keys = '<leader>Cs', desc = 'send visual selection -> sandbox file', category = 'capture' },
```

That's 31 entries. Match the file's existing 2-space indentation (the file uses `  { keys = ..., }` style).

- [ ] **Step 5: Run tests to verify pass**

```bash
pytest tests/integration/test_coach_tips_coverage.py -v
```

Expected: 3/3 PASS.

- [ ] **Step 6: Run full integration regression**

```bash
pytest tests/integration/ -v 2>&1 | tail -10
```

Expected: prior + 2 (T1) + 1 (T2) + 3 (T3) = 46 passed + 1 skipped.

- [ ] **Step 7: Commit**

```bash
git add lua/coach/tips.lua tests/integration/test_coach_tips_coverage.py
git commit -m "feat(coach): cheatsheet entries for undotree, fugitive, remote, claude, projects, capture (closes 30.9, 30.10, 30.11)"
```

---

## Task 4: Append manual-tests rows

**Files:**
- Modify: `docs/manual-tests.md`

- [ ] **Step 1: Read current tail of docs/manual-tests.md**

Use Read tool on lines 125-end to find the `§ 10` section end + the `---` separator.

- [ ] **Step 2: Insert `§ 11` before the `---` separator**

Use Edit tool. Find the block:

```
<last line of §10>

---

Last updated: P1 non-tmux bug batch landed 2026-04-19.
```

Replace with:

```
<last line of §10>

## 11. UX micro-batch 2026-04-19

- [ ] `<leader>ck` with active claude session → Y/N dialog at bottom. `<Y>` or `<Enter>` kills, `<N>` cancels. Pressing `<Enter>` repeatedly never loops (30.4)
- [ ] Cold `nvim` open on a `.lua` file → no `w / b / e / $ / ^ / %` overlays. `<leader>?p` toggles them on. Second `<leader>?p` toggles off (30.7)
- [ ] `<leader>?` cheatsheet opens → type `remote`, `claude`, `projects`, `capture`, `undo`, or `git` → results show the respective keybindings (30.9, 30.10, 30.11)

---

Last updated: UX micro-batch landed 2026-04-19.
```

Use generous `old_string` context so the Edit call is unambiguous (include the last 2-3 lines of §10 + the trailer lines).

- [ ] **Step 3: Commit**

```bash
git add docs/manual-tests.md
git commit -m "docs: manual-tests rows for UX micro-batch (30.4, 30.7, 30.9, 30.10, 30.11)"
```

---

## Task 5: Assess + push + CI poll + close todos

- [ ] **Step 1: Full assess**

```bash
cd /home/raul/worktrees/happy-nvim/feat-sp1-cockpit
bash scripts/assess.sh 2>&1 | tail -20
```

Expected: `ASSESS: ALL LAYERS PASS`. If the integration layer reports a transient pytest FAIL (the harness is occasionally flaky), re-run once. If lint fails on stylua formatting (new entries in `tips.lua` must match 2-space indent + multi-line tables), fix formatting before pushing.

- [ ] **Step 2: Push**

```bash
git fetch https://github.com/raulfrk/happy-nvim.git main
git log --oneline HEAD ^FETCH_HEAD   # show commits ahead of remote main

git push https://github.com/raulfrk/happy-nvim.git feat-sp1-cockpit:main
```

If non-fast-forward: rebase onto FETCH_HEAD, re-assess, re-push.

- [ ] **Step 3: Poll CI**

```bash
mkdir -p $TMPDIR/gh-cache
XDG_CACHE_HOME=$TMPDIR/gh-cache gh run list --repo raulfrk/happy-nvim --branch main --limit 1
# grab RUN_ID from output, then:
XDG_CACHE_HOME=$TMPDIR/gh-cache gh run watch <RUN_ID> --repo raulfrk/happy-nvim --exit-status
```

Expected: both `assess (stable)` + `assess (nightly)` jobs green.

- [ ] **Step 4: Close todos**

Only after CI green:

```
mcp__plugin_proj_proj__todo_complete --todo_ids ["30.4","30.7","30.9","30.10","30.11"] --note "UX micro-batch landed on main, CI green (run <id>). 30.4: confirm dialog. 30.7: precognition off by default. 30.9/30.10/30.11: cheatsheet coverage for undotree, fugitive, remote, claude, projects, capture."
```

Leave 30.13 (tmux vision parent), 30.2 (OSC 52 — needs SP3), 30.8 (ss picker empty — SP3) open.

---

## Self-review

**Spec coverage:**
- §4 (Fix 1 30.4 confirm) → Task 1 ✓
- §5 (Fix 2 30.7 precognition) → Task 2 ✓
- §6 (Fix 3+4 tips coverage) → Task 3 ✓
- §7 tests → Tasks 1/2/3 ✓
- §Manual Test Additions → Task 4 ✓

**Placeholder scan:** none. Every code block is complete.

**Type consistency:** n/a — no cross-task data types.

---

## Manual Test Additions

(Listed in Task 4 above. The implementing subagent appends those rows
to `docs/manual-tests.md` as part of the Task 4 commit.)

```markdown
## 11. UX micro-batch 2026-04-19

- [ ] `<leader>ck` with active claude session → Y/N dialog at bottom. `<Y>` or `<Enter>` kills, `<N>` cancels. Pressing `<Enter>` repeatedly never loops (30.4)
- [ ] Cold `nvim` open on a `.lua` file → no `w / b / e / $ / ^ / %` overlays. `<leader>?p` toggles them on. Second `<leader>?p` toggles off (30.7)
- [ ] `<leader>?` cheatsheet opens → type `remote`, `claude`, `projects`, `capture`, `undo`, or `git` → results show the respective keybindings (30.9, 30.10, 30.11)
```
