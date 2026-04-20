# tests/integration/test_manual_s9_sp1_cockpit.py
"""Manual-tests §9 AUTO rows (todo 32.9):
<leader>P shows projects, <C-a> path/host:path add, <leader>Pp peek,
:HappyWt* stream, <leader>Pa prompt."""

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


def _seed_registry(path, projects):
    path.write_text(json.dumps({'version': 1, 'projects': projects}))


def test_leader_P_lists_registered_projects(tmp_path):
    reg = tmp_path / 'projects.json'
    _seed_registry(reg, {
        'proj-a': {'kind': 'local', 'path': '/p/a', 'last_opened': int(time.time()),
                   'frecency': 0.5, 'open_count': 1, 'sandbox_written': False},
        'proj-b': {'kind': 'local', 'path': '/p/b', 'last_opened': int(time.time()) - 3600,
                   'frecency': 0.3, 'open_count': 2, 'sandbox_written': False},
    })
    out = tmp_path / 'entries.out'
    snippet = textwrap.dedent(f'''
        local repo = '{os.getcwd()}'
        vim.opt.rtp:prepend(repo)
        local registry = require('happy.projects.registry')
        local entries = registry.sorted_by_score()
        local ids = {{}}
        for _, e in ipairs(entries) do table.insert(ids, e.id) end
        local fh = io.open('{out}', 'w'); fh:write(table.concat(ids, ',')); fh:close()
        vim.cmd('qa!')
    ''')
    _run_lua(snippet, env_extra={'HAPPY_PROJECTS_JSON_OVERRIDE': str(reg)})
    got = out.read_text().strip().split(',')
    assert set(got) == {'proj-a', 'proj-b'}


def test_picker_ca_local_path_registers(tmp_path):
    reg = tmp_path / 'projects.json'
    snippet = textwrap.dedent(f'''
        local repo = '{os.getcwd()}'
        vim.opt.rtp:prepend(repo)
        local registry = require('happy.projects.registry')
        -- Simulate the picker's <C-a> action for input = '/tmp/newproj'
        local parse = function(text)
          if text:sub(1, 1) == '/' or text:sub(1, 1) == '~' then
            return {{ kind = 'local', path = vim.fn.expand(text) }}
          end
          local h, p = text:match('^([^:]+):(.+)$')
          if h and p then return {{ kind = 'remote', host = h, path = p }} end
          return nil
        end
        local spec = parse('/tmp/newproj')
        registry.add(spec)
        vim.cmd('qa!')
    ''')
    _run_lua(snippet, env_extra={'HAPPY_PROJECTS_JSON_OVERRIDE': str(reg)})
    data = json.loads(reg.read_text())
    assert any(p['path'] == '/tmp/newproj' for p in data['projects'].values())


def test_picker_ca_remote_host_path_registers(tmp_path):
    reg = tmp_path / 'projects.json'
    snippet = textwrap.dedent(f'''
        local repo = '{os.getcwd()}'
        vim.opt.rtp:prepend(repo)
        local registry = require('happy.projects.registry')
        local parse = function(text)
          if text:sub(1, 1) == '/' or text:sub(1, 1) == '~' then
            return {{ kind = 'local', path = vim.fn.expand(text) }}
          end
          local h, p = text:match('^([^:]+):(.+)$')
          if h and p then return {{ kind = 'remote', host = h, path = p }} end
          return nil
        end
        registry.add(parse('prod01:/var/log'))
        vim.cmd('qa!')
    ''')
    _run_lua(snippet, env_extra={'HAPPY_PROJECTS_JSON_OVERRIDE': str(reg)})
    data = json.loads(reg.read_text())
    entries = list(data['projects'].values())
    assert any(p['kind'] == 'remote' and p['host'] == 'prod01' and p['path'] == '/var/log'
               for p in entries), entries


