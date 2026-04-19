# SP1 — Multi-Project Cockpit (Design Spec)

**Status:** design approved 2026-04-19
**Scope:** sub-project 1 of the tmux-integration vision overhaul (parent
todo `30.13`). Subsumes todos `30.3` (multi-project `<leader>cc` no-op),
`30.12` (worktree-claude helpers unsurfaced), and partially resolves
`30.8` (ss empty picker) and `30.11` (which-key coverage).

Sibling sub-projects SP2 (quick-pivot hub), SP3 (fast remote ops),
SP4 (parallel claude pattern) are separate specs.

## 1. Problem

Working on >1 project at a time — a mix of manually edited source and
autonomous claude sessions on distinct project directories. Current
happy-nvim model: per-project `cc-<slug>` tmux session created on
`<leader>cc`; routing via `@claude_pane_id` on the nvim window.

Pain points reported:
- Cannot see multiple projects' state simultaneously — have to swap
  tmux sessions to check what each claude is doing.
- Second `<leader>cc` in a different tmux pane no-ops (bug).
- Worktree claude provisioning lives in shell scripts (`wt-claude-*`)
  with no nvim surface.
- Remote ssh workflows (log inspection, arbitrary cmd on hosts) have
  no "project" identity — they drop out of the cockpit.
- No registry of known projects → no fast pivot.

## 2. Solution (one-line)

Promote "project" to a first-class, persistent entity with a unified
picker (`<leader>P`), ambient status (nvim statusline + tmux
status-right), and a remote-project kind backed by a **one-way
sandboxed local claude** so hosts that can't install anything still
benefit.

## 3. Architecture

```
┌─────────────────────────────────────────────┐
│ Cockpit nvim (any instance, not singleton)  │  ← 1 active project
│  ┌─────────────────────────────────────┐    │
│  │ source buffers, telescope, harpoon  │    │
│  └─────────────────────────────────────┘    │
│  statusline: ✓ proj-a · ⟳ proj-b · ✓ logs-prod│  ← ambient status
└─────────────────────────────────────────────┘
        │                  ▲
        │ <leader>P pivot  │ status poll (2s)
        ▼                  │
┌──────────────┐  ┌──────────────┐  ┌─────────────────────┐
│ cc-proj-a    │  │ cc-proj-b    │  │ remote-logs-prod01  │
│ tmux session │  │ tmux session │  │ tmux session        │
│ claude CLI   │  │ claude CLI   │  │ ssh prod01 (pane A) │
│              │  │              │  │ sandboxed claude    │
│              │  │              │  │   (pane B, local)   │
└──────────────┘  └──────────────┘  └─────────────────────┘

Registry: ~/.local/share/nvim/happy/projects.json  (per-machine)
```

**Invariants:**

1. Registry is source of truth for project identity. Tmux sessions are
   named `cc-<id>` (local) or `remote-<id>` (remote). Sessions may die
   and respawn; registry entry persists.
2. **Cockpit is not singleton.** Any nvim with happy-nvim loaded is a
   cockpit. Multiple nvim instances on the same machine read/write the
   same registry (atomic writes).
3. Remote projects **never execute on the host from claude**. Data
   flow is strictly `remote → claude` and user-initiated.

## 4. Components

All new files under `lua/happy/projects/`:

- `registry.lua` — CRUD on `projects.json`, frecency math, migration
  from existing `cc-*` tmux sessions on upgrade. Exposes:
  `add{kind,path|host+path} → id`, `forget(id)`, `list() → [entries]`,
  `touch(id)` (bump frecency + last_opened).
- `picker.lua` — telescope `<leader>P`. entry_maker renders
  `[icon] slug · <age> · <status-icon>`. `<C-a>` inline-add by typed
  text (path or `host:path`), `<C-d>` forget, `<C-p>` peek-only,
  `Enter` pivot.
- `pivot.lua` — pivot primitive. Nvim side: `:cd <path>`; harpoon2 is
  already cwd-keyed so its per-project state is automatic, no extra
  file swapping needed. Tmux side: focus `cc-<id>`/`remote-<id>`
  pane. If the tmux session is dead, auto-spawn a fresh one and notify
  `cc-<id> session was dead — spawned fresh.` Do not prompt.
- `status.lua` — polls tmux sessions every 2s (piggybacks on existing
  `lua/tmux/idle.lua` busy/idle state where possible); exports
  `lualine` component + helper that renders tmux status-right format
  string. Max 5 entries before truncation with `…+N`.
