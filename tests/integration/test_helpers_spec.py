"""Unit tests for the assert_capture_equals golden-file helper.

Stubs capture_pane so the helper's behavior is tested w/o real tmux.
"""
from __future__ import annotations

import os
from pathlib import Path

import pytest

from . import helpers


@pytest.fixture(autouse=True)
def fake_capture(monkeypatch):
    """Make capture_pane return whatever we stash in _FAKE."""
    state = {"value": ""}
    def _capture(_socket, _target):
        return state["value"]
    monkeypatch.setattr(helpers, "capture_pane", _capture)
    return state


def test_asserts_equal_on_match(fake_capture, tmp_path: Path):
    golden = tmp_path / "golden.txt"
    golden.write_text("line one\nline two")
    fake_capture["value"] = "line one\nline two"
    # Must not raise
    helpers.assert_capture_equals("sock", "target", golden)


def test_raises_on_mismatch_with_unified_diff(fake_capture, tmp_path: Path):
    golden = tmp_path / "golden.txt"
    golden.write_text("line one\nline two")
    fake_capture["value"] = "line one\nCHANGED"
    with pytest.raises(AssertionError) as exc:
        helpers.assert_capture_equals("sock", "target", golden)
    msg = str(exc.value)
    assert "-line two" in msg, f"diff missing removed line: {msg}"
    assert "+CHANGED" in msg, f"diff missing added line: {msg}"
    assert str(golden) in msg, "diff missing golden path for context"


def test_update_golden_writes_file(fake_capture, tmp_path: Path, monkeypatch):
    golden = tmp_path / "nonexistent.txt"  # doesn't exist yet
    fake_capture["value"] = "brand new content"
    monkeypatch.setenv("UPDATE_GOLDEN", "1")
    helpers.assert_capture_equals("sock", "target", golden)
    assert golden.read_text() == "brand new content"


def test_update_golden_overwrites_existing(fake_capture, tmp_path: Path, monkeypatch):
    golden = tmp_path / "golden.txt"
    golden.write_text("stale content")
    fake_capture["value"] = "fresh content"
    monkeypatch.setenv("UPDATE_GOLDEN", "1")
    helpers.assert_capture_equals("sock", "target", golden)
    assert golden.read_text() == "fresh content"


def test_update_golden_disabled_on_other_values(fake_capture, tmp_path: Path, monkeypatch):
    """Only '1' enables regen — '0', 'false', empty are no-ops."""
    golden = tmp_path / "golden.txt"
    golden.write_text("existing")
    fake_capture["value"] = "different"
    for val in ("0", "false", ""):
        monkeypatch.setenv("UPDATE_GOLDEN", val)
        with pytest.raises(AssertionError):
            helpers.assert_capture_equals("sock", "target", golden)
