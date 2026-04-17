# happy-nvim v1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship happy-nvim v1 — a modular Neovim config forked from kickstart.nvim, with macro-nudge layer (precognition + noice + which-key + hardtime + tip-of-day + curated cheatsheet), OSC 52 dual-clipboard for mosh+tmux+nvim stack, tmux Claude Code integration, and pure-SSH remote ops (host frecency, zoxide-like remote dir picker, niced ssh-grep, scp:// browse).

**Architecture:** Fresh repo at `github.com/raulfrk/happy-nvim`. Seeded once from `nvim-lua/kickstart.nvim` then modularized into `lua/{config,plugins,coach,tmux,remote,clipboard,happy}/`. Plugin manager is `lazy.nvim` with `defaults = { lazy = true }`. Core logic in pure-Lua modules is test-covered via `plenary.nvim` busted harness. Plugin wiring is verified via headless nvim startup smoke tests in GitHub Actions.

**Tech Stack:** Neovim 0.10+, Lua, lazy.nvim, plenary.nvim (test runner), stylua (formatter), selene (linter), GitHub Actions CI, tokyonight theme, ~25 external plugins documented in the spec.

**Reference spec:** `docs/superpowers/specs/2026-04-16-happy-nvim-design.md` — every decision below traces back to a labeled section (§N) in that spec.

---

## File Structure

### Repo layout to produce

```
happy-nvim/
├── init.lua
├── lua/
│   ├── config/
│   │   ├── options.lua
│   │   ├── keymaps.lua
│   │   ├── autocmds.lua
│   │   ├── colors.lua
│   │   └── lazy.lua
│   ├── plugins/
│   │   ├── colorscheme.lua
│   │   ├── treesitter.lua
│   │   ├── lsp.lua
│   │   ├── completion.lua
│   │   ├── conform.lua
│   │   ├── lint.lua
│   │   ├── telescope.lua
│   │   ├── harpoon.lua
│   │   ├── undotree.lua
│   │   ├── fugitive.lua
│   │   ├── gitsigns.lua
│   │   ├── whichkey.lua
│   │   ├── hardtime.lua
│   │   ├── precognition.lua
│   │   ├── alpha.lua
│   │   ├── lualine.lua
│   │   ├── noice.lua
│   │   ├── notify.lua
│   │   ├── surround.lua
│   │   ├── repeat.lua
│   │   └── tmux-nav.lua
│   ├── coach/
│   │   ├── init.lua
│   │   └── tips.lua
│   ├── tmux/
│   │   ├── init.lua
│   │   ├── popup.lua
│   │   ├── send.lua
│   │   └── claude.lua
│   ├── remote/
│   │   ├── init.lua
│   │   ├── hosts.lua
│   │   ├── dirs.lua
│   │   ├── browse.lua
│   │   └── grep.lua
│   ├── clipboard/
│   │   └── init.lua
│   └── happy/
│       └── health.lua
├── tests/
│   ├── minimal_init.lua
│   ├── coach_spec.lua
│   ├── clipboard_spec.lua
│   ├── tmux_send_spec.lua
│   ├── tmux_claude_spec.lua
│   ├── remote_hosts_spec.lua
│   ├── remote_dirs_spec.lua
│   └── remote_grep_spec.lua
├── scripts/
│   ├── smoke.sh
│   └── ssh-z.zsh
├── .github/workflows/ci.yml
├── lazy-lock.json
├── stylua.toml
├── selene.toml
├── .neoconf.json
├── .gitignore
├── LICENSE
└── README.md
```

### Phase map

| Phase | Tasks | Output |
|---|---|---|
| 0: Bootstrap | 1–5 | Repo, CI skeleton, test harness, LICENSE, .gitignore. |
| 1: Core config | 6–11 | `init.lua`, `config/`, lazy.nvim bootstrap. Minimal nvim starts clean. |
| 2: UI + theme + nav | 12–20 | tokyonight, alpha, lualine, which-key, telescope, harpoon, undotree, fugitive, gitsigns. Usable daily driver. |
| 3: LSP + completion + treesitter + fmt | 21–26 | mason, lspconfig, blink.cmp, conform, nvim-lint, treesitter. Full dev experience for Py/Go/Lua/Bash/YAML/MD/C++. |
| 4: Macro-nudge | 27–32 | hardtime, precognition, noice, vim-surround, vim-repeat, `coach/` module w/ 30-tip seed. |
| 5: Clipboard | 33–34 | OSC 52 TextYankPost hook. Dual-clipboard verified. |
| 6: Tmux + Claude | 35–40 | vim-tmux-navigator, `tmux/` module, popup launchers, Claude `<leader>c*` commands. |
| 7: Remote ops | 41–48 | `remote/` module — ssh-z zsh helper, hosts frecency, dirs cache, browse + binary guard, grep with full regex flags. |
| 8: Health + polish | 49–52 | `:checkhealth happy-nvim`, README, migration from MyHappyPlace, acceptance-matrix run. |

Each phase ends with a commit on main and a smoke-tested working config. Phases can be paused between for dogfooding.

---

## Phase 0 — Bootstrap (Tasks 1–5)

### Task 1: Seed the repo and commit the license

**Files:**
- Create: `LICENSE`
- Create: `.gitignore`
- Create: `README.md` (stub; real content in Task 52)

- [ ] **Step 1: Write MIT LICENSE**

Create `/home/raul/projects/happy-nvim/LICENSE` with the standard MIT text, copyright line `Copyright (c) 2026 Raul Farkas`.

- [ ] **Step 2: Write `.gitignore`**

```gitignore
# Plugin lockfile
# lazy-lock.json is COMMITTED — do not ignore.

# Test runner artifacts
.tests/
tests/.coverage/

# Neovim state (should never be inside the config repo, but defensive)
.cache/
*.swp
*.swo
*~

# Editor
.vscode/
.idea/

# OS
.DS_Store
Thumbs.db
```

- [ ] **Step 3: Write stub README.md**

```markdown
# happy-nvim

A Neovim config focused on macro fluency. Successor to
[MyHappyPlace](https://github.com/raulfrk/MyHappyPlace).

Full documentation: see [README §Install](README.md#install) after Task 52.

**Status:** v1.0 under construction — see
`docs/superpowers/plans/2026-04-17-happy-nvim-v1.md`.
```

- [ ] **Step 4: Commit**

```bash
cd /home/raul/projects/happy-nvim
git add LICENSE .gitignore README.md
git commit -m "chore: add license, gitignore, stub readme"
```

### Task 2: Add stylua + selene config

**Files:**
- Create: `stylua.toml`
- Create: `selene.toml`
- Create: `selene/nvim.yml`

- [ ] **Step 1: Write `stylua.toml`**

```toml
column_width = 100
line_endings = "Unix"
indent_type = "Spaces"
indent_width = 2
quote_style = "AutoPreferSingle"
call_parentheses = "Always"
```

- [ ] **Step 2: Write `selene.toml`**

```toml
std = "lua51+nvim"
exclude = [
  "lazy-lock.json",
  ".tests/",
]
```

- [ ] **Step 3: Write `selene/nvim.yml` (Neovim stdlib whitelist)**

```yaml
---
base: lua51
name: nvim
globals:
  vim:
    any: true
```

- [ ] **Step 4: Verify stylua works locally**

```bash
cd /home/raul/projects/happy-nvim
stylua --check . || echo "no lua files yet, expected"
```

Expected: exits 0 (no `.lua` files yet) — this just proves the tool reads the config.

- [ ] **Step 5: Commit**

```bash
git add stylua.toml selene.toml selene/nvim.yml
git commit -m "chore: add stylua + selene config"
```

### Task 3: Set up the plenary test harness

**Files:**
- Create: `tests/minimal_init.lua`
- Create: `tests/sanity_spec.lua`

- [ ] **Step 1: Write `tests/minimal_init.lua`**

This minimal init is what the test runner loads. It bootstraps plenary into a sandbox so tests run in isolation of the user's real config.

```lua
-- tests/minimal_init.lua
local plugin_root = vim.fn.stdpath('data') .. '/site/pack/vendor/start'
local plenary_path = plugin_root .. '/plenary.nvim'

if vim.fn.isdirectory(plenary_path) == 0 then
  vim.fn.system({
    'git', 'clone', '--depth', '1',
    'https://github.com/nvim-lua/plenary.nvim', plenary_path,
  })
end

vim.opt.rtp:prepend(plenary_path)
vim.opt.rtp:prepend(vim.fn.getcwd())
vim.cmd('runtime plugin/plenary.vim')

require('plenary.busted')
```

- [ ] **Step 2: Write a sanity spec**

```lua
-- tests/sanity_spec.lua
describe('test harness', function()
  it('runs a trivially true assertion', function()
    assert.are.equal(1 + 1, 2)
  end)

  it('can require lua modules from the repo root', function()
    -- lua/happy/_probe.lua does not exist yet; this just proves the RTP is wired
    local ok = pcall(require, 'plenary.path')
    assert.is_true(ok)
  end)
end)
```

- [ ] **Step 3: Run the test**

```bash
cd /home/raul/projects/happy-nvim
nvim --headless -u tests/minimal_init.lua \
  -c "PlenaryBustedDirectory tests/ {minimal_init='tests/minimal_init.lua'}"
```

Expected output ends with `Success: 2  /  Failed: 0  /  Errors: 0`.

- [ ] **Step 4: Commit**

```bash
git add tests/minimal_init.lua tests/sanity_spec.lua
git commit -m "test: add plenary busted harness with sanity spec"
```

### Task 4: Add the GitHub Actions CI skeleton

**Files:**
- Create: `.github/workflows/ci.yml`

- [ ] **Step 1: Write CI config**

```yaml
name: ci
on:
  push:
    branches: [main]
  pull_request:

jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: JohnnyMorganz/stylua-action@v4
        with:
          token: ${{ secrets.GITHUB_TOKEN }}
          version: latest
          args: --check .
      - uses: NTBBloodbath/selene-action@v1
        with:
          token: ${{ secrets.GITHUB_TOKEN }}
          version: latest
          args: .

  test:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        nvim: [stable, nightly]
    steps:
      - uses: actions/checkout@v4
      - uses: rhysd/action-setup-vim@v1
        with:
          neovim: true
          version: ${{ matrix.nvim }}
      - name: Run plenary tests
        run: |
          nvim --headless -u tests/minimal_init.lua \
            -c "PlenaryBustedDirectory tests/ {minimal_init='tests/minimal_init.lua'}" \
            -c 'qa!' 2>&1 | tee test.log
          grep -q 'Failed: 0' test.log
          grep -q 'Errors: 0' test.log

  startup:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        nvim: [stable, nightly]
    steps:
      - uses: actions/checkout@v4
      - uses: rhysd/action-setup-vim@v1
        with:
          neovim: true
          version: ${{ matrix.nvim }}
      - name: Headless startup smoke
        run: |
          mkdir -p $HOME/.config/nvim
          cp -r . $HOME/.config/nvim/
          nvim --headless -c 'qa!' 2>&1 | tee startup.log
          ! grep -Ei 'Error|E[0-9]+:' startup.log
```

- [ ] **Step 2: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: add lint + test + startup smoke workflow"
```

### Task 5: Scaffold `lua/happy/health.lua` stub

The `:checkhealth happy-nvim` provider must be registered from day one so we can add probes incrementally. In this task we just wire up the empty provider so it loads.

**Files:**
- Create: `lua/happy/health.lua`
- Create: `tests/health_spec.lua`

- [ ] **Step 1: Write failing test**

```lua
-- tests/health_spec.lua
describe('happy.health', function()
  it('exports a check() function', function()
    local health = require('happy.health')
    assert.is_function(health.check)
  end)
end)
```

- [ ] **Step 2: Run test to verify it fails**

```bash
nvim --headless -u tests/minimal_init.lua \
  -c "PlenaryBustedFile tests/health_spec.lua" -c 'qa!'
```

Expected: FAIL with `module 'happy.health' not found`.

- [ ] **Step 3: Write minimal implementation**

```lua
-- lua/happy/health.lua
local M = {}

function M.check()
  vim.health.start('happy-nvim')
  vim.health.ok('Health provider registered. Probes added in later tasks.')
end

return M
```

- [ ] **Step 4: Run test to verify it passes**

Same command as Step 2. Expected: PASS.

- [ ] **Step 5: Verify `:checkhealth happy-nvim` works interactively (manual)**

```bash
nvim --headless -c 'checkhealth happy-nvim' -c 'qa!' 2>&1 | grep -q 'Health provider'
```

Expected exit code 0.

- [ ] **Step 6: Commit**

```bash
git add lua/happy/health.lua tests/health_spec.lua
git commit -m "feat: scaffold happy.health :checkhealth provider"
```

---

## Phase 1 — Core config (Tasks 6–11)

This phase delivers a minimal runnable nvim using only builtin features + lazy.nvim bootstrap. No plugins load yet. After this phase, `nvim` launches cleanly and all BUG-3 style fixes from spec §6 are applied.

### Task 6: Write `lua/config/options.lua`

**Files:**
- Create: `lua/config/options.lua`

- [ ] **Step 1: Write the file**

```lua
-- lua/config/options.lua
-- Option tweaks. termguicolors is set in plugins/colorscheme.lua BEFORE the
-- theme loads (per spec BUG-3 fix).

local o = vim.opt

-- Line numbers
o.number = true
o.relativenumber = true

-- Indent — 4-space soft tabs; smart-indent on
o.tabstop = 4
o.softtabstop = 4
o.shiftwidth = 4
o.expandtab = true
o.smartindent = true

-- No wrap
o.wrap = false

-- No swap / backup; undo persisted in XDG state dir (BUG fix: not ~/.vim)
o.swapfile = false
o.backup = false
o.undofile = true
o.undodir = vim.fn.stdpath('state') .. '/undo'

-- Search
o.hlsearch = true -- BUG-3: was false, disorienting
o.incsearch = true

-- Cursor — always a block in normal, bar in insert (BUG-3 fix for kitty/alacritty)
o.guicursor = 'n-v-c-sm:block,i-ci-ve:ver25,r-cr-o:hor20'

-- Scroll context
o.scrolloff = 8
o.signcolumn = 'yes'

-- Clipboard — VM clipboard via xclip/wl-copy. OSC 52 hook added in Phase 5.
o.clipboard = 'unnamedplus'

-- Filenames containing @- are valid
o.isfname:append('@-@')

-- Faster updatetime (CursorHold, gitsigns, etc.)
o.updatetime = 50

-- Splits open to the right / below
o.splitright = true
o.splitbelow = true

-- True color — required by theme
o.termguicolors = true

-- Leader
vim.g.mapleader = ' '
vim.g.maplocalleader = ' '

