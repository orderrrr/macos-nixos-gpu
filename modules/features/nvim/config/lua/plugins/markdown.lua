local util = require('util')

-- render-markdown.nvim auto-initializes via its plugin/ file. Pack was added
-- with load=function()end, so we packadd it on first markdown buffer.
util.lazy_event({ 'render-markdown.nvim' }, 'FileType', function()
  -- packadd (inside lazy_event) sources plugin/render-markdown.lua which
  -- auto-configures. Force a redraw so highlights pick up for the current buf.
  pcall(vim.cmd, 'RenderMarkdown enable')
end, { pattern = 'markdown' })
