"""Every <leader>s* flow that needs a host MUST route through
remote.hosts.pick. This test greps the source for the anti-pattern
`vim.fn.input('Host:')` to catch regressions at CI time."""
import pathlib


def test_no_host_input_prompts_in_remote_modules():
    root = pathlib.Path('lua/remote')
    offenders = []
    for f in root.rglob('*.lua'):
        body = f.read_text()
        if 'vim.fn.input' in body and 'Host' in body:
            for i, line in enumerate(body.splitlines(), 1):
                if 'vim.fn.input' in line and 'Host' in line:
                    offenders.append(f'{f}:{i}: {line.strip()}')
    assert not offenders, 'Host prompt must use remote.hosts.pick:\n' + '\n'.join(offenders)
