# Idle alerts + telescope previewer fix

> **For agentic workers:** REQUIRED SUB-SKILL: `superpowers:subagent-driven-development` (or `superpowers:executing-plans`). Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Resolve two open project todos in one push:
- **#8 (high, bug):** `:Telescope find_files` crashes on preview with `attempt to call field 'ft_to_lang' (a nil value)`. Production pins `nvim-telescope/telescope.nvim` to `tag = '0.1.8'` whose `previewers/utils.lua:135` calls `require('nvim-treesitter.parsers').ft_to_lang(ft)` — removed from current `nvim-treesitter` master. The `0.1.x` rolling branch already migrates off the dead API. (CI is green because `tests/integration/test_telescope.py:46` already uses `branch = '0.1.x'` for its own scratch nvim — production drift wasn't caught.)
- **#7 (medium, feature):** Multi-project Claude notifications today are passive only (`@claude_idle` tmux option → picker badge `✓/⟳/?` + opt-in tmux status-right snippet). On busy→idle flip nothing pushes to nvim. Add opt-in `vim.notify` (+ optional terminal bell / `notify-send`) with focus-skip + per-session cooldown.

**Architecture:**

- **Telescope** — single-line bump from `tag = '0.1.8'` to `branch = '0.1.x'`. Add a regression assertion to `test_telescope.py` so a future regression to `ft_to_lang` is caught.
- **Idle alert** — extend `lua/tmux/idle.lua` with a pure decision fn `_should_alert` and an alert dispatch invoked from `apply_flip(session, idle=true)`. Knobs flow via `tmux.setup({ alert = {...} })` → `lua/tmux/init.lua` → `idle.setup`. Defaults: `notify=true`, `bell=false`, `desktop=false`, `cooldown_secs=10`, `skip_focused=true`. Existing 7 `_tick` unit tests untouched.

**Tech stack:** Lua 5.1 (plenary unit tests), Python 3.11 (pytest integration), tmux 3.2+, Neovim 0.11+.

---

## File Structure

```
lua/plugins/telescope.lua    # MODIFIED — tag '0.1.8' → branch '0.1.x'
lua/tmux/init.lua            # MODIFIED — accept opts, forward opts.alert to idle.setup
lua/tmux/idle.lua            # MODIFIED — setup, _should_alert, alert dispatch in apply_flip
tests/tmux_idle_spec.lua     # MODIFIED — add 5 _should_alert cases
tests/integration/
├── test_telescope.py        # MODIFIED — assert no ft_to_lang error in capture
└── test_idle_alert.py       # NEW — drives _poll_once w/ notify=true, asserts NOTIFY: line
README.md                    # MODIFIED — Active alerts subsection under Multi-project notifications
docs/manual-tests.md         # MODIFIED — append rows for telescope no-crash + idle alert
```

---

## Task 1: Bump telescope + regression assertion

**Files:** `lua/plugins/telescope.lua`, `tests/integration/test_telescope.py`.

**Context:** Pin shift unblocks daily use. Test guard prevents silent re-regression.

- [ ] **Step 1: Change pin**

In `lua/plugins/telescope.lua` replace `tag = '0.1.8'` with `branch = '0.1.x'`.

- [ ] **Step 2: Add no-crash assertion to telescope integration test**

After the existing `_has_beta` assertion in `tests/integration/test_telescope.py`, add a final capture + grep:

```python
        # Regression guard: previewer must not crash with ft_to_lang
        out_after = capture_pane(tmux_socket, session)
        assert "ft_to_lang" not in out_after, (
            f"telescope previewer raised ft_to_lang error:\n{out_after}"
        )
        assert "vim.schedule callback" not in out_after, (
            f"unexpected scheduler crash in telescope:\n{out_after}"
        )
```

- [ ] **Step 3: Run test**

```bash
cd /home/raul/worktrees/happy-nvim/feat-idle-alert-telescope
python3 -m pytest tests/integration/test_telescope.py -v 2>&1 | tail -10
```

Expect `1 passed`.

- [ ] **Step 4: Stylua + commit**

```bash
export STYLUA=/tmp/npmcache/_npx/2d7ba7d0047acad9/node_modules/.bin/stylua
$STYLUA lua/plugins/telescope.lua && $STYLUA --check lua/plugins/telescope.lua
git add lua/plugins/telescope.lua tests/integration/test_telescope.py
git commit -m "fix(telescope): track 0.1.x branch to avoid ft_to_lang crash

The 0.1.8 release calls nvim-treesitter.parsers.ft_to_lang() which
was removed from current nvim-treesitter master. 0.1.x branch
already migrated off the deprecated API. Add a regression assertion
to the integration test so silent drift is caught in CI."
```

