import os
import subprocess
import textwrap


def test_tail_spawns_tmux_session_with_ssh_tail_F(tmp_path):
    """_stream_tail(host, path) → start() → ensure_session() calls
    `tmux new-session -d -s tail-<host>-<slug> sh -c "<ssh argv> 2>&1 | tee <state>``.
    Assert tmux new-session with 'tail -F' + 'tee' embedded in the command,
    and that a scratch buffer named [tail host:path] is created."""
    argv_path = tmp_path / 'argv.out'
    bufname_path = tmp_path / 'bufname.out'
    state_dir = tmp_path / 'tails'
    snippet = textwrap.dedent(f'''
        local repo = '{os.getcwd()}'
        vim.opt.rtp:prepend(repo)
        local calls = {{}}
        -- vim.system is used in :wait() form by tail.lua's sys() helper.
        -- Must return a handle with a :wait() method.
        vim.system = function(cmd, opts, cb)
          local key = type(cmd) == 'table' and table.concat(cmd, ' ') or tostring(cmd)
          table.insert(calls, key)
          local code = 0
          local stdout = ''
          -- has-session → non-zero so ensure_session spawns a new one.
          if key:match('has%-session') then code = 1 end
          -- shellescape calls go through vim.fn — not vim.system.
          local handle = {{}}
          function handle:is_closing() return false end
          function handle:kill() end
          function handle:wait() return {{ code = code, stdout = stdout, stderr = '' }} end
          if cb then vim.schedule(function() cb({{ code = code }}) end) end
          return handle
        end
        -- Override state dir so mkdir doesn't fail in sandbox.
        local tail = require('remote.tail')
        tail._set_state_dir_for_test('{state_dir}')
        vim.fn.mkdir('{state_dir}', 'p')
        tail._stream_tail('prod01', '/var/log/syslog')
        vim.wait(200, function() return false end, 50)
        local fh = io.open('{argv_path}', 'w')
        for _, c in ipairs(calls) do fh:write(c .. '\\n') end
        fh:close()
        fh = io.open('{bufname_path}', 'w')
        for _, b in ipairs(vim.api.nvim_list_bufs()) do
          local n = vim.api.nvim_buf_get_name(b)
          if n:match('%[tail ') then fh:write(n) end
        end
        fh:close()
        vim.cmd('qa!')
    ''')
    subprocess.run(
        ['nvim', '--clean', '--headless', '-u', 'NONE', '-c', f'lua {snippet}'],
        check=True, timeout=15,
    )
    argv = argv_path.read_text()
    # tmux new-session call must be present with 'sh' + '-c' as executor.
    assert 'tmux new-session' in argv, f'tmux new-session missing:\n{argv}'
    # The sh -c payload embeds the ssh tail -F invocation and a tee pipe.
    assert 'tail -F' in argv, f'tail -F missing from session cmd:\n{argv}'
    assert 'tee' in argv, f'tee missing (state file piping) from session cmd:\n{argv}'
    # Session name follows the tail-<host>-<slug> convention.
    assert 'tail-prod01' in argv, f'session name prefix missing:\n{argv}'
    # Scratch buffer named [tail host:path] is created.
    bufname = bufname_path.read_text()
    assert '[tail prod01:/var/log/syslog]' in bufname, f'scratch buf name wrong: {bufname!r}'
