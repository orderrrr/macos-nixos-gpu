local rpc = require('pi_session.rpc')
local uv = vim.uv or vim.loop
local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p')
  :match('^(.*)/tests/rpc.lua$')
local python = vim.fn.exepath('python3')

local function bytes(path)
  local file = assert(io.open(path, 'rb'))
  local value = file:read('*a')
  file:close()
  return value
end

local function write(path, value)
  local file = assert(io.open(path, 'wb'))
  assert(file:write(value))
  assert(file:close())
end

local function load(context, mode, overrides)
  local options = vim.tbl_extend('force', {
    command = { python, root .. '/tests/fixtures/fake_rpc.py', mode, context.record },
    timeout_ms = 2500,
  }, overrides or {})
  local result = { count = 0 }
  result.cancel = rpc.load({ path = context.source, cwd = context.directory }, options,
    function(err, data)
      assert(not vim.in_fast_event(), 'Callback must run on the main loop')
      result.count = result.count + 1
      result.err, result.data = err, data
    end)
  assert(result.count == 0, 'Callback must not run inline')
  context.cancellations[#context.cancellations + 1] = result.cancel
  return result
end

local function await(result)
  assert(vim.wait(6000, function() return result.count > 0 end, 5), 'RPC callback hung')
  vim.wait(30, function() return false end, 5)
  assert(result.count == 1, 'Callback ran more than once')
  return result
end

local function record(context)
  return vim.json.decode(bytes(context.record))
end

local function cleaned(context)
  for _, directory in ipairs(context.snapshots) do
    assert(not uv.fs_stat(directory), 'Private snapshot leaked: ' .. directory)
  end
  assert(bytes(context.source) == context.original, 'Original session was modified')
  if uv.fs_stat(context.record) then
    local info = record(context)
    assert(not uv.fs_stat(info.directory), 'Backend snapshot leaked')
    assert(not uv.kill(info.pid, 0), 'Backend process still exists')
  end
end

return function(test)
  local function case(description, body)
    test(description, function()
      assert(python ~= '', 'The offline RPC fixture needs python3')
      local context = {
        directory = assert(uv.fs_mkdtemp(vim.fn.tempname() .. '-rpc-test-XXXXXX')),
        original = '{"type":"session","version":3,"id":"original"}\n',
        cancellations = {},
        snapshots = {},
      }
      context.source = context.directory .. '/original.jsonl'
      context.record = context.directory .. '/record.json'
      write(context.source, context.original)
      local mkdtemp = uv.fs_mkdtemp
      uv.fs_mkdtemp = function(template)
        local directory, err = mkdtemp(template)
        if directory then
          context.snapshots[#context.snapshots + 1] = directory
        end
        return directory, err
      end
      local ok, err = xpcall(function() body(context) end, debug.traceback)
      for _, cancel in ipairs(context.cancellations) do cancel() end
      vim.wait(50, function() return false end, 5)
      uv.fs_mkdtemp = mkdtemp
      local clean_ok, clean_err = pcall(cleaned, context)
      vim.fn.delete(context.directory, 'rf')
      assert(ok, err)
      assert(clean_ok, clean_err)
    end)
  end

  case('RPC isolates source, enforces safe flags and cancels dialogs', function(context)
    -- The peer validates argv and mutates its copy; inspect permissions and digest afterward.
    local upper, lower = vim.env.NPM_CONFIG_PREFIX, vim.env.npm_config_prefix
    local agent_dir = vim.env.PI_CODING_AGENT_DIR
    vim.env.NPM_CONFIG_PREFIX, vim.env.npm_config_prefix = 'upper-secret', 'lower-secret'
    vim.env.PI_CODING_AGENT_DIR = 'inherited-agent'
    local result = await(load(context, 'success', { agent_dir = '/private/explicit-agent' }))
    local same_env = vim.env.NPM_CONFIG_PREFIX == 'upper-secret'
      and vim.env.npm_config_prefix == 'lower-secret'
      and vim.env.PI_CODING_AGENT_DIR == 'inherited-agent'
    vim.env.NPM_CONFIG_PREFIX, vim.env.npm_config_prefix = upper, lower
    vim.env.PI_CODING_AGENT_DIR = agent_dir
    assert(not result.err, result.err)
    assert(result.data.leafId == 'archive')
    assert(result.data.entries[1].text == 'café 雪\226\128\168tail\226\128\169end')
    local info = record(context)
    assert(info.snapshot ~= context.source)
    assert(uv.fs_realpath(info.cwd) == uv.fs_realpath(context.directory))
    assert(info.directory_mode == 448 and info.file_mode == 384)
    assert(info.digest == vim.fn.sha256(context.original))
    assert(info.agent_dir == '/private/explicit-agent')
    assert(info.npm_upper == vim.NIL and info.npm_lower == vim.NIL and same_env)
    assert(#info.requests == 5)
    assert(info.requests[1].type == 'get_entries')
    for index = 2, 5 do
      assert(info.requests[index].type == 'extension_ui_response')
      assert(info.requests[index].cancelled == true)
    end
  end)

  case('RPC preserves null leaves and inherits the agent environment', function(context)
    -- JSON null is a meaningful leaf value, unlike a missing field.
    local previous = vim.env.PI_CODING_AGENT_DIR
    vim.env.PI_CODING_AGENT_DIR = '/private/inherited-agent'
    local result = await(load(context, 'null'))
    vim.env.PI_CODING_AGENT_DIR = previous
    assert(not result.err, result.err)
    assert(result.data.leafId == vim.NIL and #result.data.entries == 0)
    assert(record(context).agent_dir == '/private/inherited-agent')
  end)

  local failures = {
    { 'malformed', 'Malformed RPC JSONL frame' },
    { 'blank', 'Malformed RPC JSONL frame' },
    { 'events_cap', 'response exceeds', { max_bytes = 1024 } },
    { 'failed', 'get_entries failed' },
    { 'wrongcommand', 'Unexpected command' },
    { 'baddata', 'Malformed get_entries data' },
    { 'missing_leaf', 'Malformed get_entries data' },
    { 'early', 'exited before get_entries' },
    { 'unterminated', 'exited before get_entries' },
    { 'unrelated', 'exited before get_entries' },
    { 'stderr', 'stderr exceeds' },
    { 'oversize', 'response exceeds', { max_bytes = 1024 } },
    { 'timeout', 'timed out', { timeout_ms = 150 } },
    { 'stubborn', 'timed out', { timeout_ms = 150 } },
  }
  for _, failure in ipairs(failures) do
    case('RPC rejects ' .. failure[1] .. ' and cleans up', function(context)
      -- Each fixture induces exactly one transport/protocol failure without models.
      local result = await(load(context, failure[1], failure[3]))
      assert(result.err and result.err:find(failure[2], 1, true), result.err)
      assert(not result.err:find('PRIVATE', 1, true), 'Error leaked backend content')
      assert(result.data == nil)
    end)
  end

  case('RPC rejects an oversized source before spawning', function(context)
    -- The source cap must apply to the private copy, not just the response.
    local result = await(load(context, 'success', { max_bytes = 10 }))
    assert(result.err:find('source exceeds', 1, true), result.err)
    assert(not uv.fs_stat(context.record))
  end)

  case('RPC handles missing source and spawn failure without leaking snapshots', function(context)
    -- Exercise both filesystem acquisition and jobstart failure after a full copy.
    vim.fn.delete(context.source)
    local missing = await(load(context, 'success'))
    assert(missing.err:find('snapshot open failed', 1, true), missing.err)
    write(context.source, context.original)
    local jobstart = vim.fn.jobstart
    vim.fn.jobstart = function() return 0 end
    local result = await(load(context, 'success'))
    vim.fn.jobstart = jobstart
    assert(result.err == 'Could not spawn RPC process', result.err)
  end)

  case('RPC does not silently fall back from a missing configured launcher', function(context)
    -- No real Pi is launched: the configured executable is deliberately absent.
    local previous = vim.env.PI_NIX_LAUNCHER
    vim.env.PI_NIX_LAUNCHER = context.directory .. '/missing-launcher'
    local count, err = 0, nil
    rpc.load({ path = context.source, cwd = context.directory }, {}, function(error)
      count, err = count + 1, error
    end)
    assert(vim.wait(1000, function() return count > 0 end, 5))
    vim.env.PI_NIX_LAUNCHER = previous
    assert(count == 1 and err == 'RPC launcher is not executable', err)
    assert(#context.snapshots == 0)
  end)

  case('RPC defaults to the configured launcher without starting real Pi', function(context)
    -- A private executable forwards to the offline peer and records the received flags.
    local launcher = context.directory .. '/launcher'
    write(launcher, '#!/bin/sh\nexec ' .. vim.fn.shellescape(python) .. ' '
      .. vim.fn.shellescape(root .. '/tests/fixtures/fake_rpc.py') .. ' null '
      .. vim.fn.shellescape(context.record) .. ' "$@"\n')
    assert(uv.fs_chmod(launcher, 448))
    local previous = vim.env.PI_NIX_LAUNCHER
    vim.env.PI_NIX_LAUNCHER = launcher
    local result = { count = 0 }
    local cancel = rpc.load({ path = context.source, cwd = context.directory }, {},
      function(err, data)
        result.count = result.count + 1
        result.err, result.data = err, data
      end)
    context.cancellations[#context.cancellations + 1] = cancel
    local ok, err = pcall(await, result)
    vim.env.PI_NIX_LAUNCHER = previous
    assert(ok, err)
    assert(not result.err, result.err)
    assert(result.data.leafId == vim.NIL)
  end)

  case('RPC cancellation during child execution is idempotent', function(context)
    -- Wait for the peer to record its PID, then cancel an otherwise blocked request.
    local result = load(context, 'timeout')
    assert(vim.wait(2000, function() return uv.fs_stat(context.record) ~= nil end, 5))
    result.cancel()
    result.cancel()
    await(result)
    result.cancel()
    assert(result.err == 'cancelled' and result.data == nil)
  end)

  case('RPC cancellation during copy closes the outstanding descriptor', function(context)
    -- Hold the asynchronous open callback until cancellation has been processed.
    local open = uv.fs_open
    local held
    uv.fs_open = function(path, flags, mode, callback)
      if path == context.source and callback then
        return open(path, flags, mode, function(err, descriptor)
          held = function() callback(err, descriptor) end
        end)
      end
      return open(path, flags, mode, callback)
    end
    local result = load(context, 'success')
    local ready = vim.wait(1000, function() return held ~= nil end, 5)
    result.cancel()
    vim.wait(20, function() return false end, 5)
    assert(result.count == 0, 'Cleanup must wait for the outstanding open')
    uv.fs_open = open
    assert(ready, 'Copy never opened its source')
    held()
    await(result)
    assert(result.err == 'cancelled')
    assert(not uv.fs_stat(context.record), 'Cancellation still spawned a backend')
  end)

  case('RPC copies multiple bounded chunks without altering source bytes', function(context)
    -- A source larger than one copy chunk checks offsets and preservation across writes.
    context.original = context.original .. string.rep('session-byte-雪\n', 10000)
    write(context.source, context.original)
    local result = await(load(context, 'null'))
    assert(not result.err, result.err)
    assert(record(context).digest == vim.fn.sha256(context.original))
  end)

  case('RPC applies its total deadline while copying', function(context)
    -- Withhold an open callback until the timer expires, then release its descriptor.
    local open, held = uv.fs_open, nil
    uv.fs_open = function(path, flags, mode, callback)
      return open(path, flags, mode, function(err, descriptor)
        held = function() callback(err, descriptor) end
      end)
    end
    local result = load(context, 'success', { timeout_ms = 30 })
    local ready = vim.wait(1000, function() return held ~= nil end, 5)
    uv.fs_open = open
    assert(ready)
    vim.wait(80, function() return false end, 5)
    held()
    await(result)
    assert(result.err == 'RPC load timed out')
    assert(not uv.fs_stat(context.record))
  end)

  case('RPC kills its child and removes its private directory on Neovim shutdown', function(context)
    -- A nested clean Neovim exits with an unanswered request; the outer test checks ownership.
    local script = context.directory .. '/shutdown.lua'
    local source = string.format([[
vim.opt.rtp:prepend(%q)
require('pi_session.rpc').load({ path = %q, cwd = %q }, {
  command = { %q, %q, 'timeout', %q }, timeout_ms = 10000,
}, function() error('Unexpected snapshot callback') end)
assert(vim.wait(3000, function() return vim.uv.fs_stat(%q) ~= nil end, 5))
vim.cmd('qa!')
]], root, context.source, context.directory, python,
      root .. '/tests/fixtures/fake_rpc.py', context.record, context.record)
    write(script, source)
    local process = vim.system({ vim.v.progpath, '--headless', '-u', 'NONE', '-l', script },
      { text = true }):wait(5000)
    assert(process.code == 0, process.stderr)
    local info = record(context)
    assert(vim.wait(1000, function() return not uv.kill(info.pid, 0) end, 5))
    assert(not uv.fs_stat(info.directory))
  end)

  case('RPC repeated success and cancellation deliver only one callback', function(context)
    -- A duplicate response and late cancellation cannot replace the first snapshot.
    local result = await(load(context, 'duplicate'))
    result.cancel()
    result.cancel()
    vim.wait(50, function() return false end, 5)
    assert(result.count == 1 and not result.err, result.err)
  end)

  case('RPC reconstructs empty job chunks and split UTF-8', function(context)
    -- Inject exact jobstart list shapes independently of OS pipe coalescing.
    local saved = { vim.fn.jobstart, vim.fn.chansend, vim.fn.chanclose, vim.fn.jobstop }
    local callbacks
    vim.fn.jobstart = function(_, options) callbacks = options; return 12345 end
    vim.fn.chanclose = function() return 1 end
    vim.fn.jobstop = function()
      vim.schedule(function() callbacks.on_exit(12345, 0) end)
      return 1
    end
    vim.fn.chansend = function(_, text)
      local request = vim.json.decode(text)
      vim.schedule(function()
        callbacks.on_stdout(12345, { '{"type":"agent_start"}', '' })
        callbacks.on_stdout(12345, { '' })
        local frame = vim.json.encode({ type = 'response', command = 'get_entries',
          id = request.id, success = true,
          data = { entries = { { text = '雪\226\128\168' } }, leafId = vim.NIL } })
        for index = 1, #frame do
          callbacks.on_stdout(12345, { frame:sub(index, index) })
          callbacks.on_stdout(12345, { '' })
        end
        callbacks.on_stdout(12345, { '\r' })
        callbacks.on_stdout(12345, { '', '' })
        callbacks.on_stdout(12345, { '' })
      end)
      return #text
    end
    local ok, result = pcall(function() return await(load(context, 'unused')) end)
    vim.fn.jobstart, vim.fn.chansend, vim.fn.chanclose, vim.fn.jobstop = unpack(saved)
    assert(ok, result)
    assert(not result.err, result.err)
    assert(result.data.entries[1].text == '雪\226\128\168')
  end)
end
