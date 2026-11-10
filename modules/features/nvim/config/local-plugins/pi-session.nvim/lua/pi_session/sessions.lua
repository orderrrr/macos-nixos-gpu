local M = {}
local uv = vim.uv

local function absolute(path)
  local normalized = vim.fs.normalize(vim.fn.fnamemodify(vim.fn.expand(path), ':p'))
  if normalized == '/' then
    return normalized
  end
  return normalized:gsub('/+$', '')
end

local function same_project(left, right)
  return (uv.fs_realpath(left) or absolute(left)) == (uv.fs_realpath(right) or absolute(right))
end

function M.directory(cwd, options)
  local override = options.session_dir or vim.env.PI_CODING_AGENT_SESSION_DIR
  if override and override ~= '' then
    return absolute(override)
  end
  local agent_dir = options.agent_dir or vim.env.PI_CODING_AGENT_DIR or '~/.pi/agent'
  local encoded = absolute(cwd):gsub('^[\\/]', ''):gsub('[\\/:]', '-')
  return absolute(agent_dir) .. '/sessions/--' .. encoded .. '--'
end

local function decode(line)
  local ok, value = pcall(vim.json.decode, line, { luanil = { object = true, array = true } })
  if ok and type(value) == 'table' then
    return value
  end
end

local function one_line(text, length)
  return vim.fn.strcharpart(text:gsub('%c', ' '):gsub('%s+', ' '), 0, length)
end

local function first_text(content)
  if type(content) == 'string' then
    return content
  end
  if type(content) == 'table' then
    for _, block in ipairs(content) do
      if type(block) == 'table' and block.type == 'text' and type(block.text) == 'string' then
        return block.text
      end
    end
  end
end

local function samples(path, maximum)
  -- Directory entries can change between discovery and opening; do not block on a FIFO.
  local flags = uv.constants.O_RDONLY + uv.constants.O_NONBLOCK
  local file, err = uv.fs_open(path, flags, 0)
  if not file then
    return nil, err
  end
  local stat, stat_error = uv.fs_fstat(file)
  if not stat or stat.type ~= 'file' then
    uv.fs_close(file)
    return nil, stat_error or 'Not a regular session file'
  end
  local prefix, read_error = uv.fs_read(file, math.min(stat.size, maximum), 0)
  local tail = ''
  if prefix and stat.size > maximum then
    local offset = math.max(maximum, stat.size - maximum)
    tail, read_error = uv.fs_read(file, stat.size - offset, offset)
    if tail then
      -- A tail sample may start inside a huge JSON record; never decode that fragment.
      tail = tail:match('\n(.*)') or ''
    end
  end
  local closed, close_error = uv.fs_close(file)
  if not prefix or not tail or not closed then
    return nil, read_error or close_error
  end
  return { prefix = prefix, tail = tail, stat = stat }
end

local function metadata(path, cwd, maximum)
  local sample, err = samples(path, maximum)
  if not sample then
    return nil, err
  end
  local header = decode(sample.prefix:match('([^\n]+)') or '')
  if not header or header.type ~= 'session' or type(header.id) ~= 'string' then
    return nil
  end
  if type(header.cwd) ~= 'string' or not same_project(header.cwd, cwd) then
    return nil
  end
  local preview, name = '', nil
  for _, text in ipairs({ sample.prefix, sample.tail }) do
    for line in text:gmatch('[^\n]+') do
      if line:find('"session_info"', 1, true) or preview == '' then
        local entry = decode(line)
        if entry and entry.type == 'session_info' and type(entry.name) == 'string' then
          if entry.name ~= '' then
            name = one_line(entry.name, 120)
          end
        elseif entry and entry.type == 'message' and type(entry.message) == 'table' then
          if preview == '' and entry.message.role == 'user' then
            preview = one_line(first_text(entry.message.content) or '', 200)
          end
        end
      end
    end
  end
  return {
    path = path, cwd = header.cwd, id = header.id,
    title = name or (preview ~= '' and preview or '(untitled session)'),
    preview = preview, modified = sample.stat.mtime.sec,
  }
end

--- Discover labels only. The selected conversation is always loaded through RPC.
--- Work is scheduled one bounded metadata sample at a time to keep the editor responsive.
function M.list(cwd, options, callback)
  local cancelled = false
  local directory = M.directory(cwd, options)
  local maximum = options.max_sessions or 2000
  local sample_bytes = options.preview_bytes or 65536
  local scan, scan_error, scan_code = uv.fs_scandir(directory)
  if not scan then
    vim.schedule(function()
      if not cancelled then
        if scan_code == 'ENOENT' then
          callback(nil, {})
        else
          callback(scan_error, nil)
        end
      end
    end)
    return function() cancelled = true end
  end
  local paths = {}
  for index = 1, maximum * 4 + 1 do
    local name, kind = uv.fs_scandir_next(scan)
    if not name then
      break
    end
    local is_session = kind == 'file' and name:sub(-6) == '.jsonl'
    if index > maximum * 4 or (is_session and #paths >= maximum) then
      vim.schedule(function()
        if not cancelled then
          callback('Too many session files; increase max_sessions', nil)
        end
      end)
      return function() cancelled = true end
    end
    if is_session then
      paths[#paths + 1] = directory .. '/' .. name
    end
  end
  local records, index, skipped = {}, 1, 0
  local function next_file()
    if cancelled then
      return
    end
    if index > #paths then
      table.sort(records, function(left, right)
        if left.modified == right.modified then
          return left.path > right.path
        end
        return left.modified > right.modified
      end)
      callback(nil, records, skipped)
      return
    end
    local record, err = metadata(paths[index], cwd, sample_bytes)
    if record then
      records[#records + 1] = record
    elseif err then
      skipped = skipped + 1
    end
    index = index + 1
    vim.schedule(next_file)
  end
  vim.schedule(next_file)
  return function() cancelled = true end
end

return M
