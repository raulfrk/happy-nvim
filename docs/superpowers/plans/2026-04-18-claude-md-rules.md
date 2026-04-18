# Project CLAUDE.md Rules Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Codify two process rules — "every plan includes Manual Test Additions section" and "every user-visible feature appends rows to `docs/manual-tests.md`" — as a project-level `CLAUDE.md` so future Claude sessions (and human contributors) auto-apply them without being retold. Reference the rules from `CONTRIBUTING.md` so non-Claude contributors find them too.

**Architecture:** Claude Code auto-loads `CLAUDE.md` at repo root into every session's context. The rules live there as terse instructions with examples. `CONTRIBUTING.md` gets a "Process rules for contributors" subsection pointing at `CLAUDE.md` so humans reading the contributing doc learn the conventions. No runtime code; pure docs that change future behavior.

**Tech Stack:** Markdown only.

---

## File Structure

```
CLAUDE.md                 # NEW — repo-level rules Claude auto-loads
CONTRIBUTING.md           # MODIFIED — point at CLAUDE.md's process rules
```

---

## Task 1: Write `CLAUDE.md` at repo root

**Files:**
- Create: `CLAUDE.md`

**Context:** Claude Code merges any repo-root `CLAUDE.md` into the session's instructions on startup. Keep it short + imperative — bullets, not prose. Two rules to codify:

1. **Plan convention**: every `docs/superpowers/plans/*.md` must contain a `## Manual Test Additions` section listing new rows the implementing subagent appends to `docs/manual-tests.md`.
2. **Feature-lands rule**: after any PR that adds/changes a user-visible surface (new keymap, new command, UI change), Claude must append one or more rows to `docs/manual-tests.md` in the same commit.

We also capture a couple of already-adopted conventions observed across existing plans (subagent-driven execution, caveman commit messages, `bash scripts/assess.sh` pre-push). Those are lessons from the last ~40 plans; codifying them prevents drift.

- [ ] **Step 1: Write `CLAUDE.md`**

Create `/home/raul/worktrees/happy-nvim/feat-v1-implementation/CLAUDE.md`:

```markdown
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
```

- [ ] **Step 2: Commit**

```bash
cd /home/raul/worktrees/happy-nvim/feat-v1-implementation
git add CLAUDE.md
git commit -m "docs(claude): project-level CLAUDE.md w/ process rules

Codifies two conventions we've been following ad-hoc:
1. Every plan ends with a 'Manual Test Additions' section.
2. Every user-visible feature PR appends to docs/manual-tests.md
   in the same commit.

Plus reference documentation for the end-to-end workflow
(brainstorming -> writing-plans -> subagent-driven-development),
assess.sh pre-push, commit style, and the push-by-url sandbox
workaround. Claude Code auto-loads CLAUDE.md at session start;
humans should read CONTRIBUTING.md which points back here."
```

---

## Task 2: Cross-reference from `CONTRIBUTING.md`

**Files:**
- Modify: `CONTRIBUTING.md`

**Context:** Human contributors looking at `CONTRIBUTING.md` should discover the same rules. Add a small subsection pointing at `CLAUDE.md` so nothing is documented twice.

- [ ] **Step 1: Append the cross-reference**

Find `CONTRIBUTING.md` and locate the "## Workflow: implementation plans" section. After that section, before "## Manual testing", insert:

```markdown

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
```

- [ ] **Step 2: Commit**

```bash
git add CONTRIBUTING.md
git commit -m "docs(contributing): point at CLAUDE.md for process rules

Two-rule summary inline (plans have Manual Test Additions section;
features update docs/manual-tests.md in-commit), full text stays in
CLAUDE.md so we don't diverge between the human + AI entry points."
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

Expected all `success`. Doc-only changes; CI should be fast.

- [ ] **Step 3: Close source todos**

```
todo_complete 6.2 6.4
```

---

## Manual Test Additions

None — CLAUDE.md and CONTRIBUTING.md are internal documentation for
contributors; no user-visible feature change. The manual-tests checklist
doesn't need new rows for this plan.

---

## Self-Review

**1. Spec coverage:**

| Todo | Task |
|---|---|
| #6.2 writing-plans convention (Manual Test Additions section) | Task 1 (rule #1 in CLAUDE.md) + Task 2 (cross-ref) |
| #6.4 Claude auto-updates manual-tests.md on feature-lands | Task 1 (rule #2 in CLAUDE.md) + Task 2 (cross-ref) |

**2. Placeholder scan:** no TBDs. All text is final.

**3. Type consistency:**
- File paths (`docs/superpowers/plans/`, `docs/manual-tests.md`, `scripts/assess.sh`) match the actual repo layout.
- Section headings in `CONTRIBUTING.md` Task 2 Step 1 match the existing structure (verified via `grep '^##' CONTRIBUTING.md` before writing the insertion point).
