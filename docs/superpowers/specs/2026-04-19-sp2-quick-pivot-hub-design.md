# SP2 — Quick-Pivot Hub (Design Spec)

**Status:** design approved 2026-04-19
**Scope:** sub-project 2 of the tmux-integration vision overhaul (parent
todo `30.13`). Builds on SP1 (projects registry) + SP3 (hosts picker).
Ships a single `<leader><leader>` picker that merges projects + hosts +
active claude sessions into one frecency-ordered list — one keystroke
answers "where am I going next?"

Sibling sub-projects: SP1 (shipped), SP3 (shipped), SP4 (parallel
claude — pending).

## 1. Problem

Three pickers cover distinct navigation surfaces:

- `<leader>P` → projects registry (SP1)
- `<leader>ss` → ssh hosts (SP3)
- `<leader>cl` → claude sessions (SP1)

All three are "where next?" but a user pivoting between a work project,
a host, and an ongoing claude session has to remember which picker lives
where. User's vision from 2026-04-19 brainstorm: "ONE key answers 'where
am I going next?' — picker opens, first entry is your most-frecent
next-place. Enter pivots."

## 2. Solution (one-line)

Add `lua/happy/hub/` module that aggregates the three existing sources
into a unified telescope picker behind `<leader><leader>`. Scores
normalized per source + weighted so projects dominate by default but
recently-used hosts and working claude sessions float up.

## 3. Architecture

```
                     <leader><leader>
                            │
                            ▼
                   ┌─────────────────┐
                   │ happy.hub.open  │
                   └────────┬────────┘
                            │ aggregates
          ┌─────────────────┼─────────────────┐
          ▼                 ▼                 ▼
  ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐
  │  projects    │  │  hosts       │  │  sessions        │
  │  (SP1)       │  │  (SP3)       │  │  (tmux-derived)  │
  │              │  │              │  │                  │
  │ registry.list│  │ hosts.list   │  │ list-sessions    │
  │  → proj rows │  │  → host rows │  │ ^cc-|^remote-    │
  └──────┬───────┘  └──────┬───────┘  └──────┬───────────┘
         │                 │                 │
         ▼                 ▼                 ▼
   Entry shape: { kind, id, display, score, on_pivot }
         │                 │                 │
         └─────────┬───────┴───────┬─────────┘
                   │               │
                   ▼               ▼
             Scored + sorted; telescope picker
```

**Invariants:**
1. Hub does NOT mutate any source. Reads only.
2. If a session's name maps to a project id in the registry (e.g.
   `cc-proj-a` where `proj-a` is a registered project), the session is
   suppressed — user pivots via the project row. Sessions source only
   emits **orphan** sessions (not in registry).
3. Hub module is a strict addition — zero changes to SP1 registry or
   SP3 hosts.

## 4. Components

**New files:**

- `lua/happy/hub/init.lua` — `M.setup()` registers `<leader><leader>`,
  `M.open()` opens the picker, `M.sources()` returns the merged entry
  list.
- `lua/happy/hub/sources.lua` — three private fns `project_rows()`,
  `host_rows()`, `session_rows()`. Each returns normalized entries with
  `{ kind, id, display, score, on_pivot }`. Score is raw (per-source
  scale); `init.lua` does the weight + normalize.

**Modified files:**

- `init.lua` (project root) — add `'happy.hub'` to the module list at
  line 33 (mirrors SP1 pattern).
- `lua/coach/tips.lua` — append one entry for `<leader><leader>`.
- `docs/manual-tests.md` — new `§ 13. Quick-pivot hub (SP2)` with 3
  rows.

**Unchanged:**

- `lua/happy/projects/registry.lua`, `lua/happy/projects/pivot.lua` —
  consumed read-only.
- `lua/remote/hosts.lua` — consumed read-only.

## 5. Entry shape + scoring

Each source function returns a list of entries. Internal shape:

```lua
{
  kind = 'project' | 'host' | 'session',
  id = <string>,            -- canonical id (proj id, host name, session name)
  label = <string>,         -- user-visible label column
  status = <string>,        -- short status column (e.g. '✓ idle', '⟳ working', '2h ago')
  raw_score = <number>,     -- per-source raw frecency score
  on_pivot = <function>,    -- what to do on Enter
}
```

**Scoring:**

Each source has its own raw-score range:
- projects → `registry.score(id)` (zoxide-style, already normalized-ish)
- hosts → `hosts._score(entry, now)` (internal fn; exposed via `list()`)
- sessions → activity-based: 1.0 if working, 0.5 if idle, 0.1 if stale,
  0.0 if dead

Hub normalizes per source (divide by source max, or 1.0 if max is 0)
and applies weights:

```lua
local WEIGHTS = { project = 1.0, session = 0.8, host = 0.6 }
```

Final score = `normalized_raw * WEIGHTS[kind]`. Sort descending.

**Configurable:**

```lua
require('happy.hub').setup({
  weights = { project = 1.5, host = 0.3 },   -- partial override
})
```

## 6. Pivot actions per kind

**project:**
```lua
on_pivot = function() require('happy.projects.pivot').pivot(entry.id) end
```
Reuses SP1's `pivot` (cd nvim + focus `cc-<id>` tmux session).

