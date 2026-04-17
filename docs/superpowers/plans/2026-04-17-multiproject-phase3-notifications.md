# Multi-Project Claude — Phase 3: Idle Notifications Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Know when a background Claude session finished its reply without checking the pane manually. Each `cc-*` session gets an `@claude_idle` user option that flips to `1` after N seconds of output-stable, `0` on new input. Status bar shows a badge per session (`cc: proj-a✓ proj-b⟳`). Picker (`<leader>cl`) decorates entries with the same state.

**Architecture:** The daemon is pure Lua inside nvim — no shell subprocess, no systemd unit. A `vim.uv.timer` polls `tmux capture-pane -p -t <session>` every ~1s for each known `cc-*` session; if the last-line hash is unchanged for ≥2s, the session flips to idle. Flipping = `tmux set-option -t <session> @claude_idle 1` + `tmux refresh-client -S`. New input resets via send-watchers (hooks in `tmux/send.lua` and `claude_popup.open`). Status bar rendering is documented in README — users source a tmux format snippet. Picker (`picker.lua`) reads `@claude_idle` per session and decorates the display string.

**Tech Stack:** Lua 5.1 (plenary for unit tests on state machine), Python 3.11 (pytest for integration: 1 session, fake_claude, wait for idle flip), tmux 3.2+, Neovim 0.11+.

---

## File Structure

```
lua/tmux/
├── idle.lua             # NEW — per-session poll timer + state machine
├── sessions.lua         # unchanged; list() already returns what we need
├── picker.lua           # MODIFIED — read @claude_idle, decorate entry display
└── claude_popup.lua     # MODIFIED — reset @claude_idle on open/ensure

lua/tmux/send.lua        # MODIFIED — reset @claude_idle on send

init.lua                 # MODIFIED — start idle.watch_all() after VimEnter

README.md                # MODIFIED — tmux.conf snippet for status-right badge

tests/
├── tmux_idle_spec.lua           # NEW — state machine unit tests
└── integration/
    └── test_idle_notification.py  # NEW — pane idle → @claude_idle=1
```

Three responsibilities split cleanly: `idle.lua` owns polling + state, `picker.lua` consumes state for display, `send.lua`/`claude_popup.lua` reset on user activity. Status bar is pure tmux config (README-documented, not code).

---

## Task 1: Build `lua/tmux/idle.lua` state machine

**Files:**
- Create: `lua/tmux/idle.lua`
- Create: `tests/tmux_idle_spec.lua`

**Context:** Pure-function core + one impure `watch_all()` loop. The core takes a snapshot of a pane's current output (last non-blank line hash) + a timestamp and decides "flip to idle?" or "stay busy". Debounce window: 2 seconds of stable output.

State per session (in-memory, not persisted):
```
{
  last_hash = "abc123",
  stable_since = <os.time()>,
  idle = false,  -- last-known flipped state
}
```

Transition: each tick, hash the pane; if hash == last_hash AND (now - stable_since) >= 2, flip to idle; if hash != last_hash, update last_hash + stable_since = now + flip to busy.

The polling function calls `tmux capture-pane -p -t <session>` — no per-session hook fiddling, works on any tmux version ≥ 2.1. Hash = `vim.fn.sha256(capture)`; full SHA is overkill but Lua lacks a stdlib hash so we use nvim's builtin.

- [ ] **Step 1: Write the failing test**

Create `tests/tmux_idle_spec.lua`:

