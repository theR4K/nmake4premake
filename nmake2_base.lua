--
-- Name: nmake2_base.lua
-- Purpose: utilities set for nmake project generator 
-- Author: Roman Masanin (36927roma@gmail.com)
-- based on gmake2 by Jason Perkins
--

	local p       = premake
	local project = p.project

	p.modules.nmake2 = {}
	p.modules.nmake2._VERSION = p._VERSION
	local nmake2 = p.modules.nmake2

--
-- Write out the default configuration rule for a workspace or project.
--
-- @param target
--    The workspace or project object for which a makefile is being generated.
--

	function nmake2.defaultconfig(target)
		-- find the right configuration iterator function for this object
		local eachconfig = iif(target.project, project.eachconfig, p.workspace.eachconfig)
		local defaultconfig = nil

		-- find the right default configuration platform, grab first configuration that matches
		if target.defaultplatform then
			for cfg in eachconfig(target) do
				if cfg.platform == target.defaultplatform then
					defaultconfig = cfg
					break
				end
			end
		end

		-- grab the first configuration and write the block
		if not defaultconfig then
			local iter = eachconfig(target)
			defaultconfig = iter()
		end

		if defaultconfig then
			p.w('!IF "$(CFG)" == ""')
			p.w('CFG=%s', defaultconfig.shortname)
			p.w('!ENDIF')
			p.w('')
		end
	end


---
-- Escape a string so it can be written to a makefile.
---

	function nmake2.esc(value)
		result = value:gsub("\\", "\\\\")
		result = result:gsub("\"", "\\\"")
		result = result:gsub(" ", "\\ ")
		result = result:gsub("%(", "\\(")
		result = result:gsub("%)", "\\)")

		-- leave $(...) shell replacement sequences alone
		result = result:gsub("$\\%((.-)\\%)", "$(%1)")
		return result
	end

--
-- Output a makefile header.
--
-- @param target
--    The workspace or project object for which the makefile is being generated.
--

	function nmake2.header(target)
		local kind = iif(target.project, "project", "workspace")

		p.w('# %s %s makefile autogenerated by Premake', p.action.current().shortname, kind)
		p.w('')

		nmake2.defaultconfig(target)
	end
	
	function nmake2.verboseRule(prj)
		p.w('!IF "$(VERBOSE)" == "1"')
		p.w('SILENT=')
		p.w('IGNOREERROR=')
		p.w('!ELSE')
		p.w('SILENT=@')
		p.w('IGNOREERROR=2> nul')
		p.w('!ENDIF')
		p.w('')
	end
	
	function nmake2.chdirRule(prj)
		p.w('CHDIR:')
		p.push('!IF "$(CHDIR)" != ""')
		p.w('@cd "$(CHDIR)"')
		p.pop('!ENDIF')
		p.w('')
	end
	
	function nmake2.nullDefine(prj)

	end


--
-- Rules for file ops based on the shell type. Can't use defines and $@ because
-- it screws up the escaping of spaces and parenthesis (anyone know a fix?)
--

	function nmake2.mkdir(dirname)
		p.w('@if not exist "%s" mkdir "%s"', dirname, dirname)
	end

	function nmake2.mkdirRules(dirname)
		p.push('"%s": CHDIR', dirname)
		p.w('-@echo Creating %s', dirname)
		nmake2.mkdir(dirname)
		p.pop('')
	end

--
-- Format a list of values to be safely written as part of a variable assignment.
--

	function nmake2.list(value, quoted)
		quoted = false
		if #value > 0 then
			if quoted then
				local result = ""
				for _, v in ipairs (value) do
					if #result then
						result = result .. " "
					end
					result = result .. p.quoted(v)
				end
				return result
			else
				return " " .. table.concat(value, " ")
			end
		else
			return ""
		end
	end


