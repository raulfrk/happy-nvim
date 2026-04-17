-- lua/happy/health.lua
local M = {}

local function exec(cmd)
  local res = vim.system(cmd, { text = true }):wait()
  return res.code == 0, res.stdout or '', res.stderr or ''
end

function M.check()
  local h = vim.health
  h.start('happy-nvim: core')
  if vim.fn.has('nvim-0.10') == 1 then
    h.ok('Neovim >= 0.10')
  else
    h.error('Neovim >= 0.10 required')
  end

  h.start('happy-nvim: local CLIs')
  for _, cli in ipairs({ 'rg', 'fd', 'stylua', 'selene', 'git' }) do
    if vim.fn.executable(cli) == 1 then
      h.ok(cli .. ' found')
    else
      h.warn(cli .. ' not found (install for full feature set)')
    end
  end

  h.start('happy-nvim: tmux')
  if vim.env.TMUX == nil or vim.env.TMUX == '' then
    h.info('not running inside tmux — tmux/Claude features disabled')
  else
    local ok, ver = exec({ 'tmux', '-V' })
    if ok then
      h.ok('tmux: ' .. ver:gsub('%s+$', ''))
    end
    local _, passthrough = exec({ 'tmux', 'show-option', '-v', '-g', 'allow-passthrough' })
    if passthrough:match('on') then
      h.ok('tmux allow-passthrough=on (OSC 52 host clipboard will work)')
    else
      h.warn('tmux allow-passthrough off — host clipboard via OSC 52 may be stripped. Set: tmux set -g allow-passthrough on')
    end
    local _, setclip = exec({ 'tmux', 'show-option', '-v', '-g', 'set-clipboard' })
    if setclip:match('on') or setclip:match('external') then
      h.ok('tmux set-clipboard on/external')
    else
      h.warn('tmux set-clipboard should be `on` or `external`')
    end
  end

  h.start('happy-nvim: mosh')
  if vim.env.MOSH_CONNECTION ~= nil then
    local ok, ver = exec({ 'mosh', '--version' })
    if ok then
      local major, minor = ver:match('mosh (%d+)%.(%d+)')
      if major and minor and (tonumber(major) > 1 or (tonumber(major) == 1 and tonumber(minor) >= 4)) then
        h.ok('mosh ' .. major .. '.' .. minor .. ' (>= 1.4 required for OSC 52 passthrough)')
      else
        h.warn('mosh < 1.4 — OSC 52 will be stripped, host clipboard unavailable')
      end
    end
  else
    h.info('not a mosh session')
  end

  h.start('happy-nvim: ssh')
  if vim.env.SSH_AUTH_SOCK ~= nil and vim.env.SSH_AUTH_SOCK ~= '' then
    h.ok('ssh-agent socket present')
  else
    h.warn('SSH_AUTH_SOCK not set — remote ops will fail on password-only hosts')
  end

  h.start('happy-nvim: XDG dirs')
  local state = vim.fn.stdpath('state')
  if vim.fn.isdirectory(state) == 1 then
    h.ok('state dir: ' .. state)
  else
    h.warn('state dir missing: ' .. state)
  end
end

return M
