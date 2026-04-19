# SP3 Fast Remote Ops Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix OSC 52 host clipboard (30.2), ss empty picker (30.8), and add three new remote primitives — ad-hoc cmd runner (`<leader>sc`), log tailer (`<leader>sT`), file-name finder (`<leader>sf`).

**Architecture:** Modify `lua/clipboard/init.lua` for tmux DCS passthrough. Refactor `lua/remote/hosts.lua` to always-prepend an `[+ Add host]` synthetic entry and accept a callback so new features can reuse the picker. Add three single-responsibility modules `lua/remote/{cmd,tail,find}.lua`. All subprocess calls go through `remote.util.run` (async, pumps event loop per CLAUDE.md Subprocess hygiene).

**Tech Stack:** Lua 5.1 (LuaJIT via Neovim 0.11+), telescope.nvim, pytest integration harness, async `vim.system` (callback form).

**Reference:** `docs/superpowers/specs/2026-04-19-sp3-fast-remote-ops-design.md`

**Working branch:** Reuse worktree at `/home/raul/worktrees/happy-nvim/feat-sp1-cockpit` (branch `feat-sp1-cockpit`). HEAD matches remote `main` after UX batch. New commits push to `main` directly.

---

## File Plan

**New files:**
- `lua/remote/cmd.lua` — `<leader>sc` flow (cmd runner, scratch buffer streaming)
- `lua/remote/tail.lua` — `<leader>sT` flow (log tail w/ `-F`/`-f` fallback)
- `lua/remote/find.lua` — `<leader>sf` flow (find over ssh + telescope picker)
- `tests/integration/test_osc52_tmux_passthrough.py`
- `tests/integration/test_ss_empty_state.py`
- `tests/integration/test_remote_cmd_runner.py`
- `tests/integration/test_remote_tail.py`
- `tests/integration/test_remote_find.py`

**Modified files:**
- `lua/clipboard/init.lua` — OSC 52 tmux DCS wrap + `:HappyCheckClipboard` command
- `lua/remote/hosts.lua` — `[+ Add host]` marker + inline-add prompt + `pick_with_callback`
- `lua/remote/init.lua` — register cmd/tail/find modules
- `lua/coach/tips.lua` — 3 new entries for sc/sT/sf
- `docs/manual-tests.md` — new §12 w/ 6 rows

---

## Ordering

```
T1 OSC 52  ──┐
T2 ss empty ─┤  ── T7 wiring ── T8 manual tests ── T9 assess+push+CI
T3 hosts.pick_with_callback ──┐
                               ├── T4 sc (uses T3)
                               ├── T5 sT (uses T3)
                               └── T6 sf (uses T3)
```

T3 must land before T4-T6. T1, T2, T3 can each be their own subagent; T4-T6 then sequential.

---

## Task 1: 30.2 — OSC 52 tmux DCS passthrough

**Files:**
- Modify: `lua/clipboard/init.lua`
- Create: `tests/integration/test_osc52_tmux_passthrough.py`

- [ ] **Step 1: Write failing test**

```python
# tests/integration/test_osc52_tmux_passthrough.py
"""30.2: OSC 52 yanks inside tmux must be wrapped in DCS passthrough so
the outer terminal (host) receives them regardless of tmux's
set-clipboard / allow-passthrough config. Outside tmux, emit raw OSC 52.

Invariant check via unit-level Lua snippet: call _encode_osc52('hello')
with TMUX set vs unset, assert the output structure."""

import os
import subprocess
import textwrap


def _run_lua(snippet, timeout=15):
    env = os.environ.copy()
    return subprocess.run(
        ['nvim', '--clean', '--headless', '-u', 'NONE', '-c', f'lua {snippet}'],
        env=env, check=True, timeout=timeout, capture_output=True, text=True,
    )


def test_osc52_wraps_in_tmux_dcs_when_tmux_set(tmp_path):
    out = tmp_path / 'osc.out'
    snippet = textwrap.dedent(f'''
        local repo = '{os.getcwd()}'
        vim.opt.rtp:prepend(repo)
        vim.env.TMUX = 'dummy-socket,1234,0'
        local cb = require('clipboard')
        local seq = cb._encode_osc52('hello')
        local fh = io.open('{out}', 'w')
        fh:write(seq or 'NIL'); fh:close()
        vim.cmd('qa!')
    ''')
    _run_lua(snippet)
    seq = out.read_text()
    # tmux DCS passthrough: starts with \ePtmux; ends with \e\\
    assert seq.startswith('\x1bPtmux;'), f'missing DCS prefix: {seq[:20]!r}'
    assert seq.endswith('\x1b\\'), f'missing ST terminator: {seq[-4:]!r}'
    # Inner OSC 52 escapes should be doubled (\e\e]52;)
    assert '\x1b\x1b]52;c;' in seq, 'inner OSC 52 not doubled for DCS passthrough'


def test_osc52_raw_when_tmux_unset(tmp_path):
    out = tmp_path / 'osc.out'
    snippet = textwrap.dedent(f'''
        local repo = '{os.getcwd()}'
        vim.opt.rtp:prepend(repo)
        vim.env.TMUX = nil
        local cb = require('clipboard')
        local seq = cb._encode_osc52('hello')
        local fh = io.open('{out}', 'w')
        fh:write(seq or 'NIL'); fh:close()
        vim.cmd('qa!')
    ''')
    _run_lua(snippet)
    seq = out.read_text()
    # Raw OSC 52: starts with \e]52;c; ends with \e\\ or \a
    assert seq.startswith('\x1b]52;c;'), f'raw OSC 52 expected, got: {seq[:20]!r}'
    assert 'Ptmux' not in seq, 'should NOT be wrapped outside tmux'


def test_happy_check_clipboard_command_registered(tmp_path):
    out = tmp_path / 'exists.out'
    snippet = textwrap.dedent(f'''
        local repo = '{os.getcwd()}'
        vim.opt.rtp:prepend(repo)
        require('clipboard').setup()
        local fh = io.open('{out}', 'w')
        fh:write(tostring(vim.fn.exists(':HappyCheckClipboard'))); fh:close()
        vim.cmd('qa!')
    ''')
    _run_lua(snippet)
    assert out.read_text().strip() == '2'
```

