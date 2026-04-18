"""Integration test: vim.notify fires while popup's async subprocess is still pending.

Regression guard for the popup-blocks-idle-watcher bug. Before the fix,
claude_popup.open did vim.system({display-popup...}):wait() which froze
nvim's event loop for the popup's entire lifetime — vim.uv.timer starved,
idle.watch_all() never ticked, no NOTIFY: fired until after detach.

This test drives the real timer (not _poll_once manually) and keeps a
long-running async vim.system alive during the wait window. If the
async contract breaks (e.g. someone reintroduces :wait()), the timer
won't tick during the subprocess and no NOTIFY: will surface.
"""
from __future__ import annotations

import os
import subprocess
import time
from pathlib import Path

from .helpers import send_keys, tmx, wait_for_pane

REPO_ROOT = Path(__file__).resolve().parents[2]
SESSION = "cc-popup-test"


def _cleanup(tmux_socket: str) -> None:
    subprocess.run(
        ["tmux", "-L", tmux_socket, "kill-session", "-t", SESSION],
        check=False, capture_output=True,
    )


def _tmux_wrapper(bin_dir: Path, socket: str) -> None:
    real = "/usr/bin/tmux"
    w = bin_dir / "tmux"
    w.write_text(f"#!/usr/bin/env bash\nexec {real} -L {socket} \"$@\"\n")
    w.chmod(0o755)


def _run_nvim_with_watcher(bin_dir: Path, wait_ms: int) -> str:
    """Start idle.watch_all, keep a long async vim.system alive,
    let the real timer tick, return merged stdout+stderr."""
    env = os.environ | {
        "PATH": f"{bin_dir}:{os.environ['PATH']}",
        "TMUX": "/tmp/fake,1,0",
    }
    # Lua driver: override vim.notify to print NOTIFY: lines, configure idle
    # with short cooldown + skip_focused=false, start an async `sleep 4`
    # (standing in for the display-popup subprocess that blocks in prod),
    # start watch_all, block on vim.wait for wait_ms so timers can fire.
    lua = (
        "vim.opt.rtp:prepend('" + str(REPO_ROOT) + "');"
        "vim.notify = function(msg, _, _) print('NOTIFY:'..msg) end;"
        "require('tmux.idle').setup({ notify=true, skip_focused=false, cooldown_secs=0 });"
        "local popup_exited = false;"
        "vim.system({'sleep', '4'}, {}, function(_) popup_exited = true end);"
        "require('tmux.idle').watch_all();"
        "vim.wait(" + str(wait_ms) + ", function() return false end, 100);"
        "print('POPUP_EXITED='..tostring(popup_exited));"
    )
    result = subprocess.run(
        [
            "nvim", "--headless", "--clean",
            "-c", "lua " + lua,
            "-c", "qa!",
        ],
        check=True, text=True, capture_output=True, env=env,
    )
    return result.stdout + result.stderr


def test_notify_fires_during_pending_async_subprocess(tmux_socket: str, tmp_path: Path):
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    _tmux_wrapper(bin_dir, tmux_socket)
    _cleanup(tmux_socket)

    try:
        tmx(tmux_socket, "new-session", "-d", "-s", SESSION, "claude --delay 0")
        pane = tmx(tmux_socket, "list-panes", "-t", SESSION, "-F", "#{pane_id}").stdout.strip()

        send_keys(tmux_socket, pane, "hi", "Enter")
        wait_for_pane(tmux_socket, pane, r"ACK:hi", timeout=5)
        # settle so fake_claude's trailing "> " is flushed before watcher ticks
        time.sleep(0.5)

        # Wait long enough for: poll #1 (t=1s init), poll #2 (t=2s debounce flip).
        # Cap at 3500ms so we finish before the fake subprocess (sleep 4) exits,
        # proving the timer fired WHILE the async vim.system was still pending.
        out = _run_nvim_with_watcher(bin_dir, wait_ms=3500)

        assert "NOTIFY:Claude (popup-test) idle" in out, (
            f"timer didn't tick (or alert didn't fire) while async subprocess pending:\n{out}"
        )
        # Assert the subprocess really was still running when the notify fired:
        # popup_exited should print False (4s sleep > 3.5s wait).
        assert "POPUP_EXITED=false" in out, (
            f"async subprocess finished before wait window closed; "
            f"test doesn't actually prove non-blocking:\n{out}"
        )
    finally:
        _cleanup(tmux_socket)
