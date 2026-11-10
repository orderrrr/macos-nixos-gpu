-- nvim-treesitter `main` branch: no module system. Install parsers via
-- require('nvim-treesitter').install(); start highlighting per-buffer via a
-- FileType autocmd.
vim.cmd.packadd('nvim-treesitter')
vim.cmd.packadd('nvim-treesitter-context')

require('nvim-treesitter').install({
  'bash', 'c', 'cpp', 'css', 'dart', 'diff', 'dockerfile', 'fish',
  'gitcommit', 'go', 'html', 'java', 'javascript', 'json', 'lua', 'luadoc',
  'markdown', 'markdown_inline', 'nix', 'python', 'query', 'regex', 'rust',
  'toml', 'tsx', 'typescript', 'vim', 'vimdoc', 'yaml', 'zig',
})

vim.api.nvim_create_autocmd('FileType', {
  callback = function(args)
    if pcall(vim.treesitter.start, args.buf) then
      vim.bo[args.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
    end
  end,
})

require('treesitter-context').setup({
  enable = true,
  multiwindow = true,
  max_lines = 6,
  min_window_height = 0,
  line_numbers = true,
  multiline_threshold = 1,
  trim_scope = 'outer',
  mode = 'cursor',
  separator = nil,
  zindex = 20,
  on_attach = nil,
})

