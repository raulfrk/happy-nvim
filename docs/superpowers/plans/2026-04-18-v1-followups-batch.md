# v1 Follow-ups Batch Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship four small follow-up improvements: `:checkhealth` probes for `tree-sitter` CLI + `winborder` option, Nerd Font prerequisite docs, CONTRIBUTING.md for stylua/selene local setup, and a `FileType` autocmd that auto-installs the missing nvim-treesitter parser on first open.

**Architecture:** Four independent deliverables, one commit each. `health.lua` gains two new probe sections. Nerd-font guidance lands in README + a stderr warning from `migrate.sh` if `fc-list` doesn't show a Nerd Font. `CONTRIBUTING.md` is new. Auto-TSInstall hook lives in `lua/plugins/treesitter.lua`'s `config` function and extends the existing `vim.treesitter.start` FileType autocmd.

**Tech Stack:** Lua 5.1, Bash 5, Neovim 0.11+, nvim-treesitter main branch, `fc-list` (Linux/mac font catalog).

---

## File Structure

```
lua/happy/health.lua              # MODIFIED — add tree-sitter + winborder probes
lua/plugins/treesitter.lua        # MODIFIED — auto :TSInstall on unknown FileType
scripts/migrate.sh                # MODIFIED — nerd-font presence warning
README.md                         # MODIFIED — "Prerequisites" nerd-font subsection
CONTRIBUTING.md                   # NEW — local stylua/selene install
docs/manual-tests.md              # MODIFIED — one new row for Nerd Font check
```

Each file has one responsibility. Plan's four deliverables map 1:1 to Tasks 1-4.

---

## Task 1: `:checkhealth` probes for tree-sitter CLI + winborder

**Files:**
- Modify: `lua/happy/health.lua`

**Context:** Users migrating from MyHappyPlace frequently hit two issues we can't see from inside nvim: (1) no `tree-sitter` CLI on PATH (nvim-treesitter@main needs it for parser builds), (2) their nvim predates `winborder` option (0.11 pre-merge dev builds). Current `:checkhealth happy-nvim` doesn't surface either. Add two probe sections.

- [ ] **Step 1: Read current health.lua to see the existing probe pattern**

The file has `h.start('happy-nvim: ...')` sections and uses an `exec(cmd)` helper. Each section groups related checks. We'll add a new `happy-nvim: tree-sitter` section and extend `happy-nvim: core` with the winborder check.

- [ ] **Step 2: Edit `lua/happy/health.lua`**

Find the `happy-nvim: core` section:

```lua
  h.start('happy-nvim: core')
  if vim.fn.has('nvim-0.10') == 1 then
    h.ok('Neovim >= 0.10')
  else
    h.error('Neovim >= 0.10 required')
  end
```

Replace with:

```lua
  h.start('happy-nvim: core')
  if vim.fn.has('nvim-0.11') == 1 then
    h.ok('Neovim >= 0.11')
  else
    h.error('Neovim >= 0.11 required (happy-nvim now assumes 0.11 APIs)')
  end
  if vim.fn.exists('&winborder') == 1 then
    h.ok('winborder option available')
  else
    h.warn(
      'winborder option missing — some 0.11 plugins (noice, nui) error on float borders. Upgrade to a nvim build that includes the winborder PR.'
    )
  end
```

Then find `h.start('happy-nvim: local CLIs')` and add a dedicated tree-sitter section AFTER the local-CLIs block (before `h.start('happy-nvim: tmux')`):

```lua

  h.start('happy-nvim: tree-sitter')
  if vim.fn.executable('tree-sitter') == 1 then
    local ok, ver = exec({ 'tree-sitter', '--version' })
    if ok then
      h.ok('tree-sitter CLI: ' .. ver:gsub('%s+$', ''))
    else
      h.warn('tree-sitter CLI present but --version failed')
    end
  else
    h.error(
      'tree-sitter CLI not on $PATH — nvim-treesitter@main needs it to build parsers. Install: npm install -g tree-sitter-cli'
    )
  end
```

- [ ] **Step 3: Run `:checkhealth happy-nvim` headlessly and verify new lines appear**

```bash
cd /home/raul/worktrees/happy-nvim/feat-v1-implementation
XDG_DATA_HOME="$PWD/.tests" XDG_CONFIG_HOME="$PWD/.tests/config" \
  XDG_CACHE_HOME="$PWD/.tests/cache" XDG_STATE_HOME="$PWD/.tests/state" \
  nvim --headless -c 'checkhealth happy-nvim' -c 'qa!' 2>&1 | grep -E 'winborder|tree-sitter'
```

Expected output: at least two lines — one winborder ok/warn, one tree-sitter ok/warn/error.

- [ ] **Step 4: Stylua + commit**

