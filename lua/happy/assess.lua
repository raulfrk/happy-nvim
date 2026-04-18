-- lua/happy/assess.lua — :HappyAssess user command.
-- Spawns scripts/assess.sh; streams stdout+stderr into a scratch buffer.
local M = {}

local function open_buffer()
  vim.cmd('new')
  local buf = vim.api.nvim_get_current_buf()
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].swapfile = false
  vim.api.nvim_buf_set_name(buf, 'happy-assess')
  vim.bo[buf].filetype = 'log'
  return buf
end

local function append_line(buf, line)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  -- Replace the first empty line produced at buffer creation on first append
  local count = vim.api.nvim_buf_line_count(buf)
  if count == 1 and vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] == '' then
    vim.api.nvim_buf_set_lines(buf, 0, 1, false, { line })
  else
    vim.api.nvim_buf_set_lines(buf, -1, -1, false, { line })
  end
  -- Follow tail: move cursor in any window showing this buffer
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(win) == buf then
      vim.api.nvim_win_set_cursor(win, { vim.api.nvim_buf_line_count(buf), 0 })
    end
  end
end

function M.run()
  local repo_root = vim.fn.getcwd()
  local script = repo_root .. '/scripts/assess.sh'
  if vim.fn.filereadable(script) ~= 1 then
    vim.notify(
      'happy-assess: scripts/assess.sh not found under cwd ' .. repo_root,
      vim.log.levels.ERROR
    )
    return
  end
  local buf = open_buffer()
  local tail_buf = ''

  local function on_chunk(_, chunk)
    if chunk == nil or chunk == '' then
      return
    end
    tail_buf = tail_buf .. chunk
    -- Emit complete lines; keep the trailing partial line for next chunk
    local lines = {}
    local start = 1
    while true do
      local nl = tail_buf:find('\n', start, true)
      if not nl then
        break
      end
      table.insert(lines, tail_buf:sub(start, nl - 1))
      start = nl + 1
    end
    tail_buf = tail_buf:sub(start)
    if #lines > 0 then
      vim.schedule(function()
        for _, line in ipairs(lines) do
          append_line(buf, line)
        end
      end)
    end
  end

  vim.system({ 'bash', script }, {
    cwd = repo_root,
    text = true,
    stdout = on_chunk,
    stderr = on_chunk,
  }, function(res)
    vim.schedule(function()
      if tail_buf ~= '' then
        append_line(buf, tail_buf)
      end
      append_line(buf, '')
      append_line(buf, string.format(':HappyAssess finished (exit code %d)', res.code or -1))
    end)
  end)
end

function M.setup()
  vim.api.nvim_create_user_command('HappyAssess', function()
    M.run()
  end, { desc = 'Run scripts/assess.sh and stream output into a scratch buffer' })
end

return M
