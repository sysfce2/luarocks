local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local assert = _tl_compat and _tl_compat.assert or assert; local ipairs = _tl_compat and _tl_compat.ipairs or ipairs; local math = _tl_compat and _tl_compat.math or math; local pairs = _tl_compat and _tl_compat.pairs or pairs; local string = _tl_compat and _tl_compat.string or string
local vers = {}

local util = require("luarocks.core.util")
local require = nil


local deltas = {
   dev = 120000000,
   scm = 110000000,
   cvs = 100000000,
   rc = -1000,
   pre = -10000,
   beta = -100000,
   alpha = -1000000,
}







local version_mt = {







   __eq = function(v1, v2)
      if #v1 ~= #v2 then
         return false
      end
      for i = 1, #v1 do
         if v1[i] ~= v2[i] then
            return false
         end
      end
      if v1.revision and v2.revision then
         return (v1.revision == v2.revision)
      end
      return true
   end,







   __lt = function(v1, v2)
      for i = 1, math.max(#v1, #v2) do
         local v1i, v2i = v1[i] or 0, v2[i] or 0
         if v1i ~= v2i then
            return (v1i < v2i)
         end
      end
      if v1.revision and v2.revision then
         return (v1.revision < v2.revision)
      end
      return false
   end,



   __le = function(v1, v2)
      return not (v2 < v1)
   end,



   __tostring = function(v)
      return v.string
   end,
}

local version_cache = {}
setmetatable(version_cache, {
   __mode = "kv",
})












function vers.parse_version(vstring)
   if not vstring then return nil end
   assert(type(vstring) == "string")

   local cached = version_cache[vstring]
   if cached then
      return cached
   end

   local version = {}
   local i = 1

   local function add_token(number)
      version[i] = version[i] and version[i] + number / 100000 or number
      i = i + 1
   end


   local v = vstring:match("^%s*(.*)%s*$")
   version.string = v

   local main, revision = v:match("(.*)%-(%d+)$")
   if revision then
      v = main
      version.revision = tonumber(revision)
   end
   while #v > 0 do

      local token, rest = v:match("^(%d+)[%.%-%_]*(.*)")
      if token then
         add_token(tonumber(token))
      else

         token, rest = v:match("^(%a+)[%.%-%_]*(.*)")
         if not token then
            util.warning("version number '" .. v .. "' could not be parsed.")
            version[i] = 0
            break
         end
         version[i] = deltas[token] or (token:byte() / 1000)
      end
      v = rest
   end
   setmetatable(version, version_mt)
   version_cache[vstring] = version
   return version
end





function vers.compare_versions(a, b)
   if a == b then
      return false
   end
   return vers.parse_version(a) > vers.parse_version(b)
end













local function partial_match(version_for_parse, requested_for_parce)
   assert(type(version_for_parse) == "string" or type(version_for_parse) == "table")
   assert(type(requested_for_parce) == "string" or type(requested_for_parce) == "table")

   if type(version_for_parse) ~= "table" then local version = vers.parse_version(version_for_parse) end
   if type(requested_for_parce) ~= "table" then local requested = vers.parse_version(requested_for_parce) end
   if not version or not requested then return false end

   for i, ri in ipairs(requested) do
      local vi = version[i] or 0
      if ri ~= vi then return false end
   end
   if requested.revision then
      return requested.revision == version.revision
   end
   return true
end






function vers.match_constraints(version, constraints)
   assert(type(version) == "table")
   assert(type(constraints) == "table")
   local ok = true
   setmetatable(version, version_mt)
   for _, constr in pairs(constraints) do
      if type(constr.version) == "string" then
         constr.version = vers.parse_version(constr.version)
      end
      local constr_version, constr_op = constr.version, constr.op
      setmetatable(constr_version, version_mt)
      if constr_op == "==" then ok = version == constr_version
      elseif constr_op == "~=" then ok = version ~= constr_version
      elseif constr_op == ">" then ok = version > constr_version
      elseif constr_op == "<" then ok = version < constr_version
      elseif constr_op == ">=" then ok = version >= constr_version
      elseif constr_op == "<=" then ok = version <= constr_version
      elseif constr_op == "~>" then ok = partial_match(version, constr_version)
      end
      if not ok then break end
   end
   return ok
end

return vers
