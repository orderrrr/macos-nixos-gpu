local java_cmds = vim.api.nvim_create_augroup('java_cmds', { clear = true })
local cache_vars = {}

local root_files = {
  '.git',
  'mvnw',
  'gradlew',
  'pom.xml',
  'build.gradle',
}

local features = {
  -- change this to `true` to enable codelens
  codelens = false,

  -- change this to `true` if you have `nvim-dap`,
  -- `java-test` and `java-debug-adapter` installed
  debugger = true,
}

local function is_java_source(bufnr)
  local name = vim.api.nvim_buf_get_name(bufnr)
  return name:match('%.java$') ~= nil
end

local function get_jdtls_client(bufnr)
  local clients = vim.lsp.get_active_clients({ bufnr = bufnr, name = 'jdtls' })
  return clients and clients[1] or nil
end

local function command_supported(client, command)
  if not client or not client.server_capabilities then return false end
  local exec = client.server_capabilities.executeCommandProvider
  local cmds = type(exec) == 'table' and (exec.commands or exec) or nil
  if type(cmds) ~= 'table' then return false end
  for _, c in ipairs(cmds) do
    if c == command then return true end
  end
  return false
end

local function get_jdtls_paths()
  if cache_vars.paths then return cache_vars.paths end

  local path = {
    data_dir = vim.fn.stdpath('cache') .. '/nvim-jdtls',
    bundles  = {},
  }

  local debug_dir = vim.env.JAVA_DEBUG_BUNDLE or ''
  if debug_dir ~= '' then
    local jars = vim.split(vim.fn.glob(debug_dir .. '/com.microsoft.java.debug.plugin-*.jar'), '\n')
    if jars[1] and jars[1] ~= '' then vim.list_extend(path.bundles, jars) end
  end

  local test_dir = vim.env.JAVA_TEST_BUNDLE or ''
  if test_dir ~= '' then
    local jars = vim.split(vim.fn.glob(test_dir .. '/*.jar'), '\n')
    if jars[1] and jars[1] ~= '' then vim.list_extend(path.bundles, jars) end
  end

  path.runtimes = {
    {
      name = 'JavaSE-21',
      path = '/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home',
    },
  }

  cache_vars.paths = path
  return path
end

local function enable_codelens(bufnr)
  pcall(vim.lsp.codelens.refresh)

  vim.api.nvim_create_autocmd('BufWritePost', {
    buffer = bufnr,
    group = java_cmds,
    desc = 'refresh codelens',
    callback = function()
      pcall(vim.lsp.codelens.refresh)
    end,
  })
end

local function enable_debugger(bufnr)
  require('jdtls').setup_dap { hotcodereplace = 'auto' }
  require('jdtls.dap').setup_dap_main_class_configs()

  local opts = { buffer = bufnr }
  vim.keymap.set('n', '<leader>df', function() require('jdtls').test_class({ config = { console = 'console' } }) end,
    opts)
  vim.keymap.set('n', '<leader>dfn',
    function() require('jdtls').test_nearest_method({ config = { console = 'console' } }) end, opts)
end

local function jdtls_on_attach(client, bufnr)
  if features.codelens then
    enable_codelens(bufnr)
  end

  vim.defer_fn(function()
    if features.debugger
        and is_java_source(bufnr)
        and command_supported(get_jdtls_client(bufnr), 'vscode.java.resolveMainClass') then
      enable_debugger(bufnr)
    end
  end, 200)

  local opts = { buffer = bufnr }
  vim.keymap.set('n', '<A-o>', "<cmd>lua require('jdtls').organize_imports()<cr>", opts)
  vim.keymap.set('n', 'crv', "<cmd>lua require('jdtls').extract_variable()<cr>", opts)
  vim.keymap.set('x', 'crv', "<esc><cmd>lua require('jdtls').extract_variable(true)<cr>", opts)
  vim.keymap.set('n', 'crc', "<cmd>lua require('jdtls').extract_constant()<cr>", opts)
  vim.keymap.set('x', 'crc', "<esc><cmd>lua require('jdtls').extract_constant(true)<cr>", opts)
  vim.keymap.set('x', 'crm', "<esc><Cmd>lua require('jdtls').extract_method(true)<cr>", opts)
end

