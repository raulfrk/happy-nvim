# Contributing to happy-nvim

## Development setup

You'll want these tools on `$PATH` before committing changes:

| Tool | Purpose | Install |
|------|---------|---------|
| `stylua` | lua formatter (CI runs `--check .`) | `cargo install stylua` or `npm install -g @johnnymorganz/stylua-bin` |
| `selene` | lua linter (CI runs `selene .`) | `cargo install selene` or [binary release](https://github.com/Kampfkarren/selene/releases) |
| `pytest` | integration test runner | `pip install --user pytest` or `apt install python3-pytest` |
| `tmux` >= 3.2 | integration test harness | distro package; needed for `scripts/test-integration.sh` |
| `tree-sitter` | parser builder | `npm install -g tree-sitter-cli` |

If you're on a box without a rust toolchain and don't want to install one,
the npm route works for stylua; selene has a binary release at
[Kampfkarren/selene/releases](https://github.com/Kampfkarren/selene/releases)
you can drop into `~/.local/bin/`.

## Before you push

The one-button check is:

```bash
bash scripts/assess.sh
```

This runs every verification layer (shell syntax, python syntax, init
bootstrap, plenary unit tests, pytest integration, `:checkhealth`) and
prints a pass/fail table. Exits nonzero if any layer fails.

Individual layers if you want finer control:

```bash
stylua --check .                          # formatting
selene .                                  # linting
python3 -m pytest tests/integration/ -v   # integration suite
nvim --headless -u tests/minimal_init.lua \
  -c "PlenaryBustedDirectory tests/" -c 'qa!'   # plenary unit tests
```

## Commit conventions

We use Conventional Commits (see the existing log). Types we use:

| Type | When |
|------|------|
| `feat` | new feature or new file under `lua/` or `scripts/` |
| `fix` | behavior change for a reported or latent bug |
| `test` | new or updated tests, no production code change |
| `docs` | README, CONTRIBUTING, plan docs, manual-tests |
| `chore` | tool config, CI tweaks, lockfile updates |
| `style` | formatter-only changes (usually via stylua run) |
| `refactor` | no behavior change, code reorganization |
| `perf` | measured perf improvement |
| `ci` | GitHub Actions workflow changes |

Scope goes in parens after the type: `feat(tmux/claude_popup): ...`.

## Workflow: implementation plans

User-visible changes go through `superpowers:writing-plans`. Plans live
under `docs/superpowers/plans/YYYY-MM-DD-<topic>.md`. Every plan that adds
a new keymap / command / UI surface MUST include a "Manual Test Additions"
section listing rows to append to `docs/manual-tests.md`.

## Process rules

Two rules every PR follows:

1. **Every plan** under `docs/superpowers/plans/` ends with a
   `## Manual Test Additions` section listing the rows the
   implementing work appends to `docs/manual-tests.md`. Plans for
   pure internal changes may state *"No manual test additions —
   internal change."* instead.
2. **Every user-visible change** (new keymap, new command, UI change)
   appends a row to `docs/manual-tests.md` in the same commit.

Full text lives in [`CLAUDE.md`](./CLAUDE.md) at the repo root (Claude
Code auto-loads it for agent sessions; humans read it there too).

## Manual testing

`docs/manual-tests.md` is the living checklist contributors walk through
before cutting a release. Rows marked `(CI-covered)` are also exercised
by pytest in `tests/integration/`, so you can skim those.