--
-- Convert an arbitrary string (project name) to a make variable name.
--

	function nmake2.tovar(value)
		value = value:gsub("[ -]", "_")
		value = value:gsub("[()]", "")
		return value
	end

	function nmake2.getToolSet(cfg)
		local toolset = p.config.toolset(cfg)
		if not toolset then
			error("Invalid toolset '" .. cfg.toolset .. "'")
		end
		return toolset
	end


	function nmake2.outputSection(prj, callback)
		local root = {}

		for cfg in project.eachconfig(prj) do
			-- identify the toolset used by this configurations (would be nicer if
			-- this were computed and stored with the configuration up front)

			local toolset = nmake2.getToolSet(cfg)

			local settings = {}
			local funcs = callback(cfg)
			for i = 1, #funcs do
				local c = p.capture(function ()
					funcs[i](cfg, toolset)
				end)
				if #c > 0 then
					table.insert(settings, c)
				end
			end

			if not root.settings then
				root.settings = table.arraycopy(settings)
			else
				root.settings = table.intersect(root.settings, settings)
			end

			root[cfg] = settings
		end

		if #root.settings > 0 then
			for _, v in ipairs(root.settings) do
				p.w(v)
			end
			p.w('')
		end

		local first = true
		for cfg in project.eachconfig(prj) do
			local settings = table.difference(root[cfg], root.settings)
			if #settings > 0 then
				if first then
					p.x('!IF  "$(CFG)" == "%s"', cfg.shortname)
					first = false
				else
					p.x('!ELSEIF  "$(CFG)" == "%s"', cfg.shortname)
				end

				for k, v in ipairs(settings) do
					p.w(v)
				end

				p.w('')
			end
		end

		if not first then
			p.w('!ENDIF')
			p.w('')
		end
	end


	-- convert a rule property into a string

---------------------------------------------------------------------------
--
-- Handlers for the individual makefile elements that can be shared
-- between the different language projects.
--
---------------------------------------------------------------------------

	function nmake2.target(cfg, toolset)
		local targetpath = project.getrelative(cfg.project, cfg.buildtarget.directory)
		p.outln('TARGETDIR=' .. path.translate(targetpath))
		p.outln('TARGET=$(TARGETDIR)\\' .. path.translate(cfg.buildtarget.name))	
		
		local targeth = 'TARGETDIRHIRARCHY='
		targetpath = path.normalize(targetpath .. "/../")
		while string.find(targetpath, "[^\\.\\/]") do
			targeth = targeth .. ' "' .. path.translate(targetpath) .. '"'
			targetpath = path.normalize(targetpath .. "/../")
		end
		p.w(targeth)
	end


	function nmake2.objdir(cfg, toolset)
		local objpath = project.getrelative(cfg.project, cfg.objdir)		
		p.w('OBJDIR=%s', path.translate(objpath))

		local objh = 'OBJDIRHIRARCHY='
		objpath = path.normalize(objpath .. "/../")
		while string.find(objpath, "[^\\.\\/]") do
			objh = objh .. ' "' .. path.translate(objpath) .. '"'
			objpath = path.normalize(objpath .. "/../")
		end
		p.w(objh)
	end


	function nmake2.settings(cfg, toolset)
		if #cfg.makesettings > 0 then
			for _, value in ipairs(cfg.makesettings) do
				p.outln(value)
			end
		end

		local value = toolset.getmakesettings(cfg)
		if value then
			p.outln(value)
		end
	end


	function nmake2.buildCmds(cfg, event)
		p.push('%sCMDS: ', event:upper())
		local steps = cfg[event .. "commands"]
		local msg = cfg[event .. "message"]
		if #steps > 0 then
			steps = os.translateCommandsAndPaths(steps, cfg.project.basedir, cfg.project.location)
			msg = msg or string.format("Running %s commands", event)
			p.w('\t@echo %s', msg)
			p.w('\t%s', table.implode(steps, "", "", "\n\t"))
		end
		p.pop('')
	end


	function nmake2.preBuildCmds(cfg, toolset)
		nmake2.buildCmds(cfg, "prebuild")
	end


	function nmake2.preLinkCmds(cfg, toolset)
		nmake2.buildCmds(cfg, "prelink")
	end


	function nmake2.postBuildCmds(cfg, toolset)
		nmake2.buildCmds(cfg, "postbuild")
	end


	function nmake2.targetDirRules(cfg, toolset)
		nmake2.mkdirRules("$(TARGETDIR)")
	end

	function nmake2.objDirRules(cfg, toolset)
		nmake2.mkdirRules("$(OBJDIR)")
	end


	function nmake2.preBuildRules(cfg, toolset)
		p.w('PREBUILD: $(OBJDIR) PREBUILDCMDS')
		p.w('')
	end



	include("nmake2_cpp.lua")
	include("nmake2_workspace.lua")
