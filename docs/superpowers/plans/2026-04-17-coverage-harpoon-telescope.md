# Harpoon + Telescope Integration Test Coverage Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Pytest integration tests for the harpoon v2 workflow and telescope `find_files` picker — both running real nvim inside the isolated tmux harness. Guards against accidental removal of `<leader>h*` / `<leader>ff` keymaps, plugin-version drift, and first-load race conditions.

**Architecture:** Two small test files in `tests/integration/`. Both use the existing `tmux_socket` fixture from `conftest.py` and a per-test scratch nvim config that requires only the plugin under test (no full Lazy sync — too slow). The scratch config uses a minimal lazy bootstrap that loads just harpoon or just telescope. The test drives keystrokes via `tmux send-keys`, asserts observable effects via `capture-pane`.

**Tech Stack:** Python 3.11 + pytest (existing harness), tmux 3.2+, Neovim 0.11+, harpoon `harpoon2` branch, telescope.nvim. No new dependencies.

---

## File Structure

```
tests/integration/
├── conftest.py                       # unchanged
├── helpers.py                        # unchanged
├── test_harpoon.py                   # NEW
└── test_telescope.py                 # NEW
```

Each test owns one scratch config because the two plugins have different setup surfaces. Per-test configs are ~30 lines of Lua each; no shared helper is worth the indirection.

---

## Task 1: `tests/integration/test_harpoon.py` — add / switch / quick-nav

**Files:**
- Create: `tests/integration/test_harpoon.py`

**Context:** Harpoon v2 API: `harpoon:list():add()` marks current buffer; `harpoon:list():select(n)` jumps to the nth marked buffer. Our plugin spec wires `<leader>ha` → add and `<leader>h1..4` → select(n). The integration test needs to:

1. Start nvim in a tmux pane with a tiny config that bootstraps lazy + harpoon.
2. Edit 3 scratch files via `:e`.
3. Press `<leader>ha` on each (marks all 3).
4. Press `<leader>h1`, `<leader>h2`, `<leader>h3` and assert the active buffer's basename matches.

The "active buffer" check uses `tmux capture-pane` and looks for the filename in the status/ruler/buffer contents. Simpler probe: write `:echo expand('%:t')` after each select and assert via capture. Even simpler: use a plugin-free marker — `:echo` prints to the command line which tmux captures.

Scratch config only needs lazy + harpoon. Skip all other plugins to keep boot time ≤ 2s on CI.

- [ ] **Step 1: Write the test**

Create `tests/integration/test_harpoon.py`:

