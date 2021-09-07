local math = require("math")
local console = require("console")
local util = require("util")
local thread = require("thread")
local process = require("process")
local buffer = require("buffer")

local shell = {}

function shell.read(mode)
	local p = process.running()
	return p.stdInput:read(mode)
end

function shell.write(text)
	local p = process.running()
	p.stdOutput:write(text)
end

function shell.writeLine(text)
	shell.write(text .. "\n")
end

function shell.readLine()
	return console.readLine(shell.getInput(), shell.getOutput())
end

function shell.getInput()
	local p = process.running()
	return p.stdInput
end

function shell.getOutput()
	local p = process.running()
	return p.stdOutput
end

function shell.createLexer()
	local lexer = {
		tokenTypes = {},
		tokenData = {},
		tokenStart = {},
		tokenStop = {},
		len = 0
	}
	
	function lexer:nextToken(str)
		local pos = str:find("[%s+\"'\\<>]")
		if not pos then
			return "", "text", str
		end
		if pos > 1 then
			return str:sub(pos), "text", str:sub(1, pos-1)
		end
		local c = str:sub(1,1)
		if c == "\"" or c == "'" then
			return str:sub(pos+1), "quote", c
		end
		if c == "\\" then
			return str:sub(pos+1), "esc", c
		end
		if c == "=" then
			return str:sub(pos+1), "set", c
		end
		if c == "<" or c == ">" then
			return str:sub(pos+1), c, c
		end
		return str:sub(pos+1), "whitespace", c
	end
	
	function lexer:tokenize(txt)
		local tokenType, tokenData
		while txt:len() > 0 do
			txt, tokenType, tokenData = self:nextToken(txt)
			table.insert(self.tokenTypes, tokenType)
			table.insert(self.tokenData, tokenData)
			table.insert(self.tokenStart, self.len+1)
			table.insert(self.tokenStop, self.len + tokenData:len())
			self.len = self.len + tokenData:len()
		end
	end
	
	function lexer:getToken(pos)
		return self.tokenTypes[pos], self.tokenData[pos], self.tokenStart[pos], self.tokenStop[pos]
	end
	
	return lexer
end

function shell.replaceVars(str, vars)
	vars = vars or process.running().environment
	local function replaceVar(var)
		return vars[var] or ""
	end
	str = str:gsub("$(%w+)", replaceVar)
	str = str:gsub("${(%w+)}", replaceVar)
	return str
end

