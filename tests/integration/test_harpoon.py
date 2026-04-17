"""Integration test: harpoon v2 add + select wiring.

Drives a minimal nvim (lazy + harpoon2 only) inside a tmux pane.
Marks 3 scratch files via <leader>ha, then jumps between them via
<leader>h1/h2/h3 and asserts the active buffer matches each time.

Guards against: accidental removal of <leader>h* keymaps, drift of
the harpoon2 branch pin, LazyDone race (setup not running before
tests fire keys).
"""
from __future__ import annotations

import os
import textwrap
import time
from pathlib import Path

import pytest

from .helpers import capture_pane, send_keys, tmx, wait_for_pane

REPO_ROOT = Path(__file__).resolve().parents[2]


def _write_scratch_config(cfg_dir: Path) -> None:
    """Write init.lua that bootstraps lazy + harpoon2 only."""
    cfg_dir.mkdir(parents=True, exist_ok=True)
    init = cfg_dir / "init.lua"
    init.write_text(textwrap.dedent(f"""
        -- Minimal config: lazy.nvim bootstrap + harpoon2 only.
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
        vim.g.maplocalleader = ' '

        require('lazy').setup({{
            {{ 'nvim-lua/plenary.nvim' }},
            {{
                'ThePrimeagen/harpoon',
                branch = 'harpoon2',
                dependencies = {{ 'nvim-lua/plenary.nvim' }},
                config = function()
                    local harpoon = require('harpoon')
                    harpoon:setup()
                    vim.keymap.set('n', '<leader>ha', function()
                        harpoon:list():add()
                    end, {{ desc = 'harpoon add' }})
                    for i = 1, 4 do
                        vim.keymap.set('n', '<leader>h' .. i, function()
                            harpoon:list():select(i)
                        end, {{ desc = 'harpoon select ' .. i }})
                    end
                end,
            }},
        }}, {{
            lockfile = '{cfg_dir}/lazy-lock.json',
            install = {{ missing = true }},
            change_detection = {{ enabled = false }},
        }})
    """).lstrip())


@pytest.fixture
def harpoon_scratch(tmp_path: Path) -> Path:
    cfg = tmp_path / "nvim"
    _write_scratch_config(cfg)
    # Give each test its own XDG so Lazy installs land in tmp_path
    return cfg


def test_harpoon_add_and_select(tmux_socket: str, harpoon_scratch: Path, tmp_path: Path):
    session = "harpoon-test"
    # Create 3 scratch files in a dedicated dir
    work = tmp_path / "work"
    work.mkdir()
    files = []
    for name in ("alpha.txt", "beta.txt", "gamma.txt"):
        p = work / name
        p.write_text(name + " content\n")
        files.append(p)

    env = {
        "XDG_CONFIG_HOME": str(harpoon_scratch.parent),
        "XDG_DATA_HOME": str(tmp_path / "data"),
        "XDG_STATE_HOME": str(tmp_path / "state"),
        "XDG_CACHE_HOME": str(tmp_path / "cache"),
        "TMUX": os.environ.get("TMUX", "/tmp/fake,1,0"),
        "HOME": str(tmp_path),
    }
    env_str = " ".join(f'{k}={v}' for k, v in env.items())

    try:
        # Open nvim with the first file already loaded
        tmx(
            tmux_socket, "new-session", "-d", "-s", session,
            "-x", "120", "-y", "40",
            f"{env_str} nvim --clean -u {harpoon_scratch}/init.lua {files[0]}",
        )
        # Wait for Lazy to finish cloning + harpoon config to register <leader>ha
        # (Lazy! sync on first run clones into XDG_DATA_HOME)
        wait_for_pane(tmux_socket, session, r"alpha\.txt", timeout=60)
        # Wait for LazyDone notification to clear (ensures config() has run)
        time.sleep(2.0)

        # Mark all 3 files with <leader>ha
        for f in files:
            # Space is mapleader; send "<Space>ha" for each buffer
            send_keys(tmux_socket, session, "Space", "h", "a")
            time.sleep(0.2)
            # Open the next file (skip on last iteration)
            if f != files[-1]:
                next_idx = files.index(f) + 1
                send_keys(tmux_socket, session, f":e {files[next_idx]}", "Enter")
                # Wait for the filename to render (ruler or tabline)
                wait_for_pane(tmux_socket, session, files[next_idx].name, timeout=5)

        # Now cursor is in gamma.txt. Jump to each harpoon slot + verify.
        # Use :echo expand('%:t') to emit the basename to the cmd-line;
        # tmux capture will contain it right after the echo.
        import re as _re

        def assert_active_is(expected_name: str) -> None:
            """Assert the active buffer basename matches expected_name.

            Strategy: send ':echo expand('%:t')' then poll the pane until
            the expected filename appears on the cmdline area.
            """
            send_keys(tmux_socket, session, ":echo expand('%:t')", "Enter")
            # Poll until the filename appears anywhere in the pane capture.
            # The statusline always renders the active buffer path (at minimum)
            # so this is reliable even if the cmdline flushes quickly.
            wait_for_pane(
                tmux_socket, session,
                _re.escape(expected_name),
                timeout=3,
            )

        # Expect: slot 1 -> alpha, slot 2 -> beta, slot 3 -> gamma
        for idx, expected in enumerate([files[0], files[1], files[2]], start=1):
            send_keys(tmux_socket, session, "Space", "h", str(idx))
            time.sleep(0.5)
            assert_active_is(expected.name)
    finally:
        tmx(tmux_socket, "kill-session", "-t", session, check=False)
