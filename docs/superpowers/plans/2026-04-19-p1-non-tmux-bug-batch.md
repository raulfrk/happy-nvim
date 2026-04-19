# P1 Non-Tmux Bug Batch Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix three small independent P1 bugs surfaced in the 2026-04-19 revdiff pass: `:checkhealth happy-nvim` not found (30.1), `.lua` file errors on missing selene binary (30.5), `:LspInfo` missing on nvim 0.12 (30.6).

**Architecture:** One new 1-line shim file, two small edits to existing `lua/plugins/*.lua`. No new modules. Two new pytest integration tests. Zero impact on tmux / remote / projects code.

**Tech Stack:** Lua 5.1 (LuaJIT via Neovim 0.11+), nvim-lint (`mfussenegger/nvim-lint`), nvim-lspconfig, pytest integration harness.

**Reference:** `docs/superpowers/specs/2026-04-19-p1-non-tmux-bug-batch-design.md`

**Working branch:** Reuse worktree at `/home/raul/worktrees/happy-nvim/feat-sp1-cockpit` (branch `feat-sp1-cockpit`). Its HEAD already equals remote `main` (post-SP1). New commits on this branch push to `main` directly.

---

## File Plan

**New files:**
- `lua/happy-nvim/health.lua` — 1-line shim `return require('happy.health')`
- `tests/integration/test_lint_missing_binary.py` — 30.5 regression coverage
- `tests/integration/test_happy_lsp_info.py` — 30.6 smoke coverage

**Modified files:**
- `lua/plugins/lint.lua` — autocmd callback filters `linters_by_ft` by `vim.fn.executable`
- `lua/plugins/lsp.lua` — register `:HappyLspInfo` user command inside `nvim-lspconfig` `config` block
- `docs/manual-tests.md` — append three rows in a new `§ 10. Bug batch 2026-04-19` section

---

## Ordering + dependencies

All three bug fixes are independent. Tasks 1-3 can run in any order. Tasks 4 (manual-tests rows) and 5 (assess + push) must run last.

Linear order below for subagent-driven execution.

---

## Task 1: 30.1 — health alias shim

**Files:**
- Create: `lua/happy-nvim/health.lua`

- [ ] **Step 1: Create the shim**

Use Write tool to create `lua/happy-nvim/health.lua` with exactly this content:

```lua
-- `:checkhealth happy-nvim` alias. The canonical implementation lives at
-- `lua/happy/health.lua` (Lua namespace `happy`); this shim lets
-- `:checkhealth happy-nvim` find the same health module when users type
-- the repo name instead of the Lua namespace.
return require('happy.health')
```

- [ ] **Step 2: Smoke-test via headless nvim**

`cd /home/raul/worktrees/happy-nvim/feat-sp1-cockpit`

Use an isolated XDG data dir so the test picks up the bundled config:

```bash
export XDG_DATA_HOME=$TMPDIR/happy-t1
mkdir -p $XDG_DATA_HOME/nvim/site/pack/vendor/start
ln -sfn /home/raul/.local/share/nvim/lazy/plenary.nvim \
  $XDG_DATA_HOME/nvim/site/pack/vendor/start/plenary.nvim
nvim --clean --headless \
  -c "set rtp+=." \
  -c "checkhealth happy-nvim" \
  -c "redir >> /tmp/happy-t1-chk.out" -c "silent messages" -c "redir END" \
  -c "qa!" 2>&1 | tail -5
grep -c "ok Neovim" /tmp/happy-t1-chk.out || echo "MISSING"
```

Expected:
- The `nvim ... checkhealth happy-nvim` invocation exits 0 (no stack trace).
- The `:messages` capture contains the string `ok Neovim` (first health assertion in `lua/happy/health.lua`).
- `grep -c` prints a number ≥ 1.

If grep prints `MISSING` or 0, the shim isn't being found — verify the rtp setting or the file path.

- [ ] **Step 3: Commit**

```bash
git add lua/happy-nvim/health.lua
git commit -m "fix(health): alias :checkhealth happy-nvim → happy namespace (closes 30.1)"
```

---

## Task 2: 30.5 — executable-guarded lint

**Files:**
- Modify: `lua/plugins/lint.lua`
- Create: `tests/integration/test_lint_missing_binary.py`

