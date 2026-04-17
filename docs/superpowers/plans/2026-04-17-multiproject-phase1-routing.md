# Multi-Project Claude — Phase 1: Project-Aware Routing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `<leader>cc`, `<leader>cp`, and `<leader>cs/cf/ce` project-aware so every independent repo (or worktree) gets its own tmux Claude session keyed by project ID. Two projects open in parallel tmux panes talk to two different Claude instances without cross-contamination.

**Architecture:** New `lua/tmux/project.lua` owns project-ID resolution (`git rev-parse --show-toplevel` → slug, with worktree-path disambiguation) and session-name derivation (`cc:<slug>`). Existing `claude_popup.lua` grows from a single-session module into a per-project one by reading the session name from `project.session_name()` instead of a hardcoded `claude-happy`. Existing `claude.lua` pane logic keeps its per-nvim-window `@claude_pane_id` model — that layer is already project-correct because nvim windows are scoped to one cwd. The routing change is entirely in the session name used by `claude_popup`. `send.resolve_target()` needs no change: it already consults `claude_popup.pane_id()`, which now returns the current project's pane.

**Tech Stack:** Lua 5.1 (plenary busted), Python 3.11 (pytest), tmux 3.2+, Neovim 0.11+. No new dependencies.

---

## File Structure

```
lua/tmux/
├── project.lua          # NEW — project_id(), session_name(), current()
├── claude_popup.lua     # MODIFIED — session name from project.lua, not hardcoded
├── claude.lua           # unchanged
└── send.lua             # unchanged

tests/
├── tmux_project_spec.lua       # NEW — plenary tests for project-id derivation
└── integration/
    └── test_multiproject_routing.py  # NEW — 2 repos, 2 sessions, no crosstalk
```

`project.lua` is a pure function module (no side effects on require) so it can be unit-tested with mocked `vim.system`. `claude_popup.lua` thins: the only change is the session name lookup.

---

## Task 1: Build `lua/tmux/project.lua`

**Files:**
- Create: `lua/tmux/project.lua`
- Create: `tests/tmux_project_spec.lua`

**Context:** Resolve which "project" the current nvim buffer belongs to. Rules:

1. **Primary:** `git rev-parse --show-toplevel` from the buffer's directory → returns the git working tree root.
2. **Worktree disambiguation:** If inside a git worktree (not the primary checkout), append the worktree path leaf. Detected via `git rev-parse --git-common-dir` vs `git rev-parse --git-dir` — when they differ, we're in a worktree.
3. **Fallback (not a git repo):** use the absolute cwd.

Slug format: replace any `/` with `-`, strip other path-unfriendly chars to `-`, collapse repeats, strip leading/trailing `-`. Examples:

- `/home/raul/projects/happy-nvim` → `happy-nvim`
- `/home/raul/worktrees/happy-nvim/feat-v1` (worktree of happy-nvim) → `happy-nvim-wt-feat-v1`
- `/tmp/scratch` (not git) → `tmp-scratch`

Session name: `cc:<slug>`.

- [ ] **Step 1: Write the failing test**

Create `tests/tmux_project_spec.lua`:

```lua
-- tests/tmux_project_spec.lua
-- Unit tests for lua/tmux/project.lua. Uses monkey-patched vim.system so
-- no real git calls happen.

describe('tmux.project._slug', function()
  local project = require('tmux.project')

  it('keeps alphanumerics and hyphens unchanged', function()
    assert.are.equal('happy-nvim', project._slug('happy-nvim'))
  end)

  it('replaces slashes with hyphens', function()
    assert.are.equal('a-b-c', project._slug('a/b/c'))
  end)

  it('collapses runs of non-slug chars into one hyphen', function()
    assert.are.equal('a-b', project._slug('a /// b'))
  end)

  it('strips leading/trailing hyphens', function()
    assert.are.equal('x', project._slug('---x---'))
  end)
end)

describe('tmux.project._derive_id', function()
  local project = require('tmux.project')

  it('returns basename slug for primary git checkout', function()
    local id = project._derive_id({
      toplevel = '/home/raul/projects/happy-nvim',
      git_dir = '/home/raul/projects/happy-nvim/.git',
      common_dir = '/home/raul/projects/happy-nvim/.git',
    })
    assert.are.equal('happy-nvim', id)
  end)

  it('appends wt-<leaf> for a worktree', function()
    local id = project._derive_id({
      toplevel = '/home/raul/worktrees/happy-nvim/feat-v1',
      -- In a worktree, git_dir is .git/worktrees/<name> under the COMMON dir.
      git_dir = '/home/raul/projects/happy-nvim/.git/worktrees/feat-v1',
      common_dir = '/home/raul/projects/happy-nvim/.git',
    })
    assert.are.equal('happy-nvim-wt-feat-v1', id)
  end)

  it('falls back to cwd slug when not a git repo', function()
    local id = project._derive_id({
      toplevel = nil,
      git_dir = nil,
      common_dir = nil,
      cwd = '/tmp/scratch',
    })
    assert.are.equal('tmp-scratch', id)
  end)
end)

describe('tmux.project.session_name', function()
  local project = require('tmux.project')

  it('prefixes the id with "cc:"', function()
    local name = project.session_name('happy-nvim')
    assert.are.equal('cc:happy-nvim', name)
  end)
end)
```

