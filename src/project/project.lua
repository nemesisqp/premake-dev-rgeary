--
-- src/project/project.lua
-- Premake project object API
-- Copyright (c) 2011-2012 Jason Perkins and the Premake project
--

	local project = premake5.project
	local oven = premake5.oven
	local targets = premake5.targets
	local keyedblocks = premake.keyedblocks
	local config = premake5.config
	local solution = premake.solution
		
--
-- Flatten out a project and all of its configurations, merging all of the
-- values contained in the script-supplied configuration blocks.
--   project.bake must be recursive, as if A depends on B, we need to bake B first. 

	function project.bake(prj)
		local sln = prj.solution
		
		keyedblocks.create(prj, sln)
		
		if prj.isbaked then
			return prj
		end
		local tmr = timer.start('project.bake')
		
		-- bake the project's "root" configuration, which are all of the
		-- values that aren't part of a more specific configuration
		prj.solution = sln
		prj.platforms = prj.platforms or {}
		prj.isbaked = true
		
		-- prevent any default system setting from influencing configurations
		prj.system = nil
		
		-- Inherit sln.configurations, for ease of access
		prj.configurations = prj.configurations or sln.configurations

		-- A command project has only one configuration (& output) which is equivalent to all variants
		if #prj.configurations == 1 and prj.configurations[1] == 'All' then
			prj.isCommandProject = true
		end 
		
		-- initial build variant -> final build variant name 
		prj.buildVariantMap = {}
		
		-- add this to the generate list
		targets.prjToGenerate[prj.name] = prj

		timer.stop(tmr)
		return prj
	end
	