- [ ] **Step 1: Read the current lint.lua**

Use Read tool on `lua/plugins/lint.lua`. Confirm the shape matches the spec (one `linters_by_ft` entry, one BufWritePost/BufReadPost autocmd calling `lint.try_lint()`).

- [ ] **Step 2: Write the failing integration test**

Use Write tool to create `tests/integration/test_lint_missing_binary.py`:

```python
# tests/integration/test_lint_missing_binary.py
"""Regression for 30.5: opening a .lua file on a machine without selene
installed must NOT error-spam `:messages`. The happy-nvim lint autocmd
must filter linters_by_ft by vim.fn.executable() at call time."""

import os
import subprocess
import tempfile
import textwrap


def _make_tmux_wrapper(socket):
    """Shim so nvim's raw `tmux ...` calls hit an isolated server. Not
    strictly needed for this test (no tmux calls) but keeps us aligned
    with the existing helpers pattern used by other integration tests."""
    d = tempfile.mkdtemp(prefix='happy-shim-')
    path = os.path.join(d, 'tmux')
    with open(path, 'w') as f:
        f.write('#!/usr/bin/env bash\nexec /usr/bin/tmux -L ' + socket + ' "$@"\n')
    os.chmod(path, 0o755)
    return d


def test_lint_skipped_when_binary_missing(tmp_path):
    lua_file = tmp_path / 'probe.lua'
    lua_file.write_text('local x = 1\nreturn x\n')
    out_path = tmp_path / 'lint_called.out'
    err_path = tmp_path / 'errmsg.out'

    # Headless nvim with user config loaded. Stub vim.fn.executable globally
    # to return 0 (nothing installed). Hook lint.try_lint with a counter.
    # Open the lua file to trigger BufReadPost.
    snippet = textwrap.dedent(f'''
        -- Load user config (lazy + plugins). Mirrors tests/minimal_init.lua
        -- pattern when HAPPY_NVIM_LOAD_CONFIG=1.
        local repo = '{os.getcwd()}'
        vim.opt.rtp:prepend(repo)
        dofile(repo .. '/init.lua')
        vim.api.nvim_exec_autocmds('VimEnter', {{}})

        -- Wait for Lazy to finish so nvim-lint is on rtp.
        vim.wait(5000, function()
          local ok = pcall(require, 'lint')
          return ok
        end, 100)

        -- Stub lint.try_lint with a counter.
        local lint = require('lint')
        local counter = 0
        local orig = lint.try_lint
        lint.try_lint = function(...)
          counter = counter + 1
          -- Write counter on each call so the file reflects the last call.
          local fh = io.open('{out_path}', 'w')
          fh:write(tostring(counter)); fh:close()
        end

        -- Stub executable() to return 0 for selene.
        vim.fn.executable = function(bin)
          if bin == 'selene' then return 0 end
          return 1
        end

        -- Seed the counter file so "not called" reads as 0.
        local fh = io.open('{out_path}', 'w')
        fh:write('0'); fh:close()

        -- Open the lua file to trigger the happy_lint autocmd group.
        vim.cmd('edit {lua_file}')
        vim.cmd('doautocmd BufReadPost {lua_file}')
        vim.wait(300, function() return false end, 50)

        -- Dump errmsg.
        local ferr = io.open('{err_path}', 'w')
        ferr:write(vim.v.errmsg or ''); ferr:close()

        vim.cmd('qa!')
    ''')

    env = os.environ.copy()
    # Isolate XDG so the user's cache isn't touched.
    scratch = tmp_path / 'xdg'
    (scratch / 'cfg' / 'nvim').mkdir(parents=True)
    (scratch / 'data' / 'nvim').mkdir(parents=True)
    env['XDG_CONFIG_HOME'] = str(scratch / 'cfg')
    env['XDG_DATA_HOME'] = str(scratch / 'data')
    env['XDG_CACHE_HOME'] = str(scratch / 'cache')
    env['XDG_STATE_HOME'] = str(scratch / 'state')
    # Point the config at the repo.
    (scratch / 'cfg' / 'nvim').rmdir()
    os.symlink(os.getcwd(), scratch / 'cfg' / 'nvim')

    subprocess.run(
        ['nvim', '--headless', '-c', f'lua {snippet}'],
        env=env, check=True, timeout=60,
    )

    assert out_path.read_text().strip() == '0', (
        'lint.try_lint was called even though vim.fn.executable(selene) returned 0. '
        'Contents of counter file: ' + out_path.read_text()
    )
    assert err_path.read_text().strip() == '', (
        'vim.v.errmsg was non-empty: ' + err_path.read_text()
    )
```

