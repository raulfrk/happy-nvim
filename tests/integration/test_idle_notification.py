"""Integration test: @claude_idle flips correctly, driven by real vim.uv.timer.

Previously drove `_poll_once` manually. That proved the state machine
but not the timer wiring — a regression to `watch_all()` (forgotten
`vim.schedule_wrap`, timer leak, etc.) would have gone undetected.

Now uses `tmux.idle.watch_all()` + `vim.wait()` so the real 1s poll
cadence and 2s debounce play out end-to-end.
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


def _run_watcher(bin_dir: Path, wait_ms: int) -> None:
    """Start tmux.idle.watch_all() and block the main thread in vim.wait
    so the real libuv timer can tick (poll every 1s, flip after 2s stable).
    """
    env = os.environ | {
        "PATH": f"{bin_dir}:{os.environ['PATH']}",
        "TMUX": "/tmp/fake,1,0",
    }
    subprocess.run(
        [
            "nvim", "--headless", "--clean",
            "-c", f"lua vim.opt.rtp:prepend('{REPO_ROOT}')",
            "-c", "lua require('tmux.idle').watch_all()",
            "-c", f"lua vim.wait({wait_ms}, function() return false end, 100)",
            "-c", "qa!",
        ],
        check=True, text=True, capture_output=True, env=env,
    )


def _mark_busy_via_nvim(bin_dir: Path, session: str) -> None:
    env = os.environ | {"PATH": f"{bin_dir}:{os.environ['PATH']}"}
    subprocess.run(
        [
            "nvim", "--headless", "--clean",
            "-c", f"lua vim.opt.rtp:prepend('{REPO_ROOT}')",
            "-c", f"lua require('tmux.idle').mark_busy('{session}')",
            "-c", "qa!",
        ],
        check=True, capture_output=True, env=env,
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
        # Let fake_claude's trailing "> " stabilize before the watcher starts.
        time.sleep(0.5)

        # Real-timer drive: 3500ms is enough for poll #1 (init), poll #2
        # (stable 2s >= DEBOUNCE_SECS → flip), poll #3 (already idle).
        _run_watcher(bin_dir, wait_ms=3500)
        assert _get_idle(tmux_socket) == "1", (
            f"@claude_idle should be '1' after debounce, got {_get_idle(tmux_socket)!r}"
        )

        # mark_busy path: simulate send.send_to_claude / popup.open firing it.
        send_keys(tmux_socket, pane, "more-input", "Enter")
        _mark_busy_via_nvim(bin_dir, SESSION)
        assert _get_idle(tmux_socket) == "0", (
            f"@claude_idle should be '0' after mark_busy, got {_get_idle(tmux_socket)!r}"
        )
    finally:
        _cleanup(tmux_socket)