-- Diagnostic display
vim.diagnostic.config({
  virtual_text = true,
  signs = true,
  update_in_insert = false,
  severity_sort = true,
})
```

- [ ] **Step 2: Format + lint**

```bash
stylua lua/config/options.lua
selene lua/config/options.lua
```

Expected: no diffs, no warnings.

- [ ] **Step 3: Commit**

```bash
git add lua/config/options.lua
git commit -m "feat(config): add options.lua with BUG-3 fixes (cursor, hlsearch, undodir)"
```

### Task 7: Write `lua/config/keymaps.lua`

Core keymaps only. Namespaced leader-prefixed keymaps live in their plugin files (spec §BUG-2 fix).

**Files:**
- Create: `lua/config/keymaps.lua`

- [ ] **Step 1: Write the file**

```lua
-- lua/config/keymaps.lua
-- Core keymaps (non-namespaced). Plugin-specific leader-prefixed keymaps
-- are registered in lua/plugins/<plugin>.lua via which-key.add (spec §BUG-2).

local map = vim.keymap.set

-- Move visual selections up/down preserving indent
map('v', 'J', ":m '>+1<CR>gv=gv", { silent = true })
map('v', 'K', ":m '<-2<CR>gv=gv", { silent = true })

-- Keep cursor centered on half-page scroll + n/N search
map('n', 'J', 'mzJ`z')
map('n', '<C-d>', '<C-d>zz')
map('n', '<C-u>', '<C-u>zz')
map('n', 'n', 'nzzzv')
map('n', 'N', 'Nzzzv')

