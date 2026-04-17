-- tests/clipboard_spec.lua
describe('clipboard', function()
  local clip

  before_each(function()
    package.loaded['clipboard'] = nil
    clip = require('clipboard')
  end)

  it('encode_osc52() returns correct escape sequence for "hello"', function()
    local seq = clip._encode_osc52('hello')
    -- base64 of "hello" = "aGVsbG8="
    assert.are.equal('\027]52;c;aGVsbG8=\007', seq)
  end)

  it('encode_osc52() returns nil for content exceeding 74KB base64 cap', function()
    local huge = string.rep('x', 60 * 1024) -- ~80KB base64
    assert.is_nil(clip._encode_osc52(huge))
  end)

  it('should_emit() respects SSH_TTY / TMUX guard', function()
    local old_ssh = vim.env.SSH_TTY
    local old_tmux = vim.env.TMUX
    vim.env.SSH_TTY = nil
    vim.env.TMUX = nil
    assert.is_false(clip._should_emit())
    vim.env.TMUX = '/tmp/tmux-1000/default,123,0'
    assert.is_true(clip._should_emit())
    vim.env.SSH_TTY = old_ssh
    vim.env.TMUX = old_tmux
  end)
end)
