local thread = require("thread")
local shell  = require("shell")
local process = require("process")

shell.getInput().isTTY = true
local prog = process.create(function()
	local ishell = shell.createInteractiveShell()
	while true do
		ishell:tick()
	end
end)

process.createPipe(prog, terminal)
process.createPipe(terminal, prog)

while true do
	computer.skip()
	if console then
		console:handleInput(event.pull(0))
	end
	computer.skip()
	thread.tick()
end
