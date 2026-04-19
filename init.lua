-- init.lua — happy-nvim entry point
-- Order matters: options before keymaps (leader), autocmds, colors, then lazy.

-- Minimum nvim version check. Several locked plugins (noice, nui, mason,
-- gitsigns) use vim.o.winborder (introduced in 0.11) or the new
-- vim.lsp.config API. Fail fast with a helpful message instead of a
-- plugin stack trace.
if vim.fn.has('nvim-0.11') == 0 then
  vim.api.nvim_echo({
    { 'happy-nvim requires Neovim >= 0.11\n', 'ErrorMsg' },
    { 'You are running ' .. tostring(vim.version()) .. '.\n', 'WarningMsg' },
    { 'Upgrade: https://github.com/neovim/neovim/blob/master/INSTALL.md\n', 'Normal' },
  }, true, {})
  return
end

local function try_require(mod)
  local ok, err = pcall(require, mod)
  if not ok then
    vim.notify('happy-nvim: failed to load ' .. mod .. ': ' .. err, vim.log.levels.ERROR)
  end
end

try_require('config.options')
try_require('config.keymaps')
try_require('config.autocmds')
try_require('config.colors')
try_require('config.lazy')

-- Modules load after lazy so they can use telescope etc.
-- VimEnter fires reliably after lazy bootstraps; LazyDone race-prone.
local function setup_happy_modules()
  for _, mod in ipairs({ 'coach', 'clipboard', 'tmux', 'remote', 'happy.assess', 'happy.projects' }) do
    local ok, m = pcall(require, mod)
    if ok and type(m.setup) == 'function' then
      local ok_setup, err = pcall(m.setup)
      if not ok_setup then
        vim.notify('happy-nvim: ' .. mod .. '.setup failed: ' .. err, vim.log.levels.WARN)
      end
    end
  end
  -- Idle watcher polls cc-* tmux sessions for output-stable; only useful
  -- when nvim is inside tmux.
  if vim.env.TMUX and vim.env.TMUX ~= '' then
    local ok, idle = pcall(require, 'tmux.idle')
    if ok then
      idle.watch_all()
    end
  end
end

if vim.v.vim_did_enter == 1 then
  setup_happy_modules()
else
  vim.api.nvim_create_autocmd('VimEnter', {
    once = true,
    callback = setup_happy_modules,
  })
end
