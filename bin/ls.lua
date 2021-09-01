local shell = require("shell")
local process = require("process")
local console = require("console")

local args = {...}
local p = process.running()

local path = filesystem.path(p.environment["PWD"], args[1] or "")
local children = filesystem.childs(path)
table.sort(children)

if shell.getOutput().isTTY then
	local maxLen = 0
	for _, child in pairs(children) do
		maxLen = math.max(maxLen, child:len()+1)
	end
	shell.write("\x1B[6n\x1b[999;999H\x1B[6n")
	local startY, startX = console.readTillCPR(shell.getInput())
	local height, width = console.readTillCPR(shell.getInput())
	shell.write("\x1B[" .. startY .. ";" .. startX .. "H\x1B[J")
	local maxPerLine = width / maxLen
	local newLine = false
	for i, child in pairs(children) do
		shell.write(child .. string.rep(" ", maxLen - child:len()))
		if i % maxPerLine == 0 then
			shell.write("\r\n")
			newLine = true
		else
			newLine = false
		end
	end
	if not newLine then
		shell.write("\r\n")
	end
else
	for _, child in pairs(children) do
		shell.write(child .. "\n")
	end
end