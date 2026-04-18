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
