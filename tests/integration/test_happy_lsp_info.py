"""Smoke test for 30.6: :HappyLspInfo user command must be registered after
nvim-lspconfig's config block runs — it's the 0.12-safe replacement for
:LspInfo (which was removed in nvim 0.12).

Strategy: skip Lazy + real nvim-lspconfig. Stub package.loaded for
`lspconfig`, `blink.cmp`, and `mason-lspconfig` w/ minimal fakes, dofile()
the plugin spec, invoke the nvim-lspconfig entry's `.config()` fn directly,
then assert `:HappyLspInfo` exists and prints the expected format.
"""
from __future__ import annotations

import subprocess
import textwrap
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]


def _load_spec_and_run_config(tmp_path: Path, extra_probe: str = '') -> str:
    """Run headless nvim, stub deps, call config(), then run `extra_probe`.

    Returns contents of `${tmp_path}/probe.out`.
    """
    out_path = tmp_path / 'probe.out'

    snippet = textwrap.dedent(f'''
        local repo = [[{REPO_ROOT}]]
        vim.opt.rtp:prepend(repo)

        -- Fakes. mason-lspconfig.setup() is called inside config fn; give
        -- it a no-op so we don't touch mason. lspconfig.<server>.setup() is
        -- called via handlers, so lspconfig needs a __index metatable that
        -- returns a table w/ .setup = noop for any server name.
        local noop = function() end
        local fake_server = {{ setup = noop }}
        local fake_lspconfig = setmetatable({{}}, {{
          __index = function() return fake_server end,
        }})
        package.loaded['lspconfig'] = fake_lspconfig

        package.loaded['blink.cmp'] = {{
          get_lsp_capabilities = function() return {{}} end,
        }}

        package.loaded['mason-lspconfig'] = {{ setup = noop }}

        -- Load the plugin spec list + find the nvim-lspconfig entry.
        local specs = dofile(repo .. '/lua/plugins/lsp.lua')
        local entry = nil
        for _, s in ipairs(specs) do
          if s[1] == 'neovim/nvim-lspconfig' then entry = s; break end
        end
        assert(entry, 'plugin spec list missing neovim/nvim-lspconfig entry')
        assert(type(entry.config) == 'function', 'nvim-lspconfig .config missing')
        entry.config()

        {extra_probe}

        vim.cmd('qa!')
    ''')

    subprocess.run(
        ['nvim', '--headless', '--clean', '-c', f'lua {snippet}'],
        check=True, timeout=30, capture_output=True, text=True,
    )
    return out_path.read_text().strip() if out_path.exists() else ''


def test_happy_lsp_info_command_registered(tmp_path):
    """After nvim-lspconfig config runs, :HappyLspInfo must exist."""
    probe = textwrap.dedent(f'''
        local fh = io.open([[{tmp_path / 'probe.out'}]], 'w')
        fh:write(tostring(vim.fn.exists(':HappyLspInfo')))
        fh:close()
    ''')
    result = _load_spec_and_run_config(tmp_path, probe)
    assert result == '2', (
        f':HappyLspInfo does not exist after config load. exists() = {result!r}'
    )


def test_happy_lsp_info_notifies_when_no_clients(tmp_path):
    """No LSP clients attached → command should vim.notify, not crash."""
    probe = textwrap.dedent(f'''
        -- Capture vim.notify calls.
        local captured = {{}}
        vim.notify = function(msg, level) table.insert(captured, msg) end

        -- Stub vim.lsp.get_clients to return empty.
        vim.lsp.get_clients = function(_) return {{}} end

        vim.cmd('HappyLspInfo')

        local fh = io.open([[{tmp_path / 'probe.out'}]], 'w')
        fh:write(captured[1] or 'NO_NOTIFY')
        fh:close()
    ''')
    result = _load_spec_and_run_config(tmp_path, probe)
    assert 'No LSP clients attached' in result, (
        f'expected "No LSP clients attached..." notify, got: {result!r}'
    )


def test_happy_lsp_info_prints_client_rows(tmp_path):
    """With attached clients → cmd prints one bullet line per client."""
    probe = textwrap.dedent(f'''
        -- Capture print output via redir.
        vim.lsp.get_clients = function(_)
          return {{
            {{ name = 'lua_ls', id = 1, config = {{ root_dir = '/tmp/rootA' }} }},
            {{ name = 'pylsp',  id = 2, config = {{ root_dir = '/tmp/rootB' }} }},
          }}
        end

        vim.cmd('redir! > ' .. [[{tmp_path / 'probe.out'}]])
        vim.cmd('silent HappyLspInfo')
        vim.cmd('redir END')
    ''')
    _load_spec_and_run_config(tmp_path, probe)
    out = (tmp_path / 'probe.out').read_text()
    assert 'lua_ls' in out and 'id=1' in out and '/tmp/rootA' in out, out
    assert 'pylsp' in out and 'id=2' in out and '/tmp/rootB' in out, out
