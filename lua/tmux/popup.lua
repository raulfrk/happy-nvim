-- lua/tmux/popup.lua — wrappers around `tmux display-popup`.
-- Async subprocess contract lives in lua/tmux/_popup.lua; we just
-- bind the commands.
local M = {}
local _popup = require('tmux._popup')

local function guard(bin, hint)
  if vim.fn.executable(bin) == 1 then
    return true
  end
  vim.notify(('%s not found on $PATH. Install: %s'):format(bin, hint), vim.log.levels.WARN)
  return false
end

function M.lazygit()
  if
    not guard(
      'lazygit',
      'brew install lazygit / apt install lazygit / https://github.com/jesseduffield/lazygit'
    )
  then
    return
  end
  _popup.open('80%', '80%', 'lazygit')
end

function M.scratch()
  local root = vim.fn.system({ 'git', 'rev-parse', '--show-toplevel' })
  root = root:gsub('%s+$', '')
  if root == '' then
    root = vim.fn.getcwd()
  end
  -- Shell pick: $SHELL → zsh → bash → sh. Minimal VMs sometimes lack zsh;
  -- fall back gracefully instead of flashing a dead popup.
  local shell = os.getenv('SHELL')
  if not shell or shell == '' or vim.fn.executable(shell) == 0 then
    shell = nil
    for _, s in ipairs({ 'zsh', 'bash', 'sh' }) do
      if vim.fn.executable(s) == 1 then
        shell = s
        break
      end
    end
  end
  if not shell then
    vim.notify('no shell found on $PATH (tried $SHELL, zsh, bash, sh)', vim.log.levels.ERROR)
    return
  end
  _popup.open('80%', '80%', 'cd ' .. vim.fn.shellescape(root) .. ' && ' .. shell .. ' -l')
end

function M.btop()
  if
    not guard('btop', 'brew install btop / apt install btop / https://github.com/aristocratos/btop')
  then
    return
  end
  _popup.open('80%', '80%', 'btop')
end

-- Keymaps registered statically in lua/plugins/tmux.lua so which-key
-- sees them on <leader> before the module is loaded.
function M.setup() end

return M
