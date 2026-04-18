"""Integration: coach random_tip + cheatsheet picker.

Loads the real lua/coach via rtp:prepend, asserts random_tip()
returns a tip table, and asserts <leader>? opens a picker that
includes at least one known seed tip.
"""
from __future__ import annotations

import os
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
        vim.opt.rtp:prepend('{REPO_ROOT}')
        vim.g.mapleader = ' '
        vim.g.maplocalleader = ' '
        require('lazy').setup({{
          {{ 'nvim-lua/plenary.nvim' }},
          {{ 'nvim-telescope/telescope.nvim', branch = '0.1.x',
            dependencies = {{ 'nvim-lua/plenary.nvim' }} }},
        }}, {{ change_detection = {{ enabled = false }} }})
        require('coach').setup()
    """).lstrip())
    return cfg_dir


@pytest.fixture
def coach_scratch(tmp_path: Path) -> Path:
    return _write_scratch(tmp_path / "nvim")


def _env(coach_scratch: Path, tmp_path: Path) -> dict:
    return os.environ | {
        "XDG_CONFIG_HOME": str(coach_scratch.parent),
        "XDG_DATA_HOME": str(tmp_path / "data"),
        "XDG_STATE_HOME": str(tmp_path / "state"),
        "XDG_CACHE_HOME": str(tmp_path / "cache"),
        "TMUX": os.environ.get("TMUX", "/tmp/fake,1,0"),
        "HOME": str(tmp_path),
    }


def _env_str(coach_scratch: Path, tmp_path: Path) -> str:
    """Shell-safe subset of env vars for tmux new-session command string."""
    tmux_val = os.environ.get("TMUX", "/tmp/fake,1,0")
    return (
        f"XDG_CONFIG_HOME={coach_scratch.parent}"
        f" XDG_DATA_HOME={tmp_path / 'data'}"
        f" XDG_STATE_HOME={tmp_path / 'state'}"
        f" XDG_CACHE_HOME={tmp_path / 'cache'}"
        f" HOME={tmp_path}"
        f" TMUX={tmux_val}"
    )


def test_random_tip_returns_a_tip(tmux_socket: str, coach_scratch: Path, tmp_path: Path):
    """random_tip() returns a non-nil table with .keys + .desc fields."""
    out_file = tmp_path / "tip.out"
    env = _env(coach_scratch, tmp_path)
    import subprocess
    subprocess.run(
        [
            "nvim", "--headless", "--clean",
            "-c", f"lua vim.opt.rtp:prepend('{REPO_ROOT}')",
            "-c", "lua local t = require('coach').random_tip()",
            "-c", f"lua vim.fn.writefile({{vim.json.encode(require('coach').random_tip())}}, '{out_file}')",
            "-c", "qa!",
        ],
        check=True, text=True, capture_output=True, env=env,
    )
    import json
    payload = json.loads(out_file.read_text())
    assert isinstance(payload, dict), f"random_tip returned {payload!r}"
    assert payload.get("keys"), "tip missing 'keys' field"
    assert payload.get("desc"), "tip missing 'desc' field"


def test_cheatsheet_picker_opens(tmux_socket: str, coach_scratch: Path, tmp_path: Path):
    """<leader>? opens a telescope picker; at least one seed tip is visible."""
    work = tmp_path / "work"; work.mkdir()
    env = _env(coach_scratch, tmp_path)
    env_str = _env_str(coach_scratch, tmp_path)
    session = "coach-test"
    try:
        tmx(
            tmux_socket, "new-session", "-d", "-s", session, "-x", "120", "-y", "40",
            "-c", str(work),
            f"{env_str} nvim --clean -u {coach_scratch}/init.lua",
        )
        # Wait for Lazy + telescope + coach.setup
        time.sleep(2.0)
        # <leader>?
        send_keys(tmux_socket, session, "Space", "?")
        # Picker should show at least one seed tip — coach/tips.lua includes
        # 'ciw' (change inside word) which is in the first entries
        wait_for_pane(tmux_socket, session, r"ciw|gg / G|ci\"", timeout=10)
    finally:
        tmx(tmux_socket, "kill-session", "-t", session, check=False)
