local process = require("process")
local shell = require("shell")
local fs = require("filesystem")

local args = {...}
local p = process.running()

for _, arg in pairs(args) do
	local path = filesystem.path(p.environment["PWD"], arg)
	local f = filesystem.open(path, "r")
	shell.write(fs.readAll(f))
	f:close()
if shell.getOutput().isTTY then
	shell.write("\n")
end
end

