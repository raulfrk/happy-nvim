"""ssh_buffer: default read-only; toggle_writable flips it."""
import os
import subprocess
import textwrap


def test_default_readonly_refuses_write(tmp_path):
    repo = os.getcwd()
    out = tmp_path / 'result'
    snippet = textwrap.dedent(f'''
        local repo = '{repo}'
        vim.opt.rtp:prepend(repo)
        vim.opt.swapfile = false
        package.loaded['remote.hosts'] = {{
          ensure_home_dir = function() return '/h' end,
          expand_path = function(_, p) return p end,
        }}
        package.loaded['remote.browse'] = {{ _is_binary = function() return false end }}
        package.loaded['remote.ssh_exec'] = {{
          argv = function(h, c) return {{'true'}} end,
          run = function() return {{ code = 0, stdout = 'line', stderr = '' }} end,
        }}
        local notified = ''
        vim.notify = function(m) notified = notified .. m .. '\\n' end
        local ssh_buffer = require('remote.ssh_buffer')
        local buf = ssh_buffer.open('h', '/tmp/f')
        -- Manually clear readonly so BufWriteCmd fires, but leave
        -- happy_ssh_writable unset so the Lua guard inside it fires.
        vim.bo[buf].readonly = false
        vim.api.nvim_buf_set_option(buf, 'modified', true)
        pcall(vim.cmd, 'write')
        local fh = io.open('{out}', 'w'); fh:write(notified); fh:close()
    ''')
    subprocess.run(
        ['nvim', '--clean', '--headless', '-u', 'NONE',
         '-c', f'lua {snippet}', '-c', 'qa!'],
        check=True, timeout=15, capture_output=True, text=True,
    )
    msg = out.read_text()
    assert 'read-only' in msg, f'expected read-only warning, got: {msg!r}'
