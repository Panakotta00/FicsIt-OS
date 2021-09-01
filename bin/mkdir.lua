local process = require("process")
local shell = require("shell")

local args = {...}
local p = process.running()

if #args < 1 then
	shell.write("Require at least one argument as path to the directory you want to create")
	return 1
end

local path = filesystem.path(p.environment["PWD"], args[1])
filesystem.createDir(path)
