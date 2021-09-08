local thread = require("thread")
local shell  = require("shell")
local process = require("process")

shell.getInput().isTTY = true
local prog = process.create(filesystem.loadFile("/bin/shell.lua"))

process.createPipe(prog, terminal)
process.createPipe(terminal, prog)

while true do
	computer.skip()
	local canSleep = thread.tick()
	local timeout = 0
	if canSleep then
		timeout = 0.0
	end
	computer.skip()
	if console then
		console.process = prog
		console:handleInput(event.pull(timeout))
	end
end
