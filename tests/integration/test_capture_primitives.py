"""Integration: remote.capture(id) writes a capture-*.log under the sandbox dir.

Spawns a fake `remote-<id>` tmux session containing a known marker string,
then invokes `require('happy.projects.remote').capture(id)` from a headless
nvim, asserting the capture file appears under
`<sandbox_base>/<id>/capture-*.log` with the marker present.

Follows the same socket-isolated pattern as test_remote_project_sandbox.py.
"""
from __future__ import annotations

import os
import shutil
import subprocess
import textwrap
import time
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]


def _make_tmux_wrapper(bin_dir: Path, socket: str) -> None:
    """Shim `tmux` on PATH so nvim's plain `tmux ...` hits our isolated socket."""
    real_tmux = shutil.which("tmux") or "/usr/bin/tmux"
    wrapper = bin_dir / "tmux"
    wrapper.write_text(textwrap.dedent(f"""\
        #!/usr/bin/env bash
        exec {real_tmux} -L {socket} "$@"
    """))
    wrapper.chmod(0o755)


def test_Cc_captures_remote_pane_to_sandbox_file(tmux_socket: str, tmp_path: Path):
    registry_path = tmp_path / "projects.json"
    sandbox_base = tmp_path / "sandboxes"
    id_file = tmp_path / "id.out"

    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    _make_tmux_wrapper(bin_dir, tmux_socket)

    env = os.environ | {
        "HAPPY_PROJECTS_JSON_OVERRIDE": str(registry_path),
        "HAPPY_REMOTE_SANDBOX_BASE": str(sandbox_base),
        "PATH": f"{bin_dir}:{os.environ['PATH']}",
    }
    env.pop("TMUX", None)

    # Registry slugify strips leading path components; host=prod01
    # path=/var/log produces id 'prod01-log'.
    proj_id_expected = "prod01-log"
    session = f"remote-{proj_id_expected}"

    try:
        # Spawn a fake remote pane with a known marker in scrollback.
        subprocess.run(
            [
                "tmux", "-L", tmux_socket, "new-session", "-d", "-s", session,
                "bash", "-c", "echo CAPTURE_MARKER; sleep 60",
            ],
            check=True,
            capture_output=True,
        )
        # Let the echo land in scrollback before capture-pane reads it.
        time.sleep(0.3)

        subprocess.run(
            [
                "nvim",
                "--headless",
                "--clean",
                "-c",
                f"lua vim.opt.rtp:prepend('{REPO_ROOT}')",
                "-c",
                (
                    "lua local reg = require('happy.projects.registry'); "
                    "local id = reg.add({ kind='remote', host='prod01', path='/var/log' }); "
                    "require('happy.projects.remote').provision(id); "
                    "require('happy.projects.remote').capture(id); "
                    f"vim.fn.writefile({{id}}, '{id_file}')"
                ),
                "-c",
                "qa!",
            ],
            check=True,
            text=True,
            capture_output=True,
            env=env,
        )

        proj_id = id_file.read_text().strip()
        assert proj_id == proj_id_expected, f"unexpected id: {proj_id!r}"

        sandbox = sandbox_base / proj_id
        captures = list(sandbox.glob("capture-*.log"))
        assert len(captures) == 1, (
            f"expected exactly 1 capture file in {sandbox}, got {captures!r}"
        )
        content = captures[0].read_text()
        assert "CAPTURE_MARKER" in content, (
            f"marker not found in capture {captures[0]}: {content!r}"
        )
    finally:
        subprocess.run(
            ["tmux", "-L", tmux_socket, "kill-session", "-t", session],
            check=False,
            capture_output=True,
        )
