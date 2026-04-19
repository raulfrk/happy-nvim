local registry = require('happy.projects.registry')

describe('happy.projects.registry frecency + collisions', function()
  local tmp
  before_each(function()
    tmp = vim.fn.tempname()
    registry._set_path_for_test(tmp)
  end)
  after_each(function()
    os.remove(tmp)
    registry._reset_for_test()
  end)

  it('score ranks recently+frequently-opened higher', function()
    local older = registry.add({ kind = 'local', path = '/tmp/a' })
    local newer = registry.add({ kind = 'local', path = '/tmp/b' })
    registry.update(older, { open_count = 5, last_opened = os.time() - 3600 * 24 })
    registry.update(newer, { open_count = 2, last_opened = os.time() - 3600 * 2 })
    assert.is_true(registry.score(newer) > registry.score(older))
  end)

  it('resolves ID collisions by -2, -3 suffix', function()
    local id1 = registry.add({ kind = 'local', path = '/x/proj' })
    local id2 = registry.add({ kind = 'local', path = '/y/proj' })
    local id3 = registry.add({ kind = 'local', path = '/z/proj' })
    assert.equals('proj', id1)
    assert.equals('proj-2', id2)
    assert.equals('proj-3', id3)
  end)

  it('sorted_by_score returns list ordered descending', function()
    registry.update(
      registry.add({ kind = 'local', path = '/tmp/low' }),
      { open_count = 1, last_opened = os.time() - 3600 * 48 }
    )
    registry.update(
      registry.add({ kind = 'local', path = '/tmp/high' }),
      { open_count = 10, last_opened = os.time() }
    )
    local sorted = registry.sorted_by_score()
    assert.equals('/tmp/high', sorted[1].path)
  end)
end)
