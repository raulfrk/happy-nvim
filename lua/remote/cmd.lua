-- lua/remote/cmd.lua — <leader>sc ad-hoc remote cmd runner.
local M = {}

local function append_to_buf(buf, lines)
  vim.schedule(function()
    if not vim.api.nvim_buf_is_valid(buf) then
      return
    end
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, -1, -1, false, lines)
    vim.bo[buf].modifiable = false
    local win = vim.fn.bufwinid(buf)
    if win ~= -1 then
      vim.api.nvim_win_set_cursor(win, { vim.api.nvim_buf_line_count(buf), 0 })
    end
  end)
end

function M._stream_to_scratch(host, cmd)
  local buf = vim.api.nvim_create_buf(false, true)
  local name = ('[ssh %s: %s]'):format(host, cmd)
  vim.api.nvim_buf_set_name(buf, name)
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'wipe'
  vim.cmd('sbuffer ' .. buf)

  local handle
  handle = vim.system(
    { 'ssh', host, cmd },
    {
      text = true,
      stdout = function(_, data)
        if data then
          append_to_buf(buf, vim.split(data, '\n', { trimempty = true }))
        end
      end,
      stderr = function(_, data)
        if data then
          local prefixed = vim.tbl_map(function(l)
            return 'ERR: ' .. l
          end, vim.split(data, '\n', { trimempty = true }))
          append_to_buf(buf, prefixed)
        end
      end,
    },
    vim.schedule_wrap(function(out)
      append_to_buf(buf, { ('--- exit %d ---'):format(out.code) })
    end)
  )

  vim.keymap.set('n', '<C-c>', function()
    if handle and not handle:is_closing() then
      handle:kill('sigterm')
    end
  end, { buffer = buf, desc = 'kill remote cmd' })
  vim.keymap.set('n', 'q', function()
    vim.cmd('bd!')
  end, { buffer = buf, desc = 'close' })
end

function M.run_cmd()
  vim.ui.input({ prompt = 'Remote cmd: ' }, function(cmd)
    if not cmd or cmd == '' then
      return
    end
    require('remote.hosts').pick(function(host)
      M._stream_to_scratch(host, cmd)
    end)
  end)
end

return M
