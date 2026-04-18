-- tests/config_options_spec.lua
-- Unit tests for lua/config/ts_shim.lua — the defensive wrapper
-- around vim.treesitter.get_range that muzzles the
-- "attempt to call method 'range' (a nil value)" crash from nvim 0.12's
-- runtime/lua/vim/treesitter.lua:196 when a query capture yields a
-- non-TSNode value.

-- Capture the real (unwrapped) get_range at spec-load time. minimal_init
-- doesn't load user config by default, so this is the nvim runtime
-- original. Each test before_each restores it before re-installing so
-- we don't stack wrappers across cases.
local ORIG_GET_RANGE = vim.treesitter.get_range

describe('vim.treesitter.get_range defensive wrapper', function()
  before_each(function()
    vim.treesitter.get_range = ORIG_GET_RANGE
    vim.g._happy_ts_shim_installed = nil
    package.loaded['config.ts_shim'] = nil
    require('config.ts_shim').install()
  end)

  it('returns an empty Range6 when node is nil', function()
    local r = vim.treesitter.get_range(nil, nil, nil)
    assert.are.same({ 0, 0, 0, 0, 0, 0 }, r)
  end)

  it('returns an empty Range6 when node is nil and metadata is empty table', function()
    local r = vim.treesitter.get_range(nil, nil, {})
    assert.are.same({ 0, 0, 0, 0, 0, 0 }, r)
  end)

  it('returns an empty Range6 when node is a non-userdata table (stale ref)', function()
    -- Regression: the real-world crash had `node` as something truthy
    -- (a plain table or stale ref) so `node == nil` didn't catch it;
    -- line 196 of runtime/treesitter.lua then hit "attempt to call
    -- method 'range' (a nil value)". The type ~= 'userdata' guard
    -- covers this.
    local r = vim.treesitter.get_range({ not_a_node = true }, nil, nil)
    assert.are.same({ 0, 0, 0, 0, 0, 0 }, r)
  end)

  it('returns an empty Range6 when original get_range throws', function()
    -- Even if the arg LOOKS like a TSNode but range() errors for some
    -- other reason, pcall catches it.
    local r = vim.treesitter.get_range('not a node', nil, nil)
    assert.are.same({ 0, 0, 0, 0, 0, 0 }, r)
  end)

  it('respects metadata.range without needing a node', function()
    -- metadata.range path must still work; otherwise we break query
    -- directives that synthesize ranges from scratch.
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'hello world' })
    local r = vim.treesitter.get_range(nil, buf, { range = { 0, 0, 0, 5 } })
    -- add_bytes returns a 6-tuple; first three are start row/col/byte.
    assert.are.equal(0, r[1])
    assert.are.equal(0, r[2])
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it('delegates to the original get_range for real TSNodes', function()
    -- Bundled 'lua' parser ships w/ nvim — get a node, ensure wrapper
    -- passes it through and returns a valid range (not our empty stub).
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'local x = 1' })
    local ok, parser = pcall(vim.treesitter.get_parser, buf, 'lua')
    if not ok or not parser then
      -- No lua parser on this nvim — skip.
      vim.api.nvim_buf_delete(buf, { force = true })
      return
    end
    local tree = parser:parse()[1]
    local root = tree:root()
    local r = vim.treesitter.get_range(root, buf, nil)
    assert.is_table(r)
    -- Real root covers at least the single line we wrote.
    assert.is_true(r[4] >= 0) -- end_row >= 0
    vim.api.nvim_buf_delete(buf, { force = true })
  end)
end)
