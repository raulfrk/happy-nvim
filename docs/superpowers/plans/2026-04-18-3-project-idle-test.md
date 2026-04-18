# 3-Project Idle Notification Integration Test Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an integration test that spawns three concurrent `cc-*` tmux sessions, sends input to two of them, advances the idle-daemon clock past the debounce window, and asserts that `@claude_idle` flips INDEPENDENTLY per-session — idle sessions flip to `1`, the busy one stays `0`.

**Architecture:** New `tests/integration/test_multiproject_idle.py`. Reuses the `tmux_socket` fixture + `_poll_once_via_nvim` helper pattern from `test_idle_notification.py` (single-session). Drives the idle daemon manually so we don't wait 2s+ per debounce cycle. Tests three scenarios in a row: all three busy, one goes quiet → only that one flips, then all quiet → all three flip. No changes to production code.

**Tech Stack:** Python 3.11 + pytest, tmux 3.2+, existing fake_claude + conftest harness.

---

## File Structure

```
tests/integration/test_multiproject_idle.py   # NEW — 3-session idle-flip scenarios
docs/manual-tests.md                          # MODIFIED — add 3-project row
```

---

## Task 1: `test_multiproject_idle.py` — 3-session idle transitions

**Files:**
- Create: `tests/integration/test_multiproject_idle.py`

**Context:** The existing `test_idle_notification.py` covers one session — stable output for >DEBOUNCE_SECS flips `@claude_idle=1`, `mark_busy()` resets to `0`. The remaining gap: does the idle daemon handle multiple sessions correctly? If the internal `states` table is keyed by session name (it is, per `lua/tmux/idle.lua`), three concurrent sessions should have independent state. This test proves that.

Flow:

1. Create three `cc-<slug>` tmux sessions each running `fake-claude --delay 0`.
2. Send distinct inputs to each; wait for each session's ACK.
3. Settle 0.3s so all outputs are stable.
4. Advance clock to `now` — one poll tick initializes state for all three (no flips yet).
5. Advance clock to `now + 3` — poll again. All three should now be idle (`@claude_idle=1`).
6. Send new input to session-1 only. Call `mark_busy(session-1)` (mirroring the send-path hook).
7. Assert: `@claude_idle` = `0` on session-1, `1` on session-2 + session-3.
8. Advance clock another 3s. Session-1's output is still changing (fake-claude is ACK'ing), so it stays busy if we poll BEFORE the ACK has quiesced. For determinism, wait for the ACK first, then settle, then poll.

The trickiest part: `_poll_once_via_nvim` in the existing test spawns a fresh nvim process, which means the `states` table in `tmux/idle.lua` resets between calls. That's fine for the single-session test (runs both ticks in one invocation), but for a multi-step scenario we need to either (a) run the scenario inside ONE nvim invocation via a larger Lua script, or (b) persist state across invocations.

Option (a) is simpler + already established by the improved `_poll_twice_via_nvim` pattern the implementer switched to in the earlier idle test. Use the same trick: write the scenario as a single Lua payload the nvim subprocess executes end-to-end.

- [ ] **Step 1: Write the test**

Create `tests/integration/test_multiproject_idle.py`:

