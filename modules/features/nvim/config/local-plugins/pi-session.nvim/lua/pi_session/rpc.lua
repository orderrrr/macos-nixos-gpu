local M = {}
local Loader = {}
Loader.__index = Loader
local uv = vim.uv or vim.loop
local active = {}
local sequence = 0
local chunk_bytes = 64 * 1024
local stderr_bytes_max = 64 * 1024

-- Each loader owns one child and one private snapshot, never the original session.
function M.load(session, options, callback)
  assert(type(session) == 'table' and type(session.path) == 'string')
  assert(type(session.cwd) == 'string' and type(callback) == 'function')
  options = options or {}
  sequence = sequence + 1
  local self = setmetatable({
    session = session,
    options = options,
    callback = callback,
    request_id = 'pi-session-' .. sequence,
    max_bytes = options.max_bytes or 64 * 1024 * 1024,
    stdout_bytes = 0,
    stderr_bytes = 0,
    fragments = {},
    offset = 0,
  }, Loader)
  active[self] = true
  -- Start on the main loop even when validation or resource acquisition fails.
  vim.schedule(function()
    if not self.result then
      self:start()
    end
  end)
  return function()
    vim.schedule(function()
      self:finish('cancelled')
    end)
  end
end

function Loader:finish(err, data)
  if self.result then
    return
  end
  self.result = { err = err, data = data }
  self.fragments = nil
  if self.timer then
    self.timer:stop()
    self.timer:close()
    self.timer = nil
  end
  if self.job then
    -- jobstop escalates to SIGKILL after its bounded grace period.
    pcall(vim.fn.chanclose, self.job, 'stdin')
    pcall(vim.fn.jobstop, self.job)
  end
  self:cleanup()
end

function Loader:cleanup()
  if not self.result or self.job or self.pending or not self.callback then
    return
  end
  for _, field in ipairs({ 'source', 'target' }) do
    if self[field] then
      local ok = uv.fs_close(self[field])
      self[field] = nil
      if not ok then
        self.result = { err = 'Could not close session snapshot file' }
      end
    end
  end
  if self.directory then
    if vim.fn.delete(self.directory, 'rf') ~= 0 then
      self.result = { err = 'Could not remove private session snapshot' }
    end
    self.directory = nil
  end
  active[self] = nil
  self.copy_bytes = nil
  local callback = self.callback
  self.callback = nil
  local result = self.result
  self.result = {}
  vim.schedule(function()
    callback(result.err, result.data)
  end)
end

-- Only one bounded filesystem request is outstanding; cancellation waits for its
-- callback to adopt any newly opened descriptor before releasing owned resources.
function Loader:filesystem(operation, arguments, next_step, resource)
  self.pending = true
  arguments[#arguments + 1] = vim.schedule_wrap(function(err, value)
    self.pending = nil
    if not err and resource then
      self[resource] = value
    end
    if self.result then
      self:cleanup()
    elseif err then
      self:finish('Session snapshot ' .. operation .. ' failed')
    else
      next_step(value)
    end
  end)
  local request = uv['fs_' .. operation](unpack(arguments))
  if not request then
    self.pending = nil
    self:finish('Session snapshot ' .. operation .. ' could not start')
  end
end

function Loader:start()
  local timeout_ms = self.options.timeout_ms or 15000
  if type(self.max_bytes) ~= 'number' or self.max_bytes < 1
    or self.max_bytes == math.huge or self.max_bytes % 1 ~= 0
    or type(timeout_ms) ~= 'number' or timeout_ms < 1
    or timeout_ms == math.huge or timeout_ms % 1 ~= 0 then
    return self:finish('Invalid RPC size or timeout limit')
  end
  if self.session.path:sub(1, 1) ~= '/' then
    return self:finish('Session path must be absolute')
  end
  if self.options.agent_dir ~= nil and type(self.options.agent_dir) ~= 'string' then
    return self:finish('RPC agent_dir must be a string')
  end
  local command = self.options.command
  if command == nil then
    command = { vim.env.PI_NIX_LAUNCHER or 'pi' }
  end
  if type(command) ~= 'table' or not vim.islist(command) or #command == 0 then
    return self:finish('RPC command must be a nonempty argv list')
  end
  for _, argument in ipairs(command) do
    if type(argument) ~= 'string' or argument:find('\0', 1, true) then
      return self:finish('Invalid RPC command argument')
    end
  end
  if vim.fn.executable(command[1]) ~= 1 then
    return self:finish('RPC launcher is not executable')
  end
  self.command = vim.list_extend({ 'env', '-u', 'NPM_CONFIG_PREFIX', '-u',
    'npm_config_prefix' }, command)
  self.timer = uv.new_timer()
  if not self.timer then
    return self:finish('Could not create RPC deadline timer')
  end
  self.timer:start(timeout_ms, 0, vim.schedule_wrap(function()
    self:finish('RPC load timed out')
  end))
  self.directory = uv.fs_mkdtemp(vim.fn.tempname() .. '-pi-session-XXXXXX')
  if not self.directory then
    return self:finish('Could not create private session directory')
  end
  -- O_NONBLOCK prevents a replaced source (for example a FIFO) from hanging open.
  local read_flags = uv.constants.O_RDONLY + uv.constants.O_NONBLOCK
  self:filesystem('open', { self.session.path, read_flags, 0 }, function()
    self:filesystem('fstat', { self.source }, function(stat)
      if stat.type ~= 'file' then
        return self:finish('Session source is not a regular file')
      end
      if stat.size > self.max_bytes then
        return self:finish('Session source exceeds max_bytes')
      end
      self.size = stat.size
      self:filesystem('open', { self.directory .. '/session.jsonl', 'wx', 384 }, function()
        self:copy_read()
      end, 'target')
    end)
  end, 'source')
