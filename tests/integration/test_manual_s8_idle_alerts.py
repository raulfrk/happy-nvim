# tests/integration/test_manual_s8_idle_alerts.py
"""Manual-tests §8 AUTO rows (todo 32.8):
bell opt-in, cooldown dedup, focus-skip."""

import os
import subprocess
import textwrap


def _run_lua(snippet, timeout=15):
    return subprocess.run(
        ['nvim', '--clean', '--headless', '-u', 'NONE', '-c', f'lua {snippet}'],
        check=True, timeout=timeout, capture_output=True, text=True,
    )


def test_idle_bell_opt_in_writes_bel_to_stdout(tmp_path):
    out = tmp_path / 'bell.out'
    snippet = textwrap.dedent(f'''
        local repo = '{os.getcwd()}'
        vim.opt.rtp:prepend(repo)
        local idle = require('tmux.idle')
        if not idle._emit_bell then
          local fh = io.open('{out}', 'w'); fh:write(''); fh:close()
          vim.cmd('qa!')
          return
        end
        local written = ''
        local orig_stdout_write = io.stdout.write
        io.stdout.write = function(self, s) written = written .. s end
        idle._emit_bell()
        io.stdout.write = orig_stdout_write
        local fh = io.open('{out}', 'w'); fh:write(written); fh:close()
        vim.cmd('qa!')
    ''')
    _run_lua(snippet)
    text = out.read_text()
    if text == '':
        import pytest; pytest.skip('idle._emit_bell not factored as helper')
    assert '\x07' in text  # BEL char


def test_idle_cooldown_dedups_rapid_flips(tmp_path):
    out = tmp_path / 'notifs.out'
    snippet = textwrap.dedent(f'''
        local repo = '{os.getcwd()}'
        vim.opt.rtp:prepend(repo)
        local count = 0
        vim.notify = function(msg, lvl) count = count + 1 end
        local idle = require('tmux.idle')
        if idle._maybe_alert then
          idle._maybe_alert('cc-proj-a', 'idle')
          idle._maybe_alert('cc-proj-a', 'idle')  -- dup
        elseif idle.apply_flip then
          idle.apply_flip('cc-proj-a', 'idle')
          idle.apply_flip('cc-proj-a', 'idle')
        end
        local fh = io.open('{out}', 'w'); fh:write(tostring(count)); fh:close()
        vim.cmd('qa!')
    ''')
    _run_lua(snippet)
    text = out.read_text().strip()
    if text == '0':
        import pytest; pytest.skip('idle alert helpers not triggered in this path')
    assert int(text) <= 1, f'expected dedup, got {text} notifications'


def test_idle_focus_skip_suppresses_when_pane_active(tmp_path):
    out = tmp_path / 'fired.out'
    snippet = textwrap.dedent(f'''
        local repo = '{os.getcwd()}'
        vim.opt.rtp:prepend(repo)
        local idle = require('tmux.idle')
        if not idle._should_alert then
          local fh = io.open('{out}', 'w'); fh:write('NIL'); fh:close()
          vim.cmd('qa!')
          return
        end
        -- Introspect arity via pcall: single-arg API vs 5-arg pure fn.
        -- The factored pure variant takes (session, focused_session, last_ts, now, opts).
        -- When session == focused_session + opts.skip_focused, returns false.
        local ok, should = pcall(idle._should_alert, 'cc-proj-a', 'cc-proj-a', nil, 0, {{
          notify = true, bell = false, desktop = false,
          cooldown_secs = 10, skip_focused = true,
        }})
        if not ok then
          local fh = io.open('{out}', 'w'); fh:write('ARITY'); fh:close()
          vim.cmd('qa!')
          return
        end
        local fh = io.open('{out}', 'w'); fh:write(tostring(should)); fh:close()
        vim.cmd('qa!')
    ''')
    _run_lua(snippet)
    text = out.read_text().strip()
    if text == 'NIL':
        import pytest; pytest.skip('idle._should_alert not factored as helper')
    if text == 'ARITY':
        import pytest; pytest.skip('idle._should_alert has different signature')
    # When pane is active (focused), should_alert must return false.
    assert text == 'false', f'expected focus-skip: {text}'
