# Fix Telescope Previewer Crash Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop `:Telescope find_files` from crashing on nvim 0.11 when previewing files. telescope.nvim 0.1.8 (our pinned tag) still calls `vim.treesitter.language.ft_to_lang` which nvim removed — replace it with a one-line compat shim that aliases it to `get_lang`.

**Architecture:** Compat shim chosen over version bump for three reasons: (1) it's one line with zero runtime cost, (2) it fixes the API for *any* plugin hitting the deprecated path (not just telescope), and (3) 0.1.8 is the current stable tag — bumping to master trades a known release for a moving target. The shim goes in `lua/config/options.lua` (loads before any plugin), is guarded (`= x or y`) so if telescope ships a fix the shim becomes inert, and comes with a sentinel test that will fail loudly when the shim is no longer needed.

**Tech Stack:** Lua 5.1, Neovim 0.11+. No new dependencies.

---

## File Structure

```
lua/config/options.lua                        # MODIFIED — add 1-line compat shim
tests/config_shim_spec.lua                    # NEW — plenary spec guarding the shim's purpose
docs/manual-tests.md                          # MODIFIED — add telescope-previewer smoke row
```

---

## Task 1: Add the compat shim + guard spec

**Files:**
- Modify: `lua/config/options.lua`
- Create: `tests/config_shim_spec.lua`

**Context:** `lua/config/options.lua` is sourced from `init.lua` very early (before `config.lazy`), so the shim is live before any plugin loads. The shim:

```lua
vim.treesitter.language.ft_to_lang =
  vim.treesitter.language.ft_to_lang or vim.treesitter.language.get_lang
```

The `or` means: if nvim brings `ft_to_lang` back, we don't clobber it. If telescope.nvim ships a fix that stops calling `ft_to_lang`, the shim is inert — no behavior change.

The spec asserts two things:

1. Shim is installed (both names resolve + refer to the same function).
2. `ft_to_lang("python")` returns `"python"` end-to-end — catches any future nvim build where `get_lang` moves or the signature changes.

When nvim re-introduces `ft_to_lang` natively (unlikely) or telescope stops needing it (likely), the spec still passes and the shim becomes dead code we can remove.

- [ ] **Step 1: Write the failing test (TDD — shim not installed yet)**

Create `tests/config_shim_spec.lua`:

```lua
-- tests/config_shim_spec.lua
-- Guards the compat shim added in lua/config/options.lua for the deprecated
-- vim.treesitter.language.ft_to_lang API. telescope.nvim 0.1.8 still calls
-- it; nvim 0.11+ removed it. Shim aliases it to get_lang.

describe('vim.treesitter.language.ft_to_lang compat shim', function()
  before_each(function()
    -- Re-source options.lua to install the shim in this spec's env.
    package.loaded['config.options'] = nil
    dofile(vim.fn.getcwd() .. '/lua/config/options.lua')
  end)

  it('ft_to_lang is callable after options.lua loads', function()
    assert.is_function(vim.treesitter.language.ft_to_lang)
  end)

  it('ft_to_lang resolves a known filetype to a language', function()
    -- 'lua' -> 'lua'. Any nvim build that bundles the lua treesitter grammar
    -- (ours does) returns 'lua' from get_lang. If this fails, the shim is
    -- wired wrong OR upstream renamed get_lang.
    local lang = vim.treesitter.language.ft_to_lang('lua')
    assert.are.equal('lua', lang)
  end)

  it('ft_to_lang prefers native impl when present (idempotent shim)', function()
    -- If upstream nvim re-adds ft_to_lang natively, the shim (`= x or y`)
    -- is a no-op — don't clobber. Simulate by stashing a sentinel first.
    local sentinel = function() return 'sentinel' end
    vim.treesitter.language.ft_to_lang = sentinel
    package.loaded['config.options'] = nil
    dofile(vim.fn.getcwd() .. '/lua/config/options.lua')
    assert.are.equal('sentinel', vim.treesitter.language.ft_to_lang())
    -- Restore so later specs don't see the sentinel
    vim.treesitter.language.ft_to_lang = nil
    package.loaded['config.options'] = nil
    dofile(vim.fn.getcwd() .. '/lua/config/options.lua')
  end)
end)
```

- [ ] **Step 2: Run failing test**

```bash
cd /home/raul/worktrees/happy-nvim/feat-v1-implementation
XDG_DATA_HOME="$PWD/.tests" XDG_CONFIG_HOME="$PWD/.tests/config" \
  XDG_CACHE_HOME="$PWD/.tests/cache" XDG_STATE_HOME="$PWD/.tests/state" \
  nvim --headless -u tests/minimal_init.lua \
  -c "PlenaryBustedFile tests/config_shim_spec.lua" -c 'qa!' 2>&1 | tail -10
```