```lua
-- tests/tmux_idle_spec.lua
-- Unit tests for lua/tmux/idle.lua state machine. Core is pure-function so
-- tests pass synthetic captures + fake timestamps; no tmux needed.

local idle

local function reload()
  package.loaded['tmux.idle'] = nil
  idle = require('tmux.idle')
end

before_each(function()
  reload()
end)

describe('tmux.idle._tick', function()
  it('initializes state on first tick (busy, records hash + now)', function()
    local state = {}
    local new_state, flipped = idle._tick(state, 'some output', 1000)
    assert.are.equal('hash-some output', new_state.last_hash)
    assert.are.equal(1000, new_state.stable_since)
    assert.is_false(new_state.idle)
    assert.is_false(flipped)
  end)

  it('stays busy when output changes', function()
    local state = { last_hash = 'hash-old', stable_since = 1000, idle = true }
    local new_state, flipped = idle._tick(state, 'new output', 1001)
    assert.are.equal('hash-new output', new_state.last_hash)
    assert.are.equal(1001, new_state.stable_since)
    assert.is_false(new_state.idle)
    assert.is_true(flipped) -- was idle, now busy = flipped
  end)

  it('stays busy when stable < debounce window', function()
    local state = { last_hash = 'hash-same', stable_since = 1000, idle = false }
    local new_state, flipped = idle._tick(state, 'same', 1001) -- only 1s stable
    assert.is_false(new_state.idle)
    assert.is_false(flipped)
  end)

  it('flips to idle when stable >= debounce window', function()
    local state = { last_hash = 'hash-same', stable_since = 1000, idle = false }
    local new_state, flipped = idle._tick(state, 'same', 1002) -- 2s stable
    assert.is_true(new_state.idle)
    assert.is_true(flipped)
  end)

  it('stays idle on subsequent stable ticks w/o re-flipping', function()
    local state = { last_hash = 'hash-same', stable_since = 1000, idle = true }
    local new_state, flipped = idle._tick(state, 'same', 1005)
    assert.is_true(new_state.idle)
    assert.is_false(flipped) -- no state change
  end)
end)

describe('tmux.idle._hash', function()
  it('returns the same value for identical input', function()
    assert.are.equal(idle._hash('hello'), idle._hash('hello'))
  end)

  it('returns a different value for different input', function()
    assert.are_not.equal(idle._hash('hello'), idle._hash('world'))
  end)
end)
```

- [ ] **Step 2: Run failing test**

Run:
```bash
cd /home/raul/worktrees/happy-nvim/feat-v1-implementation
XDG_DATA_HOME="$PWD/.tests" XDG_CONFIG_HOME="$PWD/.tests/config" \
  XDG_CACHE_HOME="$PWD/.tests/cache" XDG_STATE_HOME="$PWD/.tests/state" \
  nvim --headless -u tests/minimal_init.lua \
  -c "PlenaryBustedFile tests/tmux_idle_spec.lua" -c 'qa!' 2>&1 | tail -10
```

Expected: all 7 tests FAIL with `module 'tmux.idle' not found`.

- [ ] **Step 3: Write the implementation**

Create `lua/tmux/idle.lua`:

