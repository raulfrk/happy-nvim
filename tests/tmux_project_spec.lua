-- tests/tmux_project_spec.lua
-- Unit tests for lua/tmux/project.lua. Uses monkey-patched vim.system so
-- no real git calls happen.

describe('tmux.project._slug', function()
  local project = require('tmux.project')

  it('keeps alphanumerics and hyphens unchanged', function()
    assert.are.equal('happy-nvim', project._slug('happy-nvim'))
  end)

  it('replaces slashes with hyphens', function()
    assert.are.equal('a-b-c', project._slug('a/b/c'))
  end)

  it('collapses runs of non-slug chars into one hyphen', function()
    assert.are.equal('a-b', project._slug('a /// b'))
  end)

  it('strips leading/trailing hyphens', function()
    assert.are.equal('x', project._slug('---x---'))
  end)
end)

describe('tmux.project._derive_id', function()
  local project = require('tmux.project')

  it('returns basename slug for primary git checkout', function()
    local id = project._derive_id({
      toplevel = '/home/raul/projects/happy-nvim',
      git_dir = '/home/raul/projects/happy-nvim/.git',
      common_dir = '/home/raul/projects/happy-nvim/.git',
    })
    assert.are.equal('happy-nvim', id)
  end)

  it('appends wt-<leaf> for a worktree', function()
    local id = project._derive_id({
      toplevel = '/home/raul/worktrees/happy-nvim/feat-v1',
      -- In a worktree, git_dir is .git/worktrees/<name> under the COMMON dir.
      git_dir = '/home/raul/projects/happy-nvim/.git/worktrees/feat-v1',
      common_dir = '/home/raul/projects/happy-nvim/.git',
    })
    assert.are.equal('happy-nvim-wt-feat-v1', id)
  end)

  it('falls back to cwd slug when not a git repo', function()
    local id = project._derive_id({
      toplevel = nil,
      git_dir = nil,
      common_dir = nil,
      cwd = '/tmp/scratch',
    })
    assert.are.equal('tmp-scratch', id)
  end)
end)

describe('tmux.project.session_name', function()
  local project = require('tmux.project')

  it('prefixes the id with "cc-"', function()
    local name = project.session_name('happy-nvim')
    assert.are.equal('cc-happy-nvim', name)
  end)
end)
