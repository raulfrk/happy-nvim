# Assess Button Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver the "is the config broken?" one-button workflow: plenary keymap+command inventory spec, pytest integration test for the OSC 52 TextYankPost hook (real nvim inside tmux), and `scripts/assess.sh` aggregator that runs lint + unit tests + integration tests + checkhealth and prints a pass/fail table.

**Architecture:** Three independent deliverables sharing the existing test harness. Task 1 is a new plenary spec under `tests/` — runs in the existing `test` CI job, zero new infra. Task 2 is a new pytest file under `tests/integration/` — runs in the existing `integration` CI job. Task 3 is a new shell script plus a new CI `assess` job that calls it; the job is additive (leaves existing jobs alone) and becomes the canonical entry point. Each task commits independently; no inter-task dependencies.

**Tech Stack:** Lua 5.1 (plenary busted), Python 3.11 (pytest + stdlib), bash 5, tmux 3.2+, Neovim 0.11+, GitHub Actions ubuntu-latest.

---

## File Structure

```
tests/
├── keymap_spec.lua                  # new — plenary spec: every <leader>* + user cmd registered
└── integration/
    └── test_clipboard_osc52.py      # new — real nvim in tmux, asserts OSC 52 escape emitted on yank

scripts/
└── assess.sh                        # new — one-button "is the config broken?" aggregator

.github/workflows/
└── ci.yml                           # modified — append `assess` job calling scripts/assess.sh
```

Each file owns one responsibility. `keymap_spec.lua` is a pure-lua headless assertion over the keymap registry. `test_clipboard_osc52.py` is a single pytest scenario; it lives alongside the other integration tests so `conftest.py` fixtures apply automatically. `scripts/assess.sh` is the aggregator a developer (or Claude) runs after edits to see one pass/fail verdict.

---

## Task 1: Add `tests/keymap_spec.lua`

**Files:**
- Create: `tests/keymap_spec.lua`

**Context:** Every `<leader>*` keymap and user command is defined across many files (`lua/plugins/*.lua`, `lua/remote/*.lua`, `lua/tmux/*.lua`). If a refactor accidentally removes a `vim.keymap.set(...)` call or a `nvim_create_user_command`, the only way to catch it today is running nvim by hand. This spec catalogs every expected entry and asserts it's live after plugins finish loading. Fails with a missing-entry list, so contributors get a precise diff.

Existing test runner: `nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedDirectory tests/" -c 'qa!'` (see `.github/workflows/ci.yml` `test` job). `minimal_init.lua` does NOT load the user's plugins, so the spec must bootstrap lazy.nvim + the config root itself.

- [ ] **Step 1: Inspect existing namespace table and keymap registrations**

Run these commands to confirm the expected inventory matches what's in the code. You'll be writing down what you see:

```bash
cd /home/raul/worktrees/happy-nvim/feat-v1-implementation
grep -n "'<leader>" lua/plugins/whichkey.lua
grep -rn "'<leader>[a-zA-Z?]" lua/plugins lua/tmux lua/remote | awk -F"'" '{print $2}' | sort -u
grep -rn "nvim_create_user_command" lua/ | grep -oE "'[A-Z][a-zA-Z]+'" | sort -u
```

Expected inventory (from present code state, commit `9fe84ce`):

| Group | Child keys |
|---|---|
| `<leader>f` (find) | `ff`, `fg`, `fb`, `fh` |
| `<leader>g` (git) | `gs`, `gb`, `gc`, `gd` |
| `<leader>l` (LSP) | `ld`, `lD`, `li`, `lr`, `ln`, `la`, `lh`, `lk`, `lf` |
| `<leader>d` (diagnostics) | `dn`, `dp`, `dl` |
| `<leader>h` (harpoon) | `ha`, `h1`, `h2`, `h3`, `h4` |
| `<leader>s` (ssh/remote) | `ss`, `sd`, `sD`, `sB`, `sf`, `sg`, `sO` |
| `<leader>c` (Claude) | `cc`, `cf`, `cs`, `ce` |
| `<leader>t` (tmux) | `tg`, `tt`, `tb` |
| `<leader>?` (coach) | `?`, `??` |

