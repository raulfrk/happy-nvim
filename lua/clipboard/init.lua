-- lua/clipboard/init.lua — OSC 52 dual-clipboard hook (spec §5.2)
local M = {}

-- 74KB cap on base64 payload (some terminals reject larger)
local MAX_B64 = 74 * 1024

function M._should_emit()
  return (vim.env.SSH_TTY ~= nil and vim.env.SSH_TTY ~= '')
    or (vim.env.TMUX ~= nil and vim.env.TMUX ~= '')
end

function M._encode_osc52(content)
  local b64 = vim.base64.encode(content)
  if #b64 > MAX_B64 then
    return nil
  end
  return string.format('\027]52;c;%s\007', b64)
end

function M._emit(seq)
  -- selene: allow(incorrect_standard_library_use)
  io.stdout:write(seq)
  -- selene: allow(incorrect_standard_library_use)
  io.stdout:flush()
end

function M.setup()
  local aug = vim.api.nvim_create_augroup('happy_clipboard', { clear = true })
  vim.api.nvim_create_autocmd('TextYankPost', {
    group = aug,
    callback = function()
      if vim.v.event.operator ~= 'y' then
        return
      end
      if not M._should_emit() then
        return
      end
      local content = table.concat(vim.v.event.regcontents, '\n')
      local seq = M._encode_osc52(content)
      if seq == nil then
        vim.notify(
          'happy-nvim: yank too large for OSC52 (host clipboard skipped)',
          vim.log.levels.WARN
        )
        return
      end
      M._emit(seq)
    end,
  })
end

return M
