require('conform').setup({
  formatters_by_ft = {
    yaml = { 'prettier' },
    json = { 'prettier' },
    nix  = { 'nixfmt' },
  },
})

vim.keymap.set({ 'n', 'v' }, '<leader>lf', function()
  require('conform').format({ async = true, lsp_fallback = true })
end)