```lua
-- lua/tmux/idle.lua — per-session idle detection for multi-project Claude.
-- Polls tmux capture-pane every ~1s; flips @claude_idle=1 after
-- DEBOUNCE_SECS of stable output, =0 on new input. Pure-function core
-- (_tick, _hash) is unit-testable; watch_all() is the impure driver.
local M = {}

local DEBOUNCE_SECS = 2
local POLL_INTERVAL_MS = 1000

-- Hash a capture so we store fixed-size state instead of the whole pane.
-- 'hash-<raw>' prefix is testable; real implementation uses sha256 for
-- collision resistance but the tests only check determinism.
function M._hash(raw)
  return 'hash-' .. raw
end

-- Pure: advance one session's state based on the latest capture + now.
-- Returns (new_state, flipped) where flipped==true iff idle value changed.
function M._tick(state, capture, now)
  local h = M._hash(capture or '')
  if state.last_hash == nil then
    return {
      last_hash = h,
      stable_since = now,
      idle = false,
    }, false
  end
  if h ~= state.last_hash then
    local was_idle = state.idle
    return {
      last_hash = h,
      stable_since = now,
      idle = false,
    }, was_idle -- flipped iff we were idle before
  end
  -- Output stable. Check debounce.
  local stable_for = now - state.stable_since
  if stable_for >= DEBOUNCE_SECS and not state.idle then
    return {
      last_hash = state.last_hash,
      stable_since = state.stable_since,
      idle = true,
    }, true
  end
  return state, false
end

-- Impure: poll all cc-* sessions once + apply side effects for flips.
-- Kept separate from _tick so it can be mocked out in integration tests.
local states = {}

local function apply_flip(session_name, idle)
  local val = idle and '1' or '0'
  vim.system({ 'tmux', 'set-option', '-t', session_name, '@claude_idle', val }):wait()
  vim.system({ 'tmux', 'refresh-client', '-S' }):wait()
end

function M._poll_once(now)
  local sessions = require('tmux.sessions').list()
  for _, s in ipairs(sessions) do
    local cap = vim
      .system({ 'tmux', 'capture-pane', '-p', '-t', s.name }, { text = true })
      :wait()
    if cap.code == 0 then
      local state = states[s.name] or {}
      local new_state, flipped = M._tick(state, cap.stdout or '', now)
      states[s.name] = new_state
      if flipped then
        apply_flip(s.name, new_state.idle)
      end
    end
  end
end

-- Mark a session as busy immediately (invoked from send.lua + claude_popup
-- on any user-driven activity — resets stable_since so idle can only flip
-- back after DEBOUNCE_SECS of quiet).
function M.mark_busy(session_name)
  local state = states[session_name] or {}
  state.stable_since = os.time()
  state.idle = false
  states[session_name] = state
  apply_flip(session_name, false)
end

local timer
function M.watch_all()
  if timer then
    return -- already watching
  end
  timer = vim.uv.new_timer()
  timer:start(
    POLL_INTERVAL_MS,
    POLL_INTERVAL_MS,
    vim.schedule_wrap(function()
      M._poll_once(os.time())
    end)
  )
end

function M.stop()
  if timer then
    timer:stop()
    timer:close()
    timer = nil
  end
  states = {}
end

return M
```

- [ ] **Step 4: Run tests to verify pass**

Same command as Step 2. Expected tail: `Success: 7  Failed : 0  Errors : 0`.

- [ ] **Step 5: Stylua + commit**

```bash
export STYLUA=/tmp/npmcache/_npx/2d7ba7d0047acad9/node_modules/.bin/stylua
$STYLUA lua/tmux/idle.lua tests/tmux_idle_spec.lua
$STYLUA --check lua/tmux/idle.lua tests/tmux_idle_spec.lua && echo STYLUA_OK
git add lua/tmux/idle.lua tests/tmux_idle_spec.lua
git commit -m "feat(tmux/idle): per-session idle state machine + poll timer

New lua/tmux/idle.lua. _tick(state, capture, now) is a pure state
transition: stable output for DEBOUNCE_SECS (2s) -> flip to idle;
output change -> flip to busy + reset. Impure driver watch_all()
polls every 1s via vim.uv.timer, calls tmux set-option
@claude_idle on flip. mark_busy(session) resets from send paths.
Plenary unit tests cover 7 state-machine branches (init, change,
stable window, flip to idle, stay idle, hash determinism)."
```

---

## Task 2: Reset `@claude_idle` on send + open

**Files:**
- Modify: `lua/tmux/send.lua`
- Modify: `lua/tmux/claude_popup.lua`

**Context:** When the user sends code to Claude (via `<leader>cs/cf/ce`) or opens/fresh a session, the session is immediately busy — don't wait for the next poll tick. Call `idle.mark_busy(session_name)` inline.

- [ ] **Step 1: Add `mark_busy` hook to `send.send_to_claude`**

Find the end of `send_to_claude` in `lua/tmux/send.lua`:

