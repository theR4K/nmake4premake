--
-- Name: nmake2_cpp.lua
-- Purpose: generate project.mak for nmake project generator 
-- Author: Roman Masanin (36927roma@gmail.com)
-- based on gmake2 by Jason Perkins
--

	local p = premake
	local nmake2 = p.modules.nmake2

	nmake2.cpp       = {}
	local cpp        = nmake2.cpp

	local project    = p.project
	local config     = p.config
	local fileconfig = p.fileconfig


---
-- Add namespace for element definition lists for premake.callarray()
---

	cpp.elements = {}

	cpp.elements.makefile = function(prj)
		return {
			nmake2.header,
			nmake2.verboseRule,
			nmake2.chdirRule,
			nmake2.nullDefine,
			cpp.createRuleTable,
			cpp.outputConfigurationSection,
			cpp.targetCheck,
			cpp.outputPerFileConfigurationSection,
			cpp.createFileTable,
			cpp.outputFilesSection,
			cpp.outputRulesSection,
			cpp.outputFileRuleSection,
		}
	end


	function cpp.generate(prj)
		p.eol("\n")
		p.callArray(cpp.elements.makefile, prj)

		-- allow the garbage collector to clean things up.
		for cfg in project.eachconfig(prj) do
			cfg._nmake2 = nil
		end
		prj._nmake2 = nil
	end


	function cpp.initialize()
		rule 'cpp'
			fileExtension { ".cc", ".cpp", ".cxx", ".mm" }
			buildoutputs  { "$(OBJDIR)\\%{file.objname}.obj" }
			buildmessage  'compiling $(OBJDIR)\\%{file.objname}.obj'
			buildcommands {'$(CXX) /nologo %{premake.modules.nmake2.cpp.fileFlags(cfg, file)} $(FORCE_INCLUDE) /Fo"$(OBJDIR)/" /c'}

		rule 'cc'
			fileExtension {".c", ".s", ".m"}
			buildoutputs  { "$(OBJDIR)\\%{file.objname}.obj" }
			buildmessage  '$@'
			buildcommands {'$(CC) %{premake.modules.nmake2.cpp.fileFlags(cfg, file)} $(FORCE_INCLUDE) -c'}

		rule 'resource'
			fileExtension ".rc"
			buildoutputs  { "$(OBJDIR)\\%{file.objname}.res" }
			buildmessage  'assembling resource $(OBJDIR)\\%{file.objname}.res'
			buildcommands {'$(RESCOMP) /Fo"$(OBJDIR)\\%{file.objname}.res" $(ALL_RESFLAGS)'}

		global(nil)
	end
	
	function cpp.targetCheck(prj)
		p.w('!IF "$(TARGET)" == ""')
		p.w('!ERROR An invalid configuration is specified.')
		p.w('!ENDIF')
		p.w('')
	end

	function cpp.createRuleTable(prj)
		local rules = {}

		local function addRule(extension, rule)
			if type(extension) == 'table' then
				for _, value in ipairs(extension) do
					addRule(value, rule)
				end
			else
				rules[extension] = rule
			end
		end

		-- add all rules.
		local usedRules = table.join({'cpp', 'cc', 'resource'}, prj.rules)
		for _, name in ipairs(usedRules) do
			local rule = p.global.getRule(name)
			addRule(rule.fileExtension, rule)
		end

		-- create fileset categories.
		local filesets = {
			['.o']   = 'OBJECTS',
			['.obj'] = 'OBJECTS',
			['.cc']  = 'SOURCES',
			['.cpp'] = 'SOURCES',
			['.cxx'] = 'SOURCES',
			['.mm']  = 'SOURCES',
			['.c']   = 'SOURCES',
			['.s']   = 'SOURCES',
			['.m']   = 'SOURCES',
			['.rc']  = 'RESOURCES',
			['.res']  = 'RESOURCES',
		}

		-- cache the result.
		prj._nmake2 = prj._nmake2 or {}
		prj._nmake2.rules = rules
		prj._nmake2.filesets = filesets
	end


	function cpp.createFileTable(prj)
		for cfg in project.eachconfig(prj) do
			cfg._nmake2 = cfg._nmake2 or {}
			cfg._nmake2.filesets = {}
			cfg._nmake2.fileRules = {}

			local files = table.shallowcopy(prj._.files)
			table.foreachi(files, function(node)
				cpp.addFile(cfg, node)
			end)

			for _, f in pairs(cfg._nmake2.filesets) do
				table.sort(f)
			end

			cfg._nmake2.kinds = table.keys(cfg._nmake2.filesets)
			table.sort(cfg._nmake2.kinds)

			prj._nmake2.kinds = table.join(prj._nmake2.kinds or {}, cfg._nmake2.kinds)
		end

		-- we need to reassign object sequences if we generated any files.
		if prj.hasGeneratedFiles and p.project.iscpp(prj) then
			p.oven.assignObjectSequences(prj)
		end

		prj._nmake2.kinds = table.unique(prj._nmake2.kinds)
		table.sort(prj._nmake2.kinds)
	end


	function cpp.addFile(cfg, node)
		local filecfg = fileconfig.getconfig(node, cfg)
		if not filecfg or filecfg.flags.ExcludeFromBuild then
			return
		end

		-- skip generated files, since we try to figure it out manually below.
		if node.generated then
			return
		end

		-- process custom build commands.
		if fileconfig.hasCustomBuildRule(filecfg) then
			local env = table.shallowcopy(filecfg.environ)
			env.PathVars = {
				["file.basename"]     = { absolute = false, token = node.basename },
				["file.abspath"]      = { absolute = true,  token = node.abspath },
				["file.relpath"]      = { absolute = false, token = node.relpath },
				["file.name"]         = { absolute = false, token = node.name },
				["file.objname"]      = { absolute = false, token = node.objname },
				["file.path"]         = { absolute = true,  token = node.path },
				["file.directory"]    = { absolute = true,  token = path.getdirectory(node.abspath) },
				["file.reldirectory"] = { absolute = false, token = path.getdirectory(node.relpath) },
			}

			local shadowContext = p.context.extent(filecfg, env)

			local buildoutputs = p.project.getrelative(cfg.project, shadowContext.buildoutputs)
			if buildoutputs and #buildoutputs > 0 then
				local file = {
					buildoutputs  = buildoutputs,
					source        = node.relpath,
					buildmessage  = shadowContext.buildmessage,
					buildcommands = shadowContext.buildcommands,
					buildinputs   = p.project.getrelative(cfg.project, shadowContext.buildinputs)
				}
				table.insert(cfg._nmake2.fileRules, file)

				for _, output in ipairs(buildoutputs) do
					cpp.addGeneratedFile(cfg, node, output)
				end
			end
		else
			cpp.addRuleFile(cfg, node)
		end
	end

	function cpp.determineFiletype(cfg, node)
		-- determine which filetype to use
		local filecfg = fileconfig.getconfig(node, cfg)
		local fileext = path.getextension(node.abspath):lower()
		if filecfg and filecfg.compileas then
			if p.languages.isc(filecfg.compileas) then
				fileext = ".c"
			elseif p.languages.iscpp(filecfg.compileas) then
				fileext = ".cpp"
			end
		end

		return fileext;
	end

	function cpp.addGeneratedFile(cfg, source, filename)
		-- mark that we have generated files.
		cfg.project.hasGeneratedFiles = true

		-- add generated file to the project.
		local files = cfg.project._.files
		local node = files[filename]
		if not node then
			node = fileconfig.new(filename, cfg.project)
			files[filename] = node
			table.insert(files, node)
		end

		-- always overwrite the dependency information.
		node.dependsOn = source
		node.generated = true

		-- add to config if not already added.
		if not fileconfig.getconfig(node, cfg) then
			fileconfig.addconfig(node, cfg)
		end

		-- determine which filetype to use
		local fileext = cpp.determineFiletype(cfg, node)
		-- add file to the fileset.
		local filesets = cfg.project._nmake2.filesets
		local kind     = filesets[fileext] or "CUSTOM"

		-- don't link generated object files automatically if it's explicitly
		-- disabled.
		if path.isobjectfile(filename) and source.linkbuildoutputs == false then
			kind = "CUSTOM"
		end

		local fileset = cfg._nmake2.filesets[kind] or {}
		table.insert(fileset, filename)
		cfg._nmake2.filesets[kind] = fileset

		local generatedKind = "GENERATED"
		local generatedFileset = cfg._nmake2.filesets[generatedKind] or {}
		table.insert(generatedFileset, filename)
		cfg._nmake2.filesets[generatedKind] = generatedFileset

		-- recursively setup rules.
		cpp.addRuleFile(cfg, node)
	end

	function cpp.addRuleFile(cfg, node)
		local rules = cfg.project._nmake2.rules
		local fileext = cpp.determineFiletype(cfg, node)
		local rule = rules[fileext]
		if rule then

			local filecfg = fileconfig.getconfig(node, cfg)
			local environ = table.shallowcopy(filecfg.environ)
			
			if rule.propertydefinition then
				p.rule.prepareEnvironment(rule, environ, cfg)
				p.rule.prepareEnvironment(rule, environ, filecfg)
			end

			local shadowContext = p.context.extent(rule, environ)

			local buildoutputs  = shadowContext.buildoutputs
			local buildmessage  = shadowContext.buildmessage
			local buildcommands = shadowContext.buildcommands
			local buildinputs   = shadowContext.buildinputs
			
			buildoutputs = p.project.getrelative(cfg.project, buildoutputs)
			if buildoutputs and #buildoutputs > 0 then
				local file = {
					buildoutputs  = buildoutputs,
					source        = node.relpath,
					buildmessage  = buildmessage,
					buildcommands = buildcommands,
					buildinputs   = buildinputs
				}
				table.insert(cfg._nmake2.fileRules, file)

				for _, output in ipairs(buildoutputs) do
					cpp.addGeneratedFile(cfg, node, output)
				end
			end
		end
	end


