# UX Micro-Batch (Design Spec)

**Status:** design approved 2026-04-19
**Scope:** five small user-visible UX fixes from the 2026-04-19 revdiff
pass (parent todo `30`). Batched because each is <30 LOC and they're all
config/docs tweaks — no new modules, no cross-coupling.

Fixes:
- 30.4 — `<leader>ck` prompt loops on blank Enter ("spams on number")
- 30.7 — precognition motion-hint overlay should be opt-in, not on by default
- 30.9 — undotree has no in-nvim hints ("no idea how to use it")
- 30.10 — fugitive `:Git` has no in-nvim hints (same feedback)
- 30.11 — `<leader>?` cheatsheet is thin; missing remote / claude / SP1-cockpit entries

## 1. Problem

### 30.4 — prompt loop on `<leader>ck`

`lua/plugins/tmux.lua:86-93` uses `vim.ui.select({'Yes, kill it', 'No,
cancel'}, ...)`. The default Neovim backend for `vim.ui.select` is
`vim.fn.inputlist()`, which prompts at the bottom of the screen with
`Type number and <Enter> (q or empty cancels):`. Pressing `<Enter>` with
no input redraws the same prompt instead of cancelling cleanly. To the
user this reads as "it keeps spamming the question." The rest of the
codebase already uses `vim.fn.confirm(msg, '&Yes\n&No') == 1` for this
shape of decision (`lua/tmux/send.lua:93`) — consistent pattern + no
prompt loop.

### 30.7 — precognition overlay always-on

`lua/plugins/precognition.lua:6` sets `opts.startVisible = true`. Cold
nvim boot shows `w / b / e / $ / ^ / %` overlays on every line the
cursor sits on. User validates that it works but wants it off by
default — "more info than I want while focused, give me a way to turn it
on when I'm exploring motions."

A toggle keymap already exists: `<leader>?p → <cmd>Precognition toggle<cr>`.
Flipping the default is a one-line change.

### 30.9 — undotree discoverability

`lua/plugins/undotree.lua` wires `<leader>u → :UndotreeToggle`. The
undotree window has `?` for in-pane help + `j/k/Enter` navigation, but
happy-nvim's cheatsheet doesn't surface any of this. User's reaction:
"yes, but no idea how to use it."

### 30.10 — fugitive discoverability

`lua/plugins/fugitive.lua` wires `<leader>gs → :Git` (status split).
Inside the status pane, fugitive has ~10 core keys (`s u = cc dv P ` etc.)
but again none are in the coach cheatsheet. Same user feedback pattern.

### 30.11 — cheatsheet thin

`lua/coach/tips.lua` currently covers text-objects / motions / macros /
marks / registers / search — pure-vim mechanics. It does NOT cover any
happy-nvim-specific keymaps (the `<leader>c*`, `<leader>s*`, `<leader>P*`,
`<leader>C*` clusters). Manual-test row 35: "yes, but I feel like there
should be more stuff there."

## 2. Solution (one-line each)

- 30.4 — swap `vim.ui.select` → `vim.fn.confirm(...) == 1` in
  `lua/plugins/tmux.lua:86-93`.
- 30.7 — set `opts.startVisible = false` in
  `lua/plugins/precognition.lua:6`.
- 30.9 + 30.10 — append category-tagged entries to `lua/coach/tips.lua`
  for undotree and fugitive.
- 30.11 — append entries to `lua/coach/tips.lua` for the remote / claude /
  projects / capture clusters.

## 3. Architecture

No new modules. Three existing files edited:

```
 lua/
   plugins/
     tmux.lua              [MODIFIED — lines 86-93: confirm instead of ui.select]
     precognition.lua      [MODIFIED — line 6: startVisible = false]
   coach/
     tips.lua              [MODIFIED — +~23 entries across 6 categories]
 docs/manual-tests.md       [MODIFIED — 3 new rows]
 tests/integration/
   test_claude_ck_no_loop.py [NEW — regression for 30.4]
   test_precognition_default_off.py [NEW — 30.7 smoke]
   test_coach_tips_coverage.py [NEW — 30.9+30.10+30.11 keymap-vs-tips audit]
```

## 4. Fix 1 details (30.4) — `<leader>ck` confirm

**File:** `lua/plugins/tmux.lua:78-96`

Current body:

```lua
{
  '<leader>ck',
  function()
    local popup = require('tmux.claude_popup')
    if not popup.exists() then
      vim.notify('no Claude session for this project', vim.log.levels.INFO)
      return
    end
    vim.ui.select({ 'Yes, kill it', 'No, cancel' }, {
      prompt = "Kill current project's Claude session?",
    }, function(choice)
      if choice == 'Yes, kill it' then
        popup.kill()
        vim.notify('killed ' .. require('tmux.project').session_name(), vim.log.levels.INFO)
      end
    end)
  end,
  desc = "Claude: kill current project's session",
},
```

New body:

