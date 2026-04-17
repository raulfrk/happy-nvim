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
