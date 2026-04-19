local sources = require('happy.hub.sources')

describe('happy.hub.sources.project_rows', function()
  local orig_registry
  before_each(function()
    orig_registry = package.loaded['happy.projects.registry']
    package.loaded['happy.projects.registry'] = {
      list = function()
        return {
          { id = 'proj-a', kind = 'local', path = '/p/a', last_opened = os.time() - 60 },
          {
            id = 'proj-b',
            kind = 'remote',
            host = 'h',
            path = '/p/b',
            last_opened = os.time() - 120,
          },
        }
      end,
      score = function(id)
        return id == 'proj-a' and 10 or 5
      end,
      get = function(id)
        if id == 'proj-a' then
          return { kind = 'local', path = '/p/a' }
        end
        if id == 'proj-b' then
          return { kind = 'remote', host = 'h', path = '/p/b' }
        end
        return nil
      end,
    }
  end)
  after_each(function()
    package.loaded['happy.projects.registry'] = orig_registry
  end)

  it('emits one row per registered project with correct kind', function()
    local rows = sources.project_rows()
    assert.equals(2, #rows)
    for _, r in ipairs(rows) do
      assert.equals('project', r.kind)
    end
  end)

  it('attaches on_pivot closure that calls projects.pivot.pivot', function()
    local called_with
    package.loaded['happy.projects.pivot'] = {
      pivot = function(id)
        called_with = id
      end,
    }
    local rows = sources.project_rows()
    rows[1].on_pivot()
    assert.equals(rows[1].id, called_with)
    package.loaded['happy.projects.pivot'] = nil
  end)
end)

describe('happy.hub.sources.host_rows', function()
  local orig_hosts
  before_each(function()
    orig_hosts = package.loaded['remote.hosts']
    package.loaded['remote.hosts'] = {
      list = function()
        return {
          { host = '[+ Add host]', marker = 'add' },
          { host = 'prod01', score = 8.2 },
          { host = 'dev02', score = 3.1 },
        }
      end,
      record = function(_) end,
    }
  end)
  after_each(function()
    package.loaded['remote.hosts'] = orig_hosts
  end)

  it('drops the add-marker entry', function()
    local rows = sources.host_rows()
    assert.equals(2, #rows)
    for _, r in ipairs(rows) do
      assert.is_nil(r.id:match('^%['))
    end
  end)

  it('emits kind=host with id=host-name', function()
    local rows = sources.host_rows()
    assert.equals('host', rows[1].kind)
    assert.equals('prod01', rows[1].id)
  end)
end)

describe('happy.hub.sources.session_rows', function()
  local orig_registry
  before_each(function()
    orig_registry = package.loaded['happy.projects.registry']
    package.loaded['happy.projects.registry'] = {
      get = function(id)
        if id == 'proj-a' then
          return { kind = 'local' }
        end
        return nil
      end,
    }
  end)
  after_each(function()
    package.loaded['happy.projects.registry'] = orig_registry
  end)

  it('emits orphan sessions only (not in registry)', function()
    sources._set_tmux_fn_for_test(function(args)
      if args[2] == 'list-sessions' then
        return 'cc-proj-a\ncc-legacy\nremote-orphan\nrandom-other'
      end
      return ''
    end)
    local rows = sources.session_rows()
    assert.equals(2, #rows)
    local ids = {}
    for _, r in ipairs(rows) do
      ids[r.id] = true
    end
    assert.is_true(ids['cc-legacy'])
    assert.is_true(ids['remote-orphan'])
    assert.is_nil(ids['cc-proj-a'])
  end)
end)

describe('happy.hub merge + weight', function()
  it('sorts merged entries by weighted normalized score', function()
    local sources = require('happy.hub.sources')
    sources.project_rows = function()
      return {
        { kind = 'project', id = 'p-hot', raw_score = 10, on_pivot = function() end },
        { kind = 'project', id = 'p-cold', raw_score = 1, on_pivot = function() end },
      }
    end
    sources.host_rows = function()
      return { { kind = 'host', id = 'h-hot', raw_score = 10, on_pivot = function() end } }
    end
    sources.session_rows = function()
      return { { kind = 'session', id = 's-hot', raw_score = 1, on_pivot = function() end } }
    end

    local hub = require('happy.hub')
    hub._reset_weights_for_test()
    local merged = hub._merge_for_test()
    -- Defaults: project=1.0, session=0.8, host=0.6
    -- Normalized:
    --   p-hot: 1.0*1.0=1.0
    --   p-cold: 0.1*1.0=0.1
    --   h-hot: 1.0*0.6=0.6
    --   s-hot: 1.0*0.8=0.8
    -- Order: p-hot (1.0) > s-hot (0.8) > h-hot (0.6) > p-cold (0.1)
    assert.equals('p-hot', merged[1].id)
    assert.equals('s-hot', merged[2].id)
    assert.equals('h-hot', merged[3].id)
    assert.equals('p-cold', merged[4].id)
  end)

  it('applies user-supplied weight overrides', function()
    local sources = require('happy.hub.sources')
    sources.project_rows = function()
      return { { kind = 'project', id = 'p', raw_score = 1, on_pivot = function() end } }
    end
    sources.host_rows = function()
      return { { kind = 'host', id = 'h', raw_score = 1, on_pivot = function() end } }
    end
    sources.session_rows = function()
      return {}
    end

    local hub = require('happy.hub')
    hub.setup({ weights = { project = 0.1, host = 2.0 } })
    local merged = hub._merge_for_test()
    assert.equals('h', merged[1].id)
    assert.equals('p', merged[2].id)
    hub._reset_weights_for_test()
  end)
end)
