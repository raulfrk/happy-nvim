# Test Harness + Tree-sitter CLI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Unblock fresh happy-nvim installs (tree-sitter CLI auto-installed) and lay foundation for integration tests via a Python-based harness: fake-claude stub, pytest-driven scenarios, tmux isolation managed by conftest fixtures.

**Architecture:** `scripts/migrate.sh` stays bash (install-time; run via `curl | bash`). Everything test-related is Python 3.11 stdlib only: `tests/integration/fake_claude.py` (deterministic claude stub), `tests/integration/conftest.py` (pytest fixtures: isolated tmux server, scratch XDG dirs, PATH shim), `tests/integration/test_*.py` (scenarios as regular pytest tests using `subprocess` + `tmux capture-pane`). `scripts/test-integration.sh` is a 5-line wrapper invoking `pytest tests/integration/ -v`. Python gives us real assertions w/ diffs, parametrization, and proper signal/cleanup handling — bash was doing all this awkwardly.

**Tech Stack:** Bash 5 (migrate.sh only), Python 3.11 stdlib + pytest, tmux 3.2+, npm, Neovim 0.11+.

---

## File Structure

```
scripts/
├── migrate.sh             # modified — preflight installs tree-sitter CLI
└── test-integration.sh    # new — 5-line wrapper, runs pytest

tests/integration/
├── conftest.py            # new — pytest fixtures: tmux server, XDG, PATH
├── fake_claude.py         # new — deterministic claude stub (python3)
├── helpers.py             # new — tmux/capture-pane helper fns
└── test_smoke.py          # new — baseline "harness works" scenario
```

One responsibility per file. `conftest.py` owns lifecycle (setup/teardown), `helpers.py` owns reusable tmux ops, `fake_claude.py` is a standalone executable, `test_smoke.py` is the first scenario proving the whole stack works. Scenarios sharing state would only grow if duplicated — pytest fixtures prevent that by construction.

---

## Task 1: Add tree-sitter CLI preflight to migrate.sh

**Files:**
- Modify: `scripts/migrate.sh`

**Context:** `nvim-treesitter` main branch (adopted in commit `3fde856`) requires `tree-sitter` CLI on `$PATH` to build parsers. Fresh installs fail with `ENOENT: tree-sitter`. Install via npm-global (user already has `npm`). Stays bash because migrate.sh runs before Python is guaranteed available on the host.

- [ ] **Step 1: Read current preflight section**

Run:
```bash
sed -n '20,35p' scripts/migrate.sh
```

Expected output contains the nvim-version check `if ! nvim --headless --clean -c 'lua if vim.fn.has("nvim-0.11") == 0 then vim.cmd("cq") end' ...`.

- [ ] **Step 2: Insert tree-sitter preflight block after the nvim-version check**

Locate this block in `scripts/migrate.sh`:

```bash
if ! nvim --headless --clean -c 'lua if vim.fn.has("nvim-0.11") == 0 then vim.cmd("cq") end' -c 'qa!' 2>/dev/null; then
  cur=$(nvim --version | head -1)
  die "happy-nvim requires nvim >= 0.11. Found: $cur
Upgrade: https://github.com/neovim/neovim/releases/tag/stable
Debian/Ubuntu: curl -L https://github.com/neovim/neovim/releases/download/stable/nvim-linux-x86_64.tar.gz -o /tmp/nvim.tar.gz && sudo tar -C /opt -xzf /tmp/nvim.tar.gz && sudo ln -sf /opt/nvim-linux-x86_64/bin/nvim /usr/local/bin/nvim"
fi
```

Add immediately after it:

