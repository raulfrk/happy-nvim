-- tests/remote_hosts_spec.lua
describe('remote.hosts', function()
  local hosts

  before_each(function()
    package.loaded['remote.hosts'] = nil
    hosts = require('remote.hosts')
  end)

  it('_score applies exp decay over days', function()
    local now = 1000000
    -- 10 visits, last_used = now → score ≈ 10
    assert.is_true(math.abs(hosts._score({ visits = 10, last_used = now }, now) - 10) < 0.01)
    -- 10 visits, 14 days ago → score ≈ 10/e ≈ 3.68
    local fourteen_days = 14 * 86400
    local score = hosts._score({ visits = 10, last_used = now - fourteen_days }, now)
    assert.is_true(score < 4 and score > 3)
  end)

  it('_merge merges frecency DB with ssh_config hosts (DB wins on rank, config adds unknown)', function()
    local db = { alpha = { visits = 5, last_used = 1000 } }
    local config = { 'alpha', 'beta', 'gamma' }
    local merged = hosts._merge(db, config, 2000)
    assert.are.equal(3, #merged)
    -- alpha first (highest score)
    assert.are.equal('alpha', merged[1].host)
    assert.is_true(merged[1].score > 0)
    -- beta + gamma have 0 score
    assert.are.equal(0, merged[2].score)
  end)
end)
