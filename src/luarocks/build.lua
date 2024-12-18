local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local io = _tl_compat and _tl_compat.io or io; local ipairs = _tl_compat and _tl_compat.ipairs or ipairs; local pairs = _tl_compat and _tl_compat.pairs or pairs; local pcall = _tl_compat and _tl_compat.pcall or pcall; local string = _tl_compat and _tl_compat.string or string; local type = type
local build = {Builder = {}, }






local path = require("luarocks.path")
local util = require("luarocks.util")
local fun = require("luarocks.fun")
local fetch = require("luarocks.fetch")
local fs = require("luarocks.fs")
local dir = require("luarocks.dir")
local deps = require("luarocks.deps")
local cfg = require("luarocks.core.cfg")
local vers = require("luarocks.core.vers")
local repos = require("luarocks.repos")
local repo_writer = require("luarocks.repo_writer")
local deplocks = require("luarocks.deplocks")













do



   local function extract_from_rockspec(files)
      for name, content in pairs(files) do
         local fd = io.open(dir.path(fs.current_dir(), name), "w+")
         fd:write(content)
         fd:close()
      end
   end







   function build.apply_patches(rockspec)

      if not (rockspec.build.extra_files or rockspec.build.patches) then
         return true
      end

      local fd = io.open(fs.absolute_name(".luarocks.patches.applied"), "r")
      if fd then
         fd:close()
         return true
      end

      if rockspec.build.extra_files then
         extract_from_rockspec(rockspec.build.extra_files)
      end
      if rockspec.build.patches then
         extract_from_rockspec(rockspec.build.patches)
         for patch, patchdata in util.sortedpairs(rockspec.build.patches) do
            util.printout("Applying patch " .. patch .. "...")
            local create_delete = rockspec:format_is_at_least("3.0")
            local ok, _err = fs.apply_patch(tostring(patch), patchdata, create_delete)
            if not ok then
               return nil, "Failed applying patch " .. patch
            end
         end
      end

      fd = io.open(fs.absolute_name(".luarocks.patches.applied"), "w")
      if fd then
         fd:close()
      end
      return true
   end
end

local function check_macosx_deployment_target(rockspec)
   local target = rockspec.build.macosx_deployment_target
   local function patch_variable(var)
      local rockspec_variables = rockspec.variables
      if rockspec_variables[var]:match("MACOSX_DEPLOYMENT_TARGET") then
         rockspec_variables[var] = (rockspec_variables[var]):gsub("MACOSX_DEPLOYMENT_TARGET=[^ ]*", "MACOSX_DEPLOYMENT_TARGET=" .. target)
      else
         rockspec_variables[var] = "env MACOSX_DEPLOYMENT_TARGET=" .. target .. " " .. rockspec_variables[var]
      end
   end
   if cfg.is_platform("macosx") and rockspec:format_is_at_least("3.0") and target then
      local version = util.popen_read("sw_vers -productVersion")
      if version:match("^%d+%.%d+%.%d+$") or version:match("^%d+%.%d+$") then
         if vers.compare_versions(target, version) then
            return nil, ("This rock requires Mac OSX %s, and you are running %s."):format(target, version)
         end
      end
      patch_variable("CC")
      patch_variable("LD")
   end
   return true
end

local function process_dependencies(rockspec, opts, cwd)
   if not opts.build_only_deps then
      local ok, err, errcode = deps.check_external_deps(rockspec, "build")
      if not ok then
         return nil, err, errcode
      end
   end

   if opts.deps_mode == "none" then
      return true
   end

   local deplock_dir = fs.exists(dir.path(cwd, "luarocks.lock")) and cwd or nil

   if not opts.build_only_deps then
      if next(rockspec.build_dependencies) then

         local user_lua_version = cfg.lua_version
         local running_lua_version = _VERSION:sub(5)

         if running_lua_version ~= user_lua_version then






            cfg.lua_version = running_lua_version
            cfg.lua_modules_path = cfg.lua_modules_path:gsub(user_lua_version:gsub("%.", "%%."), running_lua_version)
            cfg.lib_modules_path = cfg.lib_modules_path:gsub(user_lua_version:gsub("%.", "%%."), running_lua_version)
            cfg.rocks_subdir = cfg.rocks_subdir:gsub(user_lua_version:gsub("%.", "%%."), running_lua_version)
            path.use_tree(cfg.root_dir)
         end

         local _ok, err, errcode = deps.fulfill_dependencies(rockspec, "build_dependencies", "all", opts.verify, deplock_dir)

         path.add_to_package_paths(cfg.root_dir)

         if running_lua_version ~= user_lua_version then

            cfg.lua_version = user_lua_version
            cfg.lua_modules_path = cfg.lua_modules_path:gsub(running_lua_version:gsub("%.", "%%."), user_lua_version)
            cfg.lib_modules_path = cfg.lib_modules_path:gsub(running_lua_version:gsub("%.", "%%."), user_lua_version)
            cfg.rocks_subdir = cfg.rocks_subdir:gsub(running_lua_version:gsub("%.", "%%."), user_lua_version)
            path.use_tree(cfg.root_dir)
         end

         if err then
            return nil, err, errcode
         end
      end
   end

   return deps.fulfill_dependencies(rockspec, "dependencies", opts.deps_mode, opts.verify, deplock_dir)
