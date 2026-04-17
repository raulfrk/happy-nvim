"""Integration: two project dirs → two isolated Claude sessions.

Verifies lua/tmux/project.session_name() + claude_popup.ensure() produce
two distinct tmux sessions (one per project) and sends to one do not
appear in the other's capture-pane.
"""
from __future__ import annotations

import os
import subprocess
import textwrap
from pathlib import Path

import pytest

from .helpers import capture_pane, send_keys, tmx, wait_for_pane

REPO_ROOT = Path(__file__).resolve().parents[2]


def _make_project(parent: Path, name: str) -> Path:
    """Create a git repo at parent/name; return its path."""
    proj = parent / name
    proj.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        ["git", "init", "-q", "-b", "main", str(proj)],
        check=True,
        capture_output=True,
    )
    (proj / "README.md").write_text(f"# {name}\n")
    subprocess.run(
        ["git", "-C", str(proj), "add", "README.md"],
        check=True,
        capture_output=True,
    )
    env = os.environ | {
        "GIT_AUTHOR_NAME": "test",
        "GIT_AUTHOR_EMAIL": "t@t",
        "GIT_COMMITTER_NAME": "test",
        "GIT_COMMITTER_EMAIL": "t@t",
    }
    subprocess.run(
        ["git", "-C", str(proj), "commit", "-q", "-m", "init"],
        check=True,
        capture_output=True,
        env=env,
    )
    return proj


def _make_tmux_wrapper(bin_dir: Path, socket: str) -> None:
    """Put a `tmux` shim on PATH that forces all calls onto our socket.

    Nvim's claude_popup.lua calls plain `tmux ...`; we want those calls to
    target the isolated test server, not the user's default. The shim just
    prepends `-L <socket>` and delegates to the real binary.
    """
    import shutil
    real_tmux = shutil.which("tmux") or "/usr/bin/tmux"
    wrapper = bin_dir / "tmux"
    wrapper.write_text(textwrap.dedent(f"""\
        #!/usr/bin/env bash
        exec {real_tmux} -L {socket} "$@"
    """))
    wrapper.chmod(0o755)


def _session_name_for(project_dir: Path) -> str:
    """Call the Lua project.session_name() from headless nvim in the dir."""
    # Write result to a temp file — more reliable than stdout from headless nvim
    out_file = project_dir / ".session_name"
    subprocess.run(
        [
            "nvim",
            "--headless",
            "--clean",
            "-c",
            f"lua vim.cmd('cd {project_dir}')",
            "-c",
            f"lua vim.opt.rtp:prepend('{REPO_ROOT}')",
            "-c",
            f"lua vim.fn.writefile({{require('tmux.project').session_name()}}, '{out_file}')",
            "-c",
            "qa!",
        ],
        check=True,
        text=True,
        capture_output=True,
    )
    return out_file.read_text().strip()


def _ensure_session(project_dir: Path, bin_dir: Path) -> None:
    """Headless nvim in project_dir: require claude_popup and call ensure()."""
    env = os.environ | {
        # Force TMUX so claude_popup.open's guard would pass; ensure() itself
        # doesn't check TMUX, but we keep the env clean for future changes.
        "TMUX": "/tmp/fake,1,0",
        "PATH": f"{bin_dir}:{os.environ['PATH']}",
    }
    subprocess.run(
        [
            "nvim",
            "--headless",
            "--clean",
            "-c",
            f"lua vim.cmd('cd {project_dir}')",
            "-c",
            f"lua vim.opt.rtp:prepend('{REPO_ROOT}')",
            "-c",
            "lua require('tmux.claude_popup').ensure()",
            "-c",
            "qa!",
        ],
        check=True,
        text=True,
        capture_output=True,
        env=env,
    )


def test_two_projects_get_two_sessions(tmux_socket: str, tmp_path: Path):
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    _make_tmux_wrapper(bin_dir, tmux_socket)

    proj_a = _make_project(tmp_path / "repos", "proj-a")
    proj_b = _make_project(tmp_path / "repos", "proj-b")

    # Names should differ (different project roots)
    name_a = _session_name_for(proj_a)
    name_b = _session_name_for(proj_b)
    assert name_a == "cc-proj-a"
    assert name_b == "cc-proj-b"
    assert name_a != name_b

    try:
        # Spawn both sessions via the real module (exercises claude_popup.ensure)
        _ensure_session(proj_a, bin_dir)
        _ensure_session(proj_b, bin_dir)

        # Both sessions exist
        assert subprocess.run(
            ["tmux", "-L", tmux_socket, "has-session", "-t", name_a],
            check=False,
        ).returncode == 0
        assert subprocess.run(
            ["tmux", "-L", tmux_socket, "has-session", "-t", name_b],
            check=False,
        ).returncode == 0

        # Send distinct payloads
        send_keys(tmux_socket, name_a, "hello-A", "Enter")
        send_keys(tmux_socket, name_b, "hello-B", "Enter")

        # Each session got its own ACK; neither got the other's
        wait_for_pane(tmux_socket, name_a, r"ACK:hello-A", timeout=5)
        wait_for_pane(tmux_socket, name_b, r"ACK:hello-B", timeout=5)
        out_a = capture_pane(tmux_socket, name_a)
        out_b = capture_pane(tmux_socket, name_b)
        assert "hello-B" not in out_a, f"proj-a session saw proj-b's input:\n{out_a}"
        assert "hello-A" not in out_b, f"proj-b session saw proj-a's input:\n{out_b}"
    finally:
        for s in (name_a, name_b):
            subprocess.run(
                ["tmux", "-L", tmux_socket, "kill-session", "-t", s],
                check=False,
                capture_output=True,
            )
