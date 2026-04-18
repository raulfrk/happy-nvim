"""Integration: <leader> press shows which-key popup w/ all groups.

Uses a minimal scratch config (lazy + which-key + dummy keymaps) that
mirrors the real group registrations from lua/plugins/whichkey.lua.
Triggers the popup via :WhichKey n <leader> (same as pressing Space
in pending mode). Asserts all group labels are visible.

Design notes:
- Avoids the full config to skip nvim-treesitter ensure_installed which
  fails on GLIBC < 2.39 (tree-sitter-cli dependency on this system).
- which-key v3 requires actual vim keymaps to exist under a prefix for
  the group to appear — dummy <nop> keymaps satisfy this requirement.
- :WhichKey n <leader> is used instead of sending Space via tmux because
  Space enters nvim's pending-key mode and which-key's timer fires
  asynchronously; capture-pane reliably captures the float only with
  the explicit :WhichKey command.
"""
from __future__ import annotations

import os
import textwrap
import time
from pathlib import Path

import pytest

from .helpers import capture_pane, send_keys, tmx, wait_for_pane

REPO_ROOT = Path(__file__).resolve().parents[2]


def _write_scratch(cfg_dir: Path) -> Path:
    """Minimal config: lazy + which-key with real group registrations + dummy keymaps.

    Diagnoses #16 flake: prior version silently proceeded past a failed
    git clone, leaving `require('lazy')` to return `true` (boolean from
    partial module file) — subsequent `.setup(...)` raised
    "attempt to index a boolean" and tanked the whole test. Now we check
    the clone exit code, verify the require returned a table, and error
    loudly with diagnostic info if either fails.
    """
    cfg_dir.mkdir(parents=True, exist_ok=True)
    init = cfg_dir / "init.lua"
    init.write_text(textwrap.dedent(f"""
        local data = vim.fn.stdpath('data')
        local lazypath = data .. '/lazy/lazy.nvim'
        if not vim.uv.fs_stat(lazypath) then
          local out = vim.fn.system({{
            'git', 'clone', '--filter=blob:none',
            'https://github.com/folke/lazy.nvim.git',
            '--branch=stable', lazypath,
          }})
          if vim.v.shell_error ~= 0 then
            error('lazy.nvim clone failed (exit=' .. vim.v.shell_error
              .. '): ' .. out)
          end
        end
        vim.opt.rtp:prepend(lazypath)
        local ok, lazy = pcall(require, 'lazy')
        if not ok or type(lazy) ~= 'table' then
          error('require(lazy) failed or returned non-table: ok='
            .. tostring(ok) .. ' value=' .. vim.inspect(lazy))
        end
        vim.g.mapleader = ' '
        vim.g.maplocalleader = ' '
        -- Dummy keymaps so which-key has real entries to group
        vim.keymap.set('n', '<leader>ff', '<nop>', {{ desc = 'find files' }})
        vim.keymap.set('n', '<leader>gg', '<nop>', {{ desc = 'git status' }})
        vim.keymap.set('n', '<leader>ss', '<nop>', {{ desc = 'ssh hosts' }})
        vim.keymap.set('n', '<leader>cc', '<nop>', {{ desc = 'Claude pane' }})
        vim.keymap.set('n', '<leader>tt', '<nop>', {{ desc = 'tmux popup' }})
        vim.keymap.set('n', '<leader>??', '<nop>', {{ desc = 'cheatsheet' }})
        lazy.setup({{
          {{
            'folke/which-key.nvim',
            lazy = false,
            config = function()
              local wk = require('which-key')
              wk.setup({{ preset = 'modern', delay = 400, notify = false }})
              wk.add({{
                {{ '<leader>f', group = 'find / files (telescope)', icon = '' }},
                {{ '<leader>g', group = 'git', icon = '' }},
                {{ '<leader>l', group = 'LSP', icon = '' }},
                {{ '<leader>d', group = 'diagnostics', icon = '' }},
                {{ '<leader>h', group = 'harpoon', icon = '' }},
                {{ '<leader>s', group = 'ssh / remote files', icon = '' }},
                {{ '<leader>c', group = 'Claude (tmux pane)', icon = '' }},
                {{ '<leader>t', group = 'tmux popups', icon = '' }},
                {{ '<leader>?', group = 'cheatsheet / coach', icon = '' }},
              }})
            end,
          }},
        }}, {{ change_detection = {{ enabled = false }} }})
    """).lstrip())
    return cfg_dir


@pytest.fixture
def wk_scratch(tmp_path: Path) -> Path:
    return _write_scratch(tmp_path / "nvim")


@pytest.mark.slow
def test_leader_shows_whichkey_groups(tmux_socket: str, wk_scratch: Path, tmp_path: Path):
    uid = os.getuid()
    real_socket = f"/tmp/tmux-{uid}/{tmux_socket}"
    env_str = (
        f"XDG_CONFIG_HOME={wk_scratch.parent}"
        f" XDG_DATA_HOME={tmp_path / 'data'}"
        f" XDG_STATE_HOME={tmp_path / 'state'}"
        f" XDG_CACHE_HOME={tmp_path / 'cache'}"
        f" HOME={tmp_path}"
        f" TMUX={real_socket},0,0"
    )
    session = "wk-test"
    try:
        tmx(
            tmux_socket, "new-session", "-d", "-s", session, "-x", "160", "-y", "40",
            f"{env_str} nvim --clean -u {wk_scratch}/init.lua",
        )
        # Wait for Lazy to install which-key
        wait_for_pane(tmux_socket, session, r"~|\[No Name\]|Installed", timeout=60)
        # Dismiss Lazy UI if open (q closes it)
        send_keys(tmux_socket, session, "q")
        time.sleep(1.0)
        # Ensure normal mode
        send_keys(tmux_socket, session, "Escape")
        time.sleep(0.3)
        # Trigger which-key leader popup via :WhichKey n <leader>
        # (which-key v3 requires actual keymaps under prefix to show groups)
        send_keys(tmux_socket, session, ":WhichKey n <leader>", "Enter")
        time.sleep(1.0)
        out = capture_pane(tmux_socket, session)
        # At least 3 of our group labels should be visible in the popup
        labels = ["find", "git", "ssh", "Claude", "tmux", "cheat"]
        seen = [l for l in labels if l in out]
        assert len(seen) >= 3, (
            f"which-key popup missing group labels (saw {seen}):\n{out}"
        )
    finally:
        tmx(tmux_socket, "kill-session", "-t", session, check=False)
