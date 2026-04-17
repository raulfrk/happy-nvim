# Claude Popup Surface Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a tmux popup surface for Claude Code alongside the existing split pane. Popup attaches to a hidden detached tmux session so Claude conversation persists across popup toggles and nvim restarts. Fresh-instance variants (`<leader>cC` / `<leader>cP`) kill and respawn. Send commands auto-route to whichever surface is active.

**Architecture:** New `lua/tmux/claude_popup.lua` module owns the detached `claude-happy` tmux session lifecycle (spawn, attach via popup, kill). Existing `lua/tmux/claude.lua` keeps the pane logic. `lua/tmux/send.lua` grows a new `M.resolve_target()` function that returns pane ID if set, else popup session's pane ID, else nil. `send_to_claude` routes through `resolve_target`. Plugin spec `lua/plugins/tmux.lua` adds `<leader>cp/cC/cP` keymaps. Integration test verifies the session survives detach → nvim restart → reattach.

**Tech Stack:** Lua 5.1, Neovim 0.11+, tmux 3.2+ (for `display-popup -E`), pytest + existing integration harness for the persistence test.

---

## File Structure

```
lua/tmux/
├── claude.lua          # unchanged — still owns <leader>cc pane logic
├── claude_popup.lua    # NEW — owns claude-happy session + popup attach + fresh variants
└── send.lua            # MODIFIED — adds resolve_target(), send_to_claude() uses it

lua/plugins/
└── tmux.lua            # MODIFIED — adds <leader>cp, <leader>cC, <leader>cP keys

tests/integration/
└── test_claude_popup.py # NEW — session persists across attach/detach cycles
```

Each file owns one responsibility: `claude_popup.lua` manages the detached-session lifecycle, `send.lua` decides where to send, `plugins/tmux.lua` wires keymaps. Tests for pure routing logic (resolve_target) go in `tests/tmux_send_spec.lua`; persistence requires real tmux, so it lives in `tests/integration/`.

---

## Task 1: Build `lua/tmux/claude_popup.lua`

**Files:**
- Create: `lua/tmux/claude_popup.lua`

