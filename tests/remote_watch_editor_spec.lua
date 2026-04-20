describe('remote.watch_editor', function()
  it('_parse_lines reconstructs patterns from editor buffer', function()
    package.loaded['remote.watch_editor'] = nil
    local ed = require('remote.watch_editor')
    local lines = {
      '# host: h',
      '# path: /p',
      '',
      '[x] ERROR  :: fatal',
      '[ ] WARN   :: slowdown',
      '[x] INFO!  :: once-only',
    }
    local parsed = ed._parse_lines(lines)
    assert.are.equal(3, #parsed)
    assert.True(parsed[1].active)
    assert.are.equal('ERROR', parsed[1].level)
    assert.are.equal('fatal', parsed[1].regex)
    assert.False(parsed[2].active)
    assert.True(parsed[3].oneshot) -- '!' suffix
  end)
end)
