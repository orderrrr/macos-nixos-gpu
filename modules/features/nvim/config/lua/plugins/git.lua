local util = require('util')

-- gitsigns: setup VeryLazy; it attaches to current buffers as part of setup.
util.lazy_event({ 'gitsigns.nvim' }, 'User', function()
    require('gitsigns').setup({
        -- See `:help gitsigns.txt`
        signs = {
            add = { text = '+' },
            change = { text = '~' },
            delete = { text = '_' },
            topdelete = { text = '‾' },
            changedelete = { text = '~' },
        },
        on_attach = function(bufnr)
            vim.keymap.set('n', '<leader>gp', require('gitsigns').prev_hunk,
                { buffer = bufnr, desc = '[G]o to [P]revious Hunk' })
            vim.keymap.set('n', '<leader>gn', require('gitsigns').next_hunk,
                { buffer = bufnr, desc = '[G]o to [N]ext Hunk' })
            vim.keymap.set('n', '<leader>ph', require('gitsigns').preview_hunk,
                { buffer = bufnr, desc = '[P]review [H]unk' })
        end,
    })
end, { pattern = 'VeryLazy' })

-- lazygit.nvim ships a plugin/ file that registers `:LazyGit` on its own;
-- just map the shortcut.
vim.keymap.set('n', '<leader>lg', ':LazyGit<CR>')
