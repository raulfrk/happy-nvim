-- lua/remote/browse.lua
local M = {}

local BINARY_EXTS = {
  png = true,
  jpg = true,
  jpeg = true,
  gif = true,
  pdf = true,
  zip = true,
  tar = true,
  gz = true,
  xz = true,
  bz2 = true,
  exe = true,
  so = true,
  o = true,
  a = true,
  bin = true,
  mp4 = true,
  mov = true,
  mp3 = true,
  flac = true,
  woff = true,
  woff2 = true,
  ttf = true,
  ico = true,
  jar = true,
  class = true,
}

local MAX_SIZE = 5 * 1024 * 1024

function M._fast_path_ext(path)
  local lower = path:lower()
  -- check last suffix then all compound suffixes
  for ext in lower:gmatch('%.([^.]+)') do
    if BINARY_EXTS[ext] then
      return true
    end
  end
  return false
end

function M._build_mime_probe_cmd(host, rpath)
  local q = require('remote.util').shellquote(rpath)
  return { 'ssh', host, 'file -b --mime-encoding ' .. q }
end

function M._build_size_probe_cmd(host, rpath)
  local q = require('remote.util').shellquote(rpath)
  return { 'ssh', host, 'stat -c %s ' .. q .. ' 2>/dev/null || wc -c < ' .. q }
end

function M._is_binary_mime(out)
  local trimmed = out:gsub('%s+$', '')
  if trimmed == 'binary' then
    return true
  end
  -- Also handle full mime-type output (e.g. `application/octet-stream;
  -- charset=binary`) — useful when helpers pass through --mime (not just
  -- --mime-encoding).
  return trimmed:find('charset=binary') ~= nil
end

local function check_remote_binary(host, rpath)
  -- Event-loop-friendly ssh calls; see lua/remote/util.lua for rationale.
  local run = require('remote.util').run
  local mime = run(M._build_mime_probe_cmd(host, rpath), { text = true })
  if mime.code == 0 and M._is_binary_mime(mime.stdout or '') then
    return true, 'binary'
  end
  local sz = run(M._build_size_probe_cmd(host, rpath), { text = true })
  if sz.code == 0 then
    local n = tonumber((sz.stdout or ''):gsub('%s+', '')) or 0
    if n > MAX_SIZE then
      return true, string.format('%dMB > 5MB cap', math.floor(n / 1024 / 1024))
    end
  end
  return false
end

function M.open(host, rpath)
  if M._fast_path_ext(rpath) and not vim.b.happy_force_binary then
    vim.notify(
      string.format(
        'Binary extension detected for %s. Use <leader>sO to force.',
        rpath
      ),
      vim.log.levels.WARN
    )
    return
  end
  if not vim.b.happy_force_binary then
    local blocked, reason = check_remote_binary(host, rpath)
    if blocked then
      vim.notify(
        string.format('%s: %s. <leader>sO to force.', rpath, reason),
        vim.log.levels.WARN
      )
      return
    end
  end
  require('remote.ssh_buffer').open(host, rpath)
end

function M.browse()
  require('remote.ssh_buffer').browse_prompt()
end

function M.find()
  require('remote.hosts').pick(function(host)
    vim.ui.input({ prompt = 'Path: ' }, function(path)
      if not path or path == '' then
        return
      end
      vim.ui.input({ prompt = 'Name pattern: ' }, function(pat)
        if not pat or pat == '' then
          return
        end
        local sq = require('remote.util').shellquote
        local cmd =
          { 'ssh', host, string.format('find %s -name %s 2>/dev/null', sq(path), sq(pat)) }
        local res = require('remote.util').run(cmd, { text = true })
        if res.code ~= 0 then
          vim.notify('ssh ' .. host .. ' failed: ' .. (res.stderr or ''), vim.log.levels.ERROR)
          return
        end
        local results = {}
        for line in (res.stdout or ''):gmatch('[^\n]+') do
          table.insert(results, line)
        end
        local pickers = require('telescope.pickers')
        local finders = require('telescope.finders')
        local actions = require('telescope.actions')
        local action_state = require('telescope.actions.state')
        local conf = require('telescope.config').values

        pickers
          .new({}, {
            prompt_title = string.format('find %s:%s  %s', host, path, pat),
            finder = finders.new_table({ results = results }),
            sorter = conf.generic_sorter({}),
            attach_mappings = function(bufnr, map)
              actions.select_default:replace(function()
                actions.close(bufnr)
                local sel = action_state.get_selected_entry()
                if not sel then
                  return
                end
                M.open(host, sel[1])
              end)
              map({ 'i', 'n' }, '<C-g>', function()
                local sel = action_state.get_selected_entry()
                if not sel then
                  return
                end
                actions.close(bufnr)
                vim.ui.input({ prompt = 'grep pattern: ' }, function(pat)
                  if not pat or pat == '' then
                    return
                  end
                  require('remote.grep').run({ host = host, path = sel[1], pattern = pat })
                end)
              end)
              map({ 'i', 'n' }, '<C-t>', function()
                local sel = action_state.get_selected_entry()
                if not sel then
                  return
                end
                actions.close(bufnr)
                require('remote.tail').start(host, sel[1])
              end)
              map({ 'i', 'n' }, '<C-v>', function()
                local sel = action_state.get_selected_entry()
                if not sel then
                  return
                end
                actions.close(bufnr)
                local sq = require('remote.util').shellquote
                require('tmux._popup').open(
                  '85%',
                  '85%',
                  table.concat(
                    require('remote.ssh_exec').argv(host, 'less +F ' .. sq(sel[1])),
                    ' '
                  )
                )
              end)
              map({ 'i', 'n' }, '<C-y>', function()
                local sel = action_state.get_selected_entry()
                if not sel then
                  return
                end
                vim.fn.setreg('+', host .. ':' .. sel[1])
                vim.notify(('yanked %s:%s'):format(host, sel[1]), vim.log.levels.INFO)
              end)
              return true
            end,
          })
          :find()
      end)
    end)
  end)
end

function M.force_binary()
  vim.b.happy_force_binary = 1
  vim.notify('binary guard disabled for this buffer; re-open with :e to retry', vim.log.levels.INFO)
end

-- Public alias matching test expectations.
M.open_path = M.open

function M._is_binary(host, rpath)
  if vim.b.happy_force_binary then
    return false
  end
  if M._fast_path_ext(rpath) then
    return false
  end
  local util = require('remote.util')
  local sq = util.shellquote
    or function(s)
      return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
    end
  local cmd = { 'ssh', host, 'file -b --mime-encoding ' .. sq(rpath) }
  local mime = util.run(cmd, { text = true })
  return mime.code == 0 and M._is_binary_mime(mime.stdout or '')
end

function M._set_override(on)
  vim.b.happy_force_binary = on and true or nil
end

function M.setup() end -- keymaps in lua/plugins/remote.lua

M._picker_actions = { '<Enter>', '<C-g>', '<C-t>', '<C-v>', '<C-y>' }

return M
