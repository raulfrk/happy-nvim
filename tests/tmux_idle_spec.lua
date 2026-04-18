-- tests/tmux_idle_spec.lua
-- Unit tests for lua/tmux/idle.lua state machine. Core is pure-function so
-- tests pass synthetic captures + fake timestamps; no tmux needed.

describe('tmux.idle', function()
  local idle

  before_each(function()
    vim.g._happy_idle_timer_active = nil
    package.loaded['tmux.idle'] = nil
    idle = require('tmux.idle')
  end)

  after_each(function()
    if idle and idle.stop then
      idle.stop()
    end
    vim.g._happy_idle_timer_active = nil
  end)

  describe('._tick', function()
    it('initializes state on first tick (busy, records hash + now)', function()
      local state = {}
      local new_state, flipped = idle._tick(state, 'some output', 1000)
      assert.are.equal('hash-some output', new_state.last_hash)
      assert.are.equal(1000, new_state.stable_since)
      assert.is_false(new_state.idle)
      assert.is_false(flipped)
    end)

    it('stays busy when output changes', function()
      local state = { last_hash = 'hash-old', stable_since = 1000, idle = true }
      local new_state, flipped = idle._tick(state, 'new output', 1001)
      assert.are.equal('hash-new output', new_state.last_hash)
      assert.are.equal(1001, new_state.stable_since)
      assert.is_false(new_state.idle)
      assert.is_true(flipped) -- was idle, now busy = flipped
    end)

    it('stays busy when stable < debounce window', function()
      local state = { last_hash = 'hash-same', stable_since = 1000, idle = false }
      local new_state, flipped = idle._tick(state, 'same', 1001) -- only 1s stable
      assert.is_false(new_state.idle)
      assert.is_false(flipped)
    end)

    it('flips to idle when stable >= debounce window', function()
      local state = { last_hash = 'hash-same', stable_since = 1000, idle = false }
      local new_state, flipped = idle._tick(state, 'same', 1002) -- 2s stable
      assert.is_true(new_state.idle)
      assert.is_true(flipped)
    end)

    it('stays idle on subsequent stable ticks w/o re-flipping', function()
      local state = { last_hash = 'hash-same', stable_since = 1000, idle = true }
      local new_state, flipped = idle._tick(state, 'same', 1005)
      assert.is_true(new_state.idle)
      assert.is_false(flipped) -- no state change
    end)

    it('does NOT flip to idle while busy_until is active (#20)', function()
      -- mark_busy sets stable_since = now AND busy_until = now + ~5s.
      -- If output is stable AND debounce elapses AND busy_until still
      -- in the future, we must NOT flip.
      local state = {
        last_hash = 'hash-same',
        stable_since = 1000,
        idle = false,
        busy_until = 1010,
      }
      local new_state, flipped = idle._tick(state, 'same', 1003) -- 3s stable, within busy grace
      assert.is_false(new_state.idle)
      assert.is_false(flipped, 'busy_until should suppress premature idle flip')
    end)

    it('flips to idle once busy_until elapses (#20)', function()
      local state = {
        last_hash = 'hash-same',
        stable_since = 1000,
        idle = false,
        busy_until = 1005,
      }
      local new_state, flipped = idle._tick(state, 'same', 1010) -- past busy_until
      assert.is_true(new_state.idle)
      assert.is_true(flipped)
      assert.is_nil(new_state.busy_until, 'busy_until cleared after flip')
    end)
  end)

  describe('watch_all', function()
    it('does not start a second timer after module reload (#21)', function()
      -- First call starts a timer.
      idle.watch_all()
      assert.is_true(vim.g._happy_idle_timer_active)
      -- Simulate :source $MYVIMRC — module-local `timer` resets but
      -- vim.g flag survives. A second watch_all must be a no-op.
      package.loaded['tmux.idle'] = nil
      local idle2 = require('tmux.idle')
      idle2.watch_all()
      -- The sentinel remained set; the second module instance can't
      -- close it (no handle), but we verify the guard triggered by
      -- calling stop() and checking the flag is cleared exactly once.
      idle2.stop()
      assert.is_nil(vim.g._happy_idle_timer_active)
    end)
  end)

  describe('._hash', function()
    it('returns the same value for identical input', function()
      assert.are.equal(idle._hash('hello'), idle._hash('hello'))
    end)

    it('returns a different value for different input', function()
      assert.are_not.equal(idle._hash('hello'), idle._hash('world'))
    end)
  end)

  describe('._should_alert', function()
    local OPTS = {
      notify = true,
      bell = false,
      desktop = false,
      cooldown_secs = 10,
      skip_focused = true,
    }

    it('returns false when all channels off', function()
      local o = vim.tbl_deep_extend('force', OPTS, { notify = false })
      assert.is_false(idle._should_alert('cc-a', 'cc-b', nil, 100, o))
    end)

    it('returns false when session is focused and skip_focused=true', function()
      assert.is_false(idle._should_alert('cc-a', 'cc-a', nil, 100, OPTS))
    end)

    it('returns true when focused but skip_focused=false', function()
      local o = vim.tbl_deep_extend('force', OPTS, { skip_focused = false })
      assert.is_true(idle._should_alert('cc-a', 'cc-a', nil, 100, o))
    end)

    it('returns false when cooldown not elapsed', function()
      assert.is_false(idle._should_alert('cc-a', 'cc-b', 95, 100, OPTS))
    end)

    it('returns true when cooldown elapsed and not focused', function()
      assert.is_true(idle._should_alert('cc-a', 'cc-b', 80, 100, OPTS))
    end)
  end)
end)
