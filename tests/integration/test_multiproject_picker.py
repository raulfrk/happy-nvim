"""Integration test: sessions.list() returns all cc-* sessions.

Skips the telescope UI (no TTY in pytest). The picker (lua/tmux/picker.lua)
just consumes sessions.list(); if the data layer is correct, the UI binding
is trivial wiring. End-to-end UI test is deferred to Phase 5 once an
interactive-terminal harness lands.
"""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import textwrap
from pathlib import Path

import pytest

from .helpers import tmx

REPO_ROOT = Path(__file__).resolve().parents[2]


def _make_tmux_wrapper(bin_dir: Path, socket: str) -> None:
    """Put a `tmux` shim on PATH that forwards all calls to the test socket."""
    real_tmux = shutil.which("tmux") or "/usr/bin/tmux"
    wrapper = bin_dir / "tmux"
    wrapper.write_text(textwrap.dedent(f"""\
        #!/usr/bin/env bash
        exec {real_tmux} -L {socket} "$@"
    """))
    wrapper.chmod(0o755)


def _list_from_nvim(tmux_socket: str, bin_dir: Path) -> list[dict]:
    """Call tmux.sessions.list() from headless nvim on the test socket."""
    out_file = "/tmp/happy-sessions.json"
    env = os.environ | {"PATH": f"{bin_dir}:{os.environ['PATH']}"}
    subprocess.check_output(
        [
            "nvim",
            "--headless",
            "--clean",
            "-c",
            f"lua vim.opt.rtp:prepend('{REPO_ROOT}')",
            "-c",
            f"lua vim.fn.writefile({{vim.json.encode(require('tmux.sessions').list())}}, '{out_file}')",
            "-c",
            "qa!",
        ],
        text=True,
        stderr=subprocess.STDOUT,
        env=env,
    )
    return json.loads(Path(out_file).read_text())


def test_list_returns_both_sessions(tmux_socket: str, tmp_path: Path):
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    _make_tmux_wrapper(bin_dir, tmux_socket)

    # Set up two cc-* sessions directly on the test server
    tmx(tmux_socket, "new-session", "-d", "-s", "cc-alpha", "claude --delay 0")
    tmx(tmux_socket, "new-session", "-d", "-s", "cc-beta", "claude --delay 0")
    # Sanity: both exist via tmux directly
    for name in ("cc-alpha", "cc-beta"):
        assert (
            subprocess.run(
                ["tmux", "-L", tmux_socket, "has-session", "-t", name],
                check=False,
            ).returncode
            == 0
        ), f"{name} missing"

    try:
        sessions = _list_from_nvim(tmux_socket, bin_dir)
        names = sorted(s["name"] for s in sessions)
        slugs = sorted(s["slug"] for s in sessions)
        assert "cc-alpha" in names, f"cc-alpha missing from {names}"
        assert "cc-beta" in names, f"cc-beta missing from {names}"
        # slugs have the prefix stripped
        assert "alpha" in slugs
        assert "beta" in slugs
        # each has a numeric created_ts and pane id
        for s in sessions:
            if s["name"] in ("cc-alpha", "cc-beta"):
                assert isinstance(s["created_ts"], (int, float))
                assert s["first_pane_id"].startswith("%")
    finally:
        for s in ("cc-alpha", "cc-beta"):
            subprocess.run(
                ["tmux", "-L", tmux_socket, "kill-session", "-t", s],
                check=False,
                capture_output=True,
            )
