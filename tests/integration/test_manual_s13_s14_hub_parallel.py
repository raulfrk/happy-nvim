# tests/integration/test_manual_s13_s14_hub_parallel.py
"""Manual-tests §13+§14 AUTO rows (todo 32.10):
hub picker merges, host pivot, scratch cc-<id> unaffected."""

import os
import subprocess
import textwrap
import json
import time


def _run_lua(snippet, timeout=15, env_extra=None):
    env = os.environ.copy()
    if env_extra:
        env.update(env_extra)
    return subprocess.run(
        ['nvim', '--clean', '--headless', '-u', 'NONE', '-c', f'lua {snippet}'],
        check=True, timeout=timeout, env=env, capture_output=True, text=True,
    )


def test_hub_merge_mixes_project_host_session(tmp_path):
    reg = tmp_path / 'projects.json'
    reg.write_text(json.dumps({'version': 1, 'projects': {
        'proj-x': {'kind': 'local', 'path': '/p/x', 'last_opened': int(time.time()),
                   'frecency': 0.5, 'open_count': 5, 'sandbox_written': False},
    }}))
    out = tmp_path / 'kinds.out'
    snippet = textwrap.dedent(f'''
        local repo = '{os.getcwd()}'
        vim.opt.rtp:prepend(repo)
        package.loaded['remote.hosts'] = {{
          list = function()
            return {{
              {{ host = '[+ Add host]', marker = 'add' }},
              {{ host = 'prod01', score = 1 }},
            }}
          end,
          record = function() end,
        }}
        local sources = require('happy.hub.sources')
        sources._set_tmux_fn_for_test(function(args)
          if args[2] == 'list-sessions' then return 'cc-orphan\\nremote-foo' end
          return ''
        end)
        local hub = require('happy.hub')
        hub._reset_weights_for_test()
        local rows = hub._merge_for_test()
        local kinds = {{}}
        for _, r in ipairs(rows) do kinds[r.kind] = (kinds[r.kind] or 0) + 1 end
        local fh = io.open('{out}', 'w')
        fh:write('project=' .. (kinds.project or 0))
        fh:write(',host=' .. (kinds.host or 0))
        fh:write(',session=' .. (kinds.session or 0))
        fh:close()
        vim.cmd('qa!')
    ''')
    _run_lua(snippet, env_extra={'HAPPY_PROJECTS_JSON_OVERRIDE': str(reg)})
    text = out.read_text()
    assert 'project=1' in text and 'host=1' in text and 'session=2' in text, text


def test_hub_host_on_pivot_spawns_tmux_new_window(tmp_path):
    out = tmp_path / 'argv.out'
    snippet = textwrap.dedent(f'''
        local repo = '{os.getcwd()}'
        vim.opt.rtp:prepend(repo)
        package.loaded['remote.hosts'] = {{
          list = function()
            return {{ {{ host = 'prod01', score = 1 }} }}
          end,
          record = function() end,
        }}
        local calls = {{}}
        vim.system = function(cmd, opts, cb)
          table.insert(calls, type(cmd) == 'table' and table.concat(cmd, ' ') or tostring(cmd))
          local handle = {{ _closed = false }}
          function handle:is_closing() return self._closed end
          function handle:kill() self._closed = true end
          function handle:wait() return {{ code = 0, stdout = '', stderr = '' }} end
          if cb then cb({{ code = 0 }}) end
          return handle
        end
        vim.fn.system = function(cmd)
          table.insert(calls, type(cmd) == 'table' and table.concat(cmd, ' ') or tostring(cmd))
          return ''
        end
        vim.fn.executable = function(bin) return bin == 'mosh' and 1 or 0 end
        local rows = require('happy.hub.sources').host_rows()
        rows[1].on_pivot()
        local fh = io.open('{out}', 'w')
        for _, c in ipairs(calls) do fh:write(c .. '\\n') end
        fh:close()
        vim.cmd('qa!')
    ''')
    _run_lua(snippet)
    assert 'tmux new-window mosh prod01' in out.read_text()


def test_cq_does_not_kill_pinned_cc_session(tmp_path):
    out = tmp_path / 'argv.out'
    snippet = textwrap.dedent(f'''
        local repo = '{os.getcwd()}'
        vim.opt.rtp:prepend(repo)
        vim.env.TMUX = 'dummy'
        local calls = {{}}
        vim.system = function(cmd, opts, cb)
          table.insert(calls, table.concat(cmd, ' '))
          local handle = {{ _closed = false }}
          function handle:is_closing() return self._closed end
          function handle:kill() self._closed = true end
          function handle:wait() return {{ code = 0 }} end
          if cb then cb({{ code = 0 }}) end
          return handle
        end
        package.loaded['happy.projects.registry'] = {{
          add = function() return 'proj-x' end,
          get = function() return {{ kind = 'local', path = '/tmp' }} end,
          touch = function() end,
          score = function() return 0 end,
        }}
        vim.fn.getcwd = function() return '/tmp' end
        require('tmux.claude').open_scratch()
        -- Assert kill-session argv NEVER targets the pinned `cc-proj-x`
        -- (only `cc-proj-x-scratch-<ts>`).
        local fh = io.open('{out}', 'w')
        for _, c in ipairs(calls) do fh:write(c .. '\\n') end
        fh:close()
        vim.cmd('qa!')
    ''')
    _run_lua(snippet)
    log = out.read_text()
    # Pinned cc-proj-x should NOT be killed. Only the popup-close callback
    # kills the scratch session (which contains '-scratch-' in the name).
    # Since we don't fire the callback in this test, NO kill-session should
    # appear at all.
    for line in log.splitlines():
        if 'tmux kill-session' in line:
            assert '-scratch-' in line, f'pinned session must not be killed: {line}'
