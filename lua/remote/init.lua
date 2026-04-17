-- lua/remote/init.lua
local M = {}

function M.setup()
  require('remote.hosts').setup()
  require('remote.dirs').setup()
  require('remote.browse').setup()
  require('remote.grep').setup()
end

return M
