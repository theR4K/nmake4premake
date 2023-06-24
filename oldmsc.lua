--
-- Name: oldmsc.lua
-- Purpose: microsoft build tools v4.20 premake interface
-- Author: Roman Masanin (36927roma@gmail.com)
-- based on gmake2 by Jason Perkins, Manu Evans
--

	local p = premake

	p.tools.oldmsc = {}
	local oldmsc = p.tools.oldmsc
	local project = p.project
	local config = p.config

	premake.api.addAllowed("staticruntime", { "libc" })

--
-- Returns list of C preprocessor flags for a configuration.
--

	function oldmsc.getcppflags(cfg)
		return {}
	end


--
-- Returns list of C compiler flags for a configuration.
--

	local function getRuntimeFlag(cfg, flag)
		local rt = cfg.runtime
		if (rt == "Debug") or (rt == nil and config.isDebugBuild(cfg))  then
			flag = flag .. "d"
		end
		return flag
	end

	oldmsc.shared = {
		--clr = {
		--	On = "/clr",
		--	Unsafe = "/clr",
		--	Pure = "/clr:pure",
		--	Safe = "/clr:safe",
		--},
		flags = {
			FatalCompileWarnings = "/WX",
			--LinkTimeOptimization = "/GL",
			--MultiProcessorCompile = "/MP",
			NoMinimalRebuild = "/Gm-",
			OmitDefaultLibrary = "/Zl"
		},
		--floatingpoint = {
		--	Fast = "/fp:fast",
		--	Strict = "/fp:strict",
		--},
		--floatingpointexceptions = {
		--	On  = "/fp:except",
		--	Off = "/fp:except-",
		--},
		functionlevellinking = {
			On = "/Gy",
			--Off = "/Gy-",
		},
		callingconvention = {
			Cdecl = "/Gd",
			FastCall = "/Gr",
			StdCall = "/Gz",
			--VectorCall = "/Gv",
		},
		intrinsics = {
			On = "/Oi",
		},
		optimize = {
			Off = "/Od",
			On = "/Ot",
			Debug = "/Od",
			Full = "/Ox",
			Size = "/O1",
			Speed = "/O2",
		},
		--vectorextensions = {
		--	AVX = "/arch:AVX",
		--	AVX2 = "/arch:AVX2",
		--	SSE = "/arch:SSE",
		--	SSE2 = "/arch:SSE2",
		--	SSE3 = "/arch:SSE2",
		--	SSSE3 = "/arch:SSE2",
		--	["SSE4.1"] = "/arch:SSE2",
		--	["SSE4.2"] = "/arch:SSE2",
		--},
		warnings = {
			Off = "/w",
			High = "/W2",
			Extra = "/W3",
			Everything = "/W4",
		},
		--externalwarnings = {
		--	Off = "/external:W0",
		--	Default = "/external:W3",
		--	High = "/external:W4",
		--	Extra = "/external:W4",
		--	Everything = "/external:W4",
		--},
		--externalanglebrackets = {
		--	On = "/external:anglebrackets",
		--},
		staticruntime = {
			-- runtime defaults to dynamic in VS
			Default = function(cfg) return getRuntimeFlag(cfg, "/MD") end,
			On = function(cfg) return getRuntimeFlag(cfg, "/MT") end,
			Off = function(cfg) return getRuntimeFlag(cfg, "/MD") end,
			libc = function(cfg) return getRuntimeFlag(cfg, "/ML") end,
		},
		stringpooling = {
			On = "/GF",
			--Off = "/GF-",
		},
		symbols = {
			On = function(cfg) if cfg.debugformat == "c7" then return "/Z7" else return "/Zi" end end,
		},
		unsignedchar = {
			On = "/J",
		},
		omitframepointer = {
			On = "/Oy"
		},
		--justmycode = {
		--	On = "/JMC",
		--	Off = "/JMC-"
		--},
		--openmp = {
		--	On = "/openmp",
		--	Off = "/openmp-"
		--},
		--usestandardpreprocessor = {
		--	On = "/Zc:preprocessor",
		--	Off = "/Zc:preprocessor-"
		--}

	}

	oldmsc.cflags = {
	}

	function oldmsc.getcflags(cfg)
		local shared = config.mapFlags(cfg, oldmsc.shared)
		local cflags = config.mapFlags(cfg, oldmsc.cflags)
		local flags = table.join(shared, cflags, oldmsc.getwarnings(cfg))
		return flags
	end


