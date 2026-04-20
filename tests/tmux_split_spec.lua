-- Unit tests for lua/tmux/split.lua — layout-aware orientation picker.
local eq = assert.are.equal

describe('tmux.split.orient', function()
  local orig_system
  before_each(function()
    orig_system = vim.fn.system
    package.loaded['tmux.split'] = nil
  end)
  after_each(function()
    vim.fn.system = orig_system
  end)

  local function stub_dims(w, h)
    vim.fn.system = function(args)
      if args[3] == '-p' and args[4]:find('window_width') then return tostring(w) end
      if args[3] == '-p' and args[4]:find('window_height') then return tostring(h) end
      return ''
    end
  end

  it('wide window → vertical split', function()
    stub_dims(300, 50) -- 6.0 ratio
    eq('v', require('tmux.split').orient())
  end)

  it('tall/square window → horizontal split', function()
    stub_dims(120, 80) -- 1.5 ratio
    eq('h', require('tmux.split').orient())
  end)

  it('degenerate tmux output → horizontal fallback', function()
    vim.fn.system = function() return 'garbage' end
    eq('h', require('tmux.split').orient())
  end)
end)

describe('tmux.split.open', function()
  it('builds tmux split-window argv using M.orient', function()
    package.loaded['tmux.split'] = nil
    local split = require('tmux.split')
    local captured
    local orig_sys = vim.system
    vim.system = function(args, opts)
      captured = args
      return { wait = function() return { code = 0, stdout = '%42\n', stderr = '' } end }
    end
    split.orient = function() return 'v' end
    local pane = split.open('claude', { cwd = '/tmp' })
    vim.system = orig_sys
    assert.truthy(captured)
    assert.truthy(vim.tbl_contains(captured, '-v') or vim.tbl_contains(captured, '-h'))
    eq('%42', pane)
  end)
end)
