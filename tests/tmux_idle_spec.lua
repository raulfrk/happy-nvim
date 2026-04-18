-- tests/tmux_idle_spec.lua
-- Unit tests for lua/tmux/idle.lua state machine. Core is pure-function so
-- tests pass synthetic captures + fake timestamps; no tmux needed.

describe('tmux.idle', function()
  local idle

  before_each(function()
    package.loaded['tmux.idle'] = nil
    idle = require('tmux.idle')
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
