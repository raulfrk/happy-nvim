"""Regression for 30.5: opening a .lua file on a machine without selene
installed must NOT error-spam `:messages`. The happy-nvim lint autocmd
must filter linters_by_ft by vim.fn.executable() at call time.

Strategy: skip lazy + real nvim-lint. Stub `package.loaded.lint` w/ a fake
table, dofile() the plugin spec, invoke its `.config()` fn, trigger the
happy_lint autocmd on a .lua buffer. Stub vim.fn.executable to return 0
for selene — asserts try_lint was NOT called + vim.v.errmsg empty.
"""
from __future__ import annotations

import subprocess
import textwrap
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]


def _run_probe(tmp_path: Path, exec_returns: int) -> tuple[str, str]:
    """Run headless nvim probe. Returns (counter_content, errmsg_content).

    `exec_returns` is what the stubbed `vim.fn.executable('selene')` returns.
    """
    lua_file = tmp_path / 'probe.lua'
    lua_file.write_text('local x = 1\nreturn x\n')
    out_path = tmp_path / 'lint_called.out'
    err_path = tmp_path / 'errmsg.out'
    args_path = tmp_path / 'try_lint_args.out'

    snippet = textwrap.dedent(f'''
        local repo = [[{REPO_ROOT}]]
        vim.opt.rtp:prepend(repo)

        -- Fake `lint` module consumed by the plugin spec's config fn.
        local fake_lint = {{
          linters_by_ft = {{}},
          try_lint = function(linters)
            local fh = io.open([[{out_path}]], 'r')
            local n = tonumber((fh and fh:read('*a')) or '0') or 0
            if fh then fh:close() end
            n = n + 1
            local wh = io.open([[{out_path}]], 'w')
            wh:write(tostring(n)); wh:close()
            -- Record the args passed (table of linter names, or nil).
            local argf = io.open([[{args_path}]], 'w')
            if type(linters) == 'table' then
              argf:write(table.concat(linters, ','))
            elseif linters == nil then
              argf:write('NIL')
            else
              argf:write(tostring(linters))
            end
            argf:close()
          end,
        }}
        package.loaded['lint'] = fake_lint

        -- Stub vim.fn.executable BEFORE config runs so the callback uses it.
        local orig_exec = vim.fn.executable
        vim.fn.executable = function(bin)
          if bin == 'selene' then return {exec_returns} end
          -- Delegate everything else to the real fn so nvim internals keep
          -- working during the run.
          return orig_exec(bin)
        end

        -- Seed counter to 0 so "not called" reads back as 0.
        local seed = io.open([[{out_path}]], 'w'); seed:write('0'); seed:close()
        local seeda = io.open([[{args_path}]], 'w'); seeda:write(''); seeda:close()

        -- Load the plugin spec + run its config fn.
        local spec = dofile(repo .. '/lua/plugins/lint.lua')
        assert(type(spec.config) == 'function', 'plugin spec missing .config')
        spec.config()

        -- Open the .lua file → filetype=lua → happy_lint autocmd fires on
        -- BufReadPost. Then fire BufReadPost explicitly to be deterministic.
        vim.cmd('edit [[{lua_file}]]')
        vim.bo.filetype = 'lua'
        vim.api.nvim_exec_autocmds('BufReadPost', {{}})
        vim.wait(100, function() return false end, 25)

        local ferr = io.open([[{err_path}]], 'w')
        ferr:write(vim.v.errmsg or ''); ferr:close()

        vim.cmd('qa!')
    ''')

    subprocess.run(
        ['nvim', '--headless', '--clean', '-c', f'lua {snippet}'],
        check=True, timeout=30, capture_output=True, text=True,
    )
    return out_path.read_text().strip(), err_path.read_text().strip(), args_path.read_text().strip()


def test_lint_skipped_when_binary_missing(tmp_path):
    """Binary missing → try_lint MUST NOT be called, no errmsg."""
    counter, errmsg, args = _run_probe(tmp_path, exec_returns=0)
    assert counter == '0', (
        f'lint.try_lint was called {counter} times even though '
        f'vim.fn.executable(selene) returned 0'
    )
    assert errmsg == '', f'vim.v.errmsg non-empty: {errmsg!r}'


def test_lint_called_when_binary_present(tmp_path):
    """Binary present → try_lint IS called with the filtered linter list."""
    counter, errmsg, args = _run_probe(tmp_path, exec_returns=1)
    assert counter == '1', (
        f'lint.try_lint expected to be called exactly once; got {counter}'
    )
    assert args == 'selene', (
        f'expected try_lint called with {{"selene"}}; got {args!r}'
    )
    assert errmsg == '', f'vim.v.errmsg non-empty: {errmsg!r}'