- [ ] **Step 2: Run the failing test**

Run:
```bash
cd /home/raul/worktrees/happy-nvim/feat-v1-implementation
XDG_DATA_HOME="$PWD/.tests" XDG_CONFIG_HOME="$PWD/.tests/config" \
  XDG_CACHE_HOME="$PWD/.tests/cache" XDG_STATE_HOME="$PWD/.tests/state" \
  nvim --headless -u tests/minimal_init.lua \
  -c "PlenaryBustedFile tests/tmux_project_spec.lua" -c 'qa!' 2>&1 | tail -10
```

Expected: all 7 tests FAIL with `module 'tmux.project' not found`.

- [ ] **Step 3: Write the implementation**

Create `lua/tmux/project.lua`:

```lua
-- lua/tmux/project.lua — resolve the current nvim buffer's project identity.
--
-- Used by tmux/claude_popup.lua to pick a per-project tmux session so two
-- independent repos (or worktrees) get two distinct Claude conversations
-- instead of sharing one global 'claude-happy' session.
local M = {}

local function trim(s)
  return (s or ''):gsub('%s+$', '')
end

-- Replace non-slug characters with '-', collapse runs, strip ends.
function M._slug(s)
  s = s:gsub('[^%w%-]', '-')
  s = s:gsub('%-+', '-')
  s = s:gsub('^%-', ''):gsub('%-$', '')
  return s
end

-- Query git for the 3 paths we need. cwd is where we run from (defaults to
-- the buffer's directory). Returns a table w/ toplevel, git_dir, common_dir,
-- cwd; any missing field stays nil (indicates not-a-git-repo or error).
function M._probe(cwd)
  local function run(args)
    local res = vim.system(args, { text = true, cwd = cwd }):wait()
    if res.code ~= 0 then
      return nil
    end
    return trim(res.stdout)
  end
  local toplevel = run({ 'git', 'rev-parse', '--show-toplevel' })
  local git_dir = toplevel and run({ 'git', 'rev-parse', '--git-dir' }) or nil
  local common_dir = toplevel and run({ 'git', 'rev-parse', '--git-common-dir' }) or nil
  -- Normalize relative paths returned by older git: resolve against cwd.
  local function abs(p)
    if not p or p:sub(1, 1) == '/' then
      return p
    end
    return (cwd or vim.fn.getcwd()) .. '/' .. p
  end
  return {
    toplevel = toplevel,
    git_dir = abs(git_dir),
    common_dir = abs(common_dir),
    cwd = cwd or vim.fn.getcwd(),
  }
end

-- Pure function: derive a project id from probe data. Separated from _probe
-- so unit tests don't need to monkey-patch vim.system.
function M._derive_id(probe)
  if not probe.toplevel then
    return M._slug(probe.cwd or '')
  end
  local base = probe.toplevel:match('([^/]+)$') or probe.toplevel
  -- Worktree detection: git_dir under common_dir means we're in a worktree
  if probe.git_dir and probe.common_dir and probe.git_dir ~= probe.common_dir then
    local leaf = probe.git_dir:match('/worktrees/([^/]+)$')
    if leaf then
      return M._slug(base .. '-wt-' .. leaf)
    end
  end
  return M._slug(base)
end

function M.current()
  local cwd = vim.fn.expand('%:p:h')
  if cwd == '' then
    cwd = vim.fn.getcwd()
  end
  return M._derive_id(M._probe(cwd))
end

function M.session_name(id)
  id = id or M.current()
  return 'cc:' .. id
end

return M
```

