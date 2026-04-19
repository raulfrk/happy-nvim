# P1 Non-Tmux Bug Batch (Design Spec)

**Status:** design approved 2026-04-19
**Scope:** three small, independent user-visible bugs surfaced in the
2026-04-19 manual-test revdiff pass (parent todo `30`). Batched into one
spec/plan/commit-cycle because each fix is <30 LOC and all are mechanical.

Fixes:
- 30.1 — `:checkhealth happy-nvim` reports "No healthcheck found"
- 30.5 — Opening a `.lua` file errors "error running selenium. No file or directory"
- 30.6 — `:LspInfo` is "not an editor command" on nvim 0.12

## 1. Problem

### 30.1 — health check invocation mismatch

`lua/happy/health.lua` exists and implements `M.check()` with sections for
core, local CLIs, tmux, claude integration, etc. `:checkhealth` resolves
`:checkhealth NAME` by looking for `lua/NAME/health.lua` (Lua-namespaced) or
`autoload/health/NAME.vim` (Vim-script) on `&runtimepath`. The plugin's
canonical Lua namespace is `happy` (matching the dir `lua/happy/`). So
`:checkhealth happy` works; `:checkhealth happy-nvim` fails because there is
no `lua/happy-nvim/health.lua`.

Users naturally type the repo/plugin name (`happy-nvim`), not the Lua
namespace (`happy`). The manual-test rows we just shipped, and the earlier
ones (line 65, line 105), both used the repo-name form.

### 30.5 — lint autocmd fires selene unconditionally

`lua/plugins/lint.lua` registers a single `lint.linters_by_ft.lua = {'selene'}`
and calls `lint.try_lint()` on every `BufReadPost` / `BufWritePost`. When
selene's binary isn't on `$PATH` (fresh install before `:Mason` finishes
pulling `selene`, or a user who opted out of the mason tool install), the
lint call spams errors. mason-tool-installer lists selene in
`ensure_installed`, but the install is async and racey with the first
file-open.

### 30.6 — `:LspInfo` missing on nvim 0.12+

`nvim-lspconfig` removed `:LspInfo` in favor of the built-in
`vim.lsp.get_clients()` + `:checkhealth vim.lsp`. happy-nvim pins a recent
lspconfig (via Lazy defaults) so `:LspInfo` is gone on nvim 0.12+.
`conform.nvim` still drives `:w` → ruff_format independently, which is why
users see "`:w` works, `:LspInfo` doesn't."

Users expect a one-line cmd to check "what LSP is attached to my buffer?"
The upstream answer is `:checkhealth vim.lsp`, but that's a huge report
when the user wants a single line.

## 2. Solution (one-line each)

- 30.1 — add a 1-line alias file `lua/happy-nvim/health.lua` that
  `return require('happy.health')`. Both invocation forms now work.
- 30.5 — make `lua/plugins/lint.lua`'s autocmd filter `linters_by_ft` by
  `vim.fn.executable` at callback time; only runnable linters fire.
- 30.6 — add a `:HappyLspInfo` user command (in `lua/plugins/lsp.lua`'s
  `config` block) that prints attached-client names/root-dir for the
  current buffer via `vim.lsp.get_clients({bufnr = 0})`.

## 3. Architecture

No new modules. Three edits:

```
 lua/
   happy-nvim/
     health.lua           [NEW — 1 line: return require('happy.health')]
   plugins/
     lint.lua             [MODIFIED — filter linters by executable]
     lsp.lua              [MODIFIED — +:HappyLspInfo user command]
 docs/manual-tests.md     [MODIFIED — 3 new rows in §9 or a new §10]
 tests/
   integration/
     test_lint_missing_binary.py   [NEW — stub executable()=0, assert try_lint skipped]
     test_happy_lsp_info.py        [NEW — smoke: cmd registered + runs]
```

## 4. Fix 1 details (30.1) — health alias

**File:** `lua/happy-nvim/health.lua`

```lua
-- `:checkhealth happy-nvim` alias. The canonical implementation lives at
-- `lua/happy/health.lua` (Lua namespace `happy`); this shim lets
-- `:checkhealth happy-nvim` find the same health module when users type
-- the repo name instead of the Lua namespace.
return require('happy.health')
```

**Test:** smoke via
`nvim --headless -c "checkhealth happy-nvim" -c "qa!"` — asserting the
stdout does NOT contain `"No healthcheck found"`. CI already runs the same
check for `:checkhealth happy-nvim` in `assess.sh`'s checkhealth layer —
landing this change will turn that layer's rendering into the real health
sections rather than the error line.

**Manual test row:**
- `:checkhealth happy-nvim` renders sections (core / local CLIs / tmux /
  claude integration / etc.) without the "no healthcheck found" error.

## 5. Fix 2 details (30.5) — executable-guarded lint

**File:** `lua/plugins/lint.lua`

Replace the current autocmd body:

```lua
vim.api.nvim_create_autocmd({ 'BufWritePost', 'BufReadPost' }, {
  group = vim.api.nvim_create_augroup('happy_lint', { clear = true }),
  callback = function()
    lint.try_lint()
  end,
})
```

With:

```lua
vim.api.nvim_create_autocmd({ 'BufWritePost', 'BufReadPost' }, {
  group = vim.api.nvim_create_augroup('happy_lint', { clear = true }),
  callback = function()
    local linters = lint.linters_by_ft[vim.bo.filetype] or {}
    local runnable = vim.tbl_filter(function(l)
      return vim.fn.executable(l) == 1
    end, linters)
    if #runnable > 0 then
      lint.try_lint(runnable)
    end
  end,
})
```

