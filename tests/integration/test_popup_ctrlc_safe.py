"""Integration test: Ctrl-C inside Claude popup doesn't kill the session.

Real `claude` traps SIGINT to interrupt the current reply. Our stub
fake_claude doesn't, so when we simulate Ctrl-C the inner shell exits
— but with `remain-on-exit on` set on the window, tmux keeps the
pane alive and the session stays around for the next attach.

This guards against any future change that would make Ctrl-C tear
down the whole session (e.g. spawning fake_claude with `-E` so the
window dies on exit).
"""
from __future__ import annotations

import subprocess
import time

import pytest

from .helpers import send_keys, tmx, wait_for_pane

SESSION = "cc-ctrlc-test"


def _has_session(tmux_socket: str) -> bool:
    return subprocess.run(
        ["tmux", "-L", tmux_socket, "has-session", "-t", SESSION],
        check=False,
    ).returncode == 0


@pytest.fixture
def cleanup(tmux_socket: str):
    subprocess.run(
        ["tmux", "-L", tmux_socket, "kill-session", "-t", SESSION],
        check=False, capture_output=True,
    )
    yield
    subprocess.run(
        ["tmux", "-L", tmux_socket, "kill-session", "-t", SESSION],
        check=False, capture_output=True,
    )


def test_ctrlc_does_not_kill_session(tmux_socket: str, cleanup):
    # Spawn session w/ remain-on-exit so the pane survives child exit
    tmx(tmux_socket, "new-session", "-d", "-s", SESSION, "claude --delay 0")
    tmx(tmux_socket, "set-option", "-t", SESSION, "remain-on-exit", "on")

    pane = tmx(tmux_socket, "list-panes", "-t", SESSION, "-F", "#{pane_id}").stdout.strip()
    # Start a conversation to confirm the session is healthy before C-c
    send_keys(tmux_socket, pane, "before-interrupt", "Enter")
    wait_for_pane(tmux_socket, pane, r"ACK:before-interrupt", timeout=5)
    assert _has_session(tmux_socket), "session disappeared before C-c (precondition)"

    # Send Ctrl-C — fake_claude (bash + read loop) exits; tmux keeps the
    # pane (remain-on-exit) so the session stays alive.
    send_keys(tmux_socket, pane, "C-c")
    time.sleep(0.5)
    assert _has_session(tmux_socket), (
        "session was killed by Ctrl-C — popup is unsafe!"
    )
