--
-- io.lua
-- Additions to the I/O namespace.
-- Copyright (c) 2008-2009 Jason Perkins and the Premake project
--

--
-- Get the file size of an open file, in bytes
--
	function io.getsize(fileHandle)
		if type(fileHandle) ~= 'userdata' then
			error("io.getsize requires a file handle, received "..type(fileHanle))
		end
		if io.type(fileHandle) ~= 'file' then
			error("io.getsize file handle is " .. tostring(io.type(fileHandle)) )
		end
		local pos = fileHandle:seek("cur", 0)
		local fileSize = fileHandle:seek("end", 0)
		fileHandle:seek("set", pos)
		return fileSize
	end

--
-- Prepare to capture the output from all subsequent calls to io.printf(), 
-- used for automated testing of the generators.
--
	local builtin_write = io.write
	function io.capture()
		io.captured = {}
		io.write = function(v)
			table.insert( io.captured, v )
		end
	end
	
	
	
--
-- Returns the captured text and stops capturing.
--

	function io.endcapture()
		local captured = table.concat( io.captured, '')
		io.captured = nil
		io.write = builtin_write
		return captured
	end
	
	
--
-- Open an overload of the io.open() function, which will create any missing
-- subdirectories in the filename if "mode" is set to writeable.
--

	local builtin_open = io.open
	function io.open(fname, mode)
		if _OPTIONS['dryrun'] then
			if mode and mode:find('w') then
				printf('write : ' .. fname .. '\n')
				return 'nullfile'
			elseif mode and mode:find('a') then
				printf('append : ' .. fname .. '\n')
				return 'nullfile'
			else 
				printf('read : ' .. fname .. '\n')
				return builtin_open(fname, mode)
			end
		end
		if (mode) then
			if (mode:find("w")) then
				local dir = path.getdirectory(fname)
				local ok, err = os.mkdir(dir)
				if (not ok) then
					error(err, 0)
				end
			end
		end
		return builtin_open(fname, mode)
	end



-- 
-- A shortcut for printing formatted output to an output stream.
--

	function io.printf(msg, ...)
		if _OPTIONS['dryrun'] then
			return
		end
		
		if not io.eol then
			io.eol = "\n"
		end

		if not io.indent then
			io.indent = "\t"
		end

		if type(msg) == "number" then
			local str, fmt, x = unpack(arg)
			s = string.rep(io.indent, msg) .. string.format(unpack(arg))
		else
			s = string.format(msg, unpack(arg))
		end
		
		io.write(s)
		io.write(io.eol)
	end

	function io.close(fileHandle)
		if fileHandle and not _OPTIONS['dryrun'] then
			fileHandle:flush()
			fileHandle:close()
		end			
	end

--
-- Because I use io.printf() so often in the generators, create a terse shortcut
-- for it. This saves me typing, and also reduces the size of the executable.
--

	_p = io.printf


--
-- Another variation that calls esc() on all of its arguments before formatting.
--

	_x = function(msg, ...)
		for i=2, #arg do
			arg[i] = premake.esc(arg[i])
		end
		io.printf(msg, unpack(arg))
	end
