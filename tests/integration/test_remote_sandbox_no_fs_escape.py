import json


def test_sandbox_schema_denies_fs_outside(tmp_path):
    # Pure doc-as-contract test: writes a sandbox settings.local.json
    # matching the shape `happy.projects.remote.provision` writes, and
    # asserts the deny/allow invariants.
    sandbox = tmp_path / 'sandbox'
    (sandbox / '.claude').mkdir(parents=True)
    settings = {
        "permissions": {
            "deny": [
                "Bash(ssh:*)", "Bash(scp:*)", "Bash(sftp:*)",
                "Bash(rsync:*)", "Bash(mosh:*)",
                "Bash(curl:*)", "Bash(wget:*)",
                "Bash(nc:*)", "Bash(socat:*)", "Bash(ssh-*)",
                "WebFetch(*)",
                "Read(/**)", "Edit(/**)", "Write(/**)",
            ],
            "allow": [
                f"Read({sandbox}/**)",
                f"Write({sandbox}/**)",
                f"Edit({sandbox}/**)",
            ],
        }
    }
    (sandbox / '.claude' / 'settings.local.json').write_text(json.dumps(settings))

    data = json.loads((sandbox / '.claude' / 'settings.local.json').read_text())
    assert 'Read(/**)' in data['permissions']['deny']
    assert 'Edit(/**)' in data['permissions']['deny']
    assert 'Write(/**)' in data['permissions']['deny']
    assert any('Bash(ssh' in p for p in data['permissions']['deny'])
    assert any('WebFetch' in p for p in data['permissions']['deny'])
    for scope in ('Read', 'Write', 'Edit'):
        assert any(f'{scope}({sandbox}' in a for a in data['permissions']['allow'])
