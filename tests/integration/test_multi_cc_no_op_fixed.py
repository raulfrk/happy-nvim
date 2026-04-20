"""Regression: <leader>cc in two nvims (two project dirs) tracks pane ids
under distinct per-project window options (@claude_pane_id_<slug>).

Bug 30.3: the old pane-model stored a single @claude_pane_id window option,
so a second project sharing the same tmux window would overwrite the first
project's pane id — the second project hijacked the first project's pane.

The fix: pane ids are stored under @claude_pane_id_<slug>, where slug is
the per-project registry id. Two projects → two distinct option names →
no collision, each project tracks its own split pane independently.

This test invokes open() headlessly from two different project slugs and
asserts each uses a distinct @claude_pane_id_<slug> key.
"""
from __future__ import annotations

import os
import subprocess
import textwrap
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]


def _run_cc_for_slug(slug: str, tmp_path: Path) -> str:
    """Headless nvim: call open() for a given project slug; return logged cmds."""
    log = tmp_path / f"argv-{slug}.txt"
    snippet = textwrap.dedent(f"""
        local repo = '{REPO_ROOT}'
        vim.opt.rtp:prepend(repo)
        vim.env.TMUX = 'dummy'
        local calls = {{}}
        vim.system = function(cmd, opts, cb)
          local key = type(cmd) == 'table' and table.concat(cmd, ' ') or tostring(cmd)
          table.insert(calls, key)
          local stdout = ''
          local code = 0
          if key:match('show%-option') then
            -- No existing pane id -> force new split path.
            stdout = ''
            code = 1
          elseif key:match('split%-window') then
            -- Return a fresh pane id.
            stdout = '%42\\n'
          elseif key:match('display%-message') then
            stdout = '200\\n'
          end
          local handle = {{}}
          function handle:is_closing() return false end
          function handle:kill() end
          function handle:wait() return {{ code = code, stdout = stdout, stderr = '' }} end
          if cb then cb({{ code = code }}) end
          return handle
        end
        vim.fn.system = function(cmd)
          local key = type(cmd) == 'table' and table.concat(cmd, ' ') or tostring(cmd)
          table.insert(calls, 'FN:' .. key)
          if key:match('display%-message') then return '200\\n' end
          return ''
        end
        package.loaded['happy.projects.registry'] = {{
          add = function() return '{slug}' end,
          get = function() return {{ kind = 'local', path = '/tmp/{slug}' }} end,
          touch = function() end,
          score = function() return 0 end,
        }}
        vim.fn.getcwd = function() return '/tmp/{slug}' end
        require('tmux.claude').open()
        local fh = io.open('{log}', 'w')
        for _, c in ipairs(calls) do fh:write(c .. '\\n') end
        fh:close()
        vim.cmd('qa!')
    """).strip()
    subprocess.run(
        ["nvim", "--clean", "--headless", "-u", "NONE", "-c", f"lua {snippet}"],
        check=True,
        text=True,
        capture_output=True,
        timeout=15,
    )
    return log.read_text()


def test_second_window_cc_creates_distinct_pane_options(tmp_path: Path):
    """Two projects → two distinct @claude_pane_id_<slug> set-option calls."""
    log_a = _run_cc_for_slug("proj-a", tmp_path)
    log_b = _run_cc_for_slug("proj-b", tmp_path)

    # Each project must record its pane id under its own slug key.
    assert "@claude_pane_id_proj-a" in log_a, f"proj-a key missing:\n{log_a}"
    assert "@claude_pane_id_proj-b" in log_b, f"proj-b key missing:\n{log_b}"

    # proj-a must NOT write proj-b's key (no cross-project collision).
    assert "@claude_pane_id_proj-b" not in log_a, f"proj-a clobbered proj-b:\n{log_a}"
    assert "@claude_pane_id_proj-a" not in log_b, f"proj-b clobbered proj-a:\n{log_b}"

    # Both must actually spawn a split (not no-op).
    assert "tmux split-window" in log_a, f"no split for proj-a:\n{log_a}"
    assert "tmux split-window" in log_b, f"no split for proj-b:\n{log_b}"