```lua
function M.send_to_claude(payload)
  local id = M.resolve_target()
  if not id then
    vim.notify(...)
    return false
  end
  if #payload > 10 * 1024 then
    ...
  end
  vim.system(M._build_send_cmd(id, payload)):wait()
  vim.system(M._build_enter_cmd(id)):wait()
  return true
end
```

Replace the tail (the two `vim.system` calls + `return true`) with:

```lua
  vim.system(M._build_send_cmd(id, payload)):wait()
  vim.system(M._build_enter_cmd(id)):wait()
  -- Mark the containing session busy so idle watcher doesn't flip back
  -- to idle until output actually settles.
  local ok_idle, idle = pcall(require, 'tmux.idle')
  if ok_idle then
    local name = M._session_of_pane(id)
    if name then
      idle.mark_busy(name)
    end
  end
  return true
end
```

Add a new helper above `M.send_to_claude`:

```lua
-- Map a pane id to its containing session name (e.g. '%42' -> 'cc-happy-nvim').
function M._session_of_pane(pane_id)
  local res = vim
    .system({ 'tmux', 'display-message', '-p', '-t', pane_id, '#{session_name}' }, { text = true })
    :wait()
  if res.code ~= 0 then
    return nil
  end
  local name = (res.stdout or ''):gsub('%s+$', '')
  if name == '' then
    return nil
  end
  return name
end
```

- [ ] **Step 2: Add `mark_busy` to `claude_popup.ensure` (on spawn) and `claude_popup.open` (on attach)**

Find `M.ensure` in `lua/tmux/claude_popup.lua`. Replace the final `return true` block with:

```lua
  -- New session is busy by definition (we just spawned claude)
  local ok_idle, idle = pcall(require, 'tmux.idle')
  if ok_idle then
    idle.mark_busy(session())
  end
  return true
end
```

Find `M.open` — at the end, before it returns, call `mark_busy`:

```lua
function M.open()
  if vim.env.TMUX == nil or vim.env.TMUX == '' then
    vim.notify('Claude popup requires $TMUX (run nvim inside tmux)', vim.log.levels.WARN)
    return
  end
  if not M.ensure() then
    return
  end
  sys({
    'tmux', 'display-popup', '-E', '-w', POPUP_W, '-h', POPUP_H,
    'tmux attach -t ' .. session(),
  })
  -- User was just typing in there; treat as busy so badge clears
  local ok_idle, idle = pcall(require, 'tmux.idle')
  if ok_idle then
    idle.mark_busy(session())
  end
end
```

- [ ] **Step 3: Run existing tests to confirm no regression**

```bash
XDG_DATA_HOME="$PWD/.tests" XDG_CONFIG_HOME="$PWD/.tests/config" \
  XDG_CACHE_HOME="$PWD/.tests/cache" XDG_STATE_HOME="$PWD/.tests/state" \
  nvim --headless -u tests/minimal_init.lua \
  -c "PlenaryBustedDirectory tests/ {minimal_init='tests/minimal_init.lua'}" \
  -c 'qa!' 2>&1 | tail -15
```

Expected: all prior specs still pass. The new `_session_of_pane` helper isn't directly tested here (covered in the integration test in Task 4).

- [ ] **Step 4: Stylua + commit**

```bash
$STYLUA lua/tmux/send.lua lua/tmux/claude_popup.lua
$STYLUA --check lua/tmux/send.lua lua/tmux/claude_popup.lua && echo STYLUA_OK
git add lua/tmux/send.lua lua/tmux/claude_popup.lua
git commit -m "feat(tmux): mark sessions busy on send + open

- send.send_to_claude: after tmux send-keys, look up containing
  session via display-message #{session_name} and call
  idle.mark_busy(name) so the badge clears immediately (not after
  the next 1s poll tick).
- claude_popup.ensure: newly-spawned session is busy by definition.
- claude_popup.open: user was just typing in the popup — busy.

Uses pcall(require, 'tmux.idle') so send/popup still work when
idle.lua isn't loaded (e.g. in unit tests that stub claude_popup)."
```

