# Manual-Tests → Pytest Conversion (Design Spec)

**Status:** approved 2026-04-20
**Scope:** convert the 42 AUTO rows in `docs/manual-tests.md` into
pytest integration tests. Parent todo #32, child todos 32.1–32.10.

## 1. Canonical design

**The authoritative design lives at `docs/manual-tests-audit.md`.** Every
AUTO-tagged row has a one-line harness hint. Each of the 10 child todos
maps to a section (or merged cluster) in that audit.

## 2. Conventions (proven patterns from prior SP1–SP4 work)

- **Isolated headless nvim:** `subprocess.run(['nvim', '--clean', '--headless', '-u', 'NONE', '-c', f'lua {snippet}'])` — no user config, no Lazy bootstrap. snippet begins with `vim.opt.rtp:prepend(os.getcwd())` to pick up the repo's `lua/` dir.
- **XDG isolation when config needed:** `env['XDG_*_HOME'] = str(tmp_path / 'xdg/...')` + `os.symlink(os.getcwd(), scratch / 'cfg' / 'nvim')` — matches pattern from `test_lint_missing_binary.py`.
- **`vim.system` capture closure:**
  ```lua
  local captured
  vim.system = function(cmd, opts, cb)
    captured = cmd
    local handle = { _closed = false }
    function handle:is_closing() return self._closed end
    function handle:kill() self._closed = true end
    function handle:wait() return { code = 0, stdout = '', stderr = '' } end
    if cb then vim.schedule(function() cb({ code = 0 }) end) end
    return handle
  end
  ```
- **`package.loaded` stubs:** replace modules before `require` runs. Pattern: `package.loaded['foo.bar'] = { fn = function() return stub end }`.
- **Tmux-socket isolation:** `_make_tmux_wrapper(socket)` shim + `env['PATH']` prepended — used for tests needing a live tmux server without polluting the user's sessions.
- **Output back to pytest:** `io.open('{out_path}', 'w'):write(vim.inspect(x))` → pytest reads the file.
- **Stylua formatting:** column_width=100, multi-line long calls / long table entries. Parent session fixes lint on CI failures.

## 3. Execution order (biggest-ROI first)

1. 32.4 §4 tmux+claude (8 tests) — highest user-surface
2. 32.2 §1 core editing (6 tests) — low-risk mechanical
3. 32.6 §6 remote (6 tests) — stub-heavy, patterns proven
4. 32.9 §9 SP1 cockpit (6 tests) — extends existing harness
5. 32.10 §13 hub + §14 parallel (3 tests)
6. 32.8 §8 idle alerts (3 tests)
7. 32.5 §5 multi-project claude (2 tests)
8. 32.3 §2+§3 macro-nudge + clipboard (3 tests)
9. 32.1 §0 pre-flight (3 tests)
10. 32.7 §7 health (2 tests)

Push + CI batching: group adjacent sections (e.g. 32.4+32.2 → push+CI, 32.6+32.9 → push+CI, etc.) to amortize the ~2 min CI round-trip.

## 4. Terminal state

- ~42 new `test_*` functions across ~10 new `tests/integration/test_*.py` files
- `docs/manual-tests.md` rows tagged `(CI-covered)` for every converted row
- Parent todo #32 + all children 32.1–32.10 closed
- Manual-tests list shrinks from ~75 rows to ~33 (10 MAN + 6 PART + 17 pre-existing-CI-tagged)
- CI green on main

## 5. Out of scope

- Re-enabling `test_lsp_format.py` (currently SKIPPED; separate debt).
- Converting any MAN row (by definition non-automatable).
- Deleting rows from manual-tests.md — keep them tagged so the checklist shows what the tests verify.
- Refactoring existing integration tests.

## 6. Rollout

Sequential push+CI cycles. Each push = 1-3 section-sized commits. On lint fail, parent fixes stylua formatting + re-pushes (pattern established in SP1/SP2/SP3/SP4 batches).
