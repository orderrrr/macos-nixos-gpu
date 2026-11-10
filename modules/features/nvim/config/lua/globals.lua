-- Enable true color support
vim.o.termguicolors = true

-- Options
vim.o.swapfile = false
vim.o.undofile = true
vim.o.updatetime = 250
vim.o.timeoutlen = 300
vim.o.ignorecase = true
vim.o.smartcase = true
vim.o.completeopt = 'menu,menuone,noselect'
vim.o.breakindent = true
vim.o.signcolumn = 'yes'
vim.o.laststatus = 3
vim.o.winborder = 'rounded'
vim.o.tabstop = 2
vim.o.shiftwidth = 2
vim.o.softtabstop = 2
vim.o.expandtab = true
vim.o.linebreak = true
vim.o.breakindent = true

-- Line numbers
vim.o.number = true
vim.o.relativenumber = true

-- UI settings
vim.o.wrap = false
vim.o.scrolloff = 5
vim.o.cmdheight = 0
vim.opt.guicursor = "n-v-c-sm:block,i-ci-ve:ver25,r-cr-o:hor20"

-- JSON filetype detection
vim.cmd [[autocmd BufNewFile,BufRead *.json set filetype=json]]