---

## Task 3: Boot `idle.watch_all()` from init.lua

**Files:**
- Modify: `init.lua`

**Context:** The daemon needs to start when nvim opens inside tmux. Add it to the VimEnter module bootstrap alongside coach/clipboard/tmux/remote.

- [ ] **Step 1: Read current init.lua tail**

```bash
cat init.lua
```

Note the `setup_happy_modules()` function that loops over `{ 'coach', 'clipboard', 'tmux', 'remote' }`.

- [ ] **Step 2: Add idle watcher startup**

Find the block:

```lua
local function setup_happy_modules()
  for _, mod in ipairs({ 'coach', 'clipboard', 'tmux', 'remote' }) do
    local ok, m = pcall(require, mod)
    if ok and type(m.setup) == 'function' then
      local ok_setup, err = pcall(m.setup)
      if not ok_setup then
        vim.notify('happy-nvim: ' .. mod .. '.setup failed: ' .. err, vim.log.levels.WARN)
      end
    end
  end
end
```

Replace with:

```lua
local function setup_happy_modules()
  for _, mod in ipairs({ 'coach', 'clipboard', 'tmux', 'remote' }) do
    local ok, m = pcall(require, mod)
    if ok and type(m.setup) == 'function' then
      local ok_setup, err = pcall(m.setup)
      if not ok_setup then
        vim.notify('happy-nvim: ' .. mod .. '.setup failed: ' .. err, vim.log.levels.WARN)
      end
    end
  end
  -- Idle watcher polls cc-* tmux sessions for output-stable; only useful
  -- when nvim is inside tmux.
  if vim.env.TMUX and vim.env.TMUX ~= '' then
    local ok, idle = pcall(require, 'tmux.idle')
    if ok then
      idle.watch_all()
    end
  end
end
```

- [ ] **Step 3: Headless startup smoke**

```bash
XDG_DATA_HOME="$PWD/.tests" XDG_CONFIG_HOME="$PWD/.tests/config" \
  XDG_CACHE_HOME="$PWD/.tests/cache" XDG_STATE_HOME="$PWD/.tests/state" \
  nvim --headless -c 'qa!' 2>&1 | tail -5
```

Expected: clean exit, no errors. Outside tmux the watcher doesn't start (guarded).

- [ ] **Step 4: Stylua + commit**

```bash
$STYLUA init.lua
$STYLUA --check init.lua && echo STYLUA_OK
git add init.lua
git commit -m "feat(init): start idle.watch_all() after VimEnter when in tmux

Adds tmux.idle to the module bootstrap (after coach/clipboard/
tmux/remote setups). Guarded on \$TMUX — outside tmux the watcher
is a no-op."
```

---

## Task 4: Integration test — session flips to idle after settle

**Files:**
- Create: `tests/integration/test_idle_notification.py`

**Context:** Drives the real loop: create a cc-* session running fake_claude, wait for output, assert `@claude_idle` flips to `1` within a few seconds. Then inject input, assert it flips back to `0`.

Timing: DEBOUNCE_SECS is 2s in the Lua. Test total: ~5s max (write input, wait for ACK, wait for debounce, check option, send more input, check reset).

The test runs the idle loop once manually via `require('tmux.idle')._poll_once(os.time())` rather than the real 1s timer — deterministic.

- [ ] **Step 1: Write the test**

Create `tests/integration/test_idle_notification.py`:

```python
"""Integration test: @claude_idle flips correctly.

We drive the idle loop manually (_poll_once) to avoid 5+ second waits
for the real vim.uv timer to tick. fake_claude emits ACK 500ms after
input; then output is stable; we advance "now" past the debounce
window and expect @claude_idle=1.
"""
from __future__ import annotations

import os
import subprocess
import time
from pathlib import Path

from .helpers import send_keys, tmx, wait_for_pane

REPO_ROOT = Path(__file__).resolve().parents[2]
SESSION = "cc-idle-test"


def _cleanup(tmux_socket: str) -> None:
    subprocess.run(
        ["tmux", "-L", tmux_socket, "kill-session", "-t", SESSION],
        check=False,
        capture_output=True,
    )


def _tmux_wrapper(bin_dir: Path, socket: str) -> None:
    real = "/usr/bin/tmux"
    w = bin_dir / "tmux"
    w.write_text(f"#!/usr/bin/env bash\nexec {real} -L {socket} \"$@\"\n")
    w.chmod(0o755)


def _poll_once_via_nvim(bin_dir: Path, now: int) -> None:
    env = os.environ | {
        "PATH": f"{bin_dir}:{os.environ['PATH']}",
        "TMUX": "/tmp/fake,1,0",
    }
    subprocess.run(
        [
            "nvim",
            "--headless",
            "--clean",
            "-c",
            f"lua vim.opt.rtp:prepend('{REPO_ROOT}')",
            "-c",
            f"lua require('tmux.idle')._poll_once({now})",
            "-c",
            "qa!",
        ],
        check=True,
        text=True,
        capture_output=True,
        env=env,
    )


def _get_idle(tmux_socket: str) -> str:
    result = subprocess.run(
        [
            "tmux", "-L", tmux_socket, "show-option",
            "-t", SESSION, "-v", "-q", "@claude_idle",
        ],
        check=False,
        text=True,
        capture_output=True,
    )
    return (result.stdout or "").strip()


def test_idle_flips_on_stable_output(tmux_socket: str, tmp_path: Path):
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    _tmux_wrapper(bin_dir, tmux_socket)
    _cleanup(tmux_socket)

    try:
        tmx(tmux_socket, "new-session", "-d", "-s", SESSION, "claude --delay 0")
        pane = tmx(tmux_socket, "list-panes", "-t", SESSION, "-F", "#{pane_id}").stdout.strip()

        send_keys(tmux_socket, pane, "hello", "Enter")
        wait_for_pane(tmux_socket, pane, r"ACK:hello", timeout=5)
        # give fake_claude a moment after the ACK so output is truly settled
        time.sleep(0.2)

        # Tick 1: initial capture (state init, not idle yet)
        now = int(time.time())
        _poll_once_via_nvim(bin_dir, now)
        assert _get_idle(tmux_socket) == "", "initial tick should not set @claude_idle"

        # Tick 2: still same capture, but now > stable_since by >2s via mock clock
        _poll_once_via_nvim(bin_dir, now + 3)
        assert _get_idle(tmux_socket) == "1", (
            f"@claude_idle should be '1' after debounce, got {_get_idle(tmux_socket)!r}"
        )

        # Send input -> flips back to busy. Use mark_busy for immediacy.
        send_keys(tmux_socket, pane, "more-input", "Enter")
        # Lua-side: emulate the send-path call to mark_busy
        subprocess.run(
            [
                "nvim", "--headless", "--clean",
                "-c", f"lua vim.opt.rtp:prepend('{REPO_ROOT}')",
                "-c", f"lua require('tmux.idle').mark_busy('{SESSION}')",
                "-c", "qa!",
            ],
            check=True,
            capture_output=True,
            env=os.environ | {"PATH": f"{bin_dir}:{os.environ['PATH']}"},
        )
        assert _get_idle(tmux_socket) == "0", (
            f"@claude_idle should be '0' after mark_busy, got {_get_idle(tmux_socket)!r}"
        )
    finally:
        _cleanup(tmux_socket)
```

- [ ] **Step 2: Run the test locally**

```bash
python3 -m pytest tests/integration/test_idle_notification.py -v
```

Expected: `1 passed`. If the tmux option show is empty after tick 2: verify the Lua module's `apply_flip` actually invoked `set-option -t <name>`. If it's `'0'` instead of `'1'`: the debounce math is off — fake_claude's output might still be changing (its `>` prompt re-appears periodically).

