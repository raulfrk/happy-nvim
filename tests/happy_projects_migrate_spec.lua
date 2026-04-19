local registry = require('happy.projects.registry')
local migrate = require('happy.projects.migrate')

describe('happy.projects.migrate', function()
  local tmp
  before_each(function()
    tmp = vim.fn.tempname()
    registry._set_path_for_test(tmp)
  end)
  after_each(function()
    os.remove(tmp)
    registry._reset_for_test()
  end)

  it('ingests sessions whose HAPPY_PROJECT_PATH env is set', function()
    local fake_tmux = function(args)
      if args[2] == 'list-sessions' then
        return 'cc-foo\ncc-bar\nrandom'
      end
      if args[2] == 'show-env' and args[4] == 'cc-foo' then
        return 'HAPPY_PROJECT_PATH=/home/u/foo'
      end
      if args[2] == 'show-env' and args[4] == 'cc-bar' then
        return '-HAPPY_PROJECT_PATH' -- unset
      end
      return ''
    end
    migrate._set_tmux_fn_for_test(fake_tmux)

    local n = migrate.run()
    assert.equals(1, n)
    local all = registry.list()
    assert.equals('/home/u/foo', all[1].path)
  end)

  it('is idempotent', function()
    local fake_tmux = function(args)
      if args[2] == 'list-sessions' then
        return 'cc-foo'
      end
      if args[2] == 'show-env' then
        return 'HAPPY_PROJECT_PATH=/home/u/foo'
      end
      return ''
    end
    migrate._set_tmux_fn_for_test(fake_tmux)
    assert.equals(1, migrate.run())
    assert.equals(0, migrate.run()) -- dedup
  end)
end)
