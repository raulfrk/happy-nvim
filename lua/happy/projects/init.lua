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
end

return M
