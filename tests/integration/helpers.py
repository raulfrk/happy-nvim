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


def assert_capture_equals(socket: str, target: str, expected_path) -> None:
    """Assert pane capture matches a golden file; regen via UPDATE_GOLDEN=1.

    On mismatch, raises AssertionError w/ a unified diff pointing at the
    golden file so contributors can see what changed at a glance.

    Parameters
    ----------
    socket : str
        Tmux socket name (as passed to `tmx` / `capture_pane`).
    target : str
        Pane target (e.g. '%42' or session name).
    expected_path : pathlib.Path
        Path to the golden text file. Regen creates it if missing.

    Environment
    -----------
    UPDATE_GOLDEN=1 → overwrite (or create) the golden file with the current
    capture instead of asserting. Any other value is ignored.
    """
    import difflib
    import os as _os
    from pathlib import Path as _Path
    actual = capture_pane(socket, target)
    golden = _Path(expected_path)
    if _os.environ.get("UPDATE_GOLDEN") == "1":
        golden.parent.mkdir(parents=True, exist_ok=True)
        golden.write_text(actual)
        return
    expected = golden.read_text() if golden.exists() else ""
    if actual == expected:
        return
    diff = "\n".join(
        difflib.unified_diff(
            expected.splitlines(),
            actual.splitlines(),
            fromfile=str(golden),
            tofile="<pane capture>",
            lineterm="",
        )
    )
    raise AssertionError(
        f"capture does not match golden {golden}\n\n{diff}\n\n"
        f"(regen: UPDATE_GOLDEN=1 python3 -m pytest ...)"
    )
