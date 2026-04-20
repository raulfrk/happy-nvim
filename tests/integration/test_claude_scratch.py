import os
import re
import subprocess
import textwrap


def test_scratch_spawns_kills_on_close(tmp_path):
    argv_log = tmp_path / 'argv.log'
    snippet = textwrap.dedent(f'''
        local repo = '{os.getcwd()}'
        vim.opt.rtp:prepend(repo)
        vim.env.TMUX = 'dummy'

        local calls = {{}}
        local saved_cb
        vim.system = function(cmd, opts, cb)
          table.insert(calls, table.concat(cmd, ' '))
          if cb then saved_cb = cb end
          return {{
            wait = function() return {{ code = 0, stdout = '', stderr = '' }} end,
            is_closing = function() return false end,
            kill = function() end,
          }}
        end

        package.loaded['happy.projects.registry'] = {{
          add = function() return 'proj-test' end,
          get = function() return {{ kind = 'local', path = '/tmp' }} end,
          touch = function() end,
          score = function() return 0 end,
        }}

        vim.fn.getcwd = function() return '/tmp' end
        local claude = require('tmux.claude')
        claude.open_scratch()

        -- saved_cb is the display-popup on-close callback, wrapped in
        -- vim.schedule_wrap. Calling it queues the kill-session onto the
        -- main loop; vim.wait drains that queue.
        if saved_cb then saved_cb() end
        vim.wait(500, function() return false end, 20)

        local fh = io.open('{argv_log}', 'w')
        for _, c in ipairs(calls) do fh:write(c .. '\\n') end
        fh:close()
        vim.cmd('qa!')
    ''')
    subprocess.run(
        ['nvim', '--clean', '--headless', '-u', 'NONE', '-c', f'lua {snippet}'],
        check=True, timeout=15,
    )
    log = argv_log.read_text()
    m = re.search(r'tmux new-session -d -s (cc-[\w\-]+-scratch-\d+)', log)
    assert m, f'scratch new-session missing: {log}'
    scratch = m.group(1)
    assert 'tmux display-popup' in log and f'tmux attach -t {scratch}' in log, log
    assert f'tmux kill-session -t {scratch}' in log, log


def test_scratch_uses_sandbox_for_remote_project(tmp_path):
    argv_log = tmp_path / 'argv.log'
    snippet = textwrap.dedent(f'''
        local repo = '{os.getcwd()}'
        vim.opt.rtp:prepend(repo)
        vim.env.TMUX = 'dummy'

        local calls = {{}}
        vim.system = function(cmd, opts, cb)
          table.insert(calls, table.concat(cmd, ' '))
          return {{
            wait = function() return {{ code = 0, stdout = '', stderr = '' }} end,
            is_closing = function() return false end,
            kill = function() end,
          }}
        end

        package.loaded['happy.projects.registry'] = {{
          add = function() return 'logs-prod01' end,
          get = function() return {{ kind = 'remote', host = 'prod01', path = '/var/log' }} end,
          touch = function() end,
          score = function() return 0 end,
        }}
        package.loaded['happy.projects.remote'] = {{
          sandbox_dir = function(id) return '/tmp/sandboxes/' .. id end,
        }}

        vim.fn.getcwd = function() return '/does/not/matter' end
        require('tmux.claude').open_scratch()

        local fh = io.open('{argv_log}', 'w')
        for _, c in ipairs(calls) do fh:write(c .. '\\n') end
        fh:close()
        vim.cmd('qa!')
    ''')
    subprocess.run(
        ['nvim', '--clean', '--headless', '-u', 'NONE', '-c', f'lua {snippet}'],
        check=True, timeout=15,
    )
    log = argv_log.read_text()
    assert '/tmp/sandboxes/logs-prod01' in log, (
        f'remote scratch must use sandbox dir as cwd: {log}'
    )
