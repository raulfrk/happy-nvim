# SP4 — Parallel Claude Pattern (Design Spec)

**Status:** design approved 2026-04-19
**Scope:** final sub-project of the tmux-integration vision overhaul
(parent todo `30.13`). Adds `<leader>cq` — ephemeral "scratch" claude
session alongside the pinned project claude. Single-shot: session dies
when popup closes.

## 1. Problem

Post-SP1 model: one `cc-<id>` tmux session per project. If a long-
running claude is busy on a refactor (e.g. "rewrite the registry
layer"), the user can't open a second claude in the same project for
a quick task ("write me a commit msg for this diff") without killing
the long one. Current workaround — `<leader>cn` + manual slug — is a
5-keystroke ritual for a 10-second task.

User vision: "quick claude sessions for quick commits while maybe
bigger slower work is ongoing."

## 2. Solution (one-line)

Add `<leader>cq` → spawn `cc-<id>-scratch-<epoch>` tmux session with
same cwd (or sandbox dir for remote projects) → open as popup → kill
session when popup closes.

## 3. Architecture

```
  <leader>cq
       │
       ▼
 ┌──────────────────────┐
 │ M.open_scratch       │  in lua/tmux/claude.lua
 └──────┬───────────────┘
        │
        ▼
 Resolve current project via registry.add({kind='local', path=cwd})
        │
        ▼
 Session name: cc-<id>-scratch-<os.time()>
        │
        ▼
 cwd = (remote) sandbox_dir(id)  OR  (local) project.path
        │
        ▼
 tmux new-session -d -s <name> -c <cwd> claude
        │
        ▼
 tmux display-popup -E -w 85% -h 85% tmux attach -t <name>
        │
        ▼
 on exit: tmux kill-session -t <name>
```

**Invariants:**
1. Scratch sessions NEVER pollute the projects registry.
2. Remote-project scratch claude inherits SP1 sandbox (same deny list;
   no host reachability from claude).
3. Single-shot: popup close = session die. User wants parallel
   persistent sessions → use `<leader>cn` (existing).
4. Multiple concurrent scratches allowed (each gets unique epoch
   suffix). Spam-pressing `<leader>cq` won't collide.

## 4. Components

**Modified:**
- `lua/tmux/claude.lua` — add `M.open_scratch()` + `M.open_scratch_guarded()`
- `lua/plugins/tmux.lua` — register `<leader>cq` keymap
- `lua/coach/tips.lua` — append entry
- `lua/plugins/whichkey.lua` — no change (already has `<leader>c` group)
- `docs/manual-tests.md` — new §14 rows

**New:**
- `tests/integration/test_claude_scratch.py` — regression

## 5. Implementation — `M.open_scratch`

Append to `lua/tmux/claude.lua` (after `M.open_fresh_guarded` or at
bottom of file):

```lua
local function scratch_name_for(id)
  return ('cc-%s-scratch-%d'):format(id, os.time())
end

local function scratch_cwd_for(id, fallback_cwd)
  local ok, remote = pcall(require, 'happy.projects.remote')
  local reg_ok, registry = pcall(require, 'happy.projects.registry')
  if ok and reg_ok then
    local entry = registry.get(id)
    if entry and entry.kind == 'remote' then
      return remote.sandbox_dir(id)
    end
  end
  return fallback_cwd
end

function M.open_scratch()
  local id, _, cwd = session_for_cwd()
  local name = scratch_name_for(id)
  local effective_cwd = scratch_cwd_for(id, cwd)
  local res = vim.system({
    'tmux', 'new-session', '-d', '-s', name, '-c', effective_cwd, 'claude',
  }, { text = true }):wait()
  if res.code ~= 0 then
    vim.notify(
      'failed to spawn scratch claude: ' .. (res.stderr or ''),
      vim.log.levels.ERROR
    )
    return
  end
  -- Popup. On close, kill the session.
  vim.system({
    'tmux', 'display-popup', '-E', '-w', '85%', '-h', '85%',
    'tmux', 'attach', '-t', name,
  }, {}, function()
    vim.system({ 'tmux', 'kill-session', '-t', name }):wait()
  end)
end

function M.open_scratch_guarded()
  if guard() then
    M.open_scratch()
  end
end
```

`session_for_cwd` and `guard` already exist in the file from SP1 T6.

## 6. Keymap

In `lua/plugins/tmux.lua` add to the keys spec (next to other `<leader>c*`):

```lua
{
  '<leader>cq',
  function() require('tmux.claude').open_scratch_guarded() end,
  desc = 'Claude: quick scratch popup (single-shot)',
},
```

## 7. Coach tips

Append to `lua/coach/tips.lua`:

```lua
{
  keys = '<leader>cq',
  desc = 'quick scratch claude popup (ephemeral, single-shot, SP4)',
  category = 'claude',
},
```

## 8. Testing

**Integration test:** `tests/integration/test_claude_scratch.py`

Stub `vim.system` with a capture closure. Trigger
`require('tmux.claude').open_scratch_guarded()` with `$TMUX` set.
Assert:

1. `tmux new-session` was called with a session name matching
   `cc-<id>-scratch-<digits>`.
2. `tmux display-popup ... tmux attach -t <same-name>` was called.
3. The callback registered with `display-popup`'s async invocation
   calls `tmux kill-session -t <same-name>` when fired.

```python
# tests/integration/test_claude_scratch.py
import os, subprocess, textwrap, re


def test_scratch_spawns_kills_on_close(tmp_path):
    argv_log = tmp_path / 'argv.log'
    snippet = textwrap.dedent(f'''
        local repo = '{os.getcwd()}'
        vim.opt.rtp:prepend(repo)
        vim.env.TMUX = 'dummy'
        os.environ = nil  -- Luajit: noop

        local calls = {{}}
        local saved_cb
        vim.system = function(cmd, opts, cb)
          table.insert(calls, table.concat(cmd, ' '))
          if cb then saved_cb = cb end
          return {{
            wait = function() return {{ code = 0, stdout = '', stderr = '' }} end,
            is_closing = function() return false end,
            kill = function() end,
          }}
        end

        -- Stub registry so scratch doesn't try to disk-persist a new entry.
        package.loaded['happy.projects.registry'] = {{
          add = function() return 'proj-test' end,
          get = function() return {{ kind = 'local', path = '/tmp' }} end,
          touch = function() end,
          score = function() return 0 end,
        }}

        local claude = require('tmux.claude')
        vim.fn.getcwd = function() return '/tmp' end
        claude.open_scratch()

        -- Fire the display-popup close callback to trigger kill.
        if saved_cb then saved_cb() end

        local fh = io.open('{argv_log}', 'w')
        for _, c in ipairs(calls) do fh:write(c .. '\\n') end
        fh:close()
        vim.cmd('qa!')
    ''')
    subprocess.run(
        ['nvim', '--clean', '--headless', '-u', 'NONE', '-c', f'lua {snippet}'],
        check=True, timeout=15,
    )
    log = argv_log.read_text()
    # new-session creates the scratch session
    m = re.search(r'tmux new-session -d -s (cc-[\w\-]+-scratch-\d+)', log)
    assert m, f'scratch new-session missing: {log}'
    scratch = m.group(1)
    assert ('tmux display-popup' in log and f'tmux attach -t {scratch}' in log), log
    assert f'tmux kill-session -t {scratch}' in log, log
```

## 9. Rollout

Additive — no existing keymap changes. Single commit/push.

## 10. Open questions

None.

## Manual Test Additions

```markdown
## 14. Parallel claude (SP4)

- [ ] `<leader>cq` opens a fresh claude popup. Session named `cc-<id>-scratch-<ts>`.
- [ ] Long-running `cc-<id>` session keeps running (unaffected).
- [ ] Popup close (`ctrl-d` / `prefix+d`) → `tmux ls` shows scratch session gone.
- [ ] Remote project: `<leader>cq` uses sandbox dir (claude inherits `.claude/settings.local.json`).
```