---

## Task 2: Idle alert layer

**Files:** `lua/tmux/idle.lua`, `lua/tmux/init.lua`, `tests/tmux_idle_spec.lua`.

**Context:** Surface a `vim.notify` (and optional bell/desktop) on the busy→idle transition. Pure decision split out for unit tests; impure dispatch lives in `apply_flip`.

- [ ] **Step 1: Extend `lua/tmux/idle.lua` with setup + decision + dispatch**

Add module-level state + setup at the top (after `local POLL_INTERVAL_MS = 1000`):

```lua
local DEFAULT_OPTS = {
  notify        = true,
  bell          = false,
  desktop       = false,
  cooldown_secs = 10,
  skip_focused  = true,
}

local opts = vim.deepcopy(DEFAULT_OPTS)
local last_alert_ts = {}

function M.setup(user_opts)
  opts = vim.tbl_deep_extend('force', vim.deepcopy(DEFAULT_OPTS), user_opts or {})
end
```

Add the pure decision fn (kept exported with leading underscore for tests):

```lua
function M._should_alert(session, focused_session, last_ts, now, o)
  if not (o.notify or o.bell or o.desktop) then
    return false
  end
  if o.skip_focused and session == focused_session then
    return false
  end
  if last_ts and (now - last_ts) < o.cooldown_secs then
    return false
  end
  return true
end
```

Add focus + alert helpers (impure):

```lua
local function focused_session()
  local res = vim.system({ 'tmux', 'display-message', '-p', '#{session_name}' }, { text = true }):wait()
  if res.code ~= 0 then
    return nil
  end
  return (res.stdout or ''):gsub('%s+$', '')
end

local function fire_alert(session)
  local slug = session:gsub('^cc%-', '')
  local msg = 'Claude (' .. slug .. ') idle'
  if opts.notify then
    vim.notify(msg, vim.log.levels.INFO, { title = 'Claude' })
  end
  if opts.bell then
    io.stderr:write('\a')
  end
  if opts.desktop then
    if vim.fn.executable('notify-send') == 1 then
      vim.system({ 'notify-send', 'Claude', msg }):wait()
    elseif vim.fn.executable('osascript') == 1 then
      vim.system({ 'osascript', '-e',
        'display notification "' .. msg .. '" with title "Claude"' }):wait()
    end
  end
end
```

Modify `apply_flip` to dispatch on idle==true:

```lua
local function apply_flip(session_name, idle)
  local val = idle and '1' or '0'
  vim.system({ 'tmux', 'set-option', '-t', session_name, '@claude_idle', val }):wait()
  vim.system({ 'tmux', 'refresh-client', '-S' }):wait()
  if idle then
    local now = os.time()
    if M._should_alert(session_name, focused_session(), last_alert_ts[session_name], now, opts) then
      fire_alert(session_name)
      last_alert_ts[session_name] = now
    end
  end
end
```

Reset `last_alert_ts` in `M.stop()`:

```lua
function M.stop()
  if timer then
    timer:stop()
    timer:close()
    timer = nil
  end
  states = {}
  last_alert_ts = {}
end
```

- [ ] **Step 2: Wire opts through `lua/tmux/init.lua`**

Replace the body of `M.setup`:

```lua
function M.setup(user_opts)
  if vim.env.TMUX == nil or vim.env.TMUX == '' then
    return
  end
  user_opts = user_opts or {}
  require('tmux.claude').setup(user_opts.claude)
  require('tmux.popup').setup(user_opts.popup)
  require('tmux.idle').setup(user_opts.alert)
end
```

Backwards compat: `tmux.claude.setup(nil)` and `tmux.popup.setup(nil)` already accept no-arg calls (verified in `lua/tmux/popup.lua:29` and `lua/tmux/claude.lua`). Idle setup accepts nil.

- [ ] **Step 3: Add 5 unit tests for `_should_alert`**

Append to `tests/tmux_idle_spec.lua`:

```lua
describe('tmux.idle._should_alert', function()
  local OPTS = {
    notify = true, bell = false, desktop = false,
    cooldown_secs = 10, skip_focused = true,
  }

  it('returns false when all channels off', function()
    local o = vim.tbl_deep_extend('force', OPTS, { notify = false })
    assert.is_false(idle._should_alert('cc-a', 'cc-b', nil, 100, o))
  end)

  it('returns false when session is focused and skip_focused=true', function()
    assert.is_false(idle._should_alert('cc-a', 'cc-a', nil, 100, OPTS))
  end)

  it('returns true when focused but skip_focused=false', function()
    local o = vim.tbl_deep_extend('force', OPTS, { skip_focused = false })
    assert.is_true(idle._should_alert('cc-a', 'cc-a', nil, 100, o))
  end)

  it('returns false when cooldown not elapsed', function()
    assert.is_false(idle._should_alert('cc-a', 'cc-b', 95, 100, OPTS))
  end)

  it('returns true when cooldown elapsed and not focused', function()
    assert.is_true(idle._should_alert('cc-a', 'cc-b', 80, 100, OPTS))
  end)
end)
```

