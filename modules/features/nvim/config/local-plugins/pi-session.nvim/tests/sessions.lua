local sessions = require('pi_session.sessions')
local uv = vim.uv

local function fixture(check)
  local directory = vim.fn.tempname()
  vim.fn.mkdir(directory, 'p', 448)
  local old_override = vim.env.PI_CODING_AGENT_SESSION_DIR
  vim.env.PI_CODING_AGENT_SESSION_DIR = nil
  local ok, err = xpcall(function() check(directory) end, debug.traceback)
  vim.env.PI_CODING_AGENT_SESSION_DIR = old_override
  vim.fn.delete(directory, 'rf')
  assert(ok, err)
end

local function save(path, cwd, id, entries)
  vim.fn.mkdir(vim.fs.dirname(path), 'p')
  local lines = { vim.json.encode({ type = 'session', version = 3, id = id, cwd = cwd }) }
  for _, entry in ipairs(entries or {}) do
    lines[#lines + 1] = vim.json.encode(entry)
  end
  assert(vim.fn.writefile(lines, path) == 0)
end

local function list(cwd, options)
  local complete, result, err = false, nil, nil
  sessions.list(cwd, options, function(error, records)
    err, result, complete = error, records, true
  end)
  assert(vim.wait(3000, function() return complete end, 5), 'Discovery timed out')
  return result, err
end

return function(test)
  -- Compare directory encoding against Pi's documented slash/colon convention, including root.
  test('session directory follows Pi cwd encoding', function()
    assert(sessions.directory('/a:b/c', { agent_dir = '/agent' }) == '/agent/sessions/--a-b-c--')
    assert(sessions.directory('/', { agent_dir = '/agent' }) == '/agent/sessions/----')
  end)

  -- An absent directory is normal on a new project and must not be reported as an I/O failure.
  test('new project has an empty session list', function()
    fixture(function(root)
      local records, err = list(root, { agent_dir = root .. '/agent' })
      assert(not err, err)
      assert(#records == 0)
    end)
  end)

  -- Filter headers as well as directory names: Pi's encoding can collide for /a-b and /a/b.
  test('session search cannot leak another project through encoded path collisions', function()
    fixture(function(root)
      local cwd, other = root .. '/a-b', root .. '/a/b'
      local options = { agent_dir = root .. '/agent' }
      local directory = sessions.directory(cwd, options)
      assert(directory == sessions.directory(other, options))
      save(directory .. '/one.jsonl', cwd, 'one', {
        { type = 'message', message = { role = 'user', content = 'First prompt\nsecond line' } },
      })
      save(directory .. '/other.jsonl', other, 'other')
      local records, err = list(cwd, options)
      assert(not err, err)
      assert(#records == 1 and records[1].id == 'one')
      assert(records[1].title == 'First prompt second line')
    end)
  end)

  -- The shared override directory still requires current-project filtering and newest-first order.
  test('custom session directory is filtered and sorted', function()
    fixture(function(root)
      local cwd, directory = root .. '/project', root .. '/shared'
      save(directory .. '/old.jsonl', cwd, 'old')
      save(directory .. '/new.jsonl', cwd, 'new', {
        { type = 'session_info', name = 'Newest session' },
      })
      save(directory .. '/other.jsonl', root .. '/elsewhere', 'other')
      assert(uv.fs_utime(directory .. '/old.jsonl', 100, 100))
      assert(uv.fs_utime(directory .. '/new.jsonl', 200, 200))
      vim.env.PI_CODING_AGENT_SESSION_DIR = directory
      local records, err = list(cwd, {})
      assert(not err, err)
      assert(#records == 2)
      assert(records[1].id == 'new' and records[2].id == 'old')
      assert(records[1].title == 'Newest session')
    end)
  end)

  -- Large tool payloads must not force full-session reads; names in the tail still work.
  test('bounded metadata reads skip huge records and recover a tail name', function()
    fixture(function(root)
      local cwd, directory = root .. '/project', root .. '/sessions'
      save(directory .. '/large.jsonl', cwd, 'large', {
        { type = 'message', message = { role = 'user', content = {
          { type = 'image', data = 'not-text' }, { type = 'text', text = 'Readable prompt' },
        } } },
        { type = 'custom', data = string.rep('x', 2 * 1024 * 1024) },
        { type = 'session_info', name = 'Final name' },
      })
      local original, bytes = uv.fs_read, 0
      uv.fs_read = function(fd, size, offset, callback)
        bytes = bytes + size
        return original(fd, size, offset, callback)
      end
      local ok, err = pcall(function()
        local records, read_error = list(cwd, { session_dir = directory, preview_bytes = 1024 })
        assert(not read_error, read_error)
        assert(#records == 1 and records[1].title == 'Final name')
        assert(records[1].preview == 'Readable prompt')
        assert(bytes <= 2048, 'Read beyond bounded metadata samples')
      end)
      uv.fs_read = original
      assert(ok, err)
    end)
  end)

  -- Bad unrelated files cannot prevent selection of a valid neighbor.
  test('malformed headers are skipped', function()
    fixture(function(root)
      save(root .. '/valid.jsonl', root, 'valid')
      vim.fn.writefile({ 'not json' }, root .. '/bad.jsonl')
      vim.fn.writefile({ '[]' }, root .. '/array.jsonl')
      local records, err = list(root, { session_dir = root })
      assert(not err, err)
      assert(#records == 1 and records[1].id == 'valid')
    end)
  end)

  -- A new command can cancel discovery before scheduled metadata work opens a picker.
  test('discovery cancellation suppresses stale callbacks', function()
    fixture(function(root)
      save(root .. '/one.jsonl', root, 'one')
      local called = false
      local cancel = sessions.list(root, { session_dir = root }, function() called = true end)
      cancel()
      vim.wait(20, function() return false end, 5)
      assert(not called)
    end)
  end)

  -- Exceeding the configured file cap must be explicit rather than silently dropping history.
  test('session cap reports a useful error', function()
    fixture(function(root)
      save(root .. '/one.jsonl', root, 'one')
      save(root .. '/two.jsonl', root, 'two')
      local records, err = list(root, { session_dir = root, max_sessions = 1 })
      assert(records == nil and err:find('max_sessions', 1, true))
    end)
  end)
end
