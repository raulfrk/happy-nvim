-- lua/tmux/_popup.lua — shared async `tmux display-popup` wrapper.
--
-- Both lua/tmux/popup.lua (lazygit/btop/scratch) and
-- lua/tmux/claude_popup.lua (per-project Claude attach) need the same
-- pattern: spawn `tmux display-popup -E <cmd>` asynchronously so nvim's
-- event loop stays live while the user is inside the popup. Blocking
-- with vim.system():wait() freezes timers (idle watcher, macro-nudge,
-- LSP) for the popup's full lifetime — see commit ebf0846 for the
-- root-cause story.
local M = {}

--- Spawn `cmd` inside a tmux display-popup sized w×h; on_exit runs
--- when the popup subprocess terminates (user detach or cmd exit).
--- All args to vim.system are the async callback form — main thread
--- returns immediately.
---
--- @param w string              width (e.g. '80%', '60')
--- @param h string              height
--- @param cmd string            shell command to run inside the popup
--- @param on_exit fun()|nil     optional callback on popup close
function M.open(w, h, cmd, on_exit)
  local cb = on_exit and vim.schedule_wrap(on_exit) or function() end
  vim.system({ 'tmux', 'display-popup', '-E', '-w', w, '-h', h, cmd }, { text = true }, cb)
end

return M
