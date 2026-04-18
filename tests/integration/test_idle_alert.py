"""Integration test: vim.notify fires on busy→idle flip, driven by real timer.

Previously drove `_poll_once` manually. Now uses `watch_all()` +
`vim.wait()` so a regression to the real timer wiring (e.g. forgotten
`vim.schedule_wrap`) would fail here.
"""
from __future__ import annotations

import os
import subprocess
import time
from pathlib import Path

from .helpers import send_keys, tmx, wait_for_pane

REPO_ROOT = Path(__file__).resolve().parents[2]
SESSION = "cc-alert-test"


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


def _run_watcher_with_notify(bin_dir: Path, wait_ms: int) -> str:
    """Start watch_all(), override vim.notify to print NOTIFY: lines,
    block in vim.wait so the real timer can tick. Return merged stdout+stderr
    (headless nvim emits :lua print() to stderr)."""
    env = os.environ | {
        "PATH": f"{bin_dir}:{os.environ['PATH']}",
        "TMUX": "/tmp/fake,1,0",
    }
    result = subprocess.run(
        [
            "nvim", "--headless", "--clean",
            "-c", f"lua vim.opt.rtp:prepend('{REPO_ROOT}')",
            "-c", "lua vim.notify = function(msg, _, _) print('NOTIFY:'..msg) end",
            "-c", "lua require('tmux.idle').setup({ notify=true, skip_focused=false })",
            "-c", "lua require('tmux.idle').watch_all()",
            "-c", f"lua vim.wait({wait_ms}, function() return false end, 100)",
            "-c", "qa!",
        ],
        check=True, text=True, capture_output=True, env=env,
    )
    return result.stdout + result.stderr


def test_idle_alert_fires_on_flip(tmux_socket: str, tmp_path: Path):
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    _tmux_wrapper(bin_dir, tmux_socket)
    _cleanup(tmux_socket)

    try:
        tmx(tmux_socket, "new-session", "-d", "-s", SESSION, "claude --delay 0")
        pane = tmx(tmux_socket, "list-panes", "-t", SESSION, "-F", "#{pane_id}").stdout.strip()

        send_keys(tmux_socket, pane, "hello", "Enter")
        wait_for_pane(tmux_socket, pane, r"ACK:hello", timeout=5)
        time.sleep(0.5)

        # 3500ms ≥ one init poll (t=1s) + one debounce-flip poll (t=2s).
        # After the flip, apply_flip calls _should_alert → fire_alert → NOTIFY.
        out = _run_watcher_with_notify(bin_dir, wait_ms=3500)

        assert "NOTIFY:Claude (alert-test) idle" in out, (
            f"expected NOTIFY: line on busy→idle flip, got:\n{out}"
        )
        assert out.count("NOTIFY:") == 1, (
            f"expected exactly 1 notification, got {out.count('NOTIFY:')} in:\n{out}"
        )
    finally:
        _cleanup(tmux_socket)
