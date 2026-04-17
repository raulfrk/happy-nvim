# Multi-Project Claude — Phase 2: Picker + Create/Kill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Surface all active `cc-*` tmux sessions in a telescope picker (`<leader>cl`), spawn ad-hoc sessions for arbitrary cwds (`<leader>cn`), and kill the current project's session with a confirm prompt (`<leader>ck`).

**Architecture:** New `lua/tmux/sessions.lua` owns session discovery + enumeration (list all `cc-*` sessions on the server, with metadata like creation time). New `lua/tmux/picker.lua` builds the telescope picker that consumes that list and runs `display-popup` on selection. `lua/tmux/claude_popup.lua` grows a `kill()` helper; `lua/plugins/tmux.lua` adds the three keymaps.

**Tech Stack:** Lua 5.1, Neovim 0.11+, tmux 3.2+, telescope.nvim (already a dep). No new plugins.

---

## File Structure

```
lua/tmux/
├── project.lua          # unchanged (Phase 1)
├── claude_popup.lua     # MODIFIED — add kill()
├── sessions.lua         # NEW — list cc-* sessions + metadata
├── picker.lua           # NEW — telescope picker for list / attach
└── ...

lua/plugins/
└── tmux.lua             # MODIFIED — wire <leader>cl/cn/ck

tests/
├── tmux_sessions_spec.lua       # NEW — plenary tests for list parsing
└── integration/
    └── test_multiproject_picker.py  # NEW — real tmux, 2 sessions, list finds both
```

`sessions.lua` is pure data-shape code (parses `tmux list-sessions -F ...` output). `picker.lua` is the telescope-specific UI (depends on `sessions.lua`). Keeping them separate means unit tests for parsing don't require telescope to be loaded.

---

## Task 1: Build `lua/tmux/sessions.lua`

**Files:**
- Create: `lua/tmux/sessions.lua`
- Create: `tests/tmux_sessions_spec.lua`

**Context:** Enumerate all tmux sessions whose name starts with `cc-` (our multi-project convention from Phase 1). Return a table of `{ name, slug, created_ts, first_pane_id }` per session. Uses `tmux list-sessions -F '#{session_name}|#{session_created}|#{pane_id}'`. Parsing the format output is pure string work — testable without tmux running.

- [ ] **Step 1: Write the failing test**

Create `tests/tmux_sessions_spec.lua`:

```lua
-- tests/tmux_sessions_spec.lua
-- Unit tests for lua/tmux/sessions.lua. The parser takes raw
-- `tmux list-sessions -F ...` output; no tmux invocation needed.

describe('tmux.sessions._parse_list', function()
  local sessions = require('tmux.sessions')

  it('returns empty list for empty input', function()
    assert.are.same({}, sessions._parse_list(''))
  end)

  it('returns empty list for blank-only input', function()
    assert.are.same({}, sessions._parse_list('\n\n  \n'))
  end)

  it('ignores non cc- prefixed sessions', function()
    local raw = 'main|1700000000|%0\nscratch|1700000001|%3'
    assert.are.same({}, sessions._parse_list(raw))
  end)

  it('parses a single cc- session', function()
    local raw = 'cc-happy-nvim|1700000000|%4'
    local parsed = sessions._parse_list(raw)
    assert.are.equal(1, #parsed)
    assert.are.equal('cc-happy-nvim', parsed[1].name)
    assert.are.equal('happy-nvim', parsed[1].slug)
    assert.are.equal(1700000000, parsed[1].created_ts)
    assert.are.equal('%4', parsed[1].first_pane_id)
  end)

  it('parses multiple cc- sessions and ignores non-cc ones', function()
    local raw = table.concat({
      'main|1700000000|%0',
      'cc-happy-nvim|1700000100|%4',
      'cc-other-repo|1700000200|%7',
      '',
    }, '\n')
    local parsed = sessions._parse_list(raw)
    assert.are.equal(2, #parsed)
    assert.are.equal('cc-happy-nvim', parsed[1].name)
    assert.are.equal('cc-other-repo', parsed[2].name)
  end)

  it('tolerates extra whitespace', function()
    local raw = '  cc-happy-nvim|1700000000|%4  '
    assert.are.equal('cc-happy-nvim', sessions._parse_list(raw)[1].name)
  end)
end)
```

