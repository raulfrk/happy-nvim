# Skipped-Test Cleanup (Design Spec)

**Status:** approved 2026-04-20
**Scope:** unblock 6 `pytest.skip()` guards from the manual-tests
conversion sprint (tests for factor-these-public helpers) AND reactivate
the long-skipped `test_lsp_format.py` (Mason race workaround).

## 1. Problem

### 1a. Skipped conversion tests (6)

After the manual-tests → pytest conversion sprint (commits
`eff9e80..57356aa`), 6 tests guard-skip because their targets aren't
factored as public fns:

- `test_cl_picker_ctrl_x_kills_selected_session` — wants
  `tmux.picker._kill_session(name)`
- `test_remote_dirs_picker_reads_from_util_run` — wants
  `remote.dirs._list_remote(host)`
- `test_remote_browse_opens_scp_buffer` — wants
  `remote.browse.open_path(host, path)` OR `_open`
- `test_remote_browse_refuses_binary` — wants
  `remote.browse._is_binary(host, rpath)` (higher-level than existing
  `_is_binary_mime`)
- `test_remote_browse_override_skips_binary_check` — wants
  `remote.browse._set_override(bool)`
- `test_happy_hosts_prune_reports_count` — wants
  `remote.hosts.prune()`

### 1b. `test_lsp_format.py` Mason race

Skip reason (verbatim): `"Mason ruff install races against the settle
window on CI runners; BUG-1 (conform sole format-on-save owner) is
covered by the static lua/plugins/conform.lua + keymap_spec. Re-enable
when we ship a pre-installed-formatter harness or use a system binary
(stylua + .lua)."`

Testing `ruff` on `.py` is flaky because Mason installs `ruff` async in
the nvim test session. The BUG-1 invariant (conform is the SOLE
format-on-save owner — no double-fire) is testable with ANY formatter;
using `stylua` on `.lua` sidesteps the race (stylua is a system binary
we can `shutil.which()` and skip-if-missing).

## 2. Solution

**1a — factor helpers public** (6 small changes across 4 modules):

| File | Change |
|---|---|
| `lua/tmux/picker.lua` | Extract the kill-session block at line 107 into `function M._kill_session(name)`. Picker's `<C-x>` action calls `M._kill_session(entry.value.name)` + refresh. |
| `lua/remote/browse.lua` | Add `M.open_path = M.open` alias (name matches test expectation). Factor the binary-check block from `M.open` into `M._is_binary(host, rpath) → bool`. Add `M._set_override(bool)` that sets `vim.b.happy_force_binary`. |
| `lua/remote/dirs.lua` | Add `M._list_remote = M._fetch_sync` alias. |
| `lua/remote/hosts.lua` | Add `M.prune(max_age_days)` that removes entries with `(now - last_used) > max_age_days * 86400` from the DB. Returns count pruned. Default `max_age_days = 90`. |

Then remove `pytest.skip()` guards from the 6 conversion tests so they
run + pass.

**1b — rewrite test_lsp_format.py as `test_conform_format_once.py`:**

Drop the LSP attach check entirely. Focus on the BUG-1 invariant:
conform fires ONCE on `:w`, not twice. Use stylua + a small .lua file.
If `stylua` not on PATH, skip cleanly.

```python
# tests/integration/test_conform_format_once.py
"""BUG-1 regression: conform is the sole format-on-save owner; :w fires
stylua exactly once (not twice via an LSP formatProvider or competing
autocmd)."""

import os
import shutil
import subprocess
import textwrap
from pathlib import Path


def test_conform_fires_once_on_save(tmp_path):
    if not shutil.which('stylua'):
        import pytest; pytest.skip('stylua not installed')

    work = tmp_path / 'w'; work.mkdir()
    probe = work / 'probe.lua'
    probe.write_text("local x   =   1\n")  # unformatted

    counter = tmp_path / 'fires.out'
    counter.write_text('0')

    snippet = textwrap.dedent(f'''
        local repo = '{os.getcwd()}'
        vim.opt.rtp:prepend(repo)
        vim.api.nvim_exec_autocmds('VimEnter', {{}})
        vim.wait(5000, function() return pcall(require, 'conform') end, 100)

        local orig_format = require('conform').format
        require('conform').format = function(opts, cb)
          local fh = io.open('{counter}', 'r'); local n = tonumber(fh:read('*a')) or 0; fh:close()
          fh = io.open('{counter}', 'w'); fh:write(tostring(n + 1)); fh:close()
          return orig_format(opts, cb)
        end

        vim.cmd('edit {probe}')
        vim.cmd('silent! write')
        vim.wait(2000, function() return false end, 100)
        vim.cmd('qa!')
    ''')

    env = os.environ.copy()
    scratch = tmp_path / 'xdg'
    (scratch / 'cfg').mkdir(parents=True, exist_ok=True)
    (scratch / 'data' / 'nvim').mkdir(parents=True, exist_ok=True)
    env['XDG_CONFIG_HOME'] = str(scratch / 'cfg')
    env['XDG_DATA_HOME'] = str(scratch / 'data')
    env['XDG_CACHE_HOME'] = str(scratch / 'cache')
    env['XDG_STATE_HOME'] = str(scratch / 'state')
    if not (scratch / 'cfg' / 'nvim').exists():
        os.symlink(os.getcwd(), scratch / 'cfg' / 'nvim')
    subprocess.run(
        ['nvim', '--headless', '-c', f'lua {snippet}'],
        env=env, check=True, timeout=60,
    )
    fires = int(counter.read_text().strip())
    assert fires == 1, f'conform.format fired {fires} times (expected 1)'
```

Delete the original `test_lsp_format.py`.

## 3. Out of scope

- LSP-layer end-to-end verification (still a manual-test row; Mason-
  race workaround via pre-installed-formatter harness is a bigger
  lift).
- Renaming helpers across the codebase — only add-aliases for the
  tests' expected names. Existing callers keep the old names.

## 4. Testing

Before shipping:
1. Plenary `tmux_picker_spec.lua` if it exists (or `:HappyAssess`'s plenary layer) — should still pass.
2. Full integration suite: new `test_conform_format_once.py` passes,
   the 6 previously-skipped tests in the conversion suite now PASS
   (flipped from `skipped` → `passed`).
3. `assess.sh` ALL LAYERS PASS.

Net delta: **+7 passing integration tests** (6 unskipped + 1
reactivated). 0 new skips.

## 5. Rollout

Single push. Additive (new public helpers + new test file); one
deletion (`test_lsp_format.py`).
