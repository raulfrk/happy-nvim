# Tmux + Claude Rework (Design Spec)

**Status:** approved 2026-04-20
**Scope:** second-pass overhaul of the tmux + claude + remote flows
shipped in SP1–SP4. User ran the shipped UX and flagged mismatches
against their mental model. This spec captures the corrections + new
features (watch-pattern log tailing, ssh_buffer, layout-smart splits,
`tt-*` shell family).

## 1. Problems (from user feedback)

1. **`<leader>cc` session-switch model is buggy + wrong.** User wants
   split pane in current tmux window (pre-SP1 behavior), with
   layout-aware orientation (horizontal/vertical picked from current
   pane geometry), and without the same-window-collision bug.
2. **Popup should be the primary default** (`<leader>cp` is "the"
   claude flow). Split pane (`cc`) is the secondary.
3. **`<leader>cq` E5560 error on close** — `vim.wait` called inside a
   fast-event context.
4. **tmux-shell popups need a full cc-style family** — named,
   persistent, switchable, kill-able. Current `<leader>tt` dies on
   close with no way to name / list / resume.
5. **SSH flows inconsistent** — some skip the host picker and accept
   `user@host:` inline (e.g. `<leader>sB`). Every host-requiring flow
   must go through the picker.
6. **Remote editing via `scp://` has quirks** — netrw config surprises,
   sometimes requires sshpass, doesn't reuse ssh ControlMaster. Switch
   to a custom `ssh_buffer` module that pipes via ssh cat + stdin.
7. **Remote writes should be opt-in** — default read-only; per-buffer
   toggle to enable writes.
8. **Remote telescope pickers lack actions** — can only open as a
   buffer; user wants grep / tail / less / yank-path as picker actions.
9. **Log tails should support watch patterns** — notify when a pattern
   matches; editable while tail runs; persisted across nvim restarts
   per-host-path.
10. **Log tails should be detachable + resumable** — close scratch,
    tmux session stays alive, reattach later via picker.

## 2. Solution (per-concern one-liner)

1. `<leader>cc` = layout-smart split pane in current tmux window, pane
   id stored keyed on **project slug** (not window), so same-window
   multi-project doesn't collide.
2. `<leader>cp` = primary popup; auto-opens on idle alerts. `cc`
   becomes secondary.
3. Wrap the `vim.system({'tmux','kill-session',...}):wait()` inside
   the scratch-popup close callback with `vim.schedule_wrap`.
4. New `tt-*` family mirrors `cc-*`: `tt/tn/tl/tk/tR` = popup /
   new-named / list / kill / reset.
5. Audit every `<leader>s*` flow: any that reads a host must route
   through `remote.hosts.pick(callback)` before prompting path.
6. New `lua/remote/ssh_buffer.lua` replaces all `edit scp://...` call
   sites. `ssh://<host>/<path>` fake protocol; fetch via
   `ssh host 'cat <path>'`; save via `ssh host 'cat > <path>'`.
7. `ssh_buffer.open` sets `vim.bo.readonly = true` by default;
   `<leader>sw` toggles per-buffer `vim.b.happy_ssh_writable`; save
   refuses w/o the flag. Config knob
   `require('remote').setup({ ssh_writable_by_default = false })`.
8. Telescope picker actions on `<leader>sf/sd`: `<Enter>` open read-
   only, `<C-g>` grep-content, `<C-t>` tail, `<C-v>` less popup,
   `<C-y>` yank path, `<C-o>` drill-in (dir picker only).
9. Watch-pattern engine: `~/.local/share/nvim/happy/tail_patterns.json`
   stores every pattern ever attached. `<leader>sp` editor inside
   tail scratch adds/edits/restores-from-history. Reader scans
   incoming lines vs active patterns; on match → `vim.notify(...)`.
10. Tail backend: detached tmux session
    `tail-<host>-<slug>` running
    `ssh host 'tail -F <path>' | tee <state_file>`. Scratch buffer
    in nvim tails `<state_file>` via `vim.uv.fs_watch`. `q` in scratch
    detaches (closes buffer, tmux stays). `<leader>sP` picker lists
    active + resumable tails; `<Enter>` reattaches.

## 3. Architecture

New files:

