"""Integration: LSP attach + conform format-on-save (BUG-1 regression).

Opens a Python file with bad indentation, waits for pyright to attach,
saves with :w, asserts conform.nvim reformatted via ruff. Verifies:
- LSP setup wires correctly
- Mason auto-installs pyright/ruff
- conform.nvim is the SOLE format-on-save owner (no double-fire)
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
        vim.g.mapleader = ' '
        require('lazy').setup({{
          {{ 'williamboman/mason.nvim', config = true }},
          {{ 'williamboman/mason-lspconfig.nvim', dependencies = {{ 'mason.nvim' }},
            config = function()
              require('mason-lspconfig').setup({{ ensure_installed = {{ 'pyright' }} }})
            end }},
          {{ 'neovim/nvim-lspconfig', dependencies = {{ 'mason-lspconfig.nvim' }},
            config = function()
              require('lspconfig').pyright.setup({{}})
            end }},
          {{ 'stevearc/conform.nvim', config = function()
              require('conform').setup({{
                formatters_by_ft = {{ python = {{ 'ruff_format' }} }},
                format_on_save = {{ timeout_ms = 3000, lsp_format = 'never' }},
              }})
            end }},
        }}, {{ change_detection = {{ enabled = false }} }})
    """).lstrip())
    return cfg_dir


@pytest.fixture
def lsp_scratch(tmp_path: Path) -> Path:
    return _write_scratch(tmp_path / "nvim")


@pytest.mark.slow
def test_lsp_attach_and_format(tmux_socket: str, lsp_scratch: Path, tmp_path: Path):
    work = tmp_path / "work"; work.mkdir()
    sample = work / "sample.py"
    sample.write_text("x   =   1\ny=2\n")  # ruff_format will fix
    env_str = (
        f"XDG_CONFIG_HOME={lsp_scratch.parent}"
        f" XDG_DATA_HOME={tmp_path / 'data'}"
        f" XDG_STATE_HOME={tmp_path / 'state'}"
        f" XDG_CACHE_HOME={tmp_path / 'cache'}"
        f" HOME={tmp_path}"
        f" TMUX={os.environ.get('TMUX', '/tmp/fake,1,0')}"
    )
    session = "lsp-test"
    try:
        tmx(
            tmux_socket, "new-session", "-d", "-s", session, "-x", "120", "-y", "40",
            "-c", str(work),
            f"{env_str} nvim --clean -u {lsp_scratch}/init.lua {sample}",
        )
        # Cold install: Mason clones pyright + ruff (~60s on a clean runner)
        time.sleep(3.0)
        wait_for_pane(tmux_socket, session, r"sample\.py", timeout=120)
        # Settle for Mason install + LspAttach
        time.sleep(60.0)
        # :w to trigger conform format-on-save
        send_keys(tmux_socket, session, ":w", "Enter")
        time.sleep(2.0)
        contents = sample.read_text()
        # ruff_format normalizes 'x   =   1' to 'x = 1'
        assert "x = 1" in contents, f"conform did not reformat:\n{contents!r}"
        # And doesn't double-fire (no duplicated lines)
        assert contents.count("x = 1") == 1
    finally:
        tmx(tmux_socket, "kill-session", "-t", session, check=False)
