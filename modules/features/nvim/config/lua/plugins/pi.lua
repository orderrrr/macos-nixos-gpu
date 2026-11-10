-- Keep the viewer separate from the interactive AI integrations.
vim.opt.runtimepath:prepend(vim.fn.stdpath('config') .. '/local-plugins/pi-session.nvim')
require('pi_session').setup()
