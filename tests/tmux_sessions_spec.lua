-- tests/tmux_sessions_spec.lua
-- Unit tests for lua/tmux/sessions.lua. The parser takes raw
-- `tmux list-sessions -F ...` output; no tmux invocation needed.

describe('tmux.sessions._parse_list', function()
  local sessions = require('tmux.sessions')

  it('returns empty list for empty input', function()
    assert.are.same({}, sessions._parse_list(''))
  end)

  it('returns empty list for blank-only input', function()
    assert.are.same({}, sessions._parse_list('\n\n  \n'))
  end)

  it('ignores non cc- prefixed sessions', function()
    local raw = 'main|1700000000|%0\nscratch|1700000001|%3'
    assert.are.same({}, sessions._parse_list(raw))
  end)

  it('parses a single cc- session', function()
    local raw = 'cc-happy-nvim|1700000000|%4'
    local parsed = sessions._parse_list(raw)
    assert.are.equal(1, #parsed)
    assert.are.equal('cc-happy-nvim', parsed[1].name)
    assert.are.equal('happy-nvim', parsed[1].slug)
    assert.are.equal(1700000000, parsed[1].created_ts)
    assert.are.equal('%4', parsed[1].first_pane_id)
  end)

  it('parses multiple cc- sessions and ignores non-cc ones', function()
    local raw = table.concat({
      'main|1700000000|%0',
      'cc-happy-nvim|1700000100|%4',
      'cc-other-repo|1700000200|%7',
      '',
    }, '\n')
    local parsed = sessions._parse_list(raw)
    assert.are.equal(2, #parsed)
    assert.are.equal('cc-happy-nvim', parsed[1].name)
    assert.are.equal('cc-other-repo', parsed[2].name)
  end)

  it('tolerates extra whitespace', function()
    local raw = '  cc-happy-nvim|1700000000|%4  '
    assert.are.equal('cc-happy-nvim', sessions._parse_list(raw)[1].name)
  end)
end)
