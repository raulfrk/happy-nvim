-- tests/health_spec.lua
describe('happy.health', function()
  it('exports a check() function', function()
    local health = require('happy.health')
    assert.is_function(health.check)
  end)
end)