- [ ] **Step 4: Run tests to verify all pass**

Same command as Step 2. Expected tail: `Success: 7  Failed : 0  Errors : 0`.

If `_slug` tests fail: double-check the character class escapes; `%w` is alphanumeric, not `%a`. If `_derive_id` worktree test fails: verify `probe.git_dir:match('/worktrees/([^/]+)$')` — matches the leaf after the literal `/worktrees/` segment.

- [ ] **Step 5: Stylua + commit**

```bash
export STYLUA=/tmp/npmcache/_npx/2d7ba7d0047acad9/node_modules/.bin/stylua
$STYLUA lua/tmux/project.lua tests/tmux_project_spec.lua
$STYLUA --check lua/tmux/project.lua tests/tmux_project_spec.lua && echo STYLUA_OK
git add lua/tmux/project.lua tests/tmux_project_spec.lua
git commit -m "feat(tmux/project): project-ID resolver + session-name builder

New lua/tmux/project.lua derives a stable project id from the
current buffer's directory:
- primary git checkout -> basename slug (e.g. 'happy-nvim')
- worktree -> append '-wt-<leaf>' (e.g. 'happy-nvim-wt-feat-v1')
- non-git -> cwd slug

session_name(id) -> 'cc:<id>'. Used in Task 2 to make <leader>cp
project-aware. Pure-function core (_derive_id) unit-tested with
synthetic probe data; no real git calls in the tests."
```

---

## Task 2: Make `lua/tmux/claude_popup.lua` project-aware

**Files:**
- Modify: `lua/tmux/claude_popup.lua`

**Context:** Replace the hardcoded `SESSION = 'claude-happy'` constant with a per-call lookup via `project.session_name()`. Every function (`exists`, `ensure`, `open`, `fresh`, `pane_id`) now takes the project into account implicitly — they call `project.session_name()` to get the current target session.

This keeps the module's public API unchanged. The integration test in Task 3 verifies two sessions exist simultaneously and receive independent input.

- [ ] **Step 1: Rewrite the module**

Replace the entire contents of `lua/tmux/claude_popup.lua` with:

```lua
-- lua/tmux/claude_popup.lua — per-project detached tmux session + popup attach.
--
-- Every independent repo (or worktree) keyed by tmux.project.session_name()
-- gets its own hidden 'cc:<slug>' tmux session running claude in that
-- project's cwd. <leader>cp from nvim inside project A attaches to cc:A;
-- from project B attaches to cc:B. No crosstalk.
local M = {}
local project = require('tmux.project')

local POPUP_W = '85%'
local POPUP_H = '85%'

local function sys(args)
  return vim.system(args, { text = true }):wait()
end

local function session()
  return project.session_name()
end

function M.exists()
  return sys({ 'tmux', 'has-session', '-t', session() }).code == 0
end

function M.ensure()
  if M.exists() then
    return true
  end
  local cwd = vim.fn.expand('%:p:h')
  if cwd == '' then
    cwd = vim.fn.getcwd()
  end
  local res = sys({ 'tmux', 'new-session', '-d', '-s', session(), '-c', cwd, 'claude' })
  if res.code ~= 0 then
    vim.notify(
      'failed to spawn ' .. session() .. ' session: ' .. (res.stderr or ''),
      vim.log.levels.ERROR
    )
    return false
  end
  return true
end

function M.open()
  if vim.env.TMUX == nil or vim.env.TMUX == '' then
    vim.notify('Claude popup requires $TMUX (run nvim inside tmux)', vim.log.levels.WARN)
    return
  end
  if not M.ensure() then
    return
  end
  -- -E closes the popup when inner command exits; user detaches via prefix+d
  sys({
    'tmux',
    'display-popup',
    '-E',
    '-w',
    POPUP_W,
    '-h',
    POPUP_H,
    'tmux attach -t ' .. session(),
  })
end

function M.fresh()
  if M.exists() then
    sys({ 'tmux', 'kill-session', '-t', session() })
  end
  M.open()
end

function M.pane_id()
  if not M.exists() then
    return nil
  end
  local res = sys({
    'tmux',
    'list-panes',
    '-t',
    session(),
    '-F',
    '#{pane_id}',
  })
  if res.code ~= 0 then
    return nil
  end
  local id = (res.stdout or ''):gsub('%s+$', '')
  if id == '' then
    return nil
  end
  return id
end

return M
```

