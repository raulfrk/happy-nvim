"""Integration: pivot.pivot(id) cd's nvim into a local project's path.

Pre-seeds a registry JSON on disk via `HAPPY_PROJECTS_JSON_OVERRIDE`,
pre-creates the tmux session so pivot's respawn path is skipped, calls
`pivot.pivot(id)` in a headless nvim, and asserts the nvim cwd landed on
the project path. Writes the captured cwd to a scratch file because
headless-nvim stdout is not a reliable channel for asserting values.
"""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import textwrap
import time
from pathlib import Path

from .helpers import tmx

REPO_ROOT = Path(__file__).resolve().parents[2]


def _make_tmux_wrapper(bin_dir: Path, socket: str) -> None:
    """Shim `tmux` on PATH so nvim's plain `tmux ...` calls hit our test socket."""
    real_tmux = shutil.which("tmux") or "/usr/bin/tmux"
    wrapper = bin_dir / "tmux"
    wrapper.write_text(textwrap.dedent(f"""\
        #!/usr/bin/env bash
        exec {real_tmux} -L {socket} "$@"
    """))
    wrapper.chmod(0o755)


def test_pivot_local_project_cds_nvim_and_touches_registry(
    tmux_socket: str, tmp_path: Path
):
    # 1. On-disk project dir.
    proj = tmp_path / "proj-alpha"
    proj.mkdir()

    # 2. Pre-seed registry JSON.
    registry_path = tmp_path / "projects.json"
    registry_path.write_text(json.dumps({
        "version": 1,
        "projects": {
            "proj-alpha": {
                "kind": "local",
                "path": str(proj),
                "last_opened": int(time.time()),
                "frecency": 0.5,
                "open_count": 1,
                "sandbox_written": False,
            }
        },
    }))

    # 3. Pre-create the tmux session so pivot takes the "alive" branch
    #    (no claude-spawn needed for this smoke).
    session = "cc-proj-alpha"
    tmx(tmux_socket, "new-session", "-d", "-s", session, "-c", str(proj))

    # 4. Headless nvim runs pivot() and writes cwd to a scratch file.
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    _make_tmux_wrapper(bin_dir, tmux_socket)

    cwd_file = tmp_path / "cwd.out"
    count_file = tmp_path / "count.out"
    env = os.environ | {
        "HAPPY_PROJECTS_JSON_OVERRIDE": str(registry_path),
        "PATH": f"{bin_dir}:{os.environ['PATH']}",
    }
    # unset TMUX so pivot doesn't try to switch-client inside the headless
    # process (there's no tmux client attached).
    env.pop("TMUX", None)

    try:
        subprocess.run(
            [
                "nvim",
                "--headless",
                "--clean",
                "-c",
                f"lua vim.opt.rtp:prepend('{REPO_ROOT}')",
                "-c",
                "lua require('happy.projects.pivot').pivot('proj-alpha')",
                "-c",
                f"lua vim.fn.writefile({{vim.fn.getcwd()}}, '{cwd_file}')",
                "-c",
                (
                    "lua vim.fn.writefile({tostring("
                    "require('happy.projects.registry').get('proj-alpha').open_count"
                    ")}, "
                    f"'{count_file}')"
                ),
                "-c",
                "qa!",
            ],
            check=True,
            text=True,
            capture_output=True,
            env=env,
        )

        # 5. Assert cwd is the project path.
        got_cwd = cwd_file.read_text().strip()
        assert got_cwd == str(proj), (
            f"expected cwd={proj!s}, got {got_cwd!r}"
        )

        # 6. Assert registry.touch bumped open_count (1 → 2).
        got_count = count_file.read_text().strip()
        assert got_count == "2", (
            f"expected open_count=2 after pivot, got {got_count!r}"
        )
    finally:
        subprocess.run(
            ["tmux", "-L", tmux_socket, "kill-session", "-t", session],
            check=False,
            capture_output=True,
        )
