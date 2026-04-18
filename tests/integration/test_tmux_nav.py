"""Integration: <C-l> from nvim swaps active tmux pane (vim-tmux-navigator)."""
from __future__ import annotations

import os
import subprocess
import textwrap
import time
from pathlib import Path

import pytest

from .helpers import send_keys, tmx, wait_for_pane

REPO_ROOT = Path(__file__).resolve().parents[2]


def _write_scratch(cfg_dir: Path) -> Path:
    cfg_dir.mkdir(parents=True, exist_ok=True)
    init = cfg_dir / "init.lua"
    init.write_text(textwrap.dedent(f"""
        local data = vim.fn.stdpath('data')
        local lazypath = data .. '/lazy/lazy.nvim'
        if not vim.uv.fs_stat(lazypath) then
          vim.fn.system({{
            'git', 'clone', '--filter=blob:none',
            'https://github.com/folke/lazy.nvim.git',
            '--branch=stable', lazypath,
          }})
        end
        vim.opt.rtp:prepend(lazypath)
        vim.g.mapleader = ' '
        require('lazy').setup({{
          {{ 'christoomey/vim-tmux-navigator' }},
        }}, {{ change_detection = {{ enabled = false }} }})
    """).lstrip())
    return cfg_dir


def _active_pane(tmux_socket: str, session: str) -> str:
    """Return the currently-active pane id within session."""
    out = subprocess.run(
        ["tmux", "-L", tmux_socket, "list-panes", "-t", session, "-F",
         "#{pane_active} #{pane_id}"],
        check=True, text=True, capture_output=True,
    ).stdout
    for line in out.splitlines():
        flag, pid = line.split()
        if flag == "1":
            return pid
    return ""


@pytest.fixture
def nav_scratch(tmp_path: Path) -> Path:
    return _write_scratch(tmp_path / "nvim")


def _tmux_real_socket(tmux_socket: str) -> str:
    """Get the real socket path for our isolated tmux server."""
    # tmux uses /tmp/tmux-<uid>/<socket-name> by default
    import pwd
    uid = os.getuid()
    return f"/tmp/tmux-{uid}/{tmux_socket}"


def test_ctrl_l_swaps_to_right_pane(tmux_socket: str, nav_scratch: Path, tmp_path: Path):
    # vim-tmux-navigator needs a real $TMUX var pointing to our server
    # so it can call 'tmux select-pane' to cross the pane boundary.
    real_socket = _tmux_real_socket(tmux_socket)
    env_str = (
        f"XDG_CONFIG_HOME={nav_scratch.parent}"
        f" XDG_DATA_HOME={tmp_path / 'data'}"
        f" XDG_STATE_HOME={tmp_path / 'state'}"
        f" XDG_CACHE_HOME={tmp_path / 'cache'}"
        f" HOME={tmp_path}"
        f" TMUX={real_socket},0,0"
    )
    session = "tmuxnav-test"
    try:
        tmx(
            tmux_socket, "new-session", "-d", "-s", session, "-x", "200", "-y", "40",
            f"{env_str} nvim --clean -u {nav_scratch}/init.lua",
        )
        # Wait for nvim to start + Lazy to finish installing vim-tmux-navigator
        wait_for_pane(tmux_socket, session, r"~|\[No Name\]|Installed", timeout=60)
        # Dismiss the Lazy dashboard (q closes it) and settle
        send_keys(tmux_socket, session, "q")
        time.sleep(1.5)
        # Add a right-side pane running a shell
        tmx(tmux_socket, "split-window", "-h", "-t", session, "-l", "50%", "bash")
        # Re-focus nvim (the new pane is active by default)
        tmx(tmux_socket, "select-pane", "-L", "-t", session)
        time.sleep(0.5)
        active_before = _active_pane(tmux_socket, session)
        # Press C-l in nvim
        send_keys(tmux_socket, active_before, "C-l")
        time.sleep(0.5)
        active_after = _active_pane(tmux_socket, session)
        assert active_after != active_before, (
            f"<C-l> didn't swap pane (still {active_after})"
        )
    finally:
        tmx(tmux_socket, "kill-session", "-t", session, check=False)