- [ ] **Step 2: Run the failing test**

Run:
```bash
cd /home/raul/worktrees/happy-nvim/feat-v1-implementation
XDG_DATA_HOME="$PWD/.tests" XDG_CONFIG_HOME="$PWD/.tests/config" \
  XDG_CACHE_HOME="$PWD/.tests/cache" XDG_STATE_HOME="$PWD/.tests/state" \
  nvim --headless -u tests/minimal_init.lua \
  -c "PlenaryBustedFile tests/tmux_sessions_spec.lua" -c 'qa!' 2>&1 | tail -10
```

Expected: all 6 tests FAIL with `module 'tmux.sessions' not found`.

- [ ] **Step 3: Write the implementation**

Create `lua/tmux/sessions.lua`:

```lua
-- lua/tmux/sessions.lua — enumerate multi-project Claude tmux sessions.
-- Every cc-<slug> session created by lua/tmux/claude_popup.lua surfaces
-- here for the <leader>cl picker.
local M = {}

local PREFIX = 'cc-'

-- Parse output of `tmux list-sessions -F '#{session_name}|#{session_created}|#{pane_id}'`.
-- Returns a list of { name, slug, created_ts, first_pane_id } tables.
-- Ignores sessions whose name does not start with the cc- prefix.
function M._parse_list(raw)
  local out = {}
  for line in (raw or ''):gmatch('[^\n]+') do
    local trimmed = line:match('^%s*(.-)%s*$')
    if trimmed ~= '' then
      local name, created, pane = trimmed:match('^([^|]+)|([^|]+)|(.+)$')
      if name and name:sub(1, #PREFIX) == PREFIX then
        table.insert(out, {
          name = name,
          slug = name:sub(#PREFIX + 1),
          created_ts = tonumber(created) or 0,
          first_pane_id = pane,
        })
      end
    end
  end
  return out
end

-- Live query: returns the same shape as _parse_list on the active tmux server.
function M.list()
  local res = vim.system({
    'tmux',
    'list-sessions',
    '-F',
    '#{session_name}|#{session_created}|#{pane_id}',
  }, { text = true }):wait()
  if res.code ~= 0 then
    return {}
  end
  return M._parse_list(res.stdout or '')
end

return M
```

- [ ] **Step 4: Run tests to verify pass**

Same command as Step 2. Expected tail: `Success: 6  Failed : 0  Errors : 0`.

- [ ] **Step 5: Stylua + commit**

```bash
export STYLUA=/tmp/npmcache/_npx/2d7ba7d0047acad9/node_modules/.bin/stylua
$STYLUA lua/tmux/sessions.lua tests/tmux_sessions_spec.lua
$STYLUA --check lua/tmux/sessions.lua tests/tmux_sessions_spec.lua && echo STYLUA_OK
git add lua/tmux/sessions.lua tests/tmux_sessions_spec.lua
git commit -m "feat(tmux/sessions): enumerate cc-* tmux sessions for picker

New lua/tmux/sessions.lua exposes list() returning an array of
{ name, slug, created_ts, first_pane_id } tables, one per cc-*
tmux session on the server. Pure string parser (_parse_list)
unit-tested with 6 plenary cases."
```

---

## Task 2: Extend `lua/tmux/claude_popup.lua` with `kill()`

**Files:**
- Modify: `lua/tmux/claude_popup.lua`

**Context:** Current API: `exists`, `ensure`, `open`, `fresh`, `pane_id`. `fresh()` already kills+respawns, but `<leader>ck` needs pure kill w/o auto-respawn, plus an optional session-name override so the picker can kill sessions other than the current project's.

- [ ] **Step 1: Read current module**

Run:
```bash
cat lua/tmux/claude_popup.lua
```

Note the `local function session()` helper returning `project.session_name()`. The new `kill` takes an optional name; when nil, it falls back to the current project's.

- [ ] **Step 2: Add the `kill` function**

Find the `M.fresh` function:

```lua
function M.fresh()
  if M.exists() then
    sys({ 'tmux', 'kill-session', '-t', session() })
  end
  M.open()
end
```