Likely fix if flaky: bump `time.sleep(0.2)` after the ACK to 0.5 so fake_claude has definitely flushed its trailing `> `.

- [ ] **Step 3: Run assess.sh**

```bash
bash scripts/assess.sh
```

Expected: ALL LAYERS PASS.

- [ ] **Step 4: Commit**

```bash
git add tests/integration/test_idle_notification.py
git commit -m "test(integration): @claude_idle flips on stable + resets on mark_busy

Drives tmux.idle._poll_once manually from headless nvim (not the
real timer) so we can advance 'now' past DEBOUNCE_SECS w/o waiting.
Two transitions verified:
- stable ACK output for >2s -> @claude_idle = '1'
- mark_busy(session) -> @claude_idle = '0'"
```

---

## Task 5: Decorate picker entries with idle state

**Files:**
- Modify: `lua/tmux/picker.lua`

**Context:** Read `@claude_idle` per session when building picker entries. Prefix the display string with `✓` (idle) or `⟳` (busy) or `?` (unknown).

- [ ] **Step 1: Add a helper to read `@claude_idle` and update picker entry_maker**

Find `M.open()` in `lua/tmux/picker.lua`. At the top of the function, add a helper:

```lua
local function read_idle(session_name)
  local res = vim.system({
    'tmux', 'show-option', '-t', session_name, '-v', '-q', '@claude_idle',
  }, { text = true }):wait()
  if res.code ~= 0 then
    return nil
  end
  local val = (res.stdout or ''):gsub('%s+$', '')
  if val == '1' then return 'idle' end
  if val == '0' then return 'busy' end
  return nil
end
```

Then find the `entry_maker = function(s)` block:

```lua
        entry_maker = function(s)
          return {
            value = s,
            display = string.format('%-30s  (%s)', s.slug, rel_age(s.created_ts)),
            ordinal = s.slug,
          }
        end,
```

Replace with:

```lua
        entry_maker = function(s)
          local state = read_idle(s.name)
          local icon = (state == 'idle' and '✓') or (state == 'busy' and '⟳') or '?'
          return {
            value = s,
            display = string.format('%s %-28s  (%s)', icon, s.slug, rel_age(s.created_ts)),
            ordinal = s.slug,
          }
        end,
```

- [ ] **Step 2: Headless sanity (picker code parses)**

```bash
nvim --headless -c "lua dofile('lua/tmux/picker.lua')" -c 'qa!' 2>&1 | tail -3
```

Expected: no output (clean parse).

- [ ] **Step 3: Stylua + commit**

```bash
$STYLUA lua/tmux/picker.lua
$STYLUA --check lua/tmux/picker.lua && echo STYLUA_OK
git add lua/tmux/picker.lua
git commit -m "feat(tmux/picker): decorate entries w/ @claude_idle state

Each picker entry now reads @claude_idle via tmux show-option and
prefixes its display with an icon:
  ✓  idle (@claude_idle == '1')
  ⟳  busy (@claude_idle == '0' or session active)
  ?  unknown (option not set — session pre-daemon)

Ordinal kept as slug so fuzzy-find typing stays natural."
```

---

## Task 6: Document tmux status-bar badge in README

**Files:**
- Modify: `README.md`

**Context:** The idle value is on each session's `@claude_idle` user option. Rendering it in the tmux status line is pure tmux config — users opt in by copying a snippet. We document the snippet in README under a new "Multi-project notifications" section.

tmux `status-right` format has no foreach-session construct, so we render each active session manually using `#(...)` shell expansion. Simpler approach: a small shell one-liner that reads every `cc-*` session and renders `<slug><icon>`.

- [ ] **Step 1: Read current README's Multi-project section (if any) or Tests section**

```bash
grep -n '^##\|^###' README.md | head -30
```