```bash
# 1b. Preflight — tree-sitter CLI required by nvim-treesitter@main for parser builds
if ! command -v tree-sitter >/dev/null 2>&1; then
  log "tree-sitter CLI not found — installing via npm-global"
  if ! command -v npm >/dev/null 2>&1; then
    die "npm not found. Install Node.js (includes npm) then re-run: https://nodejs.org/en/download"
  fi
  if ! npm install -g tree-sitter-cli 2>/dev/null; then
    warn "global npm install failed — retrying with sudo"
    sudo npm install -g tree-sitter-cli || die "npm install -g tree-sitter-cli failed. Install manually: cargo install tree-sitter-cli"
  fi
  command -v tree-sitter >/dev/null 2>&1 || die "tree-sitter still not on \$PATH after install. Check npm global prefix: npm config get prefix"
fi
log "tree-sitter: $(tree-sitter --version 2>&1 | head -1)"
```

- [ ] **Step 3: Syntax check**

Run:
```bash
bash -n scripts/migrate.sh && echo SYNTAX_OK
```

Expected: `SYNTAX_OK`.

- [ ] **Step 4: Smoke-test the preflight in isolation**

Run:
```bash
# Extract just the preflight block and run the positive branch
bash -c 'command -v tree-sitter && tree-sitter --version'
```

Expected: prints a version like `tree-sitter 0.22.x`. If `tree-sitter` is missing on your box, run the actual migrate once: `bash scripts/migrate.sh` — you should see `tree-sitter CLI not found — installing via npm-global` followed by a version line.

- [ ] **Step 5: Commit**

```bash
git add scripts/migrate.sh
git commit -m "feat(migrate): preflight tree-sitter CLI install via npm-global

nvim-treesitter@main needs tree-sitter on \$PATH to build parsers.
Fresh installs currently fail with ENOENT. Install via
'npm install -g tree-sitter-cli' (sudo retry on EACCES; die with
cargo install hint on total failure)."
```

---

## Task 2: Write tests/integration/fake_claude.py

**Files:**
- Create: `tests/integration/fake_claude.py`

**Context:** Integration tests need a predictable Claude CLI replacement. Python script rather than bash — cleaner stdin handling, deterministic timing w/ `time.sleep`, exit code propagation. Reads stdin line-by-line. For each non-empty line: echoes `> <line>`, sleeps DELAY seconds, echoes `Assistant: ACK:<line>`, prints next prompt. `--slow` flag uses 2 s. `--delay <secs>` overrides. No stdlib imports beyond `sys` + `time` + `argparse`.

- [ ] **Step 1: Write the stub**

Create `tests/integration/fake_claude.py`:

```python
#!/usr/bin/env python3
"""Deterministic claude(1) stub for integration tests.

Reads stdin line-by-line. For each non-empty line:
  1. echoes "> <line>" (mimics user-input echo from the real CLI)
  2. sleeps DELAY seconds (default 0.5, 2.0 with --slow, or --delay N)
  3. echoes "Assistant: ACK:<line>"
  4. prints the next "> " prompt

Exits 0 on EOF. No network, no hidden state, no filesystem writes.
Used by tests/integration/test_*.py via the pytest fixtures in conftest.py.
"""
from __future__ import annotations

import argparse
import sys
import time


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--slow", action="store_true", help="use 2.0s delay")
    parser.add_argument("--delay", type=float, default=0.5, help="seconds (default 0.5)")
    args = parser.parse_args()

    delay = 2.0 if args.slow else args.delay

    print("> ", end="", flush=True)
    for raw in sys.stdin:
        line = raw.rstrip("\n")
        if not line:
            print("> ", end="", flush=True)
            continue
        print(f"> {line}", flush=True)
        time.sleep(delay)
        print(f"Assistant: ACK:{line}", flush=True)
        print("", flush=True)
        print("> ", end="", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

- [ ] **Step 2: Make it executable**

Run:
```bash
chmod +x tests/integration/fake_claude.py
```

- [ ] **Step 3: Smoke-test via pipe**

Run:
```bash
printf 'hello\nworld\n' | ./tests/integration/fake_claude.py --delay 0
```

Expected output exactly:
```
> > hello
Assistant: ACK:hello

