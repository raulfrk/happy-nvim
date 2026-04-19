# Manual Tests Audit — 2026-04-20

Walks every row in `docs/manual-tests.md` and categorizes:

- **[CI]** — already covered by an integration/plenary test; no action needed beyond keeping the row tagged `(CI-covered)`
- **[AUTO]** — writable as a headless-nvim integration test (no real claude/ssh/host/browser needed); convert to shrink the checklist
- **[PART]** — data / build layer is testable; UX / visual layer stays manual
- **[MAN]** — genuinely manual: real terminal escape handling, nerd font glyphs, browser paste, real claude CLI state, real desktop notifications

Counts: **[CI] 24** · **[AUTO] 35** · **[PART] 6** · **[MAN] 10** (total 75 rows; some CI-covered rows live in sections 10/11/12 where every row maps to an existing test).

Priority for conversion (biggest wins):
1. Core editing §1 — 6 AUTO rows, low complexity
2. Tmux + Claude §4 — 9 AUTO rows; covers the most-used happy-nvim surface
3. Remote §6 — 6 AUTO/PART rows; stub-friendly via `remote.util.run`
4. SP1/SP2 cockpit §9/§13 — 7 AUTO rows; extends existing harness

Each AUTO entry below includes a one-line hint on the harness / stubs needed.

---

## §0. Pre-flight

| Row | Cat | Notes / harness |
|---|---|---|
| nvim --version 0.11+ | CI | `init-bootstrap` layer asserts |
| tmux -V 3.2+ | CI | `checkhealth` layer asserts |
| tree-sitter on $PATH | AUTO | assert `vim.fn.executable('tree-sitter') == 1` in headless |
| Nerd Font renders | MAN | visual glyph rendering — can't automate |
| $SHELL is zsh/bash | AUTO | assert `vim.env.SHELL` matches `/(zsh|bash)$/` |
| assess.sh ALL PASS | CI | this IS CI |
| :HappyAssess runs | AUTO | headless `:HappyAssess`, capture scratch buffer, assert last line `exit code 0` |

## §1. Core editing

| Row | Cat | Notes |
|---|---|---|
| .lua syntax colors | PART | TS query parse AUTO; visual colors MAN |
| .py LSP attach + ruff | CI | `test_lsp_format.py` (currently SKIPPED — reactivate as follow-up) |
| .lua stylua on save | AUTO | headless edit .lua, `:w`, assert buffer reformatted |
| <Space>fh harpoon list | AUTO | harpoon stub + telescope entry_maker capture |
| <Space>ff telescope | CI | `test_telescope.py` |
| harpoon persists | CI | tagged CI-covered |
| <Space>ha add marks | AUTO | drive keymap, assert harpoon2 list grew |
| <Space>h1/2/3 switch | AUTO | same harness |
| <Space>u undotree | AUTO | headless open, assert `&filetype == 'undotree'` in split |
| <Space>gs fugitive | AUTO | same pattern — assert fugitive buffer opened |

## §2. Macro-nudge

| Row | Cat | Notes |
|---|---|---|
| alpha dashboard tip | AUTO | headless boot cold, assert `buf_get_lines(alpha_buf)` contains `Tip:` |
| which-key popup | CI | `test_whichkey_menu.py` |
| <Space>? cheatsheet | CI | `test_coach.py` |
| hardtime jjjj warn | AUTO | feedkeys `jjjj`, capture `:messages` |
| precognition overlay | PART | `nvim_buf_get_extmarks` AUTO for AST-level; visual overlay MAN |

## §3. Clipboard

| Row | Cat | Notes |
|---|---|---|
| yank in mosh+tmux+nvim | MAN | real terminal chain |
| host Cmd+V paste | MAN | real browser clipboard |
| VM xclip | MAN | needs real DISPLAY |
| yank > 74KB notify | AUTO | stub `vim.base64.encode` or inject large regcontents; assert notify msg |

## §4. Tmux + Claude

