describe('remote.tail', function()
  local orig_system
  before_each(function()
    orig_system = vim.system
    package.loaded['remote.tail'] = nil
  end)
  after_each(function()
    vim.system = orig_system
  end)

  it('session_name slugs host+path deterministically', function()
    local tail = require('remote.tail')
    local n1 = tail._session_name('prod01', '/var/log/app.log')
    local n2 = tail._session_name('prod01', '/var/log/app.log')
    assert.are.equal(n1, n2)
    assert.truthy(n1:find('^tail%-prod01%-'))
  end)

  it('start invokes tmux new-session -d w/ ssh pipe', function()
    local tail = require('remote.tail')
    tail._set_state_dir_for_test(vim.fn.tempname())
    package.loaded['remote.ssh_exec'] = {
      argv = function(h, c)
        return { 'ssh', h, c }
      end,
    }
    package.loaded['remote.watch'] = {
      scan = function()
        return {}
      end,
    }
    local captured
    vim.system = function(args)
      if args[1] == 'tmux' and args[2] == 'has-session' then
        return {
          wait = function()
            return { code = 1 }
          end,
        }
      end
      if args[1] == 'tmux' and args[2] == 'new-session' then
        captured = args
        return {
          wait = function()
            return { code = 0 }
          end,
        }
      end
      return {
        wait = function()
          return { code = 0, stdout = '', stderr = '' }
        end,
      }
    end
    tail.start('h', '/tmp/f.log', { open_buffer = false })
    assert.truthy(captured)
    local joined = table.concat(captured, ' ')
    assert.truthy(joined:find('tail %-F'))
    assert.truthy(joined:find('tee'))
  end)
end)
