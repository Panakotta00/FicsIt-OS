local buffer = require("buffer")
local util = require("util")

local packageLib = {}

---calles the visitor function for each source in the given step of the given event in the given package
---@param package table the package containing the events, steps and sources
---@param event string the name of the event
---@param step string the name of the step
---@param visitor function the function that gets called for each source as first argument
function packageLib.visitEvents(package, event, step, visitor)
	if package and package.events[event] and package.events[event][step] then
		for _, source in pairs(package.events[event][step]) do
			visitor(source)
		end
	end
end

---creates a copy of the given package that can be stored on the drive for uninstall and upgrade purposes
---@param package table the package you want to copy
function packageLib.convertPackageToSaved(package)
	local newPackage = {
		id = package.id,
		meta = util.deepCopy(package.meta),
		events = util.deepCopy(package.events),
		folders = util.deepCopy(package.folders),
		files = {},
	}
	
	for path, source in pairs(package.files) do
		local srcCopy = util.deepCopy(source)
		srcCopy.content = nil
		newPackage.files[path] = srcCopy
	end
	
	return newPackage
end

---creates a package parser objects that allows you to parse package scripts into a package
---@param id string the pastebin id of the package
---@return table a package parser object
function packageLib.createPackageParser(id)
	local parser = {
		package = {
			id = id,
			meta = {},
			events = {},
			files = {},
			folders = {},
		},
		section = nil, -- has to have a "contents" table which will contain all lines of a section while parsing, after parsing one section, contents will be converted to a single "content"
	}
	
	---tries to parse a source object from the given arguements at the given "arg" offset
	---@param args table an array of strings containing the arguments which we try to parse
	---@param arg number the start index of the args array at which we should try to parse the source object
	---@return table, number the parsed source object and the new args index at which you could continue to read the next args
	function parser:parseSource(args, arg)
		local source = {
			type = args[arg]
		}
		arg = arg + 1
		if source.type == "inline" then
			source.contents = {}
			self.section = source
			return source, arg
		elseif source.type == "paste" then
			source.paste = args[arg]
			return source, arg+1
		elseif source.type == "url" then
			source.url = args[arg]
			return source, arg+1
		end
		error("failed to parse source of type '" .. source.type .. "'")
	end
	
	function parser:tryParseMetaData(args)
		local key = args[1]:match("^(%w+):$")
		if not key then
			return false
		end
		self.package.meta[key] = args[2]
		return true
	end
	
	function parser:tryParseEvent(args)
		if args[1] ~= "event" then
			return false
		end
		local step = args[2]
		local event = args[3]
		if (step ~= "pre" and step ~= "post") or (event ~= "install" and event ~= "uninstall" and event ~= "upgrade") then
			return true
		end
		
		local source, arg = self:parseSource(args, 4)
		
		local eventTbl = self.package.events[event] or {}
		self.package.events[event] = eventTbl
		
		local stepTbl = eventTbl[step] or {}
		eventTbl[step] = stepTbl
		
		table.insert(stepTbl, source)
		
		return true
	end
	
	function parser:tryParseFile(args)
		if args[1] ~= "file" then
			return false
		end
		
		local source, arg = self:parseSource(args, 3)
		source.path = args[2]
		
		source.attributes = {}
		while arg <= #args do
			table.insert(source.attributes, args[arg])
			arg = arg + 1
		end
		
		table.insert(self.package.files, source)
		
		return true
	end
	
	function parser:tryParseFolder(args)
		if args[1] ~= "folder" then
			return false
		end
		
		local folder = {
			path = args[2],
			attributes = {}
		}
		
		for i=3,#args,1 do
			table.insert(folder.attributes, args[i])
		end
		
		table.insert(self.package.folders, folder)
		
		return true
	end
	
	---converts the contents array into a single content string for sections
	---@param section table
	local function finishSection(section)
		if section then
			section.content = table.concat(section.contents, "\n")
			section.contents = nil
		end
	end
	
	---tries to parse a single line of a package script as instruction
	---@param instruction string a single instruction to be parsed
	---@return boolean true if it was able to parse the line as instruction
	function parser:tryParseInstruction(instruction)
		local inst = instruction:match("^%s*--FIOS%s+(.*)%s*$")
		if inst then
			finishSection(self.section)
			self.section = nil
			
			local function tokenize(str)
				local pos = str:find("[%s\"\\]")
				if not pos then
					return "", "text", str
				end
				if pos > 1 then
					return str:sub(pos), "text", str:sub(1, pos-1)
				end
				local c = str:sub(1,1)
				if c == "\"" then
					return str:sub(pos+1), "quote", c
				end
				if c == "\\" then
					return str:sub(pos+1), "esc", c
				end
				return str:sub(pos+1), "whitespace", c
			end
			
			local args = {}
			local arg = {}
			local isInString = false
			local isEscaped = false
			
			while inst:len() > 0 do
				local token, tokenData
				inst, token, tokenData = tokenize(inst)
				if token == "text" then
					table.insert(arg, tokenData)
				elseif token == "quote" then
					if isEscaped then
						table.insert(arg, tokenData)
						isEscaped = false
					else
						isInString = not isInString
					end
				elseif token == "esc" then
					if isEscaped then
						table.insert(arg, tokenData)
					end
					isEscaped = not isEscaped
				elseif token == "whitespace" then
					if isEscaped or isInString then
						isEscaped = false
						table.insert(arg, tokenData)
					elseif #arg > 0 then
						table.insert(args, table.concat(arg, ""))
						arg = {}
					end
				end
			end
			table.insert(args, table.concat(arg, ""))
			
			_ = self:tryParseMetaData(args)
			or self:tryParseEvent(args)
			or self:tryParseFile(args)
			or self:tryParseFolder(args)
			
			return true
		end
		return false
	end
	
	---parses the given package-script into ther parsers package
	---@param packageScript string the package script you want to parse
	---@param onError function optional function getting called when a error occurs in parsing otherwise errors will rethrow error
	function parser:parse(packageScript, onError)
		local stream = buffer.create("r", buffer.stringstream(packageScript))
		
		local lineNr = 0
		for line in stream:lines() do
			lineNr = lineNr + 1
			local success, err = pcall(function()
				if not self:tryParseInstruction(line) then
					-- no instruction -> section content -> append line to current section
					if self.section then
						table.insert(self.section.contents, line)
					end
				end
			end)
			if not success then
				if onError then
					onError(err)
				else
					error(err)
				end
			end
		end
		finishSection(self.section)
		self.section = nil
	end
	
	return parser
end

return packageLib