- [ ] **Step 2: Run existing tests — make sure nothing else broke**

Run the full plenary suite:

```bash
XDG_DATA_HOME="$PWD/.tests" XDG_CONFIG_HOME="$PWD/.tests/config" \
  XDG_CACHE_HOME="$PWD/.tests/cache" XDG_STATE_HOME="$PWD/.tests/state" \
  nvim --headless -u tests/minimal_init.lua \
  -c "PlenaryBustedDirectory tests/ {minimal_init='tests/minimal_init.lua'}" \
  -c 'qa!' 2>&1 | tail -15
```

Expected: all tests still pass. tmux_send_spec's `resolve_target` tests don't invoke the real `claude_popup`; they stub it. No behavioral change expected.

- [ ] **Step 3: Stylua + commit**

```bash
$STYLUA lua/tmux/claude_popup.lua
$STYLUA --check lua/tmux/claude_popup.lua && echo STYLUA_OK
git add lua/tmux/claude_popup.lua
git commit -m "feat(tmux/claude_popup): per-project session via project.session_name

Session name now comes from tmux.project.session_name() at each call
site instead of the hardcoded 'claude-happy'. Every independent repo
(or worktree) keyed by its slug gets an isolated Claude conversation.
Public API unchanged — exists/ensure/open/fresh/pane_id all keep
their current signatures."
```

---

## Task 3: Integration test — 2 projects, 2 sessions, no crosstalk

**Files:**
- Create: `tests/integration/test_multiproject_routing.py`