--
-- Add a baked configuration to the project.
--  buildVariant is a keyed table of keywords (buildcfg, platform, <featureName> = <featureName>) 
--   describing the config
-- 
	local addedVariants = {}
	function project.addconfig(prj, initialBuildVariant)
		if not prj or ptype(prj) ~= 'project' then return end
		if prj.isUsage then
			prj = project.getRealProject(prj.name, prj.namespaces)
		end		
		if not prj then return end
		
		if not prj.isbaked then
			project.bake(prj)
		end
		
		-- Make sure this is in the build list
		if (not targets.prjToBuild[prj.name]) then
			-- this branch will happen if you've got a projectset with outside dependencies
			targets.prjToBuild[prj.name] = prj
		end
		
		prj.configs = prj.configs or {}
		
		-- The buildVariantMap maps requested build variants to final build variants.
		--  Some build variants may be ignored by this project, the final build variant will exclude these. 
		
		local initialBuildName = config.getBuildName(initialBuildVariant)
		
		-- Check if a mapping already exists
		local finalBuildVariant = project.applyBuildVariantMap(prj, initialBuildVariant)
		
		-- Return blank if we've called addConfig recursively
		if finalBuildVariant['__buildinprogress'] then 
			return { }
		end

		local finalBuildName = config.getBuildName(finalBuildVariant)

		-- Return the config if it's already baked
		if prj.configs[finalBuildName] then
			return prj.configs[finalBuildName]
		end

		-- Placeholders to test for recursion
		prj.buildVariantMap[initialBuildName] = finalBuildVariant		
		prj.buildVariantMap[finalBuildName] = { ['__buildinprogress'] = true }
		
		if finalBuildName == 'All' and not prj.isCommandProject then
			--print("Can't create 'All' build variant for regular project "..prj.name)
			return {}
		end

		if not addedVariants[finalBuildName] then
			addedVariants[finalBuildName] = finalBuildName
			if finalBuildName ~= 'All' then
				if #keyedblocks.active > 0 then
					printDebug("Added variant "..finalBuildName .. ' used by '..keyedblocks.active[#keyedblocks.active].name)
				else
					printDebug("Added variant "..finalBuildName)
				end
			end
		end				
		--printDebug("Baking "..prj.name..':'..finalBuildName)
		
		local tmr = timer.start('project.addconfig')
		
		-- Get the config filter for this build variant
		local filter = keyedblocks.getfilter(prj, finalBuildVariant)

		-- Get the config
		local cfg = config.bake(prj, filter)

		-- Now we've evaluated the blocks, we can get the real final build variant
		finalBuildVariant = cfg.buildVariant
		finalBuildName = config.getBuildName(finalBuildVariant)

		-- Add to the list of configs		
		prj.configs[finalBuildName] = cfg

		--printDebug("Baked "..prj.name..':'..finalBuildName)
		
		-- Add the build variants to the map
		prj.buildVariantMap[initialBuildName] = finalBuildVariant
		prj.buildVariantMap[finalBuildName] = finalBuildVariant
				
		-- Add usage requirements for the new configuration
		local uProj = project.getUsageProject(prj.name)
		if uProj then
			local usageKB = config.addUsageConfig(prj, uProj, finalBuildVariant)
			-- hack : apply buildVariantMap
			uProj.keyedblocks.__filter[initialBuildName] = usageKB
		end
		
		timer.stop(tmr)
		
		return cfg
	end
	
	function project.applyBuildVariantMap(prj, buildVariant)
	
		local buildName = config.getBuildName(buildVariant)
		if prj.buildVariantMap[buildName] then
			return prj.buildVariantMap[buildName]
		end
	
		if prj.isCommandProject then
			-- Create special "All" buildcfg variant, all other variants ignored
			return config.createBuildVariant('All')
		end
		
		return buildVariant
	end
	
	function project.getDefaultBuildVariant(prj)
		local defaultcfg
		if _OPTIONS['config'] then
			defaultcfg = _OPTIONS['config']:split(',')[1]
		else
			defaultcfg = prj.defaultconfiguration or (prj.solution or {}).defaultconfiguration
		end
		if not defaultcfg then
			return nil
		end
		if #premake.usevariants > 0 then
			local buildVariant = { 
				buildcfg = defaultcfg,
			}
			for _,v in ipairs(premake.usevariants or {}) do
				buildVariant[v] = v
			end
			defaultcfg = config.getBuildName(buildVariant)
		end		
		
		local defaultBuildVariant = prj.buildVariantMap[defaultcfg]
		
		return defaultBuildVariant
	end

--
-- Builds a list of build configuration/platform pairs for a project,
-- along with a mapping between the solution and project configurations.
-- @param prj
--    The project to query.
-- @return
--    Two values: 
--      - an array of the project's build configuration/platform
--        pairs, based on the result of the mapping
--      - a key-value table that maps solution build configuration/
--        platform pairs to project configurations.
--

	function project.bakeconfigmap(prj)
		error("Replaced with project.getBuildVariants")
		-- Apply any mapping tables to the project's initial configuration set,
		-- which includes configurations inherited from the solution. These rules
		-- may cause configurations to be added ore removed from the project.
		local sln = prj.solution
		local configs = table.fold(sln.configurations or {}, sln.platforms or {})
		for i, cfg in ipairs(configs) do
			configs[i] = project.mapconfig(prj, cfg[1], cfg[2])
		end
		
		-- walk through the result and remove duplicates
		local buildcfgs = {}
		local platforms = {}
		
		for _, pairing in ipairs(configs) do
			local buildcfg = pairing[1]
			local platform = pairing[2]
			
			if not table.contains(buildcfgs, buildcfg) then
				table.insert(buildcfgs, buildcfg)
			end
			
			if platform and not table.contains(platforms, platform) then
				table.insert(platforms, platform)
			end
		end

		-- merge these canonical lists back into pairs for the final result
		configs = table.fold(buildcfgs, platforms)	
		return configs
	end

	function project.getBuildVariants(prj)
		local slnBVs = solution.getBuildVariants(prj.solution)
		
		-- to do : support mapconfig
		
		return slnBVs
	end
--
-- Returns an iterator function for the configuration objects contained by
-- the project. Each configuration corresponds to a build configuration/
-- platform pair (i.e. "Debug|x32") as specified in the solution.
--
-- @param prj
--    The project object to query.
-- @return
--    An iterator function returning configuration objects.
--

	function project.eachconfig(prj)
		if not prj.isbaked then
			error('Project "'..prj.name..'" is not baked')
		end

		return Seq:new(prj.configs):getValues():each()
	end
	
-- 
-- Locate a project by name; case insensitive.
--
-- @param name
--    The name of the project for which to search.
-- @return
--    The corresponding project, or nil if no matching project could be found.
--

	local function getProject(allProjects, name, namespaces)
		local prj = allProjects[name]
		if prj then return prj end
		
		if name:contains(':') then
			name = name:match("[^:]*")
			local prj = allProjects[name]
			if prj then return prj end
		end
		
		if name:startswith("/") then
			name = name:sub(2)
		end

		-- check aliases		
		if not prj then
			local tryName = name
			local i = 0
			while targets.aliases[tryName] do
				tryName = targets.aliases[tryName]
				i = i + 1
				if i > 100 then
					error("Recursive project alias : "..tryName)
				end
			end
		
			prj = allProjects[tryName]
		end
	
		-- check supplied namespaces
		if namespaces and name:contains("/") then
			namespaces = nil
		else
		 	-- convert namespace from string to array
			if type(namespaces) == 'string' then
				local namespace = namespaces
				namespaces = {}
				local prevNS = ''
				for n in namespace:gmatch("[^/]+/") do
					table.insert(namespaces, prevNS..n)
					prevNS = prevNS..n
				end
			end
		end	

		if not prj and namespaces then
			for i = #namespaces,1,-1 do
				local ns = namespaces[i]

				-- Try prepending the namespace
				local tryName = ns..name
				local i = 0
				while targets.aliases[tryName] do
					tryName = targets.aliases[tryName]
					i = i + 1
					if i > 100 then
						error("Recursive project alias : "..tryName)
					end
				end
				prj = allProjects[tryName]
				if prj then return prj end
			end
			
		end
		
		return prj
	end

-- Get a real project. Namespaces is an optional list of prefixes to try to prepend to "name"
	function project.getRealProject(name, namespaces)
		return getProject(targets.allReal, name, namespaces)
	end
	
-- Get a usage project. Namespaces is an optional list of prefixes to try to prepend to "name"
	function project.getUsageProject(name, namespaces)
		return getProject(targets.allUsage, name, namespaces)
	end

-- If a project isn't found, this returns some alternatives
	function project.getProjectNameSuggestions(name, namespaces)
		local suggestions = {}
		local suggestionStr
		
		-- Find hints
		local namespace = '/'
		if namespaces and #namespaces > 1 then namespace = namespaces[#namespaces] end
		local namespace,shortname,fullname = project.getNameParts(name, namespace)
		
		-- Check for wrong namespace
		for prjName,prj in Seq:new(targets.aliases):concat(targets.allUsage):each() do
			if prj.shortname == shortname then
				table.insert(suggestions, prj.name)
			end
		end
		local usage = project.getUsageProject(name, namespaces)
		if #suggestions == 0 then
			-- check for misspellings
			local allUsageNames = Seq:new(targets.aliases):concat(targets.allUsage):getKeys():toTable()
			local spell,count = premake.spelling.new(allUsageNames)
			
			if count < 10 then
				suggestions = spell:getSuggestions(name)
				if #suggestions == 0 then
					suggestions = spell:getSuggestions(fullname)
				end
			end
		end

		if #suggestions > 0 then
			suggestionStr = Seq:new(suggestions):take(20):mkstring(', ')
			if #suggestions > 20 then
				suggestionStr = suggestionStr .. '...'
			end
			suggestionStr = ' Did you mean ' .. suggestionStr .. '?'
		end

		return suggestions, suggestionStr
	end
	
-- Iterate over all real projects
	function project.eachproject()
		local iter,t,k,v = ipairs(targets.allReal)
		return function()
			k,v = iter(t,k)
			return v
		end
	end
	
	-- helper function
	function project.getNameParts(name, namespace)
		if name:startswith("/") then
			name = name:sub(2)
			namespace = "/"
		end
	
		local shortname = name
		namespace = namespace or '/'

		local fullname = name

		if name:find('/') then
			-- extract namespace from the name
			namespace,shortname = name:match("(.*/)([^/]+)$")
		end

		if not namespace:endswith('/') then
			error("namespace must end with /")
		end
		
		if namespace:startswith('/') then namespace = namespace:sub(2, #namespace-1) end 
		
		-- special case for fully specified names, avoids a/b/b when you mean just a/b
		if not name:startswith(namespace) then
			fullname = namespace .. shortname
		end
		
		return namespace, shortname, fullname
	end

-- Create a project
	function project.createproject(name, sln, isUsage)
	
		-- Project full name is MySolution/MyProject, shortname is MyProject
		local namespace,shortname,fullname
		
		if isUsage and premake.api.scope.currentNamespace:sub(1,#name) == name then
			local namespace = premake.api.scope.currentNamespace
			fullname = name
			shortname = name
		else
			namespace,shortname,fullname = project.getNameParts(name, premake.api.scope.currentNamespace)
		end
				
		-- Now we have the fullname, check if this is already a project
		if isUsage then
			local existing = targets.allUsage[fullname]
			if existing then return existing end
			
		else
			local existing = targets.allReal[fullname]
			if existing then return existing end
		end
					
		local prj = {}
		
		-- attach a type
		ptypeSet(prj, 'project')
		
		-- add to global list keyed by name
		if isUsage then
			targets.allUsage[fullname] = prj
		else
			targets.allReal[fullname] = prj
		end
		
		-- add to solution list keyed by both name and index
		if not sln.projects[name] then
			table.insert(sln.projects, prj)
			sln.projects[name] = prj
		end
		
		prj.solution       = sln
		prj.namespaces     = namespace
		prj.name           = fullname
		prj.fullname       = fullname
		prj.shortname      = shortname
		prj.basedir        = _CWD
		prj.dirFromRoot    = _CWD:replace(repoRootPlain,""):replace(repoRoot,"")
		prj.script         = _SCRIPT
		prj.uuid           = os.uuid()
		prj.blocks         = { }
		prj.isUsage		   = isUsage;
		
		-- Create a default usage project if there isn't one
		-- Note : use targets.allUsage[] directly as we may already have an alias to another project with the same name
		if (not isUsage) then
			prj.usagePrj = targets.allUsage[fullname]
			if not prj.usagePrj then
				prj.usagePrj = project.createproject(fullname, sln, true)
			end
			prj.realPrj = prj
		else
			prj.usagePrj = prj
			prj.realPrj = targets.allReal[fullname]
		end
		
		return prj;
	end
	

--
-- Retrieve the project's configuration information for a particular build 
-- configuration/platform pair.
--
-- @param prj
--    The project object to query.
-- @param buildcfg
--    The name of the build configuration on which to filter.
-- @param platform
--    Optional; the name of the platform on which to filter.
-- @return
--    A configuration object.
--
	
	function project.getconfig(prj, buildcfg, platform)
		if type(buildcfg) == 'table' then
			-- alias
			local buildVariant = buildcfg
			return project.getconfig2(prj, buildVariant)
		end
		return project.getconfig(prj, { buildcfg = buildcfg, platform = platform })
	end
	
	function project.getconfig2(prj, buildVariant)
		-- to make testing a little easier, allow this function to
		-- accept an unbaked project, and fix it on the fly
		if not prj.isbaked then
			prj = project.bake(prj)
		end
	
		buildVariant = project.applyBuildVariantMap(prj, buildVariant)
	
		-- look up and return the associated config		
		local key = config.getBuildName(buildVariant)
		return prj.configs[key]
	end


--
-- Returns a list of sibling projects on which the specified project depends. 
-- This is used to list dependencies within a solution or workspace. Must 
-- consider all configurations because Visual Studio does not support per-config
-- project dependencies.
--
-- @param prj
--    The project to query.
-- @return
--    A list of dependent projects, as an array of project objects.
--

	function project.getdependencies(prj)
		local result = {}

		for cfg in project.eachconfig(prj) do
			for _, link in ipairs(cfg.links or {}) do
				local dep = premake.solution.findproject(cfg.solution, link)
				if dep and not table.contains(result, dep) then
					table.insert(result, dep)
				end
			end
		end

		return result
	end


--
-- Builds a file configuration for a specific file from a project.
--
-- @param prj
--    The project to query.
-- @param filename
--    The absolute path of the file to query.
-- @return
--    A corresponding file configuration object.
--

	function project.getfileconfig(prj, filename)
		local fcfg = {}

		fcfg.abspath = filename
		fcfg.relpath = project.getrelative(prj, filename)

		local vpath = project.getvpath(prj, filename)
		if vpath ~= filename then
			fcfg.vpath = vpath
		else
			fcfg.vpath = fcfg.relpath
		end

		fcfg.name = path.getname(filename)
		fcfg.basename = path.getbasename(filename)
		fcfg.path = fcfg.relpath
		
		return fcfg
	end


--
-- Returns a unique object file name for a project source code file.
--
-- @param prj
--    The project object to query.
-- @param filename
--    The name of the file being compiled to the object file.
--

	function project.getfileobject(prj, filename)
		-- make sure I have the project, and not it's root configuration
		prj = prj.project or prj
		
		-- create a list of objects if necessary
		prj.fileobjects = prj.fileobjects or {}

		-- look for the corresponding object file		
		local basename = path.getbasename(filename)
		local uniqued = basename
		local i = 0
		
		while prj.fileobjects[uniqued] do
			-- found a match?
			if prj.fileobjects[uniqued] == filename then
				return uniqued
			end
			
			-- check a different name
			i = i + 1
			uniqued = basename .. i
		end
		
		-- no match, create a new one
		prj.fileobjects[uniqued] = filename
		return uniqued
	end


--
-- Retrieve the project's file name.
--
-- @param prj
--    The project object to query.
-- @return
--    The project's file name. This will usually match the project's
--    name, or the external name for externally created projects.
--

	function project.getfilename(prj)
		return prj.externalname or prj.name
	end


--
-- Return the first configuration of a project, which is used in some
-- actions to generate project-wide defaults.
--
-- @param prj
--    The project object to query.
-- @return
--    The first configuration in a project, as would be returned by
--    eachconfig().
--

	function project.getfirstconfig(prj)
		local iter = project.eachconfig(prj)
		local first = iter()
		return first
	end


--
-- Retrieve the project's file system location.
--
-- @param prj
--    The project object to query.
-- @param relativeto
--    Optional; if supplied, the project location will be made relative
--    to this path.
-- @return
--    The path to the project's file system location.
--

	function project.getlocation(prj, relativeto)
		local location = prj.location or prj.solution.location or prj.basedir
		if relativeto then
			location = path.getrelative(relativeto, location)
		end
		return location
	end


--
-- Return the relative path from the project to the specified file.
--
-- @param prj
--    The project object to query.
-- @param filename
--    The file path, or an array of file paths, to convert.
-- @return
--    The relative path, or array of paths, from the project to the file.
--

	function project.getrelative(prj, filename)
		if type(filename) == "table" then
			local result = {}
			for i, name in ipairs(filename) do
				result[i] = project.getrelative(prj, name)
			end
			return result
		else
			if filename then
				return path.getrelative(project.getlocation(prj), filename)
			end
		end
	end


--
-- Create a tree from a project's list of source files.
--
-- @param prj
--    The project to query.
-- @return
--    A tree object containing the source file hierarchy. Leaf nodes
--    representing the individual files contain the fields:
--      abspath  - the absolute path of the file
--      relpath  - the relative path from the project to the file
--      vpath    - the file's virtual path
--    All nodes contain the fields:
--      path     - the node's path within the tree
--      realpath - the node's file system path (nil for virtual paths)
--      name     - the directory or file name represented by the node
--

	function project.getsourcetree(prj)
		-- make sure I have the project, and not it's root configuration
		prj = prj.project or prj
		
		-- check for a previously cached tree
		if prj.sourcetree then
			return prj.sourcetree
		end

		-- find *all* files referenced by the project, regardless of configuration
		local files = {}
		for cfg in project.eachconfig(prj) do
			for _, file in ipairs(cfg.files or {}) do
				if not path.isabsolute(file) then
					file = path.join( prj.basedir, file )
				end
				files[file] = file
			end
		end

		-- create a tree from the file list
		local tr = premake.tree.new(prj.name)
		
		for file in pairs(files) do
			local fcfg = project.getfileconfig(prj, file)

			-- The tree represents the logical source code tree to be displayed
			-- in the IDE, not the physical organization of the file system. So
			-- virtual paths are used when adding nodes.
			local node = premake.tree.add(tr, fcfg.vpath, function(node)
				-- ...but when a real file system path is used, store it so that
				-- an association can be made in the IDE 
				if fcfg.vpath == fcfg.relpath then
					node.realpath = node.path
				end
			end)

			-- Store full file configuration in file (leaf) nodes
			for key, value in pairs(fcfg) do
				node[key] = value
			end
		end

		premake.tree.trimroot(tr)
		premake.tree.sort(tr)
		
		-- cache result and return
		prj.sourcetree = tr
		return tr
	end


--
-- Given a source file path, return a corresponding virtual path based on
-- the vpath entries in the project. If no matching vpath entry is found,
-- the original path is returned.
--

	function project.getvpath(prj, filename)
		-- if there is no match, return the input filename
		local vpath = filename
		
		for replacement,patterns in pairs(prj.vpaths or {}) do
			for _,pattern in ipairs(patterns) do

				-- does the filename match this vpath pattern?
				local i = filename:find(path.wildcards(pattern))
				if i == 1 then				

					-- yes; trim the leading portion of the path
					i = pattern:find("*", 1, true) or (pattern:len() + 1)
					local leaf = filename:sub(i)
					if leaf:startswith("/") then
						leaf = leaf:sub(2)
					end
					
					-- check for (and remove) stars in the replacement pattern.
					-- If there are none, then trim all path info from the leaf
					-- and use just the filename in the replacement (stars should
					-- really only appear at the end; I'm cheating here)
					local stem = ""
					if replacement:len() > 0 then
						stem, stars = replacement:gsub("%*", "")
						if stars == 0 then
							leaf = path.getname(leaf)
						end
					end
					
					vpath = path.join(stem, leaf)

				end
			end
		end
		
		return vpath
	end


--
-- Determines if a project contains a particular build configuration/platform pair.
--

	function project.hasconfig(prj, buildcfg, platform)
		if buildcfg and not prj.configurations[buildcfg] then
			return false
		end
		if platform and not prj.platforms[platform] then
			return false
		end
		return true
	end


--
-- Given a build config/platform pairing, applies any project configuration maps
-- and returns a new (or the same) pairing.
--

	function project.mapconfig(prj, buildcfg, platform)
		local pairing = { buildcfg, platform }
		
		local testpattern = function(pattern, pairing, i)
			local j = 1
			while i <= #pairing and j <= #pattern do
				if pairing[i] ~= pattern[j] then
					return false
				end
				i = i + 1
				j = j + 1
			end
			return true
		end
		
		for pattern, replacements in pairs(prj.configmap or {}) do
			if type(pattern) ~= "table" then
				pattern = { pattern }
			end
			
			-- does this pattern match any part of the pair? If so,
			-- replace it with the corresponding values
			for i = 1, #pairing do
				if testpattern(pattern, pairing, i) then
					if #pattern == 1 and #replacements == 1 then
						pairing[i] = replacements[1]
					else
						pairing = { replacements[1], replacements[2] }
					end
				end
			end
		end
				
		return pairing
	end


--
-- Returns true if the project use the C language.
--

	function project.iscproject(prj)
		local language = prj.language or prj.solution.language
		return language == "C"
	end


--
-- Returns true if the project uses a C/C++ language.
--

	function project.iscppproject(prj)
		local language = prj.language or prj.solution.language
		return language == "C" or language == "C++"
	end



--
-- Returns true if the project uses a .NET language.
--

	function project.isdotnetproject(prj)
		local language = prj.language or prj.solution.language
		return language == "C#"
	end

	-- returns true if the project is in the set s
	function project.inProjectSet(prj, s)
		
		if s == nil or s == 'all' then 
			return true 
		end
		
		if type(s) == 'table' then
			-- Return true if the project is in any of the values in table s
			for _,v in pairs(s) do
				if project.inProjectSet(prj, v) then 
					return true 
				end
			end
			return false
		else
			local prjset = targets.prjNameToSet[prj.fullname]
			if not prjset then
				return false 
			end
			return prjset[s]
		end
	end