Add immediately after it:

```lua

-- Kill a session by name (defaults to current project's). Returns true on
-- success or if the session already didn't exist.
function M.kill(name)
  name = name or session()
  local res = sys({ 'tmux', 'has-session', '-t', name })
  if res.code ~= 0 then
    return true -- already gone
  end
  local r = sys({ 'tmux', 'kill-session', '-t', name })
  return r.code == 0
end
```

- [ ] **Step 3: Stylua + commit**

```bash
$STYLUA lua/tmux/claude_popup.lua
$STYLUA --check lua/tmux/claude_popup.lua && echo STYLUA_OK
git add lua/tmux/claude_popup.lua
git commit -m "feat(tmux/claude_popup): add kill(name?) for <leader>ck + picker

New M.kill(name) — if name is nil, uses project.session_name()
(the current nvim buffer's project). Returns true on success or
when the session already didn't exist. Used by <leader>ck (Task 4)
and by the picker's delete action (Task 3)."
```

---

## Task 3: Build `lua/tmux/picker.lua` — telescope picker for `<leader>cl`

**Files:**
- Create: `lua/tmux/picker.lua`

**Context:** Telescope picker that lists every `cc-*` session from `tmux.sessions.list()` and opens the selected one via `tmux display-popup -E 'tmux attach -t <name>'`. A `<C-x>` action on a selected entry kills that session without closing the picker (so the user can tidy up multiple sessions in one sitting).

Entry display format: `"<slug>  (N min ago)"` — short slug, relative age from `created_ts`. Sort newest first.

- [ ] **Step 1: Write the module**

Create `lua/tmux/picker.lua`:

```lua
-- lua/tmux/picker.lua — telescope picker listing all cc-* Claude sessions.
-- <leader>cl opens this; Enter attaches via display-popup; <C-x> kills in-place.
local M = {}

local function rel_age(ts)
  if not ts or ts == 0 then
    return '?'
  end
  local secs = os.time() - ts
  if secs < 60 then
    return secs .. 's ago'
  elseif secs < 3600 then
    return math.floor(secs / 60) .. 'm ago'
  elseif secs < 86400 then
    return math.floor(secs / 3600) .. 'h ago'
  end
  return math.floor(secs / 86400) .. 'd ago'
end

function M.open()
  local ok, pickers = pcall(require, 'telescope.pickers')
  if not ok then
    vim.notify('telescope.nvim not available', vim.log.levels.ERROR)
    return
  end
  local finders = require('telescope.finders')
  local actions = require('telescope.actions')
  local action_state = require('telescope.actions.state')
  local conf = require('telescope.config').values

  local sessions = require('tmux.sessions').list()
  if #sessions == 0 then
    vim.notify('no Claude sessions open (press <leader>cp to start one)', vim.log.levels.INFO)
    return
  end
  -- Newest first
  table.sort(sessions, function(a, b)
    return (a.created_ts or 0) > (b.created_ts or 0)
  end)

  pickers
    .new({}, {
      prompt_title = 'Claude sessions',
      finder = finders.new_table({
        results = sessions,
        entry_maker = function(s)
          return {
            value = s,
            display = string.format('%-30s  (%s)', s.slug, rel_age(s.created_ts)),
            ordinal = s.slug,
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
          vim.system({
            'tmux',
            'display-popup',
            '-E',
            '-w',
            '85%',
            '-h',
            '85%',
            'tmux attach -t ' .. entry.value.name,
          }):wait()
        end)
        map({ 'i', 'n' }, '<C-x>', function()
          local entry = action_state.get_selected_entry()
          if not entry then
            return
          end
          require('tmux.claude_popup').kill(entry.value.name)
          -- Refresh the picker by closing + reopening
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

- [ ] **Step 2: Stylua + commit**

```bash
$STYLUA lua/tmux/picker.lua
$STYLUA --check lua/tmux/picker.lua && echo STYLUA_OK
git add lua/tmux/picker.lua
git commit -m "feat(tmux/picker): telescope picker for <leader>cl

Lists all cc-* sessions via tmux.sessions.list() sorted newest
first. Display: '<slug>  (N min ago)'. Actions:
- <CR>: tmux display-popup attach
- <C-x>: kill session in-place, re-open picker