> > world
Assistant: ACK:world

>
```

(`--delay 0` removes the sleep for the smoke test.)

- [ ] **Step 4: Smoke-test --slow timing**

Run:
```bash
time printf 'x\n' | ./tests/integration/fake_claude.py --slow
```

Expected: `real` ≥ 2.0 s, output ends with `Assistant: ACK:x`.

- [ ] **Step 5: Commit**

```bash
mkdir -p tests/integration
git add tests/integration/fake_claude.py
git commit -m "test: add tests/integration/fake_claude.py deterministic stub

Python3 stdlib-only claude CLI replacement. Reads stdin line-by-line,
echoes 'Assistant: ACK:<line>' w/ configurable delay (--slow=2.0s,
--delay N). Used by pytest integration tests for reproducible
assertions on pane contents and idle-detection timing."
```

---

## Task 3: Write tests/integration/helpers.py

**Files:**
- Create: `tests/integration/helpers.py`

**Context:** Reusable tmux ops. Three functions: `capture_pane` (ANSI-stripped contents), `wait_for_pane` (poll-until-match w/ timeout + good diagnostic on timeout), `send_keys` (thin wrapper around tmux send-keys). Sourced by scenarios. Kept small — scenario complexity lives in each `test_*.py`.

- [ ] **Step 1: Write the helpers**

Create `tests/integration/helpers.py`:

```python
"""Helpers for integration scenarios.

All helpers operate on the isolated tmux server set up by conftest's
`tmux_socket` fixture. Callers pass the socket name explicitly so the
functions are pure (no hidden global state).
"""
from __future__ import annotations

import re
import subprocess
import time

ANSI_RE = re.compile(r"\x1b\[[0-9;]*m")


def tmx(socket: str, *args: str, check: bool = True) -> subprocess.CompletedProcess:
    """Run `tmux -L <socket> <args...>` and return CompletedProcess."""
    return subprocess.run(
        ["tmux", "-L", socket, *args],
        check=check,
        text=True,
        capture_output=True,
    )


def capture_pane(socket: str, target: str) -> str:
    """Return pane contents with ANSI escapes stripped and trailing spaces trimmed."""
    result = tmx(socket, "capture-pane", "-p", "-t", target)
    lines = (ANSI_RE.sub("", line).rstrip() for line in result.stdout.splitlines())
    return "\n".join(lines)


def wait_for_pane(
    socket: str,
    target: str,
    pattern: str,
    timeout: float = 5.0,
    poll_interval: float = 0.1,
) -> str:
    """Poll `target` until `pattern` (regex) matches a line in capture output.

    Returns the full capture on match. Raises AssertionError with the last
    capture attached on timeout.
    """
    deadline = time.monotonic() + timeout
    regex = re.compile(pattern, re.MULTILINE)
    last = ""
    while time.monotonic() < deadline:
        last = capture_pane(socket, target)
        if regex.search(last):
            return last
        time.sleep(poll_interval)
    raise AssertionError(
        f"wait_for_pane: pattern {pattern!r} not found in {target!r} after {timeout}s\n"
        f"--- last capture ---\n{last}\n--- end ---"
    )


def send_keys(socket: str, target: str, *keys: str) -> None:
    """Send keys to a pane. Each arg is passed as-is to `tmux send-keys`."""
    tmx(socket, "send-keys", "-t", target, *keys)
```

- [ ] **Step 2: Syntax check**

Run:
```bash
python3 -c "import ast; ast.parse(open('tests/integration/helpers.py').read()); print('SYNTAX_OK')"
```

Expected: `SYNTAX_OK`.

- [ ] **Step 3: Commit**

```bash
git add tests/integration/helpers.py
git commit -m "test: add tests/integration/helpers.py tmux helpers

