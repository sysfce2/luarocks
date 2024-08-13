local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local assert = _tl_compat and _tl_compat.assert or assert; local ipairs = _tl_compat and _tl_compat.ipairs or ipairs; local pcall = _tl_compat and _tl_compat.pcall or pcall; local table = _tl_compat and _tl_compat.table or table; local test = {TestModules = {}, }







local fetch = require("luarocks.fetch")
local deps = require("luarocks.deps")
local util = require("luarocks.util")










local test_types = {
   "busted",
   "command",
}

local test_modules = {}

for _, test_type in ipairs(test_types) do
   local mod
   if test_type == "command" then
      mod = require("luarocks.test.command")
   elseif test_type == "busted" then
      mod = require("luarocks.test.busted")
   end
   table.insert(test_modules, mod)
   test_modules.typetomod[test_type] = mod
   test_modules.modtotype[mod] = test_type
end

local function get_test_type(rockspec)
   if rockspec.test and rockspec.test.type then
      return rockspec.test.type
   end

   for _, test_module in ipairs(test_modules) do
      if test_module.detect_type() then
         return test_modules.modtotype[test_module]
      end
   end

   return nil, "could not detect test type -- no test suite for " .. rockspec.package .. "?"
end


function test.run_test_suite(rockspec_arg, test_type, args, prepare)
   local rockspec
   if type(rockspec_arg) == "string" then
      local err, errcode
      rockspec, err, errcode = fetch.load_rockspec(rockspec_arg)
      if err then
         return nil, err, errcode
      end
   else
      rockspec = rockspec_arg
   end

   if not test_type then
      local err
      test_type, err = get_test_type(rockspec)
      if not test_type then
         return nil, err
      end
   end
   assert(test_type)

   local all_deps = {
      "dependencies",
      "build_dependencies",
      "test_dependencies",
   }
   for _, dep_kind in ipairs(all_deps) do
      if (rockspec)[dep_kind] and next((rockspec)[dep_kind]) ~= nil then
         local _, err, errcode = deps.fulfill_dependencies(rockspec, dep_kind, "all")
         if err then
            return nil, err, errcode
         end
      end
   end

   local pok, test_mod
   if test_type == "command" then
      pok, test_mod = pcall(require, "luarocks.test.command")
      if not pok then
         return nil, "failed loading test execution module luarocks.test.command"
      end
   elseif test_type == "busted" then
      pok, test_mod = pcall(require, "luarocks.test.busted")
      if not pok then
         return nil, "failed loading test execution module luarocks.test.busted"
      end
   end

   if prepare then
      if test_type == "busted" then
         return test_mod.run_tests(rockspec.test, { "--version" })
      else
         return true
      end
   else
      local flags = rockspec.test and rockspec.test.flags
      if type(flags) == "table" then
         util.variable_substitutions(flags, rockspec.variables)


         for i = 1, #flags do
            table.insert(args, i, flags[i])
         end
      end

      return test_mod.run_tests(rockspec.test, args)
   end
end

return test
