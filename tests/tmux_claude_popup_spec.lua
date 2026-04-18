-- tests/tmux_claude_popup_spec.lua
-- Unit tests for lua/tmux/claude_popup.lua config merge. Live tmux ops
-- are covered by integration tests in tests/integration/; here we only
-- assert setup() applies overrides correctly.

describe('tmux.claude_popup.setup', function()
  local popup

  before_each(function()
    package.loaded['tmux.claude_popup'] = nil
    popup = require('tmux.claude_popup')
  end)

  it('defaults to 85% x 85%', function()
    assert.are.equal('85%', popup._config.popup.width)
    assert.are.equal('85%', popup._config.popup.height)
  end)

  it('applies width override, keeps height default', function()
    popup.setup({ popup = { width = '70%' } })
    assert.are.equal('70%', popup._config.popup.width)
    assert.are.equal('85%', popup._config.popup.height)
  end)

  it('applies both width + height overrides', function()
    popup.setup({ popup = { width = '100%', height = '60%' } })
    assert.are.equal('100%', popup._config.popup.width)
    assert.are.equal('60%', popup._config.popup.height)
  end)

  it('no-op when setup called with nil', function()
    popup.setup()
    assert.are.equal('85%', popup._config.popup.width)
  end)

  it('no-op when setup called with empty table', function()
    popup.setup({})
    assert.are.equal('85%', popup._config.popup.width)
  end)
end)

describe('tmux.claude_popup.open', function()
  -- Stubbing vim.system lets us assert the shape of the call without
  -- actually spawning tmux display-popup. The key invariant under test:
  -- open() must use the async (callback) form, never :wait(), otherwise
  -- idle.watch_all()'s vim.uv.timer starves while the popup is attached
  -- and no notification fires (see 2026-04-18 regression).
  local popup
  local captured
  local orig_system

  before_each(function()
    captured = nil
    orig_system = vim.system
    vim.system = function(args, opts, cb)
      -- Only intercept the display-popup call we care about; let other
      -- callers (e.g. project.session_name -> tmux display-message) pass
      -- through so session resolution still works.
      local is_display_popup = false
      for _, a in ipairs(args) do
        if a == 'display-popup' then
          is_display_popup = true
          break
        end
      end
      if is_display_popup then
        captured = { args = args, opts = opts, cb = cb }
        return setmetatable({}, {
          __index = function()
            return function()
              error('vim.system():wait() called on display-popup path — must be async', 2)
            end
          end,
        })
      end
      return orig_system(args, opts, cb)
    end
    package.loaded['tmux.claude_popup'] = nil
    popup = require('tmux.claude_popup')
    vim.env.TMUX = '/tmp/fake,1,0'
    -- Short-circuit ensure() so we don't spawn a real tmux session.
    popup.ensure = function()
      return true
    end
  end)

  after_each(function()
    vim.system = orig_system
  end)

  it('passes a callback to vim.system (async form, not :wait)', function()
    popup.open()
    assert.is_truthy(captured, 'vim.system was never called by open()')
    assert.is_function(
      captured.cb,
      'open() must pass an on_exit callback; :wait() blocks idle.watch_all timer'
    )
  end)

  it('invokes tmux display-popup', function()
    popup.open()
    local joined = table.concat(captured.args, ' ')
    assert.is_truthy(
      joined:match('display%-popup'),
      'open() must invoke `tmux display-popup`; got: ' .. joined
    )
  end)
end)