function shell.createParser(lexer)
	local parser = {
		lexer = lexer,
		pos = 1,
	}
	
	function parser:getToken(pos)
		return self.lexer:getToken(pos or self.pos)
	end
	
	function parser:nextToken()
		self.pos = self.pos + 1
	end
	
	function parser:nextNonWhitespaceToken()
		while true do
			local tokenType = self:getToken()
			if tokenType ~= "whitespace" then
				break
			else
				self:nextToken()
			end
		end
		return self:getToken()
	end
	
	function parser:parseToken()
		local text = {}
		local state = "normal"
		local isEscaped = false
		while true do
			local tokenType, tokenData, tokenStart, tokenStop = self:getToken()
			text.start = text.start or tokenStart
			if state == "normal" then
				if tokenType == "text" then
					table.insert(text, tokenData)
				elseif tokenType == "quote" then
					state = tokenData
				elseif tokenType == "esc" then
					state = tokenType
				elseif tokenType == "whitespace" and #text < 1 then
					-- ignore whitespace at beginning
					text.start = nil
				else
					break
				end
			elseif state == "'" or state == "\"" then
				if tokenData == state then
					if isEscaped then
						text[#text] = tokenData
						isEscaped = false
					else
						state = "normal"
					end
				elseif tokenType == "text" or tokenType == "quote" or tokenType == "whitespace" then
					table.insert(text, tokenData)
					isEscaped = false
				elseif tokenType == "esc" then
					if isEscaped then
						isEscaped = false
					else
						table.insert(text, tokenData)
						isEscaped = true
					end
				else
					break
				end
			elseif state == "esc" then
				if tokenType == "text" or tokenType == "quote" or tokenType == "esc" or tokenType == "whitespace" then
					table.insert(text, tokenData)
					state = "normal"
				else
					break
				end
			else
				break
			end
			text.stop = tokenStop
			self:nextToken()
		end
		
		if #text > 0 then
			return shell.replaceVars(table.concat(text, ""), self.environment), text.start, text.stop
		else
			return nil
		end
	end
	
	function parser:parseSimple()
		local simple = {}
		while true do
			local token = self:parseToken()
			if token then
				table.insert(simple, token)
			else
				break
			end
		end
		if #simple > 0 then
			return simple
		else
			return nil
		end
	end
	
	function parser:parseCommand()
		local command = {
			args = {}
		}
		while true do
			local simple = self:parseSimple()
			if simple then
				table.move(simple, 1, #simple, #command.args+1, command.args)
			else
				local tokenType, tokenData = self:nextNonWhitespaceToken()
				local action
				if tokenType == ">" then
					action = function(token)
						command.outputFile = token
					end
				elseif tokenType == "<" then
					action = function(token)
						command.inputFile = token
					end
				else
					break
				end
				if action then
					self:nextToken()
					local token = self:parseToken()
					if token then
						action(token)
					else
						break
					end
				end
			end
		end
		if #command.args > 0 then
			return command
		else
			return nil
		end
	end
	
	function parser:parseArgs(inst)
		local arg = {}
		local argMeta = {plain=true}
		local isInString = nil
		local isEscaped = false
		
		local pos = 1
		while inst:len() > 0 do
			local token, tokenData
			inst, token, tokenData = nextToken(inst)
			if token == "text" then
				table.insert(arg, tokenData)
				argMeta.start = argMeta.start or pos
			elseif token == "quote" then
				if isEscaped or (isInString and isInString ~= tokenData) then
					table.insert(arg, tokenData)
					argMeta.start = argMeta.start or pos
					argMeta.plain = false
					isEscaped = false
				elseif isInString then
					isInString = nil
				else
					isInString = tokenData
					argMeta.start = argMeta.start or pos
					argMeta.plain = false
				end
			elseif token == "esc" then
				if isEscaped then
					table.insert(arg, tokenData)
					argMeta.start = argMeta.start or pos
					argMeta.plain = false
				end
				isEscaped = not isEscaped
			elseif token == "var" then
				if isEscaped then
					table.insert(arg, tokenData)
					argMeta.plain = false
					argMeta.start = argMeta.start or pos
				else
					table.insert(arg, tokenData)
					argMeta.var = true
				end
			elseif token == "whitespace" then
				if isEscaped or isInString then
					isEscaped = false
					table.insert(arg, tokenData)
					argMeta.start = argMeta.start or pos
					argMeta.plain = false
				elseif #arg > 0 then
					argMeta.stop = pos-1
					table.insert(args, table.concat(arg, ""))
					table.insert(argsMeta, argMeta)
					argMeta = {plain=true}
					arg = {}
				end
			end
			pos = pos + tokenData:len()
		end
		if #arg > 0 then
			argMeta.stop = pos-1
			table.insert(args, table.concat(arg, ""))
			table.insert(argsMeta, argMeta)
		end
		return args, argsMeta
	end
	
	return parser
end

local function toArg(string)
	return string:gsub(" ", "\\ ")
end

local builtInCommands = {}

function builtInCommands.cd(...)
	local p = process.running()
	
	p.environment["PWD"] = filesystem.path(1, p.environment["PWD"], ...)
end

function shell.executeCommand(command)
	-- load prog
	local progName = command.args[1]
	table.remove(command.args, 1)
	
	local prog = builtInCommands[progName]
	if prog then
		return prog(table.unpack(command.args))
	else
		local path = filesystem.path(progName)
		if not filesystem.isFile(path) then
			path = util.findScriptPath(progName, "/bin/")
			if not path then
				shell.writeLine("Command not found")
				return -1
			end
		end
		local prog = filesystem.loadFile(path)
		if type(prog) ~= "function" then
			shell.writeLine("Unable to load program\n" .. prog)
			return -2
		end
		
		-- create process
		local output, input
		local proc = process.create(function(...)
			if command.outputFile then
				output = filesystem.open(command.outputFile, "w")
				process.running().stdOutput = output
			end
			if command.inputFile then
				input = filesystem.open(command.inputFile, "r")
				process.running().stdInput = input
			end
			return prog(...)
		end, table.unpack(command.args))
		proc:await()
		if output then
			output:close()
		end
		if input then
			input:close()
		end
		return table.unpack(proc.mainThread.results)
	end
end

function shell.execute(cmd)
	local lexer = shell.createLexer()
	lexer:tokenize(cmd)
	local parser = shell.createParser(lexer)
	
	local command = parser:parseCommand()
	
	return shell.executeCommand(command)
end

function shell.completions(text, withCommands)
	local completions = {}
	
	local name = text
	local body = ""
	if text:find("/") then
		withCommands = false
	end
	if text:find("/%w+%s*$") then
		name = filesystem.path(3, text)
		body = filesystem.path(0, text, "..")
	elseif text:find("/%s*$") then
		name = ""
		body = text
	end
	-- TODO: add "directory"-ref detection for filesystem.analyze and path, and add maybe something to path to be able to get all parts at once
	
	local function addChildren(path, removeEnding)
		local children = {}
		if filesystem.isDir(path) then
			children = filesystem.childs(path)
		end
		table.sort(children)
		for _, child in pairs(children) do
			local m1, m2 = child:match("^(" .. name .. ")(.*)$")
			if m1 then
				local completion = text .. m2
				if removeEnding then
					completion = filesystem.path(0, filesystem.path(completion, ".."), filesystem.path(4, completion))
				end
				table.insert(completions, completion)
			end
		end
	end

	if withCommands then
		addChildren("/bin/", true)
	end
	addChildren(filesystem.path(process.running().environment["PWD"], body))
	return completions
end

return shell