--
-- Write out the settings for a particular configuration.
--

	cpp.elements.configuration = function(cfg)
		return {
			cpp.tools,
			nmake2.target,
			nmake2.objdir,
			cpp.defines,
			cpp.includes,
			cpp.forceInclude,
			cpp.cppFlags,
			cpp.cFlags,
			cpp.cxxFlags,
			cpp.resFlags,
			cpp.libs,
			cpp.ldDeps,
			cpp.ldFlags,
			cpp.linkCmd,
			cpp.bindirs,
			cpp.exepaths,
			nmake2.settings,
			nmake2.preBuildCmds,
			nmake2.preLinkCmds,
			nmake2.postBuildCmds,
		}
	end


	function cpp.outputConfigurationSection(prj)
		_p('# Configurations')
		_p('# #############################################')
		_p('')
		nmake2.outputSection(prj, cpp.elements.configuration)
	end


	function cpp.tools(cfg, toolset)
		local tool = toolset.gettoolname(cfg, "cc")
		if tool then
			p.w('CC=%s', tool)
		end
		
		tool = toolset.gettoolname(cfg, "cxx")
		if tool then
			p.w('CXX=%s', tool)
		end
		
		tool = toolset.gettoolname(cfg, "link")
		if tool then
			p.w('LINK=%s', tool)
		end
		
		tool = toolset.gettoolname(cfg, "rc")
		if tool then
			p.w('RESCOMP=%s', tool)
		end
	end

	function cpp.defines(cfg, toolset)
		p.outln('DEFINES=$(DEFINES) ' .. nmake2.list(table.join(toolset.getdefines(cfg.defines, cfg), toolset.getundefines(cfg.undefines))))
	end


	function cpp.includes(cfg, toolset)
		local includes = toolset.getincludedirs(cfg, cfg.includedirs, cfg.externalincludedirs, cfg.frameworkdirs, cfg.includedirsafter)
		p.outln('INCLUDES=$(INCLUDES) ' .. nmake2.list(includes))
	end


	function cpp.forceInclude(cfg, toolset)
		local includes = toolset.getforceincludes(cfg)
		p.outln('FORCE_INCLUDE=$(FORCE_INCLUDE) ' .. nmake2.list(includes))
	end


	function cpp.cppFlags(cfg, toolset)
		local flags = nmake2.list(toolset.getcppflags(cfg))
		p.outln('ALL_CPPFLAGS=$(ALL_CPPFLAGS) $(CPPFLAGS)' .. flags .. ' $(DEFINES) $(INCLUDES)')
	end


	function cpp.cFlags(cfg, toolset)
		local flags = nmake2.list(table.join(toolset.getcflags(cfg), cfg.buildoptions))
		p.outln('ALL_CFLAGS=$(ALL_CFLAGS) $(CFLAGS) $(ALL_CPPFLAGS)' .. flags)
	end


	function cpp.cxxFlags(cfg, toolset)
		local flags = nmake2.list(table.join(toolset.getcxxflags(cfg), cfg.buildoptions))
		p.outln('ALL_CXXFLAGS=$(ALL_CXXFLAGS) $(CXXFLAGS) $(ALL_CPPFLAGS)' .. flags)
	end


	function cpp.resFlags(cfg, toolset)
		local resflags = table.join(toolset.getdefines(cfg.resdefines), toolset.getincludedirs(cfg, cfg.resincludedirs), cfg.resoptions)
		p.outln('ALL_RESFLAGS=$(ALL_RESFLAGS) $(RESFLAGS) $(DEFINES) $(INCLUDES)' .. nmake2.list(resflags))
	end


	function cpp.libs(cfg, toolset)
		local flags = toolset.getlinks(cfg)
		p.outln('LIBS=$(LIBS)' .. nmake2.list(flags, true))
	end


	function cpp.ldDeps(cfg, toolset)
		local deps = config.getlinks(cfg, "siblings", "fullpath")
		p.outln('LDDEPS=$(LDDEPS)' .. nmake2.list(p.esc(deps)))
	end


	function cpp.ldFlags(cfg, toolset)
		local flags = table.join(toolset.getLibraryDirectories(cfg), toolset.getrunpathdirs(cfg, table.join(cfg.runpathdirs, config.getsiblingtargetdirs(cfg))), toolset.getldflags(cfg), cfg.linkoptions)
		p.outln('ALL_LDFLAGS=$(ALL_LDFLAGS) $(LDFLAGS)' .. nmake2.list(flags))
	end

	cpp.linkMacineNames = {
		x86 = "I386",
	}
	
	function cpp.linkMacineName(cfg)
		if cpp.linkMacineNames[cfg.architecture] then
			return cpp.linkMacineNames[cfg.architecture]
		end
		return nil
	end

	function cpp.linkCmd(cfg, toolset)
		local percfgflags = '/out:"$(TARGET)"'
		
		if cfg.symbols ==p.ON then
			if cfg.symbolspath then
				percfgflags = percfgflags .. " /pdb:" .. p.quote(cfg.symbolspath)
			else
				percfgflags = percfgflags .. ' /pdb:"$(TARGETDIR)\\' .. path.getbasename(cfg.buildtarget.name) .. '.pdb"'
			end
		end
		
		if cfg.kind == "SharedLib" then
			percfgflags = percfgflags .. ' /implib:"$(TARGETDIR)\\' .. path.getbasename(cfg.buildtarget.name) .. '.lib"'
		end
		
		if cpp.linkMacineName(cfg) then
			percfgflags = percfgflags .. " /machine:" .. cpp.linkMacineName(cfg)
		end
		
		p.w('LINKCMD=$(OBJECTS) $(RESOURCES) $(ALL_LDFLAGS) %s $(LIBS)', percfgflags)
	end


	function cpp.bindirs(cfg, toolset)
		local dirs = project.getrelative(cfg.project, cfg.bindirs)
		if #dirs > 0 then
			p.outln('EXECUTABLE_PATHS = "' .. table.concat(dirs, ":") .. '"')
		end
	end


	function cpp.exepaths(cfg, toolset)
		local dirs = project.getrelative(cfg.project, cfg.bindirs)
		if #dirs > 0 then
			p.outln('EXE_PATHS = export PATH=$(EXECUTABLE_PATHS):$$PATH;')
		end
	end


