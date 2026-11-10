local ls = require "luasnip"

local s = ls.snippet
local t = ls.text_node

-- ZTRACY zone
ls.add_snippets("zig", {
  s("zone", {
    t({ 'const zone = rd.log.ztrace(@src());', "defer zone.End();" }),
  }),
})