- [ ] **Step 3: Run test to verify failure**

```bash
cd /home/raul/worktrees/happy-nvim/feat-sp1-cockpit
pytest tests/integration/test_lint_missing_binary.py -v
```

Expected: FAIL — counter file reads `1` (existing code calls `try_lint()` unconditionally).

- [ ] **Step 4: Patch `lua/plugins/lint.lua`**

Use Edit tool on `lua/plugins/lint.lua`. Replace:

```lua
    vim.api.nvim_create_autocmd({ 'BufWritePost', 'BufReadPost' }, {
      group = vim.api.nvim_create_augroup('happy_lint', { clear = true }),
      callback = function()
        lint.try_lint()
      end,
    })
```

With:

```lua
    vim.api.nvim_create_autocmd({ 'BufWritePost', 'BufReadPost' }, {
      group = vim.api.nvim_create_augroup('happy_lint', { clear = true }),
      callback = function()
        local linters = lint.linters_by_ft[vim.bo.filetype] or {}
        local runnable = vim.tbl_filter(function(l)
          return vim.fn.executable(l) == 1
        end, linters)
        if #runnable > 0 then
          lint.try_lint(runnable)
        end
      end,
    })
```

- [ ] **Step 5: Run test to verify pass**

```bash
pytest tests/integration/test_lint_missing_binary.py -v
```

Expected: PASS — counter stays at 0, errmsg empty.

- [ ] **Step 6: Run full regression check**

```bash
pytest tests/integration/ -v 2>&1 | tail -10
```

Expected: everything that was green before is still green; no new failures.

- [ ] **Step 7: Commit**

```bash
git add lua/plugins/lint.lua tests/integration/test_lint_missing_binary.py
git commit -m "fix(lint): skip linters whose binary isn't on \$PATH (closes 30.5)"
```

---

## Task 3: 30.6 — `:HappyLspInfo` user command

**Files:**
- Modify: `lua/plugins/lsp.lua`
- Create: `tests/integration/test_happy_lsp_info.py`

- [ ] **Step 1: Read the current lsp.lua**

Use Read tool on `lua/plugins/lsp.lua`. Confirm the `nvim-lspconfig` entry's `config = function()` block exists and ends before the top-level `}` of the Lazy spec. Identify the `LspAttach` autocmd block (already present) — the new user command is added immediately AFTER it, still inside the same `config = function()` body.

- [ ] **Step 2: Write the failing integration test**

Use Write tool to create `tests/integration/test_happy_lsp_info.py`:

```python
# tests/integration/test_happy_lsp_info.py
"""Smoke test for 30.6: :HappyLspInfo user command must exist after the
user config loads + nvim-lspconfig's config block runs."""

import os
import subprocess
import tempfile
import textwrap


def test_happy_lsp_info_command_registered(tmp_path):
    out = tmp_path / 'exists.out'
    snippet = textwrap.dedent(f'''
        local repo = '{os.getcwd()}'
        vim.opt.rtp:prepend(repo)
        dofile(repo .. '/init.lua')
        vim.api.nvim_exec_autocmds('VimEnter', {{}})

        -- Wait for Lazy to finish + lspconfig's config=function() to run.
        -- lspconfig is lazy-loaded on BufReadPre/BufNewFile; triggering a
        -- file-open autocmd forces the config body to execute.
        vim.cmd('edit /tmp/happy-t3-probe.py')
        vim.wait(5000, function()
          return vim.fn.exists(':HappyLspInfo') == 2
        end, 100)

        local fh = io.open('{out}', 'w')
        fh:write(tostring(vim.fn.exists(':HappyLspInfo'))); fh:close()
        vim.cmd('qa!')
    ''')

    env = os.environ.copy()
    scratch = tmp_path / 'xdg'
    (scratch / 'data' / 'nvim').mkdir(parents=True)
    env['XDG_CONFIG_HOME'] = str(scratch / 'cfg')
    env['XDG_DATA_HOME'] = str(scratch / 'data')
    env['XDG_CACHE_HOME'] = str(scratch / 'cache')
    env['XDG_STATE_HOME'] = str(scratch / 'state')
    os.symlink(os.getcwd(), scratch / 'cfg' / 'nvim')

    subprocess.run(
        ['nvim', '--headless', '-c', f'lua {snippet}'],
        env=env, check=True, timeout=90,
    )

    assert out.read_text().strip() == '2', (
        ':HappyLspInfo does not exist after config load. exists() = '
        + out.read_text()
    )
```

