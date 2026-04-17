-- lua/happy/health.lua
local M = {}

function M.check()
  vim.health.start('happy-nvim')
  vim.health.ok('Health provider registered. Probes added in later tasks.')
end

return M
