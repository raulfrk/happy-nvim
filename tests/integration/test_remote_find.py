import os
import subprocess
import textwrap
import json


def test_sf_builds_find_cmd_and_returns_paths(tmp_path):
    argv_path = tmp_path / 'argv.out'
    paths_path = tmp_path / 'paths.out'
    snippet = textwrap.dedent(f'''
        local repo = '{os.getcwd()}'
        vim.opt.rtp:prepend(repo)

        local captured
        package.loaded['remote.util'] = {{
          run = function(cmd, opts, timeout)
            captured = cmd
            return {{
              code = 0,
              stdout = '/etc/hosts\\n/etc/passwd\\n/etc/resolv.conf\\n',
              stderr = '',
            }}
          end,
        }}

        local picker_paths
        package.loaded['telescope.pickers'] = {{
          new = function(_, opts)
            picker_paths = opts.finder._results or opts.finder.results
            return {{ find = function() end }}
          end,
        }}
        package.loaded['telescope.finders'] = {{
          new_table = function(spec)
            return {{ _results = spec.results, results = spec.results }}
          end,
        }}
        package.loaded['telescope.config'] = {{
          values = {{ generic_sorter = function() return nil end }},
        }}
        package.loaded['telescope.actions'] = {{
          select_default = {{ replace = function() end }},
          close = function() end,
        }}
        package.loaded['telescope.actions.state'] = {{
          get_selected_entry = function() end,
        }}

        local find = require('remote.find')
        find._list_then_pick('prod01', '/etc')
        vim.wait(100, function() return false end, 25)

        local fh = io.open('{argv_path}', 'w')
        fh:write(vim.inspect(captured)); fh:close()
        fh = io.open('{paths_path}', 'w')
        fh:write(vim.json.encode(picker_paths or {{}})); fh:close()
        vim.cmd('qa!')
    ''')
    subprocess.run(
        ['nvim', '--clean', '--headless', '-u', 'NONE', '-c', f'lua {snippet}'],
        check=True, timeout=15,
    )
    argv = argv_path.read_text()
    assert 'ssh' in argv and 'prod01' in argv
    assert 'find ' in argv and '-type f' in argv and '-maxdepth 6' in argv, argv
    assert "'/etc'" in argv, f'path not shell-escaped: {argv}'
    paths = json.loads(paths_path.read_text())
    assert paths == ['/etc/hosts', '/etc/passwd', '/etc/resolv.conf'], paths
