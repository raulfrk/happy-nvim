"""remote.browse.find picker supports C-g/C-t/C-v/C-y actions.

Assert the callbacks are wired (we can't drive the real picker in
headless nvim, but we can introspect attach_mappings indirectly by
asserting the module exposes a known M._picker_actions attribute)."""
import os
import subprocess
import textwrap


def test_browse_find_picker_actions_exposed(tmp_path):
    repo = os.getcwd()
    out = tmp_path / 'actions'
    snippet = textwrap.dedent(f'''
        local repo = '{repo}'
        vim.opt.rtp:prepend(repo)
        local browse = require('remote.browse')
        local keys = browse._picker_actions or {{}}
        local fh = io.open('{out}', 'w')
        for _, k in ipairs(keys) do fh:write(k .. '\\n') end
        fh:close()
        vim.cmd('qa!')
    ''')
    subprocess.run(
        ['nvim', '--clean', '--headless', '-u', 'NONE', '-c', f'lua {snippet}'],
        check=True, timeout=10, capture_output=True, text=True,
    )
    body = out.read_text().splitlines()
    for k in ('<C-g>', '<C-t>', '<C-v>', '<C-y>'):
        assert k in body, f'missing picker action: {k}'