end

local function fetch_and_change_to_source_dir(rockspec, opts)
   if opts.minimal_mode or opts.build_only_deps then
      return true
   end
   if opts.need_to_fetch then
      if opts.branch then
         rockspec.source.branch = opts.branch
      end
      local oks, source_dir, errcode = fetch.fetch_sources(rockspec, true)
      if not oks then
         return nil, source_dir, errcode
      end
      local ok, err
      ok, err = fs.change_dir(source_dir)
      if not ok then
         return nil, err
      end
   else
      if rockspec.source.file then
         local ok, err = fs.unpack_archive(rockspec.source.file)
         if not ok then
            return nil, err
         end
      end
      local ok, err = fetch.find_rockspec_source_dir(rockspec, ".")
      if not ok then
         return nil, err
      end
   end
   fs.change_dir(rockspec.source.dir)
   return true
end

local function prepare_install_dirs(name, version)
   local dirs = {
      lua = { name = path.lua_dir(name, version), is_module_path = true, perms = "read" },
      lib = { name = path.lib_dir(name, version), is_module_path = true, perms = "exec" },
      bin = { name = path.bin_dir(name, version), is_module_path = false, perms = "exec" },
      conf = { name = path.conf_dir(name, version), is_module_path = false, perms = "read" },
   }

   for _, d in pairs(dirs) do
      local ok, err = fs.make_dir(d.name)
      if not ok then
         return nil, err
      end
   end

   return dirs
end

local function run_build_driver(rockspec, no_install)
   local btype = rockspec.build.type
   if btype == "none" then
      return true
   end

   if btype == "module" then
      util.printout("Do not use 'module' as a build type. Use 'builtin' instead.")
      btype = "builtin"
      rockspec.build.type = btype
   end
   local driver
   if cfg.accepted_build_types and not fun.contains(cfg.accepted_build_types, btype) then
      return nil, "This rockspec uses the '" .. btype .. "' build type, which is blocked by the 'accepted_build_types' setting in your LuaRocks configuration."
   end
   local _pok, driver_str = pcall(require, "luarocks.build." .. btype)
   if not (type(driver_str) == "table") then
      return nil, "Failed initializing build back-end for build type '" .. btype .. "': " .. driver_str
   else
      driver = driver_str
   end

   if not driver.skip_lua_inc_lib_check then
      local ok, err, errcode = deps.check_lua_incdir(rockspec.variables)
      if not ok then
         return nil, err, errcode
      end

      if cfg.link_lua_explicitly then
         ok, err, errcode = deps.check_lua_libdir(rockspec.variables)
         if not ok then
            return nil, err, errcode
         end
      end
   end

   local ok, err = driver.run(rockspec, no_install)
   if not ok then
      return nil, "Build error: " .. err
   end
   return true
end

