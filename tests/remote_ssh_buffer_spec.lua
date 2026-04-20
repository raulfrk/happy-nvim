describe('remote.ssh_buffer', function()
  local ssh_buffer
  before_each(function()
    package.loaded['remote.ssh_buffer'] = nil
    package.loaded['remote.hosts'] = nil
    package.loaded['remote.ssh_exec'] = nil
    package.loaded['remote.browse'] = nil
    package.loaded['remote.util'] = nil
  end)

  it('_parse_bufname splits host and absolute path', function()
    ssh_buffer = require('remote.ssh_buffer')
    local host, path = ssh_buffer._parse_bufname('ssh://host01/var/log/app.log')
    assert.are.equal('host01', host)
    assert.are.equal('/var/log/app.log', path)
  end)

  it('_parse_bufname preserves ~ paths for later expansion', function()
    ssh_buffer = require('remote.ssh_buffer')
    local host, path = ssh_buffer._parse_bufname('ssh://h/~/.bashrc')
    assert.are.equal('h', host)
    assert.are.equal('~/.bashrc', path)
  end)

  it('open sets buftype acwrite and readonly=true by default', function()
    ssh_buffer = require('remote.ssh_buffer')
    package.loaded['remote.hosts'] = {
      ensure_home_dir = function()
        return '/home/u'
      end,
      expand_path = function(_, p)
        return p
      end,
    }
    package.loaded['remote.browse'] = {
      _is_binary = function()
        return false
      end,
    }
    package.loaded['remote.ssh_exec'] = {
      run = function()
        return { code = 0, stdout = 'hello\nworld\n', stderr = '' }
      end,
    }
    local buf = ssh_buffer.open('h', '/tmp/x.txt')
    assert.are.equal('acwrite', vim.bo[buf].buftype)
    assert.True(vim.bo[buf].readonly)
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    assert.are.equal('hello', lines[1])
    assert.are.equal('world', lines[2])
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it('toggle_writable flips vim.b.happy_ssh_writable + clears readonly', function()
    ssh_buffer = require('remote.ssh_buffer')
    package.loaded['remote.hosts'] = {
      ensure_home_dir = function()
        return '/h'
      end,
      expand_path = function(_, p)
        return p
      end,
    }
    package.loaded['remote.browse'] = {
      _is_binary = function()
        return false
      end,
    }
    package.loaded['remote.ssh_exec'] = {
      run = function()
        return { code = 0, stdout = '', stderr = '' }
      end,
    }
    local buf = ssh_buffer.open('h', '/tmp/y')
    vim.api.nvim_set_current_buf(buf)
    ssh_buffer.toggle_writable()
    assert.True(vim.b.happy_ssh_writable)
    assert.False(vim.bo[buf].readonly)
    vim.api.nvim_buf_delete(buf, { force = true })
  end)
end)
