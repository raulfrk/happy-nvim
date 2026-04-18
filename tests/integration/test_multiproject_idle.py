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
