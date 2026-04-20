-- lua/coach/tips.lua
return {
  -- text-objects
  { keys = 'ciw', desc = 'change inside word', category = 'text-objects' },
  { keys = 'ci"', desc = 'change inside double quotes', category = 'text-objects' },
  { keys = "ci'", desc = 'change inside single quotes', category = 'text-objects' },
  { keys = 'ci(', desc = 'change inside parens', category = 'text-objects' },
  { keys = 'ci[', desc = 'change inside brackets', category = 'text-objects' },
  { keys = 'ci{', desc = 'change inside braces', category = 'text-objects' },
  { keys = 'cit', desc = 'change inside XML/HTML tag', category = 'text-objects' },
  { keys = 'dap', desc = 'delete a paragraph (with trailing blank)', category = 'text-objects' },
  { keys = 'vip', desc = 'visual-select inside paragraph', category = 'text-objects' },
  { keys = 'daf', desc = 'delete a function (treesitter)', category = 'text-objects' },
  -- motions
  { keys = 'f<char>', desc = 'jump forward to next <char> on line', category = 'motions' },
  { keys = 'F<char>', desc = 'jump backward to <char> on line', category = 'motions' },
  { keys = 't<char>', desc = 'jump to just-before <char> on line', category = 'motions' },
  { keys = '%', desc = 'jump to matching (/)/[/]/{/}', category = 'motions' },
  { keys = 'gg / G', desc = 'jump to file top / bottom', category = 'motions' },
  -- macros
  { keys = 'qa...q', desc = 'record macro into register a (q again to stop)', category = 'macros' },
  { keys = '@a', desc = 'replay macro a', category = 'macros' },
  { keys = '@@', desc = 'replay the last macro', category = 'macros' },
  { keys = '10@a', desc = 'replay macro a ten times', category = 'macros' },
  -- marks
  { keys = "ma / 'a", desc = 'set mark a / jump to line of mark a', category = 'marks' },
  { keys = "mA / 'A", desc = 'set global mark A (cross-file) / jump', category = 'marks' },
  { keys = "''", desc = 'jump back to previous position', category = 'marks' },
  -- registers
  { keys = '"ayy', desc = 'yank line into register a', category = 'registers' },
  { keys = '"+y', desc = 'yank into system clipboard', category = 'registers' },
  { keys = ':reg', desc = 'list all registers', category = 'registers' },
  -- search
  { keys = '*', desc = 'search forward for word under cursor', category = 'search' },
  { keys = 'n / N', desc = 'next / prev search match', category = 'search' },
  -- window
  { keys = '<C-w>v', desc = 'split window vertical', category = 'window' },
  { keys = '<C-w>=', desc = 'balance all splits', category = 'window' },
  -- lsp
  { keys = 'gd', desc = 'LSP: goto definition', category = 'lsp' },
  { keys = 'K', desc = 'LSP: hover docs', category = 'lsp' },
  { keys = '<leader>la', desc = 'LSP: code action', category = 'lsp' },

  -- undotree (<leader>u) — 30.9
  { keys = '<leader>u', desc = 'open undotree panel', category = 'undo' },
  { keys = '? (in undotree)', desc = 'show undotree help', category = 'undo' },
  { keys = 'j/k (in undotree)', desc = 'navigate revisions up/down', category = 'undo' },
  { keys = '<Enter> (in undotree)', desc = 'jump buffer to selected revision', category = 'undo' },
  { keys = 'd (in undotree)', desc = 'diff selected revision vs current', category = 'undo' },

  -- fugitive (<leader>gs / :Git) — 30.10
  { keys = '<leader>gs', desc = 'open Git status split (fugitive)', category = 'git' },
  { keys = 's (in :Git)', desc = 'stage file under cursor', category = 'git' },
  { keys = 'u (in :Git)', desc = 'unstage file under cursor', category = 'git' },
  { keys = '= (in :Git)', desc = 'toggle inline diff under cursor', category = 'git' },
  { keys = 'cc (in :Git)', desc = 'start commit (opens commit msg buffer)', category = 'git' },
  { keys = 'ca (in :Git)', desc = 'commit --amend', category = 'git' },

  -- remote (<leader>s*) — 30.11
  { keys = '<leader>ss', desc = 'ssh host picker (frecency-ordered)', category = 'remote' },
  { keys = '<leader>sd', desc = 'remote dir picker (zoxide-like, 7d cache)', category = 'remote' },
  { keys = '<leader>sB', desc = 'open remote file as scp:// buffer', category = 'remote' },
  {
    keys = '<leader>sg',
    desc = 'remote grep (nice/ionice over ssh) -> quickfix',
    category = 'remote',
  },

  -- claude tmux (<leader>c*) — 30.11
  {
    keys = '<leader>cc',
    desc = 'open/attach project claude session (cc-<id>)',
    category = 'claude',
  },
  {
    keys = '<leader>cp',
    desc = 'popup claude (SP1: remote-sandboxed if remote)',
    category = 'claude',
  },
  { keys = '<leader>cf', desc = 'send current file as @path to claude', category = 'claude' },
  {
    keys = '<leader>cs',
    desc = 'send visual selection (fenced w/ file:L-L header)',
    category = 'claude',
  },
  { keys = '<leader>ce', desc = 'send LSP diagnostics for current buffer', category = 'claude' },
  { keys = '<leader>cl', desc = 'list claude sessions (telescope picker)', category = 'claude' },
  {
    keys = '<leader>cn',
    desc = 'new named claude session (prompts for slug)',
    category = 'claude',
  },
  {
    keys = '<leader>ck',
    desc = "kill current project's claude session (Y/N confirm)",
    category = 'claude',
  },

  -- projects / cockpit (<leader>P*) — 30.11 (SP1)
  {
    keys = '<leader>P',
    desc = 'projects picker — pivot / peek / add / forget',
    category = 'projects',
  },
  {
    keys = '<leader>Pa',
    desc = 'add project (prompt for /path or host:path)',
    category = 'projects',
  },
  { keys = '<leader>Pp', desc = 'peek project scrollback (no pivot)', category = 'projects' },
  {
    keys = ':HappyWtProvision <path>',
    desc = 'provision worktree claude (async)',
    category = 'projects',
  },
  {
    keys = ':HappyWtCleanup <path>',
    desc = 'cleanup worktree claude (async)',
    category = 'projects',
  },

  -- capture (<leader>C*) — SP1 remote->claude one-way data flow
  { keys = '<leader>Cc', desc = 'capture remote pane -> sandbox file', category = 'capture' },
  {
    keys = '<leader>Ct',
    desc = 'toggle tail-pipe from remote pane -> sandbox live.log',
    category = 'capture',
  },
  { keys = '<leader>Cl', desc = 'pull remote file via scp -> sandbox dir', category = 'capture' },
  { keys = '<leader>Cs', desc = 'send visual selection -> sandbox file', category = 'capture' },

  -- SP3 remote additions
  {
    keys = '<leader>sc',
    desc = 'remote ad-hoc cmd (streams to scratch buffer)',
    category = 'remote',
  },
  {
    keys = '<leader>sL',
    desc = 'ssh: log tail w/ watch patterns (watch-aware, detachable)',
    category = 'remote',
  },
  {
    keys = '<leader>sp',
    desc = 'edit watch patterns (inside tail scratch buffer)',
    category = 'remote',
  },
  {
    keys = '<leader>sP',
    desc = 'tails picker — Enter reattaches, C-x kills active tail session',
    category = 'remote',
  },
  {
    keys = '<leader>sf',
    desc = 'remote file-name finder (find + telescope) — C-g grep · C-t tail · C-v less · C-y yank',
    category = 'remote',
  },
  {
    keys = '<leader>sT',
    desc = '[deprecated] use <leader>sL for log tail',
    category = 'remote',
  },

  -- SP1 cockpit tips
  {
    keys = '<leader>cp / <leader>cc',
    desc = '<leader>cp is primary claude popup; <leader>cc splits in place',
    category = 'claude',
  },
  {
    keys = '<leader>tt / <leader>tl',
    desc = '<leader>tt opens project-scoped tt-* shell popup; <leader>tl picks from list',
    category = 'claude',
  },

  -- SP2 quick-pivot hub
  {
    keys = '<leader><leader>',
    desc = 'quick-pivot hub: projects + hosts + sessions (SP2)',
    category = 'projects',
  },
  {
    keys = '<leader>cq',
    desc = 'quick scratch claude popup (ephemeral, single-shot, SP4)',
    category = 'claude',
  },
}
