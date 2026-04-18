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

## Sandbox note

When running under Claude Code's bubblewrap sandbox:

- Writes under `~/.git/config` of the main repo may fail with
  "Device or resource busy" — use `git push <url> main:main` directly
  (no `remote add`) to sidestep. Main push path is already
  documented in every plan's final push task.
- Integration tests redirect `XDG_*_HOME` to a scratch tmpdir so nvim
  state never leaks into the user's `~/.local/share/nvim`. See
  `tests/integration/conftest.py`.
