local registry = require('happy.projects.registry')

describe('happy.projects.registry', function()
  local tmp
  before_each(function()
    tmp = vim.fn.tempname()
    registry._set_path_for_test(tmp)
  end)
  after_each(function()
    os.remove(tmp)
    registry._reset_for_test()
  end)

  it('starts empty', function()
    assert.same({}, registry.list())
  end)

  it('adds a local project and persists', function()
    local id = registry.add({ kind = 'local', path = '/tmp/proj-a' })
    assert.is_string(id)
    assert.equals('local', registry.get(id).kind)
    assert.equals('/tmp/proj-a', registry.get(id).path)

    registry._reset_for_test()
    registry._set_path_for_test(tmp)
    assert.equals('/tmp/proj-a', registry.get(id).path)
  end)

  it('adds a remote project', function()
    local id = registry.add({ kind = 'remote', host = 'prod01', path = '/var/log' })
    local entry = registry.get(id)
    assert.equals('remote', entry.kind)
    assert.equals('prod01', entry.host)
    assert.equals('/var/log', entry.path)
  end)

  it('forgets a project', function()
    local id = registry.add({ kind = 'local', path = '/tmp/proj-b' })
    registry.forget(id)
    assert.is_nil(registry.get(id))
  end)

  it('touch bumps open_count and last_opened', function()
    local id = registry.add({ kind = 'local', path = '/tmp/proj-c' })
    local before = registry.get(id).open_count
    registry.touch(id)
    local after = registry.get(id).open_count
    assert.equals(before + 1, after)
    assert.is_true(registry.get(id).last_opened > 0)
  end)

  it('dedupes on add by identity (path for local, host+path for remote)', function()
    local id1 = registry.add({ kind = 'local', path = '/tmp/proj-d' })
    local id2 = registry.add({ kind = 'local', path = '/tmp/proj-d' })
    assert.equals(id1, id2)
  end)

  it('stale .new tmp file from crashed write does not corrupt state', function()
    -- Commit a real entry so the registry file exists on disk.
    registry.add({ kind = 'local', path = '/tmp/proj-e' })

    -- Simulate a mid-write crash: save() writes to `<path>.new` then
    -- renames. If nvim dies between write and rename, the .new is left
    -- behind as half-written garbage.
    local stale = tmp .. '.new'
    local fh = io.open(stale, 'w')
    fh:write('{ "partial":'); fh:close()

    -- Reload: load() reads the real file only, must ignore the stale .new.
    registry._reset_for_test()
    registry._set_path_for_test(tmp)
    assert.equals('/tmp/proj-e', registry.list()[1].path)

    -- Next save() must overwrite the stale .new cleanly. After it runs,
    -- either the .new is gone (renamed onto the real path) or it contains
    -- valid JSON — no stale garbage leaks past the write.
    registry.add({ kind = 'local', path = '/tmp/proj-f' })
    local leftover = io.open(stale, 'r')
    if leftover then
      local content = leftover:read('*a')
      leftover:close()
      local ok, decoded = pcall(vim.json.decode, content)
      assert.is_true(ok, 'stale .new should not linger as garbage after save')
      assert.is_table(decoded)
    end

    os.remove(stale)
  end)
end)
