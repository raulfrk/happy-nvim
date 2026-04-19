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
  local osc = string.format('\027]52;c;%s\027\\', b64)
  if vim.env.TMUX and vim.env.TMUX ~= '' then
    osc = '\027Ptmux;' .. osc:gsub('\027', '\027\027') .. '\027\\'
  end
  return osc
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

  vim.api.nvim_create_user_command('HappyCheckClipboard', function()
    local payload = 'HAPPY-CLIPBOARD-TEST-' .. os.time()
    local seq = M._encode_osc52(payload)
    if not seq then
      vim.notify('OSC 52 encoding failed (payload too large?)', vim.log.levels.ERROR)
      return
    end
    M._emit(seq)
    vim.notify(
      'Emitted OSC 52 test payload. Paste in host terminal / browser — '
        .. 'expect `'
        .. payload
        .. '`.',
      vim.log.levels.INFO
    )
  end, { desc = 'Emit a known OSC 52 payload + print expected string' })
end

return M
