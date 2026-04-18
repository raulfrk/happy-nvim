# happy-nvim

A Neovim config focused on **macro fluency** — built to nudge a non-power-user
toward native nvim motions, text objects, macros, and registers.

Successor to [MyHappyPlace](https://github.com/raulfrk/MyHappyPlace).

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
| `<leader>cf` | Send @file ref |
| `<leader>ce` | Send file + diagnostics |
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

### Worktrees: pre-warmed Claude per branch

If you use `git worktree add` to keep multiple branches checked out, pair
your create/remove commands with the provisioning helpers:

```bash
# After creating a worktree
git worktree add ~/worktrees/myrepo/feat-x feat-x
bash ~/.config/nvim/scripts/wt-claude-provision.sh ~/worktrees/myrepo/feat-x

# Before removing one
bash ~/.config/nvim/scripts/wt-claude-cleanup.sh ~/worktrees/myrepo/feat-x
git worktree remove ~/worktrees/myrepo/feat-x
```

Either invoke the scripts manually, alias them, or hook them into your
worktree wrapper (e.g. the `worktree` MCP plugin's post-create / pre-remove
events if you use one). The session name (`cc-<repo>-wt-<branch>`) matches
what `<leader>cp` inside the worktree resolves to, so opening nvim there
attaches to the pre-warmed instance instead of cold-starting Claude.

## Working with Claude

Two surfaces for Claude Code, pick per task:

| Surface | Key | When to use |
|---|---|---|
| Split pane | `<leader>cc` | Long sessions; keep chat + code side-by-side. Per-nvim-window. |
| Floating popup | `<leader>cp` | Quick questions; reclaim screen space by dismissing. Global per project. |

### Keymap reference

| Key | Action |
|---|---|
| `<leader>cc` | open/attach per-window pane (splits horizontally on first press) |
| `<leader>cp` | toggle popup attached to `cc-<project>` session |
| `<leader>cC` | kill + respawn the pane (fresh Claude) |
| `<leader>cP` | kill + respawn the popup session (fresh Claude) |
| `<leader>cl` | telescope picker of every `cc-*` session w/ idle-state icons |
| `<leader>cn` | prompt for a slug → spawn a new `cc-<slug>` session in cwd |
| `<leader>ck` | kill the current project's popup session (confirm) |
| `<leader>cf` | send current file's path as `@path/to/file` to active surface |
| `<leader>cs` | (visual mode) send selection as fenced code block w/ file:lineno header |
| `<leader>ce` | send current buffer's LSP diagnostics + a "fix these" prompt |

### Send routing

`<leader>cf` / `<leader>cs` / `<leader>ce` auto-route in this priority:

1. `@claude_pane_id` on the current nvim window (set by `<leader>cc`).
2. The `cc-<current-project>` popup session's pane (set by `<leader>cp`).
3. If neither exists: warn + no-op.

You can have both open; pane wins when both are registered, so the
chat you've been looking at gets the send.

### Customizing popup size

Default is 85% × 85% of the outer terminal. Override in your
`init.lua` (or any file sourced after happy-nvim loads):

```lua
require('tmux.claude_popup').setup({
  popup = { width = '70%', height = '80%' },
})
```

Values are passed verbatim to `tmux display-popup -w / -h`, so absolute
cell counts (e.g. `120`) work too.

## Running tests

Three layers, cheapest first. All four commands run from the repo root.

### 1. Unit tests — plenary busted specs

Fast (~1s). Pure-lua assertions on module internals (project-id
resolver, idle state machine, coach tips, etc.).

```bash
nvim --headless -u tests/minimal_init.lua \
  -c "PlenaryBustedDirectory tests/ {minimal_init='tests/minimal_init.lua'}" \
  -c 'qa!'
```

### 2. Integration tests — real nvim in tmux

Slower (~30s). Scenarios spawn real nvim inside isolated tmux sessions
using the `fake-claude` stub. Requires `python3 -m pytest` + tmux >= 3.2.

```bash
bash scripts/test-integration.sh           # full suite
python3 -m pytest tests/integration/ -v    # equivalent
python3 -m pytest tests/integration/test_harpoon.py -v   # single scenario
```

Regenerate golden files for tests that use `assert_capture_equals`:

```bash
UPDATE_GOLDEN=1 python3 -m pytest tests/integration/test_whichkey_menu.py -v
```

### 3. One-button assessment — `scripts/assess.sh`

All six layers: shell/python syntax, init bootstrap, plenary, pytest
integration, `:checkhealth`. Prints a pass/fail table. Exits nonzero
on any failure. CI runs this under nvim stable + nightly.

```bash
bash scripts/assess.sh
```

Example output:

```
 LAYER                STATUS DURATION
----------------------------------------------------------------
 shell-syntax         PASS   0s
 python-syntax        PASS   1s
 init-bootstrap       PASS   0s
 plenary              PASS   1s
 integration          PASS   35s
 checkhealth          PASS   0s
ASSESS: ALL LAYERS PASS
```

Inside nvim:

```vim
:HappyAssess
```

Opens a scratch buffer streaming `assess.sh` output line-by-line. `:bd`
to close when done. Useful for quick verification after edits without
leaving the editor.

### 4. Manual checklist — `docs/manual-tests.md`

For features CI can't exercise (real `claude` CLI, real SSH, host clipboard,
Nerd Font rendering). Walk through before cutting a release.

## Multi-project notifications

Each active Claude session carries a `@claude_idle` tmux option that flips to
`1` after 2 seconds of stable output and back to `0` when you send input.
Add this snippet to your `~/.tmux.conf` to show a badge per session in
your status line:

```tmux
# ~/.tmux.conf
set -g status-right "#(bash -c 'for s in $(tmux list-sessions -F \"#{session_name}\" | grep ^cc-); do idle=$(tmux show-option -t \"$s\" -v -q @claude_idle); case \"$idle\" in 1) icon=\"✓\";; 0) icon=\"⟳\";; *) icon=\"?\";; esac; echo -n \" ${s#cc-}$icon\"; done') | %H:%M"
```

Reload with `tmux source-file ~/.tmux.conf`. Example rendering with two
open projects:

    happy-nvim✓ other-repo⟳ | 14:32

The `<leader>cl` picker shows the same state inline, so the status-bar
snippet is optional — useful mainly when you want always-visible state
without opening the picker.

### Active alerts

Beyond the passive status-bar badge, you can opt into push notifications
when a session flips busy→idle. Configure in your nvim setup:

```lua
require('tmux').setup({
  alert = {
    notify        = true,   -- vim.notify on flip (default ON)
    bell          = false,  -- terminal bell (\a)
    desktop       = false,  -- notify-send (Linux) / osascript (macOS)
    cooldown_secs = 10,     -- min seconds between alerts per session
    skip_focused  = true,   -- don't alert if you're in that session
  },
})
```

`vim.notify` integrates with `noice.nvim` automatically. `desktop` requires
`notify-send` (Linux) or `osascript` (macOS) on `$PATH`.