--
-- Write out the per file configurations.
--
	function cpp.outputPerFileConfigurationSection(prj)
		_p('# Per File Configurations')
		_p('# #############################################')
		_p('')
		for cfg in project.eachconfig(prj) do
			table.foreachi(prj._.files, function(node)
				local fcfg = fileconfig.getconfig(node, cfg)
				if fcfg then
					cpp.perFileFlags(cfg, fcfg)
				end
			end)
		end
		_p('')
	end

	function cpp.makeVarName(prj, value, saltValue)
		prj._nmake2 = prj._nmake2 or {}
		prj._nmake2.varlist = prj._nmake2.varlist or {}
		prj._nmake2.varlistlength = prj._nmake2.varlistlength or 0
		local cache = prj._nmake2.varlist
		local length = prj._nmake2.varlistlength

		local key = value .. saltValue

		if (cache[key] ~= nil) then
			return cache[key], false
		end

		local var = string.format("PERFILE_FLAGS_%d", length)
		cache[key] = var

		prj._nmake2.varlistlength = length + 1

		return var, true
	end

	function cpp.perFileFlags(cfg, fcfg)
		local toolset = nmake2.getToolSet(cfg)

		local isCFile = path.iscfile(fcfg.name)

		local getflags = iif(isCFile, toolset.getcflags, toolset.getcxxflags)
		local value = nmake2.list(table.join(getflags(fcfg), fcfg.buildoptions))

		if fcfg.defines or fcfg.undefines then
			local defs = table.join(toolset.getdefines(fcfg.defines, cfg), toolset.getundefines(fcfg.undefines))
			if #defs > 0 then
				value = value .. nmake2.list(defs)
			end
		end

		if fcfg.includedirs or fcfg.externalincludedirs or fcfg.frameworkdirs then
			local includes = toolset.getincludedirs(cfg, fcfg.includedirs, fcfg.externalincludedirs, fcfg.frameworkdirs)
			if #includes > 0 then
				value = value ..  nmake2.list(includes)
			end
		end

		if #value > 0 then
			local newPerFileFlag = false
			fcfg.flagsVariable, newPerFileFlag = cpp.makeVarName(cfg.project, value, iif(isCFile, '_C', '_CPP'))
			if newPerFileFlag then
				if isCFile then
					_p('%s = $(ALL_CFLAGS)%s', fcfg.flagsVariable, value)
				else
					_p('%s = $(ALL_CXXFLAGS)%s', fcfg.flagsVariable, value)
				end
			end
		end
	end

	function cpp.fileFlags(cfg, file)
		local fcfg = fileconfig.getconfig(file, cfg)
		local flags = {}
		
		-- make dummy object to simplify next code
		if not fcfg then
			fcfg = {}
			fcfg.flag = {}
		end

		if not cfg.flags.NoPCH and not fcfg.flags.NoPCH then
			if cfg.pchheader then
				table.insert(flags, '/Fp"' .. path.translate(cfg.pchheader) .. '"')
			else
				table.insert(flags, '/YX /Fp"$(OBJDIR)\\' .. cfg.project.name .. '.pch"')
			end			
		end
		
		if cfg.symbols == p.ON then
			table.insert(flags, '/Fd"$(OBJDIR)/"')
		end

		if fcfg.flagsVariable then
			table.insert(flags, string.format("$(%s)", fcfg.flagsVariable))
		else
			local fileExt = cpp.determineFiletype(cfg, file)

			if path.iscfile(fileExt) then
				table.insert(flags, "$(ALL_CFLAGS)")
			elseif path.iscppfile(fileExt) then
				table.insert(flags, "$(ALL_CXXFLAGS)")
			end
		end

		return table.concat(flags, ' ')
	end

