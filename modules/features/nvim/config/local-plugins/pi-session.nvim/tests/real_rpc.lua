-- Opt-in integration: launches installed Pi against synthetic data, never sends a prompt.
local rpc = require('pi_session.rpc')
local transcript = require('pi_session.transcript')
local uv = vim.uv
local patch = '--- absent.lua\n+++ absent.lua\n@@ -1 +1 @@\n-recorded before\n+recorded after\n'
local written = 'local from_session = true\n'
local command = 'printf "RECORDED COMMAND\\n"\nprintf executed > preview-sentinel'
local previews = {
  { name = 'bash', id = 'call_bash', arguments = { command = command },
    content = { { type = 'text', text = 'HISTORICAL BASH FIRST\nsecond line' },
      { type = 'text', text = 'HISTORICAL BASH LAST' } },
    contains = { command, 'HISTORICAL BASH FIRST\nsecond line', 'HISTORICAL BASH LAST' } },
  { name = 'read', id = 'call_read', arguments = { path = 'current.txt', offset = 2 },
    content = { { type = 'text', text = 'HISTORICAL READ VALUE' } },
    contains = { 'current.txt', '2', 'HISTORICAL READ VALUE' } },
  { name = 'custom_archive_probe', id = 'call_custom',
    arguments = { enabled = true, scope = { region = 'recorded-region', tags = { 'archived' } } },
    content = {}, details = { receipt = { token = 'DETAILS ONLY RECEIPT', count = 7 } },
    contains = { 'true', 'recorded-region', 'archived', 'DETAILS ONLY RECEIPT', '7' } },
}

local views = vim.list_extend({
  { name = 'edit', id = 'call_recorded', prefix = 'pi-session-diff://',
    filetype = 'diff' },
  { name = 'write', id = 'call_write', prefix = 'pi-session-write://' },
}, previews)