User commands:
- `HappyHostsPrune`

If the commands above reveal different entries (e.g. a keymap got renamed), update the `EXPECTED` tables in Step 2 to match the code that's actually there.

- [ ] **Step 2: Write the spec**

Create `tests/keymap_spec.lua`:

```lua
-- tests/keymap_spec.lua
-- Asserts every <leader>* keymap and user command declared by the config is
-- actually registered after VimEnter fires. Catches accidental removal/
-- rename during refactors. Runs in the existing `test` CI job via
-- PlenaryBustedDirectory.

local EXPECTED_LEADER_KEYS = {
  -- find / files
  ['<leader>ff'] = 'n',
  ['<leader>fg'] = 'n',
  ['<leader>fb'] = 'n',
  ['<leader>fh'] = 'n',
  -- git
  ['<leader>gs'] = 'n',
  ['<leader>gb'] = 'n',
  ['<leader>gc'] = 'n',
  ['<leader>gd'] = 'n',
  -- LSP
  ['<leader>ld'] = 'n',
  ['<leader>lD'] = 'n',
  ['<leader>li'] = 'n',
  ['<leader>lr'] = 'n',
  ['<leader>ln'] = 'n',
  ['<leader>la'] = 'n',
  ['<leader>lh'] = 'n',
  ['<leader>lk'] = 'n',
  ['<leader>lf'] = 'n',
  -- diagnostics
  ['<leader>dn'] = 'n',
  ['<leader>dp'] = 'n',
  ['<leader>dl'] = 'n',
  -- harpoon
  ['<leader>ha'] = 'n',
  ['<leader>h1'] = 'n',
  ['<leader>h2'] = 'n',
  ['<leader>h3'] = 'n',
  ['<leader>h4'] = 'n',
  -- ssh / remote
  ['<leader>ss'] = 'n',
  ['<leader>sd'] = 'n',
  ['<leader>sD'] = 'n',
  ['<leader>sB'] = 'n',
  ['<leader>sf'] = 'n',
  ['<leader>sg'] = 'n',
  ['<leader>sO'] = 'n',
  -- Claude (tmux)
  ['<leader>cc'] = 'n',
  ['<leader>cf'] = 'n',
  ['<leader>cs'] = 'v',
  ['<leader>ce'] = 'n',
  -- tmux popups
  ['<leader>tg'] = 'n',
  ['<leader>tt'] = 'n',
  ['<leader>tb'] = 'n',
  -- coach
  ['<leader>?'] = 'n',
  ['<leader>??'] = 'n',
}

local EXPECTED_USER_CMDS = {
  'HappyHostsPrune',
}

-- Translate <leader> to the actual leader character before looking up in the
-- keymap registry, because vim.api.nvim_get_keymap returns resolved LHS.
local function resolve_leader(lhs)
  local leader = vim.g.mapleader or '\\'
  return (lhs:gsub('<[Ll]eader>', leader))
end

local function has_mapping(mode, lhs)
  local resolved = resolve_leader(lhs)
  for _, m in ipairs(vim.api.nvim_get_keymap(mode)) do
    if m.lhs == resolved then
      return true
    end
  end
  return false
end

local function has_user_cmd(name)
  return vim.api.nvim_get_commands({})[name] ~= nil
end

describe('happy-nvim keymap + user-command inventory', function()
  it('registers every expected <leader>* keymap', function()
    local missing = {}
    for lhs, mode in pairs(EXPECTED_LEADER_KEYS) do
      if not has_mapping(mode, lhs) then
        table.insert(missing, string.format('%s (%s)', lhs, mode))
      end
    end
    assert.are.equal(0, #missing, 'missing keymaps: ' .. table.concat(missing, ', '))
  end)

  it('registers every expected user command', function()
    local missing = {}
    for _, name in ipairs(EXPECTED_USER_CMDS) do
      if not has_user_cmd(name) then
        table.insert(missing, name)
      end
    end
    assert.are.equal(0, #missing, 'missing user commands: ' .. table.concat(missing, ', '))
  end)
end)
```