Graceful fallback when telescope missing (notify, no crash).
Tests for picker UI deferred to Phase 3 integration suite."
```

---

## Task 4: Wire `<leader>cl`, `<leader>cn`, `<leader>ck` in `lua/plugins/tmux.lua`

**Files:**
- Modify: `lua/plugins/tmux.lua`
- Modify: `lua/plugins/whichkey.lua`

**Context:**
- `<leader>cl` → `tmux.picker.open()`. No guard needed (picker shows a friendly message if no sessions).
- `<leader>cn` → prompts for a project slug via `vim.ui.input`, creates `cc-<slug>` in the current buffer's cwd, opens popup. Purpose: let the user spawn a Claude for a directory they're NOT currently cd'd into (e.g. quickly check a side project).
- `<leader>ck` → confirms via `vim.ui.select`, kills the current project's session.

The `<leader>cn` helper needs a small addition to `claude_popup.lua`: a `spawn_named(name, cwd)` function that skips the project.session_name lookup. Keep it inline in `plugins/tmux.lua` since it's a one-liner specific to the cn binding — we don't need another module export.

- [ ] **Step 1: Read current plugin spec**

Run:
```bash
cat lua/plugins/tmux.lua
```

Note the `lazy_cmd` helper + the existing `keys = {}` block with `<leader>cc/cp/cf/cs/ce/cC/cP` entries.

- [ ] **Step 2: Add cn/cl/ck keymaps to the `keys = {}` block**

Find the last `<leader>c` entry (should be `<leader>cP` from Phase 2 popup work):

```lua
    {
      '<leader>cP',
      lazy_cmd('tmux.claude_popup', 'fresh'),
      desc = 'Claude: fresh popup (kill + respawn)',
    },
```

Add immediately after it (before the `<leader>tg` entries):

```lua
    {
      '<leader>cl',
      lazy_cmd('tmux.picker', 'open'),
      desc = 'Claude: list + attach sessions',
    },
    {
      '<leader>cn',
      function()
        vim.ui.input({ prompt = 'Project slug for new Claude: ' }, function(slug)
          if not slug or slug == '' then
            return
          end
          local safe = slug:gsub('[^%w%-]', '-'):gsub('%-+', '-')
          local name = 'cc-' .. safe
          local cwd = vim.fn.expand('%:p:h')
          if cwd == '' then
            cwd = vim.fn.getcwd()
          end
          vim.system({ 'tmux', 'new-session', '-d', '-s', name, '-c', cwd, 'claude' }):wait()
          vim.system({
            'tmux',
            'display-popup',
            '-E',
            '-w',
            '85%',
            '-h',
            '85%',
            'tmux attach -t ' .. name,
          }):wait()
        end)
      end,
      desc = 'Claude: new named session (prompts for slug)',
    },
    {
      '<leader>ck',
      function()
        local popup = require('tmux.claude_popup')
        if not popup.exists() then
          vim.notify('no Claude session for this project', vim.log.levels.INFO)
          return
        end
        vim.ui.select({ 'Yes, kill it', 'No, cancel' }, {
          prompt = 'Kill current project\'s Claude session?',
        }, function(choice)
          if choice == 'Yes, kill it' then
            popup.kill()
            vim.notify('killed ' .. require('tmux.project').session_name(), vim.log.levels.INFO)
          end
        end)
      end,
      desc = 'Claude: kill current project\'s session',
    },
```

- [ ] **Step 3: Register a `cl` group hint in whichkey (optional sub-binding visual polish)**

No new whichkey groups needed — the existing `<leader>c` group (`Claude (tmux pane)`) already covers these children. which-key picks up `desc` strings automatically from lazy's `keys = {}`.

- [ ] **Step 4: Headless smoke check**

Run (verifies the keymap file parses cleanly; can't exercise the picker without telescope):

```bash
XDG_DATA_HOME="$PWD/.tests" XDG_CONFIG_HOME="$PWD/.tests/config" \
  XDG_CACHE_HOME="$PWD/.tests/cache" XDG_STATE_HOME="$PWD/.tests/state" \
  nvim --headless -c 'qa!' 2>&1 | tail -5
