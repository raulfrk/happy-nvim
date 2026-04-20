# tests/integration/test_conform_format_once.py
"""BUG-1 regression (replaces the Mason-race test_lsp_format.py).

conform.nvim must be the SOLE format-on-save owner — :w fires conform
exactly once, never twice via competing autocmds or LSP formatProvider.
Uses stylua on .lua to sidestep Mason (stylua is a system binary, skip-
if-missing)."""

import os
import shutil
import subprocess
import textwrap


def test_conform_fires_once_on_save(tmp_path):
    if not shutil.which('stylua'):
        import pytest; pytest.skip('stylua not installed')

    work = tmp_path / 'w'; work.mkdir()
    probe = work / 'probe.lua'
    probe.write_text('local x   =   1\n')

    counter = tmp_path / 'fires.out'
    counter.write_text('0')

    snippet = textwrap.dedent(f'''
        local repo = '{os.getcwd()}'
        vim.opt.rtp:prepend(repo)
        vim.api.nvim_exec_autocmds('VimEnter', {{}})
        vim.wait(5000, function() return pcall(require, 'conform') end, 100)

        local orig_format = require('conform').format
        require('conform').format = function(opts, cb)
          local fh = io.open('{counter}', 'r')
          local n = tonumber(fh:read('*a')) or 0
          fh:close()
          fh = io.open('{counter}', 'w')
          fh:write(tostring(n + 1))
          fh:close()
          return orig_format(opts, cb)
        end

        vim.cmd('edit {probe}')
        vim.cmd('silent! write')
        vim.wait(2000, function() return false end, 100)
        vim.cmd('qa!')
    ''')

    env = os.environ.copy()
    scratch = tmp_path / 'xdg'
    (scratch / 'cfg').mkdir(parents=True, exist_ok=True)
    (scratch / 'data' / 'nvim').mkdir(parents=True, exist_ok=True)
    env['XDG_CONFIG_HOME'] = str(scratch / 'cfg')
    env['XDG_DATA_HOME'] = str(scratch / 'data')
    env['XDG_CACHE_HOME'] = str(scratch / 'cache')
    env['XDG_STATE_HOME'] = str(scratch / 'state')
    if not (scratch / 'cfg' / 'nvim').exists():
        os.symlink(os.getcwd(), scratch / 'cfg' / 'nvim')

    subprocess.run(
        ['nvim', '--headless', '-c', f'lua {snippet}'],
        env=env, check=True, timeout=60,
    )

    fires = int(counter.read_text().strip())
    assert fires == 1, f'conform.format fired {fires} times (expected 1)'
