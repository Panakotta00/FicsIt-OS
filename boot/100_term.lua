local consoleLib = require("console")
local process = require("process")

local gpu = computer.getPCIDevices(findClass("GPU_T1_C"))[1]
local consoleBuffer = gpu:getBuffer()

terminal = process.create(function()
	console = consoleLib.createConsole()
	while true do
		console:tick()
		console:paint(consoleBuffer)
		gpu:setBuffer(consoleBuffer)
		gpu:flush()
		computer.skip()
		coroutine.yield()
		computer.skip()
	end
end)