**Behavior:**
- Selene installed → `try_lint({'selene'})` — unchanged.
- Selene missing → `try_lint` not called, no error spam.
- Tool-installer finishes mid-session → next save picks up selene
  automatically (the check is at callback time, not at plugin setup).

**Test:** integration test stubs `vim.fn.executable` to return `0` for
`selene`, opens a `.lua` file, asserts no error was emitted (check
`vim.v.errmsg` stays empty). Also asserts when executable returns `1`,
`lint.try_lint` is called with `{'selene'}`.

**Manual test row:**
- Open a `.lua` file on a machine without selene installed → no error
  message in `:messages`.

## 6. Fix 3 details (30.6) — `:HappyLspInfo`

**File:** `lua/plugins/lsp.lua` — inside the `neovim/nvim-lspconfig` block's
existing `config = function() ... end`, add near the end (after the
`LspAttach` autocmd block):

```lua
vim.api.nvim_create_user_command('HappyLspInfo', function()
  local clients = vim.lsp.get_clients({ bufnr = 0 })
  if #clients == 0 then
    vim.notify('No LSP clients attached to this buffer.', vim.log.levels.INFO)
    return
  end
  for _, c in ipairs(clients) do
    print(('• %s (id=%d, root=%s)'):format(c.name, c.id, c.config.root_dir or '?'))
  end
end, { desc = 'Show attached LSP clients (0.12-safe replacement for :LspInfo)' })
```

**Test:** integration test opens a `.py` file, waits for LSP attach (we
have an `ensure_installed=ruff` via mason → pyright isn't pinned but ruff
LSP via conform covers the format path — actual LSP attach tests live at
`test_lsp_format.py` which is currently SKIPPED in CI; don't re-enable
here). Instead: smoke test asserting
`vim.fn.exists(':HappyLspInfo') == 2` in a minimal headless nvim.

**Manual test row:**
- Open any file with an LSP attached (`:e some.py`), run `:HappyLspInfo` →
  one line per attached client, format `• <name> (id=<n>, root=<path>)`.
- On a buffer with no LSP: `:HappyLspInfo` prints "No LSP clients attached
  to this buffer."

## 7. Testing summary

**Unit (plenary):** none — all three changes are too thin for a pure-Lua
unit test (shim file, autocmd filter, user command).

**Integration (pytest, `tests/integration/`):**

1. `test_lint_missing_binary.py` — headless nvim loads user config, then
   monkey-patches `vim.fn.executable` to return `0` via a Lua snippet
   (`vim.fn.executable = function(_) return 0 end`), then writes a scratch
   `.lua` file and triggers `BufReadPost`. Before the autocmd fires, the
   test stubs `require('lint').try_lint` with a counter closure that
   increments a `vim.g.happy_lint_called` counter. After triggering, the
   test reads `vim.g.happy_lint_called` via `nvim_get_var` — it must be 0.
   `vim.v.errmsg` must also stay empty. Second assertion in the same test:
   restore `executable = function(l) return l == 'selene' and 1 or 0 end`,
   re-trigger, `happy_lint_called == 1`.
2. `test_happy_lsp_info.py` — headless nvim with user config loaded;
   execute the LspAttach-block's `config = function()` by opening any
   filetype that triggers `BufReadPre` on a `.py` buffer (creates the
   autocmd trampoline); assert `vim.fn.exists(':HappyLspInfo') == 2`. No
   need to actually attach an LSP — command registration happens at
   `config = function()` time, not at LspAttach.

**Checkhealth layer (assess.sh):** already exercises `:checkhealth
happy-nvim` via the scratch-config bootstrap. Adding the alias file makes
the existing layer produce real health output. The implementing subagent
greps assess.sh stdout for the literal string `ok Neovim >= 0.11` (emitted
by `happy.health.check()`'s first `h.ok` call) — presence of that line
proves the health module ran end-to-end.

**Manual tests:** three rows appended to `docs/manual-tests.md`.

## 8. Out of scope

- Fixing the manual-test rows from pre-SP1 that mention `:checkhealth
  happy-nvim` (line 65/105) — the alias lands the fix; no text change
  needed there unless we want to also mention `:checkhealth happy` as an
  equivalent form.
- Re-enabling `test_lsp_format.py` (SKIPPED) — separate debt.
- Any tmux / remote work (deferred to SP2/SP3/SP4).
- Replacing selene with another linter.

## 9. Rollout

Single PR / single push to `main`. No feature flag. Additive fixes — no
user-facing deprecations.

## 10. Open questions

None after this design.

## Manual Test Additions

Three rows appended to `docs/manual-tests.md` (inside existing §9
"Multi-project cockpit (SP1)" or a new §10 "Bug batch 2026-04-19" — the
plan picks one and the implementing subagent enforces it):

```
- [ ] `:checkhealth happy-nvim` renders sections (core / local CLIs / tmux /
      claude integration) without "no healthcheck found" (30.1)
- [ ] Open a `.lua` file on a machine without `selene` installed → no error
      in `:messages` (30.5)
- [ ] `:HappyLspInfo` in a buffer with an attached client lists `•
      <name> (id=<n>, root=<path>)`; in a buffer with no client, prints
      "No LSP clients attached to this buffer." (30.6)
```
