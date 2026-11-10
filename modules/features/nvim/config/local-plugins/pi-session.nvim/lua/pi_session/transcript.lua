local M = {}
local preview = require("pi_session.preview")
local folds = require("pi_session.folds")
local render, open, jump

function M.render(session, data)
  local ok, document = pcall(render, session, data)
  if not ok then return nil, tostring(document) end
  return document
end

function M.open(session, data, window)
  local document, err = M.render(session, data)
  if not document then return nil, err end
  window = window or vim.api.nvim_get_current_win()
  if not vim.api.nvim_win_is_valid(window) then return nil, "Snapshot window is closed" end
  local ok, buffer = pcall(open, session, document, window)
  if not ok then return nil, tostring(buffer) end
  return buffer
end

local function check(condition, message)
  if not condition then error(message, 0) end
end

local function id(value)
  return type(value) == "string" and #value > 0 and #value <= 1024
    and not value:find("[%c]")
end

local function array(value)
  return type(value) == "table" and vim.islist(value)
end

-- Bound even ignored payloads, without recursively trusting decoded structures.
local function bounded(data)
  local stack, seen, nodes, bytes = { data }, {}, 0, 0
  while #stack > 0 do
    local value = table.remove(stack)
    if type(value) == "table" and not seen[value] then
      seen[value] = true
      for key, child in pairs(value) do
        nodes = nodes + 1
        check(nodes <= 500000, "Snapshot has too many fields")
        if type(key) == "string" then bytes = bytes + #key end
        if type(child) == "string" then bytes = bytes + #child end
        check(bytes <= 32 * 1024 * 1024, "Snapshot exceeds 32 MiB")
        if type(child) == "table" then stack[#stack + 1] = child end
      end
    end
  end
end

local function branch(data)
  check(type(data) == "table" and array(data.entries), "Expected an entries array")
  check(#data.entries <= 50000, "Snapshot has too many entries")
  check(data.leafId == vim.NIL or id(data.leafId), "Invalid leaf ID")
  bounded(data)
  local entries, done = {}, {}
  for _, entry in ipairs(data.entries) do
    check(type(entry) == "table" and id(entry.id), "Invalid entry ID")
    check(entry.parentId == vim.NIL or id(entry.parentId), "Invalid parent ID")
    check(not entries[entry.id], "Duplicate entry ID")
    entries[entry.id] = entry
  end
  -- Validate abandoned paths too; each entry is visited at most twice.
  for _, entry in ipairs(data.entries) do
    local current, path, visiting = entry.id, {}, {}
    for _ = 1, #data.entries + 1 do
      if current == vim.NIL or done[current] then break end
      check(entries[current], "Missing parent entry")
      check(not visiting[current], "Cycle in session entries")
      visiting[current] = true
      path[#path + 1] = current
      current = entries[current].parentId
    end
    for _, visited in ipairs(path) do done[visited] = true end
  end
  local path, current = {}, data.leafId
  for _ = 1, #data.entries + 1 do
    if current == vim.NIL then break end
    check(entries[current], "Missing leaf entry")
    path[#path + 1] = entries[current]
    current = entries[current].parentId
  end
  local active = {}
  for index = #path, 1, -1 do active[#active + 1] = path[index] end
  return active
end

local function short(value, limit)
  if type(value) ~= "string" then return "" end
  limit = limit or 240
  local line = vim.fn.strcharpart(value, 0, limit + 1):match("[^\r\n]*"):gsub("[%c]", " ")
  line = vim.fn.strcharpart(line, 0, limit)
  return line .. (#line < #value and "…" or "")
end

local function append(document, text)
  check(type(text) == "string", "Invalid message text")
  document.bytes = document.bytes + #text
  check(document.bytes <= 16 * 1024 * 1024, "Transcript exceeds 16 MiB")
  local start = 1
  for _ = 1, #text + 1 do
    local stop = text:find("\n", start, true)
    check(#document.lines < 100000, "Transcript has too many lines")
    document.lines[#document.lines + 1] = text:sub(start, stop and stop - 1)
    if not stop then break end
    start = stop + 1
  end
end

local function message(entry)
  if entry.type == "message" and type(entry.message) == "table" then
    return entry.message
  end
end

local function index_tools(active)
  local results, calls = {}, {}
  for _, entry in ipairs(active) do
    local value = message(entry)
    if value and value.role == "toolResult" and id(value.toolCallId) then
      check(not results[value.toolCallId], "Duplicate tool result ID")
      results[value.toolCallId] = value
    elseif value and value.role == "assistant" and array(value.content) then
      for _, block in ipairs(value.content) do
        if type(block) == "table" and block.type == "toolCall" and id(block.id) then
          check(not calls[block.id], "Duplicate tool call ID")
          calls[block.id] = true
        end
      end
    end
  end
  return results, calls
end

local intent_keys = { "path", "file_path", "command", "subject", "title", "name",
  "taskId", "id", "query", "url", "pattern", "description" }
local payload_keys = { content = true, oldText = true, newText = true, edits = true,
  input = true, messages = true }

local function intent(arguments, cwd)
  for _, key in ipairs(intent_keys) do
    local value = arguments[key]
    if type(value) == "number" then return tostring(value) end
    if type(value) == "string" and value ~= "" then
      if key == "path" or key == "file_path" then
        local prefix = cwd:sub(-1) == "/" and cwd or (cwd .. "/")
        if cwd ~= "" and value:sub(1, #prefix) == prefix then value = value:sub(#prefix + 1) end
        -- Keep directory components: equal basenames must not conceal different files.
        return short(value)
      end
      return short(value, 80)
    end
  end
  local keys = vim.tbl_keys(arguments)
  table.sort(keys, function(left, right) return tostring(left) < tostring(right) end)
  for _, key in ipairs(keys) do
    local value = arguments[key]
    if not payload_keys[key] then
      if type(value) == "string" or type(value) == "number" or type(value) == "boolean" then
        if tostring(value) ~= "" then
          return short(tostring(key) .. "=" .. tostring(value), 80)
        end
      end
    end
  end
  return ""
end

local function artifact(result, call)
  if not result or result.isError ~= false or not id(call.id) then return end
  local arguments = type(call.arguments) == "table" and call.arguments or {}
  local details = type(result.details) == "table" and result.details or {}
  local text, kind = details.patch, "patch"
  if type(text) ~= "string" or text == "" then text, kind = details.diff, "display_diff" end
  if type(text) ~= "string" or text == "" then
    if call.name ~= "write" or type(arguments.content) ~= "string" then return end
    text, kind = arguments.content, "write_content"
  end
  check(#text <= 4 * 1024 * 1024, "Recorded change content exceeds 4 MiB")
  local _, breaks = text:gsub("\n", "")
  check(breaks < 100000, "Recorded change content has too many lines")
  if text:find("\0", 1, true) then return end
  local path = arguments.path or arguments.file_path
  return { tool_call_id = call.id, path = type(path) == "string" and path or nil,
    text = text, kind = kind }
end

local function tool(document, call, result, prefix)
  local arguments = type(call.arguments) == "table" and call.arguments or {}
  local target = artifact(result, call)
  if not target and id(call.id) then
    target = { kind = "tool", tool_call_id = call.id, call = call, result = result }
  end
  local name = short(call.name)
  if name == "" then name = "tool" end
  local label = intent(arguments, document.cwd)
  local status = preview.status(result)
  local suffix = status ~= "done" and (" [" .. status .. "]") or ""
  if prefix then suffix = suffix .. " [orphan]" end
  local padding = string.rep(" ", math.max(2, 12 - vim.fn.strdisplaywidth(name)))
  append(document, name .. (label ~= "" and (padding .. label) or "") .. suffix)
  document.tool_rows[#document.lines] = { status = status }
  if target then document.targets[#document.lines] = target end
end

local function content(document, value, results)
  if type(value) == "string" then append(document, value); return end
  if not array(value) or #value == 0 then append(document, "[empty message]"); return end
  local visible = false
  for _, block in ipairs(value) do
    if type(block) == "table" then
      if block.type == "text" and type(block.text) == "string" then
        append(document, block.text)
        visible = true
      elseif block.type == "image" then
        append(document, "[image]")
        visible = true
      elseif block.type == "toolCall" then
        tool(document, block, id(block.id) and results[block.id] or nil)
        visible = true
      end
    end
  end
  if not visible then append(document, "[no visible content]") end
end

local function render_entry(document, entry, results, calls)
  if entry.type == "compaction" then
    append(document, "\n[compaction — earlier history preserved]\n")
    return
  end
  if entry.type == "branch_summary" then
    append(document, "\n[branch summary]\n")
    return
  end
  if entry.type == "custom_message" then
    if entry.display == true then
      append(document, "\n## " .. (short(entry.customType) ~= "" and short(entry.customType)
        or "Custom"))
      content(document, entry.content, results)
      document.speaker = nil
    end
    return
  end
  local value = message(entry)
  if not value then return end
  if value.role == "toolResult" then
    if not calls[value.toolCallId] then
      tool(document, { id = value.toolCallId, name = value.toolName }, value, "Orphan tool result")
    end
    return
  end
  if value.role == "bashExecution" then
    local status = value.cancelled and "cancelled" or "unfinished"
    if type(value.exitCode) == "number" then status = "exit " .. value.exitCode end
    append(document, "bash        " .. short(value.command, 80)
      .. (value.exitCode == 0 and "" or (" [" .. status .. "]")))
    return
  end
  if value.role == "custom" and value.display ~= true then return end
  local heading = ({ user = "User", assistant = "Pi", custom = "Custom" })[value.role]
  if not heading then return end
  if document.speaker ~= value.role then
    append(document, "\n## " .. heading)
    document.speaker = value.role
  end
  content(document, value.content, results)
  if value.role == "assistant" and (value.stopReason == "error"
    or value.stopReason == "aborted" or type(value.errorMessage) == "string") then
    append(document, "[assistant " .. short(value.stopReason or "error") .. "] "
      .. short(value.errorMessage))
  end
end

render = function(session, data)
  check(type(session) == "table" and type(session.path) == "string"
    and #session.path > 0 and #session.path <= 16384, "Invalid session path")
  check(type(session.cwd) == "string" and #session.cwd <= 16384, "Invalid project path")
  local active = branch(data)
  local results, calls = index_tools(active)
  local document = { lines = {}, targets = {}, tool_rows = {}, bytes = 0, cwd = session.cwd }
  append(document, "# Pi snapshot — " .. short(session.title or session.id or session.path))
  append(document, "Session: " .. short(session.path))
  append(document, "Project: " .. short(session.cwd))
  if #active == 0 then append(document, "\n[empty active branch]") end
  for _, entry in ipairs(active) do render_entry(document, entry, results, calls) end
  document.bytes = nil
  document.speaker = nil
  document.cwd = nil
  return document
end

local function buffer_for(name)
  local buffer = vim.fn.bufnr(name)
  if buffer == -1 then
    buffer = vim.api.nvim_create_buf(true, true)
    vim.api.nvim_buf_set_name(buffer, name)
  end
  return buffer
end

local function fill(buffer, lines, filetype)
  vim.bo[buffer].buftype = "nofile"
  vim.bo[buffer].buflisted = true
  vim.bo[buffer].bufhidden = "hide"
  vim.bo[buffer].swapfile = false
  vim.bo[buffer].readonly = false
  vim.bo[buffer].modifiable = true
  vim.api.nvim_buf_set_lines(buffer, 0, -1, false, lines)
  vim.bo[buffer].filetype = filetype
  vim.bo[buffer].modified = false
  vim.bo[buffer].readonly = true
  vim.bo[buffer].modifiable = false
end

open = function(session, document, window)
  local identity = vim.fn.sha256(session.path)
  local buffer = buffer_for("pi-session://" .. identity)
  fill(buffer, document.lines, "markdown")
  local targets = document.targets
  vim.keymap.set("n", "gd", function()
    jump(identity, targets[vim.api.nvim_win_get_cursor(0)[1]])
  end, { buffer = buffer, silent = true, desc = "Preview recorded tool use" })
  if vim.api.nvim_get_current_win() == window then
    -- Enter the read-only view in Normal mode without interrupting another window.
    vim.cmd('stopinsert')
  end
  vim.api.nvim_win_set_buf(window, buffer)
  folds.apply(buffer, document)
  return buffer
end

jump = function(identity, target)
  if not target then
    vim.notify("No recorded preview on this row", vim.log.levels.INFO)
    return
  end
  local lines, filetype
  local prefix = "pi-session-diff://"
  if target.kind == "write_content" or target.kind == "tool" then
    local err
    lines, err = preview.render(target)
    if not lines then vim.notify(err, vim.log.levels.ERROR); return end
    filetype = "markdown"
    prefix = target.kind == "tool" and "pi-session-tool://" or "pi-session-write://"
  else
    lines = vim.split(target.text, "\n", { plain = true, trimempty = false })
    filetype = target.kind == "patch" and "diff" or "pisession"
    if target.kind == "display_diff" then
      table.insert(lines, 1, "# Recorded display diff (not a unified patch)")
    end
  end
  local buffer = buffer_for(prefix .. identity .. "/" .. vim.fn.sha256(target.tool_call_id))
  fill(buffer, lines, filetype)
  -- Set the native previous-context mark before changing the existing window's buffer.
  vim.cmd("normal! m'")
  vim.api.nvim_win_set_buf(0, buffer)
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
end

return M
