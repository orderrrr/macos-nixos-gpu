local util = require('util')

vim.filetype.add({
  extension = {
    yml = "yaml",
  },
})

vim.cmd('set completeopt+=noselect')

require('lsp-servers')

-- Built-in LSP keymaps: safe to set unconditionally — `vim.lsp.*` is core.

vim.keymap.set('n', 'K', vim.lsp.buf.hover)
vim.keymap.set('n', '<leader>k', vim.lsp.buf.hover)
vim.keymap.set('n', '<leader>rn', vim.lsp.buf.rename)


-- SNACKS
vim.keymap.set('n', 'gd', function() require('snacks').picker.lsp_definitions() end)
vim.keymap.set('n', 'gD', function() require('snacks').picker.lsp_declarations() end)
vim.keymap.set('n', 'gr', function() require('snacks').picker.lsp_references() end)
vim.keymap.set('n', 'gI', function() require('snacks').picker.lsp_implementations() end)
vim.keymap.set('n', 'gy', vim.lsp.buf.type_definition)
vim.keymap.set('n', '<leader>ss', function() require('snacks').picker.lsp_symbols() end)
vim.keymap.set('n', '<leader>sS', function() require('snacks').picker.lsp_workspace_symbols() end)

-- actions-preview: load on first <leader>ca
util.lazy_key('actions-preview.nvim', { { 'n', '<leader>ca' } }, function()
  vim.keymap.set('n', '<leader>ca', require('actions-preview').code_actions)
end)

vim.keymap.set('n', 'gd', vim.lsp.buf.definition)


-- nvim-cmp supports additional completion capabilities, so broadcast that to servers
local capabilities = vim.lsp.protocol.make_client_capabilities()

local on_attach = function(_, _)
end

-- jdtls: FileType autocmd is set up inside this module already.
require('plugins.filetypes.jdtls')(on_attach, capabilities)

-- flutter-tools: only for Dart files. Pull nvim-dap along so the debugger
-- config callback has dap available.
util.lazy_event({ 'nvim-nio', 'nvim-dap', 'flutter-tools.nvim' }, 'FileType', function()
  require("flutter-tools").setup {
    debugger = {
      enabled = true,
      run_via_dap = true,
      register_configurations = function(_)
        require('dap').configurations.dart = {
          {
            type = 'dart',
            request = 'launch',
            name = 'Launch Flutter App',
            program = '${workspaceFolder}/lib/main.dart', -- Adjust if your entry point is different
            cwd = '${workspaceFolder}',
          },
        }
      end,
    },
  }
end, { pattern = 'dart' })

util.lazy_event({ 'slang' }, 'FileType', function()
  require("slang").setup({
    auto_format = true,
    inlay_hints = true,
  })
end, { pattern = 'slang', 'hlsl' })

if vim.fn.executable 'slangd' == 1 then
  require("slang").setup({
    auto_format = true,
    inlay_hints = true,
  })
end
