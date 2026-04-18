# Tests README + Golden-File Helper Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a README section explaining the test layers + how to run them, and extend `tests/integration/helpers.py` with a golden-file helper that prints a unified diff on mismatch and regenerates on `UPDATE_GOLDEN=1`.

**Architecture:** Two tiny, independent deliverables. README gets a "Running tests" subsection next to "Testing + Assessment" (or adjacent if that exists). The helper adds one function `assert_capture_equals(socket, target, expected_path)` that reuses the existing `capture_pane` helper, compares against a file, and either writes the file (regen mode) or asserts equality with a diff message.

**Tech Stack:** Python 3.11 stdlib (`difflib` for unified diffs), tmux 3.2+, existing pytest harness.

---

## File Structure

```
tests/integration/helpers.py           # MODIFIED — add assert_capture_equals()
tests/integration/test_helpers_spec.py # NEW (small) — unit test for the helper itself
README.md                              # MODIFIED — "Running tests" subsection
```

---

## Task 1: `assert_capture_equals` in `tests/integration/helpers.py`

**Files:**
- Modify: `tests/integration/helpers.py`
- Create: `tests/integration/test_helpers_spec.py`

**Context:** Integration tests frequently check "after sending these keys, the pane contents should look like this". Right now each test hand-codes assertions like `assert "ACK:hello" in output`. For larger captures (e.g. which-key menu layout, alpha dashboard rendering) we want an exact-match check against a committed file, with a one-env-var regen knob. Convention follows rust's `insta` + go's `cupaloy`: `UPDATE_GOLDEN=1 pytest ...` updates goldens; normal runs assert.

The helper:
- Reads expected text from `expected_path` (a `Path`).
- Gets current text via `capture_pane(socket, target)`.
- On `UPDATE_GOLDEN=1` env var → write current text to the file + return.
- Else: if texts differ, raise `AssertionError` with a `difflib.unified_diff` message.

The helper does NOT need tmux for its own unit test — we stub `capture_pane` via monkey-patching.

- [ ] **Step 1: Write the unit test first (TDD)**

Create `tests/integration/test_helpers_spec.py`:

```python
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
```

