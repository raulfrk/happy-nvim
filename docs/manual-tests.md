# happy-nvim — Manual Test Checklist

Run through this list to verify the config works end-to-end. Items not
covered by CI (real TTY, real Claude CLI, real clipboard, real ssh, real
nerd fonts). Mark each [x] pass / [ ] fail / [~] skipped. Open an issue
for any fail.

## 0. Pre-flight

- [ ] `nvim --version` reports 0.11+
- [ ] `tmux -V` reports 3.2+
- [ ] (CI-covered) `tree-sitter --version` exists on $PATH
- [ ] Terminal font is a Nerd Font (icons render, not boxes/?). If you see `?`, run `fc-list | grep -i 'nerd font'` — empty output = install per README Prerequisites.
- [ ] (CI-covered) `$SHELL` is zsh or bash
- [ ] `bash scripts/assess.sh` runs to completion with `ASSESS: ALL LAYERS PASS`
- [ ] (CI-covered) Inside nvim `:HappyAssess` opens a scratch buffer w/ live output; final line shows `:HappyAssess finished (exit code 0)`

## 1. Core editing

- [ ] Open a .lua file — syntax colors render (vim regex or treesitter)
- [ ] (CI-covered, slow — Mason cold install) Open a .py file — LSP attaches within 2s (`:LspInfo` shows client); `:w` reformats via ruff_format (conform.nvim, single format only — BUG-1 regression)
- [ ] (CI-covered) Edit .lua, `:w` — stylua formats automatically (conform.nvim)
- [ ] (CI-covered) `<Space>fh` — telescope harpoon list
- [ ] (CI-covered, but worth spot-checking locally) `<Space>ff` in a repo with >50 files — telescope sorts by relevance, not alphabet
- [ ] (CI-covered) harpoon persists marks across nvim restarts if the same cwd is re-opened (v2 stores in `~/.local/share/nvim/harpoon2.json`)
- [ ] (CI-covered) `<Space>ha` on 3 different files — harpoon marks added
- [ ] (CI-covered) `<Space>h1/2/3` — buffer switches to marked files
- [ ] (CI-covered) `<Space>u` — undotree opens
- [ ] (CI-covered) `<Space>gs` — fugitive :Git opens in a split

## 2. Macro-nudge

- [ ] (CI-covered) Open nvim cold — alpha dashboard shows "Tip: <keys>" in footer
- [ ] (CI-covered) Press `<Space>` alone, wait 400ms — which-key popup lists groups (find/git/LSP/diag/harpoon/ssh/Claude/tmux/cheatsheet)
- [ ] (CI-covered) Press `<Space>?` — cheatsheet picker opens
- [ ] (CI-covered) Type `jjjj` in normal mode — hardtime warns about j-repeat
- [ ] Move cursor to a word — precognition overlays show motion targets (w/b/e etc)

## 3. Clipboard (real terminal, mosh+tmux+nvim)

- [ ] Yank a line in nvim (yy) inside tmux over mosh
- [ ] On the host (outside mosh), `Cmd+V` (mac) / `Ctrl+V` (win/linux) — pastes the yanked line
- [ ] On the VM (inside mosh), `xclip -o -selection clipboard` — returns the yanked line
- [ ] (CI-covered) Yank > 74KB — nvim notifies "yank too large for OSC52" (host clipboard skipped, VM clipboard still works)

## 4. Tmux + Claude

Requires `claude` CLI on $PATH + `$TMUX` set.

- [ ] (CI-covered) `<C-h/j/k/l>` in nvim at window edge — moves active tmux pane (vim-tmux-navigator)


