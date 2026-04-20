describe('tmux.tt', function()
  local orig_system
  before_each(function()
    orig_system = vim.system
    package.loaded['tmux.tt'] = nil
  end)
  after_each(function()
    vim.system = orig_system
  end)

  it('M.session_name uses tt- prefix + project slug', function()
    package.loaded['tmux.project'] = {
      session_name = function()
        return 'cc-proj-a'
      end,
    }
    local tt = require('tmux.tt')
    assert.are.equal('tt-proj-a', tt.session_name())
  end)

  it('M.ensure spawns a detached session w/ $SHELL if missing', function()
    package.loaded['tmux.project'] = {
      session_name = function()
        return 'cc-x'
      end,
    }
    local tt = require('tmux.tt')
    local calls = {}
    vim.system = function(args)
      table.insert(calls, args)
      if args[2] == 'has-session' then
        return {
          wait = function()
            return { code = 1 }
          end,
        }
      end
      return {
        wait = function()
          return { code = 0 }
        end,
      }
    end
    assert.True(tt.ensure())
    local saw_new = false
    for _, a in ipairs(calls) do
      if a[2] == 'new-session' and a[5] == 'tt-x' then
        saw_new = true
      end
    end
    assert.True(saw_new)
  end)
end)
