local util = require('util')

util.lazy_cmd('oil.nvim', 'Oil', function()
  require("oil").setup({
    columns = {
      "icon",
      "permissions",
      "size",
      "mtime",
    },
    delete_to_trash = false,
  })
end)

vim.keymap.set('n', '<leader>o', ':Oil<CR>');
