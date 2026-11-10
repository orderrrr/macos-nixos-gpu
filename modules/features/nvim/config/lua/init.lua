-- Ensure Homebrew bins are available to subprocesses (tree-sitter, etc.)
vim.env.PATH = '/opt/homebrew/bin:' .. vim.env.PATH

-- Eager plugins: colorscheme + shared deps.
vim.pack.add({
  'https://github.com/nvim-lua/plenary.nvim',
  'https://github.com/f-person/auto-dark-mode.nvim',
})

-- Global settings
-- Leader keys
vim.g.mapleader = ' '
vim.g.maplocalleader = ' '

-- Load modules
require('keybinds')
require('theme').setup()
require('globals')
require('build')
require('plugins')

-- Local plugin, developed at ~/opt/scrub.nvim. Adding it to the runtimepath
-- during config sourcing means its plugin/scrub.lua is picked up by the
-- normal plugin loading phase, exactly as an installed plugin would be.
vim.opt.rtp:prepend(vim.fs.normalize('~/opt/scrub.nvim'))

-- Fire a `User VeryLazy` event once the UI is up, for lazy plugin setup that
-- shouldn't block startup but should still run immediately after.
vim.api.nvim_create_autocmd('UIEnter', {
  once = true,
  callback = function()
    vim.schedule(function()
      vim.api.nvim_exec_autocmds('User', { pattern = 'VeryLazy', modeline = false })
    end)
  end,
})
