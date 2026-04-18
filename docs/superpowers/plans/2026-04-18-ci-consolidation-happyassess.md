# CI Consolidation + `:HappyAssess` + Plugin Cache Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Simplify CI from six parallel jobs to a single `assess` matrix that already covers every layer, add a `:HappyAssess` nvim user command that runs `scripts/assess.sh` async and streams output into a scratch buffer, and cache `~/.local/share/nvim/lazy` so cold-runner plugin clones drop from ~30s to ~3s.

**Architecture:** The assess matrix already runs every layer (shell-syntax, python-syntax, init-bootstrap, plenary, integration, checkhealth) — keeping lint/test/startup/health/integration as separate jobs duplicates work. We drop them; assess becomes the sole gate. `:HappyAssess` is a new `lua/happy/assess.lua` module that spawns `scripts/assess.sh` via `vim.system` with `stdout` streaming into an auto-created scratch buffer; users `<CR>` through or `:bd` to close. Caching uses `actions/cache@v4` keyed on `lazy-lock.json` hash (or fallback to branch name when absent).

**Tech Stack:** Lua 5.1, Bash 5, GitHub Actions, `actions/cache@v4`. No new dependencies.

---

## File Structure

```
lua/happy/assess.lua         # NEW — :HappyAssess user cmd + scratch buffer stream
init.lua                     # MODIFIED — require('happy.assess').setup() in VimEnter bootstrap
.github/workflows/ci.yml     # MODIFIED — drop 5 redundant jobs, cache Lazy dir
README.md                    # MODIFIED — add :HappyAssess to keymap reference (short note)
```

Three independent pieces. Each commits separately.

---

## Task 1: `lua/happy/assess.lua` + `:HappyAssess` user command

**Files:**
- Create: `lua/happy/assess.lua`
- Modify: `init.lua`

**Context:** `bash scripts/assess.sh` works fine from a shell but contributors often want to run it from inside nvim after edits. The command spawns the script, streams stdout + stderr line-by-line into a new scratch buffer, and prints the final exit-code summary. The buffer is a regular `bufhidden=wipe` scratch so `:bd` tidies it. While running, we set `buftype=nofile` and set a statusline-visible `b:assess_running` marker (optional polish).

`vim.system` in nvim 0.11 supports `stdout = function(err, chunk) end` callbacks. Each chunk is a string (may contain multiple newlines). We buffer partial lines, split on `\n`, append complete lines via `vim.schedule` (required because `vim.system` callbacks run off the main loop).

- [ ] **Step 1: Write the module**

Create `/home/raul/worktrees/happy-nvim/feat-v1-implementation/lua/happy/assess.lua`:

```lua
-- lua/happy/assess.lua — :HappyAssess user command.
-- Spawns scripts/assess.sh; streams stdout+stderr into a scratch buffer.
local M = {}

local function open_buffer()
  vim.cmd('new')
  local buf = vim.api.nvim_get_current_buf()
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].swapfile = false
  vim.api.nvim_buf_set_name(buf, 'happy-assess')
  vim.bo[buf].filetype = 'log'
  return buf
end

local function append_line(buf, line)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  -- Replace the first empty line produced at buffer creation on first append
  local count = vim.api.nvim_buf_line_count(buf)
  if count == 1 and vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] == '' then
    vim.api.nvim_buf_set_lines(buf, 0, 1, false, { line })
  else
    vim.api.nvim_buf_set_lines(buf, -1, -1, false, { line })
  end
  -- Follow tail: move cursor in any window showing this buffer
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(win) == buf then
      vim.api.nvim_win_set_cursor(win, { vim.api.nvim_buf_line_count(buf), 0 })
    end
  end
end

function M.run()
  local repo_root = vim.fn.getcwd()
  local script = repo_root .. '/scripts/assess.sh'
  if vim.fn.filereadable(script) ~= 1 then
    vim.notify(
      'happy-assess: scripts/assess.sh not found under cwd ' .. repo_root,
      vim.log.levels.ERROR
    )
    return
  end
  local buf = open_buffer()
  local tail_buf = ''

  local function on_chunk(_, chunk)
    if chunk == nil or chunk == '' then
      return
    end
    tail_buf = tail_buf .. chunk
    -- Emit complete lines; keep the trailing partial line for next chunk
    local lines = {}
    local start = 1
    while true do
      local nl = tail_buf:find('\n', start, true)
      if not nl then
        break
      end
      table.insert(lines, tail_buf:sub(start, nl - 1))
      start = nl + 1
    end
    tail_buf = tail_buf:sub(start)
    if #lines > 0 then
      vim.schedule(function()
        for _, line in ipairs(lines) do
          append_line(buf, line)
        end
      end)
    end
  end

  vim.system({ 'bash', script }, {
    cwd = repo_root,
    text = true,
    stdout = on_chunk,
    stderr = on_chunk,
  }, function(res)
    vim.schedule(function()
      if tail_buf ~= '' then
        append_line(buf, tail_buf)
      end
      append_line(buf, '')
      append_line(
        buf,
        string.format(':HappyAssess finished (exit code %d)', res.code or -1)
      )
    end)
  end)
end

function M.setup()
  vim.api.nvim_create_user_command(
    'HappyAssess',
    function()
      M.run()
    end,
    { desc = 'Run scripts/assess.sh and stream output into a scratch buffer' }
  )
end

return M
```

