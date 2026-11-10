local M = {}
local render

function M.render(target)
  local ok, lines = pcall(render, target)
  if not ok then return nil, tostring(lines) end
  return lines
end

function M.status(result)
  if not result then return "unfinished" end
  if result.isError == false then return "done" end
  if result.isError == true then return "failed" end
  return "unknown status"
end

local function short(value)
  if type(value) ~= "string" then return "" end
  return value:sub(1, 240):match("[^\r\n]*"):gsub("[%c]", " ")
end

local function append(document, text)
  document.bytes = document.bytes + #text + 1
  if document.bytes > 16 * 1024 * 1024 then error("Tool preview exceeds 16 MiB", 0) end
  local _, breaks = text:gsub("\n", "")
  if #document.lines + breaks + 1 > 100000 then
    error("Tool preview has too many lines", 0)
  end
  vim.list_extend(document.lines, vim.split(text, "\n", { plain = true, trimempty = false }))
end

local function structured(value)
  -- Keep arbitrarily nested extension data inspectable without unbounded display depth.
  return vim.inspect(value, { depth = 16, indent = "  ", newline = "\n" })
end

local function code(document, text, language)
  if #text > 4 * 1024 * 1024 then error("Recorded preview content exceeds 4 MiB", 0) end
  -- Neovim text buffers cannot preserve NUL bytes; show their escaped representation instead.
  if text:find("\0", 1, true) then text, language = structured(text), "lua" end
  local length = 3
  for run in text:gmatch("~+") do length = math.max(length, #run + 1) end
  local fence = string.rep("~", length)
  language = type(language) == "string" and language:gsub("[^%w_+%-]", ""):sub(1, 64) or ""
  append(document, fence .. language)
  append(document, text)
  append(document, fence)
end

local function file_language(path)
  if type(path) ~= "string" then return "" end
  return vim.filetype.match({ filename = short(path) }) or ""
end

local function write_content(document, target)
  append(document, "# Recorded write content" .. (target.text == "" and " (empty)" or ""))
  append(document, "File: " .. (target.path and short(target.path) or "[unknown path]"))
  append(document, "")
  code(document, target.text, file_language(target.path))
end

local function section(document, title, text, language)
  append(document, "\n## " .. title)
  code(document, text, language)
end

local function arguments(document, value)
  if value == nil or value == vim.NIL then return end
  if type(value) ~= "table" or vim.islist(value) then
    if type(value) == "table" and next(value) == nil then return end
    section(document, "Arguments", structured(value), "lua")
    return
  end
  local keys = vim.tbl_keys(value)
  table.sort(keys, function(left, right) return tostring(left) < tostring(right) end)
  local blocks = {}
  -- Keep scalar inputs together, outside the sections for larger argument bodies.
  for _, key in ipairs(keys) do
    local argument = value[key]
    local block = type(argument) == "table"
    if type(argument) == "string" then
      block = key == "command" or key == "content" or #argument > 160
        or argument:find("\n", 1, true)
    end
    if block then
      blocks[#blocks + 1] = key
    else
      append(document, short(tostring(key)) .. ": " .. structured(argument))
    end
  end
  for _, key in ipairs(blocks) do
    local name, argument = short(tostring(key)), value[key]
    if type(argument) == "string" then
      local language = key == "command" and "bash" or "text"
      if key == "content" then language = file_language(value.path or value.file_path) end
      section(document, name, argument, language)
    else
      section(document, name, structured(argument), "lua")
    end
  end
end

local function output(document, value, language)
  if value == nil or value == vim.NIL then return end
  append(document, "\n## Output")
  if type(value) == "string" then code(document, value, language); return end
  if type(value) ~= "table" or not vim.islist(value) then
    code(document, structured(value), "lua")
    return
  end
  if #value == 0 then append(document, "(empty)"); return end
  for _, block in ipairs(value) do
    if type(block) == "table" and block.type == "text" and type(block.text) == "string" then
      code(document, block.text, language)
    elseif type(block) == "table" and block.type == "image" then
      append(document, "[image" .. (type(block.mimeType) == "string"
        and (": " .. short(block.mimeType)) or "") .. "]")
    else
      code(document, structured(block), "lua")
    end
  end
end

local function tool_content(document, target)
  local name = short(target.call.name)
  append(document, "# " .. (name ~= "" and name or "Tool") .. " — " .. M.status(target.result))
  arguments(document, target.call.arguments)
  if not target.result then return end
  local language = "text"
  if target.call.name == "read" and target.result.isError == false then
    local value = type(target.call.arguments) == "table" and target.call.arguments or {}
    language = file_language(value.path or value.file_path)
  end
  output(document, target.result.content, language)
  local details = target.result.details
  if details ~= nil and details ~= vim.NIL then
    if type(details) ~= "table" or next(details) ~= nil then
      section(document, "Details", structured(details), "lua")
    end
  end
end

render = function(target)
  local document = { lines = {}, bytes = 0 }
  if target.kind == "write_content" then
    write_content(document, target)
  else
    tool_content(document, target)
  end
  return document.lines
end

return M