- [ ] **Step 3: Run test to verify failure**

```bash
pytest tests/integration/test_happy_lsp_info.py -v
```

Expected: FAIL — `exists()` returns `0`.

- [ ] **Step 4: Register the command in `lua/plugins/lsp.lua`**

Use Read tool on `lua/plugins/lsp.lua`. Find the `LspAttach` autocmd block (the exact lines depend on file state — grep for `nvim_create_autocmd('LspAttach'`). Immediately AFTER the `})` that closes that autocmd's opts table, and BEFORE the `end,` that closes the outer `config = function()`, insert:

```lua
      vim.api.nvim_create_user_command('HappyLspInfo', function()
        local clients = vim.lsp.get_clients({ bufnr = 0 })
        if #clients == 0 then
          vim.notify('No LSP clients attached to this buffer.', vim.log.levels.INFO)
          return
        end
        for _, c in ipairs(clients) do
          print(('• %s (id=%d, root=%s)'):format(c.name, c.id, c.config.root_dir or '?'))
        end
      end, { desc = 'Show attached LSP clients (0.12-safe replacement for :LspInfo)' })
```

Use Edit tool with `old_string` = the last line of the LspAttach block (the `})` closing its `nvim_create_autocmd` opts table) + a unique suffix so it's unambiguous. Something like:

```
old_string:
        end,
      })
    end,
  },
```
(adjust to match actual whitespace in the file)

```
new_string:
        end,
      })

      vim.api.nvim_create_user_command('HappyLspInfo', function()
        local clients = vim.lsp.get_clients({ bufnr = 0 })
        if #clients == 0 then
          vim.notify('No LSP clients attached to this buffer.', vim.log.levels.INFO)
          return
        end
        for _, c in ipairs(clients) do
          print(('• %s (id=%d, root=%s)'):format(c.name, c.id, c.config.root_dir or '?'))
        end
      end, { desc = 'Show attached LSP clients (0.12-safe replacement for :LspInfo)' })
    end,
  },
```

If the Edit tool errors on ambiguity, add more surrounding context until `old_string` is unique.

- [ ] **Step 5: Run test to verify pass**

```bash
pytest tests/integration/test_happy_lsp_info.py -v
```

Expected: PASS.

- [ ] **Step 6: Run full regression check**

```bash
pytest tests/integration/ -v 2>&1 | tail -10
```

Expected: everything green.

- [ ] **Step 7: Commit**

```bash
git add lua/plugins/lsp.lua tests/integration/test_happy_lsp_info.py
git commit -m "feat(lsp): :HappyLspInfo cmd — 0.12-safe attached-client report (closes 30.6)"
```

---

## Task 4: Append manual-test rows

**Files:**
- Modify: `docs/manual-tests.md`

- [ ] **Step 1: Read current tail of docs/manual-tests.md**

Use Read tool. Find the `---` separator + `Last updated:` line. New section goes immediately before the `---`.

- [ ] **Step 2: Append `§ 10. Bug batch 2026-04-19`**

Use Edit tool. Insert before the `---` separator line:

```markdown
## 10. Bug batch 2026-04-19

- [ ] `:checkhealth happy-nvim` renders sections (core / local CLIs / tmux / claude integration) without "no healthcheck found" (30.1)
- [ ] Open a `.lua` file on a machine without `selene` installed → no error in `:messages` (30.5)
- [ ] `:HappyLspInfo` in a buffer with an attached client lists `• <name> (id=<n>, root=<path>)`; in a buffer with no client, prints "No LSP clients attached to this buffer." (30.6)

---
```

Update the `Last updated:` trailer to:

```
Last updated: P1 non-tmux bug batch landed 2026-04-19.
```

