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
vim.api.nvim_create_autocmd('User', {
  pattern = 'LazyDone',
  once = true,
  callback = function()
    local ok, coach = pcall(require, 'coach')
    if ok then
      coach.setup()
    end
    local ok_c, clipboard = pcall(require, 'clipboard')
    if ok_c then
      clipboard.setup()
    end
    local ok_t, tmux = pcall(require, 'tmux')
    if ok_t then
      tmux.setup()
    end
    local ok_r, remote = pcall(require, 'remote')
    if ok_r then
      remote.setup()
    end
  end,
})
