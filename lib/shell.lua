local math = require("math")
local console = require("console")
local util = require("util")
local thread = require("thread")
local process = require("process")

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
	local inString = ""
	local isEscape = 0
	for _, token in pairs(tokens) do
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
			end
		else
			if token.type == "text" then
				if isEscape > 0 then
					args[#args] = args[#args] .. token.data
				else
					table.insert(args, token.data)
				end
			elseif token.type == "quote" then
				inString = token.data
				table.insert(args, "")
			elseif token.type == "escape" then
				isEscape = true
			elseif token.type == "whitespace" and isEscape == 1 then
				args[#args] = args[#args] .. token.data
				isEscape = 2
			end
		end
	end
	return args
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
	local obj = {}
	
	function obj:tick()
		shell.write(process.running().environment["PWD"] .. " > ")
		local cmd = console.readLine()
		print("cmd:", cmd)
		--s, err, ret = pcall(function()
			shell.execute(cmd)
		--[[end)
		print(s, err, ret)
		if not s then
			print(s, err)
			shell.writeLine(err)
		end]]--
	end
	
	return obj
end

return shell