```

Expected: clean exit, no `E\d+:` errors.

- [ ] **Step 5: Stylua + commit**

```bash
$STYLUA lua/plugins/tmux.lua
$STYLUA --check lua/plugins/tmux.lua && echo STYLUA_OK
git add lua/plugins/tmux.lua
git commit -m "feat(tmux): wire <leader>cl (picker) / cn (new) / ck (kill)

Three new <leader>c* keymaps:
- <leader>cl -> tmux.picker.open (telescope list of cc-* sessions)
- <leader>cn -> vim.ui.input for slug, spawns cc-<slug> in cwd
- <leader>ck -> vim.ui.select confirm, kills current project's
  session via claude_popup.kill()

which-key shows all three under the existing 'Claude (tmux pane)'
group by reading the desc strings."
```

---

## Task 5: Integration test — picker lists both sessions

**Files:**
- Create: `tests/integration/test_multiproject_picker.py`

**Context:** Can't render telescope UI in pytest (no TTY). Test the data layer: call `tmux.sessions.list()` from headless nvim after creating two sessions, assert both appear with correct metadata.

- [ ] **Step 1: Write the test**

Create `tests/integration/test_multiproject_picker.py`:

```python
"""Integration test: sessions.list() returns all cc-* sessions.

Skips the telescope UI (no TTY in pytest). The picker (lua/tmux/picker.lua)
just consumes sessions.list(); if the data layer is correct, the UI binding
is trivial wiring. End-to-end UI test is deferred to Phase 5 once an
interactive-terminal harness lands.
"""
from __future__ import annotations

import json
import os
import subprocess
from pathlib import Path

import pytest

from .helpers import tmx

REPO_ROOT = Path(__file__).resolve().parents[2]


def _list_from_nvim(tmux_socket: str) -> list[dict]:
    """Call tmux.sessions.list() from headless nvim on the test socket."""
    # Wrapper script so nvim's `tmux ...` calls use the test socket
    wrapper = Path(os.environ["PATH"].split(":", 1)[0]) / "tmux"
    if not wrapper.exists():
        # Fallback: set up a one-shot wrapper in a scratch dir
        scratch = Path(os.environ.get("HAPPY_TEST_SCRATCH", "/tmp"))
        wrapper = scratch / "tmux-wrap"
        wrapper.write_text(
            f"#!/usr/bin/env bash\nexec /usr/bin/tmux -L {tmux_socket} \"$@\"\n"
        )
        wrapper.chmod(0o755)
        os.environ["PATH"] = f"{wrapper.parent}:{os.environ['PATH']}"

    out = subprocess.check_output(
        [
            "nvim",
            "--headless",
            "--clean",
            "-c",
            f"lua vim.opt.rtp:prepend('{REPO_ROOT}')",
            "-c",
            "lua vim.fn.writefile({vim.json.encode(require('tmux.sessions').list())}, '/tmp/happy-sessions.json')",
            "-c",
            "qa!",
        ],
        text=True,
        stderr=subprocess.STDOUT,
    )
    # Re-run via the wrapped tmux so sessions.list sees our test server
    return json.loads(Path("/tmp/happy-sessions.json").read_text())


def test_list_returns_both_sessions(tmux_socket: str, tmp_path: Path):
    # Set up two cc-* sessions directly on the test server
    tmx(tmux_socket, "new-session", "-d", "-s", "cc-alpha", "claude --delay 0")
    tmx(tmux_socket, "new-session", "-d", "-s", "cc-beta", "claude --delay 0")
    # Sanity: both exist via tmux directly
    for name in ("cc-alpha", "cc-beta"):
        assert (
            subprocess.run(
                ["tmux", "-L", tmux_socket, "has-session", "-t", name],
                check=False,
            ).returncode
            == 0
        ), f"{name} missing"

    try:
        os.environ["HAPPY_TEST_SCRATCH"] = str(tmp_path)
        sessions = _list_from_nvim(tmux_socket)
        names = sorted(s["name"] for s in sessions)
        slugs = sorted(s["slug"] for s in sessions)
        assert "cc-alpha" in names, f"cc-alpha missing from {names}"
        assert "cc-beta" in names, f"cc-beta missing from {names}"
        # slugs have the prefix stripped
        assert "alpha" in slugs
        assert "beta" in slugs
        # each has a numeric created_ts and pane id
        for s in sessions:
            if s["name"] in ("cc-alpha", "cc-beta"):
                assert isinstance(s["created_ts"], (int, float))
                assert s["first_pane_id"].startswith("%")
    finally:
        for s in ("cc-alpha", "cc-beta"):
            subprocess.run(
                ["tmux", "-L", tmux_socket, "kill-session", "-t", s],
                check=False,
                capture_output=True,
            )