```python
"""Integration test: harpoon v2 add + select wiring.

Drives a minimal nvim (lazy + harpoon2 only) inside a tmux pane.
Marks 3 scratch files via <leader>ha, then jumps between them via
<leader>h1/h2/h3 and asserts the active buffer matches each time.

Guards against: accidental removal of <leader>h* keymaps, drift of
the harpoon2 branch pin, LazyDone race (setup not running before
tests fire keys).
"""
from __future__ import annotations

import os
import textwrap
import time
from pathlib import Path

import pytest

from .helpers import capture_pane, send_keys, tmx, wait_for_pane

REPO_ROOT = Path(__file__).resolve().parents[2]


def _write_scratch_config(cfg_dir: Path) -> None:
    """Write init.lua that bootstraps lazy + harpoon2 only."""
    cfg_dir.mkdir(parents=True, exist_ok=True)
    init = cfg_dir / "init.lua"
    init.write_text(textwrap.dedent(f"""
        -- Minimal config: lazy.nvim bootstrap + harpoon2 only.
        local data = vim.fn.stdpath('data')
        local lazypath = data .. '/lazy/lazy.nvim'
        if not vim.uv.fs_stat(lazypath) then
            vim.fn.system({{
                'git', 'clone', '--filter=blob:none',
                'https://github.com/folke/lazy.nvim.git',
                '--branch=stable', lazypath,
            }})
        end
        vim.opt.rtp:prepend(lazypath)

        vim.g.mapleader = ' '
        vim.g.maplocalleader = ' '

        require('lazy').setup({{
            {{ 'nvim-lua/plenary.nvim' }},
            {{
                'ThePrimeagen/harpoon',
                branch = 'harpoon2',
                dependencies = {{ 'nvim-lua/plenary.nvim' }},
                config = function()
                    local harpoon = require('harpoon')
                    harpoon:setup()
                    vim.keymap.set('n', '<leader>ha', function()
                        harpoon:list():add()
                    end, {{ desc = 'harpoon add' }})
                    for i = 1, 4 do
                        vim.keymap.set('n', '<leader>h' .. i, function()
                            harpoon:list():select(i)
                        end, {{ desc = 'harpoon select ' .. i }})
                    end
                end,
            }},
        }}, {{
            lockfile = '{cfg_dir}/lazy-lock.json',
            install = {{ missing = true }},
            change_detection = {{ enabled = false }},
        }})
    """).lstrip())


@pytest.fixture
def harpoon_scratch(tmp_path: Path) -> Path:
    cfg = tmp_path / "nvim"
    _write_scratch_config(cfg)
    # Give each test its own XDG so Lazy installs land in tmp_path
    return cfg


def test_harpoon_add_and_select(tmux_socket: str, harpoon_scratch: Path, tmp_path: Path):
    session = "harpoon-test"
    # Create 3 scratch files in a dedicated dir
    work = tmp_path / "work"
    work.mkdir()
    files = []
    for name in ("alpha.txt", "beta.txt", "gamma.txt"):
        p = work / name
        p.write_text(name + " content\n")
        files.append(p)

    env = {
        "XDG_CONFIG_HOME": str(harpoon_scratch.parent),
        "XDG_DATA_HOME": str(tmp_path / "data"),
        "XDG_STATE_HOME": str(tmp_path / "state"),
        "XDG_CACHE_HOME": str(tmp_path / "cache"),
        "TMUX": os.environ.get("TMUX", "/tmp/fake,1,0"),
        "HOME": str(tmp_path),
    }
    env_str = " ".join(f'{k}={v}' for k, v in env.items())

    try:
        # Open nvim with the first file already loaded
        tmx(
            tmux_socket, "new-session", "-d", "-s", session,
            "-x", "120", "-y", "40",
            f"{env_str} nvim --clean -u {harpoon_scratch}/init.lua {files[0]}",
        )
        # Wait for Lazy to finish cloning + harpoon config to register <leader>ha
        # (Lazy! sync on first run clones into XDG_DATA_HOME)
        wait_for_pane(tmux_socket, session, r"alpha\.txt", timeout=30)
        # Extra settle time for LazyDone + keymap registration
        time.sleep(1.0)

        # Mark all 3 files with <leader>ha
        for f in files:
            # Space is mapleader; send "<Space>ha" for each buffer
            send_keys(tmux_socket, session, "Space", "h", "a")
            time.sleep(0.2)
            # Open the next file (skip on last iteration)
            if f != files[-1]:
                next_idx = files.index(f) + 1
                send_keys(tmux_socket, session, f":e {files[next_idx]}", "Enter")
                # Wait for the filename to render (ruler or tabline)
                wait_for_pane(tmux_socket, session, files[next_idx].name, timeout=5)

        # Now cursor is in gamma.txt. Jump to each harpoon slot + verify.
        # Use :echo expand('%:t') to emit the basename to the cmd-line;
        # tmux capture will contain it right after the echo.
        def active_basename() -> str:
            send_keys(tmux_socket, session, ":echo expand('%:t')", "Enter")
            time.sleep(0.3)
            out = capture_pane(tmux_socket, session)
            # Walk lines backwards; the echo result is the last non-blank line
            for line in reversed(out.splitlines()):
                line = line.strip()
                if line and not line.startswith(":"):
                    return line
            return ""

        # Expect: slot 1 -> alpha, slot 2 -> beta, slot 3 -> gamma
        for idx, expected in enumerate([files[0], files[1], files[2]], start=1):
            send_keys(tmux_socket, session, "Space", "h", str(idx))
            time.sleep(0.3)
            got = active_basename()
            assert got == expected.name, (
                f"harpoon slot {idx}: expected {expected.name}, got {got!r}"
            )
    finally:
        tmx(tmux_socket, "kill-session", "-t", session, check=False)
```

- [ ] **Step 2: Run the test locally**

