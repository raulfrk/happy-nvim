-- lua/remote/watch_editor.lua — scratch buffer for editing watch
-- patterns on the current tail. Format (one pattern per line):
--   [x] ERROR  :: regex
--   [ ] WARN   :: regex
--   [x] INFO!  :: regex  (the `!` after the level marks oneshot)
-- Lines starting with '#' are comments. Blank lines ignored.
local M = {}
local LEVELS = { DEBUG = true, INFO = true, WARN = true, ERROR = true }

function M._parse_lines(lines)
  local out = {}
  for _, line in ipairs(lines) do
    if line:sub(1, 1) ~= '#' and line:match('%S') then
      local box, lvl, body = line:match('^%[([ x])%]%s+([%w]+!?)%s+::%s+(.+)$')
      if box then
        local oneshot = false
        local level = lvl
        if level:sub(-1) == '!' then
          oneshot = true
          level = level:sub(1, -2)
        end
        if LEVELS[level] then
          table.insert(out, {
            active = box == 'x',
            level = level,
            oneshot = oneshot,
            regex = body,
          })
        end
      end
    end
  end
  return out
end

local function render(host, path, patterns)
  local lines = {
    '# Edit watch patterns for tail — :w to save, q to close',
    '# Format: [x]/[ ] LEVEL[!] :: regex  (! = oneshot)',
    '# host: ' .. host,
    '# path: ' .. path,
    '',
  }
  for _, p in ipairs(patterns) do
    local chk = p.active and '[x]' or '[ ]'
    local lvl = p.level .. (p.oneshot and '!' or '')
    table.insert(lines, ('%s %-6s :: %s'):format(chk, lvl, p.regex))
  end
  return lines
end

function M.open(host, path)
  local watch = require('remote.watch')
  local patterns = watch.list(host, path)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, ('[watch %s:%s]'):format(host, path))
  vim.bo[buf].buftype = 'acwrite'
  vim.bo[buf].bufhidden = 'wipe'
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, render(host, path, patterns))
  vim.api.nvim_create_autocmd('BufWriteCmd', {
    buffer = buf,
    callback = function()
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      local parsed = M._parse_lines(lines)
      local existing = watch.list(host, path)
      for _, e in ipairs(existing) do
        watch.remove(e.id)
      end
      for _, p in ipairs(parsed) do
        watch.add(host, path, p.regex, {
          level = p.level,
          oneshot = p.oneshot,
          active = p.active,
        })
      end
      vim.bo[buf].modified = false
      vim.notify(
        ('saved %d watch patterns for %s:%s'):format(#parsed, host, path),
        vim.log.levels.INFO
      )
    end,
  })
  vim.keymap.set('n', 'q', function()
    vim.cmd('bw!')
  end, { buffer = buf, desc = 'close watch editor' })
  vim.cmd('sbuffer ' .. buf)
end

return M
