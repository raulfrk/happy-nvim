"""Pytest fixtures for happy-nvim integration tests.

Each pytest session runs against:
- An isolated tmux server on socket `happy-test-<pid>` (never touches the
  user's default tmux).
- A scratch tempdir with XDG_*_HOME redirected into it (so nvim plugin
  state doesn't leak into the user's ~/.local/share/nvim).
- A PATH prepended with a bin/ dir that shadows `claude` with
  fake_claude.py.

Fixtures are session-scoped — one tmux server shared across all scenarios
in a run, but each scenario creates its own tmux sessions via `tmux_socket`.
"""
from __future__ import annotations

import os
import shutil
import subprocess
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
FAKE_CLAUDE = Path(__file__).resolve().parent / "fake_claude.py"
MIN_TMUX_MAJOR, MIN_TMUX_MINOR = 3, 2


def _tmux_version() -> tuple[int, int]:
    out = subprocess.check_output(["tmux", "-V"], text=True).strip()
    # "tmux 3.4" or "tmux next-3.4" or "tmux 3.3a"
    ver = out.split()[-1].lstrip("next-")
    parts = ver.split(".")
    major = int(parts[0])
    # strip any trailing non-numeric suffix (e.g. "3a" -> 3)
    import re as _re
    minor = int(_re.match(r"\d+", parts[1]).group())
    return major, minor


@pytest.fixture(scope="session")
def scratch_dir(tmp_path_factory) -> Path:
    """Session-wide scratch dir; auto-removed at end of pytest session."""
    return tmp_path_factory.mktemp("happy-integration")


@pytest.fixture(scope="session", autouse=True)
def _env(scratch_dir: Path, monkeypatch_session):
    """Redirect XDG dirs and prepend fake-claude bin dir to PATH."""
    for var in ("XDG_CONFIG_HOME", "XDG_DATA_HOME", "XDG_CACHE_HOME", "XDG_STATE_HOME"):
        target = scratch_dir / var.split("_")[1].lower()
        target.mkdir(parents=True, exist_ok=True)
        monkeypatch_session.setenv(var, str(target))

    bin_dir = scratch_dir / "bin"
    bin_dir.mkdir(parents=True, exist_ok=True)
    (bin_dir / "fake_claude.py").symlink_to(FAKE_CLAUDE)
    (bin_dir / "claude").symlink_to(FAKE_CLAUDE)
    monkeypatch_session.setenv("PATH", f"{bin_dir}:{os.environ['PATH']}")


@pytest.fixture(scope="session")
def monkeypatch_session():
    """Session-scoped monkeypatch (pytest's default is function-scoped)."""
    from _pytest.monkeypatch import MonkeyPatch
    mp = MonkeyPatch()
    yield mp
    mp.undo()


@pytest.fixture(scope="session")
def tmux_socket() -> str:
    """Start an isolated tmux server; return socket name; kill on teardown."""
    if shutil.which("tmux") is None:
        pytest.skip("tmux not installed")
    major, minor = _tmux_version()
    if (major, minor) < (MIN_TMUX_MAJOR, MIN_TMUX_MINOR):
        pytest.skip(f"tmux >= {MIN_TMUX_MAJOR}.{MIN_TMUX_MINOR} required, found {major}.{minor}")

    socket = f"happy-test-{os.getpid()}"
    # tmux starts the server lazily on first command; force it via a no-op
    subprocess.run(["tmux", "-L", socket, "list-sessions"], capture_output=True)
    yield socket
    subprocess.run(["tmux", "-L", socket, "kill-server"], capture_output=True)
