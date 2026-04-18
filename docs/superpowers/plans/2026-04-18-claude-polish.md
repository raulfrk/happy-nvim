# Claude Integration Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Three small polish items — `:checkhealth` probes for the Claude integration surface, a README "Working with Claude" subsection explaining pane-vs-popup trade-offs, and a `setup({ popup = { width, height } })` entry point so popup dimensions are configurable.

**Architecture:** Health gains one new section (`claude`). `README.md` gains a subsection before the existing "Multi-project notifications" block. `lua/tmux/claude_popup.lua` gains a module-level `M._config = { width = '85%', height = '85%' }` + an `M.setup(opts)` that merges user overrides; existing `open` / `fresh` read from `M._config` instead of hard-coded constants. Backwards-compatible — callers who never call `setup()` see the existing defaults.

**Tech Stack:** Lua 5.1, Neovim 0.11+, tmux 3.2+.

---

## File Structure

```
lua/happy/health.lua         # MODIFIED — add claude probe section
lua/tmux/claude_popup.lua    # MODIFIED — configurable width/height via setup(opts)
README.md                    # MODIFIED — "Working with Claude" subsection
```

---

## Task 1: `:checkhealth` probes for Claude integration

**Files:**
- Modify: `lua/happy/health.lua`

**Context:** Missing `claude` CLI is currently invisible in `:checkhealth`. Users only find out when `<leader>cc` silently fails. Same for tmux < 3.2 (no `display-popup -E`). Add a `happy-nvim: claude` section that probes:
1. `claude` on `$PATH`
2. tmux version >= 3.2 (for popup support)
3. For the current nvim window: is `@claude_pane_id` set + alive?
4. Is `cc-<current-project>` session present?

The current project's session name is derived via `require('tmux.project').session_name()` which Phase 1 added. If `tmux.project` fails to load, skip the session check (not fatal).

- [ ] **Step 1: Edit `lua/happy/health.lua`**

Find the existing `h.start('happy-nvim: tmux')` section. Add a new Claude section AFTER the tmux block (before `h.start('happy-nvim: mosh')`):

```lua

  h.start('happy-nvim: claude integration')
  if vim.fn.executable('claude') == 1 then
    h.ok('claude CLI found on $PATH')
  else
    h.warn('claude CLI not on $PATH — <leader>c* tmux integration inoperable')
  end
  if vim.env.TMUX == nil or vim.env.TMUX == '' then
    h.info('not in tmux — skipping session probes')
  else
    local _, tmux_ver = exec({ 'tmux', '-V' })
    local major, minor = (tmux_ver or ''):match('(%d+)%.(%d+)')
    if major and minor then
      local m = tonumber(major)
      local n = tonumber(minor)
      if m > 3 or (m == 3 and n >= 2) then
        h.ok('tmux ' .. major .. '.' .. minor .. ' supports display-popup -E')
      else
        h.error(
          'tmux ' .. major .. '.' .. minor .. ' < 3.2 — <leader>cp popup requires 3.2+'
        )
      end
    end
    -- Per-window pane registration
    local _, pane = exec({ 'tmux', 'show-option', '-w', '-v', '-q', '@claude_pane_id' })
    pane = (pane or ''):gsub('%s+$', '')
    if pane == '' then
      h.info('no @claude_pane_id on this window (press <leader>cc to create one)')
    else
      local alive, _ = exec({ 'tmux', 'list-panes', '-t', pane })
      if alive then
        h.ok('claude pane registered + alive: ' .. pane)
      else
        h.warn('claude pane ' .. pane .. ' registered but no longer exists (stale)')
      end
    end
    -- Per-project popup session
    local ok, project = pcall(require, 'tmux.project')
    if ok then
      local session = project.session_name()
      local has, _ = exec({ 'tmux', 'has-session', '-t', session })
      if has then
        h.ok("claude-popup session '" .. session .. "' running")
      else
        h.info(
          "no claude-popup session for this project yet (press <leader>cp to start one, target: "
            .. session
            .. ')'
        )
      end
    end
  end
```

- [ ] **Step 2: Stylua + smoke**

```bash
cd /home/raul/worktrees/happy-nvim/feat-v1-implementation
export STYLUA=/tmp/npmcache/_npx/2d7ba7d0047acad9/node_modules/.bin/stylua
$STYLUA lua/happy/health.lua
$STYLUA --check lua/happy/health.lua && echo STYLUA_OK
bash scripts/assess.sh 2>&1 | tail -15
```

Expected: `STYLUA_OK` + `ASSESS: ALL LAYERS PASS` (checkhealth layer now includes the new probes).

- [ ] **Step 3: Commit**

```bash
git add lua/happy/health.lua
git commit -m "feat(health): claude integration probes

New :checkhealth happy-nvim section 'claude integration' checks:
- claude CLI on \$PATH (warn if missing)
- tmux >= 3.2 (error if older — display-popup -E required)
- Current window's @claude_pane_id: set + alive vs unset vs stale
- Current project's cc-<slug> popup session presence

Info-level for optional state (no pane yet, no popup yet); warn/error
for actual prerequisites."
```

