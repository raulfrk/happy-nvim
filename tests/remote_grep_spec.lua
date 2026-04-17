-- tests/remote_grep_spec.lua
describe('remote.grep', function()
  local grep

  before_each(function()
    package.loaded['remote.grep'] = nil
    grep = require('remote.grep')
  end)

  it('_parse_input extracts pattern, path, glob, and flags', function()
    local parsed = grep._parse_input("pattern=foo path=/etc glob=*.conf +timeout=60 +size=50M +hidden")
    assert.are.equal('foo', parsed.pattern)
    assert.are.equal('/etc', parsed.path)
    assert.are.equal('*.conf', parsed.glob)
    assert.are.equal(60, parsed.timeout)
    assert.are.equal('50M', parsed.size)
    assert.is_true(parsed.hidden)
  end)

  it('_parse_input supports +regex=perl / fixed', function()
    local p1 = grep._parse_input('pattern=foo path=/ glob=* +regex=perl')
    assert.are.equal('perl', p1.regex)
    local p2 = grep._parse_input('pattern=foo path=/ glob=* +regex=fixed')
    assert.are.equal('fixed', p2.regex)
  end)

  it('_build_cmd uses grep -EIlH by default', function()
    local cmd = grep._build_cmd('myhost', {
      pattern = 'foo', path = '/etc', glob = '*.conf',
      timeout = 30, size = '10M',
    })
    local joined = table.concat(cmd, ' ')
    assert.is_true(joined:find('grep %-EIlH') ~= nil)
    assert.is_true(joined:find("nice %-n19") ~= nil)
    assert.is_true(joined:find("ionice %-c3") ~= nil)
    assert.is_true(joined:find("timeout 30") ~= nil)
    assert.is_true(joined:find('%-size %-10M') ~= nil)
  end)

  it('_build_cmd switches to -PIlH for +regex=perl', function()
    local cmd = grep._build_cmd('myhost', {
      pattern = 'foo', path = '/', glob = '*',
      timeout = 30, size = '10M', regex = 'perl',
    })
    assert.is_true(table.concat(cmd, ' '):find('grep %-PIlH') ~= nil)
  end)

  it('_build_cmd drops hidden/node_modules/venv filters with +all', function()
    local cmd = grep._build_cmd('myhost', {
      pattern = 'foo', path = '/', glob = '*',
      timeout = 30, size = '10M', all = true,
    })
    local joined = table.concat(cmd, ' ')
    assert.is_false(joined:find('node_modules') ~= nil)
    assert.is_false(joined:find('venv') ~= nil)
  end)
end)