--
-- Write out the file sets.
--

	cpp.elements.filesets = function(cfg)
		local result = {}
		for _, kind in ipairs(cfg._nmake2.kinds) do
			--table.insert(result, function(cfg, toolset) p.push() end)
			for _, f in ipairs(cfg._nmake2.filesets[kind]) do
				table.insert(result, function(cfg, toolset) p.w('%s=$(%s) "%s"', kind, kind, path.translate(f)) end)
			end
			--table.insert(result, function(cfg, toolset) p.pop() end)
		end
		return result
	end

	function cpp.outputFilesSection(prj)
		p.w('# File sets')
		p.w('# #############################################')
		p.w('')

		for _, kind in ipairs(prj._nmake2.kinds) do
			p.x('%s=', kind)
		end
		p.x('')

		nmake2.outputSection(prj, cpp.elements.filesets)
	end

--
-- Write out the targets.
--

	cpp.elements.rules = function(cfg)
		return {
			cpp.allRules,
			cpp.targetRules,
			nmake2.targetDirRules,
			nmake2.objDirRules,
			cpp.cleanRules,
			nmake2.preBuildRules,
			cpp.customDeps,
		}
	end


	function cpp.outputRulesSection(prj)
		p.w('# Rules')
		p.w('# #############################################')
		p.w('')
		nmake2.outputSection(prj, cpp.elements.rules)
	end


	function cpp.allRules(cfg, toolset)
		p.w('ALL: $(TARGET)')
		p.w('')
		p.w('$(OBJECTS): PREBUILD')
		p.w('')
	end


	function cpp.targetRules(cfg, toolset)
		local targets = ''

		for _, kind in ipairs(cfg._nmake2.kinds) do
			if kind ~= 'OBJECTS' and kind ~= 'RESOURCES' then
				targets = targets .. '$(' .. kind .. ') '
			end
		end

		targets = targets .. '$(OBJECTS) $(LDDEPS)'
		if cfg._nmake2.filesets['RESOURCES'] then
			targets = targets .. ' $(RESOURCES)'
		end

		p.push('$(TARGET): $(TARGETDIR) %s', targets)
		p.w('$(PRELINKCMDS)')
		p.w('@echo Linking %s', cfg.project.name)
		p.w('$(SILENT) $(LINK) @<<')
		-- due specification << must be at position 0
		p.pop('$(LINKCMD)')
		p.push('<<')
		p.w('$(POSTBUILDCMDS)')
		p.pop('')
	end


	function cpp.customDeps(cfg, toolset)
		for _, kind in ipairs(cfg._nmake2.kinds) do
			if kind == 'CUSTOM' or kind == 'SOURCES' then
				p.w('$(%s): PREBUILD', kind)
			end
		end
	end


	function cpp.cleanRules(cfg, toolset)
		p.push('CLEAN: CHDIR')
		p.w('-@echo Cleaning %s $(CFG)', cfg.project.name)
		p.w('-$(SILENT) erase /q $(GENERATED) "$(TARGET)" $(IGNOREERROR)')
		p.w('-$(SILENT) rmdir /q "$(TARGETDIR)" $(TARGETDIRHIRARCHY) $(IGNOREERROR)')
		p.w('-$(SILENT) rmdir /q "$(OBJDIR)" $(OBJDIRHIRARCHY) $(IGNOREERROR)')
		p.pop('')
	end

