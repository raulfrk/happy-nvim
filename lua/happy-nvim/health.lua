-- `:checkhealth happy-nvim` alias. The canonical implementation lives at
-- `lua/happy/health.lua` (Lua namespace `happy`); this shim lets
-- `:checkhealth happy-nvim` find the same health module when users type
-- the repo name instead of the Lua namespace.
return require('happy.health')