- [ ] **Step 4: Run unit tests**

```bash
XDG_DATA_HOME="$PWD/.tests" XDG_CONFIG_HOME="$PWD/.tests/config" \
  XDG_CACHE_HOME="$PWD/.tests/cache" XDG_STATE_HOME="$PWD/.tests/state" \
  nvim --headless -u tests/minimal_init.lua \
  -c "PlenaryBustedFile tests/tmux_idle_spec.lua" -c 'qa!' 2>&1 | tail -15
```

Expect `Success: 12, Failed: 0`.

- [ ] **Step 5: Stylua + commit**

```bash
$STYLUA lua/tmux/idle.lua lua/tmux/init.lua tests/tmux_idle_spec.lua
$STYLUA --check lua/tmux/idle.lua lua/tmux/init.lua tests/tmux_idle_spec.lua
git add lua/tmux/idle.lua lua/tmux/init.lua tests/tmux_idle_spec.lua
git commit -m "feat(tmux/idle): vim.notify + bell + desktop alerts on idle flip

New tmux.setup({ alert = { notify, bell, desktop, cooldown_secs,
skip_focused }}) surface routes through tmux.init -> idle.setup.
Pure _should_alert decision fn keeps cooldown + focus-skip
testable without mocking tmux. apply_flip(idle=true) reads the
focused session via tmux display-message, runs _should_alert, and
fires enabled channels. Defaults: notify ON, others off, 10s
cooldown, skip current session."
```

---

## Task 3: Integration test for the alert path

**Files:** `tests/integration/test_idle_alert.py` (new).

**Context:** Mirror `test_idle_notification.py`'s `_poll_twice_via_nvim` pattern. Override `vim.notify` with a stdout shim so the integration test can assert one notification fired.

- [ ] **Step 1: Write the test**

```python
"""Integration test: tmux.idle fires vim.notify on busy→idle flip.

Same _poll_once driver as test_idle_notification.py, but with
alert.notify=true and a vim.notify shim that prints to stdout so we
can assert exactly one notification is emitted per flip.
"""
from __future__ import annotations

import os
import subprocess
import time
from pathlib import Path

from .helpers import send_keys, tmx, wait_for_pane

REPO_ROOT = Path(__file__).resolve().parents[2]
SESSION = "cc-alert-test"


def _cleanup(tmux_socket: str) -> None:
    subprocess.run(
        ["tmux", "-L", tmux_socket, "kill-session", "-t", SESSION],
        check=False, capture_output=True,
    )


def _tmux_wrapper(bin_dir: Path, socket: str) -> None:
    real = "/usr/bin/tmux"
    w = bin_dir / "tmux"
    w.write_text(f"#!/usr/bin/env bash\nexec {real} -L {socket} \"$@\"\n")
    w.chmod(0o755)


def _poll_with_alert(bin_dir: Path, now1: int, now2: int) -> str:
    """Run two _poll_once calls with notify shim; return captured stdout."""
    env = os.environ | {
        "PATH": f"{bin_dir}:{os.environ['PATH']}",
        "TMUX": "/tmp/fake,1,0",
    }
    result = subprocess.run(
        [
            "nvim", "--headless", "--clean",
            "-c", f"lua vim.opt.rtp:prepend('{REPO_ROOT}')",
            "-c", "lua vim.notify = function(msg, _, _) print('NOTIFY:'..msg) end",
            "-c", "lua require('tmux.idle').setup({ notify=true, skip_focused=false })",
            "-c", f"lua require('tmux.idle')._poll_once({now1})",
            "-c", f"lua require('tmux.idle')._poll_once({now2})",
            "-c", "qa!",
        ],
        check=True, text=True, capture_output=True, env=env,
    )
    return result.stdout


def test_idle_alert_fires_on_flip(tmux_socket: str, tmp_path: Path):
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    _tmux_wrapper(bin_dir, tmux_socket)
    _cleanup(tmux_socket)

    try:
        tmx(tmux_socket, "new-session", "-d", "-s", SESSION, "claude --delay 0")
        pane = tmx(tmux_socket, "list-panes", "-t", SESSION, "-F", "#{pane_id}").stdout.strip()

        send_keys(tmux_socket, pane, "hello", "Enter")
        wait_for_pane(tmux_socket, pane, r"ACK:hello", timeout=5)
        time.sleep(0.5)

        now = int(time.time())
        out = _poll_with_alert(bin_dir, now, now + 3)

        assert "NOTIFY:Claude (alert-test) idle" in out, (
            f"expected NOTIFY: line on busy→idle flip, got:\n{out}"
        )
        assert out.count("NOTIFY:") == 1, (
            f"expected exactly 1 notification, got {out.count('NOTIFY:')} in:\n{out}"
        )
    finally:
        _cleanup(tmux_socket)
```

