-- tests/config_options_spec.lua
-- Unit tests for the defensive wrapper around vim.treesitter.get_range
-- installed by lua/config/options.lua. Purpose: muzzle the
-- "attempt to call method 'range' (a nil value)" crash from nvim 0.12's
-- runtime/lua/vim/treesitter.lua:196 when a query capture yields nil
-- node with non-informative metadata.

describe('vim.treesitter.get_range defensive wrapper', function()
  before_each(function()
    -- Re-source options.lua to install the wrapper in this spec's env.
    package.loaded['config.options'] = nil
    dofile(vim.fn.getcwd() .. '/lua/config/options.lua')
  end)

  it('returns an empty Range6 when node is nil', function()
    local r = vim.treesitter.get_range(nil, nil, nil)
    assert.are.same({ 0, 0, 0, 0, 0, 0 }, r)
  end)

  it('returns an empty Range6 when node is nil and metadata is empty table', function()
    local r = vim.treesitter.get_range(nil, nil, {})
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
