"""Integration test: Claude session survives nvim restart.

Spawn cc-<slug> via claude_popup.ensure() from a headless nvim,
type into the pane, kill that nvim entirely, start a fresh nvim
in the same dir, verify claude_popup.exists() is true + history
is intact via capture-pane.
"""
from __future__ import annotations

import os
import shutil
import subprocess
import textwrap
from pathlib import Path

from .helpers import capture_pane, send_keys, tmx, wait_for_pane

REPO_ROOT = Path(__file__).resolve().parents[2]


def _make_tmux_wrapper(bin_dir: Path, socket: str) -> None:
    real = shutil.which("tmux") or "/usr/bin/tmux"
    w = bin_dir / "tmux"
    w.write_text(f"#!/usr/bin/env bash\nexec {real} -L {socket} \"$@\"\n")
    w.chmod(0o755)


def _make_project(parent: Path, name: str) -> Path:
    p = parent / name
    p.mkdir(parents=True, exist_ok=True)
    subprocess.run(["git", "init", "-q", "-b", "main", str(p)], check=True, capture_output=True)
    (p / "README.md").write_text(name + "\n")
    env = os.environ | {
        "GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@t",
        "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@t",
    }
    subprocess.run(["git", "-C", str(p), "add", "README.md"], check=True, capture_output=True)
    subprocess.run(
        ["git", "-C", str(p), "commit", "-q", "-m", "init"],
        check=True, capture_output=True, env=env,
    )
    return p


def _ensure_session(project_dir: Path, bin_dir: Path) -> None:
    """Headless nvim in project_dir: claude_popup.ensure()."""
    env = os.environ | {
        "TMUX": "/tmp/fake,1,0",
        "PATH": f"{bin_dir}:{os.environ['PATH']}",
    }
    subprocess.run(
        [
            "nvim", "--headless", "--clean",
            "-c", f"lua vim.cmd('cd {project_dir}')",
            "-c", f"lua vim.opt.rtp:prepend('{REPO_ROOT}')",
            "-c", "lua require('tmux.claude_popup').ensure()",
            "-c", "qa!",
        ],
        check=True, text=True, capture_output=True, env=env,
    )


def _exists(project_dir: Path, bin_dir: Path) -> bool:
    """Headless nvim asks claude_popup.exists() for project_dir."""
    env = os.environ | {
        "TMUX": "/tmp/fake,1,0",
        "PATH": f"{bin_dir}:{os.environ['PATH']}",
    }
    out_file = bin_dir.parent / "exists.out"
    subprocess.run(
        [
            "nvim", "--headless", "--clean",
            "-c", f"lua vim.cmd('cd {project_dir}')",
            "-c", f"lua vim.opt.rtp:prepend('{REPO_ROOT}')",
            "-c", f"lua vim.fn.writefile({{tostring(require('tmux.claude_popup').exists())}}, '{out_file}')",
            "-c", "qa!",
        ],
        check=True, text=True, capture_output=True, env=env,
    )
    return out_file.read_text().strip() == "true"


def test_session_persists_across_nvim_restart(tmux_socket: str, tmp_path: Path):
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    _make_tmux_wrapper(bin_dir, tmux_socket)
    proj = _make_project(tmp_path / "repos", "persist-proj")
    session_name = "cc-persist-proj"

    try:
        # 1st nvim: spawn the session, send input
        _ensure_session(proj, bin_dir)
        # The pane was created in the session; grab the pane id
        pane = subprocess.run(
            ["tmux", "-L", tmux_socket, "list-panes", "-t", session_name, "-F", "#{pane_id}"],
            check=True, text=True, capture_output=True,
        ).stdout.strip()
        send_keys(tmux_socket, pane, "hello-from-old-nvim", "Enter")
        wait_for_pane(tmux_socket, pane, r"ACK:hello-from-old-nvim", timeout=5)

        # First nvim is already gone (subprocess returned). Now start a "second"
        # nvim invocation in the same project and verify exists() + history.
        assert _exists(proj, bin_dir), "session disappeared after first nvim exited"
        out = capture_pane(tmux_socket, pane)
        assert "ACK:hello-from-old-nvim" in out, (
            f"history lost across nvim restart:\n{out}"
        )
    finally:
        subprocess.run(
            ["tmux", "-L", tmux_socket, "kill-session", "-t", session_name],
            check=False, capture_output=True,
        )
