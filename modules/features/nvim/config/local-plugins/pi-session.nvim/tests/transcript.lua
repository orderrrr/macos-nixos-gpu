local transcript = require("pi_session.transcript")
local preview = require("pi_session.preview")
local session = {
  path = "/synthetic/project/session.jsonl", cwd = "/synthetic/project", title = "Test",
}

local function entry(id, parent, value)
  return { id = id, parentId = parent or vim.NIL, type = "message", message = value }
end

local function text(role, value)
  return { role = role, content = value }
end

local function call(id, path, name)
  return { type = "toolCall", id = id, name = name or "edit",
    arguments = { path = path, oldText = "PROPOSED OLD", newText = "PROPOSED NEW" } }
end

local function result(id, details, failed)
  return { role = "toolResult", toolCallId = id, toolName = "edit", isError = failed or false,
    content = { { type = "text", text = "Complete\nhuge output omitted" } }, details = details }
end

local patch = "--- a/file\n+++ b/file\n@@ -1 +1 @@\n-actual old\n+actual new\n"

local function snapshot(blocks, results)
  local entries = { entry("a", nil, text("assistant", blocks)) }
  local parent = "a"
  for index, value in ipairs(results or {}) do
    local next_id = "r" .. index
    entries[#entries + 1] = entry(next_id, parent, value)
    parent = next_id
  end
  return { entries = entries, leafId = parent }
end

local function render(data)
  local document, err = transcript.render(session, data)
  assert(document, err)
  return document, table.concat(document.lines, "\n")
end

local function contains(value, expected)
  assert(value:find(expected, 1, true), "Missing: " .. expected .. "\nIn: " .. value)
end

local function excludes(value, unexpected)
  assert(not value:find(unexpected, 1, true), "Unexpected: " .. unexpected)
end

local function targets(document)
  local rows = vim.tbl_keys(document.targets)
  table.sort(rows)
  return rows
end

local function feed(keys)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "xt", false)
end

