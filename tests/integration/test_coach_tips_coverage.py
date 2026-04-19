# tests/integration/test_coach_tips_coverage.py
"""30.9 + 30.10 + 30.11: cheatsheet coverage audit for undotree,
fugitive, remote, claude, projects, capture keymap clusters."""

import os
import subprocess
import textwrap
import json


def _dump_tips(tmp_path):
    out = tmp_path / 'tips.json'
    snippet = textwrap.dedent(f'''
        local repo = '{os.getcwd()}'
        vim.opt.rtp:prepend(repo)
        local tips = dofile(repo .. '/lua/coach/tips.lua')
        local fh = io.open('{out}', 'w')
        fh:write(vim.json.encode(tips)); fh:close()
        vim.cmd('qa!')
    ''')
    subprocess.run(
        ['nvim', '--clean', '--headless', '-u', 'NONE', '-c', f'lua {snippet}'],
        check=True, timeout=15,
    )
    return json.loads(out.read_text())


def test_tips_include_new_categories(tmp_path):
    tips = _dump_tips(tmp_path)
    categories = {t.get('category') for t in tips}
    required = {'undo', 'git', 'remote', 'claude', 'projects', 'capture'}
    missing = required - categories
    assert not missing, f'tips missing categories: {missing}. Present: {categories}'


def test_tips_include_required_keymaps(tmp_path):
    tips = _dump_tips(tmp_path)
    keys_present = {t.get('keys') for t in tips}
    required_keys = {
        '<leader>u',
        '<leader>gs',
        '<leader>ss',
        '<leader>cc',
        '<leader>ck',
        '<leader>P',
        '<leader>Cc',
    }
    missing = required_keys - keys_present
    assert not missing, (
        f'tips missing required keymaps: {missing}. Tips count: {len(tips)}.'
    )


def test_tips_grew(tmp_path):
    tips = _dump_tips(tmp_path)
    assert len(tips) >= 55, f'tips count {len(tips)} < 55, batch not applied'
