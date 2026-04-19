# tests/integration/test_claude_ck_no_loop.py
"""Regression for 30.4: <leader>ck must NOT call vim.ui.select (whose
default inputlist backend loops on blank Enter). It must use
vim.fn.confirm + run popup.kill only when confirm returns 1."""

import os
import subprocess
import textwrap


def _run_nvim(snippet, cwd=None, env_extra=None, timeout=30):
    env = os.environ.copy()
    env.setdefault('XDG_CONFIG_HOME', '/tmp/happy-ux-t1-cfg')
    env.setdefault('XDG_DATA_HOME', '/tmp/happy-ux-t1-data')
    env.setdefault('XDG_CACHE_HOME', '/tmp/happy-ux-t1-cache')
    env.setdefault('XDG_STATE_HOME', '/tmp/happy-ux-t1-state')
    if env_extra:
        env.update(env_extra)
    return subprocess.run(
        ['nvim', '--clean', '--headless', '-u', 'NONE', '-c', f'lua {snippet}'],
        cwd=cwd or os.getcwd(), env=env, check=True, timeout=timeout,
    )


def test_ck_callback_uses_confirm_not_ui_select(tmp_path):
    confirm_path = tmp_path / 'confirm.out'
    select_path = tmp_path / 'select.out'
    kill_path = tmp_path / 'kill.out'

    snippet = textwrap.dedent(f'''
        local repo = '{os.getcwd()}'
        vim.opt.rtp:prepend(repo)

        for _, p in ipairs({{ '{confirm_path}', '{select_path}', '{kill_path}' }}) do
          local fh = io.open(p, 'w'); fh:write('0'); fh:close()
        end

        local function bump(path)
          local fh = io.open(path, 'r'); local n = tonumber(fh:read('*a') or '0') or 0; fh:close()
          fh = io.open(path, 'w'); fh:write(tostring(n + 1)); fh:close()
        end

        vim.ui.select = function(...) bump('{select_path}'); return nil end
        vim.fn.confirm = function(...) bump('{confirm_path}'); return 1 end

        package.loaded['tmux.claude_popup'] = {{
          exists = function() return true end,
          kill = function() bump('{kill_path}') end,
        }}
        package.loaded['tmux.project'] = {{
          session_name = function() return 'cc-probe' end,
        }}

        local spec = dofile(repo .. '/lua/plugins/tmux.lua')
        local ck
        for _, e in ipairs(spec.keys or {{}}) do
          if e[1] == '<leader>ck' then ck = e break end
        end
        assert(ck, '<leader>ck keymap entry not found in lua/plugins/tmux.lua')
        ck[2]()

        vim.cmd('qa!')
    ''')

    _run_nvim(snippet)

    assert confirm_path.read_text().strip() == '1', \
        f'vim.fn.confirm should have been called once; got {confirm_path.read_text()}'
    assert select_path.read_text().strip() == '0', \
        f'vim.ui.select should NOT have been called; got {select_path.read_text()}'
    assert kill_path.read_text().strip() == '1', \
        f'popup.kill should have run (confirm returned 1); got {kill_path.read_text()}'


def test_ck_callback_skips_kill_when_confirm_says_no(tmp_path):
    confirm_path = tmp_path / 'confirm.out'
    kill_path = tmp_path / 'kill.out'

    snippet = textwrap.dedent(f'''
        local repo = '{os.getcwd()}'
        vim.opt.rtp:prepend(repo)

        for _, p in ipairs({{ '{confirm_path}', '{kill_path}' }}) do
          local fh = io.open(p, 'w'); fh:write('0'); fh:close()
        end
        local function bump(path)
          local fh = io.open(path, 'r'); local n = tonumber(fh:read('*a') or '0') or 0; fh:close()
          fh = io.open(path, 'w'); fh:write(tostring(n + 1)); fh:close()
        end

        vim.fn.confirm = function(...) bump('{confirm_path}'); return 2 end
        package.loaded['tmux.claude_popup'] = {{
          exists = function() return true end,
          kill = function() bump('{kill_path}') end,
        }}
        package.loaded['tmux.project'] = {{
          session_name = function() return 'cc-probe' end,
        }}

        local spec = dofile(repo .. '/lua/plugins/tmux.lua')
        local ck
        for _, e in ipairs(spec.keys or {{}}) do
          if e[1] == '<leader>ck' then ck = e break end
        end
        ck[2]()

        vim.cmd('qa!')
    ''')

    _run_nvim(snippet)

    assert confirm_path.read_text().strip() == '1'
    assert kill_path.read_text().strip() == '0'