```lua
{
  '<leader>ck',
  function()
    local popup = require('tmux.claude_popup')
    if not popup.exists() then
      vim.notify('no Claude session for this project', vim.log.levels.INFO)
      return
    end
    if vim.fn.confirm("Kill current project's Claude session?", '&Yes\n&No') == 1 then
      popup.kill()
      vim.notify('killed ' .. require('tmux.project').session_name(), vim.log.levels.INFO)
    end
  end,
  desc = "Claude: kill current project's session",
},
```

`vim.fn.confirm` uses a native Y/N dialog (mnemonic-keyed), so
`<Enter>` on the default choice doesn't loop. Matches pattern already in
`lua/tmux/send.lua:93`.

**Test:** integration test with XDG-isolated nvim that loads user
config, stubs `vim.fn.confirm` with a counter closure, and
`require('tmux.claude_popup').exists` returning `true` + `.kill` stubbed
with a counter. Triggers the `<leader>ck` keymap callback via
`vim.api.nvim_feedkeys` (or invokes the spec's function body directly
with a package-level lookup). Asserts (a) `vim.fn.confirm` was called
exactly once, (b) `vim.ui.select` was NOT called, (c) when
`confirm()` returns 1, `popup.kill` was called once.

**Manual test row:**
- `<leader>ck` with active claude session → Y/N dialog at bottom. `<Y>`
  or `<Enter>` kills, `<N>` cancels. Pressing `<Enter>` repeatedly never
  loops (30.4).

## 5. Fix 2 details (30.7) — precognition off by default

**File:** `lua/plugins/precognition.lua:6`

```diff
   opts = {
-    startVisible = true,
+    startVisible = false,
     showBlankVirtLine = true,
     hints = {
```

`<leader>?p` toggles via the existing keymap.

