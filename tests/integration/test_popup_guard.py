"""Regression: lua/tmux/popup.lua guards lazygit/btop on missing binary.

Previously, `<leader>tg` / `<leader>tb` would spawn `tmux display-popup -E lazygit`
even when lazygit wasn't installed; tmux closed the popup the instant the
child exited → user saw a 50ms flash + no feedback. Guard now notifies +
aborts before the popup call."""

import os
import subprocess
import textwrap


def _run(snippet, timeout=15):
    return subprocess.run(
        ['nvim', '--clean', '--headless', '-u', 'NONE', '-c', f'lua {snippet}'],
        check=True, timeout=timeout, capture_output=True, text=True,
    )


def _make_guard_snippet(fn_name, tmp_path):
    notify_out = tmp_path / f'{fn_name}.notify'
    open_out = tmp_path / f'{fn_name}.open'
    snippet = textwrap.dedent(f'''
        local repo = '{os.getcwd()}'
        vim.opt.rtp:prepend(repo)
        vim.fn.executable = function(_) return 0 end
        local msg = ''
        vim.notify = function(m, lvl) msg = m end
        local opened = false
        package.loaded['tmux._popup'] = {{
          open = function(w, h, cmd) opened = true end,
        }}
        require('tmux.popup').{fn_name}()
        local fh = io.open('{notify_out}', 'w'); fh:write(msg); fh:close()
        fh = io.open('{open_out}', 'w'); fh:write(tostring(opened)); fh:close()
        vim.cmd('qa!')
    ''')
    return snippet, notify_out, open_out


def test_lazygit_missing_binary_notifies_and_skips(tmp_path):
    snippet, notify_out, open_out = _make_guard_snippet('lazygit', tmp_path)
    _run(snippet)
    msg = notify_out.read_text()
    assert 'lazygit not found' in msg, f'expected warn msg, got: {msg!r}'
    assert 'Install:' in msg
    assert open_out.read_text().strip() == 'false', 'popup must NOT open on missing binary'


def test_btop_missing_binary_notifies_and_skips(tmp_path):
    snippet, notify_out, open_out = _make_guard_snippet('btop', tmp_path)
    _run(snippet)
    msg = notify_out.read_text()
    assert 'btop not found' in msg, f'expected warn msg, got: {msg!r}'
    assert 'Install:' in msg
    assert open_out.read_text().strip() == 'false'


def test_scratch_falls_back_when_default_shell_missing(tmp_path):
    """If $SHELL points at a non-existent binary (rare but possible in
    minimal VMs), scratch falls back to zsh/bash/sh."""
    out = tmp_path / 'cmd.out'
    snippet = textwrap.dedent(f'''
        local repo = '{os.getcwd()}'
        vim.opt.rtp:prepend(repo)
        os.getenv = function(name)
          if name == 'SHELL' then return '/nonexistent/xyzsh' end
          return nil
        end
        vim.fn.executable = function(bin)
          if bin == '/nonexistent/xyzsh' then return 0 end
          if bin == 'zsh' then return 0 end
          if bin == 'bash' then return 1 end  -- bash available
          return 0
        end
        -- Stub git rev-parse so scratch picks a reasonable cwd.
        local orig_sys = vim.fn.system
        vim.fn.system = function(cmd)
          if type(cmd) == 'table' and cmd[2] == 'rev-parse' then
            return '/tmp/probe'
          end
          return orig_sys(cmd)
        end
        local captured
        package.loaded['tmux._popup'] = {{
          open = function(w, h, cmd) captured = cmd end,
        }}
        require('tmux.popup').scratch()
        local fh = io.open('{out}', 'w'); fh:write(captured or 'NIL'); fh:close()
        vim.cmd('qa!')
    ''')
    _run(snippet)
    cmd = out.read_text()
    assert 'bash -l' in cmd, f'expected bash fallback, got: {cmd!r}'
    assert 'xyzsh' not in cmd, f'broken $SHELL must not be used: {cmd!r}'