local function check_preview(content, preview)
  if preview.name == 'edit' then assert(content == patch); return end
  if preview.name == 'write' then
    assert(content:find(written, 1, true) and content:find('# Recorded write content', 1, true))
    return
  end
  assert(content:find(preview.name, 1, true) and content:find('done', 1, true))
  for _, value in ipairs(preview.contains) do
    assert(content:find(value, 1, true), 'Preview missing recorded value: ' .. value)
  end
  assert(not content:find('CURRENT FILE DECOY', 1, true), 'Preview read the current file')
  if preview.name == 'bash' then
    local fence = content:match('\n([~`]+)bash\n')
    assert(fence and #fence >= 3 and fence == string.rep(fence:sub(1, 1), #fence))
    assert(content:find(fence .. 'bash\n' .. command .. '\n' .. fence, 1, true))
    assert(content:find('HISTORICAL BASH FIRST', 1, true)
      < content:find('HISTORICAL BASH LAST', 1, true), 'Result text order changed')
  end
end

local function source_bytes(path)
  local file = assert(io.open(path, 'rb'))
  local value = file:read('*a')
  assert(file:close())
  return value
end

local function sample(cwd)
  local timestamp = '2026-01-01T00:00:00.000Z'
  local function entry(id, parent, kind, fields)
    return vim.tbl_extend('force', {
      type = kind, id = id, parentId = parent or vim.NIL, timestamp = timestamp,
    }, fields)
  end
  local function assistant(content)
    return { role = 'assistant', api = 'anthropic-messages', provider = 'anthropic',
      model = 'claude-sonnet-4-20250514', stopReason = 'toolUse', timestamp = 0,
      content = content, usage = { input = 0, output = 0, cacheRead = 0, cacheWrite = 0,
        totalTokens = 0,
        cost = { input = 0, output = 0, cacheRead = 0, cacheWrite = 0, total = 0 } } }
  end
  local records = {
    { type = 'session', version = 3, id = '11111111-2222-4333-8444-555555555555',
      timestamp = timestamp, cwd = cwd },
    entry('00000001', nil, 'message', {
      message = { role = 'user', content = 'PRE-COMPACTION USER', timestamp = 0 },
    }),
    entry('00000002', '00000001', 'message', {
      message = assistant({ { type = 'text', text = 'PRE-COMPACTION PI' } }),
    }),
    entry('00000003', '00000002', 'message', {
      message = { role = 'user', content = 'ABANDONED DECOY', timestamp = 0 },
    }),
    entry('00000004', '00000002', 'compaction', {
      summary = 'Synthetic compaction', firstKeptEntryId = '00000002', tokensBefore = 100,
    }),
    entry('00000005', '00000004', 'message', {
      message = { role = 'user', content = 'Show the recorded edit', timestamp = 0 },
    }),
    entry('00000006', '00000005', 'message', {
      message = assistant({ { type = 'text', text = 'PI BEFORE EDIT' },
        { type = 'toolCall', id = 'call_recorded', name = 'edit', arguments = {
          path = 'absent.lua', edits = { { oldText = 'WRONG PROPOSAL', newText = 'ALSO WRONG' } },
        } }, { type = 'text', text = 'PI AFTER EDIT' } }),
    }),
    entry('00000007', '00000006', 'message', { message = {
      role = 'toolResult', toolCallId = 'call_recorded', toolName = 'edit', isError = false,
      timestamp = 0, content = { { type = 'text', text = 'Recorded success' } },
      details = { patch = patch, diff = 'NOT THE PREFERRED PATCH', firstChangedLine = 1 },
    } }),
    entry('00000008', '00000007', 'message', { message = assistant({
      { type = 'toolCall', id = 'call_write', name = 'write', arguments = {
        path = 'never-written.lua', content = written,
      } },
    }) }),
    entry('00000009', '00000008', 'message', { message = {
      role = 'toolResult', toolCallId = 'call_write', toolName = 'write', isError = false,
      timestamp = 0, content = { { type = 'text', text = 'Successfully wrote content' } },
    } }),
    entry('0000000a', '00000009', 'session_info', { name = 'Synthetic RPC session' }),
  }
  local parent = '0000000a'
  for index, preview in ipairs(previews) do
    local call_id, result_id = string.format('%08x', 10 + index * 2 - 1),
      string.format('%08x', 10 + index * 2)
    records[#records + 1] = entry(call_id, parent, 'message', { message = assistant({
      { type = 'toolCall', id = preview.id, name = preview.name, arguments = preview.arguments },
    }) })
    records[#records + 1] = entry(result_id, call_id, 'message', { message = {
      role = 'toolResult', toolCallId = preview.id, toolName = preview.name, isError = false,
      timestamp = 0, content = preview.content, details = preview.details,
    } })
    parent = result_id
  end
  return records
end

