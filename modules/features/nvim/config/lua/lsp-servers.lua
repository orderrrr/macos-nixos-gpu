-- Static LSP server configurations using Neovim 0.11+ native API.
-- All binaries are installed by Nix (home/lsp-tools.nix).
-- vim.lsp.config() registers the config; vim.lsp.enable() creates the
-- FileType autocmd that starts the server when a matching buffer opens.

vim.lsp.config('lua_ls', {
  cmd      = { 'lua-language-server' },
  filetypes = { 'lua' },
  root_markers = { '.luarc.json', '.luarc.jsonc', '.stylua.toml', 'stylua.toml', '.git' },
  single_file_support = true,
  settings = {
    Lua = {
      workspace = { library = vim.api.nvim_get_runtime_file('lua', true) },
    },
  },
})

vim.lsp.config('zls', {
  cmd      = { 'zls' },
  filetypes = { 'zig', 'zir' },
  root_markers = { 'build.zig', 'build.zig.zon', '.git' },
})

vim.lsp.config('clangd', {
  cmd      = { 'clangd' },
  filetypes = { 'c', 'cpp', 'objc', 'objcpp', 'cuda', 'proto' },
  root_markers = { '.clangd', 'compile_commands.json', 'compile_flags.txt', '.git' },
})

vim.lsp.config('rust_analyzer', {
  cmd      = { 'rust-analyzer' },
  filetypes = { 'rust' },
  root_markers = { 'Cargo.toml', 'Cargo.lock', '.git' },
})

vim.lsp.config('pyright', {
  cmd      = { 'pyright-langserver', '--stdio' },
  filetypes = { 'python' },
  root_markers = { 'pyproject.toml', 'setup.py', 'setup.cfg', 'requirements.txt', '.git' },
  single_file_support = true,
})

vim.lsp.config('nil_ls', {
  cmd      = { 'nil' },
  filetypes = { 'nix' },
  root_markers = { 'flake.nix', 'default.nix', '.git' },
  single_file_support = true,
})

vim.lsp.config('jsonls', {
  cmd      = { 'vscode-json-language-server', '--stdio' },
  filetypes = { 'json', 'jsonc' },
  root_markers = { '.git' },
  single_file_support = true,
  init_options = { provideFormatter = true },
})

vim.lsp.config('yamlls', {
  cmd      = { 'yaml-language-server', '--stdio' },
  filetypes = { 'yaml', 'yaml.docker-compose', 'yaml.gitlab' },
  root_markers = { '.git' },
  single_file_support = true,
})

vim.lsp.config('ansiblels', {
  cmd      = { 'ansible-language-server', '--stdio' },
  filetypes = { 'yaml.ansible' },
  root_markers = { '.git' },
})

vim.lsp.config('fish_lsp', {
  cmd      = { 'fish-lsp', 'start' },
  filetypes = { 'fish' },
  root_markers = { '.git' },
  single_file_support = true,
})

vim.lsp.config('lemminx', {
  cmd      = { 'lemminx' },
  filetypes = { 'xml', 'xsd', 'xsl', 'xslt', 'svg' },
  root_markers = { '.git' },
  single_file_support = true,
})

vim.lsp.config('glsl_analyzer', {
  cmd      = { 'glsl_analyzer' },
  filetypes = { 'glsl', 'vert', 'frag', 'geom', 'tesc', 'tese', 'comp', 'hlsl' },
  root_markers = { '.git' },
  single_file_support = true,
})

vim.lsp.enable({
  'lua_ls', 'zls', 'clangd', 'rust_analyzer', 'pyright',
  'nil_ls', 'jsonls', 'yamlls', 'ansiblels',
  'fish_lsp', 'lemminx', 'glsl_analyzer',
})
