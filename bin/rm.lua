local process = require("process")
local util = require("util")
local shell = require("shell")

local p = process.running()
local paths = {}
local recursive = false

for _, arg in pairs({...}) do
	if util.isArgumentFlag(arg) then
		if arg == "-r" then
			recursive = true
		else
			shell.writeLine("Unknown argument flag '" .. arg .. "'")
			return 2
		end
	else
		table.insert(paths, arg)
	end
end

function remove(path)
	if filesystem.isDir(path) then
		if recursive then
			for _, child in pairs(filesystem.childs(path)) do
				remove(filesystem.path(path, child))
			end
		else
			shell.writeLine("Unable to remove folder. Use '-r' to enable recursive remove.")
			return 3
		end
	end
	if filesystem.remove(path) then
		shell.writeLine("'" .. filesystem.path(1, path) .. "' removed")
	else
		shell.writeLine("Unable to remove '" .. filesystem.path(1, path) .. "'")
	end
end

for _, path in pairs(paths) do
	local path = filesystem.path(p.environment["PWD"], path)

	remove(path)
end
