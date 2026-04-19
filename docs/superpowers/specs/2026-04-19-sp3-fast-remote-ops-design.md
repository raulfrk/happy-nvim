# SP3 — Fast Remote Ops (Design Spec)

**Status:** design approved 2026-04-19
**Scope:** sub-project 3 of the tmux-integration vision overhaul (parent
todo `30.13`). Ships fast, no-install-on-host remote workflows — OSC 52
host-clipboard fix (30.2), seeded host picker (30.8), ad-hoc remote cmd
runner, log tailer, remote file-name finder.

Sibling sub-projects: SP1 multi-project cockpit (shipped), SP2 quick-pivot
hub (pending), SP4 parallel claude (pending).

## 1. Problem

### 30.2 — OSC 52 yanks don't reach host clipboard

`lua/clipboard/init.lua` emits raw OSC 52 escapes (`\e]52;c;<b64>\a`) to
`io.stdout` on `TextYankPost`. When nvim runs inside tmux inside mosh,
tmux intercepts the escape and **silently drops it** unless the user has
tmux configured with both `set-clipboard on` AND
`allow-passthrough on`. Default tmux configs don't, so yanks register
locally (nvim shows the orange flash + `"` register works) but the host
terminal never receives anything. User quote: "xclip -o on the VM shows
the line; paste in browser shows nothing."

### 30.8 — `<leader>ss` host picker empty on fresh install

`lua/remote/hosts.lua` reads frecency DB at
`~/.local/share/nvim/happy-nvim/hosts.json`, then falls back to non-
wildcard `Host` entries in `~/.ssh/config`. If both are empty (new
machine, no ssh_config yet), the picker shows nothing. Users can't
discover how to add a host — the only surfaces are frecency DB (built by
usage) and an ssh_config the user hasn't written.

### Gap — no ad-hoc remote cmd runner

The existing `<leader>s*` cluster covers: ssh into a host via tmux split
(`ss`), remote dir picker (`sd`), open a specific remote file (`sB`),
remote grep (`sg`). It doesn't cover "run `df -h` on prod01 and show me
the output" — a very common ops workflow.

### Gap — no log tailer

Similarly, no in-nvim way to `tail -F /var/log/app.log` on a remote host
and watch it live. Users fall back to: `<leader>ss` → tmux split → shell
→ `ssh host` → `tail -f`. Several steps + breaks the cockpit metaphor.

### Gap — no remote file-name finder

`<leader>sd` picks a dir. `<leader>sB` opens a named file. `<leader>sg`
greps content. Nothing fuzzy-finds a file by name inside a remote subtree
(e.g. "find any `config.yaml` under `/etc`").

## 2. Solution (one-line each)

- 30.2 — wrap OSC 52 in **tmux DCS passthrough** (`\ePtmux;\e<esc>\e\\`)
  when `$TMUX` is set. Works with default tmux config.
- 30.8 — always prepend a synthetic **`[+ Add host]` entry** to the picker.
  `<Enter>` on it prompts for `user@host[:port]`, stores to frecency,
  refocuses. Also bind `<C-a>` inside the picker to the same prompt.
- New `<leader>sc` — **ad-hoc remote cmd runner**. Prompt for cmd, pick
  host, stream `ssh <host> <cmd>` stdout+stderr into a scratch buffer.
  `<C-c>` kills.
- New `<leader>sT` — **log tailer**. Pick host + path, stream
  `ssh <host> tail -F <path>` into a scratch buffer with scroll-follow.
  `q` closes + kills.
- New `<leader>sf` — **remote file-name finder**. Pick host + root dir,
  run `find <dir> -type f -maxdepth 6` via ssh, pipe results into
  telescope. `<Enter>` opens selected as `scp://host/path` (reuses
  browse.lua).

## 3. Architecture

```
 lua/
   clipboard/
     init.lua          [MODIFIED — OSC 52 tmux DCS wrap]
   remote/
     hosts.lua         [MODIFIED — [+ Add host] entry + inline-add prompt]
     cmd.lua           [NEW — <leader>sc flow]
     tail.lua          [NEW — <leader>sT flow]
     find.lua          [NEW — <leader>sf flow]
     init.lua          [MODIFIED — register new keymaps]
   plugins/
     whichkey.lua      [MODIFIED — 3 new labels]
   coach/
     tips.lua          [MODIFIED — 3 new entries]
 docs/manual-tests.md  [MODIFIED — new §12 with 5 rows]
 tests/
   integration/
     test_osc52_tmux_passthrough.py   [NEW]
     test_ss_empty_state.py           [NEW]
     test_remote_cmd_runner.py        [NEW]
     test_remote_tail.py              [NEW]
     test_remote_find.py              [NEW]
```

