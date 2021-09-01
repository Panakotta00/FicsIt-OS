local shell = require("shell")
local process = require("process")

local args = {...}
local p = process.running()

local path = filesystem.path(p.environment["PWD"], args[1] or "")
print(path)
local children = filesystem.childs(path)

for _, child in pairs(children) do
	shell.write(child .. "\n")
end
