-- tests/remote_browse_spec.lua
describe('remote.browse', function()
  local browse

  before_each(function()
    package.loaded['remote.browse'] = nil
    browse = require('remote.browse')
  end)

  it('_fast_path_ext returns true for known binary extensions', function()
    assert.is_true(browse._fast_path_ext('foo.png'))
    assert.is_true(browse._fast_path_ext('bar.tar.gz'))
    assert.is_false(browse._fast_path_ext('baz.lua'))
    assert.is_false(browse._fast_path_ext('readme'))
  end)

  it('_build_mime_probe_cmd builds ssh file -b --mime-encoding cmd', function()
    local cmd = browse._build_mime_probe_cmd('myhost', '/etc/passwd')
    assert.are.same({ 'ssh', 'myhost', 'file -b --mime-encoding /etc/passwd' }, cmd)
  end)

  it('_is_binary_mime detects "binary" encoding', function()
    assert.is_true(browse._is_binary_mime('binary\n'))
    assert.is_true(browse._is_binary_mime('binary'))
    assert.is_false(browse._is_binary_mime('utf-8'))
    assert.is_false(browse._is_binary_mime('us-ascii'))
  end)
end)