**Context:** End-to-end proof the routing works. Sets up two fake "projects" (two git repos in temp dirs), derives each project's session name by running the Lua `project.session_name()` from nvim, opens a `claude_popup` session per project, sends a distinct payload to each, and asserts each session's capture contains only its own payload (not the other's).

We can't render the actual popup (no TTY under pytest), so we drive the module's functions headlessly:

- `nvim --headless -c "lua require('tmux.claude_popup').ensure()" -c 'qa!'` with cwd set to each project's dir.
- Session creation goes to the isolated `$HAPPY_TEST_SOCKET`, NOT the user's default tmux server. To force this, we prepend a wrapper script (`tmux_wrap.sh`) to `$PATH` that rewrites every `tmux ...` call to `tmux -L $HAPPY_TEST_SOCKET ...`. Simple + portable across nvim/tmux versions.

Once both sessions exist, we directly `tmux send-keys` into each and check `capture-pane` on each. fake-claude (already on PATH from the integration harness) produces `ACK:<input>` so we have a deterministic string to match.

- [ ] **Step 1: Write the test**

Create `tests/integration/test_multiproject_routing.py`:

```python
"""Integration: two project dirs → two isolated Claude sessions.

Verifies lua/tmux/project.session_name() + claude_popup.ensure() produce
two distinct tmux sessions (one per project) and sends to one do not
appear in the other's capture-pane.
"""
from __future__ import annotations

import os
import subprocess
import textwrap
from pathlib import Path

import pytest

from .helpers import capture_pane, send_keys, tmx, wait_for_pane

REPO_ROOT = Path(__file__).resolve().parents[2]


def _make_project(parent: Path, name: str) -> Path:
    """Create a git repo at parent/name; return its path."""
    proj = parent / name
    proj.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        ["git", "init", "-q", "-b", "main", str(proj)],
        check=True,
        capture_output=True,
    )
    (proj / "README.md").write_text(f"# {name}\n")
    subprocess.run(
        ["git", "-C", str(proj), "add", "README.md"],
        check=True,
        capture_output=True,
    )
    env = os.environ | {
        "GIT_AUTHOR_NAME": "test",
        "GIT_AUTHOR_EMAIL": "t@t",
        "GIT_COMMITTER_NAME": "test",
        "GIT_COMMITTER_EMAIL": "t@t",
    }
    subprocess.run(
        ["git", "-C", str(proj), "commit", "-q", "-m", "init"],
        check=True,
        capture_output=True,
        env=env,
    )
    return proj


def _make_tmux_wrapper(bin_dir: Path, socket: str) -> None:
    """Put a `tmux` shim on PATH that forces all calls onto our socket.

    Nvim's claude_popup.lua calls plain `tmux ...`; we want those calls to
    target the isolated test server, not the user's default. The shim just
    prepends `-L <socket>` and delegates to the real binary.
    """
    real_tmux = subprocess.check_output(["command", "-v", "tmux"], shell=False, text=True).strip()
    if not real_tmux:
        real_tmux = "/usr/bin/tmux"
    wrapper = bin_dir / "tmux"
    wrapper.write_text(textwrap.dedent(f"""\
        #!/usr/bin/env bash
        exec {real_tmux} -L {socket} "$@"
    """))
    wrapper.chmod(0o755)


def _session_name_for(project_dir: Path) -> str:
    """Call the Lua project.session_name() from headless nvim in the dir."""
    result = subprocess.run(
        [
            "nvim",
            "--headless",
            "--clean",
            "-c",
            f"lua vim.cmd('cd {project_dir}')",
            "-c",
            f"lua vim.opt.rtp:prepend('{REPO_ROOT}')",
            "-c",
            "lua io.stdout:write(require('tmux.project').session_name())",
            "-c",
            "qa!",
        ],
        check=True,
        text=True,
        capture_output=True,
    )
    return result.stdout.strip()


def _ensure_session(project_dir: Path, bin_dir: Path) -> None:
    """Headless nvim in project_dir: require claude_popup and call ensure()."""
    env = os.environ | {
        # Force TMUX so claude_popup.open's guard would pass; ensure() itself
        # doesn't check TMUX, but we keep the env clean for future changes.
        "TMUX": "/tmp/fake,1,0",
        "PATH": f"{bin_dir}:{os.environ['PATH']}",
    }
    subprocess.run(
        [
            "nvim",
            "--headless",
            "--clean",
            "-c",
            f"lua vim.cmd('cd {project_dir}')",
            "-c",
            f"lua vim.opt.rtp:prepend('{REPO_ROOT}')",
            "-c",
            "lua require('tmux.claude_popup').ensure()",
            "-c",
            "qa!",
        ],
        check=True,
        text=True,
        capture_output=True,
        env=env,
    )


def test_two_projects_get_two_sessions(tmux_socket: str, tmp_path: Path):
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    _make_tmux_wrapper(bin_dir, tmux_socket)

    proj_a = _make_project(tmp_path / "repos", "proj-a")
    proj_b = _make_project(tmp_path / "repos", "proj-b")

    # Names should differ (different project roots)
    name_a = _session_name_for(proj_a)
    name_b = _session_name_for(proj_b)
    assert name_a == "cc:proj-a"
    assert name_b == "cc:proj-b"
    assert name_a != name_b

    try:
        # Spawn both sessions via the real module (exercises claude_popup.ensure)
        _ensure_session(proj_a, bin_dir)
        _ensure_session(proj_b, bin_dir)

        # Both sessions exist
        assert subprocess.run(
            ["tmux", "-L", tmux_socket, "has-session", "-t", name_a],
            check=False,
        ).returncode == 0
        assert subprocess.run(
            ["tmux", "-L", tmux_socket, "has-session", "-t", name_b],
            check=False,
        ).returncode == 0

        # Send distinct payloads
        send_keys(tmux_socket, name_a, "hello-A", "Enter")
        send_keys(tmux_socket, name_b, "hello-B", "Enter")

        # Each session got its own ACK; neither got the other's
        wait_for_pane(tmux_socket, name_a, r"ACK:hello-A", timeout=5)
        wait_for_pane(tmux_socket, name_b, r"ACK:hello-B", timeout=5)
        out_a = capture_pane(tmux_socket, name_a)
        out_b = capture_pane(tmux_socket, name_b)
        assert "hello-B" not in out_a, f"proj-a session saw proj-b's input:\n{out_a}"
        assert "hello-A" not in out_b, f"proj-b session saw proj-a's input:\n{out_b}"
    finally:
        for s in (name_a, name_b):
            subprocess.run(
                ["tmux", "-L", tmux_socket, "kill-session", "-t", s],
                check=False,
                capture_output=True,
            )
```

- [ ] **Step 2: Run the test locally**

Run:
```bash
cd /home/raul/worktrees/happy-nvim/feat-v1-implementation
python3 -m pytest tests/integration/test_multiproject_routing.py -v
```

Expected tail:
```
tests/integration/test_multiproject_routing.py::test_two_projects_get_two_sessions PASSED

======== 1 passed in X.XXs ========
```

Likely failure modes + fixes:
- `_session_name_for` returns empty stdout: the `-c "lua io.stdout:write(...)"` is redirected into nvim's normal message system, not real stdout. If that happens, change the command sequence to `-c "lua vim.fn.writefile({require('tmux.project').session_name()}, '/tmp/sname')"` and read the file.
- `ensure()` fails because `claude` binary isn't the fake one: the integration harness's `_env` autouse fixture already prepends fake-claude as `claude` on `$PATH`. The `_ensure_session` helper inherits `os.environ`, so that PATH is in scope when nvim spawns tmux-under-wrapper which spawns `claude`.
- Session names collide: check `_derive_id` slug chars (the test uses simple `proj-a` / `proj-b` that need no slugging).

- [ ] **Step 3: Run assess.sh to confirm every layer still green**

```bash
bash scripts/assess.sh
```

Expected: ALL LAYERS PASS (new routing test adds to the integration layer count).

- [ ] **Step 4: Commit**

```bash
git add tests/integration/test_multiproject_routing.py
git commit -m "test(integration): two projects get isolated Claude sessions

Creates two scratch git repos, calls lua tmux.project.session_name()
from headless nvim in each, then invokes claude_popup.ensure() via a
PATH-shimmed tmux (so sessions land on the isolated test socket).
Sends distinct payloads into each; asserts neither session's capture
contains the other's payload. Guards against cross-project send
regressions — the destructive bug this whole refactor prevents."
```

---

## Task 4: Push + verify green CI

**Files:** none (push-only).

- [ ] **Step 1: Fast-forward main + push**

```bash
cd /home/raul/projects/happy-nvim
git checkout main
git merge --ff-only feat/v1-implementation
git push git@github.com:raulfrk/happy-nvim.git main:main
```

Expected: `main -> main` advances 3 commits.

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

Expected all `success`, especially `integration (stable)` and `assess (stable)` which run the new multiproject test.

If integration fails, fetch logs:
```bash
TMPDIR=/tmp XDG_CACHE_HOME=/tmp gh run view "$RUN_ID" --log-failed -R raulfrk/happy-nvim | tail -80
```

Common CI-specific issues:
- `git init -b main` needs git ≥ 2.28; ubuntu-latest is fine.
- Wrapper script permission: `chmod 0o755` is set in Python, not `install`; runners keep those perms.
- session existence check: if `has-session` returns nonzero on CI but the `send-keys` subsequently works, the race is fixed by the wait_for_pane timeout.

- [ ] **Step 4: Close source todos**

In the main conversation:
```
todo_complete 3.1 3.2
```

Note: 3.11 (full 3-project concurrency test) stays open — this phase covers 2-project routing; 3.11 in its full scope also asserts idle notifications which require Phase 3.

---

## Self-Review

**1. Spec coverage:**

| Todo | Task |
|---|---|
| #3.1 project-ID resolver + session-name | Task 1 (lua/tmux/project.lua + 7 unit tests) |
| #3.2 project-aware cc/cp/cs/cf/ce | Task 2 (claude_popup reads session from project.lua); send + pane unchanged (already project-correct via @claude_pane_id) |
| #3.11 (partial — 2-project routing assertion) | Task 3 (test_multiproject_routing.py) |

The `cc/cs/cf/ce` mappings touch `claude.lua`'s per-window pane, which is already project-correct: `@claude_pane_id` is a tmux window-local option, and nvim windows are scoped to one cwd. So Task 2 only needs to modify `claude_popup.lua`.

**2. Placeholder scan:** no TBDs, no "similar to Task N", no vague steps. Every code block complete.

**3. Type consistency:**
- `project._slug`, `project._derive_id`, `project._probe`, `project.current`, `project.session_name` — names match between `lua/tmux/project.lua` (Task 1 Step 3), `tests/tmux_project_spec.lua` (Task 1 Step 1), and the `session()` local in `claude_popup.lua` (Task 2 Step 1).
- Probe table keys (`toplevel`, `git_dir`, `common_dir`, `cwd`) match between `_probe` return value and `_derive_id` argument table (used in tests).
- pytest fixtures `tmux_socket`, `tmp_path` — `tmux_socket` from existing `conftest.py`, `tmp_path` is a pytest builtin.
