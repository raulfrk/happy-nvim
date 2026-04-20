# tests/integration/test_manual_s7_health.py
""" Manual-tests §7 AUTO rows (todo 32.7):
:checkhealth happy-nvim section headers + no ERROR: lines."""

import os
import subprocess
import textwrap


def _run_lua(snippet, timeout=30):
    return subprocess.run(
        ['nvim', '--clean', '--headless', '-u', 'NONE', '-c', f'lua {snippet}'],
        check=True, timeout=timeout, capture_output=True, text=True,
    )


def _capture_health():
    out_path = '/tmp/happy-s7-health.out'
    snippet = textwrap.dedent(f'''
        local repo = '{os.getcwd()}'
        vim.opt.rtp:prepend(repo)
        vim.cmd('checkhealth happy')
        for _, b in ipairs(vim.api.nvim_list_bufs()) do
          if vim.api.nvim_buf_get_name(b):match('health:') then
            local lines = vim.api.nvim_buf_get_lines(b, 0, -1, false)
            local fh = io.open('{out_path}', 'w')
            for _, l in ipairs(lines) do fh:write(l .. '\\n') end
            fh:close()
            break
          end
        end
        vim.cmd('qa!')
    ''')
    _run_lua(snippet)
    with open(out_path) as f:
        return f.read()


def test_checkhealth_has_section_headers():
    health = _capture_health()
    assert 'Neovim' in health or 'core' in health.lower(), health[:500]


def test_checkhealth_has_no_error_lines():
    health = _capture_health()
    for line in health.splitlines():
        assert not line.strip().startswith('ERROR'), f'unexpected ERROR: {line}'
