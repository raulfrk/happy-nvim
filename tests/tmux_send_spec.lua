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
  local orig_system
  local orig_popup
  local orig_registry

  before_each(function()
    package.loaded['tmux.send'] = nil
    send = require('tmux.send')
    orig_system = vim.system
    orig_popup = package.loaded['tmux.claude_popup']
    orig_registry = package.loaded['happy.projects.registry']
  end)

  after_each(function()
    vim.system = orig_system
    package.loaded['tmux.claude_popup'] = orig_popup
    package.loaded['happy.projects.registry'] = orig_registry
  end)

  -- Helper: stub `vim.system` to script responses to the tmux subcommands
  -- resolve_target issues (has-session, list-panes).
  local function stub_tmux(responses)
    vim.system = function(cmd, _opts)
      local key = table.concat(cmd or {}, ' ')
      local r = responses[key] or { code = 1, stdout = '', stderr = '' }
      return {
        wait = function()
          return r
        end,
      }
    end
  end

  local function stub_registry(id, entry)
    package.loaded['happy.projects.registry'] = {
      add = function()
        return id
      end,
      get = function()
        return entry
      end,
    }
  end

  it('returns session pane id + "session" label when cc-<id> is alive', function()
    stub_registry('proj-x', { kind = 'local', path = '/tmp/proj' })
    stub_tmux({
      ['tmux has-session -t cc-proj-x'] = { code = 0, stdout = '', stderr = '' },
      ['tmux list-panes -t cc-proj-x -F #{pane_id}'] = {
        code = 0,
        stdout = '%42\n',
        stderr = '',
      },
    })
    package.loaded['tmux.claude_popup'] = {
      pane_id = function()
        return '%99'
      end,
    }
    local id, kind = send.resolve_target()
    assert.are.equal('%42', id)
    assert.are.equal('session', kind)
  end)

  it('uses remote-<id> session prefix for kind=remote', function()
    package.loaded['happy.projects.registry'] = {
      add = function()
        return 'host-proj'
      end,
      get = function()
        return { kind = 'remote', host = 'h', path = '/p' }
      end,
    }
    stub_tmux({
      ['tmux has-session -t remote-host-proj'] = { code = 0, stdout = '', stderr = '' },
      ['tmux list-panes -t remote-host-proj -F #{pane_id}'] = {
        code = 0,
        stdout = '%77\n',
        stderr = '',
      },
    })
    package.loaded['tmux.claude_popup'] = {
      pane_id = function()
        return nil
      end,
    }
    local id, kind = send.resolve_target()
    assert.are.equal('%77', id)
    assert.are.equal('session', kind)
  end)

  it('falls back to popup pane id + "popup" when session not alive', function()
    package.loaded['happy.projects.registry'] = {
      add = function()
        return 'proj-x'
      end,
      get = function()
        return { kind = 'local', path = '/p' }
      end,
    }
    -- no session alive: every tmux cmd returns code=1
    stub_tmux({})
    package.loaded['tmux.claude_popup'] = {
      pane_id = function()
        return '%99'
      end,
    }
    local id, kind = send.resolve_target()
    assert.are.equal('%99', id)
    assert.are.equal('popup', kind)
  end)

  it('returns nil, nil when neither session nor popup is open', function()
    package.loaded['happy.projects.registry'] = {
      add = function()
        return 'proj-x'
      end,
      get = function()
        return { kind = 'local', path = '/p' }
      end,
    }
    stub_tmux({})
    package.loaded['tmux.claude_popup'] = {
      pane_id = function()
        return nil
      end,
    }
    local id, kind = send.resolve_target()
    assert.is_nil(id)
    assert.is_nil(kind)
  end)

  it('survives registry errors and falls through to popup', function()
    -- Simulate registry.add throwing (e.g. read-only FS).
    package.loaded['happy.projects.registry'] = {
      add = function()
        error('registry broken')
      end,
      get = function()
        return nil
      end,
    }
    stub_tmux({})
    package.loaded['tmux.claude_popup'] = {
      pane_id = function()
        return '%99'
      end,
    }
    local id, kind = send.resolve_target()
    assert.are.equal('%99', id)
    assert.are.equal('popup', kind)
  end)
end)