Three pure functions: tmx (socket-scoped subprocess wrapper),
capture_pane (ANSI-stripped output), wait_for_pane (poll-until-regex
w/ timeout + diagnostic capture on failure). Callers pass socket name
explicitly — no hidden global state."
```

---

## Task 4: Write tests/integration/conftest.py

**Files:**
- Create: `tests/integration/conftest.py`

**Context:** Pytest fixtures managing the integration environment per-session: one isolated tmux server (socket name `happy-test-<pid>`), scratch XDG dirs, `fake_claude.py` + a `claude` symlink first on `$PATH`. Tests get these via fixture args. Cleanup on teardown via the fixture yield pattern.

- [ ] **Step 1: Write conftest**

Create `tests/integration/conftest.py`:

```python
"""Pytest fixtures for happy-nvim integration tests.

Each pytest session runs against:
- An isolated tmux server on socket `happy-test-<pid>` (never touches the
  user's default tmux).
- A scratch tempdir with XDG_*_HOME redirected into it (so nvim plugin
  state doesn't leak into the user's ~/.local/share/nvim).
- A PATH prepended with a bin/ dir that shadows `claude` with
  fake_claude.py.

Fixtures are session-scoped — one tmux server shared across all scenarios
in a run, but each scenario creates its own tmux sessions via `tmux_socket`.
"""
from __future__ import annotations

import os
import shutil
import subprocess
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
FAKE_CLAUDE = Path(__file__).resolve().parent / "fake_claude.py"
MIN_TMUX_MAJOR, MIN_TMUX_MINOR = 3, 2


def _tmux_version() -> tuple[int, int]:
    out = subprocess.check_output(["tmux", "-V"], text=True).strip()
    # "tmux 3.4" or "tmux next-3.4"
    parts = out.split()[-1].lstrip("next-").split(".")
    return int(parts[0]), int(parts[1])


@pytest.fixture(scope="session")
def scratch_dir(tmp_path_factory) -> Path:
    """Session-wide scratch dir; auto-removed at end of pytest session."""
    return tmp_path_factory.mktemp("happy-integration")


@pytest.fixture(scope="session", autouse=True)
def _env(scratch_dir: Path, monkeypatch_session):
    """Redirect XDG dirs and prepend fake-claude bin dir to PATH."""
    for var in ("XDG_CONFIG_HOME", "XDG_DATA_HOME", "XDG_CACHE_HOME", "XDG_STATE_HOME"):
        target = scratch_dir / var.split("_")[1].lower()
        target.mkdir(parents=True, exist_ok=True)
        monkeypatch_session.setenv(var, str(target))

    bin_dir = scratch_dir / "bin"
    bin_dir.mkdir(parents=True, exist_ok=True)
    (bin_dir / "fake_claude.py").symlink_to(FAKE_CLAUDE)
    (bin_dir / "claude").symlink_to(FAKE_CLAUDE)
    monkeypatch_session.setenv("PATH", f"{bin_dir}:{os.environ['PATH']}")


@pytest.fixture(scope="session")
def monkeypatch_session():
    """Session-scoped monkeypatch (pytest's default is function-scoped)."""
    from _pytest.monkeypatch import MonkeyPatch
    mp = MonkeyPatch()
    yield mp
    mp.undo()


@pytest.fixture(scope="session")
def tmux_socket() -> str:
    """Start an isolated tmux server; return socket name; kill on teardown."""
    if shutil.which("tmux") is None:
        pytest.skip("tmux not installed")
    major, minor = _tmux_version()
    if (major, minor) < (MIN_TMUX_MAJOR, MIN_TMUX_MINOR):
        pytest.skip(f"tmux >= {MIN_TMUX_MAJOR}.{MIN_TMUX_MINOR} required, found {major}.{minor}")

    socket = f"happy-test-{os.getpid()}"
    # tmux starts the server lazily on first command; force it via a no-op
    subprocess.run(["tmux", "-L", socket, "list-sessions"], capture_output=True)
    yield socket
    subprocess.run(["tmux", "-L", socket, "kill-server"], capture_output=True)