```bash
export STYLUA=/tmp/npmcache/_npx/2d7ba7d0047acad9/node_modules/.bin/stylua
$STYLUA lua/happy/health.lua
$STYLUA --check lua/happy/health.lua && echo STYLUA_OK
git add lua/happy/health.lua
git commit -m "feat(health): probe for tree-sitter CLI + winborder option

Two new :checkhealth happy-nvim rows surface issues that break
fresh installs:
- winborder availability (missing on nvim 0.11-dev pre-PR-31073
  → noice/nui crash on float border)
- tree-sitter CLI on PATH (nvim-treesitter@main needs it to build
  parsers; missing = ENOENT on first Lazy sync)

Bumped core probe from nvim-0.10 to nvim-0.11 to match actual
minimum (happy-nvim uses vim.lsp.config + vim.o.winborder)."
```

---

## Task 2: Auto-install missing tree-sitter parsers on first open

**Files:**
- Modify: `lua/plugins/treesitter.lua`

**Context:** `lua/plugins/treesitter.lua` currently calls `ts.install(LANGS)` for a fixed list. When the user opens a filetype NOT in that list (e.g. `ruby`, `rust`, `typescript`), nvim falls back to regex syntax instead of treesitter. We add a `FileType` autocmd that checks if the parser is installed and triggers async install if not. The existing FileType autocmd already exists for starting the highlighter — we extend it.

- [ ] **Step 1: Read current `lua/plugins/treesitter.lua`**

```bash
cat lua/plugins/treesitter.lua
```

Note the `LANGS` table + the FileType autocmd calling `pcall(vim.treesitter.start, ev.buf)`.

- [ ] **Step 2: Extend the config function**

Find the block:

```lua
  config = function()
    local ts = require('nvim-treesitter')
    ts.install(LANGS)

    vim.api.nvim_create_autocmd('FileType', {
      pattern = LANGS,
      callback = function(ev)
        pcall(vim.treesitter.start, ev.buf)
      end,
    })
  end,
```

Replace with:

```lua
  config = function()
    local ts = require('nvim-treesitter')
    ts.install(LANGS)

    -- Start TS on every file that has a parser (bundled or installed).
    vim.api.nvim_create_autocmd('FileType', {
      callback = function(ev)
        local ft = ev.match
        if ft == '' then
          return
        end
        -- Bundled or previously-installed → just start.
        if pcall(vim.treesitter.language.get_lang, ft) then
          pcall(vim.treesitter.start, ev.buf)
          return
        end
        -- Not installed. Kick off an async install + start on completion.
        -- Skip filetypes treesitter doesn't know about at all (no parser exists).
        local ok, parsers = pcall(require, 'nvim-treesitter.parsers')
        if not ok or not parsers[ft] then
          return
        end
        ts.install({ ft })
        -- Re-check after a short delay; start if install finished.
        vim.defer_fn(function()
          if pcall(vim.treesitter.language.get_lang, ft) then
            pcall(vim.treesitter.start, ev.buf)
          end
        end, 3000)
      end,
    })
  end,
```

- [ ] **Step 3: Stylua + commit**

```bash
$STYLUA lua/plugins/treesitter.lua
$STYLUA --check lua/plugins/treesitter.lua && echo STYLUA_OK
git add lua/plugins/treesitter.lua
git commit -m "feat(treesitter): auto :TSInstall missing parsers on first open

FileType autocmd now handles three cases:
1. Parser already installed -> vim.treesitter.start (existing).
2. Parser known to nvim-treesitter but not installed -> ts.install(\\{ft}\\)
   then defer-start after 3s when the build finishes.
3. Unknown filetype (no parser exists) -> fall back to vim regex.

Eliminates the 'open .rs file, have to run :TSInstall rust manually'
friction point. Install is async so the FileType event doesn't block."
```

---

## Task 3: Nerd Font prereq — docs + migrate.sh warning

**Files:**
- Modify: `README.md`
- Modify: `scripts/migrate.sh`
- Modify: `docs/manual-tests.md`

**Context:** Most common post-install complaint is "icons render as ?" — terminal font isn't a Nerd Font. We add a Prerequisites subsection to README with install commands per OS, emit a stderr warning from `migrate.sh` if `fc-list` doesn't show "Nerd Font" in any family, and add one row to `manual-tests.md`.

