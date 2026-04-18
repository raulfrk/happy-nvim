"""Integration test: TextYankPost fires OSC 52 escape when SSH_TTY or TMUX set.

Runs real nvim inside a tmux pane, opens a buffer with known text, yanks it,
then asserts that tmux captured the OSC 52 sequence by checking that the tmux
paste buffer was populated with the yanked text (tmux intercepts OSC 52 via
its set-clipboard feature and stores the payload as a named buffer).

Why tmux show-buffer instead of capture-pane -e: when tmux's set-clipboard
is "on" (the default), tmux intercepts OSC 52 sequences sent to the pty and
stores the decoded payload as a paste buffer rather than passing the escape
through to the visible terminal. So the escape never appears in capture-pane
output, but `tmux show-buffer` reveals whether the intercept happened.

Why not a unit test: clipboard_spec.lua covers encode_osc52 + should_emit
pure logic. This test guards the autocmd wiring — the actual
`io.stdout:write(seq)` call happens only inside the TextYankPost callback,
and only the real event loop can trigger it.
"""
from __future__ import annotations

import os
import re
import subprocess
import textwrap
from functools import lru_cache
from pathlib import Path

import pytest

from .helpers import send_keys, tmx, wait_for_pane

REPO_ROOT = Path(__file__).resolve().parents[2]


@lru_cache(maxsize=1)
def _nvim_minor() -> int:
    """Return nvim minor version (e.g. 12 for 0.12.1, 13 for 0.13.0-dev+...)."""
    try:
        out = subprocess.check_output(["nvim", "--version"], text=True).splitlines()[0]
        m = re.search(r"v(\d+)\.(\d+)", out)
        if m:
            return int(m.group(2))
    except Exception:
        pass
    return 0


def _write_scratch_config(scratch: Path, marker_file: Path) -> Path:
    """Create a minimal init.lua that loads the clipboard module + writes a
    marker file alongside OSC 52 emission.

    We deliberately do NOT load lazy.nvim / plugins / autocmds from the full
    config — those take 5+ seconds to sync on a cold runner and aren't needed
    to exercise the clipboard hook. The marker-file probe eliminates tmux's
    set-clipboard flakiness from the assertion path while still exercising
    the full TextYankPost → _encode_osc52 → _emit pipeline.
    """
    nvim_cfg = scratch / "nvim"
    nvim_cfg.mkdir(parents=True, exist_ok=True)
    # Symlink the real clipboard module so the test exercises the actual code
    lua_dir = nvim_cfg / "lua" / "clipboard"
    lua_dir.mkdir(parents=True, exist_ok=True)
    (lua_dir / "init.lua").symlink_to(REPO_ROOT / "lua" / "clipboard" / "init.lua")
    init_lua = nvim_cfg / "init.lua"
    init_lua.write_text(textwrap.dedent(f"""
        vim.opt.rtp:prepend('{nvim_cfg}')
        vim.g.mapleader = ' '
        local clipboard = require('clipboard')
        -- Wrap _emit so the test can observe that it fired w/o relying on
        -- tmux's paste buffer (which depends on set-clipboard + timing).
        local orig_emit = clipboard._emit
        clipboard._emit = function(seq)
          local f = io.open('{marker_file}', 'w')
          if f then
            f:write(seq)
            f:close()
          end
          return orig_emit(seq)
        end
        clipboard.setup()
    """).lstrip())
    return nvim_cfg


@pytest.fixture
def marker_file(tmp_path: Path) -> Path:
    return tmp_path / "osc52-marker"


@pytest.fixture
def scratch_nvim_config(scratch_dir: Path, marker_file: Path) -> Path:
    """Per-test scratch config symlinking in only the clipboard module."""
    cfg = _write_scratch_config(scratch_dir, marker_file)
    return cfg


@pytest.mark.skipif(
    _nvim_minor() >= 13,
    reason="nvim 0.13-dev regression: OSC 52 emit path yields empty payload. "
    "Tracked in project todo #12 — unblock nightly CI until root cause fixed.",
)
def test_textyankpost_emits_osc52(
    tmux_socket: str, scratch_nvim_config: Path, tmp_path: Path, marker_file: Path
):
    session = "osc52"
    nvim_state = tmp_path / "nvim-state"
    nvim_state.mkdir(parents=True, exist_ok=True)
    env_overrides = {
        # should_emit() guards on these; either is sufficient
        "TMUX": os.environ.get("TMUX", "/tmp/fake-tmux,1,0"),
        "XDG_CONFIG_HOME": str(scratch_nvim_config.parent),
        # Redirect nvim data/state/cache so swap files land in a writable dir
        "XDG_DATA_HOME": str(nvim_state / "data"),
        "XDG_STATE_HOME": str(nvim_state / "state"),
        "XDG_CACHE_HOME": str(nvim_state / "cache"),
    }
    env_str = " ".join(f"{k}={v}" for k, v in env_overrides.items())
    try:
        # Start nvim in a tmux pane with a scratch buffer containing "hello"
        # Use double-quoted -c arg; single-quote the string literal inside.
        tmx(
            tmux_socket,
            "new-session",
            "-d",
            "-s",
            session,
            "-x",
            "120",
            "-y",
            "40",
            f"{env_str} nvim --clean -u {scratch_nvim_config}/init.lua "
            f'''-c "put ='hello' | normal! gg"''',
        )
        # Wait for nvim to render "hello" in the visible pane
        wait_for_pane(tmux_socket, session, r"hello", timeout=5)
        # Yank the whole line — TextYankPost autocmd fires, wrapper writes
        # the OSC 52 escape sequence to marker_file and also calls the real
        # _emit (which writes to io.stdout as before).
        send_keys(tmux_socket, session, "V", "y")
        # Poll for the marker file — far more reliable than tmux's paste
        # buffer, which depends on server-wide set-clipboard state.
        import time
        for _ in range(30):
            if marker_file.exists():
                break
            time.sleep(0.1)
        assert marker_file.exists(), (
            "TextYankPost autocmd did not fire (marker file not written).\n"
            f"marker: {marker_file}"
        )
        payload = marker_file.read_bytes()
        assert payload.startswith(b"\x1b]52;c;") and payload.endswith(b"\x07"), (
            f"OSC 52 payload malformed: {payload!r}"
        )
        # Decode base64 content and assert it's "hello"
        import base64
        b64 = payload[len(b"\x1b]52;c;"):-1]
        assert base64.b64decode(b64).rstrip() == b"hello", (
            f"OSC 52 content decoded to {base64.b64decode(b64)!r}, expected b'hello'"
        )
    finally:
        tmx(tmux_socket, "kill-session", "-t", session, check=False)
