-- tests/remote_grep_spec.lua
describe('remote.grep', function()
  local grep

  before_each(function()
    package.loaded['remote.grep'] = nil
    grep = require('remote.grep')
  end)

  it('_parse_input extracts pattern, path, glob, and flags', function()
    local parsed =
      grep._parse_input('pattern=foo path=/etc glob=*.conf +timeout=60 +size=50M +hidden')
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
      pattern = 'foo',
      path = '/etc',
      glob = '*.conf',
      timeout = 30,
      size = '10M',
    })
    local joined = table.concat(cmd, ' ')
    assert.is_true(joined:find('grep %-EIlH') ~= nil)
    assert.is_true(joined:find('nice %-n19') ~= nil)
    assert.is_true(joined:find('ionice %-c3') ~= nil)
    assert.is_true(joined:find('timeout 30') ~= nil)
    assert.is_true(joined:find('%-size %-10M') ~= nil)
  end)

  it('_build_cmd switches to -PIlH for +regex=perl', function()
    local cmd = grep._build_cmd('myhost', {
      pattern = 'foo',
      path = '/',
      glob = '*',
      timeout = 30,
      size = '10M',
      regex = 'perl',
    })
    assert.is_true(table.concat(cmd, ' '):find('grep %-PIlH') ~= nil)
  end)

  it('_build_cmd drops hidden/node_modules/venv filters with +all', function()
    local cmd = grep._build_cmd('myhost', {
      pattern = 'foo',
      path = '/',
      glob = '*',
      timeout = 30,
      size = '10M',
      all = true,
    })
    local joined = table.concat(cmd, ' ')
    assert.is_false(joined:find('node_modules') ~= nil)
    assert.is_false(joined:find('venv') ~= nil)
  end)

  it('_build_cmd shell-escapes single quotes in user input (#19)', function()
    -- Pattern w/ `'; rm -rf /; echo '` must be POSIX-quoted so the
    -- remote shell sees a single literal argument, not two commands.
    local cmd = grep._build_cmd('myhost', {
      pattern = "foo'; rm -rf ~; echo '",
      path = '/',
      glob = '*',
      timeout = 30,
      size = '10M',
    })
    local joined = table.concat(cmd, ' ')
    -- Must contain the escaped-quote dance '\'' (close, escaped-quote, reopen).
    assert.is_truthy(
      joined:find("'\\''"),
      'expected `' .. "'\\''" .. '` in escaped pattern; got: ' .. joined
    )
    -- Must NOT contain a bare `rm -rf ~` that would execute remotely.
    -- After proper quoting, the rm is inside a quoted literal, not a separate cmd.
    -- Sanity check: still sends one -exec grep, not multiple.
    local grep_count = 0
    for _ in joined:gmatch('grep %-') do
      grep_count = grep_count + 1
    end
    assert.are.equal(1, grep_count, 'multiple grep tokens suggest quote escape broke')
  end)
end)
