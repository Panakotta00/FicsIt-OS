local shell = require("shell")
local process = require("process")

local inet = computer.getPCIDevices(findClass("FINInternetCard"))[1]

if not inet then
	shell.writeLine("Unable to get Internet Card!")
	return 1
end

local function getPaste(id)
	if not id:find("^[%w]+$") then
		shell.writeLine("'" .. id .. "' is not a valid pastebin id")
		return nil, 2
	end

	local request = inet:request("https://pastebin.com/raw/" .. id, "GET", "")
	s, text = request:await()
	if s ~= 200 then
		return nil, 3
	end
	return text
end

local args = {...}
local p = process.running()

local sub = args[1]
table.remove(args, 1)

if sub == "download" then
	local argc = 1
	local path
	if args[argc] == "-f" then
		argc = argc+1
		path = args[argc]
		argc = argc+1
		if not path then
			shell.write("-f flag given, excpects file path after it")
		end
	end
	local id = args[argc]
	argc = argc+1

	if not path then
		path = id
	end

	path = filesystem.path(p.environment["PWD"], path)

	text, e = getPaste(id)
	if not text then
		return e
	end
	if path then
		local f = filesystem.open(path, "w")
		f:write(text)
		f:close()
	else
		shell.writeLine(text)
	end
end

if sub == "run" then
	local id = args[2]
	text, e = getPaste(id)
	if not text then
		return e
	end
	local f = filesystem.open("/tmp.lua", "w")
	f:write(text)
	f:close()
	local f = filesystem.loadFile("tmp.lua")
	print(f)
	f()
end

return 0