-- Paste over visual without clobbering register (classic)
map('x', '<leader>p', [["_dP]], { desc = 'paste without yank' })

-- System-clipboard yank (single, authoritative binding per spec §BUG-2)
map({ 'n', 'v' }, '<leader>y', [["+y]], { desc = 'yank to system clipboard' })
map('n', '<leader>Y', [["+Y]], { desc = 'yank line to system clipboard' })

-- Delete without clobbering unnamed register
map({ 'n', 'v' }, '<leader>d', [["_d]], { desc = 'delete without yank' })

-- Ergonomics
map('i', '<C-c>', '<Esc>', { desc = 'Esc via C-c (intentional)' })
map('n', 'Q', '<nop>', { desc = 'disable Ex mode' })

-- Clear search highlight on <Esc>
map('n', '<Esc>', '<cmd>nohlsearch<CR>')

-- Quickfix / loclist navigation
map('n', '<C-k>', '<cmd>cnext<CR>zz')
map('n', '<C-j>', '<cmd>cprev<CR>zz')

-- Make current file executable
map('n', '<leader>x', '<cmd>!chmod +x %<CR>', { silent = true, desc = 'chmod +x current file' })
```

- [ ] **Step 2: Format + lint**

```bash
stylua lua/config/keymaps.lua
selene lua/config/keymaps.lua
```

- [ ] **Step 3: Commit**

```bash
git add lua/config/keymaps.lua
git commit -m "feat(config): add keymaps.lua (core, non-namespaced)"
```

### Task 8: Write `lua/config/autocmds.lua`

**Files:**
- Create: `lua/config/autocmds.lua`

- [ ] **Step 1: Write the file**

```lua
-- lua/config/autocmds.lua

local aug = vim.api.nvim_create_augroup('happy_autocmds', { clear = true })

-- Highlight yanked text briefly
vim.api.nvim_create_autocmd('TextYankPost', {
  group = aug,
  callback = function()
    vim.highlight.on_yank({ higroup = 'IncSearch', timeout = 150 })
  end,
})

-- Re-check files changed on disk when nvim regains focus
vim.api.nvim_create_autocmd({ 'FocusGained', 'BufEnter' }, {
  group = aug,
  command = 'checktime',
})

-- Per-filetype colorcolumn (BUG-3 fix: was hardcoded 80 globally)
local cc_map = {
  markdown = '80', text = '80',
  lua = '120', go = '120', python = '120',
  c = '120', cpp = '120', sh = '120', yaml = '120',
}
vim.api.nvim_create_autocmd('FileType', {
  group = aug,
  callback = function(ev)
    vim.bo[ev.buf].colorcolumn = cc_map[ev.match] or ''
  end,
})

-- Strip trailing whitespace on save (excluding markdown where it matters for line breaks)
vim.api.nvim_create_autocmd('BufWritePre', {
  group = aug,
  callback = function(ev)
    if vim.bo[ev.buf].filetype == 'markdown' then
      return
    end
    local view = vim.fn.winsaveview()
    vim.cmd([[keeppatterns %s/\s\+$//e]])
    vim.fn.winrestview(view)
  end,
})
```

- [ ] **Step 2: Format + lint**

```bash
stylua lua/config/autocmds.lua && selene lua/config/autocmds.lua
```

- [ ] **Step 3: Commit**

```bash
git add lua/config/autocmds.lua
git commit -m "feat(config): add autocmds.lua (yank highlight, checktime, per-ft colorcolumn)"
```

### Task 9: Write `lua/config/colors.lua`

Highlight-group overrides applied after any theme loads. Empty for now; populated after tokyonight in Task 12.

**Files:**
- Create: `lua/config/colors.lua`

- [ ] **Step 1: Write the file**

```lua
-- lua/config/colors.lua
-- Highlight-group overrides. Applied after the theme loads via ColorScheme
-- autocmd so overrides survive `:colorscheme` swaps.

local aug = vim.api.nvim_create_augroup('happy_colors', { clear = true })

vim.api.nvim_create_autocmd('ColorScheme', {
  group = aug,
  callback = function()
    -- placeholder — overrides added in Task 12
  end,
})
```

- [ ] **Step 2: Format + lint + commit**

```bash
stylua lua/config/colors.lua && selene lua/config/colors.lua
git add lua/config/colors.lua
git commit -m "feat(config): add colors.lua scaffold"
```

### Task 10: Write `lua/config/lazy.lua` — plugin manager bootstrap

**Files:**
- Create: `lua/config/lazy.lua`

- [ ] **Step 1: Write the file**

```lua
-- lua/config/lazy.lua — bootstraps lazy.nvim and loads the plugins/ tree

local lazypath = vim.fn.stdpath('data') .. '/lazy/lazy.nvim'
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  local repo = 'https://github.com/folke/lazy.nvim.git'
  local out = vim.fn.system({
    'git', 'clone', '--filter=blob:none', '--branch=stable', repo, lazypath,
  })
  if vim.v.shell_error ~= 0 then
    vim.api.nvim_echo({
      { 'Failed to clone lazy.nvim:\n', 'ErrorMsg' },
      { out, 'WarningMsg' },
      { '\nPress any key to exit...' },
    }, true, {})
    vim.fn.getchar()
    os.exit(1)
  end
end
vim.opt.rtp:prepend(lazypath)

require('lazy').setup({
  spec = {
    { import = 'plugins' },
  },
  defaults = {
    lazy = true, -- spec §BUG-4 fix: lazy by default
    version = false,
  },
  install = { colorscheme = { 'tokyonight', 'habamax' } },
  checker = { enabled = true, notify = false },
  performance = {
    rtp = {
      disabled_plugins = {
        'gzip', 'tarPlugin', 'tohtml', 'tutor', 'zipPlugin',
      },
    },
  },
})
```

- [ ] **Step 2: Format + lint + commit**

```bash
stylua lua/config/lazy.lua && selene lua/config/lazy.lua
git add lua/config/lazy.lua
git commit -m "feat(config): add lazy.nvim bootstrap (lazy=true default per BUG-4)"
```

### Task 11: Write `init.lua` + verify headless startup

**Files:**
- Create: `init.lua`
- Create: `lua/plugins/.keep` (placeholder so lazy spec loader finds the dir)

- [ ] **Step 1: Write `init.lua`**

```lua
-- init.lua — happy-nvim entry point
-- Order matters: options before keymaps (leader), autocmds, colors, then lazy.

local function try_require(mod)
  local ok, err = pcall(require, mod)
  if not ok then
    vim.notify('happy-nvim: failed to load ' .. mod .. ': ' .. err, vim.log.levels.ERROR)
  end
end

try_require('config.options')
try_require('config.keymaps')
try_require('config.autocmds')
try_require('config.colors')
try_require('config.lazy')
```

- [ ] **Step 2: Create empty `lua/plugins/.keep`**

```bash
mkdir -p lua/plugins && touch lua/plugins/.keep
```

- [ ] **Step 3: Verify headless startup**

```bash
HOME=/tmp/happy-nvim-test-home mkdir -p /tmp/happy-nvim-test-home/.config
ln -sfn "$PWD" /tmp/happy-nvim-test-home/.config/nvim
HOME=/tmp/happy-nvim-test-home nvim --headless -c 'qa!' 2>&1 | tee /tmp/startup.log
! grep -Ei 'Error|E[0-9]+:' /tmp/startup.log && echo OK
```

Expected: prints `OK`. lazy.nvim may clone itself on first run — repeat command if needed.

- [ ] **Step 4: Commit**

```bash
git add init.lua lua/plugins/.keep
git commit -m "feat: wire init.lua — minimal nvim starts clean"
```

---

## Phase 2 — UI, theme, navigation (Tasks 12–20)

### Task 12: Add tokyonight theme + populate colors.lua overrides

**Files:**
- Create: `lua/plugins/colorscheme.lua`
- Modify: `lua/config/colors.lua`

- [ ] **Step 1: Write `lua/plugins/colorscheme.lua`**

```lua
-- lua/plugins/colorscheme.lua
return {
  'folke/tokyonight.nvim',
  lazy = false, -- theme loads at startup
  priority = 1000, -- before anything that reads highlight groups
  config = function()
    require('tokyonight').setup({
      style = 'storm',
      styles = { comments = { italic = true } },
    })
    vim.cmd.colorscheme('tokyonight')
  end,
}
```

- [ ] **Step 2: Update `lua/config/colors.lua`**

```lua
-- lua/config/colors.lua
local aug = vim.api.nvim_create_augroup('happy_colors', { clear = true })

vim.api.nvim_create_autocmd('ColorScheme', {
  group = aug,
  callback = function()
    -- Bump LineNr contrast
    vim.api.nvim_set_hl(0, 'LineNr', { fg = '#565f89' })
    vim.api.nvim_set_hl(0, 'CursorLineNr', { fg = '#c0caf5', bold = true })
    -- Softer float borders
    vim.api.nvim_set_hl(0, 'FloatBorder', { fg = '#565f89', bg = 'NONE' })
  end,
})
```

- [ ] **Step 3: Verify headless startup still clean**

```bash
HOME=/tmp/happy-nvim-test-home nvim --headless -c 'Lazy sync' -c 'qa!' 2>&1 | tail -20
HOME=/tmp/happy-nvim-test-home nvim --headless -c 'colorscheme' -c 'qa!' 2>&1 | grep -q tokyonight
```

Expected: second command prints `tokyonight`.

- [ ] **Step 4: Commit**

```bash
git add lua/plugins/colorscheme.lua lua/config/colors.lua
git commit -m "feat(theme): tokyonight storm + LineNr/FloatBorder overrides"
```

### Task 13: Add `nvim-web-devicons` (icon dep for telescope/lualine)

**Files:**
- Create: `lua/plugins/devicons.lua`

- [ ] **Step 1: Write the spec**

```lua
-- lua/plugins/devicons.lua
return {
  'nvim-tree/nvim-web-devicons',
  lazy = true,
}
```

- [ ] **Step 2: Commit**

```bash
git add lua/plugins/devicons.lua
git commit -m "feat(plugin): add nvim-web-devicons"
```

### Task 14: Add `nvim-notify` + `noice.nvim` + `nui.nvim`

noice depends on nui and nvim-notify. All three ship together per spec §5.1.5.

**Files:**
- Create: `lua/plugins/notify.lua`
- Create: `lua/plugins/noice.lua`

- [ ] **Step 1: Write `lua/plugins/notify.lua`**

```lua
-- lua/plugins/notify.lua
return {
  'rcarriga/nvim-notify',
  lazy = true,
  opts = {
    timeout = 3000,
    render = 'wrapped-compact',
    stages = 'fade',
  },
  init = function()
    vim.notify = function(...)
      return require('notify')(...)
    end
  end,
}
```

- [ ] **Step 2: Write `lua/plugins/noice.lua`**

```lua
-- lua/plugins/noice.lua
return {
  'folke/noice.nvim',
  event = 'VeryLazy',
  dependencies = {
    'MunifTanjim/nui.nvim',
    'rcarriga/nvim-notify',
  },
  opts = {
    lsp = {
      override = {
        ['vim.lsp.util.convert_input_to_markdown_lines'] = true,
        ['vim.lsp.util.stylize_markdown'] = true,
        ['cmp.entry.get_documentation'] = true,
      },
      signature = { enabled = true }, -- inline LSP signature popups (spec §5.1.5)
      hover = { enabled = true },
    },
    presets = {
      bottom_search = true,
      command_palette = true, -- center-screen cmdline popup
      long_message_to_split = true,
      lsp_doc_border = true,
    },
  },
}
```

- [ ] **Step 3: Verify**

```bash
HOME=/tmp/happy-nvim-test-home nvim --headless -c 'Lazy sync' -c 'qa!' 2>&1 | tail -5
```

Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add lua/plugins/notify.lua lua/plugins/noice.lua
git commit -m "feat(plugin): add nvim-notify + noice.nvim + nui.nvim (spec §5.1.5)"
```

### Task 15: Add `which-key` with namespace groups

**Files:**
- Create: `lua/plugins/whichkey.lua`

- [ ] **Step 1: Write the spec**

```lua
-- lua/plugins/whichkey.lua — namespace table enforcement (spec §BUG-2)
return {
  'folke/which-key.nvim',
  event = 'VeryLazy',
  config = function()
    local wk = require('which-key')
    wk.setup({
      preset = 'modern',
      delay = 400, -- spec §5.1.5: 400ms to not interrupt muscle memory
      notify = false,
    })

    wk.add({
      { '<leader>f', group = 'find / files (telescope)' },
      { '<leader>g', group = 'git' },
      { '<leader>l', group = 'LSP' },
      { '<leader>d', group = 'diagnostics' },
      { '<leader>h', group = 'harpoon' },
      { '<leader>s', group = 'ssh / remote' },
      { '<leader>c', group = 'Claude (tmux)' },
      { '<leader>t', group = 'tmux popups' },
      { '<leader>?', group = 'cheatsheet / coach' },
    })

    -- Visual-mode text-object hints (spec §5.1.5)
    wk.add({
      mode = 'v',
      { 'iw', desc = 'inside word' },
      { 'aw', desc = 'a word' },
      { 'ip', desc = 'inside paragraph' },
      { 'ap', desc = 'a paragraph' },
      { 'it', desc = 'inside tag' },
      { 'at', desc = 'a tag' },
      { 'i"', desc = 'inside double-quotes' },
      { "i'", desc = 'inside single-quotes' },
      { 'i(', desc = 'inside parens' },
      { 'i[', desc = 'inside brackets' },
      { 'i{', desc = 'inside braces' },
    })
  end,
}
```

- [ ] **Step 2: Commit**

```bash
git add lua/plugins/whichkey.lua
git commit -m "feat(plugin): which-key with namespace groups + visual-mode text objects"
```

### Task 16: Add `lualine`

**Files:**
- Create: `lua/plugins/lualine.lua`

- [ ] **Step 1: Write**

```lua
-- lua/plugins/lualine.lua
return {
  'nvim-lualine/lualine.nvim',
  event = 'VeryLazy',
  dependencies = { 'nvim-tree/nvim-web-devicons' },
  opts = {
    options = {
      theme = 'tokyonight',
      component_separators = '|',
      section_separators = { left = '', right = '' },
      globalstatus = true,
    },
    sections = {
      lualine_a = { 'mode' },
      lualine_b = { 'branch', 'diff', 'diagnostics' },
      lualine_c = { { 'filename', path = 1 } },
      lualine_x = { 'encoding', 'fileformat', 'filetype' },
      lualine_y = { 'progress' },
      lualine_z = { 'location' },
    },
  },
}
```

- [ ] **Step 2: Commit**

```bash
git add lua/plugins/lualine.lua
git commit -m "feat(plugin): lualine with tokyonight theme"
```

### Task 17: Add `alpha-nvim` dashboard (tip-of-day wired in Task 31)

**Files:**
- Create: `lua/plugins/alpha.lua`

- [ ] **Step 1: Write**

```lua
-- lua/plugins/alpha.lua
return {
  'goolord/alpha-nvim',
  event = 'VimEnter',
  dependencies = { 'nvim-tree/nvim-web-devicons' },
  config = function()
    local dashboard = require('alpha.themes.dashboard')
    dashboard.section.header.val = {
      [[ ██╗  ██╗ █████╗ ██████╗ ██████╗ ██╗   ██╗      ███╗   ██╗██╗   ██╗██╗███╗   ███╗]],
      [[ ██║  ██║██╔══██╗██╔══██╗██╔══██╗╚██╗ ██╔╝      ████╗  ██║██║   ██║██║████╗ ████║]],
      [[ ███████║███████║██████╔╝██████╔╝ ╚████╔╝ █████╗██╔██╗ ██║██║   ██║██║██╔████╔██║]],
      [[ ██╔══██║██╔══██║██╔═══╝ ██╔═══╝   ╚██╔╝  ╚════╝██║╚██╗██║╚██╗ ██╔╝██║██║╚██╔╝██║]],
      [[ ██║  ██║██║  ██║██║     ██║        ██║         ██║ ╚████║ ╚████╔╝ ██║██║ ╚═╝ ██║]],
      [[ ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝     ╚═╝        ╚═╝         ╚═╝  ╚═══╝  ╚═══╝  ╚═╝╚═╝     ╚═╝]],
    }
    dashboard.section.buttons.val = {
      dashboard.button('e', '  New file', '<cmd>ene<CR>'),
      dashboard.button('f', '  Find file', '<cmd>Telescope find_files<CR>'),
      dashboard.button('r', '  Recent', '<cmd>Telescope oldfiles<CR>'),
      dashboard.button('q', '  Quit', '<cmd>qa<CR>'),
    }
    -- Tip-of-day footer wired in Task 31
    dashboard.section.footer.val = ''
    require('alpha').setup(dashboard.config)
  end,
}
```

- [ ] **Step 2: Commit**

```bash
git add lua/plugins/alpha.lua
git commit -m "feat(plugin): alpha-nvim dashboard (footer wired for tip-of-day in Task 31)"
```

### Task 18: Add `telescope` + `telescope-fzf-native`

**Files:**
- Create: `lua/plugins/telescope.lua`

- [ ] **Step 1: Write**

```lua
-- lua/plugins/telescope.lua
return {
  {
    'nvim-telescope/telescope.nvim',
    tag = '0.1.8',
    cmd = 'Telescope',
    keys = {
      { '<leader>ff', '<cmd>Telescope find_files<cr>', desc = 'find files' },
      { '<leader>fg', '<cmd>Telescope git_files<cr>', desc = 'git files' },
      { '<leader>fb', '<cmd>Telescope buffers<cr>', desc = 'buffers' },
      { '<leader>fh', '<cmd>Telescope help_tags<cr>', desc = 'help tags' },
      { '<leader>fr', '<cmd>Telescope oldfiles<cr>', desc = 'recent files' },
      {
        '<leader>fs',
        function()
          require('telescope.builtin').grep_string({
            search = vim.fn.input('Grep > '),
          })
        end,
        desc = 'grep string',
      },
      { '<leader>fw', '<cmd>Telescope live_grep<cr>', desc = 'live grep' },
    },
    dependencies = {
      'nvim-lua/plenary.nvim',
      { 'nvim-telescope/telescope-fzf-native.nvim', build = 'make' },
    },
    config = function()
      local telescope = require('telescope')
      telescope.setup({
        defaults = {
          path_display = { 'truncate' },
          sorting_strategy = 'ascending',
          layout_config = { prompt_position = 'top' },
        },
      })
      telescope.load_extension('fzf')
    end,
  },
}
```

- [ ] **Step 2: Commit**

```bash
git add lua/plugins/telescope.lua
git commit -m "feat(plugin): telescope + fzf-native with <leader>f* keymaps"
```

### Task 19: Add `harpoon` (branch: harpoon2)

**Files:**
- Create: `lua/plugins/harpoon.lua`

- [ ] **Step 1: Write**

```lua
-- lua/plugins/harpoon.lua
return {
  'ThePrimeagen/harpoon',
  branch = 'harpoon2',
  event = 'VeryLazy',
  dependencies = { 'nvim-lua/plenary.nvim' },
  config = function()
    local harpoon = require('harpoon')
    harpoon:setup()
    local map = vim.keymap.set
    map('n', '<leader>ha', function()
      harpoon:list():add()
    end, { desc = 'harpoon add' })
    map('n', '<C-e>', function()
      harpoon.ui:toggle_quick_menu(harpoon:list())
    end, { desc = 'harpoon menu' })
    map('n', '<C-h>', function()
      harpoon:list():select(1)
    end)
    map('n', '<C-t>', function()
      harpoon:list():select(2)
    end)
    map('n', '<C-n>', function()
      harpoon:list():select(3)
    end)
    map('n', '<C-s>', function()
      harpoon:list():select(4)
    end)
  end,
}
```

- [ ] **Step 2: Commit**

```bash
git add lua/plugins/harpoon.lua
git commit -m "feat(plugin): harpoon2 with <leader>ha + C-h/t/n/s quick-nav"
```

### Task 20: Add `undotree`, `fugitive`, `gitsigns`

**Files:**
- Create: `lua/plugins/undotree.lua`
- Create: `lua/plugins/fugitive.lua`
- Create: `lua/plugins/gitsigns.lua`

- [ ] **Step 1: Write `undotree.lua`**

```lua
return {
  'mbbill/undotree',
  cmd = 'UndotreeToggle',
  keys = { { '<leader>u', '<cmd>UndotreeToggle<cr>', desc = 'undo tree' } },
}
```

- [ ] **Step 2: Write `fugitive.lua`**

```lua
return {
  'tpope/vim-fugitive',
  cmd = { 'Git', 'Gdiffsplit', 'Gvdiffsplit' },
  keys = { { '<leader>gs', '<cmd>Git<cr>', desc = 'git status' } },
}
```

- [ ] **Step 3: Write `gitsigns.lua`**

```lua
return {
  'lewis6991/gitsigns.nvim',
  event = { 'BufReadPre', 'BufNewFile' },
  opts = {
    signs = {
      add = { text = '│' },
      change = { text = '│' },
      delete = { text = '_' },
      topdelete = { text = '‾' },
      changedelete = { text = '~' },
    },
    on_attach = function(bufnr)
      local gs = require('gitsigns')
      local map = function(m, l, r, desc)
        vim.keymap.set(m, l, r, { buffer = bufnr, desc = desc })
      end
      map('n', ']h', gs.next_hunk, 'next hunk')
      map('n', '[h', gs.prev_hunk, 'prev hunk')
      map('n', '<leader>gp', gs.preview_hunk, 'preview hunk')
      map('n', '<leader>gb', function()
        gs.blame_line({ full = true })
      end, 'blame line')
      map('n', '<leader>gr', gs.reset_hunk, 'reset hunk')
    end,
  },
}
```

- [ ] **Step 4: Commit**

```bash
git add lua/plugins/undotree.lua lua/plugins/fugitive.lua lua/plugins/gitsigns.lua
git commit -m "feat(plugin): undotree, fugitive, gitsigns"
```

### End-of-Phase-2 smoke

```bash
HOME=/tmp/happy-nvim-test-home nvim --headless -c 'Lazy sync' -c 'qa!' 2>&1 | tail -5
HOME=/tmp/happy-nvim-test-home nvim --headless -c 'lua print(vim.g.colors_name)' -c 'qa!'
```

Expected: prints `tokyonight`. No load errors.

---

## Phase 3 — LSP, completion, treesitter, formatting (Tasks 21–26)

### Task 21: Add treesitter + textobjects

**Files:**
- Create: `lua/plugins/treesitter.lua`

- [ ] **Step 1: Write**

```lua
-- lua/plugins/treesitter.lua
return {
  {
    'nvim-treesitter/nvim-treesitter',
    event = { 'BufReadPre', 'BufNewFile' },
    build = ':TSUpdate',
    dependencies = { 'nvim-treesitter/nvim-treesitter-textobjects' },
    config = function()
      require('nvim-treesitter.configs').setup({
        ensure_installed = {
          'lua', 'vim', 'vimdoc', 'query',
          'python', 'go', 'c', 'cpp',
          'bash', 'yaml', 'markdown', 'markdown_inline',
          'json', 'toml',
        },
        highlight = { enable = true },
        indent = { enable = true },
        textobjects = {
          select = {
            enable = true,
            lookahead = true,
            keymaps = {
              ['af'] = '@function.outer',
              ['if'] = '@function.inner',
              ['ac'] = '@class.outer',
              ['ic'] = '@class.inner',
              ['ap'] = '@parameter.outer',
              ['ip'] = '@parameter.inner',
            },
          },
          move = {
            enable = true,
            set_jumps = true,
            goto_next_start = { [']f'] = '@function.outer' },
            goto_previous_start = { ['[f'] = '@function.outer' },
          },
        },
      })
    end,
  },
}
```

- [ ] **Step 2: Verify parser installation**

```bash
HOME=/tmp/happy-nvim-test-home nvim --headless -c 'TSUpdate' -c 'qa!' 2>&1 | tail -5
```

- [ ] **Step 3: Commit**

```bash
git add lua/plugins/treesitter.lua
git commit -m "feat(plugin): treesitter + textobjects for py/go/c/cpp/lua/bash/yaml/md"
```

### Task 22: Add mason + mason-lspconfig + mason-tool-installer + lspconfig

**Files:**
- Create: `lua/plugins/lsp.lua`

- [ ] **Step 1: Write**

```lua
-- lua/plugins/lsp.lua
return {
  {
    'williamboman/mason.nvim',
    cmd = 'Mason',
    build = ':MasonUpdate',
    opts = {},
  },
  {
    'williamboman/mason-lspconfig.nvim',
    event = { 'BufReadPre', 'BufNewFile' },
    dependencies = { 'williamboman/mason.nvim' },
  },
  {
    'WhoIsSethDaniel/mason-tool-installer.nvim',
    event = 'VeryLazy',
    dependencies = { 'williamboman/mason.nvim' },
    opts = {
      ensure_installed = {
        -- formatters
        'stylua', 'ruff', 'goimports', 'gofumpt', 'shfmt', 'yamlfmt', 'clang-format',
        -- linters
        'selene',
      },
    },
  },
  {
    'neovim/nvim-lspconfig',
    event = { 'BufReadPre', 'BufNewFile' },
    dependencies = {
      'williamboman/mason-lspconfig.nvim',
      'saghen/blink.cmp',
    },
    config = function()
      local lspconfig = require('lspconfig')
      local capabilities = require('blink.cmp').get_lsp_capabilities()

      -- LspAttach keymaps (spec §BUG-2 namespace: <leader>l*, diagnostics d*)
      vim.api.nvim_create_autocmd('LspAttach', {
        group = vim.api.nvim_create_augroup('happy_lsp_attach', { clear = true }),
        callback = function(ev)
          local map = function(lhs, rhs, desc)
            vim.keymap.set('n', lhs, rhs, { buffer = ev.buf, desc = desc })
          end
          map('gd', vim.lsp.buf.definition, 'goto definition')
          map('gD', vim.lsp.buf.declaration, 'goto declaration')
          map('gi', vim.lsp.buf.implementation, 'goto implementation')
          map('go', vim.lsp.buf.type_definition, 'goto type def')
          map('gr', vim.lsp.buf.references, 'references')
          map('K', vim.lsp.buf.hover, 'hover')
          map('<leader>la', vim.lsp.buf.code_action, 'code action')
          map('<leader>lr', vim.lsp.buf.rename, 'rename')
          map('<leader>de', vim.diagnostic.open_float, 'diag float')
          map('<leader>dn', function() vim.diagnostic.goto_next() end, 'next diag')
          map('<leader>dp', function() vim.diagnostic.goto_prev() end, 'prev diag')
        end,
      })

      -- Server setup via mason-lspconfig
      require('mason-lspconfig').setup({
        ensure_installed = {
          'lua_ls', 'pylsp', 'gopls', 'bashls', 'yamlls',
          'marksman', 'clangd',
        },
        handlers = {
          function(server)
            lspconfig[server].setup({ capabilities = capabilities })
          end,
          ['pylsp'] = function()
            lspconfig.pylsp.setup({
              capabilities = capabilities,
              settings = {
                pylsp = {
                  plugins = {
                    mypy = { enabled = true, live_mode = false },
                    ruff = { enabled = true },
                  },
                },
              },
            })
          end,
          ['lua_ls'] = function()
            lspconfig.lua_ls.setup({
              capabilities = capabilities,
              settings = {
                Lua = {
                  workspace = { checkThirdParty = false },
                  diagnostics = { globals = { 'vim' } },
                  telemetry = { enable = false },
                },
              },
            })
          end,
        },
      })
    end,
  },
}
```

- [ ] **Step 2: Commit**

```bash
git add lua/plugins/lsp.lua
git commit -m "feat(lsp): mason + lspconfig for py/go/lua/bash/yaml/md/cpp w/ <leader>l* keymaps"
```

### Task 23: Add `blink.cmp` + LuaSnip

**Files:**
- Create: `lua/plugins/completion.lua`

- [ ] **Step 1: Write**

```lua
-- lua/plugins/completion.lua
return {
  {
    'saghen/blink.cmp',
    version = 'v0.7.*',
    event = 'InsertEnter',
    dependencies = { 'L3MON4D3/LuaSnip', version = 'v2.*' },
    opts = {
      keymap = { preset = 'default' },
      sources = {
        default = { 'lsp', 'path', 'snippets', 'buffer' },
      },
      completion = {
        documentation = { auto_show = true, auto_show_delay_ms = 300 },
      },
      snippets = { preset = 'luasnip' },
    },
  },
}
```

- [ ] **Step 2: Commit**

```bash
git add lua/plugins/completion.lua
git commit -m "feat(plugin): blink.cmp + LuaSnip completion"
```

### Task 24: Add conform.nvim (single owner for format-on-save per BUG-1)

**Files:**
- Create: `lua/plugins/conform.lua`

- [ ] **Step 1: Write**

```lua
-- lua/plugins/conform.lua — single source of truth for formatting (spec §BUG-1)
return {
  'stevearc/conform.nvim',
  event = { 'BufWritePre' },
  cmd = 'ConformInfo',
  opts = {
    formatters_by_ft = {
      lua = { 'stylua' },
      python = { 'ruff_format', 'ruff_organize_imports' },
      go = { 'goimports', 'gofumpt' },
      javascript = { 'biome' },
      typescript = { 'biome' },
      sh = { 'shfmt' },
      yaml = { 'yamlfmt' },
      cpp = { 'clang-format' },
      c = { 'clang-format' },
    },
    format_on_save = { timeout_ms = 500, lsp_fallback = true },
  },
  keys = {
    {
      '<leader>lf',
      function()
        require('conform').format({ async = true, lsp_fallback = true })
      end,
      mode = { 'n', 'v' },
      desc = 'format buffer',
    },
  },
}
```

- [ ] **Step 2: Commit**

```bash
git add lua/plugins/conform.lua
git commit -m "feat(plugin): conform.nvim single-owner format-on-save (spec §BUG-1)"
```

### Task 25: Add nvim-lint

**Files:**
- Create: `lua/plugins/lint.lua`

- [ ] **Step 1: Write**

```lua
-- lua/plugins/lint.lua
return {
  'mfussenegger/nvim-lint',
  event = { 'BufReadPre', 'BufNewFile' },
  config = function()
    local lint = require('lint')
    lint.linters_by_ft = {
      lua = { 'selene' },
    }
    vim.api.nvim_create_autocmd({ 'BufWritePost', 'BufReadPost' }, {
      group = vim.api.nvim_create_augroup('happy_lint', { clear = true }),
      callback = function()
        lint.try_lint()
      end,
    })
  end,
}
```

- [ ] **Step 2: Commit**

```bash
git add lua/plugins/lint.lua
git commit -m "feat(plugin): nvim-lint with selene for lua"
```

### Task 26: End-of-Phase-3 smoke test

- [ ] **Step 1: Headless sync + checkhealth**

```bash
HOME=/tmp/happy-nvim-test-home nvim --headless -c 'Lazy sync' -c 'qa!' 2>&1 | tail -10
HOME=/tmp/happy-nvim-test-home nvim --headless -c 'checkhealth lsp' -c 'qa!' 2>&1 | grep -E 'ERROR|WARNING' | head -5
```

Expected: Lazy sync prints no errors. LSP checkhealth may show warnings for servers not yet installed via mason — acceptable.

- [ ] **Step 2: Open a lua file, save, confirm format**

```bash
cd /tmp && cat > fmt_test.lua <<'EOF'
local x=1;local y=2
EOF
HOME=/tmp/happy-nvim-test-home nvim --headless -c 'e /tmp/fmt_test.lua' -c 'w' -c 'qa!' 2>&1 | tail -5
cat /tmp/fmt_test.lua
```

Expected: file reformatted by stylua (indentation, semicolon removal).

- [ ] **Step 3: Commit nothing (verification only)**

---

## Phase 4 — Macro-nudge layer (Tasks 27–32)

### Task 27: Add `hardtime.nvim`

**Files:**
- Create: `lua/plugins/hardtime.lua`

- [ ] **Step 1: Write**

```lua
-- lua/plugins/hardtime.lua
return {
  'm4xshen/hardtime.nvim',
  event = 'VeryLazy',
  dependencies = { 'MunifTanjim/nui.nvim' },
  opts = {
    disable_mouse = false,
    max_count = 3, -- after 3 hjkl/arrows in a row, suggest {count}j / }
    restriction_mode = 'hint', -- not 'block' — start softly; upgrade later
    hint = true,
  },
}
```

- [ ] **Step 2: Commit**

```bash
git add lua/plugins/hardtime.lua
git commit -m "feat(plugin): hardtime.nvim in hint-only mode"
```

### Task 28: Add `precognition.nvim`

**Files:**
- Create: `lua/plugins/precognition.lua`

- [ ] **Step 1: Write**

```lua
-- lua/plugins/precognition.lua — ambient motion hints (spec §5.1.5)
return {
  'tris203/precognition.nvim',
  event = 'VeryLazy',
  opts = {
    startVisible = true,
    showBlankVirtLine = true,
    hints = {
      Caret = { text = '^', prio = 2 },
      Dollar = { text = '$', prio = 1 },
      MatchingPair = { text = '%', prio = 5 },
      Zero = { text = '0', prio = 1 },
      w = { text = 'w', prio = 10 },
      b = { text = 'b', prio = 9 },
      e = { text = 'e', prio = 8 },
      W = { text = 'W', prio = 7 },
      B = { text = 'B', prio = 6 },
      E = { text = 'E', prio = 5 },
    },
  },
  keys = {
    { '<leader>?p', '<cmd>Precognition toggle<cr>', desc = 'toggle precognition hints' },
  },
}
```

- [ ] **Step 2: Commit**

```bash
git add lua/plugins/precognition.lua
git commit -m "feat(plugin): precognition.nvim ambient motion hints w/ <leader>?p toggle"
```

### Task 29: Add `vim-surround` + `vim-repeat`

**Files:**
- Create: `lua/plugins/surround.lua`
- Create: `lua/plugins/repeat.lua`

- [ ] **Step 1: Write both**

```lua
-- lua/plugins/surround.lua
return { 'tpope/vim-surround', event = 'VeryLazy' }
```

```lua
-- lua/plugins/repeat.lua
return { 'tpope/vim-repeat', event = 'VeryLazy' }
```

- [ ] **Step 2: Commit**

```bash
git add lua/plugins/surround.lua lua/plugins/repeat.lua
git commit -m "feat(plugin): vim-surround + vim-repeat"
```

### Task 30: Build `coach/` module — tips + cheatsheet picker (TDD)

**Files:**
- Create: `lua/coach/tips.lua`
- Create: `lua/coach/init.lua`
- Create: `tests/coach_spec.lua`
- Modify: `init.lua` (add `try_require('coach')`)

- [ ] **Step 1: Write failing test**

```lua
-- tests/coach_spec.lua
describe('coach', function()
  local coach

  before_each(function()
    package.loaded['coach'] = nil
    package.loaded['coach.tips'] = nil
    coach = require('coach')
  end)

  it('exposes random_tip() that returns a tip table', function()
    local tip = coach.random_tip()
    assert.is_table(tip)
    assert.is_string(tip.keys)
    assert.is_string(tip.desc)
    assert.is_string(tip.category)
  end)

  it('random_tip() returns nil when tips is empty', function()
    package.loaded['coach.tips'] = {}
    package.loaded['coach'] = nil
    local c = require('coach')
    assert.is_nil(c.random_tip())
  end)

  it('next_tip() advances through the list without repeating consecutively', function()
    local seen = {}
    for _ = 1, 5 do
      local t = coach.next_tip()
      assert.is_table(t)
      table.insert(seen, t.keys)
    end
    -- At least two distinct tips across 5 calls (valid when tips >= 2)
    local unique = {}
    for _, k in ipairs(seen) do
      unique[k] = true
    end
    local count = 0
    for _ in pairs(unique) do
      count = count + 1
    end
    assert.is_true(count >= 2)
  end)
end)
```

- [ ] **Step 2: Run to verify FAIL**

```bash
nvim --headless -u tests/minimal_init.lua \
  -c "PlenaryBustedFile tests/coach_spec.lua" -c 'qa!'
```

Expected: FAIL with `module 'coach' not found`.

- [ ] **Step 3: Write `lua/coach/tips.lua` with 30 seed tips**

```lua
-- lua/coach/tips.lua
return {
  -- text-objects
  { keys = 'ciw', desc = 'change inside word', category = 'text-objects' },
  { keys = 'ci"', desc = 'change inside double quotes', category = 'text-objects' },
  { keys = "ci'", desc = 'change inside single quotes', category = 'text-objects' },
  { keys = 'ci(', desc = 'change inside parens', category = 'text-objects' },
  { keys = 'ci[', desc = 'change inside brackets', category = 'text-objects' },
  { keys = 'ci{', desc = 'change inside braces', category = 'text-objects' },
  { keys = 'cit', desc = 'change inside XML/HTML tag', category = 'text-objects' },
  { keys = 'dap', desc = 'delete a paragraph (with trailing blank)', category = 'text-objects' },
  { keys = 'vip', desc = 'visual-select inside paragraph', category = 'text-objects' },
  { keys = 'daf', desc = 'delete a function (treesitter)', category = 'text-objects' },
  -- motions
  { keys = 'f<char>', desc = 'jump forward to next <char> on line', category = 'motions' },
  { keys = 'F<char>', desc = 'jump backward to <char> on line', category = 'motions' },
  { keys = 't<char>', desc = 'jump to just-before <char> on line', category = 'motions' },
  { keys = '%', desc = 'jump to matching (/)/[/]/{/}', category = 'motions' },
  { keys = 'gg / G', desc = 'jump to file top / bottom', category = 'motions' },
  -- macros
  { keys = 'qa...q', desc = 'record macro into register a (q again to stop)', category = 'macros' },
  { keys = '@a', desc = 'replay macro a', category = 'macros' },
  { keys = '@@', desc = 'replay the last macro', category = 'macros' },
  { keys = '10@a', desc = 'replay macro a ten times', category = 'macros' },
  -- marks
  { keys = "ma / 'a", desc = 'set mark a / jump to line of mark a', category = 'marks' },
  { keys = "mA / 'A", desc = 'set global mark A (cross-file) / jump', category = 'marks' },
  { keys = "''", desc = 'jump back to previous position', category = 'marks' },
  -- registers
  { keys = '"ayy', desc = 'yank line into register a', category = 'registers' },
  { keys = '"+y', desc = 'yank into system clipboard', category = 'registers' },
  { keys = ':reg', desc = 'list all registers', category = 'registers' },
  -- search
  { keys = '*', desc = 'search forward for word under cursor', category = 'search' },
  { keys = 'n / N', desc = 'next / prev search match', category = 'search' },
  -- window
  { keys = '<C-w>v', desc = 'split window vertical', category = 'window' },
  { keys = '<C-w>=', desc = 'balance all splits', category = 'window' },
  -- lsp
  { keys = 'gd', desc = 'LSP: goto definition', category = 'lsp' },
  { keys = 'K', desc = 'LSP: hover docs', category = 'lsp' },
  { keys = '<leader>la', desc = 'LSP: code action', category = 'lsp' },
}
```

- [ ] **Step 4: Write `lua/coach/init.lua`**

```lua
-- lua/coach/init.lua
local M = {}

local tips = require('coach.tips')
local last_idx = nil

function M.random_tip()
  if #tips == 0 then
    return nil
  end
  return tips[math.random(#tips)]
end

function M.next_tip()
  if #tips == 0 then
    return nil
  end
  if #tips == 1 then
    last_idx = 1
    return tips[1]
  end
  local idx = math.random(#tips)
  while idx == last_idx do
    idx = math.random(#tips)
  end
  last_idx = idx
  return tips[idx]
end

function M.open_cheatsheet()
  local ok, pickers = pcall(require, 'telescope.pickers')
  if not ok then
    vim.notify('telescope not available', vim.log.levels.ERROR)
    return
  end
  local finders = require('telescope.finders')
  local conf = require('telescope.config').values

  pickers
    .new({}, {
      prompt_title = 'coach cheatsheet',
      finder = finders.new_table({
        results = tips,
        entry_maker = function(t)
          return {
            value = t,
            display = string.format('%-20s  %-18s  %s', t.keys, '[' .. t.category .. ']', t.desc),
            ordinal = t.keys .. ' ' .. t.category .. ' ' .. t.desc,
          }
        end,
      }),
      sorter = conf.generic_sorter({}),
    })
    :find()
end

function M.setup()
  vim.keymap.set('n', '<leader>?', M.open_cheatsheet, { desc = 'open cheatsheet' })
  vim.keymap.set('n', '<leader>??', function()
    local t = M.next_tip()
    if t then
      vim.notify(string.format('%s — %s (%s)', t.keys, t.desc, t.category))
    end
  end, { desc = 'next tip' })
end

return M
```

- [ ] **Step 5: Run test to verify PASS**

Same command as Step 2. Expected: `Success: 3 / Failed: 0`.

- [ ] **Step 6: Wire `coach.setup()` from `init.lua`**

Edit `/home/raul/projects/happy-nvim/init.lua`, add after `try_require('config.lazy')`:

```lua
-- Modules load after lazy so they can use telescope etc.
vim.api.nvim_create_autocmd('User', {
  pattern = 'LazyDone',
  once = true,
  callback = function()
    local ok, coach = pcall(require, 'coach')
    if ok then coach.setup() end
  end,
})
```

- [ ] **Step 7: Commit**

```bash
git add lua/coach/ tests/coach_spec.lua init.lua
git commit -m "feat(coach): tips table (30 seeds) + cheatsheet picker + <leader>?/??"
```

### Task 31: Wire tip-of-day into alpha dashboard footer

**Files:**
- Modify: `lua/plugins/alpha.lua`

- [ ] **Step 1: Update alpha.lua to read coach.random_tip()**

Replace the `dashboard.section.footer.val = ''` line with:

```lua
local ok, coach = pcall(require, 'coach')
if ok then
  local t = coach.random_tip()
  if t then
    dashboard.section.footer.val = string.format('Tip: %s — %s (%s)', t.keys, t.desc, t.category)
  end
end
```

- [ ] **Step 2: Verify manually**

```bash
HOME=/tmp/happy-nvim-test-home nvim --headless -c 'lua vim.defer_fn(function() vim.cmd("qa!") end, 500)' 2>&1 | head
```

- [ ] **Step 3: Commit**

```bash
git add lua/plugins/alpha.lua
git commit -m "feat(coach): wire tip-of-day into alpha dashboard footer"
```

### Task 32: End-of-Phase-4 smoke

- [ ] Headless sync: `HOME=/tmp/happy-nvim-test-home nvim --headless -c 'Lazy sync' -c 'qa!' 2>&1 | tail -5`
- [ ] Run all plenary tests: `nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedDirectory tests/ {minimal_init='tests/minimal_init.lua'}" -c 'qa!'`
- [ ] Expected: all tests pass, no Lazy errors.

---

## Phase 5 — Clipboard module (Tasks 33–34)

### Task 33: Build `clipboard/` OSC 52 hook (TDD)

**Files:**
- Create: `lua/clipboard/init.lua`
- Create: `tests/clipboard_spec.lua`
- Modify: `init.lua`

- [ ] **Step 1: Write failing test**

```lua
-- tests/clipboard_spec.lua
describe('clipboard', function()
  local clip

  before_each(function()
    package.loaded['clipboard'] = nil
    clip = require('clipboard')
  end)

  it('encode_osc52() returns correct escape sequence for "hello"', function()
    local seq = clip._encode_osc52('hello')
    -- base64 of "hello" = "aGVsbG8="
    assert.are.equal('\027]52;c;aGVsbG8=\007', seq)
  end)

  it('encode_osc52() returns nil for content exceeding 74KB base64 cap', function()
    local huge = string.rep('x', 60 * 1024) -- ~80KB base64
    assert.is_nil(clip._encode_osc52(huge))
  end)

  it('should_emit() respects SSH_TTY / TMUX guard', function()
    local old_ssh = vim.env.SSH_TTY
    local old_tmux = vim.env.TMUX
    vim.env.SSH_TTY = nil
    vim.env.TMUX = nil
    assert.is_false(clip._should_emit())
    vim.env.TMUX = '/tmp/tmux-1000/default,123,0'
    assert.is_true(clip._should_emit())
    vim.env.SSH_TTY = old_ssh
    vim.env.TMUX = old_tmux
  end)
end)
```

- [ ] **Step 2: Run to verify FAIL**

```bash
nvim --headless -u tests/minimal_init.lua \
  -c "PlenaryBustedFile tests/clipboard_spec.lua" -c 'qa!'
```

Expected: FAIL.

- [ ] **Step 3: Write `lua/clipboard/init.lua`**

```lua
-- lua/clipboard/init.lua — OSC 52 dual-clipboard hook (spec §5.2)
local M = {}

-- 74KB cap on base64 payload (some terminals reject larger)
local MAX_B64 = 74 * 1024

function M._should_emit()
  return (vim.env.SSH_TTY ~= nil and vim.env.SSH_TTY ~= '')
    or (vim.env.TMUX ~= nil and vim.env.TMUX ~= '')
end

function M._encode_osc52(content)
  local b64 = vim.base64.encode(content)
  if #b64 > MAX_B64 then
    return nil
  end
  return string.format('\027]52;c;%s\007', b64)
end

function M._emit(seq)
  io.stdout:write(seq)
  io.stdout:flush()
end

function M.setup()
  local aug = vim.api.nvim_create_augroup('happy_clipboard', { clear = true })
  vim.api.nvim_create_autocmd('TextYankPost', {
    group = aug,
    callback = function()
      if vim.v.event.operator ~= 'y' then
        return
      end
      if not M._should_emit() then
        return
      end
      local content = table.concat(vim.v.event.regcontents, '\n')
      local seq = M._encode_osc52(content)
      if seq == nil then
        vim.notify('happy-nvim: yank too large for OSC52 (host clipboard skipped)', vim.log.levels.WARN)
        return
      end
      M._emit(seq)
    end,
  })
end

return M
```

- [ ] **Step 4: Verify PASS**

Same command as Step 2. Expected: all 3 tests pass.

- [ ] **Step 5: Wire into `init.lua`**

Inside the existing `User LazyDone` autocmd, add after `coach.setup()`:

```lua
local ok_c, clipboard = pcall(require, 'clipboard')
if ok_c then clipboard.setup() end
```

- [ ] **Step 6: Commit**

```bash
git add lua/clipboard/ tests/clipboard_spec.lua init.lua
git commit -m "feat(clipboard): OSC 52 TextYankPost hook (spec §5.2)"
```

### Task 34: Manual verification of dual-clipboard

- [ ] **Step 1: In your real tmux session, launch happy-nvim and yank text**

Open nvim on a real VM through mosh+tmux, open any file, press `yy`.

- [ ] **Step 2: Check VM clipboard**

```bash
xclip -o -selection clipboard  # or wl-paste
```

Expected: prints the yanked line.

- [ ] **Step 3: Check host clipboard**

On your host laptop, try `Cmd+V` / `Ctrl+V` into any text field.

Expected: host clipboard contains the yanked line.

- [ ] **Step 4: If it fails, run `:checkhealth happy-nvim`**

Health probes for tmux `set-clipboard`, `allow-passthrough`, mosh version are added in Task 49.

---

## Phase 6 — Tmux + Claude integration (Tasks 35–40)

### Task 35: Add `vim-tmux-navigator`

**Files:**
- Create: `lua/plugins/tmux-nav.lua`

- [ ] **Step 1: Write**

```lua
-- lua/plugins/tmux-nav.lua
return {
  'christoomey/vim-tmux-navigator',
  cmd = {
    'TmuxNavigateLeft', 'TmuxNavigateDown',
    'TmuxNavigateUp', 'TmuxNavigateRight',
  },
  keys = {
    { '<C-h>', '<cmd>TmuxNavigateLeft<cr>' },
    { '<C-j>', '<cmd>TmuxNavigateDown<cr>' },
    { '<C-k>', '<cmd>TmuxNavigateUp<cr>' },
    { '<C-l>', '<cmd>TmuxNavigateRight<cr>' },
  },
}
```

> Note: `<C-h>` / `<C-k>` conflict with harpoon bindings from Task 19. Resolve here — tmux-nav wins for these keys; harpoon slot 1 moves to `<leader>h1`.

- [ ] **Step 2: Edit `lua/plugins/harpoon.lua`** — replace `<C-h>` with `<leader>h1`, `<C-k>` keep (harpoon doesn't use it), etc. Final harpoon maps:

```lua
map('n', '<leader>h1', function() harpoon:list():select(1) end)
map('n', '<leader>h2', function() harpoon:list():select(2) end)
map('n', '<leader>h3', function() harpoon:list():select(3) end)
map('n', '<leader>h4', function() harpoon:list():select(4) end)
```

Remove the old `<C-h>`, `<C-t>`, `<C-n>`, `<C-s>` lines (note: `<C-t>` and `<C-n>` don't conflict, but consolidating under `<leader>h*` is cleaner per BUG-2 namespace table).

- [ ] **Step 3: Commit**

```bash
git add lua/plugins/tmux-nav.lua lua/plugins/harpoon.lua
git commit -m "feat(tmux): vim-tmux-navigator; relocate harpoon to <leader>h1-4"
```

### Task 36: Build `tmux/send.lua` — pane discovery + send-keys helper (TDD)

**Files:**
- Create: `lua/tmux/send.lua`
- Create: `tests/tmux_send_spec.lua`

- [ ] **Step 1: Write failing test**

```lua
-- tests/tmux_send_spec.lua
describe('tmux.send', function()
  local send

  before_each(function()
    package.loaded['tmux.send'] = nil
    send = require('tmux.send')
  end)

  it('_quote_for_send_keys escapes single quotes for tmux send-keys -l', function()
    -- send-keys -l sends bytes literally; no special escaping needed EXCEPT
    -- the shell-level single-quote wrapping we use. Verify single quotes are
    -- escaped as '\''
    assert.are.equal("it'\\''s", send._quote_for_send_keys("it's"))
  end)

  it('_build_send_cmd assembles the expected tmux invocation', function()
    local cmd = send._build_send_cmd('%42', 'hello world')
    assert.are.same({
      'tmux', 'send-keys', '-t', '%42', '-l', 'hello world',
    }, cmd)
  end)

  it('_build_send_cmd appends Enter helper when append_enter=true', function()
    local cmd = send._build_enter_cmd('%42')
    assert.are.same({ 'tmux', 'send-keys', '-t', '%42', 'Enter' }, cmd)
  end)
end)
```

- [ ] **Step 2: Run FAIL**

```bash
nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedFile tests/tmux_send_spec.lua" -c 'qa!'
```

- [ ] **Step 3: Write `lua/tmux/send.lua`**

```lua
-- lua/tmux/send.lua — tmux send-keys + pane discovery helpers
local M = {}

function M._quote_for_send_keys(s)
  -- For shell-level `'...'` wrapping: replace each ' with '\''
  return (s:gsub("'", "'\\''"))
end

function M._build_send_cmd(pane_id, payload)
  return { 'tmux', 'send-keys', '-t', pane_id, '-l', payload }
end

function M._build_enter_cmd(pane_id)
  return { 'tmux', 'send-keys', '-t', pane_id, 'Enter' }
end

function M.get_claude_pane_id()
  local result = vim.system({
    'tmux', 'show-option', '-w', '-v', '-q', '@claude_pane_id',
  }, { text = true }):wait()
  if result.code ~= 0 then
    return nil
  end
  local id = (result.stdout or ''):gsub('%s+$', '')
  if id == '' then
    return nil
  end
  -- Verify pane is still alive
  local alive = vim.system({ 'tmux', 'list-panes', '-t', id }, { text = true }):wait()
  if alive.code ~= 0 then
    -- Stale; clear the option
    vim.system({ 'tmux', 'set-option', '-w', '-u', '@claude_pane_id' }):wait()
    return nil
  end
  return id
end

function M.set_claude_pane_id(id)
  vim.system({ 'tmux', 'set-option', '-w', '@claude_pane_id', id }):wait()
end

function M.send_to_claude(payload)
  local id = M.get_claude_pane_id()
  if not id then
    vim.notify('No Claude pane registered. Press <leader>cc first.', vim.log.levels.WARN)
    return false
  end
  if #payload > 10 * 1024 then
    local ok = vim.fn.confirm(string.format('Send %dKB to Claude pane?', math.floor(#payload / 1024)), '&Yes\n&No') == 1
    if not ok then
      return false
    end
  end
  vim.system(M._build_send_cmd(id, payload)):wait()
  vim.system(M._build_enter_cmd(id)):wait()
  return true
end

return M
```

- [ ] **Step 4: PASS**

Same command as Step 2.

- [ ] **Step 5: Commit**

```bash
git add lua/tmux/send.lua tests/tmux_send_spec.lua
git commit -m "feat(tmux): send-keys helpers + pane discovery"
```

### Task 37: Build `tmux/claude.lua` — payload builders + `<leader>c*` cmds (TDD)

**Files:**
- Create: `lua/tmux/claude.lua`
- Create: `tests/tmux_claude_spec.lua`

- [ ] **Step 1: Write failing test**

```lua
-- tests/tmux_claude_spec.lua
describe('tmux.claude', function()
  local claude

  before_each(function()
    package.loaded['tmux.claude'] = nil
    claude = require('tmux.claude')
  end)

  it('_build_cf_payload returns @path', function()
    assert.are.equal('@src/foo.lua', claude._build_cf_payload('src/foo.lua'))
  end)

  it('_build_cs_payload builds fenced block with path:line range', function()
    local p = claude._build_cs_payload('src/foo.lua', 12, 14, 'lua', { 'local x = 1', 'local y = 2', 'local z = 3' })
    assert.is_true(p:find('@src/foo.lua:12%-14') ~= nil)
    assert.is_true(p:find('```lua') ~= nil)
    assert.is_true(p:find('local x = 1') ~= nil)
  end)

  it('_build_cs_payload switches to ~~~ fence when content has ```', function()
    local p = claude._build_cs_payload('src/foo.md', 1, 1, 'markdown', { '```python' })
    assert.is_true(p:find('~~~markdown') ~= nil)
    assert.is_false(p:find('```markdown') ~= nil)
  end)

  it('_build_ce_payload includes diagnostics bullets', function()
    local p = claude._build_ce_payload('src/foo.lua', {
      { severity = 1, message = 'undefined global', lnum = 5 },
      { severity = 2, message = 'unused var', lnum = 10 },
    })
    assert.is_true(p:find('@src/foo.lua') ~= nil)
    assert.is_true(p:find('undefined global') ~= nil)
    assert.is_true(p:find('line 5') ~= nil)
  end)
end)
```

- [ ] **Step 2: Run FAIL**

- [ ] **Step 3: Write `lua/tmux/claude.lua`**

```lua
-- lua/tmux/claude.lua — <leader>c* commands
local M = {}
local send = require('tmux.send')

function M._build_cf_payload(rel_path)
  return '@' .. rel_path
end

function M._build_cs_payload(rel_path, lstart, lend, ft, lines)
  local content = table.concat(lines, '\n')
  local fence = content:find('```', 1, true) and '~~~' or '```'
  return string.format(
    '@%s:%d-%d\n%s%s\n%s\n%s',
    rel_path, lstart, lend, fence, ft, content, fence
  )
end

local SEVERITY_NAMES = { 'ERROR', 'WARN', 'INFO', 'HINT' }

function M._build_ce_payload(rel_path, diags)
  local bullets = {}
  for _, d in ipairs(diags) do
    table.insert(bullets, string.format('- %s: %s (line %d)',
      SEVERITY_NAMES[d.severity] or 'UNKNOWN', d.message, d.lnum + (d.lnum == 0 and 0 or 0)))
  end
  return string.format('@%s\nDiagnostics:\n%s\n\nFix these.', rel_path, table.concat(bullets, '\n'))
end

local function buf_rel_path()
  return vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ':.')
end

function M.open()
  local id = send.get_claude_pane_id()
  if id then
    vim.system({ 'tmux', 'select-pane', '-t', id }):wait()
    return
  end
  local cwd = vim.fn.expand('%:p:h')
  local res = vim.system({
    'tmux', 'split-window', '-h', '-c', cwd, '-P', '-F', '#{pane_id}', 'claude',
  }, { text = true }):wait()
  if res.code == 0 then
    local new_id = (res.stdout or ''):gsub('%s+$', '')
    send.set_claude_pane_id(new_id)
  else
    vim.notify('failed to spawn Claude pane: ' .. (res.stderr or ''), vim.log.levels.ERROR)
  end
end

function M.send_file()
  send.send_to_claude(M._build_cf_payload(buf_rel_path()))
end

function M.send_selection()
  local lstart = vim.fn.getpos("'<")[2]
  local lend = vim.fn.getpos("'>")[2]
  local lines = vim.api.nvim_buf_get_lines(0, lstart - 1, lend, false)
  local ft = vim.bo.filetype
  send.send_to_claude(M._build_cs_payload(buf_rel_path(), lstart, lend, ft, lines))
end

function M.send_errors()
  local diags = vim.diagnostic.get(0)
  send.send_to_claude(M._build_ce_payload(buf_rel_path(), diags))
end

function M.setup()
  if vim.env.TMUX == nil or vim.env.TMUX == '' then
    return -- spec §7.3: module no-ops outside tmux
  end
  local map = vim.keymap.set
  map('n', '<leader>cc', M.open, { desc = 'open/attach Claude pane' })
  map('n', '<leader>cf', M.send_file, { desc = 'send file @ref' })
  map('v', '<leader>cs', M.send_selection, { desc = 'send selection' })
  map('n', '<leader>ce', M.send_errors, { desc = 'send file + diagnostics' })
end

return M
```

- [ ] **Step 4: PASS**

- [ ] **Step 5: Commit**

```bash
git add lua/tmux/claude.lua tests/tmux_claude_spec.lua
git commit -m "feat(tmux): <leader>cc/cf/cs/ce Claude integration commands"
```

### Task 38: Build `tmux/popup.lua` popup launchers

**Files:**
- Create: `lua/tmux/popup.lua`

- [ ] **Step 1: Write**

```lua
-- lua/tmux/popup.lua — wrappers around `tmux display-popup`
local M = {}

local function popup(cmd)
  vim.system({ 'tmux', 'display-popup', '-E', '-w', '80%', '-h', '80%', cmd }):wait()
end

function M.lazygit()
  popup('lazygit')
end

function M.scratch()
  local root = vim.fn.system({ 'git', 'rev-parse', '--show-toplevel' })
  root = root:gsub('%s+$', '')
  if root == '' then
    root = vim.fn.getcwd()
  end
  vim.system({ 'tmux', 'display-popup', '-E', '-w', '80%', '-h', '80%', '-d', root, 'zsh -l' }):wait()
end

function M.btop()
  popup('btop')
end

function M.setup()
  if vim.env.TMUX == nil or vim.env.TMUX == '' then
    return
  end
  local map = vim.keymap.set
  map('n', '<leader>tg', M.lazygit, { desc = 'lazygit popup' })
  map('n', '<leader>tt', M.scratch, { desc = 'scratch shell popup (git root)' })
  map('n', '<leader>tb', M.btop, { desc = 'btop popup' })
end

return M
```

- [ ] **Step 2: Commit**

```bash
git add lua/tmux/popup.lua
git commit -m "feat(tmux): popup launchers (<leader>tg/tt/tb)"
```

### Task 39: Wire `tmux/init.lua` and register from `init.lua`

**Files:**
- Create: `lua/tmux/init.lua`
- Modify: `init.lua`

- [ ] **Step 1: Write `lua/tmux/init.lua`**

```lua
-- lua/tmux/init.lua
local M = {}

function M.setup()
  if vim.env.TMUX == nil or vim.env.TMUX == '' then
    return -- spec §7.3: entire module no-ops outside tmux
  end
  require('tmux.claude').setup()
  require('tmux.popup').setup()
end

return M
```

- [ ] **Step 2: Add to the `User LazyDone` block in `init.lua`**

```lua
local ok_t, tmux = pcall(require, 'tmux')
if ok_t then tmux.setup() end
```

- [ ] **Step 3: Commit**

```bash
git add lua/tmux/init.lua init.lua
git commit -m "feat(tmux): wire tmux module from init.lua (guards on $TMUX)"
```

### Task 40: End-of-Phase-6 smoke

- [ ] Open a tmux session, run happy-nvim, test `<leader>cc` → Claude pane spawns.
- [ ] Test `<leader>cs` from a visual selection → payload arrives in Claude pane with `@file:start-end` reference and fenced code block.
- [ ] Test `<leader>tg` → lazygit popup opens.
- [ ] Run plenary tests: should all pass.

---

## Phase 7 — Remote ops (Tasks 41–48)

### Task 41: Ship `scripts/ssh-z.zsh` (optional zsh wrapper)

**Files:**
- Create: `scripts/ssh-z.zsh`

- [ ] **Step 1: Write**

```bash
# scripts/ssh-z.zsh
# Source from ~/.zshrc:
#   source /path/to/happy-nvim/scripts/ssh-z.zsh
# Wraps ssh and mosh to log every connection to happy-nvim's frecency DB.

_happy_host_db="${XDG_DATA_HOME:-$HOME/.local/share}/happy-nvim/hosts.json"

_happy_log_host() {
  local host="$1"
  [[ -z "$host" ]] && return
  mkdir -p "$(dirname "$_happy_host_db")"
  [[ -f "$_happy_host_db" ]] || echo '{}' > "$_happy_host_db"
  local now=$(date +%s)
  # jq -e ensures we fail gracefully if the file is malformed
  local updated=$(jq --arg host "$host" --argjson now "$now" \
    '.[$host] = { visits: ((.[$host].visits // 0) + 1), last_used: $now }' \
    "$_happy_host_db" 2>/dev/null)
  if [[ -n "$updated" ]]; then
    printf '%s' "$updated" > "$_happy_host_db"
  fi
}

ssh() {
  # Extract host argument (first non-flag positional)
  local host=""
  for arg in "$@"; do
    case "$arg" in
      -*) ;;
      *) host="$arg"; break ;;
    esac
  done
  _happy_log_host "$host"
  command ssh "$@"
}

mosh() {
  local host=""
  for arg in "$@"; do
    case "$arg" in
      -*|--*) ;;
      *) host="$arg"; break ;;
    esac
  done
  _happy_log_host "$host"
  command mosh "$@"
}
```

- [ ] **Step 2: Commit**

```bash
git add scripts/ssh-z.zsh
git commit -m "feat(remote): ship ssh-z.zsh passive host logger"
```

### Task 42: Build `remote/hosts.lua` — frecency DB + picker (TDD)

**Files:**
- Create: `lua/remote/hosts.lua`
- Create: `tests/remote_hosts_spec.lua`

- [ ] **Step 1: Write failing test**

```lua
-- tests/remote_hosts_spec.lua
describe('remote.hosts', function()
  local hosts

  before_each(function()
    package.loaded['remote.hosts'] = nil
    hosts = require('remote.hosts')
  end)

  it('_score applies exp decay over days', function()
    local now = 1000000
    -- 10 visits, last_used = now → score ≈ 10
    assert.is_true(math.abs(hosts._score({ visits = 10, last_used = now }, now) - 10) < 0.01)
    -- 10 visits, 14 days ago → score ≈ 10/e ≈ 3.68
    local fourteen_days = 14 * 86400
    local score = hosts._score({ visits = 10, last_used = now - fourteen_days }, now)
    assert.is_true(score < 4 and score > 3)
  end)

  it('_merge merges frecency DB with ssh_config hosts (DB wins on rank, config adds unknown)', function()
    local db = { alpha = { visits = 5, last_used = 1000 } }
    local config = { 'alpha', 'beta', 'gamma' }
    local merged = hosts._merge(db, config, 2000)
    assert.are.equal(3, #merged)
    -- alpha first (highest score)
    assert.are.equal('alpha', merged[1].host)
    assert.is_true(merged[1].score > 0)
    -- beta + gamma have 0 score
    assert.are.equal(0, merged[2].score)
  end)
end)
```

- [ ] **Step 2: FAIL**

- [ ] **Step 3: Write `lua/remote/hosts.lua`**

```lua
-- lua/remote/hosts.lua
local M = {}

local DB_PATH = vim.fn.stdpath('data') .. '/happy-nvim/hosts.json'

function M._score(entry, now)
  local days_since = (now - entry.last_used) / 86400
  return entry.visits * math.exp(-days_since / 14)
end

function M._read_db()
  local f = io.open(DB_PATH, 'r')
  if not f then return {} end
  local raw = f:read('*a')
  f:close()
  local ok, db = pcall(vim.json.decode, raw)
  if not ok then
    vim.fn.delete(DB_PATH)
    return {}
  end
  return db or {}
end

function M._parse_ssh_config()
  local path = vim.fn.expand('~/.ssh/config')
  if vim.fn.filereadable(path) == 0 then
    return {}
  end
  local hosts = {}
  for line in io.lines(path) do
    local h = line:match('^%s*[Hh]ost%s+(.+)$')
    if h then
      for part in h:gmatch('%S+') do
        if not part:find('[*?]') then
          table.insert(hosts, part)
        end
      end
    end
  end
  return hosts
end

function M._merge(db, config_hosts, now)
  local seen = {}
  local out = {}
  for host, entry in pairs(db) do
    table.insert(out, { host = host, score = M._score(entry, now) })
    seen[host] = true
  end
  for _, host in ipairs(config_hosts) do
    if not seen[host] then
      table.insert(out, { host = host, score = 0 })
    end
  end
  table.sort(out, function(a, b) return a.score > b.score end)
  return out
end

function M.pick()
  local db = M._read_db()
  local cfg = M._parse_ssh_config()
  local merged = M._merge(db, cfg, os.time())
  local pickers = require('telescope.pickers')
  local finders = require('telescope.finders')
  local actions = require('telescope.actions')
  local action_state = require('telescope.actions.state')
  local conf = require('telescope.config').values

  pickers.new({}, {
    prompt_title = 'ssh host',
    finder = finders.new_table({
      results = merged,
      entry_maker = function(h)
        return {
          value = h.host,
          display = string.format('%-30s  %6.2f', h.host, h.score),
          ordinal = h.host,
        }
      end,
    }),
    sorter = conf.generic_sorter({}),
    attach_mappings = function(bufnr)
      actions.select_default:replace(function()
        actions.close(bufnr)
        local sel = action_state.get_selected_entry()
        if not sel then return end
        local mosh = vim.fn.executable('mosh') == 1 and 'mosh' or 'ssh'
        vim.system({ 'tmux', 'new-window', mosh .. ' ' .. sel.value }):wait()
      end)
      return true
    end,
  }):find()
end

function M.setup()
  vim.keymap.set('n', '<leader>ss', M.pick, { desc = 'ssh host picker' })
end

return M
```

- [ ] **Step 4: PASS**

- [ ] **Step 5: Commit**

```bash
git add lua/remote/hosts.lua tests/remote_hosts_spec.lua
git commit -m "feat(remote): hosts frecency DB + <leader>ss picker"
```

### Task 43: Build `remote/dirs.lua` — cached remote dir picker (TDD)

**Files:**
- Create: `lua/remote/dirs.lua`
- Create: `tests/remote_dirs_spec.lua`

- [ ] **Step 1: Failing test**

```lua
-- tests/remote_dirs_spec.lua
describe('remote.dirs', function()
  local dirs

  before_each(function()
    package.loaded['remote.dirs'] = nil
    dirs = require('remote.dirs')
  end)

  it('_is_stale returns true when cache older than TTL', function()
    local now = 1000000
    local old = now - 8 * 86400 -- 8 days ago, TTL = 7d
    assert.is_true(dirs._is_stale({ fetched_at = old }, now))
    assert.is_false(dirs._is_stale({ fetched_at = now - 86400 }, now))
  end)

  it('_build_find_cmd builds the expected ssh find command', function()
    local cmd = dirs._build_find_cmd('myhost')
    assert.are.same({
      'ssh', 'myhost',
      [[find ~ -type d -maxdepth 6 -not -path '*/.*' -not -path '*/node_modules/*' 2>/dev/null]],
    }, cmd)
  end)
end)
```

- [ ] **Step 2: FAIL**

- [ ] **Step 3: Write `lua/remote/dirs.lua`**

```lua
-- lua/remote/dirs.lua
local M = {}

local TTL = 7 * 86400
local CACHE_DIR = vim.fn.stdpath('data') .. '/happy-nvim/remote-dirs'

function M._cache_path(host)
  return CACHE_DIR .. '/' .. host:gsub('[^%w_-]', '_') .. '.json'
end

function M._is_stale(entry, now)
  return (now - (entry.fetched_at or 0)) > TTL
end

function M._build_find_cmd(host)
  return {
    'ssh', host,
    [[find ~ -type d -maxdepth 6 -not -path '*/.*' -not -path '*/node_modules/*' 2>/dev/null]],
  }
end

function M._read_cache(host)
  local path = M._cache_path(host)
  local f = io.open(path, 'r')
  if not f then return nil end
  local raw = f:read('*a')
  f:close()
  local ok, data = pcall(vim.json.decode, raw)
  if not ok then
    vim.fn.delete(path)
    return nil
  end
  return data
end

function M._write_cache(host, dirs)
  vim.fn.mkdir(CACHE_DIR, 'p')
  local f = io.open(M._cache_path(host), 'w')
  if not f then return end
  f:write(vim.json.encode({ fetched_at = os.time(), dirs = dirs }))
  f:close()
end

function M._fetch_sync(host)
  local res = vim.system(M._build_find_cmd(host), { text = true }):wait()
  if res.code ~= 0 then
    vim.notify('remote dir fetch failed: ' .. (res.stderr or ''), vim.log.levels.WARN)
    return {}
  end
  local dirs_list = {}
  for line in (res.stdout or ''):gmatch('[^\n]+') do
    table.insert(dirs_list, line)
  end
  return dirs_list
end

function M.pick_for_host(host)
  local entry = M._read_cache(host)
  local now = os.time()
  if entry == nil or M._is_stale(entry, now) then
    local fresh = M._fetch_sync(host)
    M._write_cache(host, fresh)
    entry = { fetched_at = now, dirs = fresh }
  end
  local pickers = require('telescope.pickers')
  local finders = require('telescope.finders')
  local actions = require('telescope.actions')
  local action_state = require('telescope.actions.state')
  local conf = require('telescope.config').values

  pickers.new({}, {
    prompt_title = 'remote dirs: ' .. host,
    finder = finders.new_table({ results = entry.dirs }),
    sorter = conf.generic_sorter({}),
    attach_mappings = function(bufnr)
      actions.select_default:replace(function()
        actions.close(bufnr)
        local sel = action_state.get_selected_entry()
        if not sel then return end
        vim.system({ 'tmux', 'send-keys', '-l', 'cd ' .. sel[1] }):wait()
        vim.system({ 'tmux', 'send-keys', 'Enter' }):wait()
      end)
      return true
    end,
  }):find()
end

function M.pick()
  local host = vim.fn.input('Remote host: ')
  if host == '' then return end
  M.pick_for_host(host)
end

function M.refresh(host)
  host = host or vim.fn.input('Refresh dirs for host: ')
  if host == '' then return end
  local fresh = M._fetch_sync(host)
  M._write_cache(host, fresh)
  vim.notify(string.format('cached %d dirs for %s', #fresh, host))
end

function M.setup()
  vim.keymap.set('n', '<leader>sd', M.pick, { desc = 'remote dir picker' })
  vim.keymap.set('n', '<leader>sD', function() M.refresh() end, { desc = 'refresh remote dirs' })
end

return M
```

- [ ] **Step 4: PASS**

- [ ] **Step 5: Commit**

```bash
git add lua/remote/dirs.lua tests/remote_dirs_spec.lua
git commit -m "feat(remote): cached remote dir picker (<leader>sd/sD)"
```

### Task 44: Build `remote/browse.lua` — scp:// + filename find + binary guard

**Files:**
- Create: `lua/remote/browse.lua`
- Create: `tests/remote_browse_spec.lua`

- [ ] **Step 1: Write failing test**

```lua
-- tests/remote_browse_spec.lua
describe('remote.browse', function()
  local browse

  before_each(function()
    package.loaded['remote.browse'] = nil
    browse = require('remote.browse')
  end)

  it('_fast_path_ext returns true for known binary extensions', function()
    assert.is_true(browse._fast_path_ext('foo.png'))
    assert.is_true(browse._fast_path_ext('bar.tar.gz'))
    assert.is_false(browse._fast_path_ext('baz.lua'))
    assert.is_false(browse._fast_path_ext('readme'))
  end)

  it('_build_mime_probe_cmd builds ssh file -b --mime-encoding cmd', function()
    local cmd = browse._build_mime_probe_cmd('myhost', '/etc/passwd')
    assert.are.same({ 'ssh', 'myhost', 'file -b --mime-encoding /etc/passwd' }, cmd)
  end)

  it('_is_binary_mime detects "binary" encoding', function()
    assert.is_true(browse._is_binary_mime('binary\n'))
    assert.is_true(browse._is_binary_mime('binary'))
    assert.is_false(browse._is_binary_mime('utf-8'))
    assert.is_false(browse._is_binary_mime('us-ascii'))
  end)
end)
```

- [ ] **Step 2: FAIL**

- [ ] **Step 3: Write `lua/remote/browse.lua`**

```lua
-- lua/remote/browse.lua
local M = {}

local BINARY_EXTS = {
  png = true, jpg = true, jpeg = true, gif = true, pdf = true,
  zip = true, tar = true, gz = true, xz = true, bz2 = true,
  exe = true, so = true, o = true, a = true, bin = true,
  mp4 = true, mov = true, mp3 = true, flac = true,
  woff = true, woff2 = true, ttf = true, ico = true,
  jar = true, class = true,
}

local MAX_SIZE = 5 * 1024 * 1024

function M._fast_path_ext(path)
  local lower = path:lower()
  -- check last suffix then all compound suffixes
  for ext in lower:gmatch('%.([^.]+)') do
    if BINARY_EXTS[ext] then return true end
  end
  return false
end

function M._build_mime_probe_cmd(host, rpath)
  return { 'ssh', host, 'file -b --mime-encoding ' .. rpath }
end

function M._build_size_probe_cmd(host, rpath)
  return { 'ssh', host, 'stat -c %s ' .. rpath .. ' 2>/dev/null || wc -c < ' .. rpath }
end

function M._is_binary_mime(out)
  return out:gsub('%s+$', '') == 'binary'
end

local function check_remote_binary(host, rpath)
  local mime = vim.system(M._build_mime_probe_cmd(host, rpath), { text = true }):wait()
  if mime.code == 0 and M._is_binary_mime(mime.stdout or '') then
    return true, 'binary'
  end
  local sz = vim.system(M._build_size_probe_cmd(host, rpath), { text = true }):wait()
  if sz.code == 0 then
    local n = tonumber((sz.stdout or ''):gsub('%s+', '')) or 0
    if n > MAX_SIZE then
      return true, string.format('%dMB > 5MB cap', math.floor(n / 1024 / 1024))
    end
  end
  return false
end

function M.open(host, rpath)
  -- Fast-path extension check (advisory, no SSH)
  if M._fast_path_ext(rpath) and not vim.b.happy_force_binary then
    vim.notify(string.format(
      'Binary extension detected for %s. Use :!scp host:path /tmp/ or <leader>sO to force.',
      rpath), vim.log.levels.WARN)
    return
  end
  -- Authoritative probe
  if not vim.b.happy_force_binary then
    local blocked, reason = check_remote_binary(host, rpath)
    if blocked then
      vim.notify(string.format(
        '%s: %s. :!scp host:path /tmp/ manually, or <leader>sO to force.',
        rpath, reason), vim.log.levels.WARN)
      return
    end
  end
  vim.cmd(string.format('edit scp://%s/%s', host, rpath))
end

function M.browse()
  local host = vim.fn.input('Host: ')
  if host == '' then return end
  local path = vim.fn.input('Path: ')
  if path == '' then return end
  vim.cmd(string.format('edit scp://%s/%s/', host, path))
end

function M.find()
  local host = vim.fn.input('Host: ')
  if host == '' then return end
  local path = vim.fn.input('Path: ')
  if path == '' then return end
  local pat = vim.fn.input('Name pattern: ')
  if pat == '' then return end
  local cmd = { 'ssh', host, string.format("find %s -name '%s' 2>/dev/null", path, pat) }
  local res = vim.system(cmd, { text = true }):wait()
  if res.code ~= 0 then
    vim.notify('ssh ' .. host .. ' failed: ' .. (res.stderr or ''), vim.log.levels.ERROR)
    return
  end
  local results = {}
  for line in (res.stdout or ''):gmatch('[^\n]+') do
    table.insert(results, line)
  end
  local pickers = require('telescope.pickers')
  local finders = require('telescope.finders')
  local actions = require('telescope.actions')
  local action_state = require('telescope.actions.state')
  local conf = require('telescope.config').values

  pickers.new({}, {
    prompt_title = string.format('find %s:%s  %s', host, path, pat),
    finder = finders.new_table({ results = results }),
    sorter = conf.generic_sorter({}),
    attach_mappings = function(bufnr)
      actions.select_default:replace(function()
        actions.close(bufnr)
        local sel = action_state.get_selected_entry()
        if not sel then return end
        M.open(host, sel[1])
      end)
      return true
    end,
  }):find()
end

function M.force_binary()
  vim.b.happy_force_binary = 1
  vim.notify('binary guard disabled for this buffer; re-open with :e to retry', vim.log.levels.INFO)
end

function M.setup()
  vim.keymap.set('n', '<leader>sB', M.browse, { desc = 'browse remote path (scp://)' })
  vim.keymap.set('n', '<leader>sf', M.find, { desc = 'find remote files' })
  vim.keymap.set('n', '<leader>sO', M.force_binary, { desc = 'override binary guard' })
end

return M
```

- [ ] **Step 4: PASS**

- [ ] **Step 5: Commit**

```bash
git add lua/remote/browse.lua tests/remote_browse_spec.lua
git commit -m "feat(remote): scp:// browse + find + content-based binary guard (spec §5.4.3)"
```

### Task 45: Build `remote/grep.lua` — niced ssh-grep with full regex (TDD)

**Files:**
- Create: `lua/remote/grep.lua`
- Create: `tests/remote_grep_spec.lua`

- [ ] **Step 1: Write failing test**

```lua
-- tests/remote_grep_spec.lua
describe('remote.grep', function()
  local grep

  before_each(function()
    package.loaded['remote.grep'] = nil
    grep = require('remote.grep')
  end)

  it('_parse_input extracts pattern, path, glob, and flags', function()
    local parsed = grep._parse_input("pattern=foo path=/etc glob=*.conf +timeout=60 +size=50M +hidden")
    assert.are.equal('foo', parsed.pattern)
    assert.are.equal('/etc', parsed.path)
    assert.are.equal('*.conf', parsed.glob)
    assert.are.equal(60, parsed.timeout)
    assert.are.equal('50M', parsed.size)
    assert.is_true(parsed.hidden)
  end)

  it('_parse_input supports +regex=perl / fixed', function()
    local p1 = grep._parse_input('pattern=foo path=/ glob=* +regex=perl')
    assert.are.equal('perl', p1.regex)
    local p2 = grep._parse_input('pattern=foo path=/ glob=* +regex=fixed')
    assert.are.equal('fixed', p2.regex)
  end)

  it('_build_cmd uses grep -EIlH by default', function()
    local cmd = grep._build_cmd('myhost', {
      pattern = 'foo', path = '/etc', glob = '*.conf',
      timeout = 30, size = '10M',
    })
    local joined = table.concat(cmd, ' ')
    assert.is_true(joined:find('grep %-EIlH') ~= nil)
    assert.is_true(joined:find("nice %-n19") ~= nil)
    assert.is_true(joined:find("ionice %-c3") ~= nil)
    assert.is_true(joined:find("timeout 30") ~= nil)
    assert.is_true(joined:find('%-size %-10M') ~= nil)
  end)

  it('_build_cmd switches to -PIlH for +regex=perl', function()
    local cmd = grep._build_cmd('myhost', {
      pattern = 'foo', path = '/', glob = '*',
      timeout = 30, size = '10M', regex = 'perl',
    })
    assert.is_true(table.concat(cmd, ' '):find('grep %-PIlH') ~= nil)
  end)

  it('_build_cmd drops hidden/node_modules/venv filters with +all', function()
    local cmd = grep._build_cmd('myhost', {
      pattern = 'foo', path = '/', glob = '*',
      timeout = 30, size = '10M', all = true,
    })
    local joined = table.concat(cmd, ' ')
    assert.is_false(joined:find('node_modules') ~= nil)
    assert.is_false(joined:find('venv') ~= nil)
  end)
end)
```

- [ ] **Step 2: FAIL**

- [ ] **Step 3: Write `lua/remote/grep.lua`**

```lua
-- lua/remote/grep.lua
local M = {}

function M._parse_input(line)
  local out = { timeout = 30, size = '10M', hidden = false, all = false, regex = 'ext', nocase = false }
  for tok in line:gmatch('%S+') do
    local k, v = tok:match('^([^=+][^=]*)=(.+)$')
    if k and v then
      if k == 'pattern' then out.pattern = v
      elseif k == 'path' then out.path = v
      elseif k == 'glob' then out.glob = v
      end
    else
      local fk, fv = tok:match('^%+([^=]+)=(.+)$')
      if fk and fv then
        if fk == 'timeout' then out.timeout = tonumber(fv) or 30
        elseif fk == 'size' then out.size = fv
        elseif fk == 'regex' then out.regex = fv
        end
      else
        local flag = tok:match('^%+(.+)$')
        if flag == 'hidden' then out.hidden = true
        elseif flag == 'all' then out.all = true; out.hidden = true
        elseif flag == 'nocase' then out.nocase = true
        end
      end
    end
  end
  return out
end

function M._build_cmd(host, opts)
  local grep_flag = 'E'
  if opts.regex == 'perl' then grep_flag = 'P'
  elseif opts.regex == 'fixed' then grep_flag = 'F'
  end
  local case = opts.nocase and 'i' or ''
  local filters = {}
  if not opts.hidden then table.insert(filters, "-not -path '*/.*'") end
  if not opts.all then
    table.insert(filters, "-not -path '*/node_modules/*'")
    table.insert(filters, "-not -path '*/venv/*'")
  end
  local size_part = ''
  if opts.size ~= '0' then size_part = '-size -' .. opts.size end

  local remote = string.format(
    "nice -n19 ionice -c3 timeout %d find %s -type f %s %s -name '%s' -exec grep -%s%sIlH '%s' {} + 2>/dev/null",
    opts.timeout, opts.path, size_part, table.concat(filters, ' '),
    opts.glob, grep_flag, case, opts.pattern
  )
  return { 'ssh', host, remote }
end

function M.prompt()
  local host = vim.fn.input('Host: ')
  if host == '' then return end
  local line = vim.fn.input('grep [pattern=X path=Y glob=Z +timeout=N +size=NM +regex=ext|perl|fixed +hidden +all +nocase]: ')
  if line == '' then return end
  local opts = M._parse_input(line)
  if not opts.pattern or not opts.path or not opts.glob then
    vim.notify('pattern, path, glob are required', vim.log.levels.ERROR)
    return
  end
  local cmd = M._build_cmd(host, opts)
  local res = vim.system(cmd, { text = true }):wait()
  if res.code == 124 then
    vim.notify('grep timed out. Narrow path/glob or pass +timeout=60', vim.log.levels.WARN)
    return
  end
  local results = {}
  for line_out in (res.stdout or ''):gmatch('[^\n]+') do
    table.insert(results, line_out)
  end
  if #results == 0 then
    vim.notify('no matches', vim.log.levels.INFO)
    return
  end
  local pickers = require('telescope.pickers')
  local finders = require('telescope.finders')
  local actions = require('telescope.actions')
  local action_state = require('telescope.actions.state')
  local conf = require('telescope.config').values

  pickers.new({}, {
    prompt_title = string.format('%s:%s  %s', host, opts.path, opts.pattern),
    finder = finders.new_table({ results = results }),
    sorter = conf.generic_sorter({}),
    attach_mappings = function(bufnr)
      actions.select_default:replace(function()
        actions.close(bufnr)
        local sel = action_state.get_selected_entry()
        if not sel then return end
        require('remote.browse').open(host, sel[1])
      end)
      return true
    end,
  }):find()
end

function M.setup()
  vim.keymap.set('n', '<leader>sg', M.prompt, { desc = 'remote grep' })
end

return M
```

- [ ] **Step 4: PASS**

- [ ] **Step 5: Commit**

```bash
git add lua/remote/grep.lua tests/remote_grep_spec.lua
git commit -m "feat(remote): niced ssh-grep w/ ERE default + perl/fixed/nocase flags (spec §5.4.4)"
```

### Task 46: Wire `remote/init.lua`

**Files:**
- Create: `lua/remote/init.lua`
- Modify: `init.lua`

- [ ] **Step 1: Write**

```lua
-- lua/remote/init.lua
local M = {}

function M.setup()
  require('remote.hosts').setup()
  require('remote.dirs').setup()
  require('remote.browse').setup()
  require('remote.grep').setup()
end

return M
```

- [ ] **Step 2: Add to `User LazyDone` in `init.lua`**

```lua
local ok_r, remote = pcall(require, 'remote')
if ok_r then remote.setup() end
```

- [ ] **Step 3: Commit**

```bash
git add lua/remote/init.lua init.lua
git commit -m "feat(remote): wire remote module from init.lua"
```

### Task 47: Add `:HappyHostsPrune` user command

**Files:**
- Modify: `lua/remote/hosts.lua`

- [ ] **Step 1: Add to `hosts.lua`**

Inside `M.setup()`:

```lua
vim.api.nvim_create_user_command('HappyHostsPrune', function()
  local db = M._read_db()
  local pruned = 0
  for host, _ in pairs(db) do
    local res = vim.system({ 'getent', 'hosts', host }, { text = true }):wait()
    if res.code ~= 0 then
      db[host] = nil
      pruned = pruned + 1
    end
  end
  vim.fn.mkdir(vim.fn.stdpath('data') .. '/happy-nvim', 'p')
  local f = io.open(DB_PATH, 'w')
  if f then
    f:write(vim.json.encode(db))
    f:close()
  end
  vim.notify(string.format('pruned %d unresolvable hosts', pruned))
end, {})
```

- [ ] **Step 2: Commit**

```bash
git add lua/remote/hosts.lua
git commit -m "feat(remote): add :HappyHostsPrune command"
```

### Task 48: End-of-Phase-7 smoke

- [ ] Run all plenary tests: `nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedDirectory tests/ {minimal_init='tests/minimal_init.lua'}" -c 'qa!'`
- [ ] Expected: all tests pass.
- [ ] Manual: set up ssh-z in a shell, run `ssh` to a real host, check `~/.local/share/happy-nvim/hosts.json`.

---

## Phase 8 — Health, CI polish, README, migration (Tasks 49–52)

### Task 49: Fill out `:checkhealth happy-nvim` probes

**Files:**
- Modify: `lua/happy/health.lua`

- [ ] **Step 1: Replace placeholder with real probes**

```lua
-- lua/happy/health.lua
local M = {}

local function exec(cmd)
  local res = vim.system(cmd, { text = true }):wait()
  return res.code == 0, res.stdout or '', res.stderr or ''
end

function M.check()
  local h = vim.health
  h.start('happy-nvim: core')
  if vim.fn.has('nvim-0.10') == 1 then
    h.ok('Neovim >= 0.10')
  else
    h.error('Neovim >= 0.10 required')
  end

  h.start('happy-nvim: local CLIs')
  for _, cli in ipairs({ 'rg', 'fd', 'stylua', 'selene', 'git' }) do
    if vim.fn.executable(cli) == 1 then
      h.ok(cli .. ' found')
    else
      h.warn(cli .. ' not found (install for full feature set)')
    end
  end

  h.start('happy-nvim: tmux')
  if vim.env.TMUX == nil or vim.env.TMUX == '' then
    h.info('not running inside tmux — tmux/Claude features disabled')
  else
    local ok, ver = exec({ 'tmux', '-V' })
    if ok then
      h.ok('tmux: ' .. ver:gsub('%s+$', ''))
    end
    local _, passthrough = exec({ 'tmux', 'show-option', '-v', '-g', 'allow-passthrough' })
    if passthrough:match('on') then
      h.ok('tmux allow-passthrough=on (OSC 52 host clipboard will work)')
    else
      h.warn('tmux allow-passthrough off — host clipboard via OSC 52 may be stripped. Set: tmux set -g allow-passthrough on')
    end
    local _, setclip = exec({ 'tmux', 'show-option', '-v', '-g', 'set-clipboard' })
    if setclip:match('on') or setclip:match('external') then
      h.ok('tmux set-clipboard on/external')
    else
      h.warn('tmux set-clipboard should be `on` or `external`')
    end
  end

  h.start('happy-nvim: mosh')
  if vim.env.MOSH_CONNECTION ~= nil then
    local ok, ver = exec({ 'mosh', '--version' })
    if ok then
      local major, minor = ver:match('mosh (%d+)%.(%d+)')
      if major and minor and (tonumber(major) > 1 or (tonumber(major) == 1 and tonumber(minor) >= 4)) then
        h.ok('mosh ' .. major .. '.' .. minor .. ' (>= 1.4 required for OSC 52 passthrough)')
      else
        h.warn('mosh < 1.4 — OSC 52 will be stripped, host clipboard unavailable')
      end
    end
  else
    h.info('not a mosh session')
  end

  h.start('happy-nvim: ssh')
  if vim.env.SSH_AUTH_SOCK ~= nil and vim.env.SSH_AUTH_SOCK ~= '' then
    h.ok('ssh-agent socket present')
  else
    h.warn('SSH_AUTH_SOCK not set — remote ops will fail on password-only hosts')
  end

  h.start('happy-nvim: XDG dirs')
  local state = vim.fn.stdpath('state')
  if vim.fn.isdirectory(state) == 1 then
    h.ok('state dir: ' .. state)
  else
    h.warn('state dir missing: ' .. state)
  end
end

return M
```

- [ ] **Step 2: Commit**

```bash
git add lua/happy/health.lua
git commit -m "feat(health): tmux/mosh/ssh/CLI probes for :checkhealth happy-nvim"
```

### Task 50: Expand CI — add checkhealth job

**Files:**
- Modify: `.github/workflows/ci.yml`

- [ ] **Step 1: Add new job**

Append under existing jobs:

```yaml
  health:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: rhysd/action-setup-vim@v1
        with:
          neovim: true
          version: stable
      - name: Install minimal deps
        run: |
          sudo apt-get update
          sudo apt-get install -y ripgrep fd-find tmux mosh
          # symlink fdfind → fd (Debian quirk)
          mkdir -p $HOME/.local/bin && ln -sf $(which fdfind) $HOME/.local/bin/fd
          echo "$HOME/.local/bin" >> $GITHUB_PATH
      - name: Install stylua + selene
        uses: cargo-bins/cargo-binstall@main
      - run: cargo binstall -y stylua selene
      - name: Run :checkhealth happy-nvim in tmux
        run: |
          mkdir -p $HOME/.config/nvim
          cp -r . $HOME/.config/nvim/
          tmux new-session -d -s ci 'nvim --headless -c "checkhealth happy-nvim" -c "qa!" 2>&1 | tee /tmp/health.log; sleep 1'
          sleep 3
          cat /tmp/health.log
          ! grep -i 'ERROR:' /tmp/health.log
```

- [ ] **Step 2: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: add :checkhealth happy-nvim job"
```

### Task 51: Migration from MyHappyPlace + manual smoke script

**Files:**
- Create: `scripts/smoke.sh`
- Create: `scripts/migrate.sh`

- [ ] **Step 1: Write `scripts/smoke.sh`**

```bash
#!/usr/bin/env bash
# scripts/smoke.sh — run before tagging a release.
set -euo pipefail

echo "1. stylua check"
stylua --check .

echo "2. selene check"
selene .

echo "3. plenary tests"
nvim --headless -u tests/minimal_init.lua \
  -c "PlenaryBustedDirectory tests/ {minimal_init='tests/minimal_init.lua'}" \
  -c 'qa!' 2>&1 | tee /tmp/happy-smoke-plenary.log
grep -q 'Failed: 0' /tmp/happy-smoke-plenary.log
grep -q 'Errors: 0' /tmp/happy-smoke-plenary.log

echo "4. headless startup"
TMPHOME=$(mktemp -d)
mkdir -p "$TMPHOME/.config"
ln -sfn "$PWD" "$TMPHOME/.config/nvim"
HOME="$TMPHOME" nvim --headless -c 'Lazy sync' -c 'qa!' 2>&1 | tee /tmp/happy-smoke-startup.log
! grep -Ei 'Error|E[0-9]+:' /tmp/happy-smoke-startup.log

echo "5. checkhealth"
HOME="$TMPHOME" nvim --headless -c 'checkhealth happy-nvim' -c 'qa!' 2>&1 | tee /tmp/happy-smoke-health.log
! grep -i 'ERROR:' /tmp/happy-smoke-health.log

echo "6. Lazy profile under 200ms"
HOME="$TMPHOME" nvim --headless --startuptime /tmp/happy-smoke-startup.time -c 'qa!'
tail -1 /tmp/happy-smoke-startup.time
# extract last number — startup time in ms — check < 200
last=$(tail -1 /tmp/happy-smoke-startup.time | awk '{print $1}')
awk -v t="$last" 'BEGIN { exit (t < 200) ? 0 : 1 }'

rm -rf "$TMPHOME"
echo "ALL OK"
```

- [ ] **Step 2: Write `scripts/migrate.sh`**

```bash
#!/usr/bin/env bash
# scripts/migrate.sh — install happy-nvim over existing nvim config safely.
set -euo pipefail

CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/nvim"
BACKUP="${CONFIG}.myhappyplace.bak.$(date +%s)"

if [[ -e "$CONFIG" ]]; then
  echo "Backing up existing config to $BACKUP"
  mv "$CONFIG" "$BACKUP"
fi

echo "Cloning happy-nvim into $CONFIG"
git clone https://github.com/raulfrk/happy-nvim "$CONFIG"

echo "Done. Launch nvim — Lazy will sync plugins on first start."
echo "Your old config is preserved at $BACKUP (safe to delete after verifying)."
```

- [ ] **Step 3: chmod + commit**

```bash
chmod +x scripts/smoke.sh scripts/migrate.sh
git add scripts/smoke.sh scripts/migrate.sh
git commit -m "feat(scripts): smoke.sh release gate + migrate.sh installer"
```

### Task 52: Write full README + acceptance matrix

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Replace stub README with full content**

```markdown
# happy-nvim

A Neovim config focused on **macro fluency** — built to nudge a non-power-user
toward native nvim motions, text objects, macros, and registers.

Successor to [MyHappyPlace](https://github.com/raulfrk/MyHappyPlace).

## Install

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/raulfrk/happy-nvim/main/scripts/migrate.sh)
```

This backs up your current `~/.config/nvim` as
`~/.config/nvim.myhappyplace.bak.<timestamp>` and clones happy-nvim in its
place. Launch `nvim` once — Lazy auto-syncs plugins on first start.

## What you get

- **Daily editor.** Tokyonight theme, telescope, treesitter, LSP for
  Python/Go/Lua/Bash/YAML/Markdown/C++, blink.cmp completion, conform
  format-on-save, gitsigns, harpoon.
- **Macro-nudge layer (5 surfaces).**
  1. Ambient: precognition.nvim overlays motion targets; noice.nvim inline
     LSP signatures + cmdline popup.
  2. which-key popup after `<leader>`, operator keys, visual mode.
  3. Tip-of-the-day on the alpha dashboard.
  4. `<leader>?` — searchable cheatsheet of 30+ curated motions/macros.
  5. hardtime.nvim hints against `hjkl` / arrow spam.
- **Tmux + Claude Code integration.** `<leader>cc/cf/cs/ce` to open/attach
  a Claude pane and send file refs, selections with location context, or
  diagnostics.
- **OSC 52 dual-clipboard.** Yanks populate both the VM clipboard (via
  `unnamedplus`) and the host terminal clipboard (via OSC 52).
- **Remote ops, zero remote install.** Host frecency picker, cached remote
  dir zoxide, scp:// browse with content-based binary guard, niced ssh-grep
  with full regex flags.

## Keymap reference

### Namespaces

| Prefix | Domain |
|---|---|
| `<leader>f` | files / find (telescope) |
| `<leader>g` | git |
| `<leader>l` | LSP |
| `<leader>d` | diagnostics |
| `<leader>h` | harpoon |
| `<leader>s` | ssh / remote |
| `<leader>c` | Claude (tmux) |
| `<leader>t` | tmux popups |
| `<leader>?` | cheatsheet / coach |

### Most-used

| Keys | Action |
|---|---|
| `<leader>ff` | Find files |
| `<leader>fg` | Find git-tracked files |
| `<leader>fw` | Live grep |
| `<leader>cc` | Open/attach Claude pane |
| `<leader>cs` (v) | Send selection to Claude with file:line ref |
| `<leader>ss` | SSH host picker |
| `<leader>sd` | Remote dir picker (zoxide-style) |
| `<leader>sg` | Remote content grep |
| `<leader>?` | Cheatsheet |
| `<leader>??` | Next tip |
| `<leader>?p` | Toggle precognition overlay |

Full list: run `:WhichKey`.

## Prereqs for full feature set

- **tmux 3.3+** with:
  ```tmux
  set -g allow-passthrough on
  set -g set-clipboard on
  ```
- **mosh 1.4+** if using mosh (earlier strips OSC 52).
- **Terminal emulator** supporting OSC 52: kitty, iTerm2, wezterm,
  alacritty, ghostty.
- **ssh-agent** or key-based auth (remote ops do not spawn password prompts).

Run `:checkhealth happy-nvim` to verify your stack.

### Optional zsh integration

To populate the SSH host frecency DB from all terminal-direct connects
(not just `<leader>ss`), source the provided zsh wrapper:

```bash
# In ~/.zshrc:
source ~/path/to/happy-nvim/scripts/ssh-z.zsh
```

## Acceptance matrix (run after major changes)

- [ ] Yank in nvim → paste works on host clipboard
- [ ] Yank in nvim → paste works on VM clipboard
- [ ] `<leader>cc` opens Claude pane
- [ ] `<leader>cs` sends visual selection with @file:lines ref
- [ ] `<leader>cf` sends @file ref
- [ ] `<leader>ce` sends file + diagnostics
- [ ] `<leader>ss` picker shows ranked hosts
- [ ] `<leader>sd` picker cd's remote shell to chosen dir
- [ ] `<leader>sg` with sample pattern returns results < 5s
- [ ] Binary file via scp:// refused with helpful message
- [ ] `<leader>sO` overrides binary guard
- [ ] Theme loads without flash
- [ ] `:checkhealth happy-nvim` clean on fresh VM + fresh mosh session
- [ ] `scripts/smoke.sh` passes
- [ ] Startup under 200 ms (`:Lazy profile`)

## Tip: add your own tips

Edit `lua/coach/tips.lua` and add entries:

```lua
{ keys = 'gUw', desc = 'uppercase word', category = 'motions' },
```

Restart nvim — the new tip joins the rotation.

## Credits

Forked once from [kickstart.nvim](https://github.com/nvim-lua/kickstart.nvim)
then modularized. Ideas and code comments preserved where they survive in
recognizable form.

## License

MIT — see `LICENSE`.
```

- [ ] **Step 2: Run the smoke script**

```bash
scripts/smoke.sh
```

Expected: `ALL OK`.

- [ ] **Step 3: Run the acceptance matrix manually on a real mosh+tmux session**

Tick each checkbox. Fix any failures inline with new tasks appended to this plan.

- [ ] **Step 4: Tag v1.0.0 + commit**

```bash
git add README.md
git commit -m "docs: full README with keymaps, prereqs, acceptance matrix"
git tag -a v1.0.0 -m "happy-nvim v1.0.0"
```

---

## Self-review checklist (applied by plan author)

Run these after writing, before handing to engineer:

1. **Spec coverage** — Every §1..§10 section of the spec maps to tasks:
   - §2 scope → phases 1-7
   - §3 architecture → Task 11 (init wiring)
   - §4 plugin catalog → Tasks 12-26, 27-29, 35
   - §5.1 coach → Tasks 30-31
   - §5.1.5 ambient → Tasks 28, 14
   - §5.2 clipboard → Tasks 33-34
   - §5.3 tmux → Tasks 35-40
   - §5.4 remote → Tasks 41-48
   - §6 bug fixes → integrated (BUG-1 Task 24, BUG-2 Tasks 7/15/22, BUG-3 Tasks 6/8/12, BUG-4 Task 10)
   - §7 errors → tested in specs + `:checkhealth` Task 49
   - §8 testing → Tasks 3-4, 26, 32, 48, 50-52
   - §9 migration → Task 51
2. **Placeholder scan** — no TBD/TODO/fill-in. Verified.
3. **Type consistency** — `send.send_to_claude(payload)` used by claude.lua (Task 37) matches definition in send.lua (Task 36). `M._fast_path_ext` signature matches in test + impl.
4. **Key conflicts** — `<C-h>` claimed by tmux-nav (Task 35) and harpoon (Task 19). Resolved in Task 35 by moving harpoon to `<leader>h1..h4`.

---

## Execution notes

- Phase boundaries are safe checkpoints. Stop between phases if you want to
  dogfood before proceeding.
- Each task ends with a commit; the engineer can cherry-pick or revert at
  task granularity.
- Tests (plenary specs) cover pure-Lua logic. Plugin-wiring correctness is
  verified via headless `Lazy sync` and `:checkhealth happy-nvim`.
- Total tasks: 52. Estimated wall time: 6–10 hours of focused work.
