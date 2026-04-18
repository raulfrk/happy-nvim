-- tests/remote_util_spec.lua
-- Unit tests for lua/remote/util.lua's run() helper. The key invariant:
-- run() must keep nvim's event loop pumping during the wait so
-- vim.uv.timer callbacks (idle watcher, etc.) keep firing. Blocking
-- vim.system(cmd):wait() would fail the "timer fires during wait" test.

describe('remote.util.run', function()
  local util

  before_each(function()
    package.loaded['remote.util'] = nil
    util = require('remote.util')
  end)

  it('returns SystemCompleted shape for fast sync command', function()
    local res = util.run({ 'echo', 'hello' })
    assert.are.equal(0, res.code)
    -- echo appends a newline; trim before compare
    assert.are.equal('hello', (res.stdout or ''):gsub('%s+$', ''))
  end)

  it('surfaces non-zero exit code', function()
    local res = util.run({ 'sh', '-c', 'exit 7' })
    assert.are.equal(7, res.code)
  end)

  it('returns code=124 on timeout', function()
    local res = util.run({ 'sleep', '2' }, { text = true }, 100)
    assert.are.equal(124, res.code)
    assert.is_truthy(res.stderr:match('timeout'))
  end)

  it('keeps vim.uv.timer firing during the wait (non-blocking contract)', function()
    -- The whole point of this helper: blocking :wait() would starve
    -- the timer. If this test ever fails, the helper regressed back
    -- to a sync :wait() variant and idle-watcher alerts will stop
    -- firing during remote ssh operations.
    local fired = 0
    local timer = vim.uv.new_timer()
    timer:start(
      100,
      100,
      vim.schedule_wrap(function()
        fired = fired + 1
      end)
    )
    util.run({ 'sleep', '1' }, { text = true }, 5000)
    timer:stop()
    timer:close()
    -- 1 second wait @ 100ms interval → roughly 8-10 fires expected;
    -- assert >=3 to allow slack for test-runner jitter.
    assert.is_true(
      fired >= 3,
      'expected vim.uv.timer to fire >=3 times during 1s run(); got ' .. fired
    )
  end)
end)
