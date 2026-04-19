"""Regression: <leader>cc in two nvims (two project dirs) creates two
distinct per-project tmux sessions (cc-<id>).

Bug 30.3: the old pane-model implementation stashed `@claude_pane_id`
on the tmux *window*, so a second nvim sharing the same tmux window
saw the first project's pane id and no-opped — the second project
never got its own Claude surface.

The fix switches `<leader>cc` to the per-project session model:
`require('tmux.claude').open_guarded()` creates a `cc-<id>` session
via the registry and falls back to "attach via CLI" when not inside
$TMUX. This test invokes `open_guarded()` headlessly from two
different cwds (sharing one tmux socket) and asserts both sessions
exist on the server.
"""
from __future__ import annotations

import os
import shutil
import subprocess
import textwrap
from pathlib import Path

from .helpers import tmx

REPO_ROOT = Path(__file__).resolve().parents[2]


def _make_tmux_wrapper(bin_dir: Path, socket: str) -> None:
    """Shim `tmux` on PATH so nvim's plain `tmux ...` calls hit our test socket."""
    real_tmux = shutil.which("tmux") or "/usr/bin/tmux"
    wrapper = bin_dir / "tmux"
    wrapper.write_text(textwrap.dedent(f"""\
        #!/usr/bin/env bash
        exec {real_tmux} -L {socket} "$@"
    """))
    wrapper.chmod(0o755)


def _open_cc_in_cwd(cwd: Path, registry_path: Path, bin_dir: Path) -> None:
    """Headless nvim: cd into cwd, load happy-nvim rtp, call open_guarded()."""
    env = os.environ | {
        "HAPPY_PROJECTS_JSON_OVERRIDE": str(registry_path),
        "PATH": f"{bin_dir}:{os.environ['PATH']}",
        # Dummy TMUX so guard() passes. The bash wrapper retargets tmux to
        # our test socket, so switch-client lands on the isolated server.
        "TMUX": "/tmp/fake-tmux,1,0",
    }
    subprocess.run(
        [
            "nvim",
            "--headless",
            "--clean",
            "-c",
            f"lua vim.cmd('cd {cwd}')",
            "-c",
            f"lua vim.opt.rtp:prepend('{REPO_ROOT}')",
            "-c",
            "lua require('tmux.claude').open_guarded()",
            "-c",
            "qa!",
        ],
        check=True,
        text=True,
        capture_output=True,
        env=env,
    )


def test_second_window_cc_creates_distinct_session(
    tmux_socket: str, tmp_path: Path
):
    proj_a = tmp_path / "a"
    proj_a.mkdir()
    proj_b = tmp_path / "b"
    proj_b.mkdir()

    registry_path = tmp_path / "projects.json"
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    _make_tmux_wrapper(bin_dir, tmux_socket)

    session_a = "cc-a"
    session_b = "cc-b"

    try:
        _open_cc_in_cwd(proj_a, registry_path, bin_dir)
        _open_cc_in_cwd(proj_b, registry_path, bin_dir)

        # Both sessions exist on the isolated test tmux server. Old pane
        # code never created cc-b — the second nvim would have re-used
        # proj-a's @claude_pane_id (window-scoped) and no-opped.
        rc_a = subprocess.run(
            ["tmux", "-L", tmux_socket, "has-session", "-t", session_a],
            check=False,
        ).returncode
        rc_b = subprocess.run(
            ["tmux", "-L", tmux_socket, "has-session", "-t", session_b],
            check=False,
        ).returncode
        assert rc_a == 0, f"{session_a} missing"
        assert rc_b == 0, f"{session_b} missing"

        # Sanity: two *distinct* sessions (not one shared by both).
        ls = tmx(tmux_socket, "list-sessions", "-F", "#{session_name}")
        names = set(ls.stdout.split())
        assert session_a in names and session_b in names, (
            f"expected both {session_a} and {session_b} in {names!r}"
        )
    finally:
        for s in (session_a, session_b):
            subprocess.run(
                ["tmux", "-L", tmux_socket, "kill-session", "-t", s],
                check=False,
                capture_output=True,
            )
