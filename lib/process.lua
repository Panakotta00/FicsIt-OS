local thread = require("thread")
local buffer = require("buffer")
local util = require("util")

_process = {
	processes = {},
	processIDs = {},
}

local process = {}

process.SIGINT = 0

function process.serialStream()
	local stream = {
		buffer = ""
	}
	
	function stream:write(msg)
		self.buffer = self.buffer .. msg
		local startPos, endPos
		while self.buffer:len() > 0 do
			startPos, endPos = self.buffer:find("\n")
			if not startPos then
				break
			end
			self.buffer = self.buffer:sub(startPos+1)
		end
	end
	
	function stream:read()
		return nil
	end
	
	function stream:seek() end
	
	return stream
end

function process.generatePID()
	return (_process.processIDs[#_process.processIDs] or 0) + 1
end

function process.createEnvironment(process)
	local environment = {}
	if process.parent then
		for k, v in pairs(process.parent.environment) do
			environment[k] = v
		end
	else
		environment["PWD"] = "/"
		environment["BIN"] = "/bin"
		environment["LIB"] = "/lib"
	end
	process.environment = environment
end

function process.create(func, ...)
	local p, index
	if type(func) == "thread" then
		index = _process.processes[func]
		if index then
			return _process.processes[index]
		end
		p = {
			mainThread = thread.create(func, ...)
		}
	else
		p = {
			mainThread = thread.create(func, ...)
		}
	end
	
	p.parent = process.running()
	p.signalHandlers = {}
	p.signalHandlers[process.SIGINT] = function(proc)
		proc:kill()
	end

	process.createEnvironment(p)
	
	if p.parent then
		p.stdInput = p.parent.stdInput
		p.stdOutput = p.parent.stdOutput
		p.environment = util.deepCopy(p.environment)
	else
		local stream = process.serialStream()
		p.stdInput = buffer.create("r", stream)
		p.stdOutput = buffer.create("w", stream)
	end

	table.insert(_process.processes, p)
	_process.processes[p.mainThread.co] = #_process.processes
	
	function p:isRunning()
		local status = self.mainThread:status()
		return status == "suspended" or status == "running"
	end
	
	function p:await()
		while self:isRunning() do
			coroutine.yield()
		end
	end
	
	function p:kill()
		p.mainThread:stop()
		table.remove(_process.processes, _process.processes[p.mainThread.co])
		_process.processes[p.mainThread.co] = nil
	end
	
	function p:triggerSignal(signal)
		local handler = self.signalHandlers[signal]
		if handler then
			handler(self)
		end
	end

	return p
end

function process.running(co)
	if not co then
		co = coroutine.running()
	end
	local index = _process.processes[co]
	local t = thread.running(co)
	while not index do
		if not t then
			return nil
		end
		t = t.parent
		if t then
			index = _process.processes[t.co]
		end
	end
	return _process.processes[index]
end

local function createPipeStream()
	local stream = {
		buffer = ""
	}
	
	function stream:write(data)
		self.buffer = self.buffer .. data
	end
	
	function stream:read(length)
		local str = self.buffer:sub(1, length)
		self.buffer = self.buffer:sub(length+1)
		return str
	end
	
	function stream:seek() end
	
	return stream
end

function process.createPipe(from, to)
	local stream = createPipeStream()
	stream.isTTY = to.stdInput.isTTY
	from.stdOutput = stream
	to.stdInput = stream
	from.stdOutput.mutex = to.stdInput.mutex
end

function process.getProcesses()
	local ids = {}
	for id in pairs(_process.processIDs) do
		table.insert(ids, id)
	end
	return ids
end

function process.getProcessByID(pid)
	return _process.processes[_process.processIDs[pid]]
end

return process