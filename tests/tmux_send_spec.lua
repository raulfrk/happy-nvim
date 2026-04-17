-- tests/tmux_send_spec.lua
describe('tmux.send', function()
  local send

  before_each(function()
    package.loaded['tmux.send'] = nil
    send = require('tmux.send')
  end)

  it('_quote_for_send_keys escapes single quotes for tmux send-keys -l', function()
    -- send-keys -l sends bytes literally; no special escaping needed EXCEPT
    -- the shell-level single-quote wrapping we use. Verify single quotes are
    -- escaped as '\''
    assert.are.equal("it'\\''s", send._quote_for_send_keys("it's"))
  end)

  it('_build_send_cmd assembles the expected tmux invocation', function()
    local cmd = send._build_send_cmd('%42', 'hello world')
    assert.are.same({
      'tmux',
      'send-keys',
      '-t',
      '%42',
      '-l',
      'hello world',
    }, cmd)
  end)

  it('_build_send_cmd appends Enter helper when append_enter=true', function()
    local cmd = send._build_enter_cmd('%42')
    assert.are.same({ 'tmux', 'send-keys', '-t', '%42', 'Enter' }, cmd)
  end)
end)

describe('tmux.send.resolve_target', function()
  local send
  local orig_get_pane
  local orig_popup

  before_each(function()
    package.loaded['tmux.send'] = nil
    send = require('tmux.send')
    orig_get_pane = send.get_claude_pane_id
    orig_popup = package.loaded['tmux.claude_popup']
  end)

  after_each(function()
    send.get_claude_pane_id = orig_get_pane
    package.loaded['tmux.claude_popup'] = orig_popup
  end)

  it('returns pane id + "pane" label when @claude_pane_id is set', function()
    send.get_claude_pane_id = function()
      return '%42'
    end
    package.loaded['tmux.claude_popup'] = {
      pane_id = function()
        return '%99'
      end,
    }
    local id, kind = send.resolve_target()
    assert.are.equal('%42', id)
    assert.are.equal('pane', kind)
  end)

  it('falls back to popup pane id + "popup" label when no pane', function()
    send.get_claude_pane_id = function()
      return nil
    end
    package.loaded['tmux.claude_popup'] = {
      pane_id = function()
        return '%99'
      end,
    }
    local id, kind = send.resolve_target()
    assert.are.equal('%99', id)
    assert.are.equal('popup', kind)
  end)

  it('returns nil, nil when neither surface is open', function()
    send.get_claude_pane_id = function()
      return nil
    end
    package.loaded['tmux.claude_popup'] = {
      pane_id = function()
        return nil
      end,
    }
    local id, kind = send.resolve_target()
    assert.is_nil(id)
    assert.is_nil(kind)
  end)
end)
