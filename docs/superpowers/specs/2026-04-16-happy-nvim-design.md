# happy-nvim — Design Spec

**Status:** Approved (2026-04-16)
**Author:** raulfrk
**Successor to:** [MyHappyPlace](https://github.com/raulfrk/MyHappyPlace)

## 1. Purpose

Replace the author's existing `MyHappyPlace` Neovim configuration with a cleaner,
modular setup that:

1. Fixes the four known bug classes in `MyHappyPlace` (format-on-save double-fire,
   keymap conflicts, theme/visual jank, plugin load errors from phantom plugins).
2. Nudges the author — a self-described non-power-user — toward fluent use of
   Neovim macros, text objects, and motions, through passive hints rather than
   intrusive tutoring.
3. Adds tmux + Claude Code integration so selections, file references, and
   LSP diagnostics can be sent to a designated Claude pane from inside nvim.
4. Solves dual-clipboard copy in the `host → mosh → VM → tmux → nvim` stack,
   so `y` lands on both the VM and host clipboards.
5. Provides a thin remote-ops layer: SSH host frecency picker, zoxide-like
   remote directory jumping, and remote file browse / content grep — all
   without installing anything on the remote host, and without bulk-copying
   files locally.

## 2. Scope

### In scope (v1)

- Fresh repository at `github.com/raulfrk/happy-nvim`, MIT-licensed.
- Forked from `kickstart.nvim`, then modularized into per-concern files.
- Language support: Python, Go, Lua, Bash, YAML, Markdown, C++.
- Theme: `tokyonight` (storm variant).
- Macro-nudge layer combining `which-key`, startup tip-of-day,
  `hardtime.nvim`, and an on-demand curated cheatsheet.
- Tmux module: `vim-tmux-navigator`, popup launchers, and Claude Code
  integration commands.
- Clipboard module: OSC 52 hook on `TextYankPost`.
- Remote-ops module: SSH host frecency, remote dir picker, remote filename
  find, remote content grep, scp:// browse/edit.

### Out of scope (v1)

- File-tree plugins (`nvim-tree`, `neo-tree`, `oil.nvim`) — use netrw +
  telescope.
- Auto-pairs, auto-tag, indent-blankline — add only if missed.
- Distant.nvim or any remote-editing daemon — violates no-install constraint.
- rsync-based remote caches — rejected to avoid bulk file copy.
- Full CI matrix for multiple nvim versions — stable + nightly only.
- Gamified stats/keystroke tracking — out of "passive nudge" scope.

## 3. Architecture

### 3.1 Repository layout

```
happy-nvim/
├── init.lua                 # bootstraps lazy.nvim, requires config.*
├── lua/
│   ├── config/
│   │   ├── options.lua      # vim.opt.*
│   │   ├── keymaps.lua      # core keymaps only (non-namespaced)
│   │   ├── autocmds.lua     # yank-highlight, OSC52 hook, FocusGained checktime
│   │   ├── colors.lua       # highlight-group overrides
│   │   └── lazy.lua         # plugin manager bootstrap + spec loader
│   ├── plugins/             # one file per plugin or tight group
│   │   ├── colorscheme.lua
│   │   ├── treesitter.lua
│   │   ├── lsp.lua
│   │   ├── completion.lua
│   │   ├── telescope.lua
│   │   ├── harpoon.lua
│   │   ├── undotree.lua
│   │   ├── fugitive.lua
│   │   ├── gitsigns.lua
│   │   ├── whichkey.lua
│   │   ├── hardtime.lua
│   │   ├── alpha.lua
│   │   ├── lualine.lua
│   │   └── tmux-nav.lua
│   ├── coach/               # macro-nudge content layer
│   │   ├── init.lua
│   │   └── tips.lua
│   ├── tmux/                # tmux popups + Claude integration
│   │   ├── init.lua
│   │   ├── popup.lua
│   │   ├── send.lua
│   │   └── claude.lua
│   ├── remote/              # SSH host frecency + remote ops
│   │   ├── init.lua
│   │   ├── hosts.lua
│   │   ├── dirs.lua
│   │   ├── browse.lua
│   │   └── grep.lua
│   ├── clipboard/           # OSC 52 hook
│   │   └── init.lua
│   └── happy/
│       └── health.lua       # :checkhealth implementation
├── scripts/
│   ├── smoke.sh             # manual integration checks
│   └── ssh-z.zsh            # optional passive host logger
├── lazy-lock.json
├── stylua.toml
├── selene.toml
├── .neoconf.json
├── .github/workflows/ci.yml
└── README.md
```

### 3.2 Foundation: kickstart.nvim fork, diverged

The repo is seeded **once** from `nvim-lua/kickstart.nvim` (a single well-
commented teaching config, ~600 lines in one file). The commented single
file is split into the module layout in §3.1 as the first commit(s).
After that, the fork diverges freely — kickstart is not tracked as an
upstream to merge from. Attribution and the original kickstart comments
are preserved where the code survives in recognizable form.

Why this starting point rather than pure-raw or LazyVim:

- Pure-raw recreates the bug class that broke MyHappyPlace (keymap drift,
  phantom-plugin keymaps, hand-wired format-on-save).
- LazyVim hides the wiring the author needs to see to learn nvim.
- kickstart gives a vetted baseline, and reading its comments during the
  split-up is itself power-user training.

### 3.3 Principles

1. **One concern per file.** No plugin file exceeds ~80 lines; split if it does.
2. **Plugins own their keymaps.** Keymaps live next to the plugin that uses them,
   registered through `which-key.add` so collisions surface at startup.
3. **Modules are not plugins.** `coach/`, `tmux/`, `remote/`, `clipboard/` are
   pure Lua modules required from `init.lua` after lazy setup. No lazy spec.
4. **No hidden globals.** Module state (caches, configuration) lives in the
   module's returned table, never on `vim.g`.
5. **Fail-safe loads.** Every module `require` in `init.lua` is wrapped in
   `pcall`. A broken module never prevents nvim from starting.

## 4. Plugin catalog

All loaded via `lazy.nvim` with `defaults = { lazy = true }`. Version pins
chosen to balance stability with currency.

### Core editing / UI

| Plugin | Purpose | Pin |
|---|---|---|
| `folke/lazy.nvim` | Plugin manager | `stable` branch |
| `folke/tokyonight.nvim` | Theme (storm) | `*` |
| `nvim-lualine/lualine.nvim` | Statusline | `*` |
| `nvim-tree/nvim-web-devicons` | Icons | `*` |
| `goolord/alpha-nvim` | Dashboard w/ tip-of-day | `*` |
| `folke/which-key.nvim` | Leader-hold popup | `v3.x` |
| `rcarriga/nvim-notify` | Notification backend | `*` |

### Navigation / files

| Plugin | Purpose | Pin |
|---|---|---|
| `nvim-telescope/telescope.nvim` | Fuzzy finder | `0.1.x` |
| `nvim-telescope/telescope-fzf-native.nvim` | Native fzf sorter (build=make) | `*` |
| `ThePrimeagen/harpoon` | Quick file pins | `harpoon2` |
| `mbbill/undotree` | Undo history | `*` |
| `christoomey/vim-tmux-navigator` | Seamless nvim↔tmux pane nav | `*` |

### LSP / completion / treesitter / formatting

| Plugin | Purpose | Pin |
|---|---|---|
| `neovim/nvim-lspconfig` | LSP configs | `*` |
| `williamboman/mason.nvim` | Tool installer | `v1.x` |
| `williamboman/mason-lspconfig.nvim` | Bridge | `v1.x` |
| `WhoIsSethDaniel/mason-tool-installer.nvim` | Auto-install formatters/linters | `*` |
| `saghen/blink.cmp` | Completion | `v0.7.x` |
| `L3MON4D3/LuaSnip` | Snippets | `v2.x` |
| `nvim-treesitter/nvim-treesitter` | Syntax + textobjects | `master` |
| `nvim-treesitter/nvim-treesitter-textobjects` | `af`/`if`/`ac`/`ic` text objects (macro training wheels) | `master` |
| `stevearc/conform.nvim` | Formatter runner (single owner for format-on-save) | `*` |
| `mfussenegger/nvim-lint` | Linter runner | `*` |

### Git

| Plugin | Purpose | Pin |
|---|---|---|
| `tpope/vim-fugitive` | `:Git` commands | `*` |
| `lewis6991/gitsigns.nvim` | Inline hunks + blame | `*` |

### Macro-nudge

| Plugin | Purpose | Pin |
|---|---|---|
| `m4xshen/hardtime.nvim` | Blocks repeated `hjkl` / arrows | `*` |
| `tpope/vim-surround` | `cs"'`, `ds(` | `*` |
| `tpope/vim-repeat` | Makes `.` work w/ plugin actions | `*` |

### Deliberate exclusions

- **`lsp-zero.nvim`** — cause of the format-on-save double-fire in `MyHappyPlace`.
  `lspconfig` + `mason-lspconfig` directly is cleaner.
- **`nvim-cmp`** — replaced by `blink.cmp` (kickstart's 2026 default).
- **`null-ls` / `none-ls`** — replaced by `conform.nvim` + `nvim-lint`.
- **File-tree plugins** — netrw + telescope cover the use case.

**Total external plugins: 22.**

## 5. Modules (author-owned Lua)

### 5.1 `coach/` — macro-nudge layer

**`coach/tips.lua`** — a single Lua table, ordered by whenever the author
learned or rediscovered a motion. Each entry:

```lua
{ keys = 'ci"', desc = 'change inside quotes', category = 'text-objects' }
```

Categories: `text-objects`, `macros`, `marks`, `registers`, `motions`,
`lsp`, `window`, `search`.

**`coach/init.lua`** exposes:

- `random_tip()` — returns one random tip (used by alpha dashboard at startup).
- `next_tip()` — advances without restart; bound to `<leader>??`.
- `open_cheatsheet()` — telescope picker over the table, searchable by keys,
  desc, or category; preview pane shows a usage example; bound to `<leader>?`.

**Why telescope:** it's already a dependency, already has fuzzy matching and a
preview pane. No new plugin.

### 5.2 `clipboard/` — OSC 52 hook

Flow on `TextYankPost`:

1. Guard: `vim.env.SSH_TTY or vim.env.TMUX`. If neither, return (no remote, no
   need to emit OSC 52).
2. Operator check: only `y` (not `d`, not `c`). Deletes and changes should not
   populate the host clipboard.
3. Build content from `vim.v.event.regcontents`.
4. Size cap at 74 KB base64 (some terminals reject larger). On overflow: skip
   OSC 52, log a warning, preserve normal yank behavior.
5. Base64-encode and emit `\033]52;c;<b64>\007` to stdout.
6. Leave `vim.opt.clipboard = 'unnamedplus'` untouched — VM clipboard
   (xclip / wl-copy) continues to work via the default provider.

Both clipboards populated, one keystroke.

**Portability.** On a bare terminal (no tmux, no SSH), the `TextYankPost`
guard short-circuits. `unnamedplus` remains the only clipboard path, which
is correct for local editing. The module is safe to ship as-is everywhere.

### 5.3 `tmux/` — popups + Claude integration

Module returns early if `$TMUX` is unset. No keymaps bound outside tmux.

**`tmux/popup.lua`** — wrappers around `tmux display-popup -E`:

- `<leader>tg` — lazygit
- `<leader>tt` — scratch shell (cwd = git root)
- `<leader>tb` — btop
- `<leader>th` — telescope picker over saved popup commands

**`tmux/send.lua`** — `send-keys` helpers and pane discovery via tmux
user-options (`@claude_pane_id` etc.).

**`tmux/claude.lua`** — Claude Code integration.

Pane discovery is **window-scoped**, not session-scoped:

```
<leader>cc:
  if tmux show-option -w -v @claude_pane_id returns a live pane id:
    tmux select-pane -t <id>
  else:
    tmux split-window -h -c <buf_cwd> 'claude'
    capture new pane id
    tmux set-option -w @claude_pane_id <new_id>
```

Send commands:

| Keymap | Payload |
|---|---|
| `<leader>cc` | (no payload — opens/attaches the pane) |
| `<leader>cs` (visual) | `@<rel_path>:<s>-<e>` + fenced selection |
| `<leader>cf` | `@<rel_path>` |
| `<leader>ce` | `@<rel_path>` + bulleted LSP diagnostics for the buffer |

Relative path is computed against the Claude pane's `#{pane_current_path}`.

Payload guards:

- Contains triple-backticks → switch fence to `~~~`.
- Selection > 10 KB → confirm prompt before sending.
- Every send ends with a literal `Enter` key.

### 5.4 `remote/` — SSH host frecency + remote ops

Pure SSH shell-out. No daemon on the remote. No bulk file copy.

#### 5.4.1 `remote/hosts.lua` — host frecency

Storage: `~/.local/share/happy-nvim/hosts.json`, schema
`{ host: { visits: int, last_used: unix_ts } }`. Score formula:
`visits × exp(-days_since_last / 14)`.

Populated by the **`ssh-z` zsh helper** (shipped in `scripts/ssh-z.zsh`, user
symlinks into their shell init). The helper wraps `ssh` and `mosh`, logs each
invocation to the JSON DB, then execs the real binary. Catches all connects
including terminal-direct ones.

`<leader>ss` opens a telescope picker over
`(frecency DB ∪ ~/.ssh/config Hosts)`, ranks by score. Selection spawns a new
tmux window running `mosh <host>` (falls back to `ssh <host>` if `mosh` is
missing locally).

`:HappyHostsPrune` removes entries that have failed to resolve N times in a row.

#### 5.4.2 `remote/dirs.lua` — remote zoxide

Per-host cached directory list at
`~/.local/share/happy-nvim/remote-dirs/<host>.json`, with TTL 7 days.

On first use (or cache expiry), runs:

```
ssh <host> 'find ~ -type d -maxdepth 6 \
    -not -path "*/.*" -not -path "*/node_modules/*" 2>/dev/null'
```

Per-(host, path) visit counter alongside the dir list, same frecency formula
as hosts.

`<leader>sd` — telescope picker over cached dirs for the current host.
On pick, `tmux send-keys -t <active> "cd <path>" Enter` in the remote shell
pane (or spawns one if `<leader>ss` has not been used).

`<leader>sD` — force-refresh the cached dir list for a chosen host.

#### 5.4.3 `remote/browse.lua` — remote file browse

Thin layer over netrw's built-in `scp://`:

- `<leader>sB` — prompts `host` + `path`, opens `scp://<host>//<path>/`.
- `<leader>sf` — prompts `host` + `path` + `name-pattern`, runs
  `ssh <host> 'find <path> -name "<pattern>"'`, displays in telescope;
  Enter opens the selected path via scp://.
- **Binary guard.** On opening a scp:// buffer, inspect extension and size.
  Extensions in
  `{png, jpg, gif, pdf, zip, tar, gz, xz, exe, so, o, a, bin, mp4, mov}` or
  size > 5 MB triggers refusal with a hint: use `:!scp` manually, or press
  `<leader>sO` to force open (sets a per-buffer override flag).

#### 5.4.4 `remote/grep.lua` — remote content grep

No bulk transfer. The remote runs `grep` directly, the only bytes streamed
back are matching lines (`file:line:content`).

Command template:

```sh
ssh <host> "nice -n19 ionice -c3 timeout 30 \
    find <path> -type f -size -1M \
    -not -path '*/.*' \
    -not -path '*/node_modules/*' \
    -not -path '*/venv/*' \
    -name '<glob>' \
    -exec grep -IlH '<pattern>' {} + 2>/dev/null"
```

Defaults baked in:

- `nice -n19 ionice -c3` — low CPU/IO priority, cannot starve other remote processes.
- `timeout 30` — aborts runaway searches.
- `-size -1M` — skips large files (logs, binaries).
- Skip hidden dirs, `node_modules`, `venv`.
- `grep -I` — skips binary files silently.

All overridable per call via a prompt flag:
`<leader>sg` prompt accepts e.g. `pattern=foo path=/etc glob=*.conf +timeout=60 +size=10M +hidden`.

Enter on a result opens the matched file via `scp://` at the matching line.

## 6. Bug-fix register (MyHappyPlace → happy-nvim)

### BUG-1: Format-on-save fires twice

**Root cause:** `MyHappyPlace/lua/plugins/lsp.lua` installs both a manual
`BufWritePre` formatter in `LspAttach` *and* `lsp_zero.format_on_save`. Both
hook the same event.

**Fix:** remove `lsp-zero`. Drop the manual `BufWritePre` autocmd.
All formatting goes through `conform.nvim` with a single `format_on_save`
owner:

```lua
require('conform').setup({
  formatters_by_ft = {
    lua         = { 'stylua' },
    python      = { 'ruff_format', 'ruff_organize_imports' },
    go          = { 'goimports', 'gofmt' },
    javascript  = { 'biome' }, typescript = { 'biome' },
    sh          = { 'shfmt' }, yaml = { 'yamlfmt' },
    cpp         = { 'clang-format' }, c = { 'clang-format' },
  },
  format_on_save = { timeout_ms = 500, lsp_fallback = true },
})
```

### BUG-2: Keymap conflicts

**Root cause:** `<leader>p` bound four times in
`MyHappyPlace/lua/config/keymaps.lua`; `<leader>y` bound twice; no
namespace discipline.

**Fix:**

1. Define a keymap namespace table (see README):

   | Prefix | Domain |
   |---|---|
   | `<leader>f` | files / find (telescope) |
   | `<leader>g` | git |
   | `<leader>l` | LSP actions |
   | `<leader>d` | diagnostics |
   | `<leader>h` | harpoon |
   | `<leader>s` | remote / ssh |
   | `<leader>c` | Claude |
   | `<leader>t` | tmux popups |
   | `<leader>y`, `<leader>p` | system clipboard (single binding each) |
   | `<leader>?` | cheatsheet |

2. All keymaps except core editing register through `which-key.add`.
   which-key warns at startup on duplicate registrations — a runtime
   collision detector.

3. `config/keymaps.lua` shrinks to core non-namespaced bindings only:
   `J` / `K` move, `<C-d>` / `<C-u>` centered scroll, `Q` nop, `<C-c>` as
   `Esc`.

### BUG-3: Theme / visual jank

**Root causes in `MyHappyPlace/lua/config/options.lua`:**

- `vim.opt.guicursor = ""` — often invisible in kitty / alacritty.
- `vim.opt.hlsearch = false` — disorienting search UX.
- `vim.opt.colorcolumn = "80"` — ignores per-filetype conventions.
- Theme setup scattered; no highlight-group overrides.

**Fix:**

- `guicursor` → `'n-v-c-sm:block,i-ci-ve:ver25,r-cr-o:hor20'`.
- `hlsearch = true`; `<Esc>` clears current highlight (`:nohlsearch`).
- `colorcolumn` per filetype via autocmd (80 for md/txt, 120 for lua/go/python,
  off for tex).
- `tokyonight.setup({ style = 'storm', styles = { comments = { italic = true } } })`
  runs **before** `colorscheme tokyonight`, which runs before any plugin that
  reads highlight groups.
- Override collection in `lua/config/colors.lua` — `LineNr` contrast bump,
  `FloatBorder` tweak. Fixes live in one file, not scattered.
- `vim.opt.termguicolors = true` moved to `plugins/colorscheme.lua` before the
  theme loads (init order matters).

### BUG-4: Plugin load errors / lazy-load issues

**Root causes:**

- Keymaps reference undeclared plugins (`vim-with-me`, `cellular-automaton.nvim`).
- `lazy.setup({ defaults = { lazy = false } })` disables lazy loading globally.

**Fix:**

- Delete keymaps for phantom plugins (`<leader>vwm`, `<leader>svwm`,
  `<leader>mr`, `<leader>vpp`).
- `lazy.setup({ defaults = { lazy = true } })`. Each plugin spec declares its
  own `event` / `cmd` / `keys` triggers.
- Startup budget: `:Lazy profile` reports < 50 ms for core, < 200 ms full.
- CI check: headless nvim starts without errors.

### Bonus fixes

- `vim.opt.undodir = vim.fn.stdpath('state') .. '/undo'` — XDG-compliant,
  replaces `~/.vim/undodir`.
- `<C-c>` → `<Esc>` kept (intentional, commented as such).

## 7. Error handling & edge cases

### 7.1 OSC 52 clipboard

| Case | Handling |
|---|---|
| Bare local terminal | Autocmd guard short-circuits; VM clipboard via `unnamedplus` still works. |
| Tmux `allow-passthrough off` | OSC 52 bytes stripped silently. `:checkhealth` writes a sentinel and asks the user to verify host paste. |
| Mosh < 1.4 | Same strip behavior. `:checkhealth` warns if `mosh --version` is too old and `$MOSH_CONNECTION` is set. |
| Yank > 74 KB | Skip OSC 52 emit, log warning; VM clipboard still populated. |
| Sensitive content | No filter. User intent wins. README notes the leak surface. |

### 7.2 `coach/`

| Case | Handling |
|---|---|
| `tips.lua` empty | `random_tip()` returns nil; alpha shows "Add tips to `lua/coach/tips.lua`". |
| Telescope not loaded on `<leader>?` | Lazy-triggered via `keys` spec; telescope loads on first use. |

### 7.3 `tmux/` Claude integration

| Case | Handling |
|---|---|
| `$TMUX` unset | Module returns early; no `<leader>c*` keymaps bound. |
| `<leader>cs/cf/ce` before `<leader>cc` | Float: "No Claude pane registered. Press `<leader>cc` first." |
| Claude pane killed externally | `tmux list-panes -t <id>` fails → clear `@claude_pane_id` → float: "Claude pane gone. Reopen with `<leader>cc`." |
| Multiple nvims in one tmux window | `@claude_pane_id` is window-scoped; all nvims share one Claude pane. Documented. |
| Payload contains triple backticks | Switch fence to `~~~`. |
| Selection > 10 KB | Confirm prompt before send. |

### 7.4 `remote/`

| Case | Handling |
|---|---|
| ssh connect fails | `vim.system()` nonzero → float: `"ssh <host> failed: <first stderr line>"`. |
| ssh prompts for password | `vim.system()` has no TTY → ssh errors out. README mandates key-based auth; `:checkhealth` warns. |
| `find` hits permission-denied | `2>/dev/null` swallows; results are best-effort. |
| Grep timeout (124) | Float: "grep timed out. Narrow path / glob or pass `+timeout=60`." |
| Stale cached dir list | Return cached data instantly + queue background refresh. Lualine shows `⟳ <host>` during refresh. |
| Corrupt cache JSON | `pcall(vim.json.decode)`; on fail, delete + refetch. Never bubble. |
| `~/.ssh/config` absent | Host picker falls back to frecency DB only. |
| Binary / huge scp:// open | Guard refuses with hint; `<leader>sO` forces. |
| Host unresolvable but high-ranked | User picks → ssh fails → DB decays score; `:HappyHostsPrune` cleans up. |
| Concurrent `<leader>sg` | Each spawns its own `vim.system()`. No global lock. |

### 7.5 Startup & plugin loading

| Case | Handling |
|---|---|
| First run, mason servers not installed | `mason-lspconfig` auto-installs; user sees `"Installing lua-language-server..."`. |
| Fresh clone, lazy.nvim missing | `init.lua` bootstraps via git clone (kickstart's standard snippet). |
| Plugin spec syntax error | `lazy.nvim` shows interactive error UI; other plugins still load. |
| Treesitter parser compile fails | `:checkhealth` flags; highlighting degrades to regex. Non-fatal. |

### 7.6 General principles

- Never let an error prevent nvim from starting.
- User messages via `vim.notify` (backed by `nvim-notify`).
- No silent failures for user-facing actions.
- `:checkhealth happy-nvim` covers: tmux version + passthrough + set-clipboard,
  mosh version, terminal OSC 52 hint, `ssh-agent` running, local CLIs
  (`rg`, `fd`, `rsync`, `stylua`, `gcc`), XDG dirs writable, plugin load
  status, LSP server install status.

## 8. Testing & verification

### 8.1 Layers

1. **Static.** `stylua` (format check) + `selene` (undefined globals, shadowing,
   unused). Both in CI.
2. **Headless startup smoke.** `nvim --headless -c 'qa!'`; grep for
   `Error|E\d+:`; fail CI on match.
3. **`:checkhealth happy-nvim`.** Implementation in `lua/happy/health.lua`.
   Runs in CI, greps for `ERROR` lines.
4. **Opt-in integration smoke.** `scripts/smoke.sh` — yank + OSC 52 roundtrip,
   scp:// round-trip, scripted tmux for `<leader>cc`. Manual, pre-release only.
5. **Human verification matrix.** Documented checklist in README:
   yank→host paste, `<leader>cc` opens pane, `<leader>cs` sends selection,
   `<leader>ss` ranked hosts, `<leader>sg` sample pattern < 5 s, theme loads
   without flash, `:checkhealth` clean, `:Lazy profile` < 200 ms.

### 8.2 CI

GitHub Actions `.github/workflows/ci.yml`:

- `lint` — stylua + selene
- `startup` — headless smoke
- `health` — spawn tmux, run `:checkhealth happy-nvim`
- `plugins` — `:Lazy! sync --headless`, verify clean install

Matrix: `ubuntu-latest` × `macos-latest`, nvim `stable` + `nightly`.

### 8.3 Acceptance criteria (v1.0)

- All four BUG-* fixes (§6) verified via the human matrix.
- CI green on both platforms.
- `:checkhealth` clean on a fresh VM + fresh mosh session.
- `tips.lua` seeded with ≥ 30 entries across categories.
- README includes install curl, keymap table, tmux/OSC 52 prereqs.
- Author dogfoods happy-nvim for one full workday without falling back to
  MyHappyPlace.

## 9. Migration notes

1. `MyHappyPlace` is archived, not deleted (historical value + commit graph).
2. `~/.config/nvim` is currently a git repo with `MyHappyPlace` content.
   Migration:
   - `mv ~/.config/nvim ~/.config/nvim.myhappyplace.bak`
   - clone happy-nvim into `~/.config/nvim`
   - copy over personal data only: `~/.vim/undodir` stays where it is (new
     config points at `stdpath('state')/undo`, starting fresh is acceptable
     given undo history is per-file).
3. Re-install language servers on first launch via mason.
4. No keymap is silently preserved from MyHappyPlace — if it's not in the new
   keymap table, it's gone. This is intentional (bug class 4).

## 10. Out-of-band decisions (for writing-plans to expand)

These are locked but will need concrete task breakdowns in the plan phase:

- Initial `tips.lua` seed content (30+ entries).
- Initial `scripts/ssh-z.zsh` contents.
- lualine segment definitions (claude-pane indicator, cache-staleness indicator).
- `health.lua` probe order (fastest first, failing slow probes last).
- Exact `:checkhealth` messages (tone, wording).
