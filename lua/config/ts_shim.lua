-- lua/config/ts_shim.lua
-- Defensive wrapper around vim.treesitter.get_range.
--
-- Root cause (nvim 0.12.1, 2026-04-18): runtime/lua/vim/treesitter.lua:196
-- unconditionally calls `node:range(true)` after metadata.range / .offset
-- fallthrough. With nvim-treesitter master's injection queries on certain
-- languages, a capture can yield a value where `node.range` is nil —
-- stale table, string, or a partially-initialised object — and crash
-- the async parse loop (languagetree.lua:215 inside tcall):
--
--   languagetree.lua:596: tcall(parse, ...)
--   languagetree.lua:215: local r = { f(...) }
--   treesitter.lua:196: return { node:range(true) }
--     -> attempt to call method 'range' (a nil value)
--
-- Type-check AND pcall the original: if the arg isn't a TSNode
-- userdata, or the call errors for any reason, return an empty Range6
-- so the highlighter silently skips the capture. Upstream can restore
-- the direct call once the injection query contract is tightened; this
-- wrapper is a no-op in the happy path.
--
-- Called twice: from lua/config/options.lua at startup (prod), and from
-- the scratch config in tests/integration/test_telescope.py (CI). Keep
-- the single source of truth here.

local M = {}

local EMPTY_RANGE = { 0, 0, 0, 0, 0, 0 }

--- Install the get_range wrapper on `vim.treesitter`. Idempotent: the
--- wrapper captures `vim.treesitter.get_range` at install time, so a
--- second install layers another wrapper around the first — harmless
--- but wasteful. The `_happy_ts_shim_installed` flag short-circuits.
function M.install()
  if vim.g._happy_ts_shim_installed then
    return
  end
  local ts = vim.treesitter
  local orig = ts.get_range
  ts.get_range = function(node, source, metadata)
    if metadata and metadata.range then
      if source == nil then
        return EMPTY_RANGE
      end
      local ok, r = pcall(ts._range.add_bytes, source, metadata.range)
      return ok and r or EMPTY_RANGE
    end
    -- TSNodes are userdata; anything else (nil, table, string) would
    -- crash line 196 of runtime/treesitter.lua on node:range(true).
    if type(node) ~= 'userdata' then
      return EMPTY_RANGE
    end
    local ok, r = pcall(orig, node, source, metadata)
    return ok and r or EMPTY_RANGE
  end
  vim.g._happy_ts_shim_installed = true
end

return M
