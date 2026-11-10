local util = require('util')

-- snacks: terminal + picker keymaps registered unconditionally, plugin setup
-- runs VeryLazy so LSP keymaps that call `require('snacks').picker.X()` find
-- a configured instance by the time the user reaches for them.
util.lazy_event({ 'snacks.nvim' }, 'User', function()
  require('snacks').setup({
    bigfile = { enabled = true },
    dashboard = { enabled = false },
    explorer = { enabled = false },
    indent = { enabled = false },
    input = { enabled = true },
    picker = { enabled = true },
    notifier = { enabled = false },
    quickfile = { enabled = false },
    scope = { enabled = false },
    scroll = { enabled = false },
    statuscolumn = { enabled = false },
    words = { enabled = false },
    terminal = { enabled = true },
  });
end, { pattern = 'VeryLazy' })

vim.keymap.set({ 'n', 't' }, '<leader>tt', function() require('snacks').terminal() end)
vim.keymap.set({ 't' }, '<C-\\>', '<C-\\><C-n>')

util.lazy_event({ 'vim-illuminate' }, 'User', function()
  require('illuminate').configure {
    providers = {
      'lsp',
      'regex',
    },
    delay = 50,
    filetypes_denylist = {
      'dirvish',
      'fugitive',
    },
    under_cursor = true,
  }
end, { pattern = 'VeryLazy' })

util.lazy_cmd({ 'ccc.nvim' }, { 'CccPick', 'CccConvert', 'CccHighlighterEnable', 'CccHighlighterToggle' }, function()
  require('ccc').setup({})
end)