end

function Loader:copy_read()
  if self.offset == self.size then
    for _, field in ipairs({ 'source', 'target' }) do
      local ok = uv.fs_close(self[field])
      self[field] = nil
      if not ok then
        return self:finish('Could not close session snapshot file')
      end
    end
    return self:spawn()
  end
  -- Fix the copy length at fstat time so a growing source cannot exhaust disk.
  self:filesystem('read', { self.source, math.min(chunk_bytes, self.size - self.offset),
    self.offset }, function(bytes)
    if #bytes == 0 then
      return self:finish('Session source changed during snapshot')
    end
    self.copy_bytes = bytes
    self:copy_write()
  end)
end

function Loader:copy_write()
  self:filesystem('write', { self.target, self.copy_bytes, self.offset }, function(count)
    if count == 0 then
      return self:finish('Session snapshot write made no progress')
    end
    self.offset = self.offset + count
    if count < #self.copy_bytes then
      self.copy_bytes = self.copy_bytes:sub(count + 1)
      return self:copy_write()
    end
    self.copy_bytes = nil
    self:copy_read()
  end)
end

function Loader:spawn()
  local arguments = { '--mode', 'rpc', '--session', self.directory .. '/session.jsonl',
    '--session-dir', self.directory, '--no-extensions', '--no-skills',
    '--no-prompt-templates', '--no-themes', '--no-context-files', '--no-tools',
    '--no-approve', '--offline' }
  local environment = vim.empty_dict()
  if self.options.agent_dir ~= nil then
    environment.PI_CODING_AGENT_DIR = self.options.agent_dir
  end
  local ok, job = pcall(vim.fn.jobstart, vim.list_extend(self.command, arguments), {
    cwd = self.session.cwd,
    env = environment,
    stdin = 'pipe',
    stdout_buffered = false,
    stderr_buffered = false,
    on_stdout = function(_, data)
      self:stdout(data)
    end,
    on_stderr = function(_, data)
      if self.result then
        return
      end
      for index, part in ipairs(data) do
        self.stderr_bytes = self.stderr_bytes + #part + (index > 1 and 1 or 0)
        if self.stderr_bytes > stderr_bytes_max then
          return self:finish('RPC stderr exceeds 65536 bytes')
        end
      end
    end,
    on_exit = function(_, code)
      self.job = nil
      if not self.result then
        self:finish('RPC exited before get_entries response (exit ' .. code .. ')')
      else
        self:cleanup()
      end
    end,
  })
  if not ok or job <= 0 then
    return self:finish('Could not spawn RPC process')
  end
  self.job = job
  self:send({ id = self.request_id, type = 'get_entries' })
end

function Loader:send(message)
  local ok, count = pcall(vim.fn.chansend, self.job, vim.json.encode(message) .. '\n')
  if not ok or count == 0 then
    self:finish('Could not send RPC request')
  end
end

function Loader:stdout(data)
  if self.result then
    return
  end
  -- Job lists encode LF boundaries only between elements, not between callbacks.
  -- Retain raw bytes until a full frame exists, including fragmented UTF-8 and CRLF.
  for index, part in ipairs(data) do
    self.stdout_bytes = self.stdout_bytes + #part + (index > 1 and 1 or 0)
    if self.stdout_bytes > self.max_bytes then
      return self:finish('RPC response exceeds max_bytes')
    end
    if index > 1 then
      local frame = table.concat(self.fragments)
      self.fragments = {}
      self:frame(frame:gsub('\r$', ''))
      if self.result then
        return
      end
    end
    if #part > 0 then
      self.fragments[#self.fragments + 1] = part
    end
  end
end

function Loader:frame(frame)
  local ok, message = pcall(vim.json.decode, frame)
  if not ok or type(message) ~= 'table' or type(message.type) ~= 'string' then
    return self:finish('Malformed RPC JSONL frame')
  end
  if message.type == 'extension_ui_request' then
    local dialogs = { select = true, confirm = true, input = true, editor = true }
    if dialogs[message.method] then
      if type(message.id) ~= 'string' then
        return self:finish('Malformed RPC extension dialog')
      end
      self:send({ type = 'extension_ui_response', id = message.id, cancelled = true })
    end
    return
  end
  if message.type ~= 'response' or message.id ~= self.request_id then
    return
  end
  if message.command ~= 'get_entries' then
    return self:finish('Unexpected command in get_entries response')
  end
  if message.success ~= true then
    -- Backend errors and stderr may contain private session text; never echo them.
    return self:finish('RPC get_entries failed')
  end
  local data = message.data
  if type(data) ~= 'table' or type(data.entries) ~= 'table' or not vim.islist(data.entries)
    or (type(data.leafId) ~= 'string' and data.leafId ~= vim.NIL) then
    return self:finish('Malformed get_entries data')
  end
  self:finish(nil, data)
end

vim.api.nvim_create_autocmd('VimLeavePre', {
  callback = function()
    for self in pairs(active) do
      -- Neovim will no longer dispatch job/filesystem callbacks during teardown.
      -- Kill before unlinking so an uncooperative child cannot keep writing copies.
      if self.job then
        local ok, pid = pcall(vim.fn.jobpid, self.job)
        if ok then
          uv.kill(pid, 'sigkill')
        end
      end
      if self.directory then
        vim.fn.delete(self.directory, 'rf')
      end
    end
  end,
})

return M
