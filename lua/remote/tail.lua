-- lua/remote/tail.lua — <leader>sT log tailer.
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

local function shell_escape(s)
  return "'" .. s:gsub("'", "'\\''") .. "'"
end

function M._stream_tail(host, path)
  local buf = vim.api.nvim_create_buf(false, true)
  local name = ('[tail %s:%s]'):format(host, path)
  vim.api.nvim_buf_set_name(buf, name)
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'wipe'
  vim.cmd('sbuffer ' .. buf)

  local remote_cmd = 'tail -F ' .. shell_escape(path)

  local handle
  handle = vim.system(
    { 'ssh', host, remote_cmd },
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
      append_to_buf(buf, { ('--- tail ended (exit %d) ---'):format(out.code) })
    end)
  )

  vim.keymap.set('n', 'q', function()
    if handle and not handle:is_closing() then
      handle:kill('sigterm')
    end
    vim.cmd('bd!')
  end, { buffer = buf, desc = 'close tail + kill ssh' })
end

function M.tail_log()
  require('remote.hosts').pick(function(host)
    vim.ui.input({ prompt = 'Remote log path: ' }, function(path)
      if not path or path == '' then
        return
      end
      M._stream_tail(host, path)
    end)
  end)
end

return M