- [ ] **Step 2: Run the test to confirm it fails (helper doesn't exist yet)**

```bash
cd /home/raul/worktrees/happy-nvim/feat-v1-implementation
python3 -m pytest tests/integration/test_helpers_spec.py -v
```

Expected: all 5 tests FAIL with `AttributeError: module 'helpers' has no attribute 'assert_capture_equals'` (or similar).

- [ ] **Step 3: Add the helper to `tests/integration/helpers.py`**

Find the end of `tests/integration/helpers.py` (after `send_keys` / any other existing helpers). Add:

```python


def assert_capture_equals(socket: str, target: str, expected_path) -> None:
    """Assert pane capture matches a golden file; regen via UPDATE_GOLDEN=1.

    On mismatch, raises AssertionError w/ a unified diff pointing at the
    golden file so contributors can see what changed at a glance.

    Parameters
    ----------
    socket : str
        Tmux socket name (as passed to `tmx` / `capture_pane`).
    target : str
        Pane target (e.g. '%42' or session name).
    expected_path : pathlib.Path
        Path to the golden text file. Regen creates it if missing.

    Environment
    -----------
    UPDATE_GOLDEN=1 → overwrite (or create) the golden file with the current
    capture instead of asserting. Any other value is ignored.
    """
    import difflib
    import os as _os
    from pathlib import Path as _Path
    actual = capture_pane(socket, target)
    golden = _Path(expected_path)
    if _os.environ.get("UPDATE_GOLDEN") == "1":
        golden.parent.mkdir(parents=True, exist_ok=True)
        golden.write_text(actual)
        return
    expected = golden.read_text() if golden.exists() else ""
    if actual == expected:
        return
    diff = "\n".join(
        difflib.unified_diff(
            expected.splitlines(),
            actual.splitlines(),
            fromfile=str(golden),
            tofile="<pane capture>",
            lineterm="",
        )
    )
    raise AssertionError(
        f"capture does not match golden {golden}\n\n{diff}\n\n"
        f"(regen: UPDATE_GOLDEN=1 python3 -m pytest ...)"
    )
```

- [ ] **Step 4: Run the test to confirm it passes**

```bash
python3 -m pytest tests/integration/test_helpers_spec.py -v
```

Expected: `5 passed`.

- [ ] **Step 5: Assess + commit**

```bash
bash scripts/assess.sh 2>&1 | tail -10
```

Expected: `ALL LAYERS PASS`. The new helper is exercised only by its own spec; existing integration tests don't use it yet.

```bash
git add tests/integration/helpers.py tests/integration/test_helpers_spec.py
git commit -m "feat(test): golden-file helper w/ UPDATE_GOLDEN=1 regen

New assert_capture_equals(socket, target, expected_path) in
tests/integration/helpers.py. Compares current pane capture against
a committed text file; on mismatch emits a unified diff pointing at
the golden path. UPDATE_GOLDEN=1 regenerates the golden instead of
asserting (mirrors insta/cupaloy conventions).

5 plenary-style pytest unit tests cover the happy path + diff
formatting + regen (create + overwrite) + that only '1' enables
regen (not '0'/'false'/empty)."
```

---

## Task 2: README "Running tests" section

**Files:**
- Modify: `README.md`

**Context:** Contributors need a one-screen reference for how to run each test layer. The `CONTRIBUTING.md` already covers install; this goes in README under a "Testing" H2 so readers of the project landing page can see it.

- [ ] **Step 1: Append the subsection to README**

Find a natural home for it in `README.md`. If there's no "Testing" section yet, append this block near the end (after "Multi-project notifications" if present, otherwise after the last feature section):

```markdown

## Running tests

Three layers, cheapest first. All four commands run from the repo root.

### 1. Unit tests — plenary busted specs

Fast (~1s). Pure-lua assertions on module internals (project-id
resolver, idle state machine, coach tips, etc.).

```bash
nvim --headless -u tests/minimal_init.lua \
  -c "PlenaryBustedDirectory tests/ {minimal_init='tests/minimal_init.lua'}" \
  -c 'qa!'
```

### 2. Integration tests — real nvim in tmux

Slower (~30s). Scenarios spawn real nvim inside isolated tmux sessions
using the `fake-claude` stub. Requires `python3 -m pytest` + tmux >= 3.2.

```bash
bash scripts/test-integration.sh           # full suite
python3 -m pytest tests/integration/ -v    # equivalent
python3 -m pytest tests/integration/test_harpoon.py -v   # single scenario
```

Regenerate golden files for tests that use `assert_capture_equals`:

```bash
UPDATE_GOLDEN=1 python3 -m pytest tests/integration/test_whichkey_menu.py -v
```

### 3. One-button assessment — `scripts/assess.sh`

All six layers: shell/python syntax, init bootstrap, plenary, pytest
integration, `:checkhealth`. Prints a pass/fail table. Exits nonzero
on any failure. CI runs this under nvim stable + nightly.

```bash
bash scripts/assess.sh
```

Example output:

```
 LAYER                STATUS DURATION
----------------------------------------------------------------
 shell-syntax         PASS   0s
 python-syntax        PASS   1s
 init-bootstrap       PASS   0s
 plenary              PASS   1s
 integration          PASS   35s
 checkhealth          PASS   0s
ASSESS: ALL LAYERS PASS
```

### 4. Manual checklist — `docs/manual-tests.md`

For features CI can't exercise (real `claude` CLI, real SSH, host clipboard,
Nerd Font rendering). Walk through before cutting a release.
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs(readme): Running tests section

Four layers documented:
1. plenary unit specs (~1s, nvim --headless -u minimal_init)
2. pytest integration (~30s, scripts/test-integration.sh, w/
   UPDATE_GOLDEN=1 mention for the new golden-file helper)
3. scripts/assess.sh — one-button aggregator w/ example output
4. docs/manual-tests.md — what CI can't reach"
```

---

## Task 3: Manual test additions

**Files:**
- Modify: `docs/manual-tests.md`

- [ ] **Step 1: Add one row to "0. Pre-flight"**

Find section "0. Pre-flight" in `docs/manual-tests.md`. Append:

```markdown
- [ ] `bash scripts/assess.sh` runs to completion with `ASSESS: ALL LAYERS PASS`
```

- [ ] **Step 2: Commit**

```bash
git add docs/manual-tests.md
git commit -m "docs(manual): add assess.sh smoke to pre-flight"
```

---

## Task 4: Push + verify green CI

**Files:** none.

- [ ] **Step 1: FF + push**

```bash
cd /home/raul/projects/happy-nvim
git checkout main
git merge --ff-only feat/v1-implementation
git push git@github.com:raulfrk/happy-nvim.git main:main
```

- [ ] **Step 2: Poll + verify**

```bash
sleep 6
RUN_ID=$(gh api repos/raulfrk/happy-nvim/actions/runs --jq '.workflow_runs[0].id')
echo "$RUN_ID"
while true; do
  s=$(gh api "repos/raulfrk/happy-nvim/actions/runs/$RUN_ID" --jq '"\(.status)|\(.conclusion)"')
  echo "$(date +%H:%M:%S) $s"
  case "$s" in completed*) break;; esac
  sleep 60
done
gh api "repos/raulfrk/happy-nvim/actions/runs/$RUN_ID/jobs" --jq '.jobs[] | "\(.name): \(.conclusion)"'
```

Expected all `success`.

- [ ] **Step 3: Close source todos**

```
todo_complete 4.10 4.11
```

---

## Self-Review

**1. Spec coverage:**

| Todo | Task |
|---|---|
| #4.10 README "Running tests" section | Task 2 |
| #4.11 capture-pane golden file helper + diff | Task 1 |

**2. Placeholder scan:** no TBDs. Complete code blocks.

**3. Type consistency:**
- `assert_capture_equals(socket, target, expected_path)` signature matches between helpers.py impl + unit test calls + docstring.
- `capture_pane(socket, target)` signature reused from existing helpers.py (Task 1 Step 3 calls it unchanged).
- `UPDATE_GOLDEN=1` env var spelling consistent across helpers.py + README + test.
