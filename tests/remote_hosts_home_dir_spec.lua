describe('remote.hosts home_dir cache', function()
  local tmp
  before_each(function()
    package.loaded['remote.hosts'] = nil
    tmp = vim.fn.tempname() .. '.json'
  end)
  after_each(function()
    vim.fn.delete(tmp)
  end)

  it('home_dir returns nil before probe, caches once set', function()
    local hosts = require('remote.hosts')
    hosts._set_db_path_for_test(tmp)
    assert.is_nil(hosts.home_dir('h1'))
    hosts.record_home_dir('h1', '/home/alice')
    assert.are.equal('/home/alice', hosts.home_dir('h1'))
  end)

  it('home_dir survives reload via JSON', function()
    local hosts = require('remote.hosts')
    hosts._set_db_path_for_test(tmp)
    hosts.record('h2')
    hosts.record_home_dir('h2', '/root')
    package.loaded['remote.hosts'] = nil
    local hosts2 = require('remote.hosts')
    hosts2._set_db_path_for_test(tmp)
    assert.are.equal('/root', hosts2.home_dir('h2'))
  end)

  it('expand_path substitutes ~ only at the start', function()
    local hosts = require('remote.hosts')
    hosts._set_db_path_for_test(tmp)
    hosts.record_home_dir('h3', '/home/bob')
    assert.are.equal('/home/bob/.bashrc', hosts.expand_path('h3', '~/.bashrc'))
    assert.are.equal('/etc/hosts', hosts.expand_path('h3', '/etc/hosts'))
    assert.are.equal('a~b', hosts.expand_path('h3', 'a~b'))
  end)
end)