--
-- Output the file compile targets.
--

	cpp.elements.fileRules = function(cfg)
		local funcs = {}
		for _, fileRule in ipairs(cfg._nmake2.fileRules) do
			table.insert(funcs, function(cfg, toolset)
				cpp.outputFileRules(cfg, fileRule)
			end)
		end
		return funcs
	end


	function cpp.outputFileRuleSection(prj)
		p.w('# File Rules')
		p.w('# #############################################')
		p.w('')
		nmake2.outputSection(prj, cpp.elements.fileRules)
	end


	function cpp.outputFileRules(cfg, file)
		local dependencies = path.translate(file.source)
		if file.buildinputs and #file.buildinputs > 0 then
			dependencies = dependencies .. " " ..  table.concat(file.buildinputs, " ")
		end

		p.push('%s: %s', path.translate(file.buildoutputs[1]), dependencies)

		if file.buildmessage then
			p.w('-@echo "%s"', file.buildmessage)
		end

		if file.buildcommands then
			local cmds = os.translateCommandsAndPaths(file.buildcommands, cfg.project.basedir, cfg.project.location)
			for _, cmd in ipairs(cmds) do
				if cfg.bindirs and #cfg.bindirs > 0 then
					p.w('$(SILENT) $(EXE_PATHS) %s %s', cmd, path.translate(file.source))
				else
					p.w('$(SILENT) %s "%s"', cmd, path.translate(file.source))
				end
			end
		end

		-- TODO: this is a hack with some imperfect side-effects.
		--       better solution would be to emit a dummy file for the rule, and then outputs depend on it (must clean up dummy in 'clean')
		--       better yet, is to use pattern rules, but we need to detect that all outputs have the same stem
		if #file.buildoutputs > 1 then
			p.w('%s: %s', table.concat({ table.unpack(file.buildoutputs, 2) }, ' '), file.buildoutputs[1])
		end
		
		p.pop()
	end