```python
"""Integration: three concurrent cc-* sessions → independent @claude_idle.

All three go idle together; sending to one resets only that one's
@claude_idle to 0, leaving the other two at 1. Guards the per-session
state table in lua/tmux/idle.lua against bleed-between-sessions bugs.
"""
from __future__ import annotations

import os
import shutil
import subprocess
import time
from pathlib import Path

from .helpers import send_keys, tmx, wait_for_pane

REPO_ROOT = Path(__file__).resolve().parents[2]
SESSIONS = ("cc-alpha-idle", "cc-beta-idle", "cc-gamma-idle")


def _make_tmux_wrapper(bin_dir: Path, socket: str) -> None:
    real = shutil.which("tmux") or "/usr/bin/tmux"
    w = bin_dir / "tmux"
    w.write_text(f"#!/usr/bin/env bash\nexec {real} -L {socket} \"$@\"\n")
    w.chmod(0o755)


def _cleanup(tmux_socket: str) -> None:
    for s in SESSIONS:
        subprocess.run(
            ["tmux", "-L", tmux_socket, "kill-session", "-t", s],
            check=False, capture_output=True,
        )


def _run_nvim(bin_dir: Path, lua: str) -> None:
    """Run one headless nvim invocation with the given Lua payload."""
    env = os.environ | {
        "PATH": f"{bin_dir}:{os.environ['PATH']}",
        "TMUX": "/tmp/fake,1,0",
    }
    subprocess.run(
        [
            "nvim", "--headless", "--clean",
            "-c", f"lua vim.opt.rtp:prepend('{REPO_ROOT}')",
            "-c", f"lua {lua}",
            "-c", "qa!",
        ],
        check=True, text=True, capture_output=True, env=env,
    )


def _get_idle(tmux_socket: str, session: str) -> str:
    r = subprocess.run(
        ["tmux", "-L", tmux_socket, "show-option", "-t", session, "-v", "-q", "@claude_idle"],
        check=False, text=True, capture_output=True,
    )
    return (r.stdout or "").strip()


def test_three_sessions_idle_independently(tmux_socket: str, tmp_path: Path):
    bin_dir = tmp_path / "bin"; bin_dir.mkdir()
    _make_tmux_wrapper(bin_dir, tmux_socket)
    _cleanup(tmux_socket)

    try:
        # Create three sessions running fake_claude (on PATH via conftest _env)
        for s in SESSIONS:
            tmx(tmux_socket, "new-session", "-d", "-s", s, "claude --delay 0")

        # Prime each: send one line, wait for ACK
        panes = {}
        for s in SESSIONS:
            panes[s] = tmx(
                tmux_socket, "list-panes", "-t", s, "-F", "#{pane_id}",
            ).stdout.strip()
            payload = f"hello-{s.split('-')[1]}"  # hello-alpha / -beta / -gamma
            send_keys(tmux_socket, panes[s], payload, "Enter")
            wait_for_pane(tmux_socket, panes[s], rf"ACK:{payload}", timeout=5)

        # Settle so fake_claude's trailing '> ' prompt is rendered too
        time.sleep(0.3)

        # Tick 1: initialize state for all three. Advance clock inside the
        # same nvim invocation so the in-memory `states` table persists.
        # now_base is captured before we run any ticks so the offsets match.
        now = int(time.time())

        _run_nvim(
            bin_dir,
            f"""
            local idle = require('tmux.idle')
            idle._poll_once({now})       -- tick 1: init (no flip)
            idle._poll_once({now + 3})   -- tick 2: debounce satisfied -> flip to idle
            """,
        )
        # All three should now be '1'
        for s in SESSIONS:
            assert _get_idle(tmux_socket, s) == "1", (
                f"{s} expected @claude_idle=1 after initial settle, got "
                f"{_get_idle(tmux_socket, s)!r}"
            )

        # Disturb only alpha. mark_busy mirrors what send.lua does after
        # a send-keys into the pane.
        _run_nvim(
            bin_dir,
            f"require('tmux.idle').mark_busy('{SESSIONS[0]}')",
        )

        # Alpha should be '0'; beta + gamma unchanged
        assert _get_idle(tmux_socket, SESSIONS[0]) == "0", (
            f"{SESSIONS[0]} expected 0 after mark_busy, got "
            f"{_get_idle(tmux_socket, SESSIONS[0])!r}"
        )
        assert _get_idle(tmux_socket, SESSIONS[1]) == "1", (
            f"{SESSIONS[1]} flipped unexpectedly, got "
            f"{_get_idle(tmux_socket, SESSIONS[1])!r}"
        )
        assert _get_idle(tmux_socket, SESSIONS[2]) == "1", (
            f"{SESSIONS[2]} flipped unexpectedly, got "
            f"{_get_idle(tmux_socket, SESSIONS[2])!r}"
        )
    finally:
        _cleanup(tmux_socket)
```

- [ ] **Step 2: Run locally**

```bash
cd /home/raul/worktrees/happy-nvim/feat-v1-implementation
python3 -m pytest tests/integration/test_multiproject_idle.py -v
```

