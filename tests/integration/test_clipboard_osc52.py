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
import subprocess
import textwrap
from pathlib import Path

import pytest

from .helpers import send_keys, tmx, wait_for_pane

REPO_ROOT = Path(__file__).resolve().parents[2]


def _write_scratch_config(scratch: Path) -> Path:
    """Create a minimal init.lua that only loads the clipboard module.

    We deliberately do NOT load lazy.nvim / plugins / autocmds from the full
    config — those take 5+ seconds to sync on a cold runner and aren't needed
    to exercise the clipboard hook.
    """
    nvim_cfg = scratch / "nvim"
    nvim_cfg.mkdir(parents=True, exist_ok=True)
    # Symlink the real clipboard module so the test exercises the actual code
    lua_dir = nvim_cfg / "lua" / "clipboard"
    lua_dir.mkdir(parents=True, exist_ok=True)
    (lua_dir / "init.lua").symlink_to(REPO_ROOT / "lua" / "clipboard" / "init.lua")
    init_lua = nvim_cfg / "init.lua"
    init_lua.write_text(textwrap.dedent(f"""
        -- Minimal init: just enough to exercise the OSC 52 hook.
        vim.opt.rtp:prepend('{nvim_cfg}')
        vim.g.mapleader = ' '
        require('clipboard').setup()
    """).lstrip())
    return nvim_cfg


@pytest.fixture
def scratch_nvim_config(scratch_dir: Path) -> Path:
    """Per-test scratch config symlinking in only the clipboard module."""
    cfg = _write_scratch_config(scratch_dir)
    return cfg


def test_textyankpost_emits_osc52(tmux_socket: str, scratch_nvim_config: Path, tmp_path: Path):
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
        # Force tmux to capture OSC 52 into a paste buffer regardless of the
        # runner's default `set-clipboard` value (varies: off on CI, on
        # locally, external in some configs). With `set-clipboard on`, tmux
        # decodes OSC 52 and writes it to the paste buffer we inspect below.
        tmx(tmux_socket, "set-option", "-g", "set-clipboard", "on")
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
        # Yank the whole line
        send_keys(tmux_socket, session, "V", "y")
        # Give the autocmd a moment to flush io.stdout
        import time
        time.sleep(0.3)
        # tmux intercepts OSC 52 (set-clipboard on by default) and stores the
        # decoded payload as a paste buffer. show-buffer returns the content of
        # the most-recently set buffer.
        result = subprocess.run(
            ["tmux", "-L", tmux_socket, "show-buffer"],
            check=False,
            text=True,
            capture_output=True,
        )
        assert result.returncode == 0 and "hello" in result.stdout, (
            "tmux paste buffer was not set to 'hello' after yank — "
            "OSC 52 sequence was not received by tmux.\n"
            f"show-buffer stdout: {result.stdout!r}\n"
            f"show-buffer stderr: {result.stderr!r}"
        )
    finally:
        tmx(tmux_socket, "kill-session", "-t", session, check=False)
