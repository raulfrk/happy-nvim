-- init.lua — happy-nvim entry point
-- Order matters: options before keymaps (leader), autocmds, colors, then lazy.

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