**host:**
```lua
on_pivot = function()
  require('remote.hosts').record(entry.id)
  local mosh = vim.fn.executable('mosh') == 1 and 'mosh' or 'ssh'
  vim.system({ 'tmux', 'new-window', mosh .. ' ' .. entry.id }):wait()
end
```
Matches existing `<leader>ss` default behavior.

**session (orphan only):**
```lua
on_pivot = function()
  if vim.env.TMUX and vim.env.TMUX ~= '' then
    vim.system({ 'tmux', 'switch-client', '-t', entry.id }):wait()
  else
    vim.notify(entry.id .. ' is alive — attach via `tmux attach -t ' .. entry.id .. '`.',
      vim.log.levels.INFO)
  end
end
```

## 7. Session-orphan detection

`session_rows()` calls `tmux list-sessions -F '#S'` and filters
`^cc-` / `^remote-`. For each matching session name:

```lua
local id = name:gsub('^cc%-', ''):gsub('^remote%-', '')
local entry = registry.get(id)
if entry then
  -- covered by project row; skip session
  return false
end
-- orphan — include in hub
```

Rationale: if the session is tied to a project, user pivots via the
project row (which already focuses the session). Orphans — sessions
whose slug doesn't map to a registry id — come from manual
`tmux new-session cc-foo` or from legacy pre-SP1 sessions that weren't
migrated. Showing them in the hub lets the user attach without first
registering.

## 8. Display format

Telescope entry row (monospace, fixed widths):

```
<kind-icon>  <id, truncated to 24>  ·  <label>         ·  <status>
```

- Project local:  ` `
- Project remote: ``
- Host: `󰢹`
- Session orphan: `󰚩`

Example:

```
  happy-nvim              · /home/raul/projects/happy-nvim    · ✓ idle    · 12m ago
  logs-prod01             · prod01:/var/log                   · ⟳ working · 4m ago
󰢹 prod01                  · ssh prod01                                    · 2h ago
󰚩 cc-legacy-foo           · (orphan)                          · ✓ idle    · 1d ago
```

Telescope's fuzzy matcher handles substring filtering (typing "proj"
narrows to projects; "prod" narrows to prod01).

## 9. Keymap + coach tips

**Keymap** (registered in `lua/happy/hub/init.lua:M.setup`):

```lua
vim.keymap.set('n', '<leader><leader>', function()
  require('happy.hub').open()
end, { desc = 'Quick pivot: projects + hosts + sessions' })
```

**Coach tips entry** (append to `lua/coach/tips.lua`):

```lua
{
  keys = '<leader><leader>',
  desc = 'quick-pivot hub: projects + hosts + sessions (SP2)',
  category = 'projects',
},
```

## 10. Testing

**Plenary unit:** `tests/happy_hub_sources_spec.lua`:

- Stub `registry.list` + `registry.score` → 3 projects. Assert
  `project_rows()` returns 3 entries with `kind='project'` + correct
  `on_pivot` closures.
- Stub `hosts.list` → 2 hosts + add-marker. Assert `host_rows()` drops
  the add-marker and returns 2 host entries.
- Stub `tmux list-sessions` (via fake `run_tmux`) → `cc-proj-a\ncc-legacy\nrandom`.
  Stub `registry.get('proj-a')` = entry, `registry.get('legacy')` = nil.
  Assert `session_rows()` returns 1 orphan (`cc-legacy`).
- `sources()` merges + weights: seed 1 project + 1 host + 1 session,
  assert final sort order matches weights × normalized raw scores.

**Integration:** `tests/integration/test_hub_pivot.py`:

- Pre-seed registry JSON + hosts.json + start a fake `cc-*` tmux session
  on the test socket.
- Launch headless nvim, call `require('happy.hub').sources()`.
- Assert result has expected count of each kind.
- Second test: invoke `on_pivot` for a project entry; assert
  `pivot.pivot(id)` was called (stub).

**Manual tests:** 3 rows in `docs/manual-tests.md § 13`.

## 11. Out of scope

- Worktree source (discussed + dropped — projects registry auto-covers
  any cwd where user ran `<leader>cc`).
- Cross-machine sync — per-machine only, matches SP1.
- Inline peek / preview in picker — keep minimal; `<leader>Pp` already
  provides peek for projects.
- Typed filters (e.g. `type:project` prefix) — telescope fuzzy matcher
  suffices.

## 12. Rollout

Single push to `main`. Additive — zero impact on existing keymaps.

## 13. Open questions

None.

## Manual Test Additions

Three rows appended to `docs/manual-tests.md` under new
`§ 13. Quick-pivot hub (SP2)`:

```markdown
## 13. Quick-pivot hub (SP2)

- [ ] `<leader><leader>` opens a single picker merging projects + hosts + orphan claude sessions. Entries show kind icon + id + label + status + age.
- [ ] Pivot to a project entry → same effect as `<leader>P` → Enter (cwd cd + tmux session focus).
- [ ] Pivot to a host entry → same effect as `<leader>ss` → Enter (ssh in tmux split).
- [ ] Sessions whose slug matches a registered project are suppressed from the session source (no duplicate row).
```

(Wrote 4 rows; tighten to 3 for §13 header "3 rows" — the duplicate-
suppression check is an invariant test; keep it to catch regression.)