- [ ] `<Space>cc` — spawns a horizontal tmux pane w/ claude. Conversation persists on repeat press.
- [ ] (CI-covered) `<Space>cf` — sends current file as `@path`. Pane shows the ref.
- [ ] (CI-covered) Select a range visually, `<Space>cs` — sends fenced code block w/ `file.lua:L10-L14` header.
- [ ] (CI-covered) `<Space>ce` — sends LSP diagnostics for the file.
- [ ] `<Space>cp` — popup appears (85x85), `claude` running. `prefix+d` detaches — popup closes, session alive.
- [ ] `<Space>cp` again — reattaches SAME conversation (history visible).
- [ ] (CI-covered) `<Space>cC` — pane session killed + respawned (empty history).
- [ ] (CI-covered) `<Space>cP` — popup session killed + respawned.
- [ ] `<Space>cl` — telescope picker lists all open `cc-*` sessions. Entries show `✓/⟳/?` icons + relative age.
- [ ] (CI-covered) `<Space>cl` then `<C-x>` on an entry — session killed, picker refreshes.
- [ ] (CI-covered) `<Space>cn` then type `sidebar` — spawns `cc-sidebar` session + popup.
- [ ] `<Space>ck` — confirm Yes — current project's session killed.
- [ ] (CI-covered) `:checkhealth happy-nvim` section "claude integration" shows:
  - `ok claude CLI found on $PATH`
  - `ok tmux X.Y supports display-popup -E` (X.Y >= 3.2)
  - Per-window pane state (ok/info/warn)
  - Per-project popup session state (ok/info)
