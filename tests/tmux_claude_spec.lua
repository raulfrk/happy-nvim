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

  it('_build_ce_payload includes diagnostics bullets w/ 1-based line numbers', function()
    -- vim.diagnostic emits 0-based lnum; payload must report the
    -- user-visible (1-based) line. #22 regression guard.
    local p = claude._build_ce_payload('src/foo.lua', {
      { severity = 1, message = 'undefined global', lnum = 5 },
      { severity = 2, message = 'unused var', lnum = 10 },
    })
    assert.is_true(p:find('@src/foo.lua') ~= nil)
    assert.is_true(p:find('undefined global') ~= nil)
    assert.is_true(p:find('line 6') ~= nil) -- lnum 5 → line 6
    assert.is_true(p:find('line 11') ~= nil) -- lnum 10 → line 11
  end)

  it('_build_ce_payload converts lnum=0 to line 1 (no line 0)', function()
    local p = claude._build_ce_payload('src/foo.lua', {
      { severity = 3, message = 'first line warn', lnum = 0 },
    })
    assert.is_true(p:find('line 1') ~= nil)
    assert.is_false(p:find('line 0') ~= nil, 'must not emit `line 0`')
  end)
end)