- [ ] **Step 2: Run test**

```bash
python3 -m pytest tests/integration/test_idle_alert.py -v 2>&1 | tail -15
```

Expect `1 passed`.

- [ ] **Step 3: Commit**

```bash
git add tests/integration/test_idle_alert.py
git commit -m "test(integration): vim.notify fires once on idle flip

Drives tmux.idle._poll_once twice in one nvim invocation (so the
in-memory states table survives), with a vim.notify shim that
prints NOTIFY: lines to stdout. Asserts exactly one notification
fires on the busy→idle transition."
```

---

## Task 4: Docs (README + manual-tests)

**Files:** `README.md`, `docs/manual-tests.md`.

- [ ] **Step 1: README — append "Active alerts" subsection**

In `README.md`, locate the "## Multi-project notifications" section and append after the existing tmux snippet block:

```markdown

### Active alerts

Beyond the passive status-bar badge, you can opt into push notifications
when a session flips busy→idle. Configure in your nvim setup:

\`\`\`lua
require('tmux').setup({
  alert = {
    notify        = true,   -- vim.notify on flip (default ON)
    bell          = false,  -- terminal bell (\a)
    desktop       = false,  -- notify-send (Linux) / osascript (macOS)
    cooldown_secs = 10,     -- min seconds between alerts per session
    skip_focused  = true,   -- don't alert if you're in that session
  },
})
\`\`\`

`vim.notify` integrates with `noice.nvim` automatically. `desktop` requires
`notify-send` (Linux) or `osascript` (macOS) on `$PATH`.
```

(The escaped backticks in the snippet above are the literal triple-backticks for the Lua block — write them unescaped in the file.)

- [ ] **Step 2: Manual-tests rows**

Append to `docs/manual-tests.md` under the existing Multi-project section (or under section 9 if exists):

```markdown
## Idle alerts (Phase 3 follow-up)

- [ ] (CI-covered) Open `:Telescope find_files`, navigate any file → no `ft_to_lang` error in `:messages`
- [ ] (CI-covered) Idle alert: send prompt to a `cc-*` session from another tmux window. After Claude finishes, nvim shows `Claude (<slug>) idle` notification
- [ ] Bell opt-in: set `alert.bell = true`, repeat above — terminal beep accompanies notify
- [ ] Desktop opt-in (requires `notify-send`/`osascript`): set `alert.desktop = true` → OS-level notification appears
- [ ] Cooldown: trigger two flips in quick succession → only one notification
- [ ] Focus-skip: stay in the `cc-*` pane → no notification fires
```

- [ ] **Step 3: Commit**

```bash
git add README.md docs/manual-tests.md
git commit -m "docs(idle-alert): README + manual-tests for tmux.setup({alert={...}})

README adds an 'Active alerts' subsection under Multi-project
notifications documenting the new opts. manual-tests.md gets rows
for the CI-covered cases (telescope no-crash + alert fires) plus
manual-only opt-ins (bell, desktop, cooldown, focus-skip)."
```

---

## Task 5: Push + verify CI

- [ ] **Step 1: Run assess.sh**

```bash
bash scripts/assess.sh
```

Expect `ASSESS: ALL LAYERS PASS`.

- [ ] **Step 2: Push to main**

```bash
git push git@github.com:raulfrk/happy-nvim.git feat/idle-alert-telescope:main
```

Expect `feat/idle-alert-telescope -> main` advances ~5 commits.

- [ ] **Step 3: Poll CI**

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

All jobs `success` including `assess (stable/nightly)` w/ new tests.

- [ ] **Step 4: Close todos**

```
todo_complete 7 8
```

---

## Manual Test Additions

The following rows are appended to `docs/manual-tests.md` by Task 4:

- `[ ] (CI-covered) :Telescope find_files preview renders without ft_to_lang error`
- `[ ] (CI-covered) Idle alert fires once on busy→idle in another tmux window`
- `[ ] Bell opt-in: alert.bell=true → terminal beep alongside notify`
- `[ ] Desktop opt-in (notify-send/osascript): alert.desktop=true → OS notification`
- `[ ] Cooldown: two rapid flips → one notification`
- `[ ] Focus-skip: staying in cc-* pane → no notification`
