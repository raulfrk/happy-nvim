# tests/integration/test_manual_s1_core_editing.py
"""Manual-tests §1 AUTO rows (todo 32.2):
stylua on save, harpoon marks, undotree open, fugitive open."""

import os
import subprocess
import textwrap


def _run_with_user_config(snippet, tmp_path, timeout=60):
    env = os.environ.copy()
    scratch = tmp_path / 'xdg'
    (scratch / 'cfg').mkdir(parents=True, exist_ok=True)
    (scratch / 'data' / 'nvim').mkdir(parents=True, exist_ok=True)
    env['XDG_CONFIG_HOME'] = str(scratch / 'cfg')
    env['XDG_DATA_HOME'] = str(scratch / 'data')
    env['XDG_CACHE_HOME'] = str(scratch / 'cache')
    env['XDG_STATE_HOME'] = str(scratch / 'state')
    cfg_nvim = scratch / 'cfg' / 'nvim'
    if not cfg_nvim.exists():
        os.symlink(os.getcwd(), cfg_nvim)
    return subprocess.run(
        ['nvim', '--headless', '-c', f'lua {snippet}'],
        env=env, check=True, timeout=timeout, capture_output=True, text=True,
    )


def _run_clean(snippet, timeout=15):
    return subprocess.run(
        ['nvim', '--clean', '--headless', '-u', 'NONE', '-c', f'lua {snippet}'],
        check=True, timeout=timeout, capture_output=True, text=True,
    )


def test_stylua_formats_on_save(tmp_path):
    """conform.nvim is wired to stylua on :w for lua files. If stylua is
    on PATH, save should reformat. If not, test passes trivially (the
    write-post autocmd fires but stylua skipped)."""
    import shutil
    if not shutil.which('stylua'):
        import pytest; pytest.skip('stylua not installed — cannot verify formatting')
    lua = tmp_path / 'probe.lua'
    lua.write_text("local x=1\nreturn  x\n")  # intentional unformatted
    snippet = textwrap.dedent(f'''
        vim.api.nvim_exec_autocmds('VimEnter', {{}})
        vim.wait(3000, function() return pcall(require, 'conform') end, 100)
        vim.cmd('edit {lua}')
        vim.cmd('silent! write')
        vim.wait(2000, function() return false end, 100)
        vim.cmd('qa!')
    ''')
    _run_with_user_config(snippet, tmp_path, timeout=30)
    formatted = lua.read_text()
    # stylua inserts spaces around `=` and collapses double-spaces.
    assert 'local x = 1' in formatted, formatted


def test_harpoon_add_and_list(tmp_path):
    out = tmp_path / 'count.out'
    snippet = textwrap.dedent(f'''
        vim.api.nvim_exec_autocmds('VimEnter', {{}})
        vim.wait(5000, function() return pcall(require, 'harpoon') end, 100)
        local harpoon = require('harpoon')
        harpoon:setup({{}})
        harpoon:list():add({{ value = '/tmp/a.lua', context = {{}} }})
        harpoon:list():add({{ value = '/tmp/b.lua', context = {{}} }})
        harpoon:list():add({{ value = '/tmp/c.lua', context = {{}} }})
        local fh = io.open('{out}', 'w')
        fh:write(tostring(harpoon:list():length())); fh:close()
        vim.cmd('qa!')
    ''')
    _run_with_user_config(snippet, tmp_path, timeout=30)
    assert out.read_text().strip() == '3'


def test_harpoon_select_switches_buffer(tmp_path):
    a = tmp_path / 'a.lua'; a.write_text('-- a')
    b = tmp_path / 'b.lua'; b.write_text('-- b')
    out = tmp_path / 'cur.out'
    snippet = textwrap.dedent(f'''
        vim.api.nvim_exec_autocmds('VimEnter', {{}})
        vim.wait(5000, function() return pcall(require, 'harpoon') end, 100)
        local harpoon = require('harpoon')
        harpoon:setup({{}})
        harpoon:list():add({{ value = '{a}', context = {{}} }})
        harpoon:list():add({{ value = '{b}', context = {{}} }})
        harpoon:list():select(2)
        vim.wait(200, function() return false end, 50)
        local fh = io.open('{out}', 'w')
        fh:write(vim.api.nvim_buf_get_name(0)); fh:close()
        vim.cmd('qa!')
    ''')
    _run_with_user_config(snippet, tmp_path, timeout=30)
    assert str(b) in out.read_text()


def test_undotree_toggle_opens_panel(tmp_path):
    out = tmp_path / 'ft.out'
    snippet = textwrap.dedent(f'''
        vim.api.nvim_exec_autocmds('VimEnter', {{}})
        vim.wait(5000, function() return vim.fn.exists(':UndotreeToggle') == 2 end, 100)
        vim.cmd('UndotreeToggle')
        vim.wait(500, function() return false end, 50)
        local fts = {{}}
        for _, b in ipairs(vim.api.nvim_list_bufs()) do
          table.insert(fts, vim.bo[b].filetype)
        end
        local fh = io.open('{out}', 'w'); fh:write(table.concat(fts, ',')); fh:close()
        vim.cmd('qa!')
    ''')
    _run_with_user_config(snippet, tmp_path, timeout=30)
    assert 'undotree' in out.read_text()


def test_fugitive_git_opens_split(tmp_path):
    # Use the repo's own .git so :Git has something to show.
    out = tmp_path / 'ft.out'
    snippet = textwrap.dedent(f'''
        vim.api.nvim_exec_autocmds('VimEnter', {{}})
        vim.wait(5000, function() return vim.fn.exists(':Git') == 2 end, 100)
        vim.cmd('edit README.md')
        vim.cmd('Git')
        vim.wait(500, function() return false end, 50)
        local fts = {{}}
        for _, b in ipairs(vim.api.nvim_list_bufs()) do
          table.insert(fts, vim.bo[b].filetype)
        end
        local fh = io.open('{out}', 'w'); fh:write(table.concat(fts, ',')); fh:close()
        vim.cmd('qa!')
    ''')
    _run_with_user_config(snippet, tmp_path, timeout=30)
    assert 'fugitive' in out.read_text()


def test_telescope_harpoon_picker_opens(tmp_path):
    out = tmp_path / 'ok.out'
    snippet = textwrap.dedent(f'''
        vim.api.nvim_exec_autocmds('VimEnter', {{}})
        vim.wait(5000, function() return pcall(require, 'telescope') end, 100)
        local ok = pcall(require, 'telescope._extensions.harpoon')
        local fh = io.open('{out}', 'w'); fh:write(tostring(ok)); fh:close()
        vim.cmd('qa!')
    ''')
    _run_with_user_config(snippet, tmp_path, timeout=30)
    assert out.read_text().strip() == 'true'
