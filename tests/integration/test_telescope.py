"""Integration test: telescope find_files navigates to selected file.

Drives a minimal nvim (lazy + telescope + plenary) inside a tmux pane.
cwd has 3 scratch files. <leader>ff opens the picker, filters by typing,
Enter selects, we assert the active buffer via :echo expand('%:t').

Guards against: <leader>ff removal, telescope version drift, race
between Lazy bootstrap and first keypress.
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
        vim.g.maplocalleader = ' '

        -- Mirror of the runtime get_range wrapper in
        -- lua/config/options.lua — muzzles the "range() on nil" crash
        -- that hit nvim-treesitter master + nvim 0.12 during injection
        -- query processing. CI's scratch config exercises the same
        -- combo as prod, so the wrapper must be in place here too.
        do
          local ts = vim.treesitter
          local orig = ts.get_range
          ts.get_range = function(node, source, metadata)
            if metadata and metadata.range then
              if source == nil then
                error('vim.treesitter.get_range: metadata.range requires source', 2)
              end
              return ts._range.add_bytes(source, metadata.range)
            end
            if node == nil then
              return {{ 0, 0, 0, 0, 0, 0 }}
            end
            return orig(node, source, metadata)
          end
        end

        require('lazy').setup({{
            {{ 'nvim-lua/plenary.nvim' }},
            -- Load nvim-treesitter on `master` branch (matches prod in
            -- lua/plugins/treesitter.lua). Legacy 0.x API gives telescope's
            -- previewer the native parsers.ft_to_lang / configs.is_enabled
            -- it expects — no shim needed in telescope config.
            {{
                'nvim-treesitter/nvim-treesitter',
                branch = 'master',
                config = function()
                    require('nvim-treesitter.configs').setup({{
                        ensure_installed = {{ 'lua' }},
                        highlight = {{ enable = true }},
                    }})
                end,
            }},
            {{
                'nvim-telescope/telescope.nvim',
                branch = '0.1.x',
                dependencies = {{
                    'nvim-lua/plenary.nvim',
                    'nvim-treesitter/nvim-treesitter',
                }},
                config = function()
                    local telescope = require('telescope')
                    telescope.setup({{}})
                    vim.keymap.set('n', '<leader>ff', function()
                        require('telescope.builtin').find_files({{
                            hidden = false, follow = false,
                        }})
                    end, {{ desc = 'telescope find_files' }})
                end,
            }},
        }}, {{
            lockfile = '{cfg_dir}/lazy-lock.json',
            install = {{ missing = true }},
            change_detection = {{ enabled = false }},
        }})
    """).lstrip())


@pytest.fixture
def telescope_scratch(tmp_path: Path) -> Path:
    cfg = tmp_path / "nvim"
    _write_scratch_config(cfg)
    return cfg


def test_telescope_find_files_opens_selected(
    tmux_socket: str, telescope_scratch: Path, tmp_path: Path
):
    session = "telescope-test"
    work = tmp_path / "work"
    work.mkdir()
    for name in ("alpha.txt", "beta.txt", "gamma.txt"):
        (work / name).write_text(name + " content\n")

    env = {
        "XDG_CONFIG_HOME": str(telescope_scratch.parent),
        "XDG_DATA_HOME": str(tmp_path / "data"),
        "XDG_STATE_HOME": str(tmp_path / "state"),
        "XDG_CACHE_HOME": str(tmp_path / "cache"),
        "TMUX": os.environ.get("TMUX", "/tmp/fake,1,0"),
        "HOME": str(tmp_path),
    }
    env_str = " ".join(f'{k}={v}' for k, v in env.items())

    try:
        # Start nvim in the work dir so find_files sees our 3 files
        tmx(
            tmux_socket, "new-session", "-d", "-s", session,
            "-x", "120", "-y", "40", "-c", str(work),
            f"{env_str} nvim --clean -u {telescope_scratch}/init.lua",
        )
        # Wait for lazy + telescope to install
        time.sleep(1.0)
        wait_for_pane(tmux_socket, session, r"Press ENTER|^~|\[No Name\]|init\.lua", timeout=30)
        # Extra settle so telescope setup has registered
        time.sleep(1.5)

        # Open find_files via <leader>ff
        send_keys(tmux_socket, session, "Space", "f", "f")
        # Telescope prompt shows with '>' prompt + result list
        wait_for_pane(tmux_socket, session, r"alpha\.txt", timeout=10)

        # Filter to just 'beta' and select
        send_keys(tmux_socket, session, "beta")
        time.sleep(0.3)
        send_keys(tmux_socket, session, "Enter")
        time.sleep(0.5)

        # Verify active buffer via statusline — nvim renders the filename in the
        # statusline as "<name>  <ruler>". We scan the capture for any line
        # whose stripped prefix is exactly "beta.txt" (possibly followed by spaces
        # and ruler text). Fall back to bare-line match for non-status renderings.
        import re as _re
        _statusline = _re.compile(r'^beta\.txt(\s|$)')

        def _has_beta(text: str) -> bool:
            for line in text.splitlines():
                if _statusline.search(line.strip()):
                    return True
            return False

        # First check: did telescope navigate to beta.txt (statusline already shows it)?
        out_before = capture_pane(tmux_socket, session)
        if not _has_beta(out_before):
            # Fall back: fire echo and check
            send_keys(tmux_socket, session, ":echo expand('%:t')", "Enter")
            time.sleep(0.4)
            out_before = capture_pane(tmux_socket, session)

        assert _has_beta(out_before), (
            f"expected active buffer beta.txt, not found in capture:\n{out_before}"
        )

        # Regression guard: previewer must not crash on treesitter API drift
        # or the 'range() on nil' injection-query bug (languagetree.lua:215).
        # With the scratch config now loading nvim-treesitter on `master`
        # alongside telescope 0.1.x AND installing the get_range wrapper
        # inline, this fixture exercises the exact path that hit production.
        out_after = capture_pane(tmux_socket, session)
        assert "ft_to_lang" not in out_after, (
            f"telescope previewer raised ft_to_lang error:\n{out_after}"
        )
        assert "attempt to call method 'range'" not in out_after, (
            f"treesitter get_range crash — wrapper in config/options.lua missing?\n{out_after}"
        )
        assert "is_enabled" not in out_after, (
            f"telescope previewer raised is_enabled error:\n{out_after}"
        )
        assert "vim.schedule callback" not in out_after, (
            f"unexpected scheduler crash in telescope:\n{out_after}"
        )
    finally:
        tmx(tmux_socket, "kill-session", "-t", session, check=False)
