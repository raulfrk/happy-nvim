"""Integration test: remote.util.run keeps vim.uv.timer firing.

Regression guard for #17. If someone reverts remote.util.run to a
blocking vim.system():wait(), the idle watcher's timer will silently
starve during every ssh call — the exact pre-fix bug. This test catches
that by running a long-ish subprocess via util.run and asserting that a
100ms-interval timer fires multiple times during the wait.

Parallel to tests/integration/test_idle_alert_during_popup.py but
scoped to the remote helper specifically (no tmux session setup).
"""
from __future__ import annotations

import os
import subprocess
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]


def _run_nvim(wait_ms: int) -> str:
    """Start a 100ms timer, call util.run({'sleep','1.5'}), report fire count.

    Returns merged stdout+stderr (headless nvim prints go to stderr).
    """
    env = os.environ | {"TMUX": "/tmp/fake,1,0"}
    lua = (
        "vim.opt.rtp:prepend('" + str(REPO_ROOT) + "');"
        "local fired = 0;"
        "local timer = vim.uv.new_timer();"
        "timer:start(100, 100, vim.schedule_wrap(function() fired = fired + 1 end));"
        "local res = require('remote.util').run({ 'sleep', '1.5' }, { text = true }, 5000);"
        "timer:stop(); timer:close();"
        "print('CODE=' .. res.code);"
        "print('FIRED=' .. fired);"
    )
    result = subprocess.run(
        [
            "nvim", "--headless", "--clean",
            "-c", "lua " + lua,
            "-c", "qa!",
        ],
        check=True, text=True, capture_output=True, env=env,
        timeout=wait_ms / 1000 + 10,
    )
    return result.stdout + result.stderr


def test_util_run_keeps_event_loop_pumping():
    out = _run_nvim(wait_ms=3000)
    assert "CODE=0" in out, f"expected util.run to succeed, got:\n{out}"
    # Parse the FIRED=N line
    fired = None
    for line in out.splitlines():
        if line.startswith("FIRED="):
            fired = int(line[len("FIRED="):])
            break
    assert fired is not None, f"FIRED= not found in output:\n{out}"
    # 1.5s subprocess / 100ms interval = 15 expected fires; allow slack
    # for CI jitter but require >=5 so the test would fail clearly if
    # someone reverts to blocking :wait() (which fires 0 times).
    assert fired >= 5, (
        f"vim.uv.timer fired only {fired} times during util.run — "
        f"event loop was blocked? Output:\n{out}"
    )
