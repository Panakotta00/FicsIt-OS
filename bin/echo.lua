local shell = require("shell")

local args = {...}

shell.write(table.concat(args, " "))

if shell.getOutput().isTTY then
	shell.write("\n")
end