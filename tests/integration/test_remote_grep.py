"""Integration: remote.grep builds the expected ssh+grep command.

Calls _build_cmd(host, opts) from headless nvim, asserts the produced
cmd array contains ssh + host + grep + ERE flag + pattern + -size 10M.
Independent of network/real ssh.

API adaptation: _build_cmd signature is (host, opts) not ({...}),
where opts = {pattern, path, glob, regex, nocase, hidden, all, size, timeout}.
"""
from __future__ import annotations

import json
import os
import subprocess
import textwrap
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]


def _make_ssh_shim(bin_dir: Path, log: Path) -> None:
    bin_dir.mkdir(parents=True, exist_ok=True)
    shim = bin_dir / "ssh"
    shim.write_text(textwrap.dedent(f"""\
        #!/usr/bin/env bash
        # Log every arg one per line + an end marker
        for a in "$@"; do printf '%s\\n' "$a" >> '{log}'; done
        printf -- '---END---\\n' >> '{log}'
        # Pretend grep found nothing
        exit 1
    """))
    shim.chmod(0o755)


def test_grep_builds_expected_command(tmp_path: Path):
    bin_dir = tmp_path / "bin"
    log = tmp_path / "ssh.log"
    _make_ssh_shim(bin_dir, log)
    env = os.environ | {
        "PATH": f"{bin_dir}:{os.environ['PATH']}",
        "HOME": str(tmp_path / "home"),
        "XDG_DATA_HOME": str(tmp_path / "data"),
        "XDG_STATE_HOME": str(tmp_path / "state"),
        "XDG_CACHE_HOME": str(tmp_path / "cache"),
        "XDG_CONFIG_HOME": str(tmp_path / "cfg"),
    }
    # _build_cmd(host, opts) — host is first arg, opts is table with all fields
    out_file = tmp_path / "cmd.json"
    subprocess.run(
        [
            "nvim", "--headless", "--clean",
            "-c", f"lua vim.opt.rtp:prepend('{REPO_ROOT}')",
            "-c", (
                "lua local g = require('remote.grep');"
                " local opts = {pattern='TODO', path='/tmp', glob='*.lua',"
                " regex='ext', nocase=false, hidden=false, all=false,"
                " size='10M', timeout=30};"
                f" vim.fn.writefile({{vim.json.encode(g._build_cmd('alpha', opts))}}, '{out_file}')"
            ),
            "-c", "qa!",
        ],
        check=True, text=True, capture_output=True, env=env,
    )
    cmd = json.loads(out_file.read_text())
    # cmd is the array: ['ssh', 'alpha', '<remote shell cmd>']
    flat = " ".join(cmd)
    assert "ssh" in flat
    assert "alpha" in flat
    assert "grep" in flat
    assert "-E" in flat, f"missing ERE flag in: {flat}"
    assert "TODO" in flat
    assert "-size" in flat and "10M" in flat, f"missing size cap: {flat}"
