--
--	Forward declare Premake's structures before anything else
--
-- 		Create a top-level namespace for Premake's own APIs. The premake5 namespace 
-- 		is a place to do next-gen (4.5) work without breaking the existing code (yet).
-- 		I think it will eventually go away.
--

	premake = { }
	premake5 = { }
	premake.tools = { }

-- Top level namespace for abstract base class definitions 
	premake.abstract = { }
	
-- Top level namespace for actions
	premake.actions = { }

-- For adding to the directories searched by os.findlib
 	premake.libSearchPath = { }

	premake5.globalContainer = { }
	
	premake5.targets = {}	
	premake5.targets.allUsage = {}
	premake5.targets.allReal = {}
	premake5.targets.releases = {}
	premake5.targets.aliases = {}

	premake5.project = { }
	premake5.oven = { }
	premake.solution = { }
	premake.keyedblocks = { }
	premake5.config = { }
	
	premake.cache = {}
	
	premake.releases = {}
	
-- Global defualt settings, override this in the system script if necessary
	premake.clearActiveProjectOnNewFile = true