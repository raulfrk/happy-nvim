describe('remote.ssh_exec', function()
  local ssh_exec
  before_each(function()
    package.loaded['remote.ssh_exec'] = nil
    ssh_exec = require('remote.ssh_exec')
  end)

  it('argv prepends ControlMaster options', function()
    local argv = ssh_exec.argv('host01', { 'uptime' })
    assert.are.equal('ssh', argv[1])
    local joined = table.concat(argv, ' ')
    assert.truthy(joined:find('ControlMaster=auto'))
    assert.truthy(joined:find('ControlPath='))
    assert.truthy(joined:find('ControlPersist='))
    assert.are.equal('host01', argv[#argv - 1])
    assert.are.equal('uptime', argv[#argv])
  end)

  it('accepts pre-joined string cmd', function()
    local argv = ssh_exec.argv('h', 'ls /tmp')
    assert.are.equal('ls /tmp', argv[#argv])
  end)

  it('ControlPath is under stdpath("cache")', function()
    local argv = ssh_exec.argv('h', 'x')
    local joined = table.concat(argv, ' ')
    assert.truthy(joined:find(vim.fn.stdpath('cache'), 1, true))
  end)
end)
