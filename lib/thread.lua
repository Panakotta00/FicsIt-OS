_thread = {
	threads = {},
	current = 0,
	runWithoutLimit = true,
}

local threadLib = {}

function threadLib.running(co)
	if not co then
		co = coroutine.running()
	end
	if not co then
		return nil
	end
	local running = threadLib.create(co)
	return running
end

function threadLib.create(func, ...)
	local thread
	if type(func) == "thread" then
		if _thread.threads[func] then
			return _thread.threads[func]
		end
		thread = {
			co = func,
			ignore = true,
			params = {...}
		}
	else
		thread = {
			co = coroutine.create(func),
			params = {...}
		}
	end

	if func ~= coroutine.running() then
		thread.parent = threadLib.running()
	end

	function thread:stop()
		table.remove(_thread.threads, _thread.threads[self])
		_thread.threads[self] = nil
		_thread.threads[self.co] = nil
		self.results = {}
	end
	
	function thread:status()
		return _thread.threads[self] and coroutine.status(self.co)
	end

	table.insert(_thread.threads, thread)
	_thread.threads[thread] = #_thread.threads
	_thread.threads[thread.co] = thread
	return thread
end

function threadLib.tick()
	if #_thread.threads > 0 then
		if _thread.current >= #_thread.threads then
			_thread.current = 0
			runWithoutLimit = true
		end
		_thread.current = _thread.current + 1
		local tickThread = _thread.threads[_thread.current]
		if not tickThread.ignore then
			local results = {coroutine.resume(true, tickThread.co, table.unpack(tickThread.params))}
			local success, e = results[1], results[2]
			if coroutine.status(tickThread.co) == "dead" then
				if not success then
					results[1] = -1
					local shell = require("shell")
					shell.write("Thread crashed!")
					shell.write(e)
					shell.write(debug.traceback(tickThread.co))
					print("Thread crashed!")
					print(e)
					print(debug.traceback(tickThread.co))
				else
					table.remove(results, 1)
					if #results < 1 then
						results[1] = 0
					end
				end
				tickThread.results = results
				tickThread:stop()
			elseif not success then
				runWithoutLimit = false
			end
		end
	end
	if _thread.current >= #_thread.threads then
		return runWithoutLimit
	end
	return false
end

function threadLib.mutex()
	local mutex = {
		queue = {},
		lockedBy = nil
	}
	
	function mutex:lock()
		local t = threadLib.running()
		if self.lockedBy then
			table.insert(self.queue, t)
			while self.lockedBy or self.queue[1] ~= t do
				coroutine.yield()
			end
		end
		self.lockedBy = t
		if self.queue[1] == t then
			table.remove(self.queue, 1)
		end
	end
	
	function mutex:unlock()
		local t = threadLib.running()
		if self.lockedBy and self.lockedBy ~= t then
			error("try to unlock mutex from other thread than locking thread")
		end
		self.lockedBy = nil
	end
	
	return mutex
end

return threadLib