- `remote.lua` — remote-project lifecycle. On add: create sandbox dir
  `~/.local/share/nvim/happy/remote-sandboxes/<id>/` + write project-
  local `.claude/settings.local.json` (sandbox deny/allow list).
  On pivot: spawn `remote-<id>` tmux session with a single ssh pane
  (`ssh <host>` cd'd to remote path). Sandboxed claude is NOT pre-
  spawned — it opens on demand via `<leader>cp`, attached as a tmux
  popup bound to the sandbox dir. Capture primitives live here.

**Touched existing files:**

- `lua/tmux/claude.lua` — `open_guarded` and friends call
  `registry.touch(current_project_id())` before/after spawn; fix
  bug 30.3 (second-pane no-op) by resolving session via registry
  instead of pane-local `@claude_pane_id`.
- `lua/tmux/claude_popup.lua` — `<leader>cp` resolves target session
  via registry; no change to popup mechanics.
- `lua/tmux/picker.lua` — `<leader>cl` now a filtered view of
  `projects.picker` (kind=local OR remote, session alive).
- `lua/tmux/project.lua` — `slug_for_cwd` retained but registry IDs
  supersede slug as canonical session identifier. Slug becomes a
  display label.
- `scripts/wt-claude-provision.sh`, `wt-claude-cleanup.sh` —
  wrapped as `:HappyWtProvision <path>` / `:HappyWtCleanup <path>`
  nvim commands (closes 30.12). Wrappers `vim.system` the scripts
  async, stream output to a scratch buffer.

## 5. Keymaps

| Key | Mode | Action |
|-----|------|--------|
| `<leader>P`  | n | Open projects picker |
| `<leader>Pa` | n | Add project (prompt path or `host:path`) |
| `<leader>Pd` | n | Forget project (picker-only, maps to `<C-d>`) |
| `<leader>Pp` | n | Peek-only (no pivot) |
| `<leader>cl` | n | Claude sessions picker (filtered projects picker) |
| `<leader>cc` | n | Open/attach pane for active project (unchanged) |
| `<leader>cp` | n | Popup for active project (unchanged; remote → sandboxed claude) |
| `<leader>Cc` | n | Capture last N lines of remote pane → sandbox claude |
| `<leader>Ct` | n | Toggle tail-capture pipe remote pane → `sandbox/<id>/live.log` |
| `<leader>Cl` | n | Pull remote file via scp → sandbox dir |
| `<leader>Cs` | v | Send visual selection from ssh pane buffer → claude input |

Commands:

- `:HappyProjectAdd <path-or-host:path>`
- `:HappyProjectForget <id>`
- `:HappyWtProvision <path>` / `:HappyWtCleanup <path>`

Which-key groups:

- `<leader>P` — `+project`
- `<leader>C` — `+capture (remote→claude)` (distinct from existing
  `<leader>c` = `+claude`)

## 6. Storage schema

`~/.local/share/nvim/happy/projects.json`:

```json
{
  "version": 1,
  "projects": {
    "proj-a": {
      "kind": "local",
      "path": "/home/raul/projects/happy-nvim",
      "last_opened": 1713456000,
      "frecency": 0.8,
      "open_count": 42,
      "sandbox_written": false
    },
    "logs-prod01": {
      "kind": "remote",
      "host": "prod01",
      "path": "/var/log",
      "last_opened": 1713400000,
      "frecency": 0.3,
      "open_count": 3,
      "sandbox_written": true
    }
  }
}
```

**Frecency formula** (zoxide-style):

```
weight(entry) = open_count * exp(-age_hours * 0.05)
age_hours     = (now - last_opened) / 3600
```

Recently-opened + frequently-opened float to top. Decays slowly (~50%
weight after ~14 hours of idleness per use).

**Writes** are atomic: write to `projects.json.tmp` → `rename()` →
`projects.json`. Multi-nvim safe under POSIX rename semantics.

**ID generation:** slugify(`path` basename for local,
`host-basename` for remote). Collision → append `-2`, `-3`, …

## 7. Remote-pinned sandboxed claude

**Goal:** one-way `remote → claude` data flow. Claude helps analyze
logs pasted/streamed from the remote; claude itself cannot reach the
host (no ssh, no network at all, no fs access outside sandbox dir).

**Sandbox `settings.local.json`** written into
`~/.local/share/nvim/happy/remote-sandboxes/<id>/.claude/settings.local.json`:

```json
{
  "permissions": {
    "deny": [
      "Bash(ssh:*)", "Bash(scp:*)", "Bash(sftp:*)",
      "Bash(rsync:*)", "Bash(mosh:*)",
      "Bash(curl:*)", "Bash(wget:*)",
      "WebFetch(*)",
      "Bash(nc:*)", "Bash(socat:*)", "Bash(ssh-*)",
      "Read(/**)", "Edit(/**)", "Write(/**)"
    ],
    "allow": [
      "Read(~/.local/share/nvim/happy/remote-sandboxes/<id>/**)",
      "Write(~/.local/share/nvim/happy/remote-sandboxes/<id>/**)",
      "Edit(~/.local/share/nvim/happy/remote-sandboxes/<id>/**)"
    ]
  }
}
```

Host placeholder (`<id>`) substituted at write time with the actual
sandbox dir path. Claude spawned with `cwd` = sandbox dir.

**Capture primitives** (remote → claude, user-initiated):

- `<leader>Cc`: `tmux capture-pane -t <ssh-pane> -p -S -500` →
  write to `sandbox/<id>/capture-<ts>.log` → send `@capture-<ts>.log`
  ref + a 1-line user summary to claude via `lua/tmux/send.lua`.
- `<leader>Ct`: toggle `tmux pipe-pane -t <ssh-pane> -o
  'cat >> sandbox/<id>/live.log'`. Claude Reads `live.log`. Second
  press turns pipe off.
- `<leader>Cl`: runs `scp <host>:<path> sandbox/<id>/` on the local
  machine (not inside claude's sandbox). Claude then Reads the file.
- `<leader>Cs`: visual-selection register `+` contents → claude
  input.

All capture primitives run in the local nvim process (outside
claude's sandbox). Claude is a passive consumer of files in its
sandbox dir.

**User owns the sandbox.** The settings file is
`settings.local.json` (intentionally the editable-by-user layer).
User may loosen the deny list manually; documented as an escape
hatch, not a default.

## 8. Migration

On first load after upgrade:

1. `tmux list-sessions -F '#S'` → filter `^cc-`.
2. For each, `tmux show-env -t <session> HAPPY_PROJECT_PATH` (set on
   future creates; legacy sessions have no value → skip with debug
   log).
3. For resolved: `registry.add(kind=local, path=<value>,
   last_opened=now, frecency=0.5)`.
4. Notify once: `Migrated N existing claude sessions to projects
   registry.`

Idempotent (re-running is safe — `add` dedups by path).

New `<leader>cc` creates sessions with
`tmux set-env -t <session> HAPPY_PROJECT_PATH <cwd>` so future
migrations and peek/pivot work without the registry having been
loaded yet.

## 9. Testing

**Unit (plenary):**

- `registry.add` / `forget` / `touch` round-trip.
- Frecency ordering — newer entry with fewer opens beats older entry
  with more opens when age delta > N hours; property-test the curve.
- ID collision resolution (`proj-a` → `proj-a-2`).
- Atomic write — kill-during-write simulation leaves a readable file.

**Integration (pytest, `tests/integration/`):**

- `test_project_pivot.py`: headless tmux → create 2 local projects
  → `<leader>P` → Enter on second → assert `:cd` + tmux session
  focus.
- `test_multi_cc_no_op_fixed.py`: regression for bug 30.3 —
  `<leader>cc` in a second tmux pane (different cwd) creates a
  session, does not no-op.
- `test_remote_project_sandbox.py`: add `remote-test:/tmp` →
  spawn sandboxed claude → attempt `Bash(ssh test ls)` → assert
  denied by settings.local.json.
- `test_remote_sandbox_no_fs_escape.py`: attempt `Read(~/.ssh/config)`
  from sandboxed claude → denied.
- `test_capture_primitives.py`: `<leader>Cc` after fixture output
  in ssh pane → sandbox dir contains `capture-*.log` with expected
  contents.
- `test_migration.py`: pre-seed tmux session with
  `HAPPY_PROJECT_PATH` env → load plugin → assert registry has
  migrated entry.

**Manual tests** — appended to `docs/manual-tests.md`:

```
## 9. Multi-project cockpit (SP1)

- [ ] `<leader>P` shows all registered projects, local + remote
- [ ] `<C-a>` in picker w/ a path → new local project, picker refreshes
- [ ] `<C-a>` in picker w/ `prod01:/var/log` → new remote project, ssh pane opens
- [ ] Pivot to remote project, `<leader>cp` → sandboxed claude popup opens
- [ ] In sandboxed claude, ask "run `ls` on the host" → refuses (Bash(ssh*) denied)
- [ ] In sandboxed claude, ask "open my ssh config" → refuses (Read outside sandbox denied)
- [ ] `<leader>Cc` after `ls -la` in remote pane → sandboxed claude sees output
- [ ] `<leader>Pp` on a non-active project → scrollback tail shown, no pivot
- [ ] `<leader>cc` in a second tmux pane (different cwd) → creates a distinct session (bug 30.3 fixed)
- [ ] `:HappyWtProvision <path>` and `:HappyWtCleanup <path>` work from nvim
```

## 10. Out of scope

- **Source-of-2-projects side-by-side editing.** If ever needed, add
  later via a tabpage-per-project option; not part of SP1.
- **Cross-machine project sync.** Per-machine registry only.
- **Automatic frecency push from zoxide.** Can be added in SP2 (hub)
  as a bootstrap option.
- **Log streaming into claude's context live** (vs. via file).
  `<leader>Ct`'s pipe-to-file + Read is close enough; true streaming
  is SP4-adjacent.
- **Parallel claudes per project** (quick-commit + long-running) —
  SP4.

## 11. Rollout

Single PR. No feature flag — behavior is additive (new keymaps,
new commands). Existing `<leader>cc`/`<leader>cp` keep working via
registry-backed routing.

## 12. Open questions

None outstanding after this design. Any implementation ambiguity
resolved in the plan file.

## Manual Test Additions

(Listed in §9 above. These rows are appended to `docs/manual-tests.md`
by the implementing subagent as part of its final commit.)
