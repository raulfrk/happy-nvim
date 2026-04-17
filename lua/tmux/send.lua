-- lua/tmux/send.lua — tmux send-keys + pane discovery helpers
local M = {}

function M._quote_for_send_keys(s)
  -- For shell-level `'...'` wrapping: replace each ' with '\''
  return (s:gsub("'", "'\\''"))
end

function M._build_send_cmd(pane_id, payload)
  return { 'tmux', 'send-keys', '-t', pane_id, '-l', payload }
end

function M._build_enter_cmd(pane_id)
  return { 'tmux', 'send-keys', '-t', pane_id, 'Enter' }
end

function M.get_claude_pane_id()
  local result = vim
    .system({
      'tmux',
      'show-option',
      '-w',
      '-v',
      '-q',
      '@claude_pane_id',
    }, { text = true })
    :wait()
  if result.code ~= 0 then
    return nil
  end
  local id = (result.stdout or ''):gsub('%s+$', '')
  if id == '' then
    return nil
  end
  -- Verify pane is still alive
  local alive = vim.system({ 'tmux', 'list-panes', '-t', id }, { text = true }):wait()
  if alive.code ~= 0 then
    -- Stale; clear the option
    vim.system({ 'tmux', 'set-option', '-w', '-u', '@claude_pane_id' }):wait()
    return nil
  end
  return id
end

function M.set_claude_pane_id(id)
  vim.system({ 'tmux', 'set-option', '-w', '@claude_pane_id', id }):wait()
end

function M.send_to_claude(payload)
  local id = M.get_claude_pane_id()
  if not id then
    vim.notify('No Claude pane registered. Press <leader>cc first.', vim.log.levels.WARN)
    return false
  end
  if #payload > 10 * 1024 then
    local ok = vim.fn.confirm(
      string.format('Send %dKB to Claude pane?', math.floor(#payload / 1024)),
      '&Yes\n&No'
    ) == 1
    if not ok then
      return false
    end
  end
  vim.system(M._build_send_cmd(id, payload)):wait()
  vim.system(M._build_enter_cmd(id)):wait()
  return true
end

return M