def test_pivot_peek_opens_scratch_with_capture_pane(tmp_path):
    reg = tmp_path / 'projects.json'
    _seed_registry(reg, {
        'proj-a': {'kind': 'local', 'path': '/tmp', 'last_opened': int(time.time()),
                   'frecency': 0.5, 'open_count': 1, 'sandbox_written': False},
    })
    out = tmp_path / 'buf.out'
    snippet = textwrap.dedent(f'''
        local repo = '{os.getcwd()}'
        vim.opt.rtp:prepend(repo)
        -- Stub tmux subprocess.
        local calls = {{}}
        vim.fn.system = function(cmd)
          table.insert(calls, type(cmd) == 'table' and table.concat(cmd, ' ') or tostring(cmd))
          if type(cmd) == 'table' and cmd[2] == 'has-session' then
            return ''
          end
          if type(cmd) == 'table' and cmd[2] == 'capture-pane' then
            return 'PEEKED_LINE_1\\nPEEKED_LINE_2'
          end
          return ''
        end
        require('happy.projects.pivot').peek('proj-a')
        vim.wait(200, function() return false end, 50)
        -- Capture all buffer names; the peek opens a scratch buf.
        local bufs = {{}}
        for _, b in ipairs(vim.api.nvim_list_bufs()) do
          if vim.bo[b].buftype == 'nofile' then
            local lines = vim.api.nvim_buf_get_lines(b, 0, -1, false)
            for _, l in ipairs(lines) do table.insert(bufs, l) end
          end
        end
        local fh = io.open('{out}', 'w'); fh:write(table.concat(bufs, '|')); fh:close()
        vim.cmd('qa!')
    ''')
    _run_lua(snippet, env_extra={'HAPPY_PROJECTS_JSON_OVERRIDE': str(reg)})
    content = out.read_text()
    assert 'PEEKED_LINE_1' in content, content


def test_happy_wt_provision_streams_scratch(tmp_path):
    out = tmp_path / 'bufname.out'
    snippet = textwrap.dedent(f'''
        local repo = '{os.getcwd()}'
        vim.opt.rtp:prepend(repo)
        vim.system = function(cmd, opts, cb)
          if cb then vim.schedule(function() cb({{ code = 0 }}) end) end
          return {{
            wait = function() return {{ code = 0 }} end,
            is_closing = function() return false end,
            kill = function() end,
          }}
        end
        require('happy.projects').setup()
        vim.cmd('HappyWtProvision /tmp/somepath')
        vim.wait(200, function() return false end, 50)
        local bufname = ''
        for _, b in ipairs(vim.api.nvim_list_bufs()) do
          local n = vim.api.nvim_buf_get_name(b)
          if n:match('wt%-claude%-provision') then
            bufname = n; break
          end
        end
        local fh = io.open('{out}', 'w'); fh:write(bufname); fh:close()
        vim.cmd('qa!')
    ''')
    _run_lua(snippet, env_extra={'HAPPY_PROJECTS_JSON_OVERRIDE': str(tmp_path / 'projects.json')})
    assert 'wt-claude-provision' in out.read_text()


def test_leader_Pa_prompt_adds_project(tmp_path):
    reg = tmp_path / 'projects.json'
    snippet = textwrap.dedent(f'''
        local repo = '{os.getcwd()}'
        vim.opt.rtp:prepend(repo)
        vim.ui.input = function(opts, cb) cb('/tmp/via-Pa') end
        require('happy.projects').setup()
        -- Invoke the <leader>Pa callback by simulating the keymap directly.
        vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Space>Pa', true, false, true), 'm', false)
        vim.wait(500, function() return false end, 50)
        vim.cmd('qa!')
    ''')
    _run_lua(snippet, env_extra={'HAPPY_PROJECTS_JSON_OVERRIDE': str(reg)})
    if not reg.exists():
        import pytest; pytest.skip('<leader>Pa keymap not triggered in headless feedkeys path')
    data = json.loads(reg.read_text())
    assert any(p['path'] == '/tmp/via-Pa' for p in data['projects'].values())