| Row | Cat | Notes |
|---|---|---|
| C-h/j/k/l nav | CI | `test_tmux_nav.py` |
| <Space>cc pane spawn | CI | `test_multi_cc_no_op_fixed.py` covers session model |
| <Space>cf send file | AUTO | stub `send.send_to_claude`, assert payload starts `@<rel-path>` |
| <Space>cs selection | AUTO | same pattern, assert fenced block + line range header |
| <Space>ce diagnostics | AUTO | stub `vim.diagnostic.get`, assert `- ERROR:` bullet list |
| <Space>cp popup detach | CI | `test_claude_popup.py` |
| <Space>cp reattach | CI | same |
| <Space>cC pane respawn | AUTO | stub tmux kill-session + assert new-session called |
| <Space>cP popup respawn | AUTO | same |
| <Space>cl picker | PART | entry_maker AUTO; `✓/⟳/?` icon render MAN |
| <C-x> kill in picker | AUTO | picker `<C-x>` mapping + kill-session assertion |
| <Space>cn named | AUTO | feedkeys prompt, assert `tmux new-session -s cc-<name>` |
| <Space>ck confirm | CI | `test_claude_ck_no_loop.py` (UX batch) |
| :checkhealth claude section | AUTO | headless checkhealth, assert section header present |
| popup width override | CI | `test_claude_popup.py::setup applies width override` |
| Ctrl-C mid-reply preserves | MAN | real claude CLI interrupt behavior |
| popup convo persists | MAN | real claude CLI state |

## §5. Multi-project Claude

| Row | Cat | Notes |
|---|---|---|
| <Space>cc pane A opens cc-A | CI | `test_multi_cc_no_op_fixed.py` |
| <Space>cc pane B opens cc-B | CI | same |
| <Space>cf routes to A | AUTO | stub + assert `tmux send-keys -t <session-A>` |
| idle indicator ✓ | CI | `test_multiproject_idle.py` |
| working indicator ⟳ | CI | same |
| status-right badges | MAN | real tmux status bar |
| three projects in parallel | CI | `test_multiproject_idle.py::test_three_sessions_idle_independently` |
| wt-claude-provision | PART | script-run AUTO; real worktree context MAN |
| prewarm attach | AUTO | stub tmux has-session, assert attach-only path |
| wt-claude-cleanup | PART | same |

## §6. Remote (ssh/scp)

| Row | Cat | Notes |
|---|---|---|
| <Space>ss picker | CI | `test_remote_hosts.py` + `test_ss_empty_state.py` |
| Pick host → tmux split | AUTO | stub `vim.fn.executable('mosh')` + assert tmux new-window |
| <Space>sd dir picker | AUTO | stub `remote.util.run` + assert dir list |
| <Space>sB scp buffer | AUTO | assert `edit scp://...` invoked |
| binary refusal | AUTO | stub `file --mime` → `binary`, assert notify |
| <Space>sO override | AUTO | set override flag, assert scp edit |
| <Space>sg grep | CI | `test_remote_grep.py` |
| :HappyHostsPrune | AUTO | seed DB w/ stale entries + assert count returned |

## §7. Health

| Row | Cat | Notes |
|---|---|---|
| :checkhealth sections | AUTO | parse checkhealth buffer, assert section headers |
| no ERROR: lines | AUTO | same buffer, assert no line matches `^ERROR` |

## §8. Idle alerts

| Row | Cat | Notes |
|---|---|---|
| Telescope ft_to_lang clean | CI | tagged CI-covered |
| idle alert fires | CI | `test_idle_alert.py` |
| bell opt-in | AUTO | stub `io.stdout:write`, drive idle flip w/ `alert.bell=true`, assert `\a` emitted |
| desktop opt-in | PART | stub `notify-send` in PATH; assert called — but real OS notification delivery is MAN |
| cooldown dedup | AUTO | trigger 2 flips w/in cooldown, assert 1 notify |
| focus-skip | AUTO | stub `tmux display-message -p '#{pane_active}'`, assert suppressed |
| popup notif still fires | CI | `test_idle_alert_during_popup.py` |
| timer fires during ssh | CI | `test_remote_async_nonblocking.py` |
| idle over real ssh | MAN | real-host latency + timer interaction |

## §9. Multi-project cockpit (SP1)