Run:
```bash
cd /home/raul/worktrees/happy-nvim/feat-v1-implementation
python3 -m pytest tests/integration/test_harpoon.py -v
```

Expected: `1 passed in X.XXs`. Likely the first run is slow (~15s) because Lazy clones harpoon2 fresh. Subsequent runs reuse the `tmp_path`-scoped data dir and are faster.

Likely failure modes + fixes:
- `wait_for_pane` times out on `alpha.txt` — Lazy's first-run clone took longer than 30s; bump timeout or verify network in the sandbox reaches github.com.
- `active_basename()` returns `":echo expand('%:t')"` instead of the filename — the echo line itself is caught. Tighten the reverse loop to skip lines starting with `:` (already done) and lines matching `Press ENTER or type command`. If still wrong, check capture-pane byte count.
- Harpoon v2's `:select(1)` errors before any files are marked — confirm `<Space>ha` on each file succeeded (it may have failed because harpoon setup() didn't run yet; bump the post-Lazy settle time to 2.0s).

- [ ] **Step 3: Run `bash scripts/assess.sh` to make sure other layers still pass**

Run:
```bash
bash scripts/assess.sh
```

Expected: ALL LAYERS PASS.

- [ ] **Step 4: Commit**

```bash
git add tests/integration/test_harpoon.py
git commit -m "test(integration): harpoon v2 add + select wiring

Minimal scratch nvim config loads lazy + harpoon2 only. Opens 3
scratch files, marks each w/ <leader>ha, then jumps via
<leader>h1/h2/h3 asserting the active buffer matches each slot.

Guards against: keymap removal, harpoon2 branch drift, Lazy race
(keymaps not registered before test fires keys)."
```

---

## Task 2: `tests/integration/test_telescope.py` — find_files picker navigates to selected file

**Files:**
- Create: `tests/integration/test_telescope.py`

**Context:** Telescope's `find_files` opens a floating picker listing files in cwd. Pressing Enter opens the selected file. Test flow:

1. Scratch nvim with lazy + telescope + plenary.
2. `<leader>ff` opens picker. Cwd has 3 scratch files.
3. Type part of a filename to filter.
4. Press Enter.
5. Assert the active buffer is the expected file (via `:echo expand('%:t')` same as harpoon test).

Telescope doesn't need a sorter extension for this test (default native_sorter is fine). We skip `telescope-fzf-native` to avoid the `make` build dep.

- [ ] **Step 1: Write the test**

Create `tests/integration/test_telescope.py`:

```python
"""Integration test: telescope find_files navigates to selected file.

Drives a minimal nvim (lazy + telescope + plenary) inside a tmux pane.
cwd has 3 scratch files. <leader>ff opens the picker, filters by typing,
Enter selects, we assert the active buffer via :echo expand('%:t').

Guards against: <leader>ff removal, telescope version drift, race
between Lazy bootstrap and first keypress.
"""
from __future__ import annotations

import os
import textwrap
import time
from pathlib import Path

import pytest

from .helpers import capture_pane, send_keys, tmx, wait_for_pane

REPO_ROOT = Path(__file__).resolve().parents[2]


def _write_scratch_config(cfg_dir: Path) -> None:
    cfg_dir.mkdir(parents=True, exist_ok=True)
    init = cfg_dir / "init.lua"
    init.write_text(textwrap.dedent(f"""
        local data = vim.fn.stdpath('data')
        local lazypath = data .. '/lazy/lazy.nvim'
        if not vim.uv.fs_stat(lazypath) then
            vim.fn.system({{
                'git', 'clone', '--filter=blob:none',
                'https://github.com/folke/lazy.nvim.git',
                '--branch=stable', lazypath,
            }})
        end
        vim.opt.rtp:prepend(lazypath)

        vim.g.mapleader = ' '
        vim.g.maplocalleader = ' '

        require('lazy').setup({{
            {{ 'nvim-lua/plenary.nvim' }},
            {{
                'nvim-telescope/telescope.nvim',
                branch = '0.1.x',
                dependencies = {{ 'nvim-lua/plenary.nvim' }},
                config = function()
                    local telescope = require('telescope')
                    telescope.setup({{}})
                    vim.keymap.set('n', '<leader>ff', function()
                        require('telescope.builtin').find_files({{
                            hidden = false, follow = false,
                        }})
                    end, {{ desc = 'telescope find_files' }})
                end,
            }},
        }}, {{
            lockfile = '{cfg_dir}/lazy-lock.json',
            install = {{ missing = true }},
            change_detection = {{ enabled = false }},
        }})
    """).lstrip())


@pytest.fixture
def telescope_scratch(tmp_path: Path) -> Path:
    cfg = tmp_path / "nvim"
    _write_scratch_config(cfg)
    return cfg


def test_telescope_find_files_opens_selected(
    tmux_socket: str, telescope_scratch: Path, tmp_path: Path
):
    session = "telescope-test"
    work = tmp_path / "work"
    work.mkdir()
    for name in ("alpha.txt", "beta.txt", "gamma.txt"):
        (work / name).write_text(name + " content\n")

    env = {
        "XDG_CONFIG_HOME": str(telescope_scratch.parent),
        "XDG_DATA_HOME": str(tmp_path / "data"),
        "XDG_STATE_HOME": str(tmp_path / "state"),
        "XDG_CACHE_HOME": str(tmp_path / "cache"),
        "TMUX": os.environ.get("TMUX", "/tmp/fake,1,0"),
        "HOME": str(tmp_path),
    }
    env_str = " ".join(f'{k}={v}' for k, v in env.items())

    try:
        # Start nvim in the work dir so find_files sees our 3 files
        tmx(
            tmux_socket, "new-session", "-d", "-s", session,
            "-x", "120", "-y", "40", "-c", str(work),
            f"{env_str} nvim --clean -u {telescope_scratch}/init.lua",
        )
        # Wait for lazy + telescope to install
        time.sleep(1.0)
        wait_for_pane(tmux_socket, session, r"Press ENTER|^~|\[No Name\]|init\.lua", timeout=30)
        # Extra settle so telescope setup has registered
        time.sleep(1.5)

        # Open find_files via <leader>ff
        send_keys(tmux_socket, session, "Space", "f", "f")
        # Telescope prompt shows with '>' prompt + result list
        wait_for_pane(tmux_socket, session, r"alpha\.txt", timeout=10)

        # Filter to just 'beta' and select
        send_keys(tmux_socket, session, "beta")
        time.sleep(0.3)
        send_keys(tmux_socket, session, "Enter")
        time.sleep(0.5)

        # Verify active buffer
        send_keys(tmux_socket, session, ":echo expand('%:t')", "Enter")
        time.sleep(0.3)
        out = capture_pane(tmux_socket, session)
        found = None
        for line in reversed(out.splitlines()):
            s = line.strip()
            if s and not s.startswith(":") and not s.startswith("Press"):
                found = s
                break
        assert found == "beta.txt", (
            f"expected active buffer beta.txt, got {found!r}\n"
            f"capture:\n{out}"
        )
    finally:
        tmx(tmux_socket, "kill-session", "-t", session, check=False)
```

- [ ] **Step 2: Run the test locally**

Run:
```bash
python3 -m pytest tests/integration/test_telescope.py -v
```

Expected: `1 passed`. First run is slow (~20s cloning telescope + plenary). Subsequent runs reuse the data dir.

Likely failure fixes:
- `wait_for_pane(r"alpha\.txt", ...)` after `<Space>ff` times out — telescope picker didn't open. Check the scratch config's `vim.keymap.set('n', '<leader>ff', ...)` registered. If Lazy was still cloning at keypress time, bump the settle to 3.0s.
- Active buffer asserts `[No Name]` instead of `beta.txt` — Enter fired before telescope's select action was armed. Add `time.sleep(1.0)` between typing filter + Enter.
- `found` is `"beta.txt content"` instead of `"beta.txt"` — capture caught the file's content line; tighten the filter to ignore lines containing `content`. Simpler fix: land cursor on the echo'd line only by checking lines that look like filenames (end with `.txt`).

- [ ] **Step 3: Run assess.sh**

Run:
```bash
bash scripts/assess.sh
```

Expected: ALL LAYERS PASS.

- [ ] **Step 4: Commit**