--
-- Returns list of C++ compiler flags for a configuration.
--

	oldmsc.cxxflags = {
		exceptionhandling = {
			Default = "/GX",
			On = "/GX",
			--SEH = "/EHa",
		},
		rtti = {
			Off = "/GR-"
		},
		--sanitize = {
		--	Address = "/fsanitize=address",
		--	Fuzzer = "/fsanitize=fuzzer",
		--}
	}

	function oldmsc.getcxxflags(cfg)
		local shared = config.mapFlags(cfg, oldmsc.shared)
		local cxxflags = config.mapFlags(cfg, oldmsc.cxxflags)
		local flags = table.join(shared, cxxflags, oldmsc.getwarnings(cfg))
		
		return flags
	end


--
-- Decorate defines for the MSVC command line.
--

	oldmsc.defines = {
		characterset = {
			Default = { },
			MBCS = '/D"_MBCS"',
			Unicode = { '/D"_UNICODE"', '/D"UNICODE"' },
			ASCII = { },
		}
	}

	function oldmsc.getdefines(defines, cfg)
		local result

		-- HACK: I need the cfg to tell what the character set defines should be. But
		-- there's lots of legacy code using the old getdefines(defines) signature.
		-- For now, detect one or two arguments and apply the right behavior; will fix
		-- it properly when the I roll out the adapter overhaul
		if cfg and defines then
			result = config.mapFlags(cfg, oldmsc.defines)
		else
			result = {}
		end

		for _, define in ipairs(defines) do
			table.insert(result, '/D"' .. define .. '"')
		end

		if cfg and cfg.exceptionhandling == p.OFF then
			table.insert(result, '/D"_HAS_EXCEPTIONS=0"')
		end

		return result
	end

	function oldmsc.getundefines(undefines)
		local result = {}
		for _, undefine in ipairs(undefines) do
			table.insert(result, '/U"' .. undefine .. '"')
		end
		return result
	end


--
-- Returns a list of forced include files, decorated for the compiler
-- command line.
--
-- @param cfg
--    The project configuration.
-- @return
--    An array of force include files with the appropriate flags.
--

	function oldmsc.getforceincludes(cfg)
		local result = {}

		table.foreachi(cfg.forceincludes, function(value)
			local fn = project.getrelative(cfg.project, value)
			table.insert(result, "/FI" .. p.quoted(fn))
		end)

		return result
	end

	function oldmsc.getrunpathdirs()
		return {}
	end

--
-- Decorate include file search paths for the MSVC command line.
--

	function oldmsc.getincludedirs(cfg, dirs, extdirs, frameworkdirs, includedirsafter)
		local result = {}
		for _, dir in ipairs(dirs) do
			dir = project.getrelative(cfg.project, dir)
			dir = path.translate(dir)
			table.insert(result, '/I"' .. dir .. '"')
		end

		for _, dir in ipairs(extdirs or {}) do
			dir = project.getrelative(cfg.project, dir)
			dir = path.translate(dir)
			table.insert(result, '/I"' .. dir .. '"')
		end

		for _, dir in ipairs(includedirsafter or {}) do
			dir = project.getrelative(cfg.project, dir)
			dir = path.translate(dir)
			table.insert(result, '/I"' .. dir .. '"')
		end

		return result
	end


