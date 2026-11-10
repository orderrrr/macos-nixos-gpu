-- Most plugins: installed and added to runtimepath, but their own setup() is
-- deferred by the per-module files via util.lazy_{key,cmd,event}.
vim.pack.add({
  -- always-on / deps
  'https://github.com/nvim-lua/plenary.nvim',
  'https://github.com/f-person/auto-dark-mode.nvim',
  'https://github.com/kdheepak/lazygit.nvim',

  -- git
  'https://github.com/lewis6991/gitsigns.nvim',

  -- telescope + ext
  'https://github.com/nvim-telescope/telescope.nvim',
  'https://github.com/nvim-telescope/telescope-ui-select.nvim',
  'https://github.com/gbrlsnchs/telescope-lsp-handlers.nvim',
  'https://github.com/aaronhallaert/advanced-git-search.nvim',

  -- dap
  'https://github.com/nvim-neotest/nvim-nio',
  'https://github.com/mfussenegger/nvim-dap',
  'https://github.com/rcarriga/nvim-dap-ui',

  -- ui / visuals
  'https://github.com/RRethy/vim-illuminate',
  'https://github.com/uga-rosa/ccc.nvim',
  'https://github.com/folke/snacks.nvim',

  -- lsp
  'https://github.com/aznhe21/actions-preview.nvim',
  'https://github.com/stevearc/conform.nvim',

  -- treesitter (parsers loaded lazily per-ft by treesitter itself)
  -- must use 'main' branch: the rewrite with require('nvim-treesitter').install() API
  { src = 'https://github.com/nvim-treesitter/nvim-treesitter', version = 'main' },
  'https://github.com/nvim-treesitter/nvim-treesitter-context',

  -- file ui
  'https://github.com/stevearc/oil.nvim',

  -- completion
  'https://github.com/Saghen/blink.lib', -- required by blink.cmp v2
  'https://github.com/Saghen/blink.cmp',
  'https://github.com/Saghen/blink.compat',
  'https://github.com/L3MON4D3/LuaSnip',
  'https://github.com/rafamadriz/friendly-snippets',

  -- ai
  'https://github.com/NickvanDyke/opencode.nvim',
  'https://github.com/ThePrimeagen/99',

  -- filetypes
  'https://github.com/mfussenegger/nvim-jdtls',
  'https://github.com/nvim-flutter/flutter-tools.nvim',
  'https://github.com/pixelsandpointers/slang.nvim',

  'https://github.com/MeanderingProgrammer/render-markdown.nvim',
})

local plugins_dir = vim.fn.stdpath("config") .. "/lua/plugins"
local files = vim.fn.readdir(plugins_dir)

for _, file in ipairs(files) do
  if file:match("%.lua$") and file ~= "init.lua" then
    local module_name = file:gsub("%.lua$", "")
    require("plugins." .. module_name)
  end
end
