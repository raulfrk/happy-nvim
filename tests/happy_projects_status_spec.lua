local status = require('happy.projects.status')
local registry = require('happy.projects.registry')

describe('happy.projects.status format', function()
  local tmp
  before_each(function()
    tmp = vim.fn.tempname(); registry._set_path_for_test(tmp)
  end)
  after_each(function()
    os.remove(tmp); registry._reset_for_test()
  end)

  it('renders empty state as blank', function()
    assert.equals('', status.format_for_statusline())
  end)

  it('renders multiple projects w/ icons', function()
    local a = registry.add({ kind = 'local', path = '/tmp/a' })
    local b = registry.add({ kind = 'local', path = '/tmp/b' })
    status._set_state_for_test({
      [a] = 'idle', [b] = 'working'
    })
    local out = status.format_for_statusline()
    assert.is_truthy(out:match('✓'))
    assert.is_truthy(out:match('⟳'))
  end)

  it('truncates beyond 5 entries', function()
    for i = 1, 7 do registry.add({ kind = 'local', path = '/tmp/p' .. i }) end
    local fake = {}
    for _, e in ipairs(registry.list()) do fake[e.id] = 'idle' end
    status._set_state_for_test(fake)
    local out = status.format_for_statusline()
    assert.is_truthy(out:match('…%+2'))
  end)
end)
