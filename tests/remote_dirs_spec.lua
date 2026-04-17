-- tests/remote_dirs_spec.lua
describe('remote.dirs', function()
  local dirs

  before_each(function()
    package.loaded['remote.dirs'] = nil
    dirs = require('remote.dirs')
  end)

  it('_is_stale returns true when cache older than TTL', function()
    local now = 1000000
    local old = now - 8 * 86400 -- 8 days ago, TTL = 7d
    assert.is_true(dirs._is_stale({ fetched_at = old }, now))
    assert.is_false(dirs._is_stale({ fetched_at = now - 86400 }, now))
  end)

  it('_build_find_cmd builds the expected ssh find command', function()
    local cmd = dirs._build_find_cmd('myhost')
    assert.are.same({
      'ssh',
      'myhost',
      [[find ~ -type d -maxdepth 6 -not -path '*/.*' -not -path '*/node_modules/*' 2>/dev/null]],
    }, cmd)
  end)
end)
