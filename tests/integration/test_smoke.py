"""Baseline scenario — proves the harness works end-to-end.

If this fails, don't trust any other integration test until it's fixed.
"""
from __future__ import annotations

import shutil

from .helpers import capture_pane, send_keys, tmx, wait_for_pane


def test_fake_claude_on_path():
    """conftest's _env fixture should shadow `claude` with fake_claude.py."""
    claude_path = shutil.which("claude")
    assert claude_path is not None, "claude (fake) not on PATH"
    assert claude_path.endswith("/bin/claude"), f"unexpected claude path: {claude_path}"


def test_tmux_echo_roundtrip(tmux_socket: str):
    """Run fake-claude in a tmux pane; send a line; assert the ACK appears.

    Exercises: tmux isolation, fake_claude stdin handling, capture_pane,
    wait_for_pane regex matching.
    """
    session = "smoke"
    try:
        tmx(
            tmux_socket,
            "new-session",
            "-d",
            "-s",
            session,
            "-x",
            "80",
            "-y",
            "24",
            "claude --delay 0",
        )
        send_keys(tmux_socket, session, "hello", "Enter")
        output = wait_for_pane(tmux_socket, session, r"^Assistant: ACK:hello$", timeout=5)
        assert "ACK:hello" in output

        send_keys(tmux_socket, session, "world", "Enter")
        wait_for_pane(tmux_socket, session, r"^Assistant: ACK:world$", timeout=5)
    finally:
        tmx(tmux_socket, "kill-session", "-t", session, check=False)


def test_helpers_strip_ansi(tmux_socket: str):
    """capture_pane must strip tmux's ANSI escapes from colored output."""
    session = "ansi"
    try:
        # printf ANSI red text via shell
        tmx(
            tmux_socket,
            "new-session",
            "-d",
            "-s",
            session,
            "-x",
            "80",
            "-y",
            "24",
            "printf '\\033[31mred\\033[0m\\n'; sleep 5",
        )
        wait_for_pane(tmux_socket, session, r"^red$", timeout=2)
        output = capture_pane(tmux_socket, session)
        assert "\x1b" not in output, "ANSI not stripped"
        assert "red" in output
    finally:
        tmx(tmux_socket, "kill-session", "-t", session, check=False)
