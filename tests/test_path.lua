--
-- tests/test_path.lua
-- Automated test suite for the path manipulation functions.
-- Copyright (c) 2008 Jason Perkins and the Premake project
--


	T.path = { }


--
-- path.getabsolute() tests
--

	function T.path.getabsolute_ReturnsCorrectPath_OnMissingSubdir()
		local expected = path.translate(os.getcwd(), "/") .. "/a/b/c"
		test.isequal(expected, path.getabsolute("a/b/c"))
	end


--
-- path.getbasename() tests
--

	function T.path.getbasename_ReturnsCorrectName_OnDirAndExtension()
		test.isequal("filename", path.getbasename("folder/filename.ext"))
	end


--
-- path.getdirectory() tests
--

	function T.path.getdirectory_ReturnsEmptyString_OnNoDirectory()
		test.isequal(".", path.getdirectory("filename.ext"))
	end
	
	function T.path.getdirectory_ReturnsDirectory_OnSingleLevelPath()
		test.isequal("dir0", path.getdirectory("dir0/filename.ext"))
	end
	
	function T.path.getdirectory_ReturnsDirectory_OnMultiLeveLPath()
		test.isequal("dir0/dir1/dir2", path.getdirectory("dir0/dir1/dir2/filename.ext"))
	end

	function T.path.getdirectory_ReturnsRootPath_OnRootPathOnly()
		test.isequal("/", path.getdirectory("/filename.ext"))
	end
	

--
-- path.getextension() tests
--

	function T.path.getextension_ReturnsEmptyString_OnNoExtension()
		test.isequal("", path.getextension("filename"))
	end

	function T.path.getextension_ReturnsExtension()
		test.isequal(".txt", path.getextension("filename.txt"))
	end
	
	function T.path.getextension_OnMultipleDots()
		test.isequal(".txt", path.getextension("filename.mod.txt"))
	end


--
-- path.getrelative() tests
--

	function T.path.getrelative_ReturnsDot_OnMatchingPaths()
		test.isequal(".", path.getrelative("/a/b/c", "/a/b/c"))
	end

	function T.path.getrelative_ReturnsDoubleDot_OnChildToParent()
		test.isequal("..", path.getrelative("/a/b/c", "/a/b"))
	end
	
	function T.path.getrelative_ReturnsDoubleDot_OnSiblingToSibling()
		test.isequal("../d", path.getrelative("/a/b/c", "/a/b/d"))
	end

	function T.path.getrelative_ReturnsChildPath_OnParentToChild()
		test.isequal("d", path.getrelative("/a/b/c", "/a/b/c/d"))
	end


--
-- path.isabsolute() tests
--

	function T.path.isabsolute_ReturnsTrue_OnAbsolutePosixPath()
		test.istrue(path.isabsolute("/a/b/c"))
	end

	function T.path.isabsolute_ReturnsTrue_OnAbsoluteWindowsPathWithDrive()
		test.istrue(path.isabsolute("C:/a/b/c"))
	end

	function T.path.isabsolute_ReturnsFalse_OnRelativePath()
		test.isfalse(path.isabsolute("a/b/c"))
	end


--
-- path.join() tests
--

	function T.path.join_OnValidParts()
		test.isequal("leading/trailing", path.join("leading", "trailing"))
	end
	
	function T.path.join_OnAbsoluteUnixPath()
		test.isequal("/trailing", path.join("leading", "/trailing"))
	end
	
	function T.path.join_OnAbsoluteWindowsPath()
		test.isequal("C:/trailing", path.join("leading", "C:/trailing"))
	end

	function T.path.join_OnCurrentDirectory()
		test.isequal("trailing", path.join(".", "trailing"))
	end
	
	
--
-- path.translate() tests
--

	function T.path.translate_ReturnsTranslatedPath_OnValidPath()
		test.isequal("dir/dir/file", path.translate("dir\\dir\\file", "/"))
	end

	function T.path.translate_ReturnsCorrectSeparator_OnMixedPath()
		local actual = path.translate("dir\\dir/file")
		if (os.windows) then
			test.isequal("dir\\dir\\file", actual)
		else
			test.isequal("dir/dir/file", actual)
		end
	end