---

## Task 2: Configurable popup width/height via `setup(opts)`

**Files:**
- Modify: `lua/tmux/claude_popup.lua`

**Context:** Popup dimensions are hardcoded `85%` x `85%`. Some users want a narrower popup that leaves more of the code visible; others want full-screen on a small terminal. Add a `setup({ popup = { width = ..., height = ... } })` that merges into module-local defaults. `open()` / `fresh()` / `M.open()` read from the merged config.

Keep backward compat: if `setup()` is never called, defaults match the current behavior. The existing `claude_popup.ensure` / `claude_popup.open` / `claude_popup.fresh` / `claude_popup.pane_id` / `claude_popup.kill` keep the same public signatures.

- [ ] **Step 1: Edit `lua/tmux/claude_popup.lua`**

Find the top of the module:

```lua
local M = {}
local project = require('tmux.project')

local POPUP_W = '85%'
local POPUP_H = '85%'
```

Replace with:

```lua
local M = {}
local project = require('tmux.project')

-- Defaults; override via M.setup({ popup = { width = ..., height = ... } }).
M._config = {
  popup = {
    width = '85%',
    height = '85%',
  },
}

-- Merge user overrides shallowly into _config. Backwards-compatible: if
-- setup is never called, popup dimensions stay at the defaults above.
function M.setup(opts)
  opts = opts or {}
  if opts.popup then
    M._config.popup.width = opts.popup.width or M._config.popup.width
    M._config.popup.height = opts.popup.height or M._config.popup.height
  end
end
```

Then find the `M.open` function:

```lua
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
```

Replace `POPUP_W` → `M._config.popup.width` and `POPUP_H` → `M._config.popup.height`:

```lua
  sys({
    'tmux',
    'display-popup',
    '-E',
    '-w',
    M._config.popup.width,
    '-h',
    M._config.popup.height,
    'tmux attach -t ' .. session(),
  })
```

- [ ] **Step 2: Add unit test for `setup()` merge behavior**

Find `tests/tmux_send_spec.lua` or create a new spec for claude_popup. Add a dedicated spec file `tests/tmux_claude_popup_spec.lua`:

```lua
-- tests/tmux_claude_popup_spec.lua
-- Unit tests for lua/tmux/claude_popup.lua config merge. Live tmux ops
-- are covered by integration tests in tests/integration/; here we only
-- assert setup() applies overrides correctly.

describe('tmux.claude_popup.setup', function()
  local popup

  before_each(function()
    package.loaded['tmux.claude_popup'] = nil
    popup = require('tmux.claude_popup')
  end)

  it('defaults to 85% x 85%', function()
    assert.are.equal('85%', popup._config.popup.width)
    assert.are.equal('85%', popup._config.popup.height)
  end)

  it('applies width override, keeps height default', function()
    popup.setup({ popup = { width = '70%' } })
    assert.are.equal('70%', popup._config.popup.width)
    assert.are.equal('85%', popup._config.popup.height)
  end)

  it('applies both width + height overrides', function()
    popup.setup({ popup = { width = '100%', height = '60%' } })
    assert.are.equal('100%', popup._config.popup.width)
    assert.are.equal('60%', popup._config.popup.height)
  end)

  it('no-op when setup called with nil', function()
    popup.setup()
    assert.are.equal('85%', popup._config.popup.width)
  end)

  it('no-op when setup called with empty table', function()
    popup.setup({})
    assert.are.equal('85%', popup._config.popup.width)
  end)
end)
```

- [ ] **Step 3: Run the spec**

```bash
XDG_DATA_HOME="$PWD/.tests" XDG_CONFIG_HOME="$PWD/.tests/config" \
  XDG_CACHE_HOME="$PWD/.tests/cache" XDG_STATE_HOME="$PWD/.tests/state" \
  nvim --headless -u tests/minimal_init.lua \
  -c "PlenaryBustedFile tests/tmux_claude_popup_spec.lua" -c 'qa!' 2>&1 | tail -10
```

Expected: `Success: 5  Failed : 0  Errors : 0`.

- [ ] **Step 4: Stylua + commit**

```bash
$STYLUA lua/tmux/claude_popup.lua tests/tmux_claude_popup_spec.lua
$STYLUA --check lua/tmux/claude_popup.lua tests/tmux_claude_popup_spec.lua && echo STYLUA_OK
git add lua/tmux/claude_popup.lua tests/tmux_claude_popup_spec.lua
git commit -m "feat(tmux/claude_popup): configurable popup width/height via setup

New M._config table + M.setup(opts) merges user overrides. Default
85% x 85% unchanged. Users can now:

  require('tmux.claude_popup').setup({
    popup = { width = '70%', height = '80%' },
  })

open/fresh read from M._config instead of hardcoded POPUP_W/H
constants. 5 plenary tests cover default + single + dual overrides
+ nil + empty-table calls."
```

---

## Task 3: README — "Working with Claude" subsection

**Files:**
- Modify: `README.md`