`fc-list` is Linux/BSD — on macOS it's `system_profiler SPFontsDataType`. migrate.sh just checks `fc-list | grep -qi "Nerd Font"` and prints a warning if not found; we don't block install (users who don't want icons can ignore).

- [ ] **Step 1: Add README Prerequisites subsection**

Find the existing install section in `README.md`. Before it (or near the top under an H2 like `## Prerequisites`), add:

```markdown

## Prerequisites

**Required:**
- Neovim >= 0.11 (for `winborder` + `vim.lsp.config`)
- tmux >= 3.2 (for `display-popup -E`)
- Node.js + npm (for `tree-sitter-cli` install via `migrate.sh`)
- git
- ripgrep (`rg`) + fd-find (`fd`) — telescope defaults

**Recommended (for full feature set):**
- A Nerd Font in your terminal — otherwise icons render as `?` or boxes.
  Quick install:

    ```bash
    # Linux (fontconfig)
    mkdir -p ~/.local/share/fonts && cd ~/.local/share/fonts
    curl -L -O https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip
    unzip -o JetBrainsMono.zip && fc-cache -fv

    # macOS
    brew install --cask font-jetbrains-mono-nerd-font
    ```

    Set your terminal font to `JetBrainsMono Nerd Font` (or any other Nerd
    Font you like).

- mosh >= 1.4 — for `OSC 52` clipboard passthrough over unreliable links
- claude CLI on `$PATH` — for `<leader>c*` tmux integration
```

- [ ] **Step 2: Add `migrate.sh` warning**

Find the section in `scripts/migrate.sh` after the tree-sitter preflight. Add a new preflight block BEFORE the backup step:

```bash

# 1c. Preflight — Nerd Font detection (warning only, not fatal)
if command -v fc-list >/dev/null 2>&1; then
  if ! fc-list 2>/dev/null | grep -qi 'nerd font'; then
    warn "No Nerd Font detected in fc-list. Icons will render as '?' or boxes."
    warn "Install one: https://github.com/ryanoasis/nerd-fonts/releases"
    warn "Then set your terminal font to e.g. 'JetBrainsMono Nerd Font'."
  fi
fi
```

(The existing `warn()` function from earlier in the script handles yellow-tinted stderr output.)

- [ ] **Step 3: Append one row to `docs/manual-tests.md`**

Find the "0. Pre-flight" section in `docs/manual-tests.md`. After the existing "Terminal font is a Nerd Font" row, expand the description:

Change:

```markdown
- [ ] Terminal font is a Nerd Font (icons render, not boxes/?)
```

To:

```markdown
- [ ] Terminal font is a Nerd Font (icons render, not boxes/?). If you see `?`, run `fc-list | grep -i 'nerd font'` — empty output = install per README Prerequisites.
```

- [ ] **Step 4: Commit**

```bash
git add README.md scripts/migrate.sh docs/manual-tests.md
git commit -m "docs(prereq): Nerd Font install guide + migrate.sh warning

Three changes for the most common post-install complaint ('icons
are question marks'):
- README gets a 'Prerequisites' section w/ Linux + macOS install
  one-liners.
- migrate.sh checks fc-list for any 'nerd font' family and warns
  (non-fatal) if none found.
- manual-tests.md pre-flight row expanded w/ diagnostic command."
```

---

## Task 4: `CONTRIBUTING.md` — local stylua + selene setup

**Files:**
- Create: `CONTRIBUTING.md`

**Context:** CI runs stylua + selene via `cargo-binstall` (see `.github/workflows/ci.yml`). Contributors hitting lint failures locally lack those tools. Document three install paths (cargo, npm for stylua, pipx/brew alternatives), plus pre-push recipe.

- [ ] **Step 1: Write `CONTRIBUTING.md`**

Create `CONTRIBUTING.md` at repo root:

```markdown
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

## Manual testing

`docs/manual-tests.md` is the living checklist contributors walk through
before cutting a release. Rows marked `(CI-covered)` are also exercised
by pytest in `tests/integration/`, so you can skim those.
```

- [ ] **Step 2: Commit**

```bash
git add CONTRIBUTING.md
git commit -m "docs(contributing): local dev setup + assess.sh workflow

New CONTRIBUTING.md covers:
- stylua/selene local install paths (cargo, npm, binary releases)
- 'bash scripts/assess.sh' as the one-button pre-push check
- Conventional Commits type table
- Reference to writing-plans skill + manual-tests.md convention"
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

- [ ] **Step 2: Capture + poll**

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

- [ ] **Step 3: Verify per-job status**

```bash
gh api "repos/raulfrk/happy-nvim/actions/runs/$RUN_ID/jobs" --jq '.jobs[] | "\(.name): \(.conclusion)"'
```

Expected all `success`. No new tests added → existing assertions still pass. Health job might report the new probes as `warn` if the CI runner doesn't have `tree-sitter` on PATH yet — the health job already installs it (added in the test-harness plan), so should be `ok`.

- [ ] **Step 4: Close source todos**

```
todo_complete 1.2 1.3 1.7 1.10
```

---

## Manual Test Additions

Already covered by Task 3 Step 3 (expanded the existing Nerd Font row with a diagnostic hint). No additional rows for Tasks 1, 2, 4 — those are behavior contributors verify during development via `assess.sh`, not end-user-visible.

---

## Self-Review

**1. Spec coverage:**

| Todo | Task |
|---|---|
| #1.2 :checkhealth probes | Task 1 (tree-sitter + winborder sections) |
| #1.3 Nerd Font prereq docs | Task 3 (README + migrate.sh warning + manual-tests row) |
| #1.7 CONTRIBUTING local setup | Task 4 |
| #1.10 Auto :TSInstall on FileType | Task 2 |

No gaps.

**2. Placeholder scan:** no TBDs. Every code block complete.

**3. Type consistency:**
- `exec()` helper in health.lua matches the existing signature.
- `warn()` in migrate.sh matches the existing function defined earlier in the script (`warn() { printf ...; }`).
- `ts.install({ft})` call signature matches Phase 3's treesitter config pattern.
- `vim.treesitter.language.get_lang(ft)` is the 0.11 API; consistent with existing usage in the same file.
