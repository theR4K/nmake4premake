--
-- Name: nmake2.lua
-- Purpose: action defenition for nmake project generator 
-- Author: Roman Masanin (36927roma@gmail.com)
-- based on gmake2 by Tom van Dijck, Aleksi Juvani, Vlad Ivanov
--

	local p = premake
	local project = p.project

	include("oldmsc.lua")
	include("nmake2_base.lua")
	
	p.modules.nmake2.cpp.initialize()

	newaction {
		trigger         = "nmake2",
		shortname       = "NMAKE",
		description     = "Microsoft Developer Studio NMAKE File",
		
		targetos = "windows",
		toolset  = "oldmsc-v420",
		
		valid_kinds     = { "ConsoleApp", "WindowedApp", "StaticLib", "SharedLib" },
		
		valid_languages = { "C", "C++" },
		
		valid_tools     = {
			cc     = { "msc" },
		},
		
		onWorkspace = function(wks)
			p.escaper(p.modules.nmake2.esc)
			wks.projects = table.filter(wks.projects, function(prj) return p.action.supports(prj.kind) and prj.kind ~= p.NONE end)
			p.generate(wks, "build.mak", p.modules.nmake2.generate_workspace)
		end,

		onProject = function(prj)
			p.escaper(p.modules.nmake2.esc)
			local makefile = ".mak"

			if not p.action.supports(prj.kind) or prj.kind == p.NONE then
				return
			elseif prj.kind == p.UTILITY then
				p.generate(prj, makefile, p.modules.nmake2.utility.generate)
			elseif prj.kind == p.MAKEFILE then
				p.generate(prj, makefile, p.modules.nmake2.makefile.generate)
			elseif project.isc(prj) or project.iscpp(prj) then
					p.generate(prj, makefile, p.modules.nmake2.cpp.generate)
			end
		end,

		onCleanWorkspace = function(wks)
			p.clean.file(wks, p.modules.nmake2.getmakefilename(wks, false))
		end,

		onCleanProject = function(prj)
			p.clean.file(prj, p.modules.nmake2.getmakefilename(prj, true))
		end
	}