local function invalid(data)
  local document, err = transcript.render(session, data)
  assert(document == nil and type(err) == "string" and #err > 0)
end

return function(test)
  test("active parent chain preserves compacted history and assistant block order", function()
    -- Shuffle append order and include retained-tail/abandoned decoys to prove ancestry wins.
    local compact = { id = "compact", parentId = "a", type = "compaction",
      retainedTail = { text("user", "NOT retained tail") } }
    local data = { leafId = "r", entries = {
      entry("r", "b", result("edit", { patch = patch })),
      entry("dead", "a", text("user", "NOT abandoned")), compact,
      entry("b", "compact", text("assistant", {
        { type = "text", text = "before" }, call("edit", "file"),
        { type = "text", text = "after" },
      })), entry("a", nil, text("user", "old user")),
    } }
    local _, output = render(data)
    contains(output, "old user")
    contains(output, "compaction")
    excludes(output, "NOT")
    assert(output:find("before") < output:find("edit"))
    assert(output:find("edit") < output:find("after"))
    assert(vim.tbl_count(render(data).tool_rows) == 1)
  end)

  test("consecutive Pi tool messages share one heading and adjacent tool rows", function()
    -- Tool results and metadata are not speaker changes between separate Pi messages.
    local document, output = render({ leafId = "r2", entries = {
      entry("a", nil, text("assistant", { call("create", nil, "TaskCreate") })),
      entry("r1", "a", result("create")),
      { id = "model", parentId = "r1", type = "model_change", modelId = "test" },
      entry("b", "model", text("assistant", { call("get", nil, "TaskGet") })),
      entry("r2", "b", result("get")),
    } })
    local _, count = output:gsub("## Pi\n", "")
    assert(count == 1, "Repeated Pi heading without a speaker change")
    local first
    for row, line in ipairs(document.lines) do
      if line:match("^TaskCreate") then first = row end
    end
    assert(first and document.lines[first + 1]:match("^TaskGet"))
  end)

  test("tool summaries show intent without success output or navigation hints", function()
    -- Select inputs generically and retain path context instead of merging equal basenames.
    local read = call("read-intent", session.cwd .. "/src/config.lua", "read")
    local other = call("other-intent", session.cwd .. "/tests/config.lua", "read")
    local shell = call("shell-intent", nil, "bash")
    shell.arguments = { command = "printf café\nprintf more" }
    local task = call("task-intent", nil, "TaskCreate")
    task.arguments = { subject = "Simplify summaries" }
    local custom = call("custom-intent", nil, "custom")
    custom.arguments = { ticket = "ABC-17" }
    local calls = { read, other, shell, task, custom }
    local results = {}
    for _, invocation in ipairs(calls) do results[#results + 1] = result(invocation.id) end
    local document, output = render(snapshot(calls, results))
    contains(output, "read        src/config.lua")
    contains(output, "read        tests/config.lua")
    contains(output, "bash        printf café…")
    contains(output, "TaskCreate  Simplify summaries")
    contains(output, "custom      ticket=ABC-17")
    excludes(output, "Tool:")
    excludes(output, "[gd:")
    excludes(output, "done")
    excludes(output, "Complete")
    assert(vim.tbl_count(document.tool_rows) == 5 and #targets(document) == 5)
    local target = document.targets[targets(document)[3]]
    contains(table.concat(assert(preview.render(target)), "\n"), shell.arguments.command)
    shell.arguments.command = string.rep("é", 81)
    document, output = render(snapshot({ shell }, { result(shell.id) }))
    contains(output, string.rep("é", 80) .. "…")
  end)

  test("only real consecutive tool rows fold and native zo exposes exact gd targets", function()
    -- Prose resembling a tool must not fold; expanded calls retain their recorded identities.
    local data = snapshot({ { type = "text", text = "read        prose.lua" },
      call("fold-first", "one.lua"), call("fold-second", "two.lua"),
      { type = "text", text = "Pi commentary" }, call("single", "three.lua") }, {
      result("fold-first", { patch = patch }), result("fold-second", nil, true), result("single"),
    })
    local document = render(data)
    local rows = targets(document)
    local buffer = assert(transcript.open(session, data))
    assert(vim.fn.foldclosed(rows[1]) == rows[1])
    assert(vim.fn.foldclosedend(rows[1]) == rows[2])
    contains(vim.fn.foldtextresult(rows[1]), "2 tool calls")
    contains(vim.fn.foldtextresult(rows[1]), "1 failed")
    assert(vim.fn.foldclosed(rows[1] - 1) == -1 and vim.fn.foldclosed(rows[3]) == -1)
    vim.api.nvim_win_set_cursor(0, { rows[1], 0 })
    feed("zo")
    assert(vim.fn.foldclosed(rows[2]) == -1)
    vim.api.nvim_win_set_cursor(0, { rows[2], 0 })
    feed("gd")
    contains(vim.api.nvim_buf_get_name(0), vim.fn.sha256("fold-second"))
    assert(vim.bo.filetype == "markdown" and not vim.bo.modifiable)
    feed("<C-o>")
    assert(vim.api.nvim_get_current_buf() == buffer)
    assert(vim.api.nvim_win_get_cursor(0)[1] == rows[2])
    assert(vim.fn.foldclosed(rows[2]) == -1)
  end)

  test("User and Pi headings are emitted only when the speaker changes", function()
    -- Repeated text, hidden notices, and compaction markers preserve the current speaker.
    local document, output = render({ leafId = "p4", entries = {
      entry("u1", nil, text("user", "First paragraph\n\nSecond paragraph")),
      entry("u2", "u1", text("user", "Another user message")),
      entry("p1", "u2", text("assistant", "Pi text one")),
      { id = "hidden", parentId = "p1", type = "custom_message", display = false,
        content = "Hidden" },
      entry("p2", "hidden", text("assistant", "Pi text two")),
      { id = "compact", parentId = "p2", type = "compaction", summary = "Summary" },
      entry("p3", "compact", text("assistant", "Pi text three")),
      entry("u3", "p3", text("user", "User returns")),
      entry("p4", "u3", text("assistant", "Pi returns")),
    } })
    local headings = {}
    for _, line in ipairs(document.lines) do
      if line:match("^## ") then headings[#headings + 1] = line end
    end
    assert(vim.deep_equal(headings, { "## User", "## Pi", "## User", "## Pi" }))
    contains(output, "First paragraph\n\nSecond paragraph")
    contains(output, "Pi text one\nPi text two")
    assert(document.speaker == nil, "Render state leaked into the document")
  end)

  test("entry graph rejects malformed IDs, duplicates, missing parents and cycles", function()
    -- Mutate each graph invariant independently, including an abandoned cycle.
    invalid({ entries = {}, leafId = nil })
    invalid({ entries = {}, leafId = "missing" })
    invalid({ entries = {}, leafId = 3 })
    invalid({ entries = {}, leafId = "" })
    invalid({ entries = { nope = true }, leafId = vim.NIL })
    invalid({ entries = { entry("", nil, {}) }, leafId = vim.NIL })
    invalid({ entries = { entry(vim.NIL, nil, {}) }, leafId = vim.NIL })
    invalid({ entries = { { id = "a" } }, leafId = "a" })
    invalid({ entries = { entry("a", 3, {}) }, leafId = "a" })
    invalid({ entries = { entry("a", nil, {}), entry("a", nil, {}) }, leafId = "a" })
    invalid({ entries = { entry("a", "missing", {}) }, leafId = "a" })
    invalid({ entries = { entry("a", "b", {}), entry("b", "a", {}) }, leafId = vim.NIL })
    invalid({ entries = { entry("a", "a", {}) }, leafId = "a" })
  end)

  test("null leaf yields an empty active branch and does not guess the latest entry", function()
    -- Both zero entries and existing inactive history must produce an empty snapshot.
    for _, entries in ipairs({ {}, { entry("a", nil, text("user", "invisible")) } }) do
      local document, output = render({ entries = entries, leafId = vim.NIL })
      contains(output, "empty active branch")
      excludes(output, "invisible")
      assert(next(document.targets) == nil)
    end
  end)

  test("empty, multimodal, custom and failed assistant messages stay readable", function()
    -- Visible text survives beside images; thinking and hidden custom payloads do not.
    local data = { entries = {
      entry("a", nil, text("user", { { type = "text", text = "hello" },
        { type = "image", data = "SECRET IMAGE" } })),
      entry("b", "a", text("assistant", {})),
      entry("c", "b", { role = "assistant", stopReason = "error", errorMessage = "provider failed",
        content = { { type = "thinking", thinking = "SECRET THOUGHT" } } }),
      { id = "d", parentId = "c", type = "custom_message", customType = "Notice",
        display = true, content = "visible custom" },
      { id = "e", parentId = "d", type = "custom_message", display = false,
        content = "SECRET CUSTOM" },
    }, leafId = "e" }
    local _, output = render(data)
    for _, expected in ipairs({ "hello", "[image]", "empty message", "provider failed",
      "## Notice", "visible custom", "## User", "## Pi" }) do contains(output, expected) end
    excludes(output, "SECRET")
    local _, empty = render(snapshot("", {}))
    contains(empty, "## Pi")
  end)

  test("successive edits match out-of-order results by ID and trust recorded patches", function()
    -- Contradictory proposals, same paths, and reverse result order cannot alter artifacts.
    local second = "--- a/file\n+++ b/file\n@@ -1 +1 @@\n-actual new\n+later\n"
    local document, output = render(snapshot({ call("one", "file"), call("two", "file") }, {
      result("two", { patch = second }), result("one", { patch = patch, diff = "FALLBACK" }),
    }))
    local rows = targets(document)
    assert(#rows == 2)
    assert(document.targets[rows[1]].tool_call_id == "one")
    assert(document.targets[rows[1]].text == patch)
    assert(document.targets[rows[2]].text == second)
    assert(document.targets[rows[1]].path == "file")
    excludes(output, "PROPOSED")
    excludes(output, "huge output omitted")
  end)

  test("successful writes expose recorded content and prefer actual patches", function()
    -- Same-path writes retain their own content, and an empty write remains inspectable.
    local first, second, empty = call("w1", "file.lua", "write"),
      call("w2", "file.lua", "write"), call("empty", "file.lua", "write")
    first.arguments.content = "first"
    second.arguments.content = "later"
    empty.arguments.content = ""
    local document, output = render(snapshot({ first, second, empty }, {
      result("w2"), result("empty"), result("w1"),
    }))
    local rows = targets(document)
    assert(#rows == 3)
    assert(document.targets[rows[1]].text == "first")
    assert(document.targets[rows[2]].text == "later")
    assert(document.targets[rows[3]].text == "")
    assert(document.targets[rows[1]].kind == "write_content")
    excludes(output, "[gd:")
    local actual = render(snapshot({ first }, { result("w1", { patch = patch }) }))
    assert(actual.targets[targets(actual)[1]].kind == "patch")
    assert(actual.targets[targets(actual)[1]].text == patch)
  end)

  test("write fallback requires successful text content and remains bounded", function()
    -- These calls remain inspectable, but not as successful write contents or applied diffs.
    local failed, pending = call("failed", "f", "write"), call("pending", "f", "write")
    local other, binary = call("other", "f", "custom"), call("binary", "f", "write")
    for _, value in ipairs({ failed, pending, other }) do value.arguments.content = "request" end
    binary.arguments.content = "a\0b"
    local document = render(snapshot({ failed, pending, other, binary }, {
      result("failed", nil, true), result("other"), result("binary"),
    }))
    assert(#targets(document) == 4)
    for _, target in pairs(document.targets) do assert(target.kind == "tool") end
    local large = call("large", "f", "write")
    large.arguments.content = string.rep("x", 4 * 1024 * 1024 + 1)
    invalid(snapshot({ large }, { result("large") }))
  end)

  test("gd shows a labelled write request rather than current file contents", function()
    -- Native navigation shows the saved request in a safe Markdown fence, never a fabricated diff.
    local path = vim.fn.tempname() .. ".lua"
    vim.fn.writefile({ "CURRENT FILE CONTENT" }, path)
    local ok, err = xpcall(function()
      local written = "local value = [[\n~~~\n## Literal Markdown\n]]\n"
      local write = call("view-write", path, "write")
      write.arguments.content = written
      local data = snapshot({ write }, { result("view-write") })
      local document = render(data)
      local row = targets(document)[1]
      local buffer = assert(transcript.open(session, data))
      local window, windows = vim.api.nvim_get_current_win(), #vim.api.nvim_list_wins()
      vim.api.nvim_win_set_cursor(0, { row, 0 })
      feed("gd")
      local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
      assert(vim.bo.filetype == "markdown" and not vim.bo.modifiable)
      assert(vim.bo.readonly and vim.api.nvim_get_current_win() == window)
      assert(#vim.api.nvim_list_wins() == windows)
      contains(lines[1], "Recorded write content")
      assert(lines[2] == "File: " .. path and lines[3] == "")
      assert(lines[4] == "~~~~lua" and lines[#lines] == "~~~~")
      assert(table.concat(vim.list_slice(lines, 5, #lines - 1), "\n") == written)
      excludes(table.concat(lines, "\n"), "Captured from the successful write request")
      excludes(table.concat(lines, "\n"), "Previous content was not recorded")
      excludes(table.concat(lines, "\n"), "CURRENT FILE CONTENT")
      assert(vim.fn.readfile(path)[1] == "CURRENT FILE CONTENT")
      feed("<C-o>")
      assert(vim.api.nvim_get_current_buf() == buffer)
      assert(vim.api.nvim_win_get_cursor(0)[1] == row)
      write.arguments.content = ""
      assert(transcript.open(session, snapshot({ write }, { result("view-write") })) == buffer)
      vim.api.nvim_win_set_cursor(0, { row, 0 })
      feed("gd")
      contains(vim.api.nvim_buf_get_lines(0, 0, 1, false)[1], "(empty)")
    end, debug.traceback)
    vim.fn.delete(path)
    assert(ok, err)
  end)

  test("generic previews cover Bash, Read and arbitrary tool arguments and results", function()
    -- Reverse result order and use an unknown name to prove ID joins, not a tool whitelist.
    local bash, read, custom = call("bash", nil, "bash"), call("read", "missing.lua", "read"),
      call("custom", nil, "unregistered_extension_tool")
    bash.arguments = { command = "printf one\nprintf two", timeout = 20 }
    read.arguments = { path = "missing.lua", offset = 8, limit = 2 }
    custom.arguments = { subject = "inspect me", options = { enabled = true } }
    local bash_result, read_result, custom_result = result("bash"), result("read"),
      result("custom", { count = 7 })
    bash_result.content = { { type = "text", text = "FIRST OUTPUT" },
      { type = "text", text = "SECOND OUTPUT" } }
    read_result.content = "local saved = true\n[More lines in file]"
    custom_result.content = {}
    local document, output = render(snapshot({ bash, read, custom }, {
      custom_result, read_result, bash_result,
    }))
    local rows = targets(document)
    assert(#rows == 3)
    excludes(output, "[gd:")
    local views = {}
    for index, row in ipairs(rows) do
      assert(document.targets[row].kind == "tool")
      views[index] = table.concat(assert(preview.render(document.targets[row])), "\n")
    end
    contains(views[1], "printf one\nprintf two")
    assert(views[1]:find("FIRST OUTPUT", 1, true) < views[1]:find("SECOND OUTPUT", 1, true))
    contains(views[2], "local saved = true\n[More lines in file]")
    contains(views[2], "offset: 8")
    contains(views[2], "~~~lua")
    contains(views[3], "unregistered_extension_tool")
    contains(views[3], "inspect me")
    contains(views[3], "enabled = true")
    contains(views[3], "count = 7")
  end)

  test("generic previews retain failure and pending states without fabricating diffs", function()
    -- A failed patch remains result data; pending writes remain arguments, not written files.
    local failed, pending = call("failed-preview", "file"), call("pending-preview", "file", "write")
    pending.arguments.content = "NOT YET WRITTEN"
    local document = render(snapshot({ failed, pending }, {
      result("failed-preview", { patch = patch }, true),
    }))
    local rows = targets(document)
    for _, row in ipairs(rows) do assert(document.targets[row].kind == "tool") end
    local failure = table.concat(assert(preview.render(document.targets[rows[1]])), "\n")
    local unfinished = table.concat(assert(preview.render(document.targets[rows[2]])), "\n")
    contains(failure, "# edit — failed")
    contains(failure, "## Details")
    contains(unfinished, "# write — unfinished")
    contains(unfinished, "NOT YET WRITTEN")
    excludes(unfinished, "## Output")
    excludes(unfinished, "Recorded write content")
  end)

  test("generic output preserves mixed blocks and unknown result shapes", function()
    -- Keep text order and opaque metadata, but never dump image bytes or allow escaping fences.
    local response = result("mixed", { nested = { count = 3 } })
    response.content = { { type = "text", text = "FIRST\n~~~\n## Literal heading" },
      { type = "image", mimeType = "image/png", data = "SECRET IMAGE BYTES" },
      { type = "unknown", value = 42 }, { type = "text", text = "LAST" } }
    local document = render(snapshot({ call("mixed", nil, "anything") }, { response }))
    local view = table.concat(assert(preview.render(document.targets[targets(document)[1]])), "\n")
    contains(view, "~~~~text\nFIRST\n~~~\n## Literal heading\n~~~~")
    contains(view, "[image: image/png]")
    contains(view, "value = 42")
    contains(view, "count = 3")
    assert(view:find("FIRST", 1, true) < view:find("LAST", 1, true))
    excludes(view, "SECRET IMAGE BYTES")
    local command = call("scalar", nil, "odd_tool")
    command.arguments = { true, 2 }
    response = result("scalar", false)
    response.content = { custom_output = "opaque" }
    document = render(snapshot({ command }, { response }))
    view = table.concat(assert(preview.render(document.targets[targets(document)[1]])), "\n")
    contains(view, "## Arguments")
    contains(view, "opaque")
    contains(view, "## Details\n~~~lua\nfalse")
  end)

  test("generic previews use per-call identities and native navigation", function()
    -- Repeated reads of one path must retain distinct recorded outputs in the same window.
    local first, second = result("read-first"), result("read-second")
    first.content, second.content = "EARLIER CONTENT", "LATER CONTENT"
    local data = snapshot({ call("read-first", "same.lua", "read"),
      call("read-second", "same.lua", "read") }, { second, first })
    local rows = targets(render(data))
    local buffer = assert(transcript.open(session, data))
    local window, windows = vim.api.nvim_get_current_win(), #vim.api.nvim_list_wins()
    local buffers = {}
    for index, row in ipairs(rows) do
      vim.api.nvim_win_set_cursor(0, { row, 0 })
      feed("zv")
      feed("gd")
      buffers[index] = vim.api.nvim_get_current_buf()
      assert(vim.bo.filetype == "markdown" and vim.bo.readonly and not vim.bo.modifiable)
      assert(vim.api.nvim_get_current_win() == window and #vim.api.nvim_list_wins() == windows)
      local output = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
      contains(output, index == 1 and "EARLIER CONTENT" or "LATER CONTENT")
      excludes(output, index == 1 and "LATER CONTENT" or "EARLIER CONTENT")
      feed("<C-o>")
      assert(vim.api.nvim_get_current_buf() == buffer)
      assert(vim.api.nvim_win_get_cursor(0)[1] == row)
    end
    assert(buffers[1] ~= buffers[2])
    vim.api.nvim_win_set_cursor(0, { rows[1], 0 })
    feed("gd")
    assert(vim.api.nvim_get_current_buf() == buffers[1])
  end)

  test("generic previews refresh and survive native delete and unload", function()
    -- Replace an unfinished preview with its result, then reload the same logical preview.
    for _, command in ipairs({ "bdelete", "bunload" }) do
      local source = { path = "/preview/" .. command .. ".jsonl", cwd = "/preview" }
      local invocation = call("refresh-preview", nil, "custom")
      local data = snapshot({ invocation })
      local row = targets(render(data))[1]
      local buffer = assert(transcript.open(source, data))
      vim.api.nvim_win_set_cursor(0, { row, 0 })
      feed("gd")
      local view = vim.api.nvim_get_current_buf()
      contains(vim.api.nvim_buf_get_lines(0, 0, 1, false)[1], "unfinished")
      data = snapshot({ invocation }, { result("refresh-preview") })
      assert(transcript.open(source, data) == buffer)
      vim.api.nvim_win_set_cursor(0, { row, 0 })
      feed("gd")
      assert(vim.api.nvim_get_current_buf() == view)
      contains(vim.api.nvim_buf_get_lines(0, 0, 1, false)[1], "done")
      vim.cmd(command .. " " .. view)
      assert(not vim.api.nvim_buf_is_loaded(view))
      vim.cmd("buffer " .. buffer)
      vim.api.nvim_win_set_cursor(0, { row, 0 })
      feed("gd")
      assert(vim.bo.filetype == "markdown" and not vim.bo.modifiable)
      contains(table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n"), "Complete")
    end
  end)

  test("generic preview limits fail without replacing the transcript", function()
    -- Oversized output is checked lazily, before allocating a preview or changing the window.
    local invocation = call("oversized-preview", nil, "anything")
    invocation.arguments = { command = string.rep("x", 4 * 1024 * 1024 + 1) }
    local data = snapshot({ invocation })
    local row = targets(render(data))[1]
    local buffer = assert(transcript.open(session, data))
    local count = #vim.api.nvim_list_bufs()
    vim.api.nvim_win_set_cursor(0, { row, 0 })
    local notify, notification = vim.notify, nil
    vim.notify = function(value) notification = value end
    feed("gd")
    vim.notify = notify
    contains(notification or "", "exceeds 4 MiB")
    assert(vim.api.nvim_get_current_buf() == buffer and #vim.api.nvim_list_bufs() == count)
    local value = {}
    invocation.arguments = { nested = value }
    for _ = 1, 30 do value.child = {}; value = value.child end
    local document = render(snapshot({ invocation }))
    local output = table.concat(
      assert(preview.render(document.targets[targets(document)[1]])), "\n")
    assert(#output < 5000)
    contains(output, "...")
  end)

  test("failed, unfinished and incomplete tools never invent diffs", function()
    -- Failed or incomplete file mutations get input/output previews, never applied-diff views.
    local document, output = render(snapshot({ call("failed", "f"), call("pending", "f"),
      call("write", "f", "write"), call("none", "f"), call("unknown", "f") }, {
      result("failed", { patch = patch }, true), result("write"), result("none", { patch = {} }),
      { role = "toolResult", toolCallId = "unknown", details = { patch = patch } },
    }))
    assert(#targets(document) == 5)
    for _, target in pairs(document.targets) do assert(target.kind == "tool") end
    contains(output, "failed")
    contains(output, "unfinished")
    contains(output, "unknown status")
  end)

  test("custom tools, display fallback, and orphan results degrade explicitly", function()
    -- Artifact shape, not the tool name, controls availability; orphan completion remains visible.
    local custom = call("custom", nil, "remote_transform")
    custom.arguments.file_path = "remote/file"
    local document, output = render(snapshot({ custom }, {
      result("custom", { diff = " 1 -old\n 1 +new" }), result("orphan", nil, true),
    }))
    local target = document.targets[targets(document)[1]]
    assert(target.kind == "display_diff" and target.path == "remote/file")
    contains(output, "[orphan]")
    contains(output, "failed")
    local unified = render(snapshot({ custom }, { result("custom", { patch = patch }) }))
    assert(unified.targets[targets(unified)[1]].kind == "patch")
  end)

  test("inactive results cannot satisfy active calls; duplicate joins are rejected", function()
    -- A sibling result is not part of the active branch, despite matching the tool ID.
    local data = snapshot({ call("one", "file") })
    data.entries[#data.entries + 1] = entry("dead", "a", result("one", { patch = patch }))
    local document, output = render(data)
    local target = document.targets[targets(document)[1]]
    assert(target.kind == "tool" and target.result == nil)
    excludes(table.concat(assert(preview.render(target)), "\n"), "actual new")
    contains(output, "unfinished")
    invalid(snapshot({ call("one", "file"), call("one", "file") }))
    invalid(snapshot({ call("one", "file") }, { result("one"), result("one") }))
  end)

  test("size limits fail before creating a transcript buffer", function()
    -- Oversized fields and entry arrays are rejected without allocating a viewer.
    invalid({ entries = {}, leafId = string.rep("x", 1025) })
    local data = snapshot(string.rep("x", 33 * 1024 * 1024))
    local before = #vim.api.nvim_list_bufs()
    local buffer, err = transcript.open(session, data)
    assert(not buffer and err and #vim.api.nvim_list_bufs() == before)
    local entries = {}
    for index = 1, 50001 do entries[index] = entry(tostring(index), nil, {}) end
    invalid({ entries = entries, leafId = vim.NIL })
  end)

  test("transcript triggers existing Markdown FileType hooks", function()
    -- Observe the real event so Markdown formatters can attach to the scratch buffer.
    local group = vim.api.nvim_create_augroup("PISessionMarkdownTest", { clear = true })
    local seen = {}
    vim.api.nvim_create_autocmd("FileType", {
      group = group, pattern = "markdown",
      callback = function(event) seen[event.buf] = true end,
    })
    local source = { path = "/markdown/session.jsonl", cwd = "/markdown" }
    local buffer, err = transcript.open(source, snapshot("**Formatted message**"))
    vim.api.nvim_del_augroup_by_id(group)
    assert(buffer, err)
    assert(seen[buffer], "Markdown FileType hooks did not run")
    assert(vim.bo[buffer].filetype == "markdown" and not vim.bo[buffer].modifiable)
  end)

  test("gd opens exact recorded patch in-place with native Ctrl-O and buffer switching", function()
    -- Execute the real buffer mapping and jumplist keys, not a direct navigation helper.
    local data = snapshot({ call("navigation", "file") }, {
      result("navigation", { patch = patch }),
    })
    local document = render(data)
    local row = targets(document)[1]
    local global = vim.api.nvim_get_keymap("n")
    local window, count = vim.api.nvim_get_current_win(), #vim.api.nvim_list_wins()
    local buffer = assert(transcript.open(session, data, window))
    assert(#vim.api.nvim_list_wins() == count and vim.api.nvim_win_get_buf(window) == buffer)
    assert(vim.bo[buffer].buftype == "nofile" and vim.bo[buffer].bufhidden == "hide")
    assert(vim.bo[buffer].buflisted and not vim.bo[buffer].swapfile)
    assert(vim.bo[buffer].readonly and not vim.bo[buffer].modifiable)
    assert(vim.bo[buffer].filetype == "markdown")
    assert(vim.deep_equal(global, vim.api.nvim_get_keymap("n")))
    local maps = vim.api.nvim_buf_get_keymap(buffer, "n")
    assert(#maps == 1 and maps[1].lhs == "gd")
    vim.api.nvim_win_set_cursor(window, { row, 0 })
    feed("gd")
    local diff = vim.api.nvim_get_current_buf()
    assert(diff ~= buffer and vim.api.nvim_get_current_win() == window)
    assert(table.concat(vim.api.nvim_buf_get_lines(diff, 0, -1, false), "\n") == patch)
    assert(vim.bo[diff].filetype == "diff" and vim.bo[diff].readonly)
    assert(not vim.bo[diff].modifiable and #vim.api.nvim_list_wins() == count)
    feed("<C-O>")
    assert(vim.api.nvim_get_current_buf() == buffer)
    assert(vim.api.nvim_win_get_cursor(window)[1] == row)
    vim.cmd("buffer #")
    assert(vim.api.nvim_get_current_buf() == diff)
    vim.cmd("buffer " .. buffer)
    feed("gd")
    assert(vim.api.nvim_get_current_buf() == diff)
  end)

  test("open uses only the supplied existing window and creates no input buffer", function()
    -- Leave another window current so accidental splits or focus-dependent placement are visible.
    local original = vim.api.nvim_get_current_win()
    vim.cmd("vsplit")
    local current = vim.api.nvim_get_current_win()
    local previous = vim.api.nvim_win_get_buf(current)
    local windows, buffers = #vim.api.nvim_list_wins(), #vim.api.nvim_list_bufs()
    local buffer = assert(transcript.open({ path = "/target/window.jsonl", cwd = "/target" },
      { entries = {}, leafId = vim.NIL }, original))
    assert(#vim.api.nvim_list_wins() == windows and #vim.api.nvim_list_bufs() == buffers + 1)
    assert(vim.api.nvim_win_get_buf(original) == buffer)
    assert(vim.api.nvim_win_get_buf(current) == previous)
    assert(vim.api.nvim_get_current_win() == current)
    vim.api.nvim_win_close(current, true)
  end)

  test("refresh replaces targets, preserves identity and labels display fallback", function()
    -- Reuse diffs, then remove the artifact while retaining an honest input-only tool preview.
    local data = snapshot({ call("refresh", "file") }, { result("refresh", { diff = " 1 +new" }) })
    local document = render(data)
    local row = targets(document)[1]
    local buffer = assert(transcript.open(session, data))
    vim.api.nvim_win_set_cursor(0, { row, 0 })
    feed("gd")
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    contains(lines[1], "display diff (not a unified patch)")
    assert(lines[2] == " 1 +new" and vim.bo.filetype ~= "diff")
    local diff = vim.api.nvim_get_current_buf()
    local changed = snapshot({ call("refresh", "file") }, { result("refresh", { patch = patch }) })
    assert(transcript.open(session, changed) == buffer)
    vim.api.nvim_win_set_cursor(0, { row, 0 })
    feed("gd")
    assert(vim.api.nvim_get_current_buf() == diff)
    assert(table.concat(vim.api.nvim_buf_get_lines(diff, 0, -1, false), "\n") == patch)
    assert(vim.bo[diff].filetype == "diff")
    local refreshed = assert(transcript.open(session, snapshot({ call("refresh", "file") })))
    assert(refreshed == buffer)
    vim.api.nvim_win_set_cursor(0, { row, 0 })
    feed("gd")
    assert(vim.bo.filetype == "markdown")
    local pending = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
    contains(pending, "unfinished")
    contains(pending, "PROPOSED OLD")
    excludes(pending, "actual new")
    feed("<C-o>")
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    local original_notify, notification = vim.notify, nil
    vim.notify = function(value) notification = value end
    feed("gd")
    vim.notify = original_notify
    assert(vim.api.nvim_get_current_buf() == buffer)
    contains(notification or "", "No recorded preview")
    local another = { path = "/another/session.jsonl", cwd = session.cwd }
    local other = assert(transcript.open(another, data))
    assert(other ~= buffer)
    local before = #vim.api.nvim_list_bufs()
    local closed, err = transcript.open(session, data, 999999)
    assert(not closed and err and #vim.api.nvim_list_bufs() == before)
  end)

  test("native delete and unload allow reopening transcripts and recorded diffs", function()
    -- Exercise real buffer unloading rather than refreshing only already-loaded buffers.
    for _, command in ipairs({ "bdelete", "bunload" }) do
      local source = { path = "/native/" .. command .. ".jsonl", cwd = "/native" }
      local data = snapshot({ call("unload", "file") }, { result("unload", { patch = patch }) })
      local document = assert(transcript.render(source, data))
      local row = targets(document)[1]
      local buffer = assert(transcript.open(source, data))
      vim.api.nvim_win_set_cursor(0, { row, 0 })
      feed("gd")
      local diff = vim.api.nvim_get_current_buf()
      vim.cmd(command .. " " .. diff)
      assert(not vim.api.nvim_buf_is_loaded(diff))
      vim.cmd("buffer " .. buffer)
      vim.cmd(command .. " " .. buffer)
      assert(not vim.api.nvim_buf_is_loaded(buffer))
      local reopened, err = transcript.open(source, data)
      assert(reopened, err)
      assert(vim.api.nvim_buf_is_loaded(reopened) and not vim.bo[reopened].modifiable)
      assert(vim.bo[reopened].buflisted and vim.bo[reopened].filetype == "markdown")
      vim.api.nvim_win_set_cursor(0, { row, 0 })
      feed("gd")
      assert(vim.bo.filetype == "diff" and not vim.bo.modifiable)
      assert(table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n") == patch)
      feed("<C-o>")
      assert(vim.api.nvim_get_current_buf() == reopened)
      assert(vim.api.nvim_win_get_cursor(0)[1] == row)
    end
  end)
end
