local consoleLib = require("console")
local thread = require("thread")
local shell  = require("shell")
local process = require("process")

local gpu = computer.getPCIDevices(findClass("GPU_T1_C"))[1]
local consoleBuffer = gpu:getBuffer()

local console
local prog
local term
term = process.create(function()
	prog = process.create(function()
		local ishell = shell.createInteractiveShell()
		while true do
			ishell:tick()
		end
	end)
	process.createPipe(prog, term)
	process.createPipe(term, prog)
	console = consoleLib.createConsole()
	while true do
		console:tick()
		console:paint(consoleBuffer)
		gpu:setBuffer(consoleBuffer)
		gpu:flush()
		coroutine.yield()
		computer.skip()
	end
end)

while true do
	computer.skip()
	if console then
		console:handleInput(event.pull(0))
	end
	thread.tick()
end