local install_files
do

















   local function install_to(files, location, is_module_path, perms)
      if not files then
         return true
      end
      for k, file in pairs(files) do
         local dest = location
         local filename = dir.base_name(file)
         if type(k) == "string" then
            local modname = k
            if is_module_path then
               dest = dir.path(location, path.module_to_path(modname))
               local ok, err = fs.make_dir(dest)
               if not ok then return nil, err end
               if filename:match("%.lua$") then
                  local basename = modname:match("([^.]+)$")
                  filename = basename .. ".lua"
               end
            else
               dest = dir.path(location, dir.dir_name(modname))
               local ok, err = fs.make_dir(dest)
               if not ok then return nil, err end
               filename = dir.base_name(modname)
            end
         else
            local ok, err = fs.make_dir(dest)
            if not ok then return nil, err end
         end
         local ok = fs.copy(file, dir.path(dest, filename), perms)
         if not ok then
            return nil, "Failed copying " .. file
         end
      end
      return true
   end

   local function install_default_docs(name, version)
      local patterns = { "readme", "license", "copying", ".*%.md" }
      local dest = dir.path(path.install_dir(name, version), "doc")
      local has_dir = false
      for file in fs.dir() do
         for _, pattern in ipairs(patterns) do
            if file:lower():match("^" .. pattern) then
               if not has_dir then
                  fs.make_dir(dest)
                  has_dir = true
               end
               fs.copy(file, dest, "read")
               break
            end
         end
      end
   end

   install_files = function(rockspec, dirs)
      local name, version = rockspec.name, rockspec.version

      if rockspec.build.install then
         for k, d in pairs(dirs) do
            local ok, err = install_to((rockspec.build.install)[k], d.name, d.is_module_path, d.perms)
            if not ok then return nil, err end
         end
      end

      local copy_directories = rockspec.build.copy_directories
      local copying_default = false
      if not copy_directories then
         copy_directories = { "doc" }
         copying_default = true
      end

      local any_docs = false
      for _, copy_dir in ipairs(copy_directories) do
         if fs.is_dir(copy_dir) then
            local dest = dir.path(path.install_dir(name, version), copy_dir)
            fs.make_dir(dest)
            fs.copy_contents(copy_dir, dest)
            any_docs = true
         else
            if not copying_default then
               return nil, "Directory '" .. copy_dir .. "' not found"
            end
         end
      end
      if not any_docs then
         install_default_docs(name, version)
      end

      return true
   end
end






function build.build_rockspec(rockspec, opts, cwd)

   cwd = cwd or dir.path(".")

   if not rockspec.build then
      if rockspec:format_is_at_least("3.0") then
         rockspec.build = {
            type = "builtin",
         }
      else
         return nil, "Rockspec error: build table not specified"
      end
   end

   if not rockspec.build.type then
      if rockspec:format_is_at_least("3.0") then
         rockspec.build.type = "builtin"
      else
         return nil, "Rockspec error: build type not specified"
      end
   end

   local ok, err = fetch_and_change_to_source_dir(rockspec, opts)
   if not ok then return nil, err end

   if opts.pin then
      deplocks.init(rockspec.name, ".")
   end

   ok, err = process_dependencies(rockspec, opts, cwd)
   if not ok then return nil, err end

   local name, version = rockspec.name, rockspec.version
   if opts.build_only_deps then
      if opts.pin then
         deplocks.write_file()
      end
      return name, version
   end

   local dirs
   local rollback
   if not opts.no_install then
      if repos.is_installed(name, version) then
         repo_writer.delete_version(name, version, opts.deps_mode)
      end

      dirs, err = prepare_install_dirs(name, version)
      if not dirs then return nil, err end

      rollback = util.schedule_function(function()
         fs.delete(path.install_dir(name, version))
         fs.remove_dir_if_empty(path.versions_dir(name))
      end)
   end

   ok, err = build.apply_patches(rockspec)
   if not ok then return nil, err end

   ok, err = check_macosx_deployment_target(rockspec)
   if not ok then return nil, err end

   ok, err = run_build_driver(rockspec, opts.no_install)
   if not ok then return nil, err end

   if opts.no_install then
      fs.pop_dir()
      if opts.need_to_fetch then
         fs.pop_dir()
      end
      return name, version
   end

   ok, err = install_files(rockspec, dirs)
   if not ok then return nil, err end

   for _, d in pairs(dirs) do
      fs.remove_dir_if_empty(d.name)
   end

   fs.pop_dir()
   if opts.need_to_fetch then
      fs.pop_dir()
   end

   if opts.pin then
      deplocks.write_file()
   end

   fs.copy(rockspec.local_abs_filename, path.rockspec_file(name, version), "read")

   local deplock_file = deplocks.get_abs_filename(name)
   if deplock_file then
      fs.copy(deplock_file, dir.path(path.install_dir(name, version), "luarocks.lock"), "read")
   end

   ok, err = repo_writer.deploy_files(name, version, repos.should_wrap_bin_scripts(rockspec), opts.deps_mode, opts.namespace)
   if not ok then return nil, err end

   util.remove_scheduled_function(rollback)
   rollback = util.schedule_function(function()
      repo_writer.delete_version(name, version, opts.deps_mode)
   end)

   ok, err = repos.run_hook(rockspec, "post_install")
   if not ok then return nil, err end

   util.announce_install(rockspec)
   util.remove_scheduled_function(rollback)
   return name, version
end

return build