**Test:** integration test loads user config, calls
`require('lazy').plugins()` (or directly `require('precognition').setup`
via the spec's `opts`), asserts `opts.startVisible == false`. Or:
simpler — read the file with `vim.fn.readfile` and assert the literal
`startVisible = false` token is present. I prefer the file-read approach
because it's resilient to how Lazy interprets the spec.

**Manual test row:**
- Cold `nvim` open on a `.lua` file → no `w / b / e / $ / ^ / %` overlays.
  `<leader>?p` toggles them on. Second `<leader>?p` toggles off (30.7).

## 6. Fix 3 + 4 details (30.9, 30.10, 30.11) — tips coverage

**File:** `lua/coach/tips.lua`

Append 23 entries across 6 categories. Categories `undo` and `capture`
are new; the others extend existing `git` category or add new
`remote`/`claude`/`projects` categories.

```lua
-- undotree (<leader>u) — 30.9
{ keys = '<leader>u', desc = 'open undotree panel', category = 'undo' },
{ keys = '? (in undotree)', desc = 'show undotree help', category = 'undo' },
{ keys = 'j/k (in undotree)', desc = 'navigate revisions up/down', category = 'undo' },
{ keys = '<Enter> (in undotree)', desc = 'jump buffer to selected revision', category = 'undo' },
{ keys = 'd (in undotree)', desc = 'diff selected revision vs current', category = 'undo' },

-- fugitive (<leader>gs / :Git) — 30.10
{ keys = '<leader>gs', desc = 'open Git status split (fugitive)', category = 'git' },
{ keys = 's (in :Git)', desc = 'stage file under cursor', category = 'git' },
{ keys = 'u (in :Git)', desc = 'unstage file under cursor', category = 'git' },
{ keys = '= (in :Git)', desc = 'toggle inline diff under cursor', category = 'git' },
{ keys = 'cc (in :Git)', desc = 'start commit (opens commit msg buffer)', category = 'git' },
{ keys = 'ca (in :Git)', desc = 'commit --amend', category = 'git' },

-- remote (<leader>s*) — 30.11
{ keys = '<leader>ss', desc = 'ssh host picker (frecency-ordered)', category = 'remote' },
{ keys = '<leader>sd', desc = 'remote dir picker (zoxide-like, 7d cache)', category = 'remote' },
{ keys = '<leader>sB', desc = 'open remote file as scp:// buffer', category = 'remote' },
{ keys = '<leader>sg', desc = 'remote grep (nice/ionice over ssh) → quickfix', category = 'remote' },

-- claude tmux (<leader>c*) — 30.11
{ keys = '<leader>cc', desc = 'open/attach project claude session (cc-<id>)', category = 'claude' },
{ keys = '<leader>cp', desc = 'popup claude for current project (SP1: remote-sandboxed if remote)', category = 'claude' },
{ keys = '<leader>cf', desc = 'send current file as @path to claude', category = 'claude' },
{ keys = '<leader>cs', desc = 'send visual selection (fenced w/ file:L-L header)', category = 'claude' },
{ keys = '<leader>ce', desc = 'send LSP diagnostics for current buffer', category = 'claude' },
{ keys = '<leader>cl', desc = 'list claude sessions (telescope picker)', category = 'claude' },
{ keys = '<leader>cn', desc = 'new named claude session (prompts for slug)', category = 'claude' },
{ keys = '<leader>ck', desc = "kill current project's claude session (Y/N confirm)", category = 'claude' },

-- projects / cockpit (<leader>P*) — 30.11 (SP1 surface)
{ keys = '<leader>P', desc = 'projects picker — pivot / peek / add / forget', category = 'projects' },
{ keys = '<leader>Pa', desc = 'add project (prompt for /path or host:path)', category = 'projects' },
{ keys = '<leader>Pp', desc = 'peek project scrollback (no pivot)', category = 'projects' },
{ keys = ':HappyWtProvision <path>', desc = 'provision worktree claude (async, scratch buffer output)', category = 'projects' },
{ keys = ':HappyWtCleanup <path>', desc = 'cleanup worktree claude (async)', category = 'projects' },

-- capture (<leader>C*) — SP1 remote→claude one-way data flow
{ keys = '<leader>Cc', desc = 'capture remote pane → sandbox file (sandboxed claude reads)', category = 'capture' },
{ keys = '<leader>Ct', desc = 'toggle tail-pipe from remote pane → sandbox live.log', category = 'capture' },
{ keys = '<leader>Cl', desc = 'pull remote file via scp → sandbox dir', category = 'capture' },
{ keys = '<leader>Cs', desc = 'send visual selection → sandbox file (from ssh pane buffer)', category = 'capture' },
```

Total additions: 31 entries (5 undo + 6 git + 4 remote + 8 claude + 5
projects + 4 capture — the 31-count corrects the spec-summary "+23"
above; authoritative count is 31 entries).

**Test:** integration test loads `require('coach.tips')`, asserts:
- `#tips > PRIOR_COUNT` (non-brittle: just "grew").
- For each new category (`undo`, `remote`, `claude`, `projects`,
  `capture`) — at least one entry exists with that `category` field.
- For a hand-picked subset of keymaps that MUST be surfaced
  (`<leader>ss`, `<leader>cc`, `<leader>P`, `<leader>Cc`), there's a
  matching row in `tips` (by `keys` field).

The test is a coverage audit — catches future regressions where someone
adds a new keymap cluster but forgets to update tips.

**Manual test row:**
- `<leader>?` cheatsheet opens → type `remote`, `claude`, `projects`,
  `capture`, `undo`, or `git` → results show the respective entries
  listed above (30.9, 30.10, 30.11).

## 7. Testing summary

**Integration (pytest):**

1. `tests/integration/test_claude_ck_no_loop.py` — stub
   `vim.fn.confirm` + `tmux.claude_popup` (via `package.loaded`),
   dispatch `<leader>ck` keymap callback directly, assert no loop +
   `popup.kill` called exactly once on Yes. Second case: `confirm`
   returns 2 (No) → `popup.kill` NOT called.
2. `tests/integration/test_precognition_default_off.py` — read the file
   with `vim.fn.readfile` from headless nvim, assert the literal pattern
   `startVisible = false` is present and `startVisible = true` is NOT.
3. `tests/integration/test_coach_tips_coverage.py` — coverage audit
   (assertions above).

**Manual tests:** three rows appended to `docs/manual-tests.md`
§ 11 (new section — Bug batch is in §10).

## 8. Out of scope

- Auditing every manual-test row and converting to automated tests
  (tracked separately as todo 31 — "Audit docs/manual-tests.md").
- Swapping the whole codebase from `vim.ui.select` to `vim.fn.confirm`
  (only `<leader>ck` is user-visible; other ui.select sites like the
  telescope pickers have proper backends already).
- Installing a ui.select backend plugin (`dressing.nvim`,
  `folke/snacks.nvim`) — deferred; solves 30.4 but adds a dep.
- Rewriting precognition config to show hints only while in visual
  mode (user just wants off-by-default; that's sufficient).

## 9. Rollout

Single push to `main`. Additive — no deprecations. The precognition
default-off change is the only behavior flip a returning user might
notice; `<leader>?p` restores prior behavior per-session.

## 10. Open questions

None.

## Manual Test Additions

Three rows appended to `docs/manual-tests.md` (new `§ 11. UX micro-batch
2026-04-19` section, immediately after §10):

```
- [ ] `<leader>ck` with active claude session → Y/N dialog at bottom. `<Y>`
      or `<Enter>` kills, `<N>` cancels. Pressing `<Enter>` repeatedly
      never loops (30.4)
- [ ] Cold `nvim` open on a `.lua` file → no `w / b / e / $ / ^ / %`
      overlays. `<leader>?p` toggles them on. Second `<leader>?p`
      toggles off (30.7)
- [ ] `<leader>?` cheatsheet opens → type `remote`, `claude`, `projects`,
      `capture`, `undo`, or `git` → results show the respective
      keybindings (30.9, 30.10, 30.11)
```