--
-- Return a list of linker flags for a specific configuration.
--

	oldmsc.linkerFlags = {
		flags = {
			FatalLinkWarnings = "/WX",
			LinkTimeOptimization = "/LTCG",
			NoIncrementalLink = function(cfg) if cfg.flags.NoIncrementalLink then return "/INCREMENTAL:NO" else return "/INCREMENTAL:YES" end end,
			NoManifest = "/MANIFEST:NO",
			OmitDefaultLibrary = "/NODEFAULTLIB",
		},
		kind = {
			SharedLib = "/DLL",
			WindowedApp = "/SUBSYSTEM:WINDOWS"
		},
		symbols = {
			On = "/DEBUG"
		}
	}

	oldmsc.librarianFlags = {
		flags = {
			FatalLinkWarnings = "/WX",
		}
	}

	function oldmsc.getldflags(cfg)
		local map = iif(cfg.kind ~= p.STATICLIB, oldmsc.linkerFlags, oldmsc.librarianFlags)
		local flags = config.mapFlags(cfg, map)

		if cfg.entrypoint then
			-- /ENTRY requires that /SUBSYSTEM is set.
			if cfg.kind == "ConsoleApp" then
				table.insert(flags, "/SUBSYSTEM:CONSOLE")
			elseif cfg.kind ~= "WindowedApp" then -- already set by above map
				table.insert(flags, "/SUBSYSTEM:NATIVE") -- fallback
			end
			table.insert(flags, '/ENTRY:' .. cfg.entrypoint)
		end

		table.insert(flags, 1, "/NOLOGO")

		-- Ignore default libraries
		for i, ignore in ipairs(cfg.ignoredefaultlibraries) do
			-- Add extension if required
			if not oldmsc.getLibraryExtensions()[ignore:match("[^.]+$")] then
				ignore = path.appendextension(ignore, ".lib")
			end
			table.insert(flags, '/NODEFAULTLIB:' .. ignore)
		end

		return flags
	end


--
-- Build a list of additional library directories for a particular
-- project configuration, decorated for the tool command line.
--
-- @param cfg
--    The project configuration.
-- @return
--    An array of decorated additional library directories.
--

	function oldmsc.getLibraryDirectories(cfg)
		local flags = {}
		local dirs = table.join(cfg.libdirs, cfg.syslibdirs)
		for i, dir in ipairs(dirs) do
			dir = project.getrelative(cfg.project, dir)
			table.insert(flags, '/LIBPATH:"' .. dir .. '"')
		end
		return flags
	end


--
-- Return a list of valid library extensions
--

	function oldmsc.getLibraryExtensions()
		return {
			["lib"] = true,
			["obj"] = true,
		}
	end

--
-- Return the list of libraries to link, decorated with flags as needed.
--

	function oldmsc.getlinks(cfg, systemonly, nogroups)
		local links = {}

		-- If we need sibling projects to be listed explicitly, grab them first
		if not systemonly then
			links = config.getlinks(cfg, "siblings", "fullpath")
		end

		-- Then the system libraries, which come undecorated
		local system = config.getlinks(cfg, "system", "fullpath")
		for i = 1, #system do
			-- Add extension if required
			local link = system[i]
			if not p.tools.oldmsc.getLibraryExtensions()[link:match("[^.]+$")] then
				link = path.appendextension(link, ".lib")
			end

			table.insert(links, link)
		end

		return links
	end

--
-- Returns makefile-specific configuration rules.
--

	function oldmsc.getmakesettings(cfg)
		return nil
	end


--
-- Retrieves the executable command name for a tool, based on the
-- provided configuration and the operating environment.
--
-- @param cfg
--    The configuration to query.
-- @param tool
--    The tool to fetch, one of "cc" for the C compiler, "cxx" for
--    the C++ compiler, or "ar" for the static linker.
-- @return
--    The executable command name for a tool, or nil if the system's
--    default value should be used.
--

	oldmsc.tools = {
		cc = "cl.exe",
		cxx = "cl.exe",
		link = "link.exe",
		rc = "rc.exe"
	}

	function oldmsc.gettoolname(cfg, tool)
		if oldmsc.tools[tool] then
			return oldmsc.tools[tool]
		end
		return nil
	end



	function oldmsc.getwarnings(cfg)
		local result = {}

		for _, enable in ipairs(cfg.enablewarnings) do
			table.insert(result, '/w1"' .. enable .. '"')
		end

		for _, disable in ipairs(cfg.disablewarnings) do
			table.insert(result, '/wd"' .. disable .. '"')
		end

		for _, fatal in ipairs(cfg.fatalwarnings) do
			table.insert(result, '/we"' .. fatal .. '"')
		end

		return result
	end
