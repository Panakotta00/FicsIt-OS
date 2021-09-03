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

local function nextToken(str)
	local pos = str:find("[%s\"'\\]")
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
	return str:sub(pos+1), "whitespace", c
end

local function parseArgs(inst)
	local args = {}
	local argsMeta = {}
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

local function toArg(string)
	return string:gsub(" ", "\\ ")
end

function shell.execute(cmd)
	local args, argsMeta = parseArgs(cmd)
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
		shell.writeLine("Unable to load program\n" .. prog)
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
		status_code, err, ret = (xpcall or pcall)(function()
			shell.execute(cmd)
		end)
		print(status_code, err, ret)
		if not status_code then
			print(status_code, err)
			shell.writeLine(err.message .. "\n" .. (err.trace or ""))
		end
	end

	obj:getHistory()
	
	return obj
end

return shell