local function fixture(check)
  local root = assert(uv.fs_mkdtemp(vim.fn.tempname() .. '-pi-real-XXXXXX'))
  local cwd, old_cwd = root .. '/project', vim.fn.getcwd()
  vim.fn.mkdir(cwd, 'p', 448)
  assert(vim.fn.writefile({ 'CURRENT FILE DECOY' }, cwd .. '/current.txt') == 0)
  local path = root .. '/session.jsonl'
  local lines = {}
  for _, record in ipairs(sample(cwd)) do lines[#lines + 1] = vim.json.encode(record) end
  assert(vim.fn.writefile(lines, path) == 0)
  local original = vim.fn.sha256(source_bytes(path))
  local directories, requests, pids = {}, {}, {}
  local mkdtemp, chansend, jobstart = uv.fs_mkdtemp, vim.fn.chansend, vim.fn.jobstart
  uv.fs_mkdtemp = function(template)
    local directory, err = mkdtemp(template)
    if directory then directories[#directories + 1] = directory end
    return directory, err
  end
  vim.fn.chansend = function(job, value)
    requests[#requests + 1] = vim.json.decode(value)
    return chansend(job, value)
  end
  vim.fn.jobstart = function(command, options)
    local job = jobstart(command, options)
    if job > 0 then pids[#pids + 1] = vim.fn.jobpid(job) end
    return job
  end
  local ok, err = xpcall(function()
    -- Any accidental execution must be confined to and detected inside this fixture.
    vim.cmd('cd ' .. vim.fn.fnameescape(cwd))
    check({ path = path, cwd = cwd, title = 'Synthetic' }, root,
      { directories = directories, requests = requests, pids = pids })
  end, debug.traceback)
  uv.fs_mkdtemp, vim.fn.chansend, vim.fn.jobstart = mkdtemp, chansend, jobstart
  vim.cmd('silent! stopinsert')
  vim.cmd('cd ' .. vim.fn.fnameescape(old_cwd))
  local preserved = vim.fn.sha256(source_bytes(path)) == original
  local sentinel_absent = uv.fs_stat(cwd .. '/preview-sentinel') == nil
  local clean = true
  for _, directory in ipairs(directories) do clean = clean and uv.fs_stat(directory) == nil end
  for _, pid in ipairs(pids) do clean = clean and not uv.kill(pid, 0) end
  vim.fn.delete(root, 'rf')
  assert(ok, err)
  assert(preserved, 'Installed Pi changed the original fixture')
  assert(sentinel_absent, 'A recorded shell command was executed')
  assert(clean, 'Snapshot or Pi child was not cleaned up')
  assert(#requests == 1 and requests[1].type == 'get_entries',
    'Unexpected RPC command/model prompt')
end

local function check_buffer(buffer, session)
  local lines = vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
  local text = table.concat(lines, '\n')
  assert(text:find('PRE-COMPACTION USER', 1, true))
  assert(text:find('PRE-COMPACTION PI', 1, true))
  assert(not text:find('ABANDONED DECOY', 1, true))
  assert(not text:find('WRONG PROPOSAL', 1, true))
  local key = vim.api.nvim_replace_termcodes('<C-o>', true, false, true)
  local window = vim.api.nvim_get_current_win()
  for _, preview in ipairs(views) do
    local preview_row
    for index, line in ipairs(lines) do
      if line:match('^(%S+)') == preview.name then
        preview_row = index
        assert(not line:find('[gd:', 1, true), 'Unexpected navigation hint')
        assert(not line:find(' — done', 1, true), 'Unexpected success boilerplate')
      end
    end
    assert(preview_row, 'Recorded tool is missing: ' .. preview.name)
    vim.api.nvim_win_set_cursor(0, { preview_row, 0 })
    if preview.name == 'write' then
      assert(vim.fn.foldclosed(preview_row) == preview_row)
      assert(vim.fn.foldtextresult(preview_row):find('4 tool calls', 1, true))
      vim.api.nvim_feedkeys('zo', 'xt', false)
    end
    assert(vim.fn.foldclosed(preview_row) == -1)
    vim.api.nvim_feedkeys('gd', 'xt', false)
    local expected = (preview.prefix or 'pi-session-tool://') .. vim.fn.sha256(session.path)
      .. '/' .. vim.fn.sha256(preview.id)
    assert(vim.api.nvim_buf_get_name(0) == expected)
    assert(vim.bo.filetype == (preview.filetype or 'markdown'))
    assert(not vim.bo.modifiable and vim.bo.readonly)
    assert(vim.api.nvim_get_current_win() == window and #vim.api.nvim_list_wins() == 1)
    check_preview(table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n'), preview)
    vim.api.nvim_feedkeys(key, 'xt', false)
    assert(vim.api.nvim_get_current_buf() == buffer)
    assert(vim.api.nvim_win_get_cursor(0)[1] == preview_row)
  end
end

return function(test)
  test('installed Pi returns full archival entries and recorded patches without modifying source',
    function()
      fixture(function(session)
        local done, data, err = false, nil, nil
        local cancel = rpc.load(session, {}, function(error, result)
          done, err, data = true, error, result
        end)
        local finished = vim.wait(20000, function() return done end, 10)
        if not finished then cancel() end
        assert(finished, 'Installed Pi did not finish')
        assert(not err, err)
        assert(#data.entries >= 16, 'History was compacted instead of archived')
        local buffer, render_error = transcript.open(session, data)
        assert(buffer, render_error)
        check_buffer(buffer, session)
        assert(not uv.fs_stat(session.cwd .. '/absent.lua'), 'A recorded edit was executed')
        assert(not uv.fs_stat(session.cwd .. '/never-written.lua'), 'A recorded write was executed')
      end)
    end)

  test('PISession Telescope selection drives real RPC into one native transcript buffer', function()
    fixture(function(session, root, observations)
      local tests = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h')
      dofile(tests .. '/native_ui.lua')(
        session, root, observations, views, check_preview)
    end)
  end)
end
