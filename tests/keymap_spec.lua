-- tests/keymap_spec.lua
-- Asserts every <leader>* keymap and user command declared by the config is
-- actually registered after VimEnter fires. Catches accidental removal/
-- rename during refactors. Runs in the existing `test` CI job via
-- PlenaryBustedDirectory.
--
-- NOTE: Only globally-registered keymaps are tested here. Buffer-local
-- keymaps (LspAttach, gitsigns on_attach) require an active buffer with an
-- LSP attached and are intentionally excluded — they live in
-- tests/lsp_spec.lua (future). Lazy-loaded keys are registered globally by
-- lazy.nvim at startup via the `keys` spec field.

local EXPECTED_LEADER_KEYS = {
  -- find / files (telescope lazy keys)
  ['<leader>ff'] = 'n',
  ['<leader>fg'] = 'n',
  ['<leader>fb'] = 'n',
  ['<leader>fh'] = 'n',
  ['<leader>fr'] = 'n',
  ['<leader>fs'] = 'n',
  ['<leader>fw'] = 'n',
  -- git (fugitive lazy key — global)
  ['<leader>gs'] = 'n',
  -- LSP formatting (conform lazy key — global; la/lr/dn/dp are buffer-local)
  ['<leader>lf'] = 'n',
  -- harpoon (config function — global)
  ['<leader>ha'] = 'n',
  ['<leader>h1'] = 'n',
  ['<leader>h2'] = 'n',
  ['<leader>h3'] = 'n',
  ['<leader>h4'] = 'n',
  -- ssh / remote (lazy keys)
  ['<leader>ss'] = 'n',
  ['<leader>sd'] = 'n',
  ['<leader>sD'] = 'n',
  ['<leader>sB'] = 'n',
  ['<leader>sf'] = 'n',
  ['<leader>sg'] = 'n',
  ['<leader>sO'] = 'n',
  -- Claude (tmux lazy keys)
  ['<leader>cc'] = 'n',
  ['<leader>cf'] = 'n',
  ['<leader>cs'] = 'v',
  ['<leader>ce'] = 'n',
  -- tmux popups (lazy keys)
  ['<leader>tg'] = 'n',
  ['<leader>tt'] = 'n',
  ['<leader>tb'] = 'n',
  -- coach (setup fn — global)
  ['<leader>?'] = 'n',
  ['<leader>??'] = 'n',
  -- precognition (lazy key — global)
  ['<leader>?p'] = 'n',
}

local EXPECTED_USER_CMDS = {
  'HappyHostsPrune',
}

-- Translate <leader> to the actual leader character before looking up in the
-- keymap registry, because vim.api.nvim_get_keymap returns resolved LHS.
local function resolve_leader(lhs)
  local leader = vim.g.mapleader or '\\'
  return (lhs:gsub('<[Ll]eader>', leader))
end

local function has_mapping(mode, lhs)
  local resolved = resolve_leader(lhs)
  for _, m in ipairs(vim.api.nvim_get_keymap(mode)) do
    if m.lhs == resolved then
      return true
    end
  end
  return false
end

local function has_user_cmd(name)
  return vim.api.nvim_get_commands({})[name] ~= nil
end

describe('happy-nvim keymap + user-command inventory', function()
  it('registers every expected <leader>* keymap', function()
    local missing = {}
    for lhs, mode in pairs(EXPECTED_LEADER_KEYS) do
      if not has_mapping(mode, lhs) then
        table.insert(missing, string.format('%s (%s)', lhs, mode))
      end
    end
    assert.are.equal(0, #missing, 'missing keymaps: ' .. table.concat(missing, ', '))
  end)

  it('registers every expected user command', function()
    local missing = {}
    for _, name in ipairs(EXPECTED_USER_CMDS) do
      if not has_user_cmd(name) then
        table.insert(missing, name)
      end
    end
    assert.are.equal(0, #missing, 'missing user commands: ' .. table.concat(missing, ', '))
  end)
end)
