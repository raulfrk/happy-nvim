import os
import subprocess
import textwrap
import json


def _dump_list(tmp_path, empty_db=True, empty_ssh=True):
    out = tmp_path / 'list.json'
    db_path = tmp_path / 'hosts.json'
    ssh_cfg = tmp_path / 'ssh_config'
    if not empty_db:
        db_path.write_text(json.dumps({'alpha': {'visits': 3, 'last_used': 1000}}))
    if not empty_ssh:
        ssh_cfg.write_text('Host bravo\n  HostName bravo.example.com\n')
    snippet = textwrap.dedent(f'''
        local repo = '{os.getcwd()}'
        vim.opt.rtp:prepend(repo)
        local hosts = require('remote.hosts')
        hosts._set_db_path_for_test('{db_path}')
        hosts._set_ssh_config_path_for_test('{ssh_cfg}')
        local entries = hosts.list()
        local fh = io.open('{out}', 'w')
        fh:write(vim.json.encode(entries)); fh:close()
        vim.cmd('qa!')
    ''')
    subprocess.run(
        ['nvim', '--clean', '--headless', '-u', 'NONE', '-c', f'lua {snippet}'],
        check=True, timeout=15,
    )
    return json.loads(out.read_text())


def test_empty_db_and_ssh_shows_add_marker(tmp_path):
    entries = _dump_list(tmp_path, empty_db=True, empty_ssh=True)
    assert len(entries) == 1, f'expected 1 entry, got {entries}'
    assert entries[0].get('marker') == 'add', entries[0]
    assert entries[0].get('host') == '[+ Add host]', entries[0]


def test_nonempty_db_prepends_add_marker(tmp_path):
    entries = _dump_list(tmp_path, empty_db=False, empty_ssh=True)
    assert len(entries) == 2, f'expected 2 entries, got {entries}'
    assert entries[0].get('marker') == 'add'
    assert entries[1].get('host') == 'alpha'
