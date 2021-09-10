local shell = require("shell")

local args = {...}

local cmd = args[1]

local function getService(id)
	local service = _systemd.services[id]
	if not service then
		error("No service with id '" .. id .. "' found")
	end
	return service
end

if cmd == "status" then
	local id = args[2]
	local service = getService(id)
	
	local isRunning = service:status()
	
	if isRunning then
		shell.writeLine("The service '" .. id .. "' is currently running")
	else
		shell.writeLine("The service '" .. id .. "' is currently NOT running")
	end
	return 0
elseif cmd == "start" then
	local id = args[2]
	local service = getService(id)
	
	service:start()
elseif cmd == "stop" then
	local id = args[2]
	local service = getService(id)
	
	service:stop()
elseif cmd == "restart" then
	local id = args[2]
	local service = getService(id)
	
	service:restart()
end