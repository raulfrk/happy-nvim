"""Helpers for integration scenarios.

All helpers operate on the isolated tmux server set up by conftest's
`tmux_socket` fixture. Callers pass the socket name explicitly so the
functions are pure (no hidden global state).
"""
from __future__ import annotations

import re
import subprocess
import time

ANSI_RE = re.compile(r"\x1b\[[0-9;]*m")


def tmx(socket: str, *args: str, check: bool = True) -> subprocess.CompletedProcess:
    """Run `tmux -L <socket> <args...>` and return CompletedProcess."""
    return subprocess.run(
        ["tmux", "-L", socket, *args],
        check=check,
        text=True,
        capture_output=True,
    )


def capture_pane(socket: str, target: str) -> str:
    """Return pane contents with ANSI escapes stripped and trailing spaces trimmed."""
    result = tmx(socket, "capture-pane", "-p", "-t", target)
    lines = (ANSI_RE.sub("", line).rstrip() for line in result.stdout.splitlines())
    return "\n".join(lines)


def wait_for_pane(
    socket: str,
    target: str,
    pattern: str,
    timeout: float = 5.0,
    poll_interval: float = 0.1,
) -> str:
    """Poll `target` until `pattern` (regex) matches a line in capture output.

    Returns the full capture on match. Raises AssertionError with the last
    capture attached on timeout.
    """
    deadline = time.monotonic() + timeout
    regex = re.compile(pattern, re.MULTILINE)
    last = ""
    while time.monotonic() < deadline:
        last = capture_pane(socket, target)
        if regex.search(last):
            return last
        time.sleep(poll_interval)
    raise AssertionError(
        f"wait_for_pane: pattern {pattern!r} not found in {target!r} after {timeout}s\n"
        f"--- last capture ---\n{last}\n--- end ---"
    )


def send_keys(socket: str, target: str, *keys: str) -> None:
    """Send keys to a pane. Each arg is passed as-is to `tmux send-keys`."""
    tmx(socket, "send-keys", "-t", target, *keys)