- [ ] **Step 3: Extend `tests/minimal_init.lua` so the spec can see plugin keymaps**

The existing minimal init bootstraps plenary only. The spec needs lazy.nvim loaded plus the happy module setup autocmd fired. Look at the current file first:

```bash
cat tests/minimal_init.lua
```

Expected current content starts with `local plugin_root = vim.fn.stdpath('data') ...`.

Append these lines to the END of `tests/minimal_init.lua` (do not touch the plenary bootstrap that's already there):

```lua

-- For keymap_spec.lua: load the real user config so registrations happen.
-- Guard with HAPPY_NVIM_LOAD_CONFIG so other specs stay minimal.
if vim.env.HAPPY_NVIM_LOAD_CONFIG == '1' then
  -- Point XDG_CONFIG_HOME at the repo root; nvim will pick up init.lua.
  -- CI + local callers must export HAPPY_NVIM_LOAD_CONFIG=1 and set
  -- XDG_CONFIG_HOME to a scratch dir that contains the repo as ./nvim.
  dofile(vim.fn.getcwd() .. '/init.lua')
  vim.api.nvim_exec_autocmds('VimEnter', {})
end
```

- [ ] **Step 4: Verify the spec fails as expected without the env flag, passes with it**

Without flag (should skip plugin loading, so every mapping is missing — test fails loudly):

```bash
cd /home/raul/worktrees/happy-nvim/feat-v1-implementation
XDG_DATA_HOME="$PWD/.tests" XDG_CONFIG_HOME="$PWD/.tests/config" \
  XDG_CACHE_HOME="$PWD/.tests/cache" XDG_STATE_HOME="$PWD/.tests/state" \
  nvim --headless -u tests/minimal_init.lua \
  -c "PlenaryBustedFile tests/keymap_spec.lua" -c 'qa!' 2>&1 | tail -20
```

Expected: one `Failed : 1` line for "registers every expected <leader>* keymap" w/ the missing list.

With flag + plugins synced:

```bash
# Ensure lazy has synced once into the redirected XDG dir
XDG_DATA_HOME="$PWD/.tests" XDG_CONFIG_HOME="$PWD/.tests/config" \
  XDG_CACHE_HOME="$PWD/.tests/cache" XDG_STATE_HOME="$PWD/.tests/state" \
  nvim --headless -c 'Lazy! sync' -c 'qa!' 2>&1 | tail -3

# Now run the spec with config loading enabled
HAPPY_NVIM_LOAD_CONFIG=1 \
  XDG_DATA_HOME="$PWD/.tests" XDG_CONFIG_HOME="$PWD/.tests/config" \
  XDG_CACHE_HOME="$PWD/.tests/cache" XDG_STATE_HOME="$PWD/.tests/state" \
  nvim --headless -u tests/minimal_init.lua \
  -c "PlenaryBustedFile tests/keymap_spec.lua" -c 'qa!' 2>&1 | tail -10
```

Expected tail ends with `Success: 2  Failed : 0  Errors : 0`.

- [ ] **Step 5: Wire `HAPPY_NVIM_LOAD_CONFIG=1` into the existing `test` CI job**

Look at `.github/workflows/ci.yml`. Find the `test` job's "Run plenary tests" step. Current form:

```yaml
      - name: Run plenary tests
        run: |
          set +e
          nvim --headless -u tests/minimal_init.lua \
            -c "PlenaryBustedDirectory tests/ {minimal_init='tests/minimal_init.lua'}" \
            2>&1 | tee test.log
          set -e
          sed -r 's/\x1b\[[0-9;]*m//g' test.log > test.clean.log
          grep -q 'Success:' test.clean.log
          if grep -qE 'Failed *: *[1-9]|Errors *: *[1-9]' test.clean.log; then
            echo 'Test failure/error detected'
            grep -E 'Failed|Errors' test.clean.log
            exit 1
          fi
```

Replace that run block with the version below. The diff: (1) run `Lazy! sync` once before the tests so plugins are on disk, (2) export `HAPPY_NVIM_LOAD_CONFIG=1` for the test invocation only:

```yaml
      - name: Run plenary tests
        env:
          HAPPY_NVIM_LOAD_CONFIG: '1'
        run: |
          nvim --headless -c 'Lazy! sync' -c 'qa!' 2>&1 | tail -5 || true
          set +e
          nvim --headless -u tests/minimal_init.lua \
            -c "PlenaryBustedDirectory tests/ {minimal_init='tests/minimal_init.lua'}" \
            2>&1 | tee test.log
          set -e
          sed -r 's/\x1b\[[0-9;]*m//g' test.log > test.clean.log
          grep -q 'Success:' test.clean.log
          if grep -qE 'Failed *: *[1-9]|Errors *: *[1-9]' test.clean.log; then
            echo 'Test failure/error detected'
            grep -E 'Failed|Errors' test.clean.log
            exit 1
          fi
```

- [ ] **Step 6: Commit**

```bash
cd /home/raul/worktrees/happy-nvim/feat-v1-implementation
git add tests/keymap_spec.lua tests/minimal_init.lua .github/workflows/ci.yml
git commit -m "test: keymap+user-cmd inventory spec

New plenary spec catalogs every <leader>* keymap and user command
the config is expected to register, then asserts each is present
after config load. Minimal init grew an opt-in path (guarded by
HAPPY_NVIM_LOAD_CONFIG=1) so the existing lightweight specs still
run without plugins. CI's test job exports the flag + runs Lazy sync
once before tests so plugins are on disk. Closes todo 5.1."
```

---

## Task 2: Add `tests/integration/test_clipboard_osc52.py`

**Files:**
- Create: `tests/integration/test_clipboard_osc52.py`

**Context:** `lua/clipboard/init.lua` installs a `TextYankPost` autocmd that emits an OSC 52 escape sequence (`\x1b]52;c;<base64>\x07`) to stdout when `$SSH_TTY` or `$TMUX` is set. Pure-lua test (`tests/clipboard_spec.lua`) covers `encode_osc52` + the `should_emit` guard. It does NOT verify the autocmd actually fires and writes to the terminal. This integration test spawns real nvim inside tmux, yanks text, captures pane bytes, and asserts the escape prefix appears — catching any regression in the autocmd wiring or the `io.stdout:write(seq)` path.

Harness: pytest + `conftest.py` fixtures (`tmux_socket`, `_env`) already installed from the previous plan. `fake_claude.py` is irrelevant here; we're running `nvim`, not `claude`.

`tmux capture-pane -p` by default strips escape sequences (it renders the visible text). To get the raw bytes, use `capture-pane -p -e` which keeps ANSI/OSC escapes. This is the key mechanic for this test.

- [ ] **Step 1: Write the test**

Create `tests/integration/test_clipboard_osc52.py`:

```python
"""Integration test: TextYankPost fires OSC 52 escape when SSH_TTY or TMUX set.

Runs real nvim inside a tmux pane, opens a buffer with known text, yanks it,
then reads the raw pane bytes (including escape sequences) via
`tmux capture-pane -p -e`. Asserts the OSC 52 introducer (ESC]52;c;) appears
in the captured bytes.

Why not a unit test: clipboard_spec.lua covers encode_osc52 + should_emit
pure logic. This test guards the autocmd wiring — the actual
`io.stdout:write(seq)` call happens only inside the TextYankPost callback,
and only the real event loop can trigger it.
"""
from __future__ import annotations

import os
import subprocess
import textwrap
from pathlib import Path

import pytest

from .helpers import send_keys, tmx, wait_for_pane

REPO_ROOT = Path(__file__).resolve().parents[2]
OSC52_PREFIX = "\x1b]52;c;"


def _write_scratch_config(scratch: Path) -> Path:
    """Create a minimal init.lua that only loads the clipboard module.

    We deliberately do NOT load lazy.nvim / plugins / autocmds from the full
    config — those take 5+ seconds to sync on a cold runner and aren't needed
    to exercise the clipboard hook.
    """
    nvim_cfg = scratch / "nvim"
    nvim_cfg.mkdir(parents=True, exist_ok=True)
    # Symlink the real clipboard module so the test exercises the actual code
    lua_dir = nvim_cfg / "lua" / "clipboard"
    lua_dir.mkdir(parents=True, exist_ok=True)
    (lua_dir / "init.lua").symlink_to(REPO_ROOT / "lua" / "clipboard" / "init.lua")
    init_lua = nvim_cfg / "init.lua"
    init_lua.write_text(textwrap.dedent("""
        -- Minimal init: just enough to exercise the OSC 52 hook.
        vim.g.mapleader = ' '
        require('clipboard').setup()
    """).lstrip())
    return nvim_cfg


@pytest.fixture
def scratch_nvim_config(scratch_dir: Path) -> Path:
    """Per-test scratch config symlinking in only the clipboard module."""
    cfg = _write_scratch_config(scratch_dir)
    return cfg


def test_textyankpost_emits_osc52(tmux_socket: str, scratch_nvim_config: Path):
    session = "osc52"
    env_overrides = {
        # should_emit() guards on these; either is sufficient
        "TMUX": os.environ.get("TMUX", "/tmp/fake-tmux,1,0"),
        "XDG_CONFIG_HOME": str(scratch_nvim_config.parent),
    }
    env_str = " ".join(f"{k}={v}" for k, v in env_overrides.items())
    try:
        # Start nvim in a tmux pane with a scratch buffer containing "hello"
        tmx(
            tmux_socket,
            "new-session",
            "-d",
            "-s",
            session,
            "-x",
            "120",
            "-y",
            "40",
            f"{env_str} nvim --clean -u {scratch_nvim_config}/init.lua "
            f"-c 'put =\"hello\" | normal! gg'",
        )
        # Wait for nvim to render "hello" in the visible pane
        wait_for_pane(tmux_socket, session, r"hello", timeout=5)
        # Yank the whole line
        send_keys(tmux_socket, session, "V", "y")
        # Give the autocmd a moment to flush io.stdout
        import time
        time.sleep(0.2)
        # Capture w/ escapes (-e keeps ANSI/OSC bytes)
        raw = subprocess.run(
            ["tmux", "-L", tmux_socket, "capture-pane", "-p", "-e", "-t", session],
            check=True,
            text=True,
            capture_output=True,
        ).stdout
        assert OSC52_PREFIX in raw, (
            f"OSC 52 prefix {OSC52_PREFIX!r} not found in captured pane.\n"
            f"--- raw capture (first 500 chars) ---\n{raw[:500]}\n--- end ---"
        )
    finally:
        tmx(tmux_socket, "kill-session", "-t", session, check=False)
```

- [ ] **Step 2: Run the test locally**

Run from repo root:

```bash
cd /home/raul/worktrees/happy-nvim/feat-v1-implementation
python3 -m pytest tests/integration/test_clipboard_osc52.py -v
```

Expected tail:
```
tests/integration/test_clipboard_osc52.py::test_textyankpost_emits_osc52 PASSED

======== 1 passed in X.XXs ========
```

If the test fails with `OSC 52 prefix ... not found`: open a debug nvim manually (`nvim --clean -u <scratch_path>/init.lua -c 'put ="hello"'`), `yy`, and run `:messages` — the clipboard module may have errored on require. Fix the cause (likely `lua/clipboard/init.lua` changed shape since the plan was written).

- [ ] **Step 3: Commit**

```bash
git add tests/integration/test_clipboard_osc52.py
git commit -m "test(integration): OSC 52 TextYankPost emits escape sequence

Real nvim in tmux, yank triggers autocmd, assert ESC]52;c; prefix
appears in raw pane capture. Guards the io.stdout:write path that
pure-lua unit tests can't reach. Closes todo 5.6."
```

---

## Task 3: Add `scripts/assess.sh` and CI `assess` job

**Files:**
- Create: `scripts/assess.sh`
- Modify: `.github/workflows/ci.yml`

**Context:** Contributors (and Claude) want one button: "is the config broken?". `assess.sh` runs every verification layer in order, times each, prints a pass/fail row per layer, and exits nonzero if any failed. The script is additive — it does not replace the existing granular CI jobs (consolidation can happen later in todo 5.13 once the aggregator is battle-tested).

Layers in order of cost (cheap first so contributors get fast-fail feedback locally):
1. `bash -n` every `scripts/*.sh` — 1 second, catches shell syntax errors.
2. `python3 -c "import ast; ast.parse(...)"` every `*.py` in `scripts/` + `tests/integration/` — 1 second.
3. `nvim --headless -c 'lua vim.cmd("qa!")' ` bootstrap check — 2 seconds, catches init.lua errors.
4. Plenary busted directory — 10-30 seconds, unit tests including the new keymap spec.
5. `pytest tests/integration/` — 10-30 seconds, integration tests including OSC 52.
6. `nvim --headless -c 'checkhealth happy-nvim' -c 'qa!'` — 5 seconds, verifies probes pass.

`scripts/test-integration.sh` already exists and wraps step 5 — assess.sh calls it rather than duplicating the invocation.

- [ ] **Step 1: Write the script**

Create `scripts/assess.sh`:

```bash
#!/usr/bin/env bash
# scripts/assess.sh — "is happy-nvim broken?" aggregator.
#
# Runs every verification layer in order (cheap first), prints a pass/fail
# table + total time, exits nonzero on any failure.
#
# Layers:
#   1. shell syntax       (bash -n scripts/*.sh)
#   2. python syntax      (ast.parse tests/integration/*.py + scripts/*.py)
#   3. init.lua bootstrap (nvim --headless -c qa!)
#   4. plenary unit+smoke (tests/*_spec.lua)
#   5. pytest integration (tests/integration/)
#   6. :checkhealth       (happy-nvim probe)
#
# Every layer runs even if an earlier one fails, so the final table shows
# the complete picture. Exit code is nonzero iff any layer failed.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

declare -A LAYER_STATUS
declare -A LAYER_DURATION
declare -a LAYER_ORDER

run_layer() {
  local name="$1"
  shift
  LAYER_ORDER+=( "$name" )
  echo
  echo "=== $name ==="
  local start
  start=$(date +%s)
  if "$@"; then
    LAYER_STATUS[$name]=PASS
  else
    LAYER_STATUS[$name]=FAIL
  fi
  local end
  end=$(date +%s)
  LAYER_DURATION[$name]=$(( end - start ))
  echo "=== $name: ${LAYER_STATUS[$name]} (${LAYER_DURATION[$name]}s) ==="
}

# Layer 1: shell syntax
layer_shell_syntax() {
  local rc=0
  while IFS= read -r -d '' f; do
    bash -n "$f" || rc=1
  done < <(find scripts tests -name '*.sh' -print0)
  return $rc
}

# Layer 2: python syntax
layer_python_syntax() {
  local rc=0
  while IFS= read -r -d '' f; do
    python3 -c "import ast, sys; ast.parse(open(sys.argv[1]).read())" "$f" || rc=1
  done < <(find scripts tests -name '*.py' -print0)
  return $rc
}

# Layer 3: init.lua bootstrap
layer_init_bootstrap() {
  local tmp
  tmp=$(mktemp -d -t happy-assess.XXXXXX)
  trap "rm -rf '$tmp'" RETURN
  XDG_DATA_HOME="$tmp/data" XDG_CONFIG_HOME="$tmp/cfg" \
    XDG_CACHE_HOME="$tmp/cache" XDG_STATE_HOME="$tmp/state" \
    nvim --headless -c 'qa!' 2>&1 | tee "$tmp/startup.log"
  ! grep -Eiq 'E[0-9]+:' "$tmp/startup.log"
}

# Layer 4: plenary unit+smoke
layer_plenary() {
  local tmp
  tmp=$(mktemp -d -t happy-assess-plenary.XXXXXX)
  trap "rm -rf '$tmp'" RETURN
  XDG_DATA_HOME="$tmp/data" XDG_CONFIG_HOME="$tmp/cfg" \
    XDG_CACHE_HOME="$tmp/cache" XDG_STATE_HOME="$tmp/state" \
    nvim --headless -c 'Lazy! sync' -c 'qa!' 2>&1 | tail -3 || true
  HAPPY_NVIM_LOAD_CONFIG=1 \
    XDG_DATA_HOME="$tmp/data" XDG_CONFIG_HOME="$tmp/cfg" \
    XDG_CACHE_HOME="$tmp/cache" XDG_STATE_HOME="$tmp/state" \
    nvim --headless -u tests/minimal_init.lua \
      -c "PlenaryBustedDirectory tests/ {minimal_init='tests/minimal_init.lua'}" \
      2>&1 | sed -r 's/\x1b\[[0-9;]*m//g' | tee "$tmp/plenary.log"
  grep -q 'Success:' "$tmp/plenary.log" || return 1
  ! grep -qE 'Failed *: *[1-9]|Errors *: *[1-9]' "$tmp/plenary.log"
}

# Layer 5: pytest integration (delegates to existing wrapper)
layer_integration() {
  bash scripts/test-integration.sh
}

# Layer 6: :checkhealth
layer_checkhealth() {
  local tmp
  tmp=$(mktemp -d -t happy-assess-health.XXXXXX)
  trap "rm -rf '$tmp'" RETURN
  XDG_DATA_HOME="$tmp/data" XDG_CONFIG_HOME="$tmp/cfg" \
    XDG_CACHE_HOME="$tmp/cache" XDG_STATE_HOME="$tmp/state" \
    nvim --headless -c 'checkhealth happy-nvim' -c 'qa!' 2>&1 | tee "$tmp/health.log"
  ! grep -Eiq '^\s*ERROR\b' "$tmp/health.log"
}

run_layer 'shell-syntax'      layer_shell_syntax
run_layer 'python-syntax'     layer_python_syntax
run_layer 'init-bootstrap'    layer_init_bootstrap
run_layer 'plenary'           layer_plenary
run_layer 'integration'       layer_integration
run_layer 'checkhealth'       layer_checkhealth

# Final table
echo
echo '================================================================'
printf ' %-20s %-6s %s\n' LAYER STATUS DURATION
echo '----------------------------------------------------------------'
overall=0
for name in "${LAYER_ORDER[@]}"; do
  printf ' %-20s %-6s %ds\n' "$name" "${LAYER_STATUS[$name]}" "${LAYER_DURATION[$name]}"
  [[ "${LAYER_STATUS[$name]}" == FAIL ]] && overall=1
done
echo '================================================================'
if (( overall == 0 )); then
  echo 'ASSESS: ALL LAYERS PASS'
else
  echo 'ASSESS: FAILURES DETECTED'
fi
exit $overall
```

- [ ] **Step 2: Make it executable**

```bash
chmod +x scripts/assess.sh
```

- [ ] **Step 3: Syntax check**

```bash
bash -n scripts/assess.sh && echo SYNTAX_OK
```

Expected: `SYNTAX_OK`.

- [ ] **Step 4: Run the assessor end-to-end**

```bash
cd /home/raul/worktrees/happy-nvim/feat-v1-implementation
bash scripts/assess.sh
```

Expected tail:
```
================================================================
 LAYER                STATUS DURATION
----------------------------------------------------------------
 shell-syntax         PASS   0s
 python-syntax        PASS   0s
 init-bootstrap       PASS   Ns
 plenary              PASS   Ns
 integration          PASS   Ns
 checkhealth          PASS   Ns
================================================================
ASSESS: ALL LAYERS PASS
```

Exit code 0.

If any layer fails locally (e.g. sandbox restrictions blocking nvim state dirs), investigate and fix before moving on — the CI runner won't have that restriction, but a green local run proves the script's logic.

- [ ] **Step 5: Append the `assess` CI job**

Append to the `jobs:` section of `.github/workflows/ci.yml`:

```yaml
  assess:
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
      - name: Install tree-sitter CLI
        run: |
          sudo npm install -g tree-sitter-cli
          tree-sitter --version
      - name: Run assess.sh (full feature acceptance)
        run: bash scripts/assess.sh
```

- [ ] **Step 6: Validate YAML and commit**

```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/ci.yml'))" && echo YAML_OK
```

Expected: `YAML_OK`.

```bash
git add scripts/assess.sh .github/workflows/ci.yml
git commit -m "feat: scripts/assess.sh aggregator + CI assess job

One-button 'is the config broken?' workflow. assess.sh runs every
verification layer in order (shell-syntax, python-syntax,
init-bootstrap, plenary, integration, checkhealth), times each,
prints a pass/fail table. Exits nonzero on any failure. CI runs it
under matrix stable+nightly. Closes todo 5.11."
```

---

## Task 4: Push + verify green CI

**Files:** none (push-only task)

**Context:** Final verification. Push the three task commits, wait for CI, confirm `assess` jobs green alongside the existing jobs.

- [ ] **Step 1: Fast-forward main + push**

```bash
cd /home/raul/projects/happy-nvim
git checkout main
git merge --ff-only feat/v1-implementation
git push git@github.com:raulfrk/happy-nvim.git main:main
```

Expected: `main -> main` advances 3 commits (one per task).

- [ ] **Step 2: Capture the new run id**

```bash
sleep 6
RUN_ID=$(gh api repos/raulfrk/happy-nvim/actions/runs --jq '.workflow_runs[0].id')
echo "$RUN_ID"
```

- [ ] **Step 3: Poll until complete**

```bash
while true; do
  s=$(gh api "repos/raulfrk/happy-nvim/actions/runs/$RUN_ID" --jq '"\(.status)|\(.conclusion)"')
  echo "$(date +%H:%M:%S) $s"
  case "$s" in completed*) break;; esac
  sleep 20
done
```

- [ ] **Step 4: Per-job status check**

```bash
gh api "repos/raulfrk/happy-nvim/actions/runs/$RUN_ID/jobs" --jq '.jobs[] | "\(.name): \(.conclusion)"'
```

Expected every line ending in `success`, including:
```
assess (stable): success
assess (nightly): success
```

If any fails, fetch the full failed log:
```bash
TMPDIR=/tmp XDG_CACHE_HOME=/tmp gh run view "$RUN_ID" --log-failed -R raulfrk/happy-nvim | tail -100
```

Likely failure modes:
- `assess` fails at plenary layer because `HAPPY_NVIM_LOAD_CONFIG=1` isn't set inside `layer_plenary` — it is; verify Step 1 of Task 3 didn't drop the env prefix.
- OSC 52 test times out on the runner because `$TMUX` env var is empty — the test supplies a fallback; verify the `env_overrides` dict in Task 2 Step 1.
- Keymap spec reports missing mappings because `Lazy! sync` didn't complete before the spec ran — `layer_plenary` does the sync inline; increase the tail window if the log says "sync incomplete".

Commit the fix, push, re-poll.

- [ ] **Step 5: Close source todos**

In the main conversation:
```
todo_complete 5.1 5.6 5.11
```

---

## Self-Review

**1. Spec coverage:**

| Todo | Task |
|---|---|
| #5.1 keymap + user-cmd inventory | Task 1 (full spec + CI wiring) |
| #5.6 OSC 52 TextYankPost integration | Task 2 |
| #5.11 assess.sh aggregator | Task 3 (script + new CI job) |

No gaps.

**2. Placeholder scan:** no TBDs, no "similar to Task N", no vague instructions. Every code block is complete. Every shell command has expected output.

**3. Type consistency:** fixture names (`tmux_socket`, `scratch_dir`) match `tests/integration/conftest.py` from the previous plan. Helper functions (`tmx`, `wait_for_pane`, `send_keys`) match `tests/integration/helpers.py`. Lua expected-keymap tables in Task 1 Step 2 align with the observed inventory collected in Task 1 Step 1 — if Step 1 reveals drift from the code, Step 2 tables must be updated inline before writing the spec.
