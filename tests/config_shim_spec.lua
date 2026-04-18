-- tests/config_shim_spec.lua
-- Guards the compat shim added in lua/config/options.lua for the deprecated
-- vim.treesitter.language.ft_to_lang API. telescope.nvim 0.1.8 still calls
-- it; nvim 0.11+ removed it. Shim aliases it to get_lang.

describe('vim.treesitter.language.ft_to_lang compat shim', function()
  before_each(function()
    -- Re-source options.lua to install the shim in this spec's env.
    package.loaded['config.options'] = nil
    dofile(vim.fn.getcwd() .. '/lua/config/options.lua')
  end)

  it('ft_to_lang is callable after options.lua loads', function()
    assert.is_function(vim.treesitter.language.ft_to_lang)
  end)

  it('ft_to_lang resolves a known filetype to a language', function()
    -- 'lua' -> 'lua'. Any nvim build that bundles the lua treesitter grammar
    -- (ours does) returns 'lua' from get_lang. If this fails, the shim is
    -- wired wrong OR upstream renamed get_lang.
    local lang = vim.treesitter.language.ft_to_lang('lua')
    assert.are.equal('lua', lang)
  end)

  it('ft_to_lang prefers native impl when present (idempotent shim)', function()
    -- If upstream nvim re-adds ft_to_lang natively, the shim (`= x or y`)
    -- is a no-op — don't clobber. Simulate by stashing a sentinel first.
    local sentinel = function()
      return 'sentinel'
    end
    vim.treesitter.language.ft_to_lang = sentinel
    package.loaded['config.options'] = nil
    dofile(vim.fn.getcwd() .. '/lua/config/options.lua')
    assert.are.equal('sentinel', vim.treesitter.language.ft_to_lang())
    -- Restore so later specs don't see the sentinel
    vim.treesitter.language.ft_to_lang = nil
    package.loaded['config.options'] = nil
    dofile(vim.fn.getcwd() .. '/lua/config/options.lua')
  end)
end)
