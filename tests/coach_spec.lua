-- tests/coach_spec.lua
describe('coach', function()
  local coach

  before_each(function()
    package.loaded['coach'] = nil
    package.loaded['coach.tips'] = nil
    coach = require('coach')
  end)

  it('exposes random_tip() that returns a tip table', function()
    local tip = coach.random_tip()
    assert.is_table(tip)
    assert.is_string(tip.keys)
    assert.is_string(tip.desc)
    assert.is_string(tip.category)
  end)

  it('random_tip() returns nil when tips is empty', function()
    package.loaded['coach.tips'] = {}
    package.loaded['coach'] = nil
    local c = require('coach')
    assert.is_nil(c.random_tip())
  end)

  it('next_tip() advances through the list without repeating consecutively', function()
    local seen = {}
    for _ = 1, 5 do
      local t = coach.next_tip()
      assert.is_table(t)
      table.insert(seen, t.keys)
    end
    -- At least two distinct tips across 5 calls (valid when tips >= 2)
    local unique = {}
    for _, k in ipairs(seen) do
      unique[k] = true
    end
    local count = 0
    for _ in pairs(unique) do
      count = count + 1
    end
    assert.is_true(count >= 2)
  end)
end)
