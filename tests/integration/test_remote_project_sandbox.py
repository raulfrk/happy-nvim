"""Integration: remote.provision(id) creates sandbox + settings.local.json.

Adds a remote project via registry, calls remote.provision(id) inside a
headless nvim with HAPPY_REMOTE_SANDBOX_BASE redirected to tmp_path, then
asserts the on-disk layout + deny/allow contents of settings.local.json.
Follows the same subprocess + env pattern as test_project_pivot.py.
"""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import textwrap
from pathlib import Path

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


def test_provision_creates_sandbox_and_settings(tmp_path: Path):
    registry_path = tmp_path / "projects.json"
    sandbox_base = tmp_path / "sandboxes"

    env = os.environ | {
        "HAPPY_PROJECTS_JSON_OVERRIDE": str(registry_path),
        "HAPPY_REMOTE_SANDBOX_BASE": str(sandbox_base),
    }
    # Keep headless nvim free of stray tmux bindings.
    env.pop("TMUX", None)

    id_file = tmp_path / "id.out"

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
    sandbox = sandbox_base / proj_id
    settings = sandbox / ".claude" / "settings.local.json"

    assert settings.exists(), f"settings.local.json not written at {settings}"

    data = json.loads(settings.read_text())
    deny = data["permissions"]["deny"]
    allow = data["permissions"]["allow"]

    # Deny list covers network egress + filesystem-wide writes.
    assert any("Bash(ssh" in p for p in deny), f"no ssh deny in {deny!r}"
    assert any("WebFetch" in p for p in deny), f"no WebFetch deny in {deny!r}"
    assert any("Read(/**)" in p for p in deny), f"no Read(/**) deny in {deny!r}"

    # Allow list is scoped to the sandbox dir.
    assert any(str(sandbox) in p for p in allow), (
        f"no sandbox-scoped allow in {allow!r}"
    )

    # Registry recorded sandbox_written=true.
    reg_data = json.loads(registry_path.read_text())
    entry = reg_data["projects"][proj_id]
    assert entry["sandbox_written"] is True, (
        f"sandbox_written not flipped in registry entry {entry!r}"
    )


def test_spawn_ssh_creates_remote_session(tmux_socket: str, tmp_path: Path):
    """spawn_ssh(entry) creates a tmux session `remote-<id>` running the ssh cmd.

    Uses HAPPY_REMOTE_SSH_CMD=cat so the spawned shell just holds STDIN open
    — no real network — long enough for `tmux list-sessions` on the isolated
    socket to see it.
    """
    registry_path = tmp_path / "projects.json"
    sandbox_base = tmp_path / "sandboxes"
    id_file = tmp_path / "id.out"

    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    _make_tmux_wrapper(bin_dir, tmux_socket)

    env = os.environ | {
        "HAPPY_PROJECTS_JSON_OVERRIDE": str(registry_path),
        "HAPPY_REMOTE_SANDBOX_BASE": str(sandbox_base),
        "HAPPY_REMOTE_SSH_CMD": "cat",
        "PATH": f"{bin_dir}:{os.environ['PATH']}",
    }
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
                (
                    "lua local reg = require('happy.projects.registry'); "
                    "local id = reg.add({ kind='remote', host='prod01', path='/var/log' }); "
                    "require('happy.projects.remote').provision(id); "
                    "require('happy.projects.remote').spawn_ssh(reg.get(id)); "
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
        session = f"remote-{proj_id}"

        result = subprocess.run(
            ["tmux", "-L", tmux_socket, "list-sessions", "-F", "#{session_name}"],
            check=True,
            text=True,
            capture_output=True,
        )
        sessions = result.stdout.strip().splitlines()
        assert session in sessions, (
            f"expected session {session!r} in tmux list-sessions, got {sessions!r}"
        )
    finally:
        proj_id = id_file.read_text().strip() if id_file.exists() else None
        if proj_id:
            subprocess.run(
                ["tmux", "-L", tmux_socket, "kill-session", "-t", f"remote-{proj_id}"],
                check=False,
                capture_output=True,
            )
