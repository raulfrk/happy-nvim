import os
import subprocess
import textwrap


def _run_lua(snippet, timeout=15):
    return subprocess.run(
        ['nvim', '--clean', '--headless', '-u', 'NONE', '-c', f'lua {snippet}'],
        check=True, timeout=timeout, capture_output=True, text=True,
    )


def test_osc52_wraps_in_tmux_dcs_when_tmux_set(tmp_path):
    out = tmp_path / 'osc.out'
    snippet = textwrap.dedent(f'''
        local repo = '{os.getcwd()}'
        vim.opt.rtp:prepend(repo)
        vim.env.TMUX = 'dummy-socket,1234,0'
        local cb = require('clipboard')
        local seq = cb._encode_osc52('hello')
        local fh = io.open('{out}', 'w')
        fh:write(seq or 'NIL'); fh:close()
        vim.cmd('qa!')
    ''')
    _run_lua(snippet)
    seq = out.read_text()
    assert seq.startswith('\x1bPtmux;'), f'missing DCS prefix: {seq[:20]!r}'
    assert seq.endswith('\x1b\\'), f'missing ST terminator: {seq[-4:]!r}'
    assert '\x1b\x1b]52;c;' in seq, 'inner OSC 52 not doubled for DCS passthrough'


def test_osc52_raw_when_tmux_unset(tmp_path):
    out = tmp_path / 'osc.out'
    snippet = textwrap.dedent(f'''
        local repo = '{os.getcwd()}'
        vim.opt.rtp:prepend(repo)
        vim.env.TMUX = nil
        local cb = require('clipboard')
        local seq = cb._encode_osc52('hello')
        local fh = io.open('{out}', 'w')
        fh:write(seq or 'NIL'); fh:close()
        vim.cmd('qa!')
    ''')
    _run_lua(snippet)
    seq = out.read_text()
    assert seq.startswith('\x1b]52;c;'), f'raw OSC 52 expected, got: {seq[:20]!r}'
    assert 'Ptmux' not in seq, 'should NOT be wrapped outside tmux'


def test_happy_check_clipboard_command_registered(tmp_path):
    out = tmp_path / 'exists.out'
    snippet = textwrap.dedent(f'''
        local repo = '{os.getcwd()}'
        vim.opt.rtp:prepend(repo)
        require('clipboard').setup()
        local fh = io.open('{out}', 'w')
        fh:write(tostring(vim.fn.exists(':HappyCheckClipboard'))); fh:close()
        vim.cmd('qa!')
    ''')
    _run_lua(snippet)
    assert out.read_text().strip() == '2'
