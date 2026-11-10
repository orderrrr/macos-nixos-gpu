-- Drive real input in another Neovim event loop; synchronous -l actions can leave
-- Telescope's startinsert queued until after its prompt buffer has been deleted.
local plugin = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')
local initialize = [[
local plugin, project, storage = ...
vim.opt.rtp:prepend(plugin)
vim.cmd('packadd plenary.nvim')
vim.cmd('packadd telescope.nvim')
vim.o.columns, vim.o.lines = 120, 40
vim.cmd('cd ' .. vim.fn.fnameescape(project))
vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'Previously viewed transcript' })
vim.bo.buftype, vim.bo.modifiable = 'nofile', false
_G.rpc_observations = { requests = {}, directories = {}, pids = {} }
local send, temporary, start = vim.fn.chansend, vim.uv.fs_mkdtemp, vim.fn.jobstart
vim.fn.chansend = function(job, value)
  table.insert(rpc_observations.requests, vim.json.decode(value))
  return send(job, value)
end
vim.uv.fs_mkdtemp = function(template)
  local directory, err = temporary(template)
  if directory then table.insert(rpc_observations.directories, directory) end
  return directory, err
end
vim.fn.jobstart = function(command, options)
  local job = start(command, options)
  if job > 0 then table.insert(rpc_observations.pids, vim.fn.jobpid(job)) end
  return job
end
require('pi_session').setup({ session_dir = storage })
vim.v.errmsg = ''
]]

return function(session, storage, observations, views, check_preview)
  local job = vim.fn.jobstart({ vim.v.progpath, '--headless', '--embed', '-u', 'NONE', '-n' },
    { rpc = true })
  assert(job > 0)
  local function lua(code, args)
    return vim.rpcrequest(job, 'nvim_exec_lua', code, args or {})
  end
  local function input(keys) vim.rpcrequest(job, 'nvim_input', keys) end
  local function await(code)
    assert(vim.wait(20000, function() return lua(code) end, 10), 'Native UI wait: ' .. code)
  end
  local ok, err = xpcall(function()
    lua(initialize, { plugin, session.cwd, storage })
    input(':PISession\r')
    await("return vim.bo.filetype == 'TelescopePrompt' and vim.api.nvim_get_mode().mode == 'i'")
    input('\r')
    local expected = 'pi-session://' .. vim.fn.sha256(session.path)
    await('return vim.api.nvim_buf_get_name(0) == ' .. string.format('%q', expected))
    assert(lua("return vim.api.nvim_get_mode().mode") == 'n')
    assert(lua('return vim.bo.filetype') == 'markdown')
    assert(lua('return #vim.api.nvim_list_wins()') == 1, 'Extra composer/panel window')
    local lines = lua('return vim.api.nvim_buf_get_lines(0, 0, -1, false)')
    local text = table.concat(lines, '\n')
    assert(text:find('PRE-COMPACTION USER', 1, true))
    assert(not text:find('ABANDONED DECOY', 1, true))
    local window = lua('return vim.api.nvim_get_current_win()')
    for _, preview in ipairs(views) do
      local preview_row
      for index, line in ipairs(lines) do
        if line:match('^(%S+)') == preview.name then
          preview_row = index
          assert(not line:find('[gd:', 1, true), 'Unexpected navigation hint')
        end
      end
      assert(preview_row, 'Native transcript has no ' .. preview.name)
      lua('vim.api.nvim_win_set_cursor(0, { ..., 0 })', { preview_row })
      if preview.name == 'write' then
        assert(lua('return vim.fn.foldclosed(...)', { preview_row }) == preview_row)
        local folded = lua('return vim.fn.foldtextresult(...)', { preview_row })
        assert(folded:find('4 tool calls', 1, true))
        input('zo')
        await('return vim.fn.foldclosed(' .. preview_row .. ') == -1')
      end
      assert(lua('return vim.fn.foldclosed(...)', { preview_row }) == -1)
      input('gd')
      local target = (preview.prefix or 'pi-session-tool://') .. vim.fn.sha256(session.path)
        .. '/' .. vim.fn.sha256(preview.id)
      await('return vim.api.nvim_buf_get_name(0) == ' .. string.format('%q', target))
      assert(lua('return vim.bo.filetype') == (preview.filetype or 'markdown'))
      assert(lua('return vim.bo.readonly and not vim.bo.modifiable'))
      assert(lua('return vim.api.nvim_get_current_win()') == window)
      assert(lua('return #vim.api.nvim_list_wins()') == 1)
      assert(lua('return vim.api.nvim_get_mode().mode') == 'n')
      local body = table.concat(lua('return vim.api.nvim_buf_get_lines(0, 0, -1, false)'), '\n')
      check_preview(body, preview)
      input('\15')
      await('return vim.api.nvim_buf_get_name(0) == ' .. string.format('%q', expected))
      assert(lua('return vim.api.nvim_win_get_cursor(0)[1]') == preview_row)
    end
    assert(lua('return vim.v.errmsg') == '', lua('return vim.v.errmsg'))
    local recorded = lua('return rpc_observations')
    for key, values in pairs(recorded) do vim.list_extend(observations[key], values) end
  end, debug.traceback)
  pcall(vim.rpcrequest, job, 'nvim_command', 'qa!')
  if vim.fn.jobwait({ job }, 3000)[1] == -1 then
    vim.fn.jobstop(job)
    vim.fn.jobwait({ job }, 3000)
  end
  assert(ok, err)
end