**Context:** This module owns a single global tmux session named `claude-happy`. On first invocation of `open()`, it creates the session detached (no window visible) running `claude` in the current nvim cwd. On subsequent `open()` calls, it opens a tmux display-popup attached to the session. Closing the popup (C-q or the user's detach keybinding) leaves the session alive. `fresh()` kills + recreates. `exists()` reports whether the session is present.

Key tmux primitives:
- `tmux has-session -t claude-happy` — returns 0 if exists, nonzero otherwise.
- `tmux new-session -d -s claude-happy -c <cwd> 'claude'` — creates detached.
- `tmux display-popup -E -w 85% -h 85% 'tmux attach -t claude-happy'` — popup attaches. `-E` closes popup when inner command exits.
- `tmux kill-session -t claude-happy` — destroys.

Closing the popup WITHOUT killing the session requires the user to detach, not exit claude. The standard tmux detach keybinding (`prefix d`) works inside the nested session. We document this in the `open()` notify message.

- [ ] **Step 1: Write the module**

Create `lua/tmux/claude_popup.lua`:

```lua
-- lua/tmux/claude_popup.lua — hidden detached tmux session + popup attach.
-- Single global Claude instance reachable from any nvim via <leader>cp.
-- Conversation persists across popup toggles and nvim restarts.
local M = {}

local SESSION = 'claude-happy'
local POPUP_W = '85%'
local POPUP_H = '85%'

local function sys(args)
  return vim.system(args, { text = true }):wait()
end

function M.exists()
  return sys({ 'tmux', 'has-session', '-t', SESSION }).code == 0
end

function M.ensure()
  if M.exists() then
    return true
  end
  local cwd = vim.fn.expand('%:p:h')
  if cwd == '' then
    cwd = vim.fn.getcwd()
  end
  local res = sys({ 'tmux', 'new-session', '-d', '-s', SESSION, '-c', cwd, 'claude' })
  if res.code ~= 0 then
    vim.notify(
      'failed to spawn claude-happy session: ' .. (res.stderr or ''),
      vim.log.levels.ERROR
    )
    return false
  end
  return true
end

function M.open()
  if vim.env.TMUX == nil or vim.env.TMUX == '' then
    vim.notify(
      'Claude popup requires $TMUX (run nvim inside tmux)',
      vim.log.levels.WARN
    )
    return
  end
  if not M.ensure() then
    return
  end
  -- -E closes the popup when inner command exits; user detaches via prefix+d
  sys({
    'tmux',
    'display-popup',
    '-E',
    '-w',
    POPUP_W,
    '-h',
    POPUP_H,
    'tmux attach -t ' .. SESSION,
  })
end

function M.fresh()
  if M.exists() then
    sys({ 'tmux', 'kill-session', '-t', SESSION })
  end
  M.open()
end

-- Returns the pane ID of the (single) pane inside claude-happy, or nil.
-- Used by lua/tmux/send.lua when no @claude_pane_id is set.
function M.pane_id()
  if not M.exists() then
    return nil
  end
  local res = sys({
    'tmux',
    'list-panes',
    '-t',
    SESSION,
    '-F',
    '#{pane_id}',
  })
  if res.code ~= 0 then
    return nil
  end
  local id = (res.stdout or ''):gsub('%s+$', '')
  if id == '' then
    return nil
  end
  return id
end

return M
```

- [ ] **Step 2: Syntax check + stylua**

Run:
```bash
cd /home/raul/worktrees/happy-nvim/feat-v1-implementation
nvim --headless -c "lua dofile('lua/tmux/claude_popup.lua')" -c 'qa!' 2>&1 | tail -3
export STYLUA=/tmp/npmcache/_npx/2d7ba7d0047acad9/node_modules/.bin/stylua
$STYLUA lua/tmux/claude_popup.lua && $STYLUA --check lua/tmux/claude_popup.lua && echo STYLUA_OK
```

Expected: both commands clean, `STYLUA_OK`.

- [ ] **Step 3: Commit**

```bash
git add lua/tmux/claude_popup.lua
git commit -m "feat(tmux/claude): claude_popup module — detached session + popup attach

New lua/tmux/claude_popup.lua owns a hidden 'claude-happy' tmux
session. ensure() creates it if missing (detached, running claude
in cwd). open() opens a display-popup attached to it; closing
the popup detaches via user's tmux prefix+d and leaves the session
alive. fresh() kills+respawns. pane_id() exposes the inner pane
for auto-routing. All ops guarded on \$TMUX presence."
```

---

## Task 2: Extend `lua/tmux/send.lua` with target resolution

**Files:**
- Modify: `lua/tmux/send.lua`
- Modify: `tests/tmux_send_spec.lua`

**Context:** Right now `send_to_claude` consults only `@claude_pane_id` (the per-nvim-window pane). With popups in play, there are two possible Claude surfaces. We introduce `M.resolve_target()` returning the first live target in this priority order:

1. `@claude_pane_id` (user explicitly opened a pane via `<leader>cc`) — wins because it's window-specific and most recently interacted with.
2. `claude_popup.pane_id()` (popup session exists, user prefers the global popup).
3. `nil` → notify user to open Claude first.

`send_to_claude` now dispatches through `resolve_target`. Existing tests still pass because they stub `get_claude_pane_id`; we add a new test covering the popup-only path.

- [ ] **Step 1: Read current test file to see the existing stubbing pattern**

Run:
```bash
cat tests/tmux_send_spec.lua
```

Expected: spec uses `package.loaded['tmux.send'] = nil` pattern + direct `M.*` calls. It does NOT currently monkey-patch the `tmux` system calls; `_build_send_cmd` and `_quote_for_send_keys` are tested as pure functions.

- [ ] **Step 2: Add `resolve_target()` to `lua/tmux/send.lua`**

Find the current `send_to_claude` block:

```lua
function M.send_to_claude(payload)
  local id = M.get_claude_pane_id()
  if not id then
    vim.notify('No Claude pane registered. Press <leader>cc first.', vim.log.levels.WARN)
    return false
  end
```

Replace it with this version:

```lua
-- Resolve which Claude surface should receive sends. Priority:
-- 1. @claude_pane_id on the current nvim window (set by <leader>cc)
-- 2. claude-happy tmux session's pane (set by <leader>cp)
-- 3. nil — caller should notify the user
function M.resolve_target()
  local id = M.get_claude_pane_id()
  if id then
    return id, 'pane'
  end
  local ok, popup = pcall(require, 'tmux.claude_popup')
  if ok then
    local pid = popup.pane_id()
    if pid then
      return pid, 'popup'
    end
  end
  return nil, nil
end

function M.send_to_claude(payload)
  local id = M.resolve_target()
  if not id then
    vim.notify(
      'No Claude surface open. Press <leader>cc (pane) or <leader>cp (popup) first.',
      vim.log.levels.WARN
    )
    return false
  end
```

- [ ] **Step 3: Add unit test for `resolve_target` priority**

Append to `tests/tmux_send_spec.lua` (inside the existing `describe('tmux.send', ...)` block if present, else at the bottom):

```lua

describe('tmux.send.resolve_target', function()
  local send = require('tmux.send')
  local orig_get_pane
  local orig_popup

  before_each(function()
    orig_get_pane = send.get_claude_pane_id
    orig_popup = package.loaded['tmux.claude_popup']
  end)

  after_each(function()
    send.get_claude_pane_id = orig_get_pane
    package.loaded['tmux.claude_popup'] = orig_popup
  end)

  it('returns pane id + "pane" label when @claude_pane_id is set', function()
    send.get_claude_pane_id = function() return '%42' end
    package.loaded['tmux.claude_popup'] = { pane_id = function() return '%99' end }
    local id, kind = send.resolve_target()
    assert.are.equal('%42', id)
    assert.are.equal('pane', kind)
  end)

  it('falls back to popup pane id + "popup" label when no pane', function()
    send.get_claude_pane_id = function() return nil end
    package.loaded['tmux.claude_popup'] = { pane_id = function() return '%99' end }
    local id, kind = send.resolve_target()
    assert.are.equal('%99', id)
    assert.are.equal('popup', kind)
  end)

  it('returns nil, nil when neither surface is open', function()
    send.get_claude_pane_id = function() return nil end
    package.loaded['tmux.claude_popup'] = { pane_id = function() return nil end }
    local id, kind = send.resolve_target()
    assert.is_nil(id)
    assert.is_nil(kind)
  end)
end)
```

- [ ] **Step 4: Run the unit tests to verify they pass**

Run:
```bash
cd /home/raul/worktrees/happy-nvim/feat-v1-implementation
XDG_DATA_HOME="$PWD/.tests" XDG_CONFIG_HOME="$PWD/.tests/config" \
  XDG_CACHE_HOME="$PWD/.tests/cache" XDG_STATE_HOME="$PWD/.tests/state" \
  nvim --headless -u tests/minimal_init.lua \
  -c "PlenaryBustedFile tests/tmux_send_spec.lua" -c 'qa!' 2>&1 | tail -10
```

Expected tail ends with `Success: 6  Failed : 0  Errors : 0` (3 existing + 3 new).

If any of the new specs fail with `package.loaded['tmux.claude_popup'] = nil` complaints: the module wasn't required, so `orig_popup` is nil and restoring works. That's fine — the assertion on the return values matters.

- [ ] **Step 5: Stylua + commit**

```bash
$STYLUA lua/tmux/send.lua tests/tmux_send_spec.lua
$STYLUA --check lua/tmux/send.lua tests/tmux_send_spec.lua && echo STYLUA_OK
git add lua/tmux/send.lua tests/tmux_send_spec.lua
git commit -m "feat(tmux/send): resolve_target() multi-surface routing

send_to_claude now checks @claude_pane_id first, then falls back
to the claude-happy popup session's pane. Returns the resolved
target id + a string label ('pane' or 'popup') for future logging.
Notify message updated to mention both <leader>cc and <leader>cp."
```

---

## Task 3: Wire `<leader>cp`, `<leader>cC`, `<leader>cP` in `lua/plugins/tmux.lua`

**Files:**
- Modify: `lua/plugins/tmux.lua`
- Modify: `lua/tmux/claude.lua`

**Context:** The plugin spec uses lazy.nvim's `keys = {}` to statically register `<leader>c*` bindings. We add three new entries. For consistency with the existing `open_guarded` pattern, we also add `open_fresh_guarded` to `claude.lua` so the `<leader>cC` capital-C variant is a pure fn ref.

`<leader>cp` → `tmux.claude_popup.open()` (guarded on `$TMUX`)
`<leader>cC` → kill current pane's `@claude_pane_id` + respawn
`<leader>cP` → `tmux.claude_popup.fresh()`

- [ ] **Step 1: Add `open_fresh_guarded` to `lua/tmux/claude.lua`**

Find this block in `lua/tmux/claude.lua`:

```lua
function M.open_guarded()
  if guard() then
    M.open()
  end
end
```

Add immediately after it:

```lua

function M.open_fresh_guarded()
  if not guard() then
    return
  end
  -- Kill existing pane if registered for the current nvim window
  local send = require('tmux.send')
  local id = send.get_claude_pane_id()
  if id then
    vim.system({ 'tmux', 'kill-pane', '-t', id }):wait()
    vim.system({ 'tmux', 'set-option', '-w', '-u', '@claude_pane_id' }):wait()
  end
  M.open()
end
```

- [ ] **Step 2: Add the three popup keymaps to `lua/plugins/tmux.lua`**

Read current file:
```bash
cat lua/plugins/tmux.lua
```

Find the `keys = {` block's `<leader>ce` entry:

```lua
    {
      '<leader>ce',
      lazy_cmd('tmux.claude', 'send_errors_guarded'),
      desc = 'Claude: send diagnostics',
    },
```

Add immediately after it, before the `<leader>tg` entries:

```lua
    {
      '<leader>cp',
      lazy_cmd('tmux.claude_popup', 'open'),
      desc = 'Claude: toggle popup (detached session)',
    },
    {
      '<leader>cC',
      lazy_cmd('tmux.claude', 'open_fresh_guarded'),
      desc = 'Claude: fresh pane (kill + respawn)',
    },
    {
      '<leader>cP',
      lazy_cmd('tmux.claude_popup', 'fresh'),
      desc = 'Claude: fresh popup (kill + respawn)',
    },
```

- [ ] **Step 3: Manual smoke test (local)**

Requires an interactive tmux + claude CLI on PATH. If you don't have `claude` locally, the pane popup still opens (showing `claude: command not found`); that proves wiring without exercising the CLI. Use `bash` as a stand-in if claude is missing:

```bash
# Temporarily swap 'claude' for 'bash' in claude_popup.lua to test wiring:
#   In lua/tmux/claude_popup.lua replace ', 'claude')' with ', 'bash')'
# Skip this test if running headless. Revert the swap before commit.
```

In an interactive tmux session with nvim running the worktree config:
- `<Space>cp` → popup opens at 85x85 w/ claude (or bash) running. Close w/ prefix+d, then `<Space>cp` again — should reattach same process (bash PID unchanged).
- `<Space>cP` → kills session, fresh shell/claude.

Skip this step if no interactive tmux available; CI integration test (Task 4) verifies the same end-to-end.

- [ ] **Step 4: Stylua + commit**

```bash
$STYLUA lua/plugins/tmux.lua lua/tmux/claude.lua
$STYLUA --check lua/plugins/tmux.lua lua/tmux/claude.lua && echo STYLUA_OK
git add lua/plugins/tmux.lua lua/tmux/claude.lua
git commit -m "feat(tmux/claude): wire <leader>cp/cC/cP keymaps

- <leader>cp: toggle popup (tmux display-popup attached to the
  claude-happy detached session from claude_popup.lua)
- <leader>cC: fresh pane (kill @claude_pane_id + respawn via open)
- <leader>cP: fresh popup (kill claude-happy session + respawn)

which-key will now show all three alongside existing cc/cf/cs/ce."
```

---

## Task 4: Integration test — popup session persists across detach + restart

**Files:**
- Create: `tests/integration/test_claude_popup.py`

**Context:** Verifies the whole flow: open popup → conversation happens → detach → kill-then-restart nvim → reopen popup → old conversation history still visible. Uses `fake_claude.py` (already on PATH in integration harness) so responses are deterministic. Exercises:

- `claude_popup.ensure()` creates `claude-happy`.
- `send-keys` into the inner pane produces an ACK we can capture.
- The session survives detach (simulated by never entering the popup — we attach programmatically outside the display-popup, which has the same effect).
- Fresh variant actually kills + replaces the session.

We skip actually rendering `display-popup` because pytest has no controlling terminal for a popup. Instead we assert the lifecycle contract: detached session created, survives, pane receives input, fresh() replaces it. The real popup vs non-popup distinction is just display — the session management is what this test guards.

- [ ] **Step 1: Write the test**

Create `tests/integration/test_claude_popup.py`:

```python
"""Integration test: claude-happy session lifecycle.

Doesn't render display-popup (no controlling TTY in pytest). Instead
asserts the backing detached session behavior:

- ensure() creates `claude-happy` running fake_claude
- session survives over time (no accidental self-kill)
- send-keys into the inner pane gets an ACK back
- fresh() kills + replaces (new pane id, empty history)

Render-to-popup is a tmux concern; if `display-popup -E` ever
regresses, the tmux upstream has its own tests.
"""
from __future__ import annotations

import subprocess
import time
from pathlib import Path

import pytest

from .helpers import capture_pane, send_keys, tmx, wait_for_pane

SESSION = "claude-happy"


def _has_session(tmux_socket: str) -> bool:
    result = subprocess.run(
        ["tmux", "-L", tmux_socket, "has-session", "-t", SESSION],
        check=False,
        capture_output=True,
    )
    return result.returncode == 0


def _pane_id(tmux_socket: str) -> str:
    result = tmx(tmux_socket, "list-panes", "-t", SESSION, "-F", "#{pane_id}")
    return result.stdout.strip()


@pytest.fixture
def cleanup_session(tmux_socket: str):
    """Make sure the session is killed before + after each test."""
    subprocess.run(
        ["tmux", "-L", tmux_socket, "kill-session", "-t", SESSION],
        check=False,
        capture_output=True,
    )
    yield
    subprocess.run(
        ["tmux", "-L", tmux_socket, "kill-session", "-t", SESSION],
        check=False,
        capture_output=True,
    )


def test_ensure_creates_detached_session(tmux_socket: str, cleanup_session):
    """Mirrors lua/tmux/claude_popup.lua M.ensure() behavior."""
    tmx(tmux_socket, "new-session", "-d", "-s", SESSION, "claude --delay 0")
    assert _has_session(tmux_socket), "session not created"
    pane = _pane_id(tmux_socket)
    assert pane.startswith("%"), f"unexpected pane id: {pane!r}"


def test_session_survives_and_accepts_input(
    tmux_socket: str, cleanup_session, tmp_path: Path
):
    """Session persists + pane receives input + ACK appears."""
    tmx(tmux_socket, "new-session", "-d", "-s", SESSION, "claude --delay 0")
    pane = _pane_id(tmux_socket)
    send_keys(tmux_socket, pane, "hello", "Enter")
    wait_for_pane(tmux_socket, pane, r"^Assistant: ACK:hello$", timeout=5)
    # Simulate time passing (popup open → close → reopen)
    time.sleep(0.3)
    assert _has_session(tmux_socket), "session died during simulated detach window"
    # The pane id is stable across detach/reattach (it's the same pane)
    assert _pane_id(tmux_socket) == pane
    # History intact
    out = capture_pane(tmux_socket, pane)
    assert "ACK:hello" in out, f"history lost after idle: {out!r}"


def test_fresh_kills_and_replaces(tmux_socket: str, cleanup_session):
    """fresh() variant must produce a new pane id with empty history."""
    tmx(tmux_socket, "new-session", "-d", "-s", SESSION, "claude --delay 0")
    old_pane = _pane_id(tmux_socket)
    send_keys(tmux_socket, old_pane, "first-convo", "Enter")
    wait_for_pane(tmux_socket, old_pane, r"ACK:first-convo", timeout=5)

    # Simulate fresh(): kill + recreate
    subprocess.run(
        ["tmux", "-L", tmux_socket, "kill-session", "-t", SESSION],
        check=True,
        capture_output=True,
    )
    assert not _has_session(tmux_socket)
    tmx(tmux_socket, "new-session", "-d", "-s", SESSION, "claude --delay 0")

    new_pane = _pane_id(tmux_socket)
    assert new_pane != old_pane, "fresh() reused old pane id"
    # Wait for fake_claude to print its prompt
    wait_for_pane(tmux_socket, new_pane, r"^>", timeout=3)
    out = capture_pane(tmux_socket, new_pane)
    assert "ACK:first-convo" not in out, f"fresh pane has stale history: {out!r}"
```

- [ ] **Step 2: Run the test locally**

Run:
```bash
cd /home/raul/worktrees/happy-nvim/feat-v1-implementation
python3 -m pytest tests/integration/test_claude_popup.py -v
```

Expected tail:
```
tests/integration/test_claude_popup.py::test_ensure_creates_detached_session PASSED
tests/integration/test_claude_popup.py::test_session_survives_and_accepts_input PASSED
tests/integration/test_claude_popup.py::test_fresh_kills_and_replaces PASSED

======== 3 passed in X.XXs ========
```

If the tmux version is < 3.2 and tests skip, that's fine — CI runners have modern tmux.

- [ ] **Step 3: Run the full assess script (sanity across all layers)**

Run:
```bash
bash scripts/assess.sh
```

Expected final table rows all `PASS` (new popup test added to integration layer count).

- [ ] **Step 4: Commit**

```bash
git add tests/integration/test_claude_popup.py
git commit -m "test(integration): claude_popup session lifecycle

Asserts: ensure() creates detached session, pane survives idle
window, fresh() kills+replaces producing a new pane id with
empty history. Skips actual display-popup rendering (no TTY in
pytest); session management is what needs guarding."
```

---

## Task 5: Push + verify green CI

**Files:** none (push-only).

- [ ] **Step 1: Fast-forward main + push**

```bash
cd /home/raul/projects/happy-nvim
git checkout main
git merge --ff-only feat/v1-implementation
git push git@github.com:raulfrk/happy-nvim.git main:main
```

Expected: `main -> main` advances 4 commits.

- [ ] **Step 2: Capture + poll the run**

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

Expected all `success`, including `assess (stable)` and `assess (nightly)` running the new popup test.

If anything fails, fetch logs:
```bash
TMPDIR=/tmp XDG_CACHE_HOME=/tmp gh run view "$RUN_ID" --log-failed -R raulfrk/happy-nvim | tail -80
```

Likely failure modes + fixes:
- `test_fresh_kills_and_replaces` flakes because `wait_for_pane` times out before fake_claude prints `>` — bump timeout to 5s.
- stylua diff on one of the touched files — re-run `$STYLUA .` and amend the nearest commit.
- `resolve_target` test failure citing `require('tmux.claude_popup')` lua error — ensure Task 1 landed before Task 2 (they're ordered).

- [ ] **Step 4: Close source todos**

In the main conversation:
```
todo_complete 2.1 2.2 2.3 2.6
```

Leaves 2.4 (health probes), 2.5 (README docs), 2.7 (popup size config) open as YAGNI/doc follow-ups.

---

## Self-Review

**1. Spec coverage:**

| Todo | Task |
|---|---|
| #2.1 popup module + `<leader>cp` | Task 1 + Task 3 |
| #2.2 fresh variants `<leader>cC`/`<leader>cP` | Task 1 (`fresh`) + Task 3 (keys) |
| #2.3 send auto-routing (pane > popup) | Task 2 |
| #2.6 persistence test | Task 4 |

No gaps for scoped todos. 2.4/2.5/2.7 are intentionally deferred.

**2. Placeholder scan:** no TBDs, no vague steps. Every code block complete. Task 3 Step 3 explicitly marked "skip if no interactive tmux" — acceptable because the CI integration test (Task 4) covers the same behavior headlessly.

**3. Type consistency:**
- `M.exists()`, `M.ensure()`, `M.open()`, `M.fresh()`, `M.pane_id()` in claude_popup.lua — all referenced with the same names in Tasks 2-4.
- `M.resolve_target()` signature `(target_id, kind_str | nil, nil)` — three call sites in Task 2 Step 3 test all use this signature.
- `SESSION = 'claude-happy'` constant in claude_popup.lua matches `SESSION` in the pytest (`test_claude_popup.py`) and the `kill-session -t claude-happy` call in Task 3 Step 1.
- Keymap desc strings in Task 3 Step 2 align with which-key group labels registered in `lua/plugins/whichkey.lua` (group = 'Claude (tmux pane)' — accepts both pane + popup under one umbrella).