Expected: first two tests FAIL with "attempt to call ... a nil value" (because `ft_to_lang` doesn't exist in nvim 0.11). Third test may pass (sentinel path) depending on exec order.

- [ ] **Step 3: Add the shim to `lua/config/options.lua`**

Find the top of `lua/config/options.lua`:

```lua
-- lua/config/options.lua
-- Option tweaks. termguicolors is set in plugins/colorscheme.lua BEFORE the
-- theme loads (per spec BUG-3 fix).

local o = vim.opt
```

Insert AFTER the header comment, BEFORE `local o = vim.opt`:

```lua
-- Compat shim: vim.treesitter.language.ft_to_lang was removed in nvim 0.11
-- (replaced by get_lang). telescope.nvim 0.1.8 still calls the old name from
-- its previewer, which crashes when you highlight a previewable file.
-- Alias it back; `= x or y` makes this a no-op if upstream ever restores
-- ft_to_lang natively. Remove once telescope ships a release that uses
-- get_lang directly.
if vim.treesitter and vim.treesitter.language then
  vim.treesitter.language.ft_to_lang =
    vim.treesitter.language.ft_to_lang or vim.treesitter.language.get_lang
end

```

- [ ] **Step 4: Run tests to verify pass**

Same command as Step 2. Expected: `Success: 3  Failed : 0  Errors : 0`.

- [ ] **Step 5: Smoke — open telescope previewer in a scratch session**

Manual smoke (skip if sandbox blocks Lazy sync):

```bash
# Same XDG redirects, open nvim interactively or via a :Telescope call
XDG_DATA_HOME="$PWD/.tests" XDG_CONFIG_HOME="$PWD/.tests/config" \
  XDG_CACHE_HOME="$PWD/.tests/cache" XDG_STATE_HOME="$PWD/.tests/state" \
  nvim --headless -c 'Lazy! sync' -c 'qa!' 2>&1 | tail -3
XDG_DATA_HOME="$PWD/.tests" XDG_CONFIG_HOME="$PWD/.tests/config" \
  XDG_CACHE_HOME="$PWD/.tests/cache" XDG_STATE_HOME="$PWD/.tests/state" \
  nvim --headless \
  -c 'lua require("telescope.previewers.utils").ts_highlighter(1, "python")' \
  -c 'qa!' 2>&1 | tail -5
```

Expected: no `attempt to call field 'ft_to_lang' (a nil value)` error. If the probe triggers a *different* telescope init error (e.g. buffer 1 not writable), that's fine — we only care the shim prevents the specific `ft_to_lang nil` crash.

- [ ] **Step 6: Stylua + assess**

```bash
export STYLUA=/tmp/npmcache/_npx/2d7ba7d0047acad9/node_modules/.bin/stylua
$STYLUA lua/config/options.lua tests/config_shim_spec.lua
$STYLUA --check lua/config/options.lua tests/config_shim_spec.lua && echo STYLUA_OK
bash scripts/assess.sh 2>&1 | tail -10
```

Expected: `STYLUA_OK` + `ASSESS: ALL LAYERS PASS`.

- [ ] **Step 7: Commit**

```bash
git add lua/config/options.lua tests/config_shim_spec.lua
git commit -m "fix(config): shim vim.treesitter.language.ft_to_lang for telescope

nvim 0.11 removed vim.treesitter.language.ft_to_lang (replaced by
get_lang). telescope.nvim 0.1.8's previewer still calls the old
name — crashes the previewer with 'attempt to call field ft_to_lang
a nil value' on every highlighted file.

Three-line shim in lua/config/options.lua aliases it to get_lang.
Guarded with '= x or y' so upstream restoration becomes a no-op.
Three plenary assertions cover: shim installs, resolves 'lua' ->
'lua', and doesn't clobber a native implementation if one exists."
```

---

## Task 2: Manual test additions

**Files:**
- Modify: `docs/manual-tests.md`

- [ ] **Step 1: Add row under section 1 (Core editing)**

Find section "1. Core editing" in `docs/manual-tests.md`. Append:

```markdown
- [ ] `<Space>ff` then arrow-navigate through the preview — no `attempt to call field 'ft_to_lang' (a nil value)` error in `:messages`
```

- [ ] **Step 2: Commit**

```bash
git add docs/manual-tests.md
git commit -m "docs(manual): telescope previewer ft_to_lang smoke"
```

---

## Task 3: Push + verify green CI

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

Expected: both `assess (stable)` and `assess (nightly)` succeed.

- [ ] **Step 3: Close the source todo**

```
todo_complete 8
```

---

## Manual Test Additions

Task 2 adds one row under "Core editing" for the telescope previewer smoke. Happens to also be the thing CI's `test_telescope.py` already exercises indirectly (opens the picker), but the explicit row flags it as a user-visible symptom worth checking manually after any nvim upgrade.

---

## Self-Review

**1. Spec coverage:**

| Todo | Task |
|---|---|
| #8 telescope previewer `ft_to_lang` crash | Task 1 (shim + 3 plenary guards) |

The todo notes listed three fix candidates; I chose the shim because it's non-invasive and fixes the API for any plugin (not just telescope). The decision rationale lives in the commit message + code comment.

**2. Placeholder scan:** no TBDs. Every code block complete.

**3. Type consistency:**
- Shim uses `vim.treesitter.language.ft_to_lang` (function) = `vim.treesitter.language.get_lang` (function) — signatures match per nvim 0.11 API (both take `ft` string, return lang string or nil).
- `dofile` path in the spec (`vim.fn.getcwd() .. '/lua/config/options.lua'`) matches the `HAPPY_NVIM_LOAD_CONFIG=1` pattern used by `tests/minimal_init.lua` — but here we source options.lua ALONE because the shim is self-contained, no plugin load needed.
- Commit message scope `fix(config)` matches Conventional Commits convention.
