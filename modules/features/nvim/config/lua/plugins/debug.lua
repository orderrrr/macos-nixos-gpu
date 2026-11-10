local util = require('util')

util.lazy_key(
  { 'nvim-nio', 'nvim-dap', 'nvim-dap-ui' },
  {
    { 'n', '<leader>do' },
    { 'n', '<leader>dt' },
    { 'n', '<leader>dn' },
  },
  function()
    require("dapui").setup()
    local dap = require('dap')

    -- codelldb path set by Nix (home/lsp-tools.nix → CODELLDB_PATH)
    local codelldb_path = vim.env.CODELLDB_PATH or vim.fn.exepath('codelldb')
    if not codelldb_path or codelldb_path == '' then
      vim.notify('codelldb not found: set CODELLDB_PATH or add codelldb to PATH', vim.log.levels.WARN)
      return
    end

    dap.adapters.codelldb = {
      type = "server",
      port = "${port}",
      executable = {
        command = codelldb_path,
        args = { "--port", "${port}" },
      },
    }

    local function zig_default_program()
      local bin_dir = vim.fn.getcwd() .. "/zig-out/bin"
      local progs = vim.fn.glob(bin_dir .. "/*", 0, 1)
      if #progs == 1 then
        return progs[1]
      end
      return vim.fn.input("Path to executable: ", bin_dir .. "/", "file")
    end

    dap.configurations.zig = {
      {
        name = "Launch (CodeLLDB)",
        type = "codelldb",
        request = "launch",
        program = zig_default_program,
        cwd = "${workspaceFolder}",
        stopOnEntry = false,
        args = {},
        runInTerminal = false, -- set true if you need interactive stdin
      },
    }

    vim.keymap.set('n', '<leader>do', require('dapui').toggle)
    vim.keymap.set('n', '<leader>dt', require('dap').toggle_breakpoint)
    vim.keymap.set('n', '<leader>dn', require('dap').continue)
  end
)
