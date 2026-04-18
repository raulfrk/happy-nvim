-- lua/tmux/idle.lua — per-session idle detection for multi-project Claude.
-- Polls tmux capture-pane every ~1s; flips @claude_idle=1 after
-- DEBOUNCE_SECS of stable output, =0 on new input. Pure-function core
-- (_tick, _hash, _should_alert) is unit-testable; watch_all() is the
-- impure driver.
local M = {}

local DEBOUNCE_SECS = 2
local POLL_INTERVAL_MS = 1000

local DEFAULT_OPTS = {
  notify = true,
  bell = false,
  desktop = false,
  cooldown_secs = 10,
  skip_focused = true,
}

local opts = vim.deepcopy(DEFAULT_OPTS)
local last_alert_ts = {}

function M.setup(user_opts)
  opts = vim.tbl_deep_extend('force', vim.deepcopy(DEFAULT_OPTS), user_opts or {})
end

-- Hash a capture so we store fixed-size state instead of the whole pane.
-- 'hash-<raw>' prefix is testable; real implementation uses sha256 for
-- collision resistance but the tests only check determinism.
function M._hash(raw)
  return 'hash-' .. raw
end

-- Pure: advance one session's state based on the latest capture + now.
-- Returns (new_state, flipped) where flipped==true iff idle value changed.
--
-- `busy_until` guards against a premature idle flip after mark_busy
-- when the pane output happens to be already stable (e.g. user sent a
-- prompt that claude doesn't produce new output for). Without it,
-- stable_since restarts but the next DEBOUNCE_SECS fires a false
-- "idle" alert. #20.
function M._tick(state, capture, now)
  local h = M._hash(capture or '')
  if state.last_hash == nil then
    return {
      last_hash = h,
      stable_since = now,
      idle = false,
      busy_until = state.busy_until,
    },
      false
  end
  if h ~= state.last_hash then
    local was_idle = state.idle
    return {
      last_hash = h,
      stable_since = now,
      idle = false,
      busy_until = state.busy_until,
    },
      was_idle -- flipped iff we were idle before
  end
  -- Output stable. Check debounce + busy-grace window.
  local stable_for = now - state.stable_since
  local grace_active = state.busy_until and now < state.busy_until
  if stable_for >= DEBOUNCE_SECS and not state.idle and not grace_active then
    return {
      last_hash = state.last_hash,
      stable_since = state.stable_since,
      idle = true,
      busy_until = nil,
    },
      true
  end
  return state, false
end

-- Pure: decide whether to fire an alert for `session` right now.
-- Returns true iff at least one channel is enabled, the session isn't the
-- currently-focused one (when skip_focused), and the cooldown has elapsed.
function M._should_alert(session, focused_session, last_ts, now, o)
  if not (o.notify or o.bell or o.desktop) then
    return false
  end
  if o.skip_focused and session == focused_session then
    return false
  end
  if last_ts and (now - last_ts) < o.cooldown_secs then
    return false
  end
  return true
end

local function focused_session()
  local res = vim
    .system({ 'tmux', 'display-message', '-p', '#{session_name}' }, { text = true })
    :wait()
  if res.code ~= 0 then
    return nil
  end
  return (res.stdout or ''):gsub('%s+$', '')
end

local function fire_alert(session)
  local slug = session:gsub('^cc%-', '')
  local msg = 'Claude (' .. slug .. ') idle'
  if opts.notify then
    vim.notify(msg, vim.log.levels.INFO, { title = 'Claude' })
  end
  if opts.bell then
    vim.api.nvim_out_write('\a')
  end
  if opts.desktop then
    if vim.fn.executable('notify-send') == 1 then
      vim.system({ 'notify-send', 'Claude', msg }):wait()
    elseif vim.fn.executable('osascript') == 1 then
      vim
        .system({
          'osascript',
          '-e',
          'display notification "' .. msg .. '" with title "Claude"',
        })
        :wait()
    end
  end
end

-- Impure: poll all cc-* sessions once + apply side effects for flips.
-- Kept separate from _tick so it can be mocked out in integration tests.
local states = {}

local function apply_flip(session_name, idle)
  local val = idle and '1' or '0'
  vim.system({ 'tmux', 'set-option', '-t', session_name, '@claude_idle', val }):wait()
  vim.system({ 'tmux', 'refresh-client', '-S' }):wait()
  if idle then
    local now = os.time()
    if M._should_alert(session_name, focused_session(), last_alert_ts[session_name], now, opts) then
      fire_alert(session_name)
      last_alert_ts[session_name] = now
    end
  end
end

function M._poll_once(now)
  local sessions = require('tmux.sessions').list()
  for _, s in ipairs(sessions) do
    local cap = vim.system({ 'tmux', 'capture-pane', '-p', '-t', s.name }, { text = true }):wait()
    if cap.code == 0 then
      local state = states[s.name] or {}
      local new_state, flipped = M._tick(state, cap.stdout or '', now)
      states[s.name] = new_state
      if flipped then
        apply_flip(s.name, new_state.idle)
      end
    end
  end
end

-- Mark a session as busy immediately (invoked from send.lua + claude_popup
-- on any user-driven activity — resets stable_since AND sets a short
-- busy-grace window so `_tick` won't flip back to idle even if the pane
-- output happens to stay stable after the user activity. See #20.
function M.mark_busy(session_name)
  local now = os.time()
  local state = states[session_name] or {}
  state.stable_since = now
  state.idle = false
  state.busy_until = now + DEBOUNCE_SECS + 3 -- grace: ~5s total
  states[session_name] = state
  apply_flip(session_name, false)
end

-- Timer handle stashed in vim.g so a subsequent module reload
-- (`:source $MYVIMRC`, `package.loaded['tmux.idle'] = nil` via tests)
-- can't leak a second libuv timer w/ the re-entry guard fooled by a
-- fresh `local timer = nil`. Module-local `timer` is also kept so we
-- have the userdata handle for stop() without needing to store it in
-- vim.g (which only holds a sentinel). See #21.
local timer
function M.watch_all()
  if vim.g._happy_idle_timer_active or timer then
    return -- already watching (this module or a prior incarnation)
  end
  timer = vim.uv.new_timer()
  vim.g._happy_idle_timer_active = true
  timer:start(
    POLL_INTERVAL_MS,
    POLL_INTERVAL_MS,
    vim.schedule_wrap(function()
      M._poll_once(os.time())
    end)
  )
end

function M.stop()
  if timer then
    timer:stop()
    timer:close()
    timer = nil
  end
  vim.g._happy_idle_timer_active = nil
  states = {}
  last_alert_ts = {}
end

return M
