local process = require("process")
local shell = require("shell")

local args = {...}
local p = process.running()

for _, arg in pairs(args) do
	local path = filesystem.path(p.environment["PWD"], arg)
	filesystem.open(path, "w"):close()
end