```

- [ ] **Step 2: Verify pytest is available**

Run:
```bash
python3 -c "import pytest; print(pytest.__version__)"
```

Expected: version like `8.x.x`. If missing: `pip install --user pytest` or add to CI install step.

- [ ] **Step 3: Syntax check**

Run:
```bash
python3 -c "import ast; ast.parse(open('tests/integration/conftest.py').read()); print('SYNTAX_OK')"
```

Expected: `SYNTAX_OK`.

- [ ] **Step 4: Commit**

```bash
git add tests/integration/conftest.py
git commit -m "test: add tests/integration/conftest.py pytest fixtures

Session-scoped fixtures manage integration test isolation:
- scratch_dir: tempdir for XDG redirection, auto-removed
- _env: redirects XDG_*_HOME, symlinks fake_claude.py as 'claude'
  first on \$PATH
- tmux_socket: isolated tmux server (socket 'happy-test-<pid>'),
  skipped if tmux < 3.2. Killed on session teardown."
```

---

## Task 5: Write tests/integration/test_smoke.py baseline scenario

**Files:**
- Create: `tests/integration/test_smoke.py`

**Context:** Smallest real test — proves fake-claude is on PATH, tmux isolation works, helpers fire correctly. If this passes, follow-up plans (persistence, routing, idle-notify) have a trusted foundation.

- [ ] **Step 1: Write the scenario**

Create `tests/integration/test_smoke.py`:

```python
"""Baseline scenario — proves the harness works end-to-end.

If this fails, don't trust any other integration test until it's fixed.
"""
from __future__ import annotations

import shutil

from .helpers import capture_pane, send_keys, tmx, wait_for_pane


def test_fake_claude_on_path():
    """conftest's _env fixture should shadow `claude` with fake_claude.py."""
    claude_path = shutil.which("claude")
    assert claude_path is not None, "claude (fake) not on PATH"
    assert claude_path.endswith("/bin/claude"), f"unexpected claude path: {claude_path}"


def test_tmux_echo_roundtrip(tmux_socket: str):
    """Run fake-claude in a tmux pane; send a line; assert the ACK appears.

    Exercises: tmux isolation, fake_claude stdin handling, capture_pane,
    wait_for_pane regex matching.
    """
    session = "smoke"
    try:
        tmx(
            tmux_socket,
            "new-session",
            "-d",
            "-s",
            session,
            "-x",
            "80",
            "-y",
            "24",
            "claude --delay 0",
        )
        send_keys(tmux_socket, session, "hello", "Enter")
        output = wait_for_pane(tmux_socket, session, r"^Assistant: ACK:hello$", timeout=5)
        assert "ACK:hello" in output

        send_keys(tmux_socket, session, "world", "Enter")
        wait_for_pane(tmux_socket, session, r"^Assistant: ACK:world$", timeout=5)
    finally:
        tmx(tmux_socket, "kill-session", "-t", session, check=False)


def test_helpers_strip_ansi(tmux_socket: str):
    """capture_pane must strip tmux's ANSI escapes from colored output."""
    session = "ansi"
    try:
        # printf ANSI red text via shell
        tmx(
            tmux_socket,
            "new-session",
            "-d",
            "-s",
            session,
            "-x",
            "80",
            "-y",
            "24",
            "printf '\\033[31mred\\033[0m\\n'; sleep 5",
        )
        wait_for_pane(tmux_socket, session, r"^red$", timeout=2)
        output = capture_pane(tmux_socket, session)
        assert "\x1b" not in output, "ANSI not stripped"
        assert "red" in output
    finally:
        tmx(tmux_socket, "kill-session", "-t", session, check=False)