- [ ] **Step 3: Commit**

```bash
git add docs/manual-tests.md
git commit -m "docs: manual-tests rows for P1 non-tmux bug batch (30.1, 30.5, 30.6)"
```

---

## Task 5: Assess + push + CI poll + close todos

- [ ] **Step 1: Full assess**

```bash
cd /home/raul/worktrees/happy-nvim/feat-sp1-cockpit
bash scripts/assess.sh 2>&1 | tail -20
```

Expected: `ASSESS: ALL LAYERS PASS`. If lint fails (stylua), run stylua from wherever it's available on the host (the shipped happy-nvim installer pulls it via mason; the implementing subagent can use the user's existing mason install at `~/.local/share/nvim/mason/bin/stylua` — or skip lint and rely on CI to catch, documented known-limit). Integration, plenary, checkhealth must be green.

If `checkhealth` layer output still shows "No healthcheck found for happy-nvim" after Task 1 landed, the alias shim isn't on `&runtimepath` — debug before pushing.

- [ ] **Step 2: Push**

Remote URL is `https://github.com/raulfrk/happy-nvim.git`. Push the branch to `main` (as with SP1 — no configured git remote, direct URL):

```bash
# Confirm we're ahead of remote main
git fetch https://github.com/raulfrk/happy-nvim.git main
git log --oneline HEAD ^FETCH_HEAD

# Push
git push https://github.com/raulfrk/happy-nvim.git feat-sp1-cockpit:main
```

If rejected as non-fast-forward (someone else pushed in the meantime): rebase onto `FETCH_HEAD`, re-run assess, re-push.

- [ ] **Step 3: Poll CI**

```bash
XDG_CACHE_HOME=$TMPDIR/gh-cache mkdir -p $XDG_CACHE_HOME
XDG_CACHE_HOME=$TMPDIR/gh-cache gh run list --repo raulfrk/happy-nvim --branch main --limit 1
# Grab the run id from the output, then:
XDG_CACHE_HOME=$TMPDIR/gh-cache gh run watch <RUN_ID> --repo raulfrk/happy-nvim --exit-status
```

Expected: both `assess (stable)` + `assess (nightly)` jobs green.

If CI fails: fetch the failing log with `gh run view <id> --log-failed`, triage, fix as a follow-up commit, re-push, re-poll.

- [ ] **Step 4: Close todos in project tracker**

Only after CI green:

```
mcp__plugin_proj_proj__todo_complete --todo_ids ["30.1","30.5","30.6"] --note "Fixed via P1 non-tmux bug batch, CI run <id> green. Health alias + executable-guarded lint + :HappyLspInfo cmd."
```

Leave 30.13 parent open (SP2/SP3/SP4 still pending).

---

## Self-review

**Spec coverage:**
- §4 (Fix 1 health alias) → Task 1 ✓
- §5 (Fix 2 executable-guarded lint) → Task 2 ✓
- §6 (Fix 3 `:HappyLspInfo`) → Task 3 ✓
- §7 testing — two new integration tests → Tasks 2+3 ✓; checkhealth layer verification → Task 5 ✓
- §Manual Test Additions → Task 4 ✓

**Placeholder scan:** none. Every code block is complete. Every command has an expected output.

**Type consistency:** the only types that cross tasks are:
- `lua/happy/health.lua`'s `M.check()` — untouched, referenced by Task 1's shim.
- `vim.lsp.get_clients({bufnr=0})` return shape — only used in Task 3.
- `lint.linters_by_ft` / `lint.try_lint` — only Task 2.

No cross-task coupling. Clean.

---

## Manual Test Additions

(Listed in Task 4 above. The implementing subagent appends those rows to
`docs/manual-tests.md` as part of the Task 4 commit.)

```markdown
## 10. Bug batch 2026-04-19

- [ ] `:checkhealth happy-nvim` renders sections (core / local CLIs / tmux / claude integration) without "no healthcheck found" (30.1)
- [ ] Open a `.lua` file on a machine without `selene` installed → no error in `:messages` (30.5)
- [ ] `:HappyLspInfo` in a buffer with an attached client lists `• <name> (id=<n>, root=<path>)`; in a buffer with no client, prints "No LSP clients attached to this buffer." (30.6)
```
