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
