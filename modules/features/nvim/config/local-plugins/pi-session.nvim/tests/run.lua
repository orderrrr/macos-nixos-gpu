-- Model-free checks run in a clean Neovim, independent of the user's startup plugins.
local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')
vim.opt.runtimepath:prepend(root)
local passed, failed = 0, 0
local function test(name, check)
  local ok, err = xpcall(check, debug.traceback)
  if ok then
    passed = passed + 1
    print('PASS ' .. name)
  else
    failed = failed + 1
    io.stderr:write('FAIL ' .. name .. '\n' .. tostring(err) .. '\n')
  end
end
local suites = vim.split(vim.env.PI_SESSION_TEST or 'sessions,transcript,folds,rpc,picker', ',')
for _, suite in ipairs(suites) do
  local ok, tests = pcall(dofile, root .. '/tests/' .. suite .. '.lua')
  if not ok then
    failed = failed + 1
    io.stderr:write(tostring(tests) .. '\n')
  else
    tests(test)
  end
end
print(string.format('%d passed, %d failed', passed, failed))
if failed > 0 then
  vim.cmd('cquit 1')
else
  vim.cmd('qa!')
end