- [ ] After `require('tmux.claude_popup').setup({ popup = { width = '50%' } })` in init.lua, `<Space>cp` opens a narrower popup
- [ ] Inside Claude popup, press `Ctrl-C` mid-reply — claude interrupts the current generation, popup stays open, history preserved
- [ ] `<Space>cp` again — same conversation visible (Ctrl-C didn't tear it down)
- [ ] (CI-covered) `<leader>tg` w/ `lazygit` missing → notify "lazygit not found on $PATH. Install: ..." — popup does NOT flash
- [ ] (CI-covered) `<leader>tb` w/ `btop` missing → same graceful notify
- [ ] `<leader>tt` opens shell popup at git root (falls back from $SHELL → zsh → bash → sh if needed)

## 5. Multi-project Claude

Open 2 tmux panes, nvim in each, one in /path/to/repoA, other in /path/to/repoB.

- [ ] `<Space>cc` in pane A — opens `cc-<A>` session. Conversation about A.
- [ ] `<Space>cc` in pane B — opens DIFFERENT `cc-<B>` session. Separate conversation.
- [ ] (CI-covered) Back in pane A: `<Space>cf` — goes to A's Claude, NOT B's.
- [ ] Let A reply + go idle ≥2s. `<Space>cl` picker shows `✓ <A>`.
- [ ] Send new input to A. `<Space>cl` shows `⟳ <A>`.
- [ ] If tmux status-right snippet from README is installed: status bar shows per-project badges.
- [ ] (CI-covered) Three projects open in parallel tmux panes. Let all three go idle — `<Space>cl` picker shows `✓` on all three. Send input to project A only. Picker shows `⟳ A / ✓ B / ✓ C`.

- [ ] `git worktree add` a branch + run `wt-claude-provision.sh <path>` — `tmux ls` shows new `cc-<repo>-wt-<branch>` session
- [ ] (CI-covered) Open nvim in that worktree → `<Space>cp` attaches to the pre-warmed session (history empty since just-spawned, but no cold-start delay)
- [ ] Run `wt-claude-cleanup.sh <path>` then `git worktree remove <path>` → `tmux ls` no longer shows the session

## 6. Remote (ssh/scp, real host)

Requires a real reachable ssh host.

- [ ] (CI-covered, partial — only data layer via remote.hosts._merge+_parse_ssh_config, not picker UI) `<Space>ss` — frecency host picker. Most-recent host at top.
- [ ] (CI-covered) Pick a host — drops you into ssh session via tmux split.
- [ ] (CI-covered) Back in nvim: `<Space>sd` — remote dir picker (zoxide-like, cached 7d).
- [ ] (CI-covered) `<Space>sB` then enter `user@host:/etc/hostname` — opens as scp:// buffer.
- [ ] (CI-covered) Try to open a binary remote file via `<Space>sB` — refuses w/ "looks binary (MIME: binary)" notify.
- [ ] (CI-covered) `<Space>sO` then reopen — loads anyway (override).
- [ ] (CI-covered, partial — _build_cmd only, not network) `<Space>sg` then enter pattern — runs `nice ionice ssh <host> 'grep -EIlH ...'` — results in quickfix.
- [ ] (CI-covered) `:HappyHostsPrune` — reports pruned hosts count.

## 7. Health

- [ ] (CI-covered) `:checkhealth happy-nvim` — sections: core, local CLIs, tmux, mosh, ssh, XDG dirs, tree-sitter, winborder
- [ ] (CI-covered) No `ERROR:` lines (warnings on optional deps are OK)

## 8. Idle alerts (Phase 3 follow-up)

- [ ] (CI-covered) Open `:Telescope find_files`, navigate any file → no `ft_to_lang` error in `:messages`
- [ ] (CI-covered) Idle alert: send prompt to a `cc-*` session from another tmux window. After Claude finishes, nvim shows `Claude (<slug>) idle` notification
- [ ] (CI-covered) Bell opt-in: set `alert.bell = true`, repeat above — terminal beep accompanies notify
- [ ] Desktop opt-in (requires `notify-send`/`osascript`): set `alert.desktop = true` → OS-level notification appears
- [ ] (CI-covered) Cooldown: trigger two flips in quick succession → only one notification
- [ ] (CI-covered) Focus-skip: stay in the `cc-*` pane → no notification fires
- [ ] (CI-covered) `<leader>cp` popup: notification fires **while popup still open** (after Claude finishes output, without detaching first)
- [ ] (CI-covered) `remote.util.run` keeps `vim.uv.timer` firing during an ssh subprocess
- [ ] `<leader>sd` / `<leader>sg` over real ssh: idle notifications from active `cc-*` sessions still fire during the find/grep

## 9. Multi-project cockpit (SP1)

- [ ] (CI-covered) `<leader>P` shows all registered projects, local + remote
- [ ] (CI-covered) `<C-a>` in picker w/ a path → new local project, picker refreshes
- [ ] (CI-covered) `<C-a>` in picker w/ `prod01:/var/log` → new remote project, ssh pane opens
- [ ] Pivot to remote project, `<leader>cp` → sandboxed claude popup opens (cwd = sandbox dir)
- [ ] In sandboxed claude, ask "run `ls` on the host" → refuses (Bash(ssh*) denied)
- [ ] In sandboxed claude, ask "open my ssh config" → refuses (Read outside sandbox denied)
- [ ] `<leader>Cc` after `ls -la` in remote pane → sandboxed claude sees output
- [ ] (CI-covered) `<leader>Pp` on a non-active project → scrollback tail shown, no pivot
- [ ] `<leader>cc` in a second tmux pane (different cwd) → creates a distinct `cc-<id>` session (bug 30.3 fixed; UX change: switch-client full attach, no inline split)
- [ ] (CI-covered) `:HappyWtProvision <path>` and `:HappyWtCleanup <path>` stream output in a scratch buffer, no `:wait()` hang
- [ ] Lualine shows `✓ <id>` (idle) / `⟳ <id>` (working) / `✗ <id>` (dead) per registered project
- [ ] (CI-covered) `<leader>Pa` prompts and registers a new project (`/path` → local, `host:path` → remote)

## 10. Bug batch 2026-04-19

- [ ] `:checkhealth happy-nvim` renders sections (core / local CLIs / tmux / claude integration) without "no healthcheck found" (30.1)
- [ ] Open a `.lua` file on a machine without `selene` installed → no error in `:messages` (30.5)
- [ ] `:HappyLspInfo` in a buffer with an attached client lists `• <name> (id=<n>, root=<path>)`; in a buffer with no client, prints "No LSP clients attached to this buffer." (30.6)

## 11. UX micro-batch 2026-04-19

- [ ] `<leader>ck` with active claude session → Y/N dialog at bottom. `<Y>` or `<Enter>` kills, `<N>` cancels. Pressing `<Enter>` repeatedly never loops (30.4)
- [ ] Cold `nvim` open on a `.lua` file → no `w / b / e / $ / ^ / %` overlays. `<leader>?p` toggles them on. Second `<leader>?p` toggles off (30.7)
- [ ] `<leader>?` cheatsheet opens → type `remote`, `claude`, `projects`, `capture`, `undo`, or `git` → results show the respective keybindings (30.9, 30.10, 30.11)

## 12. Fast remote ops (SP3)

- [ ] Inside tmux+mosh+nvim, yank a line (yy) → host (outside mosh) `Cmd+V` / `Ctrl+V` pastes the line (30.2)
- [ ] `:HappyCheckClipboard` emits a `HAPPY-CLIPBOARD-TEST-<ts>` payload; paste in host terminal shows that exact string (30.2)
- [ ] Fresh install (no ~/.ssh/config, empty frecency DB) → `<leader>ss` shows `[+ Add host]` entry. `<Enter>` prompts for `user@host[:port]`, submission adds + re-opens picker (30.8)
- [ ] `<leader>sc` → enter `df -h` → pick host → scratch buffer streams output, ends with `--- exit 0 ---`. `q` closes; `<C-c>` during a long cmd kills + shows non-zero exit
- [ ] `<leader>sT` → pick host → enter `/var/log/syslog` → scratch streams log lines live. `q` closes + kills tail
- [ ] `<leader>sf` → pick host → `/etc` → telescope lists files up to 6 levels deep. `<Enter>` opens selected as `scp://`

## 13. Quick-pivot hub (SP2)

- [ ] (CI-covered) `<leader><leader>` opens a single picker merging projects + hosts + orphan claude sessions. Entries show kind icon + id + label + status + age.
- [ ] Pivot to a project entry → same effect as `<leader>P` → Enter (cwd cd + tmux session focus).
- [ ] (CI-covered) Pivot to a host entry → same effect as `<leader>ss` → Enter (ssh in tmux split).
- [ ] Sessions whose slug matches a registered project are suppressed from the session source (no duplicate row).

## 14. Parallel claude (SP4)

- [ ] `<leader>cq` opens a fresh claude popup. Session named `cc-<id>-scratch-<ts>`.
- [ ] (CI-covered) Long-running `cc-<id>` session keeps running (unaffected).
- [ ] Popup close (`ctrl-d` / `prefix+d`) → `tmux ls` shows scratch session gone.
- [ ] Remote project: `<leader>cq` uses sandbox dir (claude inherits `.claude/settings.local.json`).

## §15 cc split layout (CI-covered partially)

| # | Surface | Test |
|---|---|---|
| 15.1 | `<leader>cc` on a wide window | Splits vertically (side-by-side) |
| 15.2 | `<leader>cc` on a tall/square window | Splits horizontally (stacked) |
| 15.3 | Same window, two `cd` projects | Each gets its own pane id (no collision) |

## §16 tt-* shell family

| # | Surface | Test |
|---|---|---|
| 16.1 | `<leader>tt` | Spawns `tt-<slug>` + opens popup attached (CI-covered) |
| 16.2 | `<leader>tn` → enter "foo" | Creates `tt-foo`, opens popup |
| 16.3 | `<leader>tl` | Lists tt-* sessions, Enter attaches, C-x kills (CI-covered) |
| 16.4 | Close popup | Session persists; `<leader>tt` reattaches |

## §17 Tail watches + detach/resume

| # | Surface | Test |
|---|---|---|
| 17.1 | `<leader>sL` → host → log path | Starts `tail-<host>-<slug>` tmux session; scratch buf opens tailing |
| 17.2 | Close scratch w/ `q` | Tmux session stays; state file keeps growing |
| 17.3 | `<leader>sP` → Enter | Reattaches; scratch shows existing + new lines |
| 17.4 | `<leader>sp` inside tail | Watch editor opens; edit + :w persists to JSON |
| 17.5 | Line matches active pattern | `vim.notify` fires w/ level (CI-covered) |
| 17.6 | Oneshot pattern | Flips inactive after first match (CI-covered) |
| 17.7 | Close + reopen nvim; `<leader>sp` | Previously-saved patterns reload |
| 17.8 | `<leader>sT` (deprecated) | Warns then forwards to sL |

---

Last updated: SP4 parallel claude landed 2026-04-19.