| Row | Cat | Notes |
|---|---|---|
| <leader>P shows projects | AUTO | seed registry + drive picker, assert entry list |
| <C-a> path add | AUTO | picker action-key test |
| <C-a> host:path add | AUTO | same w/ remote parse path |
| remote pivot → sandboxed popup | CI | `test_remote_project_sandbox.py` |
| claude refuses ssh | MAN | real claude + real sandbox enforcement |
| claude refuses fs escape | MAN | same |
| <leader>Cc capture | CI | `test_capture_primitives.py` |
| <leader>Pp peek | AUTO | stub tmux capture-pane, assert scratch buffer |
| <leader>cc 2nd pane distinct | CI | `test_multi_cc_no_op_fixed.py` |
| :HappyWt* stream | AUTO | stub bash exec, assert scratch buffer streams |
| Lualine status | PART | `format_for_statusline` CI-covered (plenary); render MAN |
| <leader>Pa prompt | AUTO | stub `vim.ui.input`, assert registry.add called |

## §10. Bug batch 2026-04-19

| Row | Cat | Notes |
|---|---|---|
| :checkhealth happy-nvim | CI | verified by checkhealth layer in assess.sh |
| .lua without selene | CI | `test_lint_missing_binary.py` |
| :HappyLspInfo | CI | `test_happy_lsp_info.py` |

## §11. UX micro-batch 2026-04-19

| Row | Cat | Notes |
|---|---|---|
| <leader>ck confirm | CI | `test_claude_ck_no_loop.py` |
| precognition off by default | CI | `test_precognition_default_off.py` |
| cheatsheet coverage | CI | `test_coach_tips_coverage.py` |

## §12. Fast remote ops (SP3)

| Row | Cat | Notes |
|---|---|---|
| yank → host paste (real) | MAN | real browser clipboard |
| :HappyCheckClipboard payload | MAN | real terminal paste target |
| empty-state picker | CI | `test_ss_empty_state.py` |
| <leader>sc cmd runner | CI | `test_remote_cmd_runner.py` |
| <leader>sT tail | CI | `test_remote_tail.py` |
| <leader>sf find | CI | `test_remote_find.py` |

## §13. Quick-pivot hub (SP2)

| Row | Cat | Notes |
|---|---|---|
| <leader><leader> picker merges | AUTO | seed 3 sources, invoke `hub._merge_for_test`, assert mixed kinds |
| project pivot | CI | `happy_hub_sources_spec.lua` (plenary) |
| host pivot | AUTO | same harness + assert tmux new-window |
| session suppression | CI | same plenary spec |

## §14. Parallel claude (SP4)

| Row | Cat | Notes |
|---|---|---|
| <leader>cq popup | CI | `test_claude_scratch.py` |
| cc-<id> unaffected | AUTO | spawn cc-<id> + <leader>cq, assert both sessions exist |
| popup close kills | CI | same test (callback assertion) |
| remote sandbox cwd | CI | `test_claude_scratch.py::test_scratch_uses_sandbox_for_remote_project` |

---

## Recommended conversion sprint

If we want to shrink the manual list aggressively, one sprint of 1-2 days
turning the **35 AUTO rows** into pytest tests would drop the checklist
from ~75 rows to ~16 (MAN + PART only). Biggest ROI clusters:

1. **§1 Core editing (6 AUTO)** — low-risk, self-contained. Harness:
   headless `vim.cmd('edit <tmp>.lua')` + feedkeys + buffer assertions.
2. **§4 Tmux + Claude (9 AUTO)** — reuse the `_make_tmux_wrapper` shim
   pattern (SP1 tests). Highest-visibility surface.
3. **§9 SP1 cockpit (7 AUTO)** — extends `test_project_pivot.py`
   harness. Covers most user-visible cockpit flows.

## Residual MAN rows (10, can't be automated)

- Nerd Font glyph rendering (§0)
- Mosh+tmux+nvim yank → host browser paste (§3, §12)
- xclip on VM w/ DISPLAY (§3)
- Claude CLI mid-reply Ctrl-C preservation (§4)
- Claude CLI convo persistence across popup cycles (§4)
- tmux status-right badges render (§5)
- Idle notification over real ssh latency (§8)
- Real sandbox enforcement by claude runtime (§9 × 2)

These are the rows that genuinely need a human at a real terminal /
browser / host. Everything else is automatable.