local function jdtls_setup(on_attach, capabilities)
  local jdtls = require 'jdtls'


  local path = get_jdtls_paths()
  local data_dir = path.data_dir .. '/' .. vim.fn.fnamemodify(vim.fn.getcwd(), ':p:h:t')


  if cache_vars.capabilities == nil then
    jdtls.extendedClientCapabilities.resolveAdditionalTextEditsSupport = true

    local ok_cmp, cmp_lsp = pcall(require, 'cmp_nvim_lsp')
    cache_vars.capabilities = vim.tbl_deep_extend('force', vim.lsp.protocol.make_client_capabilities(),
      ok_cmp and cmp_lsp.default_capabilities() or {})
  end

  -- jdtls wrapper (pkgs.jdt-language-server) handles classpath/launcher/config.
  local lombok_jar = vim.env.LOMBOK_JAR or ''
  local cmd = { 'jdtls' }
  if lombok_jar ~= '' then
    table.insert(cmd, '--jvm-arg=-javaagent:' .. lombok_jar)
  end
  table.insert(cmd, '-data')
  table.insert(cmd, data_dir)


  local home = os.getenv 'HOME'

  local lsp_settings = {
    java = {
      -- jdt = {
      --   ls = {
      --     vmargs = "-XX:+UseParallelGC -XX:GCTimeRatio=4 -XX:AdaptiveSizePolicyWeight=90 -Dsun.zip.disableMemoryMapping=true -Xmx1G -Xms100m"
      --   }
      -- },
      eclipse = {
        downloadSources = true,
      },
      configuration = {
        updateBuildConfiguration = 'interactive',
        runtimes = {
          {
            name = 'JavaSE-21',
            path = '/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home',
          },
          -- {
          --     name = 'JavaSE-24',
          --     path = '/Library/Java/JavaVirtualMachines/zulu-24.jdk/Contents/Home/',
          -- },
          -- {
          --   name = 'JavaSE-1.8',
          --   path = '/Library/Java/JavaVirtualMachines/zulu-8.jdk/Contents/Home',
          -- },
        },
      },
      maven = {
        downloadSources = true,
      },
      implementationsCodeLens = {
        enabled = true,
      },
      referencesCodeLens = {
        enabled = true,
      },
      -- inlayHints = {
      --   parameterNames = {
      --     enabled = 'all' -- literals, all, none
      --   }
      -- },
      format = {
        enabled = true,
        settings = {
          url = home .. '/.m2/VeritranE.xml',
          profile = 'Veritran',
        },
      },
      completion = {
        importOrder = { "java", "javax", "org", "com" }, -- puts org.* before com.* (blank line between groups)
      },
      sources = {
        organizeImports = { starThreshold = 999, staticStarThreshold = 999 },
      },
    },
    signatureHelp = {
      enabled = true,
    },
    contentProvider = {
      preferred = 'fernflower',
    },
    extendedClientCapabilities = jdtls.extendedClientCapabilities,
    sources = {
      organizeImports = {
        starThreshold = 9999,
        staticStarThreshold = 9999,
      },
    },
    codeGeneration = {
      toString = {
        template = '${object.className}{${member.name()}=${member.value}, ${otherMembers}}',
      },
      useBlocks = true,
    },
  }

  local extendedClientCapabilities = require('jdtls').extendedClientCapabilities
  extendedClientCapabilities.resolveAdditionalTextEditsSupport = true

  -- This starts a new client & server,
  -- or attaches to an existing client & server depending on the `root_dir`.
  jdtls.start_or_attach({
    cmd = cmd,
    settings = lsp_settings,
    on_attach = function(unknown, bufnr)
      on_attach(unknown, bufnr)
      jdtls_on_attach(unknown, bufnr)
    end,
    -- on_attach = on_attach,
    capabilities = vim.tbl_deep_extend('force', cache_vars.capabilities, capabilities),
    -- capabilities = vim.tbl_deep_extend('force', cache_vars.capabilities, capabilities),
    root_dir = jdtls.setup.find_root(root_files),
    flags = {
      allow_incremental_sync = true,
    },
    init_options = {
      bundles = path.bundles,
      extendedClientCapabilities = extendedClientCapabilities,
    },
  })
end

local jdtls_autocmd = function(on_attach, capabilities)
  vim.api.nvim_create_autocmd('FileType', {
    group = java_cmds,
    pattern = 'java',
    desc = 'Setup jdtls',
    callback = function()
      jdtls_setup(on_attach, capabilities)
    end,
  })
end

return jdtls_autocmd
