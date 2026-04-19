import os
import subprocess
import textwrap


def _run_lua(snippet, timeout=15):
    return subprocess.run(
        ['nvim', '--clean', '--headless', '-u', 'NONE', '-c', f'lua {snippet}'],
        check=True, timeout=timeout, capture_output=True, text=True,
    )


def test_sc_spawns_ssh_and_creates_scratch_buffer(tmp_path):
    argv_path = tmp_path / 'argv.out'
    bufname_path = tmp_path / 'bufname.out'
    snippet = textwrap.dedent(f'''
        local repo = '{os.getcwd()}'
        vim.opt.rtp:prepend(repo)
        local captured
        vim.system = function(cmd, opts, cb)
          captured = cmd
          local handle = {{ _closed = false }}
          function handle:is_closing() return self._closed end
          function handle:kill() self._closed = true end
          if cb then vim.schedule(function() cb({{ code = 0 }}) end) end
          return handle
        end
        local cmd = require('remote.cmd')
        cmd._stream_to_scratch('prod01', 'df -h')
        vim.wait(200, function() return false end, 50)
        local fh = io.open('{argv_path}', 'w')
        fh:write(vim.inspect(captured)); fh:close()
        fh = io.open('{bufname_path}', 'w')
        fh:write(vim.api.nvim_buf_get_name(0)); fh:close()
        vim.cmd('qa!')
    ''')
    _run_lua(snippet)
    argv = argv_path.read_text()
    assert '"ssh"' in argv and '"prod01"' in argv and '"df -h"' in argv, argv
    bufname = bufname_path.read_text()
    assert '[ssh prod01: df -h]' in bufname, bufname