**Context:** Two surfaces (pane, popup) + four variants (cc/cC/cp/cP) + three send commands (cf/cs/ce) + picker (cl) + new (cn) + kill (ck) is a lot. Users need a trade-off table + keymap reference. Add a subsection BEFORE "Multi-project notifications".

- [ ] **Step 1: Append the subsection to README**

Find the existing "Multi-project notifications" heading in `README.md`. Insert this block BEFORE it:

```markdown

## Working with Claude

Two surfaces for Claude Code, pick per task:

| Surface | Key | When to use |
|---|---|---|
| Split pane | `<leader>cc` | Long sessions; keep chat + code side-by-side. Per-nvim-window. |
| Floating popup | `<leader>cp` | Quick questions; reclaim screen space by dismissing. Global per project. |

### Keymap reference

| Key | Action |
|---|---|
| `<leader>cc` | open/attach per-window pane (splits horizontally on first press) |
| `<leader>cp` | toggle popup attached to `cc-<project>` session |
| `<leader>cC` | kill + respawn the pane (fresh Claude) |
| `<leader>cP` | kill + respawn the popup session (fresh Claude) |
| `<leader>cl` | telescope picker of every `cc-*` session w/ idle-state icons |
| `<leader>cn` | prompt for a slug → spawn a new `cc-<slug>` session in cwd |
| `<leader>ck` | kill the current project's popup session (confirm) |
| `<leader>cf` | send current file's path as `@path/to/file` to active surface |
| `<leader>cs` | (visual mode) send selection as fenced code block w/ file:lineno header |
| `<leader>ce` | send current buffer's LSP diagnostics + a "fix these" prompt |

### Send routing

`<leader>cf` / `<leader>cs` / `<leader>ce` auto-route in this priority:

1. `@claude_pane_id` on the current nvim window (set by `<leader>cc`).
2. The `cc-<current-project>` popup session's pane (set by `<leader>cp`).
3. If neither exists: warn + no-op.

You can have both open; pane wins when both are registered, so the
chat you've been looking at gets the send.

### Customizing popup size

Default is 85% × 85% of the outer terminal. Override in your
`init.lua` (or any file sourced after happy-nvim loads):

```lua
require('tmux.claude_popup').setup({
  popup = { width = '70%', height = '80%' },
})
```

Values are passed verbatim to `tmux display-popup -w / -h`, so absolute
cell counts (e.g. `120`) work too.
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs(readme): Working with Claude — surfaces + keymap reference

New subsection:
- When to use pane (long session, side-by-side) vs popup (quick Q,
  reclaim space)
- Full keymap table for <leader>c* (cc/cp/cC/cP/cl/cn/ck/cf/cs/ce)
- Send routing priority (pane > popup > warn)
- Popup size customization via claude_popup.setup({ popup = {...} })"
```

---

## Task 4: Manual test additions

**Files:**
- Modify: `docs/manual-tests.md`

- [ ] **Step 1: Add rows under "4. Tmux + Claude"**

Find section "4. Tmux + Claude" in `docs/manual-tests.md`. Append:

```markdown
- [ ] `:checkhealth happy-nvim` section "claude integration" shows:
  - `ok claude CLI found on $PATH`
  - `ok tmux X.Y supports display-popup -E` (X.Y >= 3.2)
  - Per-window pane state (ok/info/warn)
  - Per-project popup session state (ok/info)
- [ ] After `require('tmux.claude_popup').setup({ popup = { width = '50%' } })` in init.lua, `<Space>cp` opens a narrower popup
```

- [ ] **Step 2: Commit**

```bash
git add docs/manual-tests.md
git commit -m "docs(manual): claude-integration checkhealth rows + popup sizing"
```

---

## Task 5: Push + verify green CI

**Files:** none.

- [ ] **Step 1: FF + push**

```bash
cd /home/raul/projects/happy-nvim
git checkout main
git merge --ff-only feat/v1-implementation
git push git@github.com:raulfrk/happy-nvim.git main:main
```

- [ ] **Step 2: Poll**

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

- [ ] **Step 3: Verify per-job**

```bash
gh api "repos/raulfrk/happy-nvim/actions/runs/$RUN_ID/jobs" --jq '.jobs[] | "\(.name): \(.conclusion)"'
```

Expected all `success`.

- [ ] **Step 4: Close source todos**

```
todo_complete 2.4 2.5 2.7
```

---

## Self-Review

**1. Spec coverage:**

| Todo | Task |
|---|---|
| #2.4 checkhealth claude probes | Task 1 |
| #2.7 configurable popup dimensions | Task 2 |
| #2.5 README pane-vs-popup doc | Task 3 |

Task 4 (manual-tests additions) is the Manual Test Additions convention from Todo #6.2.

**2. Placeholder scan:** no TBDs. Every code block complete.

**3. Type consistency:**
- `M._config` layout (`{ popup = { width, height } }`) consistent across Task 2 Step 1 impl + Step 2 tests + Task 3 README example.
- `project.session_name()` call signature matches Phase 1 `lua/tmux/project.lua`.
- `h.ok/warn/error/info/start` calls match existing health.lua patterns.
- `exec({...})` helper signature already defined in health.lua; Task 1 reuses it.
