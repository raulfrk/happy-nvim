"""Integration: remote.hosts reads ~/.ssh/config entries.

No M.list() exists — uses M._merge(db, _parse_ssh_config(), now)
which is the same path the real M.pick() takes.
"""
from __future__ import annotations

import json
import os
import subprocess
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]


def test_list_reads_ssh_config(tmp_path: Path):
    home = tmp_path / "home"; home.mkdir()
    ssh = home / ".ssh"; ssh.mkdir(mode=0o700)
    (ssh / "config").write_text(
        "Host alpha\n  HostName 10.0.0.1\n"
        "Host beta\n  HostName 10.0.0.2\n"
        "Host gamma\n  HostName 10.0.0.3\n"
    )
    out_file = tmp_path / "hosts.json"
    env = os.environ | {
        "HOME": str(home),
        "XDG_DATA_HOME": str(tmp_path / "data"),
        "XDG_STATE_HOME": str(tmp_path / "state"),
        "XDG_CACHE_HOME": str(tmp_path / "cache"),
        "XDG_CONFIG_HOME": str(tmp_path / "cfg"),
    }
    # Use _merge({}, _parse_ssh_config(), os.time()) — same as M.pick()
    subprocess.run(
        [
            "nvim", "--headless", "--clean",
            "-c", f"lua vim.opt.rtp:prepend('{REPO_ROOT}')",
            "-c", (
                f"lua local h = require('remote.hosts');"
                f" local merged = h._merge({{}}, h._parse_ssh_config(), os.time());"
                f" vim.fn.writefile({{vim.json.encode(merged)}}, '{out_file}')"
            ),
            "-c", "qa!",
        ],
        check=True, text=True, capture_output=True, env=env,
    )
    hosts = json.loads(out_file.read_text())
    names = sorted(h["host"] for h in hosts)
    assert "alpha" in names, f"alpha missing from {names}"
    assert "beta" in names, f"beta missing from {names}"
    assert "gamma" in names, f"gamma missing from {names}"
