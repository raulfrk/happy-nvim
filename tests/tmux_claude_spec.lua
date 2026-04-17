-- tests/tmux_claude_spec.lua
describe('tmux.claude', function()
  local claude

  before_each(function()
    package.loaded['tmux.claude'] = nil
    claude = require('tmux.claude')
  end)

  it('_build_cf_payload returns @path', function()
    assert.are.equal('@src/foo.lua', claude._build_cf_payload('src/foo.lua'))
  end)

  it('_build_cs_payload builds fenced block with path:line range', function()
    local p = claude._build_cs_payload(
      'src/foo.lua',
      12,
      14,
      'lua',
      { 'local x = 1', 'local y = 2', 'local z = 3' }
    )
    assert.is_true(p:find('@src/foo.lua:12%-14') ~= nil)
    assert.is_true(p:find('```lua') ~= nil)
    assert.is_true(p:find('local x = 1') ~= nil)
  end)

  it('_build_cs_payload switches to ~~~ fence when content has ```', function()
    local p = claude._build_cs_payload('src/foo.md', 1, 1, 'markdown', { '```python' })
    assert.is_true(p:find('~~~markdown') ~= nil)
    assert.is_false(p:find('```markdown') ~= nil)
  end)

  it('_build_ce_payload includes diagnostics bullets', function()
    local p = claude._build_ce_payload('src/foo.lua', {
      { severity = 1, message = 'undefined global', lnum = 5 },
      { severity = 2, message = 'unused var', lnum = 10 },
    })
    assert.is_true(p:find('@src/foo.lua') ~= nil)
    assert.is_true(p:find('undefined global') ~= nil)
    assert.is_true(p:find('line 5') ~= nil)
  end)
end)
