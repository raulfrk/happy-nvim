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


def _poll_twice_via_nvim(bin_dir: Path, now1: int, now2: int) -> None:
    """Run two consecutive _poll_once calls in the same nvim instance.

    This preserves the in-memory `states` table between ticks so the
    debounce logic sees Tick 1 (init) then Tick 2 (stable → idle flip).
    """
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
            f"lua require('tmux.idle')._poll_once({now1})",
            "-c",
            f"lua require('tmux.idle')._poll_once({now2})",
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
        time.sleep(0.5)

        # Two ticks in one nvim invocation so in-memory state survives:
        # Tick 1 (now): initial capture → init, not idle yet
        # Tick 2 (now+3): same capture, 3s > DEBOUNCE_SECS=2 → flip to idle
        now = int(time.time())
        _poll_twice_via_nvim(bin_dir, now, now + 3)
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