- [ ] **Step 2: Wire into `init.lua` bootstrap**

Find the module-bootstrap list in `init.lua`:

```lua
  for _, mod in ipairs({ 'coach', 'clipboard', 'tmux', 'remote' }) do
    local ok, m = pcall(require, mod)
    ...
  end
```

Extend the list to include `'happy.assess'`:

```lua
  for _, mod in ipairs({ 'coach', 'clipboard', 'tmux', 'remote', 'happy.assess' }) do
    local ok, m = pcall(require, mod)
    if ok and type(m.setup) == 'function' then
      local ok_setup, err = pcall(m.setup)
      if not ok_setup then
        vim.notify('happy-nvim: ' .. mod .. '.setup failed: ' .. err, vim.log.levels.WARN)
      end
    end
  end
```

- [ ] **Step 3: Stylua + smoke**

```bash
cd /home/raul/worktrees/happy-nvim/feat-v1-implementation
export STYLUA=/tmp/npmcache/_npx/2d7ba7d0047acad9/node_modules/.bin/stylua
$STYLUA lua/happy/assess.lua init.lua
$STYLUA --check lua/happy/assess.lua init.lua && echo STYLUA_OK
```

Smoke — start nvim headlessly, run `:HappyAssess`, verify the user command is registered (we can't watch the streaming output headlessly, but we can assert the command exists):

```bash
XDG_DATA_HOME="$PWD/.tests" XDG_CONFIG_HOME="$PWD/.tests/config" \
  XDG_CACHE_HOME="$PWD/.tests/cache" XDG_STATE_HOME="$PWD/.tests/state" \
  nvim --headless \
  -c "lua vim.fn.writefile({tostring(vim.api.nvim_get_commands({}).HappyAssess ~= nil)}, '/tmp/has-cmd')" \
  -c 'qa!' && cat /tmp/has-cmd
```

Expected output: `true`.

- [ ] **Step 4: Commit**

```bash
git add lua/happy/assess.lua init.lua
git commit -m "feat(assess): :HappyAssess user command streams assess.sh output

New lua/happy/assess.lua. :HappyAssess opens a scratch buffer
(buftype=nofile, bufhidden=wipe, ft=log), spawns scripts/assess.sh
via vim.system, and streams stdout+stderr line-by-line as they
arrive (complete lines only — partial trailing text is buffered
until the next chunk). Final line reports the exit code.

Setup hooked into init.lua's VimEnter module bootstrap. :bd closes
the buffer; users can re-run via :HappyAssess any time."
```

---

## Task 2: Consolidate CI — drop 5 redundant jobs

**Files:**
- Modify: `.github/workflows/ci.yml`

**Context:** The current workflow has six jobs: `lint`, `test`, `startup`, `health`, `integration`, `assess`. Every layer in the first five is already covered by `assess.sh`:

| Individual job | Covered by assess layer |
|---|---|
| lint (stylua + selene) | shell-syntax + python-syntax (partial); stylua/selene layer added below |
| test (plenary) | plenary |
| startup (headless qa!) | init-bootstrap |
| health (checkhealth) | checkhealth |
| integration (pytest) | integration |

The only gap is lint: `assess.sh` doesn't currently run stylua/selene. We close that gap by adding a `lint` layer to `assess.sh` as part of this task, then drop the individual jobs.

- [ ] **Step 1: Add `layer_lint` to `scripts/assess.sh`**

Open `scripts/assess.sh`. Find the `run_layer` invocations near the end:

```bash
run_layer 'shell-syntax'      layer_shell_syntax
run_layer 'python-syntax'     layer_python_syntax
run_layer 'init-bootstrap'    layer_init_bootstrap
run_layer 'plenary'           layer_plenary
run_layer 'integration'       layer_integration
run_layer 'checkhealth'       layer_checkhealth
```

Add a new `layer_lint` function above the `layer_shell_syntax` definition:

```bash

# Layer 0: stylua + selene (fastest lint); gracefully skip if tools missing
layer_lint() {
  local rc=0
  if command -v stylua >/dev/null 2>&1; then
    stylua --check . || rc=1
  else
    echo 'layer_lint: stylua not on $PATH — skipping format check'
  fi
  if command -v selene >/dev/null 2>&1; then
    selene . || rc=1
  else
    echo 'layer_lint: selene not on $PATH — skipping static analysis'
  fi
  return $rc
}
```

Then add the new invocation to the run-layer list, FIRST:

```bash
run_layer 'lint'              layer_lint
run_layer 'shell-syntax'      layer_shell_syntax
run_layer 'python-syntax'     layer_python_syntax
run_layer 'init-bootstrap'    layer_init_bootstrap
run_layer 'plenary'           layer_plenary
run_layer 'integration'       layer_integration
run_layer 'checkhealth'       layer_checkhealth
```

- [ ] **Step 2: Rewrite `.github/workflows/ci.yml` to just the assess matrix**

Replace the ENTIRE contents of `.github/workflows/ci.yml` with:

```yaml
name: ci
on:
  push:
    branches: [main]
  pull_request:

jobs:
  assess:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        nvim: [stable, nightly]
    steps:
      - uses: actions/checkout@v4

      - name: Install apt deps (tmux, pytest, ripgrep, fd, mosh)
        run: |
          sudo apt-get update
          sudo apt-get install -y tmux python3-pytest ripgrep fd-find mosh
          # Debian ships fd-find as 'fdfind'; telescope expects 'fd'
          mkdir -p "$HOME/.local/bin" && ln -sf "$(which fdfind)" "$HOME/.local/bin/fd"
          echo "$HOME/.local/bin" >> "$GITHUB_PATH"

      - name: Install tree-sitter CLI
        run: sudo npm install -g tree-sitter-cli && tree-sitter --version

      - name: Install stylua + selene
        uses: cargo-bins/cargo-binstall@main
      - run: cargo binstall -y stylua selene

      - uses: rhysd/action-setup-vim@v1
        with:
          neovim: true
          version: ${{ matrix.nvim }}

      - name: Cache lazy.nvim plugin directory
        uses: actions/cache@v4
        with:
          path: .tests/nvim/lazy
          key: lazy-${{ runner.os }}-${{ matrix.nvim }}-${{ hashFiles('lazy-lock.json', 'lua/plugins/**') }}
          restore-keys: |
            lazy-${{ runner.os }}-${{ matrix.nvim }}-

      - name: Run assess.sh (full feature acceptance)
        timeout-minutes: 15
        run: bash scripts/assess.sh
```

Changes vs the pre-consolidation file:

- Drops `lint`, `test`, `startup`, `health`, `integration` jobs (every layer subsumed by assess).
- Installs every dep the assess layers might need in ONE step.
- Adds an `actions/cache@v4` step keyed on `lazy-lock.json` + plugin specs. First run misses; subsequent runs restore `.tests/nvim/lazy/` directly (saves ~25s of Lazy sync per matrix row).
- `timeout-minutes: 15` — generous ceiling; normal run is ~1-2 min on a cache hit.

- [ ] **Step 3: Validate YAML + run assess locally to confirm the lint layer passes**

```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/ci.yml'))" && echo YAML_OK
bash -n scripts/assess.sh && echo SYNTAX_OK
bash scripts/assess.sh 2>&1 | tail -15
```

Expected: `YAML_OK`, `SYNTAX_OK`, and ALL LAYERS PASS (including the new `lint` layer — which may skip both checks if stylua/selene aren't installed in the sandbox; that's acceptable, just logs the skip and returns 0).

If local stylua/selene ARE installed and the code has stale formatting, the `lint` layer will fail. Run `$STYLUA .` to clean up, then re-run.

- [ ] **Step 4: Commit**

```bash
git add scripts/assess.sh .github/workflows/ci.yml
git commit -m "ci: consolidate — assess matrix as sole gate + lint layer

Every previous job (lint/test/startup/health/integration) was
already a subset of scripts/assess.sh. Kept only the assess matrix
(stable+nightly nvim). One install step for all deps; a new
actions/cache@v4 step caches .tests/nvim/lazy keyed on
lazy-lock.json + lua/plugins/**, dropping Lazy sync from ~30s
cold to ~3s warm.

assess.sh grew a 'lint' layer (stylua --check + selene) that
gracefully skips when the tools are missing. Order is now:
lint → shell-syntax → python-syntax → init-bootstrap →
plenary → integration → checkhealth."
```

---

## Task 3: README — `:HappyAssess` note

**Files:**
- Modify: `README.md`

**Context:** Document `:HappyAssess` in the "Running tests" section so users discover it.

- [ ] **Step 1: Append to the existing "### 3. One-button assessment" subsection**

Find in `README.md`:

```markdown
### 3. One-button assessment — `scripts/assess.sh`
```

Add AFTER the existing code-block example (the one showing the LAYER STATUS DURATION table), before `### 4. Manual checklist`:

```markdown

Inside nvim:

```vim
:HappyAssess
```

Opens a scratch buffer streaming `assess.sh` output line-by-line. `:bd`
to close when done. Useful for quick verification after edits without
leaving the editor.
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs(readme): :HappyAssess cmd in Running tests section

One-paragraph addition to '3. One-button assessment' subsection
mentioning the nvim user command + :bd to close. Full behavior
lives in lua/happy/assess.lua."
```

---

## Task 4: Manual test additions

**Files:**
- Modify: `docs/manual-tests.md`

- [ ] **Step 1: Add row under section 0 (pre-flight)**

Find "0. Pre-flight" in `docs/manual-tests.md`. Append:

```markdown
- [ ] Inside nvim `:HappyAssess` opens a scratch buffer w/ live output; final line shows `:HappyAssess finished (exit code 0)`
```

- [ ] **Step 2: Commit**

```bash
git add docs/manual-tests.md
git commit -m "docs(manual): :HappyAssess smoke row"
```

---

## Task 5: Push + verify green CI

**Files:** none.

- [ ] **Step 1: FF + push**

```bash
cd /home/raul/projects/happy-nvim
git checkout main
git merge --ff-only feat/v1-implementation
git push git@github.com:raulfrk/happy-nvim.git main:main
```

- [ ] **Step 2: Poll + verify**

```bash
sleep 6
RUN_ID=$(gh api repos/raulfrk/happy-nvim/actions/runs --jq '.workflow_runs[0].id')
echo "$RUN_ID"
while true; do
  s=$(gh api "repos/raulfrk/happy-nvim/actions/runs/$RUN_ID" --jq '"\(.status)|\(.conclusion)"')
  echo "$(date +%H:%M:%S) $s"
  case "$s" in completed*) break;; esac
  sleep 60
done
gh api "repos/raulfrk/happy-nvim/actions/runs/$RUN_ID/jobs" --jq '.jobs[] | "\(.name): \(.conclusion)"'
```

Expected: only TWO jobs (previously ten) — `assess (stable)` and `assess (nightly)` — both `success`.

If the cache step errors on first run (`no cache key match`), that's a miss not a failure; the step logs a message and continues. Subsequent runs should show `cache hit, size N MB` in the step log.

If `lint` layer fails on CI but passed locally: check that `cargo binstall stylua selene` succeeded (sometimes the cargo-bins action races). Add `- run: stylua --version && selene --version` before the assess step to debug.

- [ ] **Step 3: Close source todos**

```
todo_complete 5.12 5.13 5.15
```

---

## Manual Test Additions

Task 4 adds the single manual-tests row for `:HappyAssess` pre-flight check. Tasks 1, 2, 3 have no further manual-test impact — they're contributor-facing process changes; `bash scripts/assess.sh` still works identically from the shell.

---

## Self-Review

**1. Spec coverage:**

| Todo | Task |
|---|---|
| #5.12 :HappyAssess cmd | Task 1 |
| #5.13 CI consolidation | Task 2 |
| #5.15 CI plugin cache | Task 2 Step 2 (`actions/cache@v4` step in the consolidated job) |

All three bundled into Task 2's CI rewrite because they touch the same file — splitting the cache step into its own task would mean two commits to the same YAML for no isolation benefit.

**2. Placeholder scan:** no TBDs. Every code block complete.

**3. Type consistency:**
- `vim.system` callback signature matches 0.11 docs — `function(err, chunk)` for stdout/stderr, `function(result)` for completion.
- `happy.assess` module name consistent across `lua/happy/assess.lua`, `init.lua` bootstrap list, `:HappyAssess` command, README mention.
- `layer_lint` function naming matches the existing `layer_*` convention in `assess.sh`.
- Cache key `lazy-${{ runner.os }}-${{ matrix.nvim }}-${{ hashFiles('lazy-lock.json', 'lua/plugins/**') }}` — `lazy-lock.json` may not exist (we removed it in an earlier commit and haven't re-added); `hashFiles` treats missing files as empty strings, so the key still varies with `lua/plugins/**` content. Restore key `lazy-${{ runner.os }}-${{ matrix.nvim }}-` matches any prior lock state.
