_libCache = {}

function require(libName)
	local lib = _libCache[libName]
	if lib then
		return lib
	end
	local libPath = "/lib/" .. libName
	if not filesystem.isFile(libPath) then
		libPath = libPath .. ".lua"
		if not filesystem.isFile(libPath) then
			return nil
		end
	end
	print("Lib: load Lib '" .. libPath .. "'")
	local libFunc = filesystem.loadFile(libPath)
	if type(libFunc) ~= "function" then
		print("Lib: failed to load Lib '" .. libPath .. "'!")
		print(libFunc)
	else
		lib = libFunc()
		_libCache[libName] = lib
		return lib
	end
end


--local gui = require("gui")
--local eventLib = require("event")

--gui.getWindowManager().onMouseDown = function(wm, x, y, btn)
	--if btn == 1 then
--[[		local win = gui.createWindow("window with canvas", true)
		local x, y = 10, 10
		win.x = x - win.width/2
		win.y = y - win.height/2
		local canvas = gui.createCanvasPanel()
		local text = gui.createText("meep")
		text.width = 8
		canvas:addChild(text, 0, 0)
		local text2 = gui.createText("oh boy!")
		canvas:addChild(text2, 5, 2)
		local button = gui.createButton(function()
			print("hammer!")
			computer.beep()
		end, gui.createText("OK!"))
		button.name = "button"
		canvas:addChild(button, 10, 4)
		canvas.name = "canvas"
		win:setChild(canvas)
		win.name = "window"
		win:show()
--[[	elseif btn == 2 then
		local win = gui.createWindow("window with nothing", true)
		win.x = x - win.width/2
		win.y = y - win.height/2
		win:show()
	end
end]]--
--[[
local gpu = computer.getPCIDevices(findClass("GPU_T1_C"))[1]
local screen = computer.getPCIDevices(findClass("FINComputerScreen"))[1]
print(screen)
--screen = component.proxy(component.findComponent(findClass("Screen"))[1])
gpu:bindScreen(screen)
event.listen(gpu)

local lastDraw = computer.millis()
while true do
	local e = {event.pull(1)}
	while #e > 0 do
		eventLib.handleEvent(table.unpack(e))
		e = {event.pull(0)}
	end
	computer.skip()
	while eventLib.pull() do end
	computer.skip()
	local now = computer.millis()
	if now - lastDraw > 100 then
		gui.getWindowManager():paint()
		lastDraw = now
	end
end
]]--

local consoleLib = require("console")
local thread = require("thread")
local shell  = require("shell")
local process = require("process")

local gpu = computer.getPCIDevices(findClass("GPU_T1_C"))[1]
local screen = computer.getPCIDevices(findClass("FINComputerScreen"))[1]

gpu:bindScreen(screen)
event.listen(gpu)

local consoleBuffer = gpu:getBuffer()

process.create(coroutine.running())

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
