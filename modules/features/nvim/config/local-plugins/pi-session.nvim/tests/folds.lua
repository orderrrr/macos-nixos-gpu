local folds = require('pi_session.folds')
local names = { 'foldmethod', 'foldexpr', 'foldtext', 'foldenable', 'foldlevel', 'foldminlines' }

local function options(window)
  local values = {}
  for _, name in ipairs(names) do
    values[name] = vim.api.nvim_get_option_value(name, { win = window, scope = 'local' })
  end
  return values
end

local function set_options(window, values)
  for name, value in pairs(values) do
    vim.api.nvim_set_option_value(name, value, { win = window, scope = 'local' })
  end
end

local function document(statuses)
  local result = { lines = {}, tool_rows = {} }
  for row, status in ipairs(statuses) do
    result.lines[row] = status == false and 'prose or fake tool: done' or 'tool call'
    if status ~= false then
      result.tool_rows[row] = { status = status }
    end
  end
  return result
end

local function fixture(check)
  local original_window = vim.api.nvim_get_current_win()
  local original_buffer = vim.api.nvim_get_current_buf()
  local original_options = options(original_window)
  local defaults = {}
  for _, name in ipairs(names) do
    defaults[name] = vim.api.nvim_get_option_value(name, { scope = 'global' })
  end
  local buffers, windows = {}, {}
  local function buffer(doc)
    local value = vim.api.nvim_create_buf(false, true)
    buffers[#buffers + 1] = value
    vim.api.nvim_buf_set_lines(value, 0, -1, false, doc.lines)
    return value
  end
  local function split()
    vim.cmd('vsplit')
    local value = vim.api.nvim_get_current_win()
    windows[#windows + 1] = value
    return value
  end
  local ok, err = xpcall(function() check(buffer, split) end, debug.traceback)
  for _, window in ipairs(windows) do
    if vim.api.nvim_win_is_valid(window) then
      vim.api.nvim_win_close(window, true)
    end
  end
  vim.api.nvim_set_current_win(original_window)
  vim.api.nvim_win_set_buf(original_window, original_buffer)
  set_options(original_window, original_options)
  for name, value in pairs(defaults) do
    vim.api.nvim_set_option_value(name, value, { scope = 'global' })
  end
  for _, value in ipairs(buffers) do
    if vim.api.nvim_buf_is_valid(value) then
      vim.api.nvim_buf_delete(value, { force = true })
    end
  end
  assert(ok, err)
end

local function boundaries(test)
  -- Query native folds and their text to prove only typed contiguous rows participate.
  test('folds respect typed boundaries and report non-success counts', function()
    fixture(function(buffer)
      local doc = document({ false, 'done', false, 'done', 'done', false,
        'failed', 'unfinished', 'unknown status', 'failed', false })
      local value = buffer(doc)
      vim.api.nvim_set_current_buf(value)
      folds.apply(value, doc)
      assert(vim.fn.foldclosed(2) == -1)
      assert(vim.fn.foldclosed(4) == 4 and vim.fn.foldclosedend(4) == 5)
      assert(vim.fn.foldclosed(6) == -1 and vim.fn.foldclosed(11) == -1)
      assert(vim.fn.foldclosed(7) == 7 and vim.fn.foldclosedend(7) == 10)
      assert(vim.fn.foldtextresult(4) == '▸ 2 tool calls')
      assert(vim.fn.foldtextresult(7)
        == '▸ 4 tool calls (2 failed, 1 unfinished, 1 unknown status)')
      assert(vim.deep_equal(vim.b[value].pi_session_fold_levels,
        { 0, 0, 0, 1, 1, 0, 1, 1, 1, 1, 0 }))
      assert(not vim.wo.foldexpr:find('lua', 1, true))
      vim.api.nvim_win_set_cursor(0, { 7, 0 })
      vim.cmd('normal! zv')
      assert(vim.fn.foldclosed(7) == -1)
    end)
  end)

end

local function round_trips(test)
  -- Leave and reenter the same window, including a preview buffer with its own options.
  test('folds preserve zo and zc across buffer and preview round trips', function()
    fixture(function(buffer)
      local doc = document({ 'done', 'done', false, 'done', 'failed' })
      local value = buffer(doc)
      local preview = buffer(document({ false, false, false }))
      vim.api.nvim_set_current_buf(value)
      folds.apply(value, doc)
      vim.cmd('normal! zo')
      assert(vim.fn.foldclosed(1) == -1 and vim.fn.foldclosed(4) == 4)
      for _ = 1, 2 do
        vim.api.nvim_set_current_buf(preview)
        set_options(0, { foldmethod = 'manual', foldlevel = 3 })
        vim.api.nvim_set_current_buf(value)
        assert(vim.fn.foldclosed(1) == -1 and vim.fn.foldclosed(4) == 4)
      end
      vim.cmd('normal! zc')
      vim.api.nvim_set_current_buf(preview)
      vim.api.nvim_set_current_buf(value)
      assert(vim.fn.foldclosed(1) == 1)
    end)
  end)

end

local function isolation(test)
  -- Seed manual folds and compare local/global options after a transcript round trip.
  test('folds leave unrelated manual folds and global defaults untouched', function()
    fixture(function(buffer, split)
      local global = {}
      for _, name in ipairs(names) do
        global[name] = vim.api.nvim_get_option_value(name, { scope = 'global' })
      end
      local other = buffer(document({ false, false, false, false }))
      vim.api.nvim_set_current_buf(other)
      set_options(0, { foldmethod = 'manual', foldenable = true, foldminlines = 0,
        foldexpr = '0', foldtext = '"other"', foldlevel = 0 })
      vim.cmd('1,3fold')
      local before = options(0)
      local other_window = vim.api.nvim_get_current_win()
      local doc = document({ 'done', 'done' })
      local value = buffer(doc)
      split()
      vim.api.nvim_set_current_buf(value)
      folds.apply(value, doc)
      assert(vim.deep_equal(options(other_window), before))
      vim.api.nvim_win_call(other_window, function() assert(vim.fn.foldclosedend(1) == 3) end)
      vim.api.nvim_set_current_buf(other)
      assert(vim.deep_equal(options(0), before))
      assert(vim.fn.foldclosedend(1) == 3)
      for _, name in ipairs(names) do
        assert(vim.api.nvim_get_option_value(name, { scope = 'global' }) == global[name])
      end
    end)
  end)

end

local function windows_and_refresh(test)
  -- Enter from an unrelated window after apply, then refresh both displayed copies.
  test('folds initialize independent windows and refresh copies without focus changes', function()
    fixture(function(buffer, split)
      local doc = document({ 'done', 'done', false, 'done' })
      local value = buffer(doc)
      vim.api.nvim_set_current_buf(value)
      folds.apply(value, doc)
      local first = vim.api.nvim_get_current_win()
      vim.cmd('normal! zo')
      vim.api.nvim_set_current_buf(buffer(document({ false })))
      set_options(0, { foldmethod = 'manual', foldexpr = '0' })
      split()
      vim.api.nvim_set_current_buf(value)
      assert(vim.wo.foldmethod == 'expr' and vim.fn.foldclosed(1) == 1)
      vim.cmd('normal! zo')
      local current = vim.api.nvim_get_current_win()
      vim.api.nvim_win_set_buf(first, value)
      local jumps = vim.fn.getjumplist()
      doc.tool_rows[3] = { status = 'failed' }
      folds.apply(value, doc)
      assert(vim.api.nvim_get_current_win() == current)
      assert(vim.deep_equal(vim.fn.getjumplist(), jumps))
      for _, window in ipairs({ first, current }) do
        vim.api.nvim_win_call(window, function()
          assert(vim.fn.foldclosed(1) == 1 and vim.fn.foldclosedend(1) == 4)
          assert(vim.fn.foldtextresult(1) == '▸ 4 tool calls (1 failed)')
        end)
      end
      local commands = vim.api.nvim_get_autocmds({ buffer = value, event = 'BufWinEnter' })
      assert(#commands == 1)
    end)
  end)

end

local function reload(test)
  -- Refill retained buffer handles after native unload/delete removes their fold state.
  for _, command in ipairs({ 'bunload', 'bdelete' }) do
    test('folds rebuild metadata after ' .. command, function()
      fixture(function(buffer)
        local doc = document({ 'done', 'failed' })
        local value = buffer(doc)
        local other = buffer(document({ false }))
        vim.api.nvim_set_current_buf(value)
        folds.apply(value, doc)
        vim.cmd('normal! zo')
        vim.api.nvim_set_current_buf(other)
        vim.cmd(command .. '! ' .. value)
        assert(vim.api.nvim_buf_is_valid(value))
        assert(not vim.api.nvim_buf_is_loaded(value))
        vim.api.nvim_buf_set_lines(value, 0, -1, false, doc.lines)
        vim.api.nvim_set_current_buf(value)
        assert(vim.deep_equal(vim.b[value].pi_session_fold_levels, { 1, 1 }))
        assert(vim.fn.foldclosed(1) == 1)
        assert(vim.fn.foldtextresult(1) == '▸ 2 tool calls (1 failed)')
      end)
    end)
  end

end

local function empty_refresh(test)
  -- Refresh to prose-only and empty documents so no old fold levels survive.
  test('folds clear obsolete runs on refresh and accept empty documents', function()
    fixture(function(buffer)
      local doc = document({ 'done', 'done' })
      local value = buffer(doc)
      vim.api.nvim_set_current_buf(value)
      folds.apply(value, doc)
      for _, replacement in ipairs({ document({ false, 'done' }), document({}) }) do
        vim.api.nvim_buf_set_lines(value, 0, -1, false, replacement.lines)
        folds.apply(value, replacement)
        assert(vim.fn.foldclosed(1) == -1)
        assert(vim.fn.foldlevel(1) == 0)
      end
    end)
  end)
end

return function(test)
  boundaries(test)
  round_trips(test)
  isolation(test)
  windows_and_refresh(test)
  reload(test)
  empty_refresh(test)
end
