"""Integration: remote.provision(id) creates sandbox + settings.local.json.

Adds a remote project via registry, calls remote.provision(id) inside a
headless nvim with HAPPY_REMOTE_SANDBOX_BASE redirected to tmp_path, then
asserts the on-disk layout + deny/allow contents of settings.local.json.
Follows the same subprocess + env pattern as test_project_pivot.py.
"""
from __future__ import annotations

import json
import os
import subprocess
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]


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