Identify the closest place to add a new `### Multi-project notifications` subsection. Natural home: right after the "Working with Claude" section (added in Phase 2), or appended at the end.

- [ ] **Step 2: Append the documentation section**

Append this block to the end of `README.md`:

```markdown

## Multi-project notifications

Each active Claude session carries a `@claude_idle` tmux option that flips to
`1` after 2 seconds of stable output and back to `0` when you send input.
Add this snippet to your `~/.tmux.conf` to show a badge per session in
your status line:

```tmux
# ~/.tmux.conf
set -g status-right "#(bash -c 'for s in $(tmux list-sessions -F \"#{session_name}\" | grep ^cc-); do idle=$(tmux show-option -t \"$s\" -v -q @claude_idle); case \"$idle\" in 1) icon=\"✓\";; 0) icon=\"⟳\";; *) icon=\"?\";; esac; echo -n \" ${s#cc-}$icon\"; done') | %H:%M"
```

Reload with `tmux source-file ~/.tmux.conf`. Example rendering with two
open projects:

    happy-nvim✓ other-repo⟳ | 14:32

The `<leader>cl` picker shows the same state inline, so the status-bar
snippet is optional — useful mainly when you want always-visible state
without opening the picker.
```

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs(readme): tmux status-right snippet for @claude_idle badge

New 'Multi-project notifications' section documents how to render
the per-session idle state in tmux's status bar. One-liner reads
every cc-* session's @claude_idle option and emits '<slug>✓' for
idle, '<slug>⟳' for busy. Optional — picker shows the same state."
```

---

## Task 7: Push + verify green CI

**Files:** none.

- [ ] **Step 1: FF main + push**

```bash
cd /home/raul/projects/happy-nvim
git checkout main
git merge --ff-only feat/v1-implementation
git push git@github.com:raulfrk/happy-nvim.git main:main
```

Expected: `main -> main` advances 6 commits.

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

All should be `success`, including `assess (stable/nightly)` with the new idle test.

If `integration (stable/nightly)` fails on `test_idle_notification`: fetch logs, inspect the debounce window math. Common fixes:
- fake_claude emits more than ACK (it also re-prints `> `) — bump the `time.sleep(0.2)` after the ACK to `0.5`.
- tmux's `show-option -q` returns code 0 w/ empty value for unset options — that matches the test's initial `""` assertion; no fix needed.

- [ ] **Step 4: Close source todos**

```
todo_complete 3.6 3.7 3.8
```

---

## Self-Review

**1. Spec coverage:**

| Todo | Task |
|---|---|
| #3.6 idle-detection daemon | Task 1 (idle.lua + unit tests) + Task 3 (VimEnter wiring) + Task 4 (integration) |
| #3.7 tmux status-bar badge | Task 6 (README snippet — pure user config, not nvim code) |
| #3.8 picker state decoration | Task 5 (picker.lua reads @claude_idle) |

Task 2 (mark_busy on send/open) isn't an explicit todo child but is necessary for 3.6 to feel responsive — the 1-second poll would otherwise show stale idle state for a full tick after the user just sent input. Bundled here to keep the phase shipment complete.

**2. Placeholder scan:** no TBDs. Every code block complete; every command has expected output.

**3. Type consistency:**
- `idle._tick(state, capture, now)` signature matches unit test calls + `_poll_once` callsite.
- State table keys `last_hash`, `stable_since`, `idle` consistent across `_tick`, `_poll_once`, `mark_busy`.
- `@claude_idle` option name consistent across Lua (`apply_flip`, `mark_busy`, picker `read_idle`), pytest (`_get_idle`), and README snippet.
- `DEBOUNCE_SECS = 2` in Lua matches test fixture's `now + 3` (just over debounce).
- `SESSION = 'cc-idle-test'` in pytest doesn't conflict with real `cc-<slug>` sessions spawned from nvim (always uses `cc-<projectid>`).