```

- [ ] **Step 2: Run the test**

```bash
python3 -m pytest tests/integration/test_multiproject_picker.py -v
```

Expected: `1 passed`. If the test skips because tmux < 3.2, that's acceptable locally; CI has tmux 3.4.

Likely failure fixes:
- `/tmp/happy-sessions.json` permission: fine in sandbox + CI.
- `vim.json.encode` not available on older nvim: we require 0.11, which has it.
- Wrapper script not picked up: the fallback block in `_list_from_nvim` creates one; verify `os.environ["PATH"]` is mutated before the `subprocess.check_output` call.

- [ ] **Step 3: Run `bash scripts/assess.sh`**

Expected: ALL LAYERS PASS.

- [ ] **Step 4: Commit**

```bash
git add tests/integration/test_multiproject_picker.py
git commit -m "test(integration): sessions.list returns all cc-* sessions

Creates cc-alpha + cc-beta directly on the test tmux socket,
invokes require('tmux.sessions').list() from headless nvim via a
tmux wrapper shim, asserts both appear in the returned list w/
correct names, slugs, timestamps, pane ids."
```

---

## Task 6: Push + verify green CI

**Files:** none.

- [ ] **Step 1: FF main + push**

```bash
cd /home/raul/projects/happy-nvim
git checkout main
git merge --ff-only feat/v1-implementation
git push git@github.com:raulfrk/happy-nvim.git main:main
```

- [ ] **Step 2: Capture + poll**

```bash
sleep 6
RUN_ID=$(gh api repos/raulfrk/happy-nvim/actions/runs --jq '.workflow_runs[0].id')
echo "$RUN_ID"
while true; do
  s=$(gh api "repos/raulfrk/happy-nvim/actions/runs/$RUN_ID" --jq '"\(.status)|\(.conclusion)"')
  echo "$(date +%H:%M:%S) $s"
  case "$s" in completed*) break;; esac
  sleep 60
done
```

- [ ] **Step 3: Verify per-job status**

```bash
gh api "repos/raulfrk/happy-nvim/actions/runs/$RUN_ID/jobs" --jq '.jobs[] | "\(.name): \(.conclusion)"'
```

All should be `success`.

- [ ] **Step 4: Close todos**

```
todo_complete 3.3 3.4 3.5
```

3.8 stays open (state decoration; needs Phase 3 idle daemon).

---

## Self-Review

**1. Spec coverage:**

| Todo | Task |
|---|---|
| #3.3 `<leader>cl` picker | Task 1 (sessions.lua) + Task 3 (picker.lua) + Task 4 (keymap) + Task 5 (test) |
| #3.4 `<leader>cn` new session | Task 4 (inline fn in keys block) |
| #3.5 `<leader>ck` kill current project's session | Task 2 (kill fn) + Task 4 (keymap + confirm) |

**2. Placeholder scan:** no TBDs, no "similar to Task N". Every code block complete. `cn` handler is inline rather than a separate module because it's one screen of logic used in one place.

**3. Type consistency:**
- `sessions.list()` returns `{ name, slug, created_ts, first_pane_id }` tables — matches `picker.lua` use (`entry.value.name`, `entry.value.slug`, `entry.value.created_ts`) and the integration test assertions.
- `claude_popup.kill(name)` optional-arg signature — matches picker.lua call with explicit name + `<leader>ck` call with no arg (defaults to current project).
- PREFIX constant `'cc-'` consistent between `sessions.lua` and Phase 1's `project.lua` (both produce `cc-<slug>`).