**Invariants:**
1. Every new ssh subprocess runs via `remote.util.run` (async, pumps
   event loop per CLAUDE.md Subprocess hygiene).
2. All user-supplied input (host, path, pattern, cmd) is shell-escaped
   before being sent through `ssh` (matches prior fixes #19, #23).
3. No tool installed on the host — every feature uses POSIX-ubiquitous
   binaries: `tail`, `find`, `sh`. If a host lacks GNU `tail -F`, we
   degrade to `tail -f` (no `F`).

## 4. Fix 1 details (30.2) — OSC 52 tmux passthrough

**Current `lua/clipboard/init.lua:_encode_osc52`:**

```lua
function M._encode_osc52(content)
  local b64 = vim.base64.encode(content)
  if #b64 > MAX_B64 then return nil end
  return string.format('\027]52;c;%s\007', b64)
end
```

**New:** Check `$TMUX` and wrap in DCS passthrough:

```lua
function M._encode_osc52(content)
  local b64 = vim.base64.encode(content)
  if #b64 > MAX_B64 then return nil end
  local osc = string.format('\027]52;c;%s\027\\', b64)  -- ST terminator
  if vim.env.TMUX and vim.env.TMUX ~= '' then
    -- Tmux DCS passthrough: wrap inner escapes by doubling ESC, wrap
    -- whole thing in `\ePtmux; ... \e\\`. This forces tmux to forward
    -- the escape to the outer terminal regardless of
    -- `set-clipboard` / `allow-passthrough` settings.
    osc = '\027Ptmux;' .. osc:gsub('\027', '\027\027') .. '\027\\'
  end
  return osc
end
```

Also switch terminator from BEL (`\007`) to ST (`\e\\`). BEL is accepted
by most terminals but ST is the standards-compliant terminator; some
modern terminals (iTerm2 recent, WezTerm strict mode) only accept ST.
Tmux DCS passthrough specifically requires the inner sequence to be a
full ST-terminated escape so the `gsub` escape-doubling lines up.

**Diagnostic command:** `:HappyCheckClipboard` — a new user command that:
1. Emits a known test payload (`HAPPY-CLIPBOARD-TEST-<timestamp>`)
2. Prints a notify: "Emitted test OSC 52. Paste in the host terminal /
   browser — expect `HAPPY-CLIPBOARD-TEST-<timestamp>`."

Useful when the user reports "clipboard broken" — one shot, known
payload.

**Test:** `tests/integration/test_osc52_tmux_passthrough.py`. Stub
`vim.env.TMUX = 'dummy'` + `io.stdout:write` with a capture closure,
trigger a yank, assert the captured bytes start with `\ePtmux;` and
contain the doubled-ESC form of the inner OSC 52. Second test: with
`vim.env.TMUX = nil`, assert the raw (non-wrapped) form.

**Manual test rows:**
- Inside tmux+mosh+nvim, yank a line → host (outside mosh) `Cmd+V` /
  `Ctrl+V` pastes the line (30.2)
- `:HappyCheckClipboard` emits a `HAPPY-CLIPBOARD-TEST-<ts>` payload;
  paste in the host terminal shows that exact string

## 5. Fix 2 details (30.8) — empty-state hint + inline add

**Current `lua/remote/hosts.lua:list`:**

Reads frecency DB, falls back to ssh_config entries. Returns plain
host-name list to the picker.

**New:** Always prepend a synthetic entry with a marker field so the
picker can distinguish it:

```lua
function M.list()
  local now = os.time()
  local db = M._read_db()
  local entries = {}
  for host, entry in pairs(db) do
    table.insert(entries, {
      host = host,
      visits = entry.visits,
      last_used = entry.last_used,
      score = M._score(entry, now),
      source = 'frecency',
    })
  end
  if #entries == 0 then
    for _, h in ipairs(M._parse_ssh_config()) do
      table.insert(entries, { host = h, visits = 0, score = 0, source = 'ssh_config' })
    end
  end
  table.sort(entries, function(a, b) return a.score > b.score end)
  -- Always prepend the "add host" synthetic entry so the picker is never
  -- empty. `marker = 'add'` signals to the picker to handle Enter
  -- specially instead of treating it as a host selection.
  table.insert(entries, 1, { host = '[+ Add host]', marker = 'add' })
  return entries
end
```

Picker callback (in `lua/remote/init.lua` or wherever `ss` is wired):

```lua
-- on Enter in the picker:
if entry.marker == 'add' then
  vim.ui.input({ prompt = 'Add host (user@host[:port]): ' }, function(input)
    if not input or input == '' then return end
    M.record(input)  -- bumps frecency → DB
    vim.schedule(function() M.open_picker() end)
  end)
  return
end
-- ...existing: record + jump into ssh tmux split...
```

Plus: `<C-a>` keymap inside the picker → same prompt, mirrors
`<leader>P` pattern from SP1.

**Test:** `tests/integration/test_ss_empty_state.py`. Stub empty DB + no
ssh_config; call `remote.hosts.list()`; assert result has exactly 1
entry with `marker == 'add'`. Second test: DB has 2 hosts; assert 3
entries, first is the add marker, remaining 2 sorted by score.

**Manual test row:**
- Fresh install (no `~/.ssh/config`, empty frecency DB) → `<leader>ss`
  shows `[+ Add host]`. `<Enter>` prompts for `user@host[:port]`.
  Submitting adds to frecency and re-opens picker with new host (30.8)

## 6. New feature: `<leader>sc` remote cmd runner

**File:** `lua/remote/cmd.lua`

```lua
local M = {}
local util = require('remote.util')
local hosts = require('remote.hosts')

local function shell_escape(s)
  return "'" .. s:gsub("'", "'\\''") .. "'"
end

function M.run_cmd()
  vim.ui.input({ prompt = 'Remote cmd: ' }, function(cmd)
    if not cmd or cmd == '' then return end
    M._pick_host_then(function(host)
      M._stream_to_scratch(host, cmd)
    end)
  end)
end

function M._pick_host_then(callback)
  -- reuse hosts picker; callback receives the chosen host string
  hosts.open_picker(callback)  -- <-- picker is refactored to accept an optional callback for this + future SP3 features
end

function M._stream_to_scratch(host, cmd)
  local buf = vim.api.nvim_create_buf(false, true)
  local name = ('[ssh %s: %s]'):format(host, cmd)
  vim.api.nvim_buf_set_name(buf, name)
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'wipe'
  vim.cmd('sbuffer ' .. buf)

  local function append(lines)
    vim.schedule(function()
      if not vim.api.nvim_buf_is_valid(buf) then return end
      vim.bo[buf].modifiable = true
      vim.api.nvim_buf_set_lines(buf, -1, -1, false, lines)
      vim.bo[buf].modifiable = false
      -- scroll-follow
      local win = vim.fn.bufwinid(buf)
      if win ~= -1 then
        vim.api.nvim_win_set_cursor(win, { vim.api.nvim_buf_line_count(buf), 0 })
      end
    end)
  end

  -- Async vim.system (callback form, per CLAUDE.md Subprocess hygiene).
  local handle
  handle = vim.system({ 'ssh', host, cmd }, {
    text = true,
    stdout = function(_, data) if data then append(vim.split(data, '\n', { trimempty = true })) end end,
    stderr = function(_, data) if data then append(vim.tbl_map(function(l) return 'ERR: ' .. l end, vim.split(data, '\n', { trimempty = true }))) end end,
  }, vim.schedule_wrap(function(out)
    append({ ('--- exit %d ---'):format(out.code) })
  end))

  -- <C-c> in the buffer → SIGTERM the ssh process.
  vim.keymap.set('n', '<C-c>', function()
    if handle and not handle:is_closing() then handle:kill('sigterm') end
  end, { buffer = buf, desc = 'kill remote cmd' })
  vim.keymap.set('n', 'q', function() vim.cmd('bd!') end, { buffer = buf, desc = 'close' })
end

return M
```

**Refactor note:** `lua/remote/hosts.lua` needs a new `open_picker(callback)`
fn that opens the existing picker but invokes the caller-supplied callback
with the chosen host instead of the hardcoded "ssh into tmux split"
behavior. The existing `<leader>ss` keymap keeps the old callback; new
features (`sc`, `sT`, `sf`) pass their own.

**Test:** `tests/integration/test_remote_cmd_runner.py`. Stub
`vim.system` with a capture closure, trigger the cmd flow with host=
`localhost`, cmd=`echo hello`. Assert (a) a scratch buffer was created
with name `[ssh localhost: echo hello]`, (b) `vim.system` was called
with argv `{'ssh', 'localhost', 'echo hello'}`, (c) the exit-marker
line appeared.

**Manual test row:**
- `<leader>sc` → prompt for cmd → enter `df -h` → pick host → scratch
  buffer opens, streams `df -h` output, ends with `--- exit 0 ---`.
  `q` closes; `<C-c>` during a long cmd kills + shows `--- exit N ---`.

## 7. New feature: `<leader>sT` log tailer

**File:** `lua/remote/tail.lua`

Same streaming primitive as §6 but the ssh cmd is
`tail -F <remote-path>`. Two wrinkles:

1. **Remote path input:** prompt for the path *before* picking the host
   (so the cmd can reference it), or let the user type it after the
   host is chosen. Pick **after** — the dir picker (`sd`) already teaches
   this order.
2. **Degradation:** GNU `tail -F` follows across file rotations (log4j
   style). BSD `tail -F` also exists. POSIX `tail -f` doesn't follow
   rotations but stays attached to the original inode. Call `tail -F`
   first; if ssh exits non-zero immediately, retry with `tail -f` and
   notify "no -F support, fell back to -f".

```lua
function M.tail_log()
  hosts.open_picker(function(host)
    vim.ui.input({ prompt = 'Remote log path: ' }, function(path)
      if not path or path == '' then return end
      M._stream_tail(host, path)
    end)
  end)
end

function M._stream_tail(host, path)
  -- scratch buffer w/ same primitive as cmd.lua
  -- cmd: `ssh <host> tail -F <shell-escaped-path>`
  -- on exit code == 1 within first 500ms, retry with `tail -f`
  -- ... implementation similar to cmd._stream_to_scratch
end
```

**Test:** `tests/integration/test_remote_tail.py`. Similar to cmd
runner — stub `vim.system`, trigger flow, assert argv contains
`tail -F <path>` and scratch buffer name `[tail <host>:<path>]`.

**Manual test row:**
- `<leader>sT` → pick host → enter `/var/log/syslog` → scratch buffer
  streams log lines live. `q` closes + kills tail.

## 8. New feature: `<leader>sf` remote file-name finder

**File:** `lua/remote/find.lua`

```lua
function M.find_file()
  hosts.open_picker(function(host)
    vim.ui.input({ prompt = 'Remote dir to search (default: /): ', default = '/' }, function(dir)
      if not dir or dir == '' then return end
      M._list_then_pick(host, dir)
    end)
  end)
end

function M._list_then_pick(host, dir)
  -- `find <dir> -type f -maxdepth 6 2>/dev/null` via ssh.
  -- Pipe result into telescope.new_table → Enter opens scp://host/<path>.
  -- Uses remote.util.run (sync call that pumps event loop) so we can
  -- block in this function while the find completes — find over ssh
  -- can take 5-15s for a deep tree.
  local cmd = { 'ssh', host, ('find %s -type f -maxdepth 6 2>/dev/null'):format(shell_escape(dir)) }
  local result = util.run(cmd, { text = true }, 30000)
  if result.code ~= 0 then
    vim.notify('remote find failed: ' .. (result.stderr or ''), vim.log.levels.ERROR)
    return
  end
  local paths = vim.split(result.stdout or '', '\n', { trimempty = true })
  if #paths == 0 then
    vim.notify('no files under ' .. dir, vim.log.levels.INFO)
    return
  end
  -- Telescope picker:
  local pickers = require('telescope.pickers')
  local finders = require('telescope.finders')
  local conf = require('telescope.config').values
  local actions = require('telescope.actions')
  local action_state = require('telescope.actions.state')
  pickers.new({}, {
    prompt_title = ('remote find: %s:%s'):format(host, dir),
    finder = finders.new_table({ results = paths }),
    sorter = conf.generic_sorter({}),
    attach_mappings = function(prompt_bufnr)
      actions.select_default:replace(function()
        local sel = action_state.get_selected_entry()
        actions.close(prompt_bufnr)
        if sel and sel[1] then
          vim.cmd('edit scp://' .. host .. '/' .. sel[1])
        end
      end)
      return true
    end,
  }):find()
end
```

**Test:** `tests/integration/test_remote_find.py`. Stub
`remote.util.run` to return a canned `find` output (3 paths). Trigger
`find_file` flow with host/dir. Assert (a) `util.run` was called with
the expected `ssh ... find ...` argv, (b) the telescope picker opens
with 3 entries (or: use a test-mode flag that skips the picker and
returns `paths` so the test can assert them).

**Manual test row:**
- `<leader>sf` → pick host → enter `/etc` → picker lists files under
  `/etc` up to 6 levels deep. `<Enter>` opens selected as `scp://`.

## 9. Wiring

**`lua/remote/init.lua`** — register new keymaps. Current file already
registers `<leader>s{s,d,B,O,g}` via keys spec. Add:

```lua
{ '<leader>sc', function() require('remote.cmd').run_cmd() end, desc = 'remote ad-hoc cmd' },
{ '<leader>sT', function() require('remote.tail').tail_log() end, desc = 'remote log tail' },
{ '<leader>sf', function() require('remote.find').find_file() end, desc = 'remote find file' },
```

**`lua/plugins/whichkey.lua`** — the `<leader>s` group label already
exists. Individual keys are described by their `desc`. No new group
needed.

**`lua/coach/tips.lua`** — append 3 entries:

```lua
{ keys = '<leader>sc', desc = 'remote ad-hoc cmd (streams to scratch buffer)', category = 'remote' },
{ keys = '<leader>sT', desc = 'remote log tail (tail -F streaming)', category = 'remote' },
{ keys = '<leader>sf', desc = 'remote file-name finder (find + telescope)', category = 'remote' },
```

## 10. Testing summary

**Integration (pytest, 5 new files):**

1. `test_osc52_tmux_passthrough.py` — asserts DCS wrap when `$TMUX` set,
   raw OSC 52 otherwise
2. `test_ss_empty_state.py` — asserts `[+ Add host]` marker entry
3. `test_remote_cmd_runner.py` — stub ssh, assert argv + buffer
4. `test_remote_tail.py` — stub ssh, assert `tail -F <path>` + buffer
5. `test_remote_find.py` — stub `remote.util.run`, assert argv + results

**Plenary:** none — all new logic is flow/UI, covered by integration.

**Manual tests (5 rows):**

1. Yank inside tmux+mosh → host paste yields exact line (30.2)
2. `:HappyCheckClipboard` emits test payload → host paste shows it
3. Empty fresh install → `<leader>ss` shows `[+ Add host]` + inline-add
   works (30.8)
4. `<leader>sc` streams `df -h` into scratch → exit marker appears
5. `<leader>sT` streams `/var/log/syslog` → `q` kills + closes
6. `<leader>sf` → pick host + `/etc` → telescope lists files

## 11. Out of scope

- Replacing tmux with zellij / passthrough-of-every-escape (other
  escapes like OSC 7 cwd-tracking also get dropped; not SP3's problem).
- On-host tool installation (rg, fd). We stick to POSIX ubiquity.
- Graphical file-size / line-count previews in the `sf` picker (just a
  flat list).
- Piping `sc` output into quickfix (only useful for `grep`-shaped
  output; `<leader>sg` already handles that case).
- Persistent "favorite commands" for `<leader>sc` — YAGNI until users
  ask.

## 12. Rollout

Single push to main. No feature flags. The only behavior flip visible to
existing users is OSC 52 starting to actually work on default tmux
configs (a strict improvement). All other changes are additive.

## 13. Open questions

None.

## Manual Test Additions

Six rows appended to `docs/manual-tests.md` in a new `§ 12. Fast remote
ops (SP3)` section:

```markdown
## 12. Fast remote ops (SP3)

- [ ] Inside tmux+mosh+nvim, yank a line (yy) → host (outside mosh) `Cmd+V` / `Ctrl+V` pastes the line (30.2)
- [ ] `:HappyCheckClipboard` emits a `HAPPY-CLIPBOARD-TEST-<ts>` payload; paste in host terminal shows that exact string (30.2)
- [ ] Fresh install (no ~/.ssh/config, empty frecency DB) → `<leader>ss` shows `[+ Add host]` entry. `<Enter>` prompts for `user@host[:port]`, submission adds + re-opens picker (30.8)
- [ ] `<leader>sc` → enter `df -h` → pick host → scratch buffer streams output, ends with `--- exit 0 ---`. `q` closes; `<C-c>` during a long cmd kills + shows non-zero exit
- [ ] `<leader>sT` → pick host → enter `/var/log/syslog` → scratch streams log lines live. `q` closes + kills tail
- [ ] `<leader>sf` → pick host → `/etc` → telescope lists files up to 6 levels deep. `<Enter>` opens selected as `scp://`
```