```

- [ ] **Step 2: Syntax check**

Run:
```bash
python3 -c "import ast; ast.parse(open('tests/integration/test_smoke.py').read()); print('SYNTAX_OK')"
```

Expected: `SYNTAX_OK`.

- [ ] **Step 3: Run pytest directly (not yet via harness script)**

Run from repo root:
```bash
python3 -m pytest tests/integration/test_smoke.py -v
```

Expected tail:
```
tests/integration/test_smoke.py::test_fake_claude_on_path PASSED
tests/integration/test_smoke.py::test_tmux_echo_roundtrip PASSED
tests/integration/test_smoke.py::test_helpers_strip_ansi PASSED

======== 3 passed in X.XXs ========
```

If `test_fake_claude_on_path` fails with "not on PATH": the `_env` autouse fixture didn't run, check conftest.py for typos.

- [ ] **Step 4: Commit**

```bash
git add tests/integration/test_smoke.py
git commit -m "test: add tests/integration/test_smoke.py baseline

Three assertions: (1) fake_claude.py shadows 'claude' on PATH,
(2) tmux send-keys + capture-pane round-trips correctly via
fake_claude ACK, (3) ANSI escapes stripped from capture output.
If this passes, harness is trustworthy for regression specs."
```

---

## Task 6: Write scripts/test-integration.sh wrapper

**Files:**
- Create: `scripts/test-integration.sh`

**Context:** One-line-ish wrapper so both local dev and CI run tests the same way without remembering pytest flags. Contributors type `bash scripts/test-integration.sh`; CI does the same.

- [ ] **Step 1: Write the wrapper**

Create `scripts/test-integration.sh`:

```bash
#!/usr/bin/env bash
# scripts/test-integration.sh — shared local+CI integration test entry point.
#
# Runs pytest against tests/integration/. Tmux + XDG isolation managed
# by tests/integration/conftest.py fixtures.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

command -v python3 >/dev/null || { echo "python3 required" >&2; exit 2; }
python3 -m pytest --version >/dev/null 2>&1 || {
  echo "pytest required: pip install --user pytest" >&2
  exit 2
}

exec python3 -m pytest tests/integration/ -v "$@"
```

- [ ] **Step 2: Make executable**

Run:
```bash
chmod +x scripts/test-integration.sh
```

- [ ] **Step 3: Syntax + full run**

Run:
```bash
bash -n scripts/test-integration.sh && echo SYNTAX_OK
bash scripts/test-integration.sh
```

Expected: `SYNTAX_OK`, then pytest output ending in `3 passed in X.XXs`.

- [ ] **Step 4: Verify no leaked tmux server**

Run:
```bash
tmux -L "happy-test-$$" list-sessions 2>&1 || echo NO_SERVER
```

Expected: `NO_SERVER` (or `no server running on ...`). The session-teardown fixture killed it.

- [ ] **Step 5: Commit**

```bash
git add scripts/test-integration.sh
git commit -m "test: add scripts/test-integration.sh wrapper

Five-line shell wrapper around 'python3 -m pytest tests/integration/'.
Ensures local dev + CI invoke tests the same way. Extra args
forwarded (e.g. '-k smoke' or '--pdb')."
```

---

## Task 7: Add integration CI job

**Files:**
- Modify: `.github/workflows/ci.yml`

**Context:** Linux job running the harness on every push. Matrix: nvim stable + nightly. Install pytest + tmux before invoking the wrapper.

- [ ] **Step 1: Inspect current ci.yml**

Run:
```bash
cat .github/workflows/ci.yml
```

Note: existing jobs are `lint`, `test` (matrix), `startup` (matrix), `health`. The new `integration` job mirrors the test matrix.

- [ ] **Step 2: Append the job**

Add to the end of the `jobs:` section in `.github/workflows/ci.yml`:

```yaml
  integration:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        nvim: [stable, nightly]
    steps:
      - uses: actions/checkout@v4
      - name: Install tmux + pytest
        run: |
          sudo apt-get update
          sudo apt-get install -y tmux python3-pytest
          tmux -V
          python3 -m pytest --version
      - uses: rhysd/action-setup-vim@v1
        with:
          neovim: true
          version: ${{ matrix.nvim }}
      - name: Run integration harness
        run: bash scripts/test-integration.sh
