# happy-nvim — Manual Test Checklist

Run through this list to verify the config works end-to-end. Items not
covered by CI (real TTY, real Claude CLI, real clipboard, real ssh, real
nerd fonts). Mark each [x] pass / [ ] fail / [~] skipped. Open an issue
for any fail.

## 0. Pre-flight

- [ ] `nvim --version` reports 0.11+
- [ ] `tmux -V` reports 3.2+
- [ ] `tree-sitter --version` exists on $PATH
- [ ] Terminal font is a Nerd Font (icons render, not boxes/?). If you see `?`, run `fc-list | grep -i 'nerd font'` — empty output = install per README Prerequisites.
- [ ] `$SHELL` is zsh or bash
- [ ] `bash scripts/assess.sh` runs to completion with `ASSESS: ALL LAYERS PASS`
- [ ] Inside nvim `:HappyAssess` opens a scratch buffer w/ live output; final line shows `:HappyAssess finished (exit code 0)`

## 1. Core editing

- [ ] Open a .lua file — syntax colors render (vim regex or treesitter)
- [ ] (CI-covered, slow — Mason cold install) Open a .py file — LSP attaches within 2s (`:LspInfo` shows client); `:w` reformats via ruff_format (conform.nvim, single format only — BUG-1 regression)
- [ ] Edit .lua, `:w` — stylua formats automatically (conform.nvim)
- [ ] `<Space>fh` — telescope harpoon list
- [ ] (CI-covered, but worth spot-checking locally) `<Space>ff` in a repo with >50 files — telescope sorts by relevance, not alphabet
- [ ] (CI-covered) harpoon persists marks across nvim restarts if the same cwd is re-opened (v2 stores in `~/.local/share/nvim/harpoon2.json`)
- [ ] `<Space>ha` on 3 different files — harpoon marks added
- [ ] `<Space>h1/2/3` — buffer switches to marked files
- [ ] `<Space>u` — undotree opens
- [ ] `<Space>gs` — fugitive :Git opens in a split

## 2. Macro-nudge

- [ ] Open nvim cold — alpha dashboard shows "Tip: <keys>" in footer
- [ ] (CI-covered) Press `<Space>` alone, wait 400ms — which-key popup lists groups (find/git/LSP/diag/harpoon/ssh/Claude/tmux/cheatsheet)
- [ ] (CI-covered) Press `<Space>?` — cheatsheet picker opens
- [ ] Type `jjjj` in normal mode — hardtime warns about j-repeat
- [ ] Move cursor to a word — precognition overlays show motion targets (w/b/e etc)

## 3. Clipboard (real terminal, mosh+tmux+nvim)

- [ ] Yank a line in nvim (yy) inside tmux over mosh
- [ ] On the host (outside mosh), `Cmd+V` (mac) / `Ctrl+V` (win/linux) — pastes the yanked line
- [ ] On the VM (inside mosh), `xclip -o -selection clipboard` — returns the yanked line
- [ ] Yank > 74KB — nvim notifies "yank too large for OSC52" (host clipboard skipped, VM clipboard still works)

## 4. Tmux + Claude

Requires `claude` CLI on $PATH + `$TMUX` set.

- [ ] (CI-covered) `<C-h/j/k/l>` in nvim at window edge — moves active tmux pane (vim-tmux-navigator)


- [ ] `<Space>cc` — spawns a horizontal tmux pane w/ claude. Conversation persists on repeat press.
- [ ] `<Space>cf` — sends current file as `@path`. Pane shows the ref.
- [ ] Select a range visually, `<Space>cs` — sends fenced code block w/ `file.lua:L10-L14` header.
- [ ] `<Space>ce` — sends LSP diagnostics for the file.
- [ ] `<Space>cp` — popup appears (85x85), `claude` running. `prefix+d` detaches — popup closes, session alive.
- [ ] `<Space>cp` again — reattaches SAME conversation (history visible).
- [ ] `<Space>cC` — pane session killed + respawned (empty history).
- [ ] `<Space>cP` — popup session killed + respawned.
- [ ] `<Space>cl` — telescope picker lists all open `cc-*` sessions. Entries show `✓/⟳/?` icons + relative age.
- [ ] `<Space>cl` then `<C-x>` on an entry — session killed, picker refreshes.
- [ ] `<Space>cn` then type `sidebar` — spawns `cc-sidebar` session + popup.
- [ ] `<Space>ck` — confirm Yes — current project's session killed.
- [ ] `:checkhealth happy-nvim` section "claude integration" shows:
  - `ok claude CLI found on $PATH`
  - `ok tmux X.Y supports display-popup -E` (X.Y >= 3.2)
  - Per-window pane state (ok/info/warn)
  - Per-project popup session state (ok/info)
- [ ] After `require('tmux.claude_popup').setup({ popup = { width = '50%' } })` in init.lua, `<Space>cp` opens a narrower popup
- [ ] Inside Claude popup, press `Ctrl-C` mid-reply — claude interrupts the current generation, popup stays open, history preserved
- [ ] `<Space>cp` again — same conversation visible (Ctrl-C didn't tear it down)

## 5. Multi-project Claude

Open 2 tmux panes, nvim in each, one in /path/to/repoA, other in /path/to/repoB.

- [ ] `<Space>cc` in pane A — opens `cc-<A>` session. Conversation about A.
- [ ] `<Space>cc` in pane B — opens DIFFERENT `cc-<B>` session. Separate conversation.
- [ ] Back in pane A: `<Space>cf` — goes to A's Claude, NOT B's.
- [ ] Let A reply + go idle ≥2s. `<Space>cl` picker shows `✓ <A>`.
- [ ] Send new input to A. `<Space>cl` shows `⟳ <A>`.
- [ ] If tmux status-right snippet from README is installed: status bar shows per-project badges.

- [ ] `git worktree add` a branch + run `wt-claude-provision.sh <path>` — `tmux ls` shows new `cc-<repo>-wt-<branch>` session
- [ ] Open nvim in that worktree → `<Space>cp` attaches to the pre-warmed session (history empty since just-spawned, but no cold-start delay)
- [ ] Run `wt-claude-cleanup.sh <path>` then `git worktree remove <path>` → `tmux ls` no longer shows the session

## 6. Remote (ssh/scp, real host)

Requires a real reachable ssh host.

- [ ] (CI-covered, partial — only data layer via remote.hosts._merge+_parse_ssh_config, not picker UI) `<Space>ss` — frecency host picker. Most-recent host at top.
- [ ] Pick a host — drops you into ssh session via tmux split.
- [ ] Back in nvim: `<Space>sd` — remote dir picker (zoxide-like, cached 7d).
- [ ] `<Space>sB` then enter `user@host:/etc/hostname` — opens as scp:// buffer.
- [ ] Try to open a binary remote file via `<Space>sB` — refuses w/ "looks binary (MIME: binary)" notify.
- [ ] `<Space>sO` then reopen — loads anyway (override).
- [ ] (CI-covered, partial — _build_cmd only, not network) `<Space>sg` then enter pattern — runs `nice ionice ssh <host> 'grep -EIlH ...'` — results in quickfix.
- [ ] `:HappyHostsPrune` — reports pruned hosts count.

## 7. Health

- [ ] `:checkhealth happy-nvim` — sections: core, local CLIs, tmux, mosh, ssh, XDG dirs, tree-sitter, winborder
- [ ] No `ERROR:` lines (warnings on optional deps are OK)

---

Last updated: coverage batch landed 2026-04-18 (coach, LSP/conform, remote/hosts, remote/grep, tmux-nav, whichkey).
