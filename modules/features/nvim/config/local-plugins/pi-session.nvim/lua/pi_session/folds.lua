local M = {}
local expression = 'get(b:pi_session_fold_levels,v:lnum-1,0)'
local text = 'get(b:pi_session_fold_labels,string(v:foldstart),"")'
local setup_window
local compile

function M.apply(buffer, document)
  assert(vim.api.nvim_buf_is_loaded(buffer), 'Fold buffer must be loaded')
  assert(type(document.lines) == 'table', 'Fold document needs lines')
  local levels, labels = compile(document)
  local initialized = {}
  vim.b[buffer].pi_session_fold_levels = levels
  vim.b[buffer].pi_session_fold_labels = labels
  local group = vim.api.nvim_create_augroup('PiSessionFolds', { clear = false })
  vim.api.nvim_clear_autocmds({ group = group, buffer = buffer })
  vim.api.nvim_create_autocmd('BufWinEnter', {
    group = group,
    buffer = buffer,
    callback = function()
      local missing = vim.fn.exists('b:pi_session_fold_levels') == 0
      if missing then
        vim.b[buffer].pi_session_fold_levels = levels
        vim.b[buffer].pi_session_fold_labels = labels
      end
      local window = vim.api.nvim_get_current_win()
      local options = { win = window, scope = 'local' }
      if not initialized[window]
        or vim.api.nvim_get_option_value('foldmethod', options) ~= 'expr'
        or vim.api.nvim_get_option_value('foldexpr', options) ~= expression then
        setup_window(window)
        initialized[window] = true
      end
    end,
  })
  vim.api.nvim_create_autocmd('BufUnload', {
    group = group,
    buffer = buffer,
    callback = function()
      -- Unloaded buffers lose native fold state, even when their variables survive.
      vim.b[buffer].pi_session_fold_levels = nil
      vim.b[buffer].pi_session_fold_labels = nil
      initialized = {}
    end,
  })
  for _, window in ipairs(vim.fn.win_findbuf(buffer)) do
    setup_window(window)
    initialized[window] = true
  end
end

setup_window = function(window)
  local options = {
    foldmethod = 'expr', foldexpr = expression, foldtext = text,
    foldenable = true, foldlevel = 0, foldminlines = 0,
  }
  for name, value in pairs(options) do
    vim.api.nvim_set_option_value(name, value, { win = window, scope = 'local' })
  end
  -- Window calls preserve focus; zX recomputes and discards manual open/closed state.
  vim.api.nvim_win_call(window, function() vim.cmd('normal! zX') end)
end

compile = function(document)
  local levels, labels = {}, {}
  local rows = document.tool_rows or {}
  for row = 1, #document.lines do
    levels[row] = 0
  end
  local row = 1
  while row <= #document.lines do
    if not rows[row] then
      row = row + 1
    else
      local first = row
      local counts = { failed = 0, unfinished = 0, ['unknown status'] = 0 }
      while row <= #document.lines and rows[row] do
        local status = rows[row].status
        if status ~= 'done' then
          assert(counts[status], 'Unexpected tool status: ' .. tostring(status))
          counts[status] = counts[status] + 1
        end
        row = row + 1
      end
      if row - first >= 2 then
        for tool_row = first, row - 1 do
          levels[tool_row] = 1
        end
        local label = '▸ ' .. (row - first) .. ' tool calls'
        local details = {}
        for _, status in ipairs({ 'failed', 'unfinished', 'unknown status' }) do
          if counts[status] > 0 then
            details[#details + 1] = counts[status] .. ' ' .. status
          end
        end
        if #details > 0 then
          label = label .. ' (' .. table.concat(details, ', ') .. ')'
        end
        labels[tostring(first)] = label
      end
    end
  end
  return levels, labels
end

return M