```

- [ ] **Step 3: Validate YAML**

Run:
```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/ci.yml'))" && echo YAML_OK
```

Expected: `YAML_OK`.

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: add integration harness job (ubuntu, nvim stable+nightly)

Runs scripts/test-integration.sh (python3 -m pytest tests/integration/)
under both nvim channels. Uses apt python3-pytest (stable, no pip
install needed). Baseline test_smoke.py verifies harness works;
later plans add real regression specs (persistence, routing,
idle-notify, popup-detach)."
```

---

## Task 8: Push + verify green CI

**Files:** none (push-only task)

**Context:** End-to-end verification. Push, wait for CI, confirm integration job green.

- [ ] **Step 1: Push to main**

Run from the non-worktree clone:
```bash
cd /home/raul/projects/happy-nvim
git checkout main
git merge --ff-only feat/v1-implementation
git push git@github.com:raulfrk/happy-nvim.git main:main
```

Expected: `main -> main` advances several commits.

- [ ] **Step 2: Get the run id**

Run:
```bash
sleep 6
RUN_ID=$(gh api repos/raulfrk/happy-nvim/actions/runs --jq '.workflow_runs[0].id')
echo "$RUN_ID"
```

- [ ] **Step 3: Poll until complete**

Run:
```bash
while true; do
  s=$(gh api "repos/raulfrk/happy-nvim/actions/runs/$RUN_ID" --jq '"\(.status)|\(.conclusion)"')
  echo "$(date +%H:%M:%S) $s"
  case "$s" in completed*) break;; esac
  sleep 20
done
```

- [ ] **Step 4: Verify per-job status**

Run:
```bash
gh api "repos/raulfrk/happy-nvim/actions/runs/$RUN_ID/jobs" --jq '.jobs[] | "\(.name): \(.conclusion)"'
```

Expected every line ending in `success`, including:
```
integration (stable): success
integration (nightly): success
```

If integration fails, fetch logs:
```bash
TMPDIR=/tmp XDG_CACHE_HOME=/tmp gh run view "$RUN_ID" --log-failed -R raulfrk/happy-nvim | tail -80
```

Likely failure modes + fixes:
- `tmux < 3.2` on runner → bump `apt-get install` with a backport PPA, or adjust MIN_TMUX_MINOR in conftest.
- `pytest not found` → change `python3-pytest` → `pip install pytest` step.
- `fake_claude.py: Permission denied` → ensure `chmod +x` landed in the commit (re-run Task 2 Step 2).

Commit the fix, push, re-poll.

- [ ] **Step 5: Close the source todos**

In the main conversation (not inside the plan), run:
```
todo_complete 1.1   # tree-sitter CLI in migrate
todo_complete 4.1   # fake-claude stub
todo_complete 4.2   # test-integration entry point
```

Leave todos 4.3-4.7 open for the follow-up plan (real regression specs).

---

## Self-Review

**1. Spec coverage:**

| Source todo | Task(s) |
|---|---|
| #1.1 tree-sitter CLI | Task 1 |
| #4.1 fake-claude | Task 2 |
| #4.2 test-integration.sh harness | Tasks 3 (helpers), 4 (conftest), 5 (smoke test), 6 (wrapper), 7 (CI), 8 (verify) |

No gaps. Tasks 3-6 are natural subdivisions of #4.2 (pytest structure).

**2. Placeholder scan:** no TBDs, no "similar to Task N", no vague steps. Every code block complete.

**3. Type consistency:** helper fn names (`tmx`, `capture_pane`, `wait_for_pane`, `send_keys`) consistent between `helpers.py` and `test_smoke.py`. Fixture names (`tmux_socket`, `scratch_dir`) consistent between `conftest.py` and `test_smoke.py`. Env var names (`XDG_*_HOME`, `PATH`) standard.
