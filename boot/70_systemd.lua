local process = require("process")
local json = require("json")
local buffer = require("buffer")
local util = require("util")

_systemd = {}

---@type table<string, Service>
_systemd.services = {}

---@class Service
---@field public id string the name/id of the service
---@field public enabled boolean true if the service should be automatically started on system boot
---@field private file string path to the script file of this service
---@field private messageLog string[] array of log message strings
---@field private process Process|nil process of the service
local Service = {}

---creates a new service from a given unit description
---@return Service
function Service.new(unit)
	local serv = {}
	
	serv.id = unit.id
	serv.enabled = unit.enabled or false
	serv.file = unit.file
	serv.messageLog = {}
	
	setmetatable(serv, Service)
	Service.__index = Service
	return serv
end

---adds the given log message to the message log of the service
function Service:log(verbosity, msg)
	table.insert(self.messageLog, msg)
end

---if service is a string trys to find the service with that string as name and returns it, otherwise returns the argument
function Service:getService(service)
	if type(service) == "string" then
		service = _systemd.services[service]
	end
	if not service then
		error("no valid service '" .. tostring(service) .. "' given")
	end
	return service
end

---returns the status of the process
---@return boolean true if the service is currently running
function Service:status()
	return self.process and self.process:isRunning()
end

---starts the service
function Service:start()
	if self:status() then
		return 0
	end
	
	local prog, err = filesystem.loadFile(self.file)
	if not prog then
		self:log("error", "Unable to start service file with error:")
		self:log("error", err)
		return -1
	end
	
	self.process = process.create(prog)
	
	return 0
end

---stops the service
function Service:stop()
	if not self:status() then
		return 0
	end
	self.process:kill()
end

---restarts the service
function Service:restart()
	self:stop()
	self:start()
end

local function loadUnit(unit)
	local service = Service.new(unit)
	_systemd.services[service.id] = service
	
	if service.enabled then
		service:start()
	end
end

local function reloadUnits()
    if not filesystem.exists("/etc/systemd.json") then
        local file = filesystem.open("/etc/systemd.json")
        file:write("{}")
        file:close()
    end
	local configFile = buffer.create("r", filesystem.open("/etc/systemd.json"))
	local config = json.decode(configFile:read("a"))
	configFile:close()
	
	for id, unit in pairs(config.services or {}) do
		unit.id = id
		loadUnit(unit)
	end
end

reloadUnits()
