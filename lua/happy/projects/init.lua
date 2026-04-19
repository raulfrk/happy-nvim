-- lua/happy/projects/init.lua
local M = {}

function M.setup(opts)
  opts = opts or {}
  local status = require('happy.projects.status')
  local picker = require('happy.projects.picker')

  -- migration on startup (scheduled to not block UI)
  vim.schedule(function()
    pcall(function() require('happy.projects.migrate').run() end)
  end)

  -- status poll
  status.start_timer()

  -- keymaps
  vim.keymap.set('n', '<leader>P', function() picker.open() end,
    { desc = 'Projects picker' })
  vim.keymap.set('n', '<leader>Pa', function()
    vim.ui.input({ prompt = 'Add project (/path or host:path): ' }, function(input)
      if not input or input == '' then return end
      local parsed
      if input:sub(1, 1) == '/' then
        parsed = { kind = 'local', path = input }
      else
        local h, p = input:match('^([^:]+):(.+)$')
        if h and p then parsed = { kind = 'remote', host = h, path = p } end
      end
      if not parsed then
        vim.notify('cannot parse input', vim.log.levels.WARN); return
      end
      local id = require('happy.projects.registry').add(parsed)
      if parsed.kind == 'remote' then
        pcall(function() require('happy.projects.remote').provision(id) end)
      end
      vim.notify('added ' .. id, vim.log.levels.INFO)
    end)
  end, { desc = 'Add project' })
  vim.keymap.set('n', '<leader>Pp', function() picker.open({ title = 'Peek' }) end,
    { desc = 'Peek project' })

  local function current_remote_id()
    local reg = require('happy.projects.registry')
    local id = reg.add({ kind = 'local', path = vim.fn.getcwd() })
    local entry = reg.get(id)
    if entry.kind ~= 'remote' then
      vim.notify('current project is not remote', vim.log.levels.WARN); return nil
    end
    return id
  end

  vim.keymap.set('n', '<leader>Cc', function()
    local id = current_remote_id()
    if id then require('happy.projects.remote').capture(id) end
  end, { desc = 'Capture remote pane -> claude sandbox' })
  vim.keymap.set('n', '<leader>Ct', function()
    local id = current_remote_id()
    if id then require('happy.projects.remote').toggle_tail(id) end
  end, { desc = 'Toggle remote tail-pipe to sandbox' })
  vim.keymap.set('n', '<leader>Cl', function()
    local id = current_remote_id(); if not id then return end
    vim.ui.input({ prompt = 'Remote path to pull: ' }, function(p)
      if p and p ~= '' then require('happy.projects.remote').pull(id, p) end
    end)
  end, { desc = 'Pull remote file to sandbox (scp)' })
  vim.keymap.set('v', '<leader>Cs', function()
    local id = current_remote_id()
    if id then require('happy.projects.remote').send_selection(id) end
  end, { desc = 'Send visual selection to sandbox' })

  -- commands
  vim.api.nvim_create_user_command('HappyProjectAdd', function(args)
    local input = args.args
    local parsed
    if input:sub(1, 1) == '/' then
      parsed = { kind = 'local', path = input }
    else
      local h, p = input:match('^([^:]+):(.+)$')
      if h and p then parsed = { kind = 'remote', host = h, path = p } end
    end
    if not parsed then return vim.notify('cannot parse', vim.log.levels.WARN) end
    require('happy.projects.registry').add(parsed)
  end, { nargs = 1 })
  vim.api.nvim_create_user_command('HappyProjectForget', function(args)
    require('happy.projects.registry').forget(args.args)
  end, { nargs = 1 })

  local function run_wt_script(script, path)
    local scratch = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(scratch, ('[%s %s]'):format(script, path))
    vim.cmd('sbuffer ' .. scratch)
    vim.bo[scratch].buftype = 'nofile'
    local function append(line)
      vim.schedule(function()
        vim.api.nvim_buf_set_lines(scratch, -1, -1, false, { line })
      end)
    end
    vim.system({ 'bash', 'scripts/' .. script, path }, {
      stdout = function(_, data) if data then append(data) end end,
      stderr = function(_, data) if data then append('ERR: ' .. data) end end,
    }, function(out)
      append(('=== exit %d ==='):format(out.code))
    end)
  end

  vim.api.nvim_create_user_command('HappyWtProvision', function(args)
    run_wt_script('wt-claude-provision.sh', args.args)
  end, { nargs = 1, complete = 'file' })

  vim.api.nvim_create_user_command('HappyWtCleanup', function(args)
    run_wt_script('wt-claude-cleanup.sh', args.args)
  end, { nargs = 1, complete = 'file' })
end

return M
