"""Integration test: tmux.idle fires vim.notify on busy→idle flip.

Same _poll_once driver as test_idle_notification.py, but with
alert.notify=true and a vim.notify shim that prints to stdout so we
can assert exactly one notification is emitted per flip.
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


def _poll_with_alert(bin_dir: Path, now1: int, now2: int) -> str:
    """Run two _poll_once calls with notify shim; return captured output.

    nvim --headless emits :lua print() to stderr, not stdout, so we merge
    both streams before returning.
    """
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
            "-c", f"lua require('tmux.idle')._poll_once({now1})",
            "-c", f"lua require('tmux.idle')._poll_once({now2})",
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

        now = int(time.time())
        out = _poll_with_alert(bin_dir, now, now + 3)

        assert "NOTIFY:Claude (alert-test) idle" in out, (
            f"expected NOTIFY: line on busy→idle flip, got:\n{out}"
        )
        assert out.count("NOTIFY:") == 1, (
            f"expected exactly 1 notification, got {out.count('NOTIFY:')} in:\n{out}"
        )
    finally:
        _cleanup(tmux_socket)