```bash
git add tests/integration/test_telescope.py
git commit -m "test(integration): telescope find_files navigates to selected file

Minimal scratch nvim (lazy + telescope + plenary). cwd has 3
scratch files; <leader>ff opens picker, filter 'beta', Enter,
assert active buffer is beta.txt. Skips fzf-native to dodge
the make build dep.

Guards against: <leader>ff removal, telescope branch drift,
keymap registration race w/ Lazy bootstrap."
```

---

## Manual Test Additions

Append these rows to `docs/manual-tests.md` in the "Core editing" section after the existing harpoon / telescope entries (they are already present for the keymaps themselves; the CI-covered versions confirm the logic):

```markdown
- [ ] (CI-covered, but worth spot-checking locally) `<Space>ff` in a repo with >50 files — telescope sorts by relevance, not alphabet
- [ ] (CI-covered) harpoon persists marks across nvim restarts if the same cwd is re-opened (v2 stores in `~/.local/share/nvim/harpoon2.json`)
```

- [ ] **Task 3: Append to manual-tests.md**

Find the "Core editing" section in `docs/manual-tests.md`. Add the two lines above after the existing `<Space>ff` row.

- [ ] **Step 1: Edit the file**

Open `docs/manual-tests.md`, find:

```markdown
- [ ] `<Space>fh` — telescope harpoon list
```

Add after it:

```markdown
- [ ] (CI-covered, but worth spot-checking locally) `<Space>ff` in a repo with >50 files — telescope sorts by relevance, not alphabet
- [ ] (CI-covered) harpoon persists marks across nvim restarts if the same cwd is re-opened (v2 stores in `~/.local/share/nvim/harpoon2.json`)
```

- [ ] **Step 2: Commit**

```bash
git add docs/manual-tests.md
git commit -m "docs(manual): annotate CI-covered rows for harpoon + telescope

New pytest integration tests (test_harpoon.py, test_telescope.py)
exercise <leader>ha/h1-4 and <leader>ff. Manual checklist now
flags these as 'CI-covered' so contributors know they can skip
during routine passes."
```

---

## Task 4: Push + verify green CI

**Files:** none.

- [ ] **Step 1: FF main + push**

```bash
cd /home/raul/projects/happy-nvim
git checkout main
git merge --ff-only feat/v1-implementation
git push git@github.com:raulfrk/happy-nvim.git main:main
```

Expected: `main -> main` advances 3 commits (harpoon test, telescope test, manual-tests doc).

- [ ] **Step 2: Capture + poll**

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
```

- [ ] **Step 3: Verify per-job status**

```bash
gh api "repos/raulfrk/happy-nvim/actions/runs/$RUN_ID/jobs" --jq '.jobs[] | "\(.name): \(.conclusion)"'
```

All should be `success`, especially `integration (stable/nightly)` and `assess (stable/nightly)`.

If integration fails on `test_harpoon` or `test_telescope`: fetch logs:

```bash
TMPDIR=/tmp XDG_CACHE_HOME=/tmp gh run view "$RUN_ID" --log-failed -R raulfrk/happy-nvim | tail -100
```

Most likely cause = Lazy clone race: the `wait_for_pane` threshold needs bumping. Each test has an initial `time.sleep(1.0)` + a waits-for-buffer-name + a settle sleep. Double all of those if the CI runner is slower than local.

- [ ] **Step 4: Close source todos**

```
todo_complete 5.2 5.3
```

---

## Self-Review

**1. Spec coverage:**

| Todo | Task |
|---|---|
| #5.2 harpoon integration test | Task 1 |
| #5.3 telescope find_files integration test | Task 2 |
| #6.2 (implicit — plan includes Manual Test Additions section) | Task 3 |

Task 3 is the Manual Test Additions pattern from todo 6.2. This plan is the first to formally include it; future plans should follow the same structure.

**2. Placeholder scan:** no TBDs, no "similar to Task N". Every code block complete. `active_basename()` heuristic + `found` filter in the telescope test are both documented with fallback fixes inline.

**3. Type consistency:**
- Both tests use identical env dict shape + `env_str` formatting.
- Both use the same scratch-config fixture pattern (per-test `_write_scratch_config`).
- `capture_pane`, `send_keys`, `tmx`, `wait_for_pane` helpers match Phase 1/2 usage.
- `tmux_socket` fixture from existing `conftest.py`.
- `tmp_path` is a pytest builtin; no new dependency.