- [ ] **Step 2: Run to verify failure**

```bash
cd /home/raul/worktrees/happy-nvim/feat-sp1-cockpit
pytest tests/integration/test_osc52_tmux_passthrough.py -v
```

Expected: FAIL on `test_osc52_wraps_in_tmux_dcs_when_tmux_set` (no DCS prefix) + `test_happy_check_clipboard_command_registered` (cmd doesn't exist).

- [ ] **Step 3: Patch `lua/clipboard/init.lua`**

Replace `M._encode_osc52`:

```lua
function M._encode_osc52(content)
  local b64 = vim.base64.encode(content)
  if #b64 > MAX_B64 then
    return nil
  end
  -- ST terminator (`\e\\`) is standards-compliant; some strict terminals
  -- (WezTerm strict mode, recent iTerm2) reject BEL.
  local osc = string.format('\027]52;c;%s\027\\', b64)
  if vim.env.TMUX and vim.env.TMUX ~= '' then
    -- Tmux DCS passthrough: doubles inner ESCs and wraps in `\ePtmux;...\e\\`.
    -- Forces tmux to forward regardless of set-clipboard / allow-passthrough.
    osc = '\027Ptmux;' .. osc:gsub('\027', '\027\027') .. '\027\\'
  end
  return osc
end
```

And add `:HappyCheckClipboard` command at the end of `M.setup()`:

```lua
  vim.api.nvim_create_user_command('HappyCheckClipboard', function()
    local payload = 'HAPPY-CLIPBOARD-TEST-' .. os.time()
    local seq = M._encode_osc52(payload)
    if not seq then
      vim.notify('OSC 52 encoding failed (payload too large?)', vim.log.levels.ERROR)
      return
    end
    M._emit(seq)
    vim.notify(
      'Emitted OSC 52 test payload. Paste in host terminal / browser — '
        .. 'expect `' .. payload .. '`.',
      vim.log.levels.INFO
    )
  end, { desc = 'Emit a known OSC 52 payload + print expected string' })
```

- [ ] **Step 4: Run test to verify pass**

```bash
pytest tests/integration/test_osc52_tmux_passthrough.py -v
```

Expected: 3/3 PASS.

- [ ] **Step 5: Run full integration regression**

```bash
pytest tests/integration/ -v 2>&1 | tail -10
```

Expected: prior count + 3 new PASS.

- [ ] **Step 6: Commit**

```bash
git add lua/clipboard/init.lua tests/integration/test_osc52_tmux_passthrough.py
git commit -m "fix(clipboard): OSC 52 tmux DCS passthrough + :HappyCheckClipboard (closes 30.2)"
```

---

## Task 2: 30.8 — `<leader>ss` empty-state `[+ Add host]`

**Files:**
- Modify: `lua/remote/hosts.lua`
- Create: `tests/integration/test_ss_empty_state.py`

- [ ] **Step 1: Write failing test**

```python
# tests/integration/test_ss_empty_state.py
"""30.8: `<leader>ss` picker must never be empty. On empty frecency DB
+ no ~/.ssh/config, it shows a single synthetic [+ Add host] entry
(marker='add')."""

import os
import subprocess
import textwrap
import json


def _dump_list(tmp_path, empty_db=True, empty_ssh=True):
    out = tmp_path / 'list.json'
    db_path = tmp_path / 'hosts.json'
    ssh_cfg = tmp_path / 'ssh_config'
    if not empty_db:
        db_path.write_text(json.dumps({'alpha': {'visits': 3, 'last_used': 1000}}))
    if not empty_ssh:
        ssh_cfg.write_text('Host bravo\n  HostName bravo.example.com\n')
    snippet = textwrap.dedent(f'''
        local repo = '{os.getcwd()}'
        vim.opt.rtp:prepend(repo)
        local hosts = require('remote.hosts')
        hosts._set_db_path_for_test('{db_path}')
        hosts._set_ssh_config_path_for_test('{ssh_cfg}')
        local entries = hosts.list()
        local fh = io.open('{out}', 'w')
        fh:write(vim.json.encode(entries)); fh:close()
        vim.cmd('qa!')
    ''')
    subprocess.run(
        ['nvim', '--clean', '--headless', '-u', 'NONE', '-c', f'lua {snippet}'],
        check=True, timeout=15,
    )
    return json.loads(out.read_text())


def test_empty_db_and_ssh_shows_add_marker(tmp_path):
    entries = _dump_list(tmp_path, empty_db=True, empty_ssh=True)
    assert len(entries) == 1, f'expected 1 entry, got {entries}'
    assert entries[0].get('marker') == 'add', entries[0]
    assert entries[0].get('host') == '[+ Add host]', entries[0]


def test_nonempty_db_prepends_add_marker(tmp_path):
    entries = _dump_list(tmp_path, empty_db=False, empty_ssh=True)
    assert len(entries) == 2, f'expected 2 entries, got {entries}'
    assert entries[0].get('marker') == 'add'
    assert entries[1].get('host') == 'alpha'
```

- [ ] **Step 2: Run to verify failure**

Expected: module `remote.hosts.list` + test hooks don't exist yet.

- [ ] **Step 3: Patch `lua/remote/hosts.lua`**

Add test hooks near top (after `DB_PATH`):

```lua
local DB_PATH = vim.fn.stdpath('data') .. '/happy-nvim/hosts.json'
local SSH_CONFIG_PATH = vim.fn.expand('~/.ssh/config')

function M._set_db_path_for_test(p) DB_PATH = p end
function M._set_ssh_config_path_for_test(p) SSH_CONFIG_PATH = p end
```

Adjust `_read_db` to use `DB_PATH` variable (not hardcoded), and adjust `_parse_ssh_config` to use `SSH_CONFIG_PATH`:

```lua
function M._read_db()
  local f = io.open(DB_PATH, 'r')
  if not f then return {} end
  -- ...rest unchanged
end

function M._parse_ssh_config()
  local path = SSH_CONFIG_PATH
  -- ...rest unchanged
end
```

Add new `M.list()` that builds the entries w/ marker + score:

```lua
function M.list()
  local now = os.time()
  local db = M._read_db()
  local cfg = M._parse_ssh_config()
  local merged = M._merge(db, cfg, now)
  -- Convert to richer entry shape. Always prepend [+ Add host].
  local out = { { host = '[+ Add host]', marker = 'add' } }
  for _, e in ipairs(merged) do
    table.insert(out, { host = e.host, score = e.score, marker = nil })
  end
  return out
end
```

Refactor `M.pick()` to use `M.list()` and handle the add-marker:

```lua
function M.pick(callback)
  local entries = M.list()
  local pickers = require('telescope.pickers')
  local finders = require('telescope.finders')
  local actions = require('telescope.actions')
  local action_state = require('telescope.actions.state')
  local conf = require('telescope.config').values

  local function prompt_add(then_refresh)
    vim.ui.input({ prompt = 'Add host (user@host[:port]): ' }, function(input)
      if not input or input == '' then return end
      M.record(input)
      if then_refresh then
        vim.schedule(function() M.pick(callback) end)
      end
    end)
  end

  pickers.new({}, {
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
        if not sel then return end
        local e = sel.value
        if e.marker == 'add' then
          prompt_add(true)
          return
        end
        if callback then
          callback(e.host)
        else
          -- default: ssh into tmux split (existing behavior)
          local mosh = vim.fn.executable('mosh') == 1 and 'mosh' or 'ssh'
          vim.system({ 'tmux', 'new-window', mosh .. ' ' .. e.host }):wait()
        end
      end)
      map('i', '<C-a>', function() prompt_add(true) end)
      return true
    end,
  }):find()
end
```

**`M.record(host)` must already exist in the codebase** — it's what tracks frecency on successful ssh. Verify by reading `lua/remote/hosts.lua` before patching; if `record` doesn't exist, this plan misremembered its name — use the actual frecency-bump function instead. If there's no such function, create a minimal one:

```lua
function M.record(host)
  local db = M._read_db()
  db[host] = db[host] or { visits = 0, last_used = 0 }
  db[host].visits = db[host].visits + 1
  db[host].last_used = os.time()
  local dir = DB_PATH:match('(.*/)')
  if dir then vim.fn.mkdir(dir, 'p') end
  local f = io.open(DB_PATH, 'w')
  if f then f:write(vim.json.encode(db)); f:close() end
end
```

- [ ] **Step 4: Run tests to verify pass**

```bash
pytest tests/integration/test_ss_empty_state.py -v
```

Expected: 2/2 PASS.

- [ ] **Step 5: Full regression**

```bash
pytest tests/integration/ -v 2>&1 | tail -10
```

- [ ] **Step 6: Commit**

```bash
git add lua/remote/hosts.lua tests/integration/test_ss_empty_state.py
git commit -m "fix(remote): <leader>ss shows [+ Add host] on empty state + inline <C-a> add (closes 30.8)"
```

---

## Task 3: Refactor `hosts.pick` already done in Task 2 — skip

(Task 2's `M.pick(callback)` signature covers T3's deliverable. T4-T6 can proceed directly against it.)

---

## Task 4: `<leader>sc` — ad-hoc remote cmd runner

**Files:**
- Create: `lua/remote/cmd.lua`
- Create: `tests/integration/test_remote_cmd_runner.py`

- [ ] **Step 1: Write failing test**

```python
# tests/integration/test_remote_cmd_runner.py
"""<leader>sc: stub vim.system, trigger the cmd flow directly,
assert argv + scratch-buffer name."""

import os
import subprocess
import textwrap


def _run_lua(snippet, timeout=15):
    return subprocess.run(
        ['nvim', '--clean', '--headless', '-u', 'NONE', '-c', f'lua {snippet}'],
        check=True, timeout=timeout, capture_output=True, text=True,
    )


def test_sc_spawns_ssh_and_creates_scratch_buffer(tmp_path):
    argv_path = tmp_path / 'argv.out'
    bufname_path = tmp_path / 'bufname.out'
    snippet = textwrap.dedent(f'''
        local repo = '{os.getcwd()}'
        vim.opt.rtp:prepend(repo)

        -- Stub vim.system so no real ssh fires. Capture argv.
        local captured
        vim.system = function(cmd, opts, cb)
          captured = cmd
          -- Fake handle w/ :is_closing and :kill methods.
          local handle = {{ _closed = false }}
          function handle:is_closing() return self._closed end
          function handle:kill() self._closed = true end
          -- Invoke completion callback immediately w/ exit 0.
          if cb then vim.schedule(function() cb({{ code = 0 }}) end) end
          return handle
        end

        local cmd = require('remote.cmd')
        cmd._stream_to_scratch('prod01', 'df -h')

        -- Let scheduled callbacks drain.
        vim.wait(200, function() return false end, 50)

        local fh = io.open('{argv_path}', 'w')
        fh:write(vim.inspect(captured)); fh:close()

        fh = io.open('{bufname_path}', 'w')
        fh:write(vim.api.nvim_buf_get_name(0)); fh:close()
        vim.cmd('qa!')
    ''')
    _run_lua(snippet)
    argv = argv_path.read_text()
    assert '"ssh"' in argv and '"prod01"' in argv and '"df -h"' in argv, argv
    bufname = bufname_path.read_text()
    assert '[ssh prod01: df -h]' in bufname, bufname
```

- [ ] **Step 2: Verify failure**

Expected: `remote.cmd` module missing.

- [ ] **Step 3: Create `lua/remote/cmd.lua`**

```lua
-- lua/remote/cmd.lua — <leader>sc ad-hoc remote cmd runner.
local M = {}

local function append_to_buf(buf, lines)
  vim.schedule(function()
    if not vim.api.nvim_buf_is_valid(buf) then return end
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, -1, -1, false, lines)
    vim.bo[buf].modifiable = false
    local win = vim.fn.bufwinid(buf)
    if win ~= -1 then
      vim.api.nvim_win_set_cursor(win, { vim.api.nvim_buf_line_count(buf), 0 })
    end
  end)
end

function M._stream_to_scratch(host, cmd)
  local buf = vim.api.nvim_create_buf(false, true)
  local name = ('[ssh %s: %s]'):format(host, cmd)
  vim.api.nvim_buf_set_name(buf, name)
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'wipe'
  vim.cmd('sbuffer ' .. buf)

  local handle
  handle = vim.system({ 'ssh', host, cmd }, {
    text = true,
    stdout = function(_, data)
      if data then
        append_to_buf(buf, vim.split(data, '\n', { trimempty = true }))
      end
    end,
    stderr = function(_, data)
      if data then
        local prefixed = vim.tbl_map(function(l) return 'ERR: ' .. l end,
          vim.split(data, '\n', { trimempty = true }))
        append_to_buf(buf, prefixed)
      end
    end,
  }, vim.schedule_wrap(function(out)
    append_to_buf(buf, { ('--- exit %d ---'):format(out.code) })
  end))

  vim.keymap.set('n', '<C-c>', function()
    if handle and not handle:is_closing() then handle:kill('sigterm') end
  end, { buffer = buf, desc = 'kill remote cmd' })
  vim.keymap.set('n', 'q', function() vim.cmd('bd!') end, { buffer = buf, desc = 'close' })
end

function M.run_cmd()
  vim.ui.input({ prompt = 'Remote cmd: ' }, function(cmd)
    if not cmd or cmd == '' then return end
    require('remote.hosts').pick(function(host)
      M._stream_to_scratch(host, cmd)
    end)
  end)
end

return M
```

- [ ] **Step 4: Run test**

```bash
pytest tests/integration/test_remote_cmd_runner.py -v
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lua/remote/cmd.lua tests/integration/test_remote_cmd_runner.py
git commit -m "feat(remote): <leader>sc ad-hoc cmd runner (streams to scratch)"
```

---

## Task 5: `<leader>sT` — log tailer

**Files:**
- Create: `lua/remote/tail.lua`
- Create: `tests/integration/test_remote_tail.py`

- [ ] **Step 1: Write failing test**

```python
# tests/integration/test_remote_tail.py
"""<leader>sT: stub vim.system, trigger tail flow, assert argv +
scratch-buffer name format."""

import os
import subprocess
import textwrap


def test_tail_spawns_ssh_tail_F(tmp_path):
    argv_path = tmp_path / 'argv.out'
    bufname_path = tmp_path / 'bufname.out'
    snippet = textwrap.dedent(f'''
        local repo = '{os.getcwd()}'
        vim.opt.rtp:prepend(repo)
        local captured
        vim.system = function(cmd, opts, cb)
          captured = cmd
          local handle = {{ _closed = false }}
          function handle:is_closing() return self._closed end
          function handle:kill() self._closed = true end
          if cb then vim.schedule(function() cb({{ code = 0 }}) end) end
          return handle
        end
        local tail = require('remote.tail')
        tail._stream_tail('prod01', '/var/log/syslog')
        vim.wait(200, function() return false end, 50)
        local fh = io.open('{argv_path}', 'w')
        fh:write(vim.inspect(captured)); fh:close()
        fh = io.open('{bufname_path}', 'w')
        fh:write(vim.api.nvim_buf_get_name(0)); fh:close()
        vim.cmd('qa!')
    ''')
    subprocess.run(
        ['nvim', '--clean', '--headless', '-u', 'NONE', '-c', f'lua {snippet}'],
        check=True, timeout=15,
    )
    argv = argv_path.read_text()
    assert 'ssh' in argv and 'prod01' in argv
    assert 'tail -F' in argv and '/var/log/syslog' in argv, argv
    bufname = bufname_path.read_text()
    assert '[tail prod01:/var/log/syslog]' in bufname, bufname
```

- [ ] **Step 2: Verify failure**

- [ ] **Step 3: Create `lua/remote/tail.lua`**

```lua
-- lua/remote/tail.lua — <leader>sT log tailer.
local M = {}

local function append_to_buf(buf, lines)
  vim.schedule(function()
    if not vim.api.nvim_buf_is_valid(buf) then return end
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, -1, -1, false, lines)
    vim.bo[buf].modifiable = false
    local win = vim.fn.bufwinid(buf)
    if win ~= -1 then
      vim.api.nvim_win_set_cursor(win, { vim.api.nvim_buf_line_count(buf), 0 })
    end
  end)
end

local function shell_escape(s)
  return "'" .. s:gsub("'", "'\\''") .. "'"
end

function M._stream_tail(host, path)
  local buf = vim.api.nvim_create_buf(false, true)
  local name = ('[tail %s:%s]'):format(host, path)
  vim.api.nvim_buf_set_name(buf, name)
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'wipe'
  vim.cmd('sbuffer ' .. buf)

  local remote_cmd = 'tail -F ' .. shell_escape(path)

  local handle
  handle = vim.system({ 'ssh', host, remote_cmd }, {
    text = true,
    stdout = function(_, data)
      if data then append_to_buf(buf, vim.split(data, '\n', { trimempty = true })) end
    end,
    stderr = function(_, data)
      if data then
        local prefixed = vim.tbl_map(function(l) return 'ERR: ' .. l end,
          vim.split(data, '\n', { trimempty = true }))
        append_to_buf(buf, prefixed)
      end
    end,
  }, vim.schedule_wrap(function(out)
    append_to_buf(buf, { ('--- tail ended (exit %d) ---'):format(out.code) })
  end))

  vim.keymap.set('n', 'q', function()
    if handle and not handle:is_closing() then handle:kill('sigterm') end
    vim.cmd('bd!')
  end, { buffer = buf, desc = 'close tail + kill ssh' })
end

function M.tail_log()
  require('remote.hosts').pick(function(host)
    vim.ui.input({ prompt = 'Remote log path: ' }, function(path)
      if not path or path == '' then return end
      M._stream_tail(host, path)
    end)
  end)
end

return M
```

- [ ] **Step 4: Run test + regression**

- [ ] **Step 5: Commit**

```bash
git add lua/remote/tail.lua tests/integration/test_remote_tail.py
git commit -m "feat(remote): <leader>sT log tailer (tail -F streaming)"
```

---

## Task 6: `<leader>sf` — remote file-name finder

**Files:**
- Create: `lua/remote/find.lua`
- Create: `tests/integration/test_remote_find.py`

- [ ] **Step 1: Write failing test**

```python
# tests/integration/test_remote_find.py
"""<leader>sf: stub remote.util.run to return canned find output, assert
argv was correct + picker got the paths."""

import os
import subprocess
import textwrap
import json


def test_sf_builds_find_cmd_and_returns_paths(tmp_path):
    argv_path = tmp_path / 'argv.out'
    paths_path = tmp_path / 'paths.out'
    snippet = textwrap.dedent(f'''
        local repo = '{os.getcwd()}'
        vim.opt.rtp:prepend(repo)

        -- Stub remote.util.run with canned output.
        local captured
        package.loaded['remote.util'] = {{
          run = function(cmd, opts, timeout)
            captured = cmd
            return {{
              code = 0,
              stdout = '/etc/hosts\\n/etc/passwd\\n/etc/resolv.conf\\n',
              stderr = '',
            }}
          end,
        }}

        -- Stub the telescope picker so we can inspect the result list.
        local picker_paths
        package.loaded['telescope.pickers'] = {{
          new = function(_, opts)
            picker_paths = opts.finder._results or opts.finder.results
            return {{ find = function() end }}
          end,
        }}
        package.loaded['telescope.finders'] = {{
          new_table = function(spec) return {{ _results = spec.results, results = spec.results }} end,
        }}
        package.loaded['telescope.config'] = {{ values = {{ generic_sorter = function() return nil end }} }}
        package.loaded['telescope.actions'] = {{ select_default = {{ replace = function() end }} }}
        package.loaded['telescope.actions.state'] = {{ get_selected_entry = function() end }}

        local find = require('remote.find')
        find._list_then_pick('prod01', '/etc')
        vim.wait(100, function() return false end, 25)

        local fh = io.open('{argv_path}', 'w')
        fh:write(vim.inspect(captured)); fh:close()
        fh = io.open('{paths_path}', 'w')
        fh:write(vim.json.encode(picker_paths or {{}})); fh:close()
        vim.cmd('qa!')
    ''')
    subprocess.run(
        ['nvim', '--clean', '--headless', '-u', 'NONE', '-c', f'lua {snippet}'],
        check=True, timeout=15,
    )
    argv = argv_path.read_text()
    assert 'ssh' in argv and 'prod01' in argv
    assert 'find ' in argv and '-type f' in argv and '-maxdepth 6' in argv, argv
    assert "'/etc'" in argv, f'path not shell-escaped: {argv}'
    paths = json.loads(paths_path.read_text())
    assert paths == ['/etc/hosts', '/etc/passwd', '/etc/resolv.conf'], paths
```

- [ ] **Step 2: Verify failure**

- [ ] **Step 3: Create `lua/remote/find.lua`**

```lua
-- lua/remote/find.lua — <leader>sf remote file-name finder.
local M = {}

local function shell_escape(s)
  return "'" .. s:gsub("'", "'\\''") .. "'"
end

function M._list_then_pick(host, dir)
  local util = require('remote.util')
  local cmd = {
    'ssh',
    host,
    ('find %s -type f -maxdepth 6 2>/dev/null'):format(shell_escape(dir)),
  }
  local result = util.run(cmd, { text = true }, 30000)
  if result.code ~= 0 then
    vim.notify('remote find failed: ' .. (result.stderr or ''), vim.log.levels.ERROR)
    return
  end
  local paths = vim.split(result.stdout or '', '\n', { trimempty = true })
  if #paths == 0 then
    vim.notify('no files under ' .. dir, vim.log.levels.INFO)
    return
  end
  local pickers = require('telescope.pickers')
  local finders = require('telescope.finders')
  local conf = require('telescope.config').values
  local actions = require('telescope.actions')
  local action_state = require('telescope.actions.state')
  pickers
    .new({}, {
      prompt_title = ('remote find: %s:%s'):format(host, dir),
      finder = finders.new_table({ results = paths }),
      sorter = conf.generic_sorter({}),
      attach_mappings = function(bufnr)
        actions.select_default:replace(function()
          local sel = action_state.get_selected_entry()
          actions.close(bufnr)
          if sel and sel[1] then
            vim.cmd('edit scp://' .. host .. '/' .. sel[1])
          end
        end)
        return true
      end,
    })
    :find()
end

function M.find_file()
  require('remote.hosts').pick(function(host)
    vim.ui.input(
      { prompt = 'Remote dir to search (default: /): ', default = '/' },
      function(dir)
        if not dir or dir == '' then return end
        M._list_then_pick(host, dir)
      end
    )
  end)
end

return M
```

- [ ] **Step 4: Run test + regression**

- [ ] **Step 5: Commit**

```bash
git add lua/remote/find.lua tests/integration/test_remote_find.py
git commit -m "feat(remote): <leader>sf remote file-name finder (find + telescope)"
```

---

## Task 7: Wire keymaps + coach tips

**Files:**
- Modify: `lua/remote/init.lua`
- Modify: `lua/coach/tips.lua`

- [ ] **Step 1: Read current state**

READ both files. `lua/remote/init.lua` currently has `M.setup()` calling `hosts.setup()`, `dirs.setup()`, `browse.setup()`, `grep.setup()`. Add `cmd.setup()`, `tail.setup()`, `find.setup()` if those modules expose `.setup()` — BUT they don't in the current plan. Each new module only exports its top-level fn (`run_cmd`, `tail_log`, `find_file`). The keymap registration has to live somewhere. Options:

**Option A (chosen):** register keymaps directly in `lua/remote/init.lua`:

```lua
function M.setup()
  require('remote.hosts').setup()
  require('remote.dirs').setup()
  require('remote.browse').setup()
  require('remote.grep').setup()
  vim.keymap.set('n', '<leader>sc', function() require('remote.cmd').run_cmd() end,
    { desc = 'Remote: ad-hoc cmd (streams to scratch)' })
  vim.keymap.set('n', '<leader>sT', function() require('remote.tail').tail_log() end,
    { desc = 'Remote: log tail (tail -F)' })
  vim.keymap.set('n', '<leader>sf', function() require('remote.find').find_file() end,
    { desc = 'Remote: find file (find + telescope)' })
end
```

- [ ] **Step 2: Apply `lua/remote/init.lua` edit**

Edit `lua/remote/init.lua` to match the block above.

- [ ] **Step 3: Append to `lua/coach/tips.lua`**

Insert before the closing `}` of the tips array:

```lua
  -- SP3 remote additions
  {
    keys = '<leader>sc',
    desc = 'remote ad-hoc cmd (streams to scratch buffer)',
    category = 'remote',
  },
  {
    keys = '<leader>sT',
    desc = 'remote log tail (tail -F streaming)',
    category = 'remote',
  },
  {
    keys = '<leader>sf',
    desc = 'remote file-name finder (find + telescope)',
    category = 'remote',
  },
```

(These entries go multi-line because stylua column-width=100 trips single-line versions.)

- [ ] **Step 4: Smoke test**

```bash
nvim --headless -c "lua require('remote').setup(); print(vim.fn.exists('<Plug>'))" -c "qa!" 2>&1 | tail
```

Better: run the tips coverage test to confirm new keymaps are listed:

```bash
pytest tests/integration/test_coach_tips_coverage.py -v
```

Expected: still 3/3 pass (the existing assertions don't require the new SP3 keys, but the "tips grew" assertion keeps passing).

- [ ] **Step 5: Commit**

```bash
git add lua/remote/init.lua lua/coach/tips.lua
git commit -m "feat(remote): wire <leader>sc/sT/sf keymaps + cheatsheet entries"
```

---

## Task 8: Manual-tests rows

**Files:**
- Modify: `docs/manual-tests.md`

- [ ] **Step 1: Append new §12**

Use Edit tool. Insert immediately before the final `---` + `Last updated:` trailer:

```markdown
## 12. Fast remote ops (SP3)

- [ ] Inside tmux+mosh+nvim, yank a line (yy) → host (outside mosh) `Cmd+V` / `Ctrl+V` pastes the line (30.2)
- [ ] `:HappyCheckClipboard` emits a `HAPPY-CLIPBOARD-TEST-<ts>` payload; paste in host terminal shows that exact string (30.2)
- [ ] Fresh install (no ~/.ssh/config, empty frecency DB) → `<leader>ss` shows `[+ Add host]` entry. `<Enter>` prompts for `user@host[:port]`, submission adds + re-opens picker (30.8)
- [ ] `<leader>sc` → enter `df -h` → pick host → scratch buffer streams output, ends with `--- exit 0 ---`. `q` closes; `<C-c>` during a long cmd kills + shows non-zero exit
- [ ] `<leader>sT` → pick host → enter `/var/log/syslog` → scratch streams log lines live. `q` closes + kills tail
- [ ] `<leader>sf` → pick host → `/etc` → telescope lists files up to 6 levels deep. `<Enter>` opens selected as `scp://`
```

Update `Last updated:` trailer to:

```
Last updated: SP3 fast remote ops landed 2026-04-19.
```

- [ ] **Step 2: Commit**

```bash
git add docs/manual-tests.md
git commit -m "docs: manual-tests rows for SP3 fast remote ops (30.2, 30.8 + new primitives)"
```

---

## Task 9: Assess + push + CI + close todos

- [ ] **Step 1: Full assess**

```bash
cd /home/raul/worktrees/happy-nvim/feat-sp1-cockpit
bash scripts/assess.sh 2>&1 | tail -20
```

Expected: `ASSESS: ALL LAYERS PASS`. If stylua lint fails on new code, fix formatting (column width 100; multi-line long table entries).

- [ ] **Step 2: Push**

```bash
git fetch https://github.com/raulfrk/happy-nvim.git main
git log --oneline HEAD ^FETCH_HEAD   # show commits ahead

git push https://github.com/raulfrk/happy-nvim.git feat-sp1-cockpit:main
```

Rebase on non-fast-forward + re-assess + re-push as needed.

- [ ] **Step 3: Poll CI**

```bash
mkdir -p $TMPDIR/gh-cache
XDG_CACHE_HOME=$TMPDIR/gh-cache gh run list --repo raulfrk/happy-nvim --branch main --limit 1
XDG_CACHE_HOME=$TMPDIR/gh-cache gh run watch <RUN_ID> --repo raulfrk/happy-nvim --exit-status
```

- [ ] **Step 4: Close todos**

After CI green:

```
mcp__plugin_proj_proj__todo_complete --todo_ids ["30.2","30.8"] --note "SP3 fast remote ops landed, CI green (run <id>). 30.2: OSC 52 tmux DCS passthrough + :HappyCheckClipboard. 30.8: [+ Add host] synthetic entry + inline <C-a> add."
```

Leave 30.13 open (SP2 + SP4 still pending).

---

## Self-review

**Spec coverage:**
- §4 (30.2 OSC 52) → Task 1 ✓
- §5 (30.8 empty state) → Task 2 ✓
- §6 (sc runner) → Task 4 ✓
- §7 (sT tail) → Task 5 ✓
- §8 (sf finder) → Task 6 ✓
- §9 (wiring) → Task 7 ✓
- §10 (tests) → Tasks 1/2/4/5/6 ✓
- §Manual Test Additions → Task 8 ✓

**Placeholder scan:** none.

**Type consistency:**
- `M.pick(callback)` signature defined in Task 2, used in Tasks 4/5/6 ✓
- `append_to_buf(buf, lines)` helper duplicated in cmd.lua + tail.lua — intentional (one file's responsibility each; no cross-import of a private util). Could be hoisted to `remote/util.lua` as a follow-up.
- `shell_escape` duplicated in tail.lua + find.lua — same rationale.

---

## Manual Test Additions

(Listed in Task 8 above. Implementing subagent appends to
`docs/manual-tests.md` as part of Task 8's commit.)

```markdown
## 12. Fast remote ops (SP3)

- [ ] Inside tmux+mosh+nvim, yank a line (yy) → host (outside mosh) `Cmd+V` / `Ctrl+V` pastes the line (30.2)
- [ ] `:HappyCheckClipboard` emits a `HAPPY-CLIPBOARD-TEST-<ts>` payload; paste in host terminal shows that exact string (30.2)
- [ ] Fresh install (no ~/.ssh/config, empty frecency DB) → `<leader>ss` shows `[+ Add host]` entry. `<Enter>` prompts for `user@host[:port]`, submission adds + re-opens picker (30.8)
- [ ] `<leader>sc` → enter `df -h` → pick host → scratch buffer streams output, ends with `--- exit 0 ---`. `q` closes; `<C-c>` during a long cmd kills + shows non-zero exit
- [ ] `<leader>sT` → pick host → enter `/var/log/syslog` → scratch streams log lines live. `q` closes + kills tail
- [ ] `<leader>sf` → pick host → `/etc` → telescope lists files up to 6 levels deep. `<Enter>` opens selected as `scp://`
```