Expected: `1 passed`. If the assertion fires for beta or gamma flipping back to `0`:

- `mark_busy` may be touching a shared structure. Check `lua/tmux/idle.lua` `states` table — should be keyed by session name.
- The nvim subprocess in `_run_nvim` for `mark_busy` loses the previous `states` table (fresh Lua VM). `mark_busy` writes `@claude_idle=0` directly via `tmux set-option` in the tmux-side representation, so the in-memory reset isn't required — only the tmux option write. Verify by reading `lua/tmux/idle.lua M.mark_busy` — if it both updates `states[session]` AND writes the option, the option write is what matters for this test.

If the helper's `mark_busy` ONLY updates in-memory state (no `tmux set-option` call), the test won't observe the flip. Patch the scenario to also call `idle._poll_once` after `mark_busy` to force the flush. But per the Phase 3 plan `mark_busy` was specified to call `apply_flip` which writes `@claude_idle=0`; trust that.

- [ ] **Step 3: Run assess.sh**

```bash
bash scripts/assess.sh
```

Expected: ALL LAYERS PASS (one new pytest, no other changes).

- [ ] **Step 4: Commit**

```bash
git add tests/integration/test_multiproject_idle.py
git commit -m "test(integration): three sessions get independent @claude_idle

Creates cc-alpha-idle / -beta / -gamma; primes each w/ ACKs; advances
the clock past DEBOUNCE_SECS — asserts all three flip to @claude_idle=1.
Then mark_busy on alpha only: asserts alpha resets to 0 while beta +
gamma stay at 1. Guards the per-session states table in lua/tmux/idle.lua
against bleed-between-sessions regressions."
```

---

## Task 2: Manual test additions

**Files:**
- Modify: `docs/manual-tests.md`

- [ ] **Step 1: Add row under "5. Multi-project Claude"**

Find section "5. Multi-project Claude" in `docs/manual-tests.md`. Append:

```markdown
- [ ] (CI-covered) Three projects open in parallel tmux panes. Let all three go idle — `<Space>cl` picker shows `✓` on all three. Send input to project A only. Picker shows `⟳ A / ✓ B / ✓ C`.
```

- [ ] **Step 2: Commit**

```bash
git add docs/manual-tests.md
git commit -m "docs(manual): 3-project independent-idle row"
```

---

## Task 3: Push + verify green CI

**Files:** none.

- [ ] **Step 1: FF + push**

```bash
cd /home/raul/projects/happy-nvim
git checkout main
git merge --ff-only feat/v1-implementation
git push git@github.com:raulfrk/happy-nvim.git main:main
```

- [ ] **Step 2: Poll + verify**

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
gh api "repos/raulfrk/happy-nvim/actions/runs/$RUN_ID/jobs" --jq '.jobs[] | "\(.name): \(.conclusion)"'
```

Expected: two jobs (`assess (stable)`, `assess (nightly)`) both `success`.

- [ ] **Step 3: Close the source todo**

```
todo_complete 3.11
```

---

## Manual Test Additions

Task 2 adds one manual-tests row — the 3-project multiproject-idle scenario. Marked `(CI-covered)` because this plan ships a pytest integration test exercising the same behavior headlessly.

---

## Self-Review

**1. Spec coverage:**

| Todo | Task |
|---|---|
| #3.11 three concurrent projects, idle flips independently | Task 1 (pytest scenario) + Task 2 (manual-tests row) |

**2. Placeholder scan:** no TBDs. Every code block complete.

**3. Type consistency:**
- `SESSIONS` tuple keeps 3 `cc-*` names; every assertion references them by index (`SESSIONS[0]` = alpha = the busy one).
- `_get_idle`, `_make_tmux_wrapper`, `_cleanup`, `_run_nvim` helper signatures match the pattern from existing `test_idle_notification.py` and `test_multiproject_routing.py`.
- `lua tmux.idle` module API calls (`_poll_once`, `mark_busy`) match Phase 3's `lua/tmux/idle.lua`.
- `@claude_idle` option name consistent with Phase 3 impl + existing tests.
