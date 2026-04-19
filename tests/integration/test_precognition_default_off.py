# tests/integration/test_precognition_default_off.py
"""30.7: precognition must NOT auto-enable on cold nvim boot. Users
opt in via <leader>?p. Invariant: lua/plugins/precognition.lua sets
opts.startVisible = false."""

from pathlib import Path


def test_precognition_spec_default_off():
    spec = Path('lua/plugins/precognition.lua').read_text()
    assert 'startVisible = false' in spec, \
        'lua/plugins/precognition.lua must set startVisible = false'
    assert 'startVisible = true' not in spec, \
        'lua/plugins/precognition.lua must NOT set startVisible = true'
