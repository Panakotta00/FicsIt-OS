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

local function nextToken(text)
	local start, stop = text:find("^[%c ]+")
	if start then
		return text:sub(stop+1), "whitespace", text:sub(start, stop)
	end
	local start, stop = text:find("^[\"'`]")
	if start then
		return text:sub(stop+1), "quote", text:sub(start, stop)
	end
	local start, stop = text:find("^\"")
	if start then
		return text:sub(stop+1), "escape", "\\"
	end

	local start, stop = text:find("^[^%c\"' ]+")
	if start then
		return text:sub(stop+1), "text", text:sub(start, stop)
	end
	return text, "none", ""
end

local function tokenize(cmd)
	local tokens = {}
	while cmd:len() > 0 do
		cmd, token, tokendata = nextToken(cmd)
		table.insert(tokens, {type = token, data = tokendata})
	end
	return tokens
end

local function parseArgs(tokens)
	local args = {}
	local textRanges = {}
	local inString = ""
	local isEscape = 0
	local len = 0
	for _, token in pairs(tokens) do
		len = len + token.data:len()
		if inString:len() > 0 then
			if token.type == "quote" and token.data == inString and isEscape <= 0 then
				inString = ""
			else
				if token.type == "escape" then
					isEscape = 1
				else
					isEscape = 0
				end
				args[#args] = args[#args] .. token.data
				textRanges[#textRanges].stop = len
				textRanges[#textRanges].start = len - args[#args]:len()
			end
		else
			if token.type == "text" then
				if isEscape > 0 then
					args[#args] = args[#args] .. token.data
					textRanges[#textRanges].stop = len
					textRanges[#textRanges].start = len - args[#args]:len()
				else
					table.insert(args, token.data)
					table.insert(textRanges, {start = len - token.data:len(), stop = len})
					last = len
				end
			elseif token.type == "quote" then
				inString = token.data
				table.insert(args, "")
				table.insert(textRanges, {start = len, stop = len})
				last = len
			elseif token.type == "escape" then
				isEscape = true
			elseif token.type == "whitespace" and isEscape == 1 then
				args[#args] = args[#args] .. token.data
				textRanges[#textRanges].stop = len
				textRanges[#textRanges].start = len - args[#args]:len()
				isEscape = 2
			end
		end
	end
	return args, textRanges
end

local function toArg(string)
	return string:gsub(" ", "\\ ")
end

function shell.execute(cmd)
	local tokens = tokenize(cmd)
	local args = parseArgs(tokens)
	if #args < 1 then
		return
	end
	local progName = args[1]
	table.remove(args, 1)

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
		shell.writeLine("Unable to load program")
		return -2
	end
	return prog(table.unpack(args))
end

function shell.createInteractiveShell()
	local obj = {
		historyOffset = -1,
		maxHistoryOffset = 0,
	}

	function obj:getHistoryPath()
		return process.running().environment["shell_history"] or "/.shell_history"
	end

	function obj:getHistory(offset)
		offset = offset or self.historyOffset
		if not filesystem.isFile(self:getHistoryPath()) then
			return ""
		end
		local file = buffer.create("r", filesystem.open(self:getHistoryPath(), "r"))
		local history = {}
		for line in file:lines() do
			table.insert(history, line)
		end
		file:close()
		self.maxHistoryOffset = #history - 1
		return history[#history - offset] or ""
	end

	function obj:addHistory(cmd)
		local o_cmd = self:getHistory(0)
		if o_cmd == cmd then
			return
		end
		local file = filesystem.open(self:getHistoryPath(), "a")
		file:write(cmd .. "\n")
		file:close()
		self.maxHistoryOffset = self.maxHistoryOffset + 1
	end
	
	function obj:tick()
		shell.write(process.running().environment["PWD"] .. " > ")
		local tabIndex = 0
		local prevTab = nil
		local prevPath = nil
		local tabsProgs = false
		local cmd = console.readLine(shell.getInput(), shell.getOutput(), function(arg, text, off, token, data)
			if arg == 0 then
				if token == "text" then
					if data == "\t" then
						tabIndex = tabIndex + 1
						local args, ranges = parseArgs(tokenize(text))
						local arg = args[#args] or ""
						local path = prevPath or arg:match(".*/") or ""
						local name = prevTab or arg:match("[^/]*$")
						prevTab = name
						prevPath = path
						local f_path = filesystem.path(process.running().environment["PWD"], path)
						if #args < 1 or (#args == 1 and path:len() < 1)or tabsProgs then
							tabsProgs = true
							path = ""
							f_path = "/bin/"
						end
						local i = 0
						local children = filesystem.childs(f_path)
						table.sort(children)
						for _, child in pairs(children) do
							local m1, m2 = child:match("^(" .. name .. ")(.*)$")
							if m1 then
								i = i + 1
								if tabIndex == i then
									if tabsProgs then
										child = filesystem.path(4, child)
									end
									return false, true, text:sub(1, (ranges[#ranges] or {}).start or 0) .. toArg(path .. child), 0
								end
							end
						end
						tabIndex = 0
						return false, true, text:sub(1, (ranges[#ranges] or {}).start or 0) .. toArg(path .. name), 0
					end
				end
				prevTab = nil
				prevPath = nil
				tabsProgs = false
				tabIndex = 0
				if token == "csi" then
					if data.c == "A" then
						self.historyOffset = math.min(self.maxHistoryOffset, self.historyOffset + 1)
						return false, true, self:getHistory(), 0
					elseif data.c == "B" then
						self.historyOffset = math.max(0, self.historyOffset - 1)
						return false, true, self:getHistory(), 0
					end
				end
			end
			return true, false, text, off
		end)
		self:addHistory(cmd)
		self.historyOffset = -1
		s, err, ret = pcall(function()
			shell.execute(cmd)
		end)
		print(s, err, ret)
		if not s then
			print(s, err)
			shell.writeLine(err)
		end
	end

	obj:getHistory()
	
	return obj
end

return shell