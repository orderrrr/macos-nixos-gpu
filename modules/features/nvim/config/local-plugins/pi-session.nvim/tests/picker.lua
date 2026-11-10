local viewer = require('pi_session')
local sessions = require('pi_session.sessions')

local function fixture(check)
  vim.cmd('packadd plenary.nvim')
  vim.cmd('packadd telescope.nvim')
  local telescope = require('telescope')
  local initial_mode = require('telescope.config').values.initial_mode
  -- These unit checks call actions synchronously; native_ui.lua tests real Insert-mode input.
  telescope.setup({ defaults = { initial_mode = 'normal' } })
  local root = vim.fn.tempname()
  vim.fn.mkdir(root .. '/project', 'p', 448)
  local cwd, notify = vim.fn.getcwd(), vim.notify
  local old_rpc = package.loaded['pi_session.rpc']
  local old_transcript = package.loaded['pi_session.transcript']
  local old_override = vim.env.PI_CODING_AGENT_SESSION_DIR
  vim.env.PI_CODING_AGENT_SESSION_DIR = nil
  vim.notify = function() end
  vim.o.columns, vim.o.lines = 120, 40
  vim.cmd('cd ' .. vim.fn.fnameescape(root .. '/project'))
  local config = { agent_dir = root .. '/agent' }
  local directory = sessions.directory(vim.fn.getcwd(), config)
  vim.fn.mkdir(directory, 'p')
  local path = directory .. '/one.jsonl'
  vim.fn.writefile({
    vim.json.encode({ type = 'session', version = 3, id = 'session-one', cwd = vim.fn.getcwd() }),
    vim.json.encode({
      type = 'message', message = { role = 'user', content = 'Find this session' },
    }),
  }, path)
  viewer.setup(config)
  local ok, err = xpcall(function() check(path, config) end, debug.traceback)
  viewer.setup({})
  telescope.setup({ defaults = { initial_mode = initial_mode } })
  package.loaded['pi_session.rpc'] = old_rpc
  package.loaded['pi_session.transcript'] = old_transcript
  vim.notify = notify
  vim.env.PI_CODING_AGENT_SESSION_DIR = old_override
  vim.cmd('silent! stopinsert')
  vim.cmd('cd ' .. vim.fn.fnameescape(cwd))
  vim.fn.delete(root, 'rf')
  assert(ok, err)
end

local function choose()
  vim.cmd('PISession')
  local state = require('telescope.actions.state')
  assert(vim.wait(3000, function()
    return vim.bo.filetype == 'TelescopePrompt' and state.get_selected_entry() ~= nil
  end, 5), 'Telescope did not show a session')
  -- Consume Telescope's queued A<Esc> while its prompt still exists.
  vim.api.nvim_feedkeys('', 'x', false)
  local prompt = vim.api.nvim_get_current_buf()
  assert(state.get_selected_entry().value.id == 'session-one')
  require('telescope.actions').select_default(prompt)
end

return function(test)
  -- Exercise the actual Telescope picker; only the process and renderer are replaced with spies.
  test('PISession selects a current-project session and loads it through RPC', function()
    fixture(function(path, config)
      local window = vim.api.nvim_get_current_win()
      local loaded, opened = nil, nil
      package.loaded['pi_session.rpc'] = {
        load = function(session, options, callback)
          loaded = session
          assert(options.agent_dir == config.agent_dir)
          vim.schedule(function() callback(nil, { entries = {}, leafId = vim.NIL }) end)
          return function() end
        end,
      }
      package.loaded['pi_session.transcript'] = {
        open = function(session, data, target)
          assert(target == window and data.leafId == vim.NIL)
          opened = session
          return vim.api.nvim_get_current_buf()
        end,
      }
      choose()
      assert(vim.wait(2000, function() return opened ~= nil end, 5), 'Selection was not opened')
      assert(loaded.path == path and opened.path == path)
      assert(#vim.api.nvim_list_wins() == 1, 'Picker left an extra input/panel window')
    end)
  end)

  -- RPC failures must preserve the existing editor rather than presenting an empty fake transcript.
  test('RPC failure never opens a transcript', function()
    fixture(function(path)
      local notified, opened = false, false
      vim.notify = function(message) notified = message:find('test RPC failure', 1, true) ~= nil end
      package.loaded['pi_session.rpc'] = {
        load = function(_, _, callback)
          vim.schedule(function() callback('test RPC failure') end)
          return function() end
        end,
      }
      package.loaded['pi_session.transcript'] = { open = function() opened = true end }
      local buffer = vim.api.nvim_get_current_buf()
      viewer.open({ path = path, cwd = vim.fn.getcwd() })
      assert(vim.wait(1000, function() return notified end, 5))
      assert(not opened and vim.api.nvim_get_current_buf() == buffer)
    end)
  end)

  -- A newer selection owns the destination even if a cancelled load replies late.
  test('newer selection cancels and suppresses stale RPC results', function()
    fixture(function(path)
      local callbacks, opened, cancelled = {}, {}, 0
      package.loaded['pi_session.rpc'] = {
        load = function(_, _, callback)
          callbacks[#callbacks + 1] = callback
          return function() cancelled = cancelled + 1 end
        end,
      }
      package.loaded['pi_session.transcript'] = {
        open = function(session)
          opened[#opened + 1] = session.id
          return vim.api.nvim_get_current_buf()
        end,
      }
      viewer.open({ path = path, cwd = vim.fn.getcwd(), id = 'first' })
      viewer.open({ path = path, cwd = vim.fn.getcwd(), id = 'second' })
      assert(cancelled == 1)
      callbacks[1](nil, {})
      callbacks[2](nil, {})
      assert(#opened == 1 and opened[1] == 'second')
    end)
  end)

  -- A load must not take over an unrelated file opened while the RPC request was pending.
  test('delayed RPC does not replace a different destination buffer', function()
    fixture(function(path)
      local callback, opened
      package.loaded['pi_session.rpc'] = {
        load = function(_, _, reply)
          callback = reply
          return function() end
        end,
      }
      package.loaded['pi_session.transcript'] = {
        open = function()
          opened = true
          return vim.api.nvim_get_current_buf()
        end,
      }
      viewer.open({ path = path, cwd = vim.fn.getcwd() })
      local other = vim.api.nvim_create_buf(true, true)
      vim.api.nvim_win_set_buf(0, other)
      callback(nil, { entries = {}, leafId = vim.NIL })
      assert(not opened, 'Delayed load replaced unrelated work')
      assert(vim.api.nvim_get_current_buf() == other)
    end)
  end)

  -- Validate bounded resource options before a command can start filesystem or process work.
  test('configuration rejects invalid resource limits', function()
    for _, value in ipairs({ 0, -1, 1.5, 'unlimited' }) do
      local ok = pcall(viewer.setup, { max_sessions = value })
      assert(not ok)
    end
    viewer.setup({})
    assert(vim.fn.exists(':PISession') == 2)
  end)
end
