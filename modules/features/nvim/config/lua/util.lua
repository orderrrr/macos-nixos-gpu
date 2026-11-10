local M = {}

function M.copy_with_numbers()
	-- Get the start and end lines of the current visual selection
	local start_line = vim.fn.line("'<")
	local end_line = vim.fn.line("'>")

	-- Get the lines from the buffer
	local lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)

	-- Create a new list with line numbers prepended
	local numbered_lines = {}
	for i, line in ipairs(lines) do
		-- The number is the 1-based index `i`
		table.insert(numbered_lines, tostring(i) .. " " .. line)
	end

	-- Combine the lines into a single string
	local content = table.concat(numbered_lines, "\n")

	-- Copy the content to the system clipboard register '+'
	vim.fn.setreg('+', content)

	-- Print a confirmation message
	vim.notify("Copied " .. #lines .. " lines to clipboard with numbers.", vim.log.levels.INFO)
end

-- ---------------------------------------------------------------------------
-- Lazy-loading helpers for vim.pack plugins.
--
-- Plugins registered with `vim.pack.add({...}, { load = function() end })`
-- are installed but never sourced. The helpers below source them on first
-- trigger via `vim.cmd.packadd(name)` and then run a user `setup_fn` that
-- registers the real keymaps/commands/autocmds.
-- ---------------------------------------------------------------------------

local function to_list(x) return type(x) == 'string' and { x } or x end

local function packadd_all(names)
	for _, n in ipairs(names) do
		vim.cmd.packadd(n)
	end
end

--- Register keymap stubs that load pack plugins + run setup on first press.
--- The stub replays the key so the real mapping (registered by setup_fn) fires.
--- @param pack_names string|string[]
--- @param keys { [1]: string|string[], [2]: string }[]  list of {mode(s), lhs}
--- @param setup_fn fun()
function M.lazy_key(pack_names, keys, setup_fn)
	pack_names = to_list(pack_names)
	local loaded = false
	local function load_once()
		if loaded then return end
		loaded = true
		for _, k in ipairs(keys) do
			pcall(vim.keymap.del, k[1], k[2])
		end
		packadd_all(pack_names)
		setup_fn()
	end
	for _, k in ipairs(keys) do
		local mode, lhs = k[1], k[2]
		vim.keymap.set(mode, lhs, function()
			local m = vim.fn.mode()
			load_once()
			local prefix = ''
			if m == 'v' or m == 'V' or m == '\22' then
				prefix = 'gv'
			end
			vim.api.nvim_feedkeys(
				prefix .. vim.api.nvim_replace_termcodes(lhs, true, false, true),
				'm', false)
		end, { desc = '[lazy] ' .. table.concat(pack_names, ',') })
	end
end

--- Register user-command stubs that load pack plugins + run setup on first
--- invocation, then re-dispatch the command.
--- @param pack_names string|string[]
--- @param cmds string|string[]
--- @param setup_fn fun()
function M.lazy_cmd(pack_names, cmds, setup_fn)
	pack_names = to_list(pack_names)
	cmds = to_list(cmds)
	local loaded = false
	local function load_once()
		if loaded then return end
		loaded = true
		for _, c in ipairs(cmds) do pcall(vim.api.nvim_del_user_command, c) end
		packadd_all(pack_names)
		setup_fn()
	end
	for _, c in ipairs(cmds) do
		vim.api.nvim_create_user_command(c, function(opts)
			load_once()
			local bang = opts.bang and '!' or ''
			local line = c .. bang .. ' ' .. (opts.args or '')
			vim.cmd(line)
		end, { bang = true, nargs = '*', complete = 'file', desc = '[lazy] ' .. table.concat(pack_names, ',') })
	end
end

--- Register a one-shot autocmd that loads pack plugins + runs setup.
--- @param pack_names string|string[]
--- @param events string|string[]
--- @param setup_fn fun()
--- @param opts? { pattern?: string|string[] }
function M.lazy_event(pack_names, events, setup_fn, opts)
	pack_names = to_list(pack_names)
	opts = opts or {}
	vim.api.nvim_create_autocmd(events, {
		once = true,
		pattern = opts.pattern,
		callback = function()
			packadd_all(pack_names)
			setup_fn()
		end,
	})
end

return M
