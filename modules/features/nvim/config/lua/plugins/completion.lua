vim.cmd.packadd 'LuaSnip'
vim.cmd.packadd 'friendly-snippets'
vim.cmd.packadd 'blink.compat'
vim.cmd.packadd 'blink.cmp'

require('luasnip').setup {}
require('luasnip.loaders.from_vscode').lazy_load()
require('plugins.snippets')

require('blink.cmp').setup({
	keymap = { preset = 'default' },
	completion = {
		list = {
			selection = {
				preselect = true,
				auto_insert = true,
			},
		},
		accept = { auto_brackets = { enabled = true } },
		menu = {
			border = "rounded",
			auto_show = true,
			draw = {
				columns = {
					{ "label",     "label_description", gap = 1 },
					{ "kind_icon", "kind" },
				},
			},
		},
		documentation = {
			auto_show = true,
			window = {
				border = "single",
			},
		},
		ghost_text = {
			enabled = false,
		},
	},
	fuzzy = {
		implementation = 'lua',
	},
	appearance = {
		use_nvim_cmp_as_default = true,
		nerd_font_variant = 'normal'
	},
	sources = {
		default = { 'lsp', 'path', 'snippets', 'buffer' },
		providers = {},
	},
	signature = { enabled = true, window = { border = "rounded" } },
	snippets = { preset = 'luasnip' },
})
