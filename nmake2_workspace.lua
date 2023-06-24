--
-- Name: nmake2_workspace.lua
-- Purpose: generate build.mak for nmake project generator 
-- Author: Roman Masanin (36927roma@gmail.com)
-- based on gmake2 by Jason Perkins
--

	local p = premake
	local nmake2 = p.modules.nmake2

	local tree    = p.tree
	local project = p.project

	function nmake2.generate_workspace(wks)
		p.eol("\n")

		nmake2.header(wks)

		nmake2.configmap(wks)
		nmake2.projects(wks)

		nmake2.workspacePhonyRule(wks)
		nmake2.groupRules(wks)

		nmake2.projectrules(wks)
		nmake2.cleanrules(wks)
		nmake2.helprule(wks)
	end


--
-- Write out the workspace's configuration map, which maps workspace
-- level configurations to the project level equivalents.
--

	function nmake2.configmap(wks)
		local first = true
		for cfg in p.workspace.eachconfig(wks) do
			if first then
				p.w('!IF "$(CFG)" == "%s"', cfg.shortname)
				first = false
			else
				p.w('!ELSEIF "$(CFG)" == "%s"', cfg.shortname)
			end

			for prj in p.workspace.eachproject(wks) do
				local prjcfg = project.getconfig(prj, cfg.buildcfg, cfg.platform)
				if prjcfg then
					p.w('%s_CFG = %s', nmake2.tovar(prj.name):upper(), prjcfg.shortname)
				end
			end

			p.w('')
		end

		if not first then
			p.w('!ELSE')
			p.w('  $(error "invalid configuration $(CFG)")')
			p.w('!ENDIF')
			p.w('')
		end
	end


--
-- Write out the rules for the `make clean` action.
--

	function nmake2.cleanrules(wks)
		p.push('CLEAN:')
		for prj in p.workspace.eachproject(wks) do
			local prjpath = p.filename(prj, ".mak")
			local prjdir = path.getdirectory(path.getrelative(wks.location, prjpath))
			local prjname = path.getname(prjpath)
			
			for cfg in p.project.eachconfig(prj) do
				p.x('@$(MAKE) /NOLOGO /F %s CHDIR="%s" CFG="%s" CLEAN', prjname, prjdir, cfg.shortname)
			end
		end
		p.pop('')
	end


--
-- Write out the make file help rule and configurations list.
--

	function nmake2.helprule(wks)
		p.push('HELP:')
		p.w('-@echo "Usage: nmake.exe /f build.mak [GFG=name] [target]"')
		p.w('-@echo ""')
		p.w('-@echo "CONFIGURATIONS:"')

		for cfg in p.workspace.eachconfig(wks) do
			p.x('-@echo "  %s"', cfg.shortname)
		end

		p.w('-@echo ""')

		p.w('-@echo "TARGETS:"')
		p.w('-@echo "   all (default)"')
		p.w('-@echo "   clean"')

		for prj in p.workspace.eachproject(wks) do
			p.w('-@echo "   %s"', prj.name)
		end

		p.w('-@echo ""')
		p.pop('')
	end


--
-- Write out the list of projects that comprise the workspace.
--

	function nmake2.projects(wks)
		p.w('PROJECTS= %s', table.concat(p.esc(table.extract(wks.projects, "name")), " "))
		p.w('')
	end

--
-- Write out the workspace PHONY rule
--

	function nmake2.workspacePhonyRule(wks)
		p.w('MAKE=%s', 'nmake.exe')
		p.w('')
		p.w('ALL: $(PROJECTS)')
		p.w('')
	end

--
-- Write out the phony rules representing project groups
--
	function nmake2.groupRules(wks)
		-- Transform workspace groups into target aggregate
		local tr = p.workspace.grouptree(wks)
		tree.traverse(tr, {
			onbranch = function(n)
				local rule = p.esc(n.path) .. ":"
				local projectTargets = {}
				local groupTargets = {}
				for i, c in pairs(n.children)
				do
					if type(i) == "string"
					then
						if c.project
						then
							table.insert(projectTargets, c.name)
						else
							table.insert(groupTargets, c.path)
						end
					end
				end
				if #groupTargets > 0 then
					table.sort(groupTargets)
					rule = rule .. " " .. table.concat(groupTargets, " ")
				end
				if #projectTargets > 0 then
					table.sort(projectTargets)
					rule = rule .. " " .. table.concat(projectTargets, " ")
				end
				_p(rule)
				_p('')
			end
		})
	end

--
-- Write out the rules to build each of the workspace's projects.
--

	function nmake2.projectrules(wks)
		for prj in p.workspace.eachproject(wks) do
			local deps = project.getdependencies(prj)
			deps = table.extract(deps, "name")

			p.w('%s:%s', p.esc(prj.name):upper(), nmake2.list(p.esc(deps)))

			local cfgvar = nmake2.tovar(prj.name):upper()
			p.push('!IF "$(%s_CFG)" != ""', cfgvar)

			p.w('@echo "==== Building %s ($(%s_CFG)) ===="', prj.name, cfgvar)

			local prjpath = p.filename(prj, ".mak")
			local prjdir = path.getdirectory(path.getrelative(wks.location, prjpath))
			local prjname = path.getname(prjpath)

			p.x('@$(MAKE) /NOLOGO /F %s CHDIR="%s" CFG=$(%s_CFG) ALL', prjname, prjdir, cfgvar)

			p.pop('!ENDIF')
			p.w('')
		end
	end
