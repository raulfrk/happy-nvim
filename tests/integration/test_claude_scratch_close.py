"""Regression: lua/tmux/claude.lua:M.open_scratch used vim.system():wait()
inside a fast-event on-close callback -> E5560. Guard by wrapping the
cleanup kill in vim.schedule_wrap.

This test drives M.open_scratch() w/ tmux stubbed out + simulates the
on-close callback being invoked. If the cleanup path runs :wait() in a
fast-event context, nvim logs E5560 to stderr before exiting.
"""
import os
import subprocess
import textwrap


def test_scratch_close_callback_is_scheduled():
    repo = os.getcwd()
    snippet = textwrap.dedent(f'''
        local repo = '{repo}'
        vim.opt.rtp:prepend(repo)
        -- Stub tmux.project so session_for_cwd doesn't crash on missing repo config.
        package.loaded['tmux.project'] = {{ session_name = function() return 'cc-test' end }}
        -- Stub registry to produce a deterministic id.
        package.loaded['happy.projects.registry'] = {{
          add = function() return 'test' end,
          touch = function() end,
          get = function() return {{ kind = 'local' }} end,
        }}
        vim.env.TMUX = 'fake'
        -- Stub vim.system:
        --   new-session -> fake ok object (sync stub)
        --   display-popup -> capture the on-close callback (cb); return fake obj
        --   kill-session -> use REAL vim.system so :wait() in fast-event raises E5560
        local real_system = vim.system
        local captured_cb = nil
        vim.system = function(args, opts, cb)
          if args[2] == 'new-session' then
            return {{ wait = function() return {{ code = 0, stdout = '', stderr = '' }} end }}
          elseif args[2] == 'display-popup' then
            captured_cb = cb
            return {{ wait = function() return {{ code = 0, stdout = '', stderr = '' }} end }}
          else
            -- kill-session: use real vim.system so :wait() in fast-event raises E5560
            return real_system(args, opts, cb)
          end
        end
        require('tmux.claude').open_scratch()
        assert(captured_cb ~= nil, 'on-close callback was not captured')
        -- Simulate libuv calling the on-close callback from a fast-event context.
        -- vim.schedule_wrap defers to the main loop, so the cleanup :wait()
        -- runs safely. Without the wrap, vim.system():wait() raises E5560 here.
        local ok, err = pcall(function()
          local timer = vim.uv.new_timer()
          local done = false
          timer:start(0, 0, function()
            local ok2, e = pcall(captured_cb, {{ code = 0 }})
            timer:stop(); timer:close()
            if not ok2 then
              vim.schedule(function()
                io.stderr:write('FAIL: ' .. tostring(e) .. '\\n')
                vim.cmd('cq')
              end)
            else
              vim.schedule(function() done = true end)
            end
          end)
          vim.wait(1000, function() return done end, 20)
        end)
        if not ok then
          io.stderr:write('FAIL: ' .. tostring(err) .. '\\n')
          vim.cmd('cq')
        end
        vim.cmd('qa!')
    ''')
    proc = subprocess.run(
        ['nvim', '--clean', '--headless', '-u', 'NONE', '-c', f'lua {snippet}'],
        capture_output=True, text=True, timeout=20,
    )
    assert 'E5560' not in proc.stderr, f'fast-event violation: {proc.stderr}'
    assert proc.returncode == 0, f'nvim exited {proc.returncode}: {proc.stderr}'