- `lua/remote/ssh_buffer.lua` — fetch/save + read-only toggle + ~-expand.
- `lua/remote/ssh_exec.lua` — shared helper building ssh argv with
  ControlMaster options prepended (reused by ssh_buffer + cmd + tail +
  find + dirs + grep).
- `lua/remote/watch.lua` — watch-pattern engine (read/write
  `tail_patterns.json`, match per-line, dispatch notifies).
- `lua/tmux/tt.lua` — `tt-*` shell family (mirrors `claude_popup.lua`
  closely).
- `lua/tmux/split.lua` — layout-smart split helper used by `cc` + `cC`.

Modified:

- `lua/tmux/claude.lua` — `M.open` goes back to split, uses `split.lua`
  helper, tracks pane id keyed on project slug not window.
- `lua/tmux/claude_popup.lua` — stays as primary popup path; no
  behavior change beyond being marked primary.
- `lua/tmux/popup.lua` — lazygit/btop guards stay (from prior fix);
  `tt-*` flow lives in new `tt.lua`.
- `lua/remote/browse.lua` / `dirs.lua` / `grep.lua` / `cmd.lua` /
  `tail.lua` / `find.lua` — all migrate off scp:// to ssh_buffer; all
  use `ssh_exec` helper (adds ControlMaster); all route through
  `remote.hosts.pick` (no inline host).
- `lua/remote/hosts.lua` — cache per-host `$HOME` in the frecency DB
  entry (`home_dir` field) for ~ expansion.
- `lua/plugins/tmux.lua` — register `tt/tn/tl/tk/tR` keymaps.
- `lua/plugins/remote.lua` — rename `sT` → `sL`; register `sp/sP/sw`;
  rewire telescope actions.
- `lua/coach/tips.lua` — +~10 new entries.
- `docs/manual-tests.md` — 3 new sections.

## 4. Key decisions + details

### 4a. `<leader>cc` layout-smart split

```lua
-- lua/tmux/split.lua
local M = {}

function M.orient()
  local w = tonumber(vim.fn.system({ 'tmux', 'display-message', '-p', '#{window_width}' }))
  local h = tonumber(vim.fn.system({ 'tmux', 'display-message', '-p', '#{window_height}' }))
  if not w or not h then return 'h' end  -- fallback horizontal
  return (w / h > 2.5) and 'v' or 'h'
end

-- M.open(cmd, opts) → spawns tmux split-window (-h or -v) inside the
-- current nvim window; returns new pane id.
```

Pane id stored as window option `@claude_pane_id_<slug>` (not the bare
`@claude_pane_id`) so two different projects in the same tmux window
don't collide. The slug is the project id from SP1 registry.

### 4b. `ssh_buffer` model

- Buffer name: `ssh://<host>/<absolute-path>`.
- On `BufReadCmd ssh://*`: fetch via `ssh host 'cat <path>' → local buf`.
- On `BufWriteCmd ssh://*`: check `vim.b.happy_ssh_writable`; if set,
  pipe buffer content to `ssh host 'cat > <path>'` (close stdin); else
  notify "read-only; `<leader>sw` to enable".
- `filetype` inferred from extension (reuse `vim.filetype.match`).
- Binary refusal integrated: before `BufReadCmd`, check
  `ssh host 'file -b --mime-encoding <path>' == 'binary'` → refuse
  (reuses `browse._is_binary`).

### 4c. Watch pattern persistence

Schema (`~/.local/share/nvim/happy/tail_patterns.json`):

```json
{
  "version": 1,
  "patterns": [
    {
      "host": "prod01",
      "path": "/var/log/app.log",
      "regex": "ERROR.*panic",
      "level": "ERROR",
      "oneshot": false,
      "created_at": 1713590000,
      "last_matched_at": 1713590300,
      "active": true
    }
  ]
}
```

API (`lua/remote/watch.lua`):

```lua
M.list(host, path)            -- all patterns for this tail (active + history)
M.list_all()                  -- everything
M.add(host, path, regex, opts)
M.update(id, patch)           -- e.g. flip active, bump last_matched_at
M.remove(id)
M.set_active(host, path, ids) -- replace active set
M.scan(host, path, line)      -- returns list of matched pattern entries
```

### 4d. Detachable tail backend

Tail spawn:

```
tmux new-session -d -s tail-<host>-<slug> \
  "ssh <host> 'tail -F <path>' | tee <state_file>"
```

Scratch reader (`lua/remote/tail.lua`, revised):

- Opens scratch buffer `[tail <host>:<path>]`.
- `vim.uv.fs_watch(<state_file>)` → on change, append new lines.
- For each appended line: call `watch.scan(host, path, line)` → dispatch
  notifies.
- `q` in scratch: close buffer only (tmux session stays).
- Picker `<leader>sP` lists sessions matching `^tail-`; each entry
  resolves back to `host+path` via stored state index (JSON).

## 5. Keymap cheatsheet (final)

| Key | Cluster | Action |
|---|---|---|
| `<leader>cp` / `<leader>cP` | claude | popup / fresh popup (primary) |
| `<leader>cc` / `<leader>cC` | claude | layout-smart split / fresh split |
| `<leader>cl/cn/ck/cq/cf/cs/ce` | claude | unchanged |
| `<leader>tt` / `<leader>tR` | shell | popup default / reset |
| `<leader>tn/tl/tk` | shell | named / list / kill |
| `<leader>tg/tb` | utility popups | lazygit / btop (unchanged) |
| `<leader>ss` | ssh | host picker → ssh tmux split (unchanged) |
| `<leader>sd` | ssh | remote dir picker (always picks host) |
| `<leader>sB` | ssh | pick host → prompt path → ssh_buffer.open (RO) |
| `<leader>sw` | ssh | toggle write for current ssh:// buffer |
| `<leader>sO` | ssh | toggle binary-override (unchanged) |
| `<leader>sg` | ssh | remote grep → quickfix (always picks host) |
| `<leader>sc` | ssh | ad-hoc cmd (always picks host) |
| `<leader>sL` | ssh | log tail (renamed from `sT`) |
| `<leader>sf` | ssh | remote find file |
| `<leader>sp` | ssh | edit watch patterns for current tail |
| `<leader>sP` | ssh | tails picker (list/reattach/kill) |

## 6. Picker actions on remote file pickers (`sf`, `sd` drill-in leaf)

| Key in picker | Action |
|---|---|
| `<Enter>` | `ssh_buffer.open(host, path)` read-only |
| `<C-g>` | `remote.grep.run({host=host, path=path, pattern=<prompt>})` |
| `<C-t>` | `remote.tail.start(host, path)` |
| `<C-v>` | popup running `ssh host 'less +F <path>'` |
| `<C-y>` | `vim.fn.setreg('+', host .. ':' .. path)` |
| `<C-o>` (dirs only) | drill into subdir |

## 7. Migration notes

- Existing `cc-<slug>` tmux sessions + `@claude_pane_id_<slug>` window
  options left intact — SP1 session-model users lose nothing; the
  window option is read by the new cc split code.
- Existing `scp://` buffers: new `BufReadCmd ssh://*` doesn't conflict.
  Users still opening `scp://` use legacy netrw — not touched. Docs
  updated to recommend `<leader>sB`.
- `sT → sL` rename: users who hardcoded `<leader>sT` in a custom
  mapping get a `vim.keymap.set` shim for one release cycle printing a
  deprecation notice.

## 8. Testing

- Integration: ~15 new pytest tests (ssh_buffer roundtrip w/ stubs,
  readonly refusal, ~-expand, ControlMaster argv, layout-smart split
  orient, tt family, watch-pattern engine, detach+resume).
- Plenary: watch pattern scan unit tests (regex engine, one-shot
  semantics).
- Manual-tests: 3 new sections (`§ 15` cc split layout · `§ 16` tt
  shells · `§ 17` tail watches + detach/resume).

## 9. Rollout

Single branch, multiple commits (~12–15). Pushes batched. Breaking
change for users who typed `user@host:/path` into `<leader>sB` — now
prompts host first. Deprecation shim for `<leader>sT`.

## 10. Out of scope

- Remote editing of binary files (still refused).
- Auto-detection of remote cwd for non-`~` paths.
- Cross-machine tail-pattern sync.
- Real-time collaborative tail viewing (multiple nvims on same tail).
- Nvim-side undo-history persistence across ssh_buffer save.
- `<leader>cq` scratch persistence (kept single-shot).

## 11. Open questions

None.
