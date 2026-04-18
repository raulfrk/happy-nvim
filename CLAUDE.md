# happy-nvim — Project Rules for Claude Code

These rules apply to any Claude Code session working in this repo.
Human contributors should read `CONTRIBUTING.md` for the same conventions.

## Plan files

- Every implementation plan lives at
  `docs/superpowers/plans/YYYY-MM-DD-<topic>.md`.
- Every plan ends with a `## Manual Test Additions` section listing new
  rows to append to `docs/manual-tests.md`. The implementing subagent
  appends those rows as part of its final commit.
- Plans whose features don't add/change user-visible surfaces (pure
  internal refactors, test-only changes) may state *"No manual test
  additions — internal change."* in that section instead.

## Manual-tests checklist

- `docs/manual-tests.md` is the living smoke checklist contributors walk
  through before cutting a release. Rows cover features CI can't reach
  (real `claude` CLI, real SSH, host clipboard, Nerd Font rendering).
- **After any commit that adds or changes a user-visible surface**
  (new `<leader>*` keymap, new `:Happy*` command, new tmux integration,
  UI change), append one or more rows to `docs/manual-tests.md` in the
  same commit (or the immediately-following commit if the feature is
  split across files).
- Mark rows as `(CI-covered)` when a corresponding pytest integration
  test in `tests/integration/` exercises the same behavior.

## Workflow

1. User requests a change →  use `superpowers:brainstorming` to design.
2. Design approved → `superpowers:writing-plans` to emit the plan file.
3. Plan committed → `superpowers:subagent-driven-development` dispatches
   fresh subagents per task; parent-session coordinates + runs CI.
4. Every final commit pushes + polls CI via `gh api`. Close related
   todos via `mcp__plugin_proj_proj__todo_complete` only after CI green.

## Pre-push check

One-button validator: `bash scripts/assess.sh`. Runs every layer
(shell/python syntax, init bootstrap, plenary, pytest integration,
`:checkhealth`) and prints a pass/fail table. Must pass before push.

## Commit style

- Conventional Commits (see `CONTRIBUTING.md` table for types we use).
- Body is optional; use it only when the *why* isn't obvious from the
  subject line. Reasons > restating the diff.
- Never mention Claude Code or AI assistance in the commit body — keep
  the log implementation-focused.

## Subprocess hygiene

- Use `vim.system(cmd, opts, on_exit)` (callback form) for any subprocess
  that may run longer than ~1 second. Reserve `vim.system(cmd):wait()`
  for operations guaranteed to finish sub-second (e.g. `tmux
  set-option`, `tmux display-message`, `tmux new-session -d`) AND where
  the caller needs the result synchronously.
- Why: `:wait()` blocks nvim's main thread for the subprocess's full
  lifetime. During the block, `vim.uv.timer` callbacks don't fire,
  `vim.schedule` queued fns don't run, and the UI freezes. This
  starves the idle watcher (`lua/tmux/idle.lua`) and every other
  timer-driven feature. Verified empirically on nvim 0.12.1: a
  300ms-interval timer fires 0 times during a 2-second blocking
  `vim.system({'sleep','2'}):wait()`.
- Reference fix: commit `ebf0846` converted
  `lua/tmux/claude_popup.lua:M.open` from `:wait()` to the callback
  form so idle notifications fire while the popup is open.
- Regression tests for the pattern: `tests/tmux_claude_popup_spec.lua`
  (stubs `vim.system`, asserts `open()` passes a callback) +
  `tests/integration/test_idle_alert_during_popup.py` (drives the real
  `vim.uv.timer` while an async subprocess is pending).

## Sandbox note

When running under Claude Code's bubblewrap sandbox:

- Writes under `~/.git/config` of the main repo may fail with
  "Device or resource busy" — use `git push <url> main:main` directly
  (no `remote add`) to sidestep. Main push path is already
  documented in every plan's final push task.
- Integration tests redirect `XDG_*_HOME` to a scratch tmpdir so nvim
  state never leaks into the user's `~/.local/share/nvim`. See
  `tests/integration/conftest.py`.
