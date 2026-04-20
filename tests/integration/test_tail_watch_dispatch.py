"""remote.watch.scan fires vim.notify when tail line matches an active pattern."""
import os
import subprocess
import textwrap


def test_watch_scan_dispatches_notify(tmp_path):
    repo = os.getcwd()
    state = tmp_path / 'state.json'
    out = tmp_path / 'notifies'
    snippet = textwrap.dedent(f'''
        local repo = '{repo}'
        vim.opt.rtp:prepend(repo)
        local w = require('remote.watch')
        w._set_state_path_for_test('{state}')
        w.add('h', '/l', 'panic', {{ level = 'ERROR' }})
        local notifies = {{}}
        vim.notify = function(m, lvl) table.insert(notifies, m) end
        for _, line in ipairs({{'normal', 'kernel panic', 'ok'}}) do
          local hits = w.scan('h', '/l', line)
          for _, h in ipairs(hits) do
            vim.notify(('[%s] %s'):format(h.regex, line), vim.log.levels.ERROR)
          end
        end
        local fh = io.open('{out}', 'w')
        for _, n in ipairs(notifies) do fh:write(n .. '\\n') end
        fh:close()
        vim.cmd('qa!')
    ''')
    subprocess.run(
        ['nvim', '--clean', '--headless', '-u', 'NONE', '-c', f'lua {snippet}'],
        check=True, timeout=15, capture_output=True, text=True,
    )
    body = out.read_text()
    assert '[panic] kernel panic' in body, f'expected match notify, got: {body!r}'
    assert body.count('\n') == 1, 'should have exactly one notify'
