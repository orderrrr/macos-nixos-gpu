local M = {}
local options = {}
local pending
local generation = 0

local function notify(message, level)
  vim.notify('PISession: ' .. message, level or vim.log.levels.INFO)
end

local function begin_request()
  generation = generation + 1
  if pending then
    pending()
    pending = nil
  end
  return generation
end

local function request_options()
  local result = vim.deepcopy(options)
  result.agent_dir = vim.fs.normalize(vim.fn.expand(
    result.agent_dir or vim.env.PI_CODING_AGENT_DIR or '~/.pi/agent'
  ))
  return result
end

--- Open a read-only RPC snapshot without replacing the editor's other windows.
function M.open(session, window)
  local request = begin_request()
  window = window or vim.api.nvim_get_current_win()
  if not vim.api.nvim_win_is_valid(window) then
    notify('The destination window was closed; select the session again.')
    return
  end
  local original_buffer = vim.api.nvim_win_get_buf(window)
  notify('Loading session through Pi RPC…')
  pending = require('pi_session.rpc').load(session, request_options(), function(err, data)
    if request ~= generation then
      return
    end
    pending = nil
    if err then
      notify(err, vim.log.levels.ERROR)
      return
    end
    if not vim.api.nvim_win_is_valid(window) then
      notify('The destination window was closed; select the session again.')
      return
    end
    if vim.api.nvim_win_get_buf(window) ~= original_buffer then
      notify('The destination buffer changed; select the session again to view it.')
      return
    end
    local buffer, render_error = require('pi_session.transcript').open(session, data, window)
    if not buffer then
      notify(render_error, vim.log.levels.ERROR)
    end
  end)
end

local function show_picker(records, window, request, cwd)
  local actions = require('telescope.actions')
  local state = require('telescope.actions.state')
  require('telescope.pickers').new({}, {
    prompt_title = 'Pi sessions · ' .. vim.fs.basename(cwd),
    previewer = false,
    finder = require('telescope.finders').new_table({
      results = records,
      entry_maker = function(session)
        return {
          value = session,
          display = string.format('%s  %s  [%s]', os.date('%Y-%m-%d %H:%M', session.modified),
            session.title, session.id:sub(1, 8)),
          ordinal = session.title .. ' ' .. session.preview .. ' ' .. session.id,
        }
      end,
    }),
    sorter = require('telescope.config').values.generic_sorter({}),
    attach_mappings = function(prompt_buffer)
      actions.select_default:replace(function()
        local selected = state.get_selected_entry()
        actions.close(prompt_buffer)
        if selected and request == generation then
          vim.schedule(function()
            if request == generation then
              M.open(selected.value, window)
            end
          end)
        end
      end)
      return true
    end,
  }):find()
end

function M.pick()
  local request = begin_request()
  local ok = pcall(require, 'telescope.pickers')
  if not ok then
    notify('Telescope is required. Load telescope.nvim and try again.', vim.log.levels.ERROR)
    return
  end
  local cwd = vim.fn.getcwd()
  local window = vim.api.nvim_get_current_win()
  local discovery = require('pi_session.sessions')
  pending = discovery.list(cwd, request_options(), function(err, records, skipped)
    if request ~= generation then
      return
    end
    pending = nil
    if err then
      notify(err, vim.log.levels.ERROR)
    elseif #records == 0 then
      notify('No Pi sessions for ' .. cwd)
    else
      if skipped and skipped > 0 then
        notify(string.format('Skipped %d unreadable session files.', skipped), vim.log.levels.WARN)
      end
      show_picker(records, window, request, cwd)
    end
  end)
end

function M.setup(configuration)
  local configured = vim.deepcopy(configuration or {})
  for _, key in ipairs({ 'timeout_ms', 'max_bytes', 'max_sessions', 'preview_bytes' }) do
    local value = configured[key]
    assert(value == nil or (type(value) == 'number' and value >= 1 and value % 1 == 0),
      key .. ' must be a positive integer')
  end
  begin_request()
  options = configured
  vim.api.nvim_create_user_command('PISession', M.pick, {
    desc = 'Search this project’s Pi sessions and view an RPC snapshot',
  })
  local group = vim.api.nvim_create_augroup('PISession', { clear = true })
  vim.api.nvim_create_autocmd('VimLeavePre', {
    group = group,
    callback = begin_request,
  })
end

return M
