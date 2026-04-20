describe('tmux.claude.open (split model)', function()
  local orig_system, orig_env, orig_getcwd
  before_each(function()
    orig_system = vim.system
    orig_env = vim.env.TMUX
    orig_getcwd = vim.fn.getcwd
    vim.env.TMUX = 'fake'
    package.loaded['tmux.claude'] = nil
    package.loaded['tmux.split'] = nil
    package.loaded['happy.projects.registry'] = {
      add = function() return 'proj-a' end,
      touch = function() end,
      get = function() return { kind = 'local' } end,
    }
  end)
  after_each(function()
    vim.system = orig_system
    vim.env.TMUX = orig_env
    vim.fn.getcwd = orig_getcwd
  end)

  it('spawns a split in the current window (not a new session)', function()
    local calls = {}
    vim.system = function(args, opts, cb)
      table.insert(calls, args)
      if args[1] == 'tmux' and args[2] == 'split-window' then
        return { wait = function() return { code = 0, stdout = '%99\n' } end }
      end
      if args[1] == 'tmux' and args[2] == 'set-option' then
        return { wait = function() return { code = 0 } end }
      end
      return { wait = function() return { code = 0, stdout = '' } end }
    end
    require('tmux.claude').open()
    local saw_split, saw_set_opt_slug = false, false
    for _, a in ipairs(calls) do
      if a[1] == 'tmux' and a[2] == 'split-window' then saw_split = true end
      if a[1] == 'tmux' and a[2] == 'set-option'
         and a[#a - 1] == '@claude_pane_id_proj-a' then saw_set_opt_slug = true end
    end
    assert.True(saw_split)
    assert.True(saw_set_opt_slug)
  end)
end)
