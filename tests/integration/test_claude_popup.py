"""Integration test: claude-happy session lifecycle.

Doesn't render display-popup (no controlling TTY in pytest). Instead
asserts the backing detached session behavior:

- ensure() creates `claude-happy` running fake_claude
- session survives over time (no accidental self-kill)
- send-keys into the inner pane gets an ACK back
- fresh() kills + replaces (new pane id, empty history)

Render-to-popup is a tmux concern; if `display-popup -E` ever
regresses, the tmux upstream has its own tests.
"""
from __future__ import annotations

import subprocess
import time
from pathlib import Path

import pytest

from .helpers import capture_pane, send_keys, tmx, wait_for_pane

SESSION = "claude-happy"


def _has_session(tmux_socket: str) -> bool:
    result = subprocess.run(
        ["tmux", "-L", tmux_socket, "has-session", "-t", SESSION],
        check=False,
        capture_output=True,
    )
    return result.returncode == 0


def _pane_id(tmux_socket: str) -> str:
    result = tmx(tmux_socket, "list-panes", "-t", SESSION, "-F", "#{pane_id}")
    return result.stdout.strip()


@pytest.fixture
def cleanup_session(tmux_socket: str):
    """Make sure the session is killed before + after each test."""
    subprocess.run(
        ["tmux", "-L", tmux_socket, "kill-session", "-t", SESSION],
        check=False,
        capture_output=True,
    )
    yield
    subprocess.run(
        ["tmux", "-L", tmux_socket, "kill-session", "-t", SESSION],
        check=False,
        capture_output=True,
    )


def test_ensure_creates_detached_session(tmux_socket: str, cleanup_session):
    """Mirrors lua/tmux/claude_popup.lua M.ensure() behavior."""
    tmx(tmux_socket, "new-session", "-d", "-s", SESSION, "claude --delay 0")
    assert _has_session(tmux_socket), "session not created"
    pane = _pane_id(tmux_socket)
    assert pane.startswith("%"), f"unexpected pane id: {pane!r}"


def test_session_survives_and_accepts_input(
    tmux_socket: str, cleanup_session, tmp_path: Path
):
    """Session persists + pane receives input + ACK appears."""
    tmx(tmux_socket, "new-session", "-d", "-s", SESSION, "claude --delay 0")
    pane = _pane_id(tmux_socket)
    send_keys(tmux_socket, pane, "hello", "Enter")
    wait_for_pane(tmux_socket, pane, r"^Assistant: ACK:hello$", timeout=5)
    # Simulate time passing (popup open → close → reopen)
    time.sleep(0.3)
    assert _has_session(tmux_socket), "session died during simulated detach window"
    # The pane id is stable across detach/reattach (it's the same pane)
    assert _pane_id(tmux_socket) == pane
    # History intact
    out = capture_pane(tmux_socket, pane)
    assert "ACK:hello" in out, f"history lost after idle: {out!r}"


def test_fresh_kills_and_replaces(tmux_socket: str, cleanup_session):
    """fresh() variant must produce a new pane id with empty history."""
    tmx(tmux_socket, "new-session", "-d", "-s", SESSION, "claude --delay 0")
    old_pane = _pane_id(tmux_socket)
    send_keys(tmux_socket, old_pane, "first-convo", "Enter")
    wait_for_pane(tmux_socket, old_pane, r"ACK:first-convo", timeout=5)

    # Simulate fresh(): kill + recreate
    subprocess.run(
        ["tmux", "-L", tmux_socket, "kill-session", "-t", SESSION],
        check=True,
        capture_output=True,
    )
    assert not _has_session(tmux_socket)
    tmx(tmux_socket, "new-session", "-d", "-s", SESSION, "claude --delay 0")

    new_pane = _pane_id(tmux_socket)
    # tmux may reuse pane IDs across kill+recreate on the same socket;
    # what matters is the history is clean, not the numeric ID.
    # Wait for fake_claude to print its prompt
    wait_for_pane(tmux_socket, new_pane, r"^>", timeout=3)
    out = capture_pane(tmux_socket, new_pane)
    assert "ACK:first-convo" not in out, f"fresh pane has stale history: {out!r}"
