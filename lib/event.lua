local eventLib = {}
_eventSubscriptions = {}
_eventThreadQueues = {}

function getRunningThread()
	local thread, main = coroutine.running()
	if main then
		return "main"
	end
	return thread
end

local function getThreadQueue(thread, create)
	local queue = _eventThreadQueues[thread]
	if not queue and create then
		queue = {}
		_eventThreadQueues[thread] = queue
	end
	return queue
end

local function pushEventToThread(thread, name, sender, ...)
	local queue = getThreadQueue(thread, true)
	if queue then
		table.insert(queue, {name, sender, ...})
	end
end

local function getSubscriptionListOfCurrentThread(name)
	local subThreads = _eventSubscriptions[name]
	if not subThreads then
		subThreads = {}
		_eventSubscriptions[name] = subThreads
	end
	local funcList = subThreads[getRunningThread()]
	if not funcList then
		funcList = {}
		subThreads[getRunningThread()] = funcList
	end
	return funcList
end

function eventLib.subscribe(name, func)
	local sub = getSubscriptionListOfCurrentThread(name)
	table.insert(sub, func)
end

function eventLib.handleEvent(name, sender, ...)
	if not name or not sender then
		return
	end
	print(name)
	local sub = _eventSubscriptions[name]
	if not sub then return end
	for thread, _ in pairs(sub) do
		pushEventToThread(thread, name, sender, ...)
	end
end

function eventLib.callSubscriprions(name, ...)
	local subs = getSubscriptionListOfCurrentThread(name)
	for _, v in pairs(subs) do
		v(...)
	end
end

function eventLib.pull()
	local queue = getThreadQueue(getRunningThread(), false)
	if not queue or #queue < 1 then
		return nil
	else
		local event = queue[1]
		table.remove(queue, 1)
		eventLib.callSubscriprions(table.unpack(event))
		return table.unpack(event)
	end
end

return eventLib