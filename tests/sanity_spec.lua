-- tests/sanity_spec.lua
describe('test harness', function()
  it('runs a trivially true assertion', function()
    assert.are.equal(1 + 1, 2)
  end)

  it('can require lua modules from the repo root', function()
    -- lua/happy/_probe.lua does not exist yet; this just proves the RTP is wired
    local ok = pcall(require, 'plenary.path')
    assert.is_true(ok)
  end)
end)
