# tests/integration/test_manual_s5_multiproject.py
"""Manual-tests §5 AUTO rows (todo 32.5):
<Space>cf routes to A's claude, prewarm attach."""

import os
import subprocess
import textwrap


def _run_lua(snippet, timeout=15):
    return subprocess.run(
        ['nvim', '--clean', '--headless', '-u', 'NONE', '-c', f'lua {snippet}'],
        check=True, timeout=timeout, capture_output=True, text=True,
    )


def test_cf_routes_to_current_project_session(tmp_path):
    out = tmp_path / 'pane.out'
    snippet = textwrap.dedent(f'''
        local repo = '{os.getcwd()}'
        vim.opt.rtp:prepend(repo)
        -- Stub registry so current cwd resolves to proj-a.
        package.loaded['happy.projects.registry'] = {{
          add = function() return 'proj-a' end,
          get = function() return {{ kind = 'local', path = '/p/a' }} end,
          touch = function() end,
          score = function() return 0 end,
        }}
        -- Stub tmux calls so send.resolve_target picks session cc-proj-a.
        vim.system = function(cmd, opts)
          local key = type(cmd) == 'table' and table.concat(cmd, ' ') or tostring(cmd)
          local out = ''
          local code = 0
          if key:match('tmux has%-session %-t cc%-proj%-a') then
            code = 0
          elseif key:match('tmux list%-panes') then
            out = '%99\\n'
          end
          return {{
            wait = function() return {{ code = code, stdout = out, stderr = '' }} end,
          }}
        end
        local send = require('tmux.send')
        local pane, kind = send.resolve_target()
        local fh = io.open('{out}', 'w')
        fh:write(tostring(pane) .. ':' .. tostring(kind)); fh:close()
        vim.cmd('qa!')
    ''')
    _run_lua(snippet)
    result = out.read_text().strip()
    assert result.startswith('%99') and 'session' in result, result


def test_prewarm_attach_does_not_spawn_new_session(tmp_path):
    """If the per-project pane is already alive, <leader>cc should
    select-pane (focus), not spawn a new split."""
    out = tmp_path / 'argv.out'
    snippet = textwrap.dedent(f'''
        local repo = '{os.getcwd()}'
        vim.opt.rtp:prepend(repo)
        vim.env.TMUX = 'dummy'
        local calls = {{}}
        vim.system = function(cmd, opts, cb)
          local key = type(cmd) == 'table' and table.concat(cmd, ' ') or tostring(cmd)
          table.insert(calls, key)
          local stdout = ''
          local code = 0
          if key:match('show%-option') then
            -- Return a pre-existing pane id so pane_alive branch is checked.
            stdout = '%%77\\n'
          elseif key:match('list%-panes') then
            -- Pane is alive -> select-pane, no new split.
            stdout = '%%77\\n'
          end
          local handle = {{ _closed = false }}
          function handle:is_closing() return self._closed end
          function handle:kill() self._closed = true end
          function handle:wait() return {{ code = code, stdout = stdout, stderr = '' }} end
          if cb then cb({{ code = code }}) end
          return handle
        end
        vim.fn.system = function(cmd)
          local key = type(cmd) == 'table' and table.concat(cmd, ' ') or tostring(cmd)
          table.insert(calls, 'FN:' .. key)
          if key:match('display%-message') then return '200\\n' end
          return ''
        end
        package.loaded['happy.projects.registry'] = {{
          add = function() return 'proj-prewarm' end,
          get = function() return {{ kind = 'local', path = '/tmp' }} end,
          touch = function() end,
          score = function() return 0 end,
        }}
        vim.fn.getcwd = function() return '/tmp' end
        require('tmux.claude').open()
        local fh = io.open('{out}', 'w')
        for _, c in ipairs(calls) do fh:write(c .. '\\n') end
        fh:close()
        vim.cmd('qa!')
    ''')
    _run_lua(snippet)
    log = out.read_text()
    # Pane already alive: select-pane called, no new split spawned.
    assert 'tmux select-pane -t' in log, f'select-pane missing: {log}'
    assert 'tmux split-window' not in log, f'must not spawn new split: {log}'
