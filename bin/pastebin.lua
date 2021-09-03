local shell = require("shell")
local process = require("process")
local buffer = require("buffer")
local json = require("json")

local inet = computer.getPCIDevices(findClass("FINInternetCard"))[1]

if not inet then
	shell.writeLine("Unable to get Internet Card!")
	return 1
end

local requests = {}

---enqueues the request in the requests list, allows for parallel data requests making requesting a package faster
---@param url string the url to the data that has to be requested
---@param func function the function that will be called afterwards and takes the requested data as input
local function requestCode(url, func)
	local request = inet:request(url, "GET", "")
	table.insert(requests, {request=request, func=func})
end

---tries to fetch the url directly and returns the data if present, nil if failed to fetch
---@param url string the url of the data you want to request
local function getCode(url)
	local request = inet:request(url, "GET", "")
	status_code, text = request:await()
	if status_code ~= 200 then
		error("unable to fetch '" .. url .. "', responds with code " .. status_code)
	end
	return text
end

---checks the provided id for validity and requests its contents right away
---@param id string the paste-id you want to request
local function requestPaste(id, func)
	if not id:find("^%w+$") then
		error("'" .. id .. "' is not a valid pastebin id")
	end
	
	requestCode("https://pastebin.com/raw/" .. id, func)
end

---checks the provided id for validity and requests its contents right away
---@param id string the paste-id you want to request
local function getPaste(id)
	if not id:find("^%w+$") then
		error("'" .. id .. "' is not a valid pastebin id")
	end

	return getCode("https://pastebin.com/raw/" .. id)
end

local function requestSource(source, func)
	if source.type == "inline" then
		func(source.content)
	elseif source.type == "paste" then
		requestPaste(source.paste, func)
	elseif source.type == "url" then
		requestCode(source.url, func)
	end
end

local instructionPattern = "^--FIOS"
local metaPattern = "^--FIOS%s+(%a+):%s+([%w%p%s]+)%s*$"
local eventPattern = "^--FIOS%s+event%s+(%a+)%s+(%a+)%s*(.*)%s*$"
local filePattern = "^--FIOS%s+file%s+\"(.+)\"%s+(.+)%s*$"
local sourcePattern = "^%s*(%a+)%s*(.*)%s*$"

local function doSource(src)
	local source = {}
	local type, data = src:match(sourcePattern)
	source.type = type
	if type == "inline" then
		source.contents = {}
		return source, source
	elseif type == "paste" then
		source.paste = data
		if not data:find("^%w+$") then
			error("paste-id is invalid")
		end
		return source
	elseif type == "url" then
		source.url = data
		return source
	end
end

local function parsePackage(id, packageScript)
	local stream = buffer.create("r", buffer.stringstream(packageScript))
	local package = {
		id = id,
		meta = {},
		events = {},
		files = {}
	}
	local item = nil
	local sources = {}
	for line in stream:lines() do
		local instruction = line:find(instructionPattern)
		if instruction then
			item = nil
			local done = false
			if not done then
				local key, data = line:match(metaPattern)
				if key then
					done = true
					package.meta[key] = data
				end
			end
			if not done then
				local step, event, src = line:match(eventPattern)
				if step then
					done = true
					if (step == "pre" or step == "post") and (event == "install" or event == "uninstall" or event == "upgrade") then
						local source
						source, item = doSource(src)
						
						local eventTbl = package.events[event] or {}
						package.events[event] = eventTbl
						
						local stepTbl = eventTbl[step] or {}
						eventTbl[step] = stepTbl
						
						table.insert(stepTbl, source)
						table.insert(sources, source)
					end
				end
			end
			if not done then
				local file, src = line:match(filePattern)
				if file then
					done = true
					local source
					source, item = doSource(src)
					package.files[file] = source
					table.insert(sources, source)
				end
			end
		elseif item then
			table.insert(item.contents, line)
		end
	end
	for _, source in pairs(sources) do
		if source.contents then
			source.content = table.concat(source.contents, "\n")
			source.contents = nil
		end
	end
	return package
end

local function doAllRequests()
	while #requests > 0 do
		local i = 1
		while i <= #requests do
			local request = requests[i]
			if request.request:canGet() then
				local status_code, data = request.request:get()
				if status_code ~= 200 then
					error("unable to fetch data, response with status code " .. status_code)
				end
				request.func(data)
				table.remove(requests, i)
				i = i - 1
			end
			i = i + 1
		end
	end
end

local function loadEvents(package)
	local sources = {}
	for _, event in pairs(package.events) do
		for _, step in pairs(event) do
			for _, item in pairs(step) do
				requestSource(item, function(data)
					sources[item] = data
				end)
			end
		end
	end
	doAllRequests()
	return sources
end

local function savePackage(package)
	for _, file in pairs(package.files) do
		if file.type == "inline" then
			file.content = nil
		end
	end
	filesystem.createDir("/.pastebin")
	local file = filesystem.open(filesystem.path("/.pastebin", package.id .. ".json"), "w")
	file:write(json.encode(package))
	file:close()
end

local function install(id)
	local packageScript = getPaste(id)
	local package = parsePackage(id, packageScript)
	
	local eventSources = loadEvents(package)
	if package.events.install and package.events.install.pre then
		for _, e in pairs(package.events.install.pre) do
			local func = load(eventSources[e])
			func()
		end
	end
	
	for path, source in pairs(package.files) do
		requestSource(source, function(data)
			local file = filesystem.open(path, "w")
			file:write(data)
			file:close()
		end)
	end
	doAllRequests()
	
	if package.events.install and package.events.install.post then
		for _, e in pairs(package.events.install.post) do
			local func = load(eventSources[e])
			func()
		end
	end
	
	savePackage(package)
end

local function uninstall(id)
	local path = filesystem.path("/.pastebin", id .. ".json")
	if not filesystem.isFile(path) then
		error("package '" .. id .. "' not yet installed")
	end
	local file = buffer.create("r", filesystem.open(path, "r"))
	local packageData = file:read("a")
	file:close()
	local package = json.decode(packageData)
	
	local eventSources = loadEvents(package)
	if package.events.uninstall and package.events.uninstall.pre then
		for _, e in pairs(package.events.uninstall.pre) do
			local func = load(eventSources[e])
			func()
		end
	end
	
	for path in pairs(package.files) do
		filesystem.remove(path)
	end
	
	if package.events.uninstall and package.events.uninstall.post then
		for _, e in pairs(package.events.uninstall.post) do
			local func = load(eventSources[e])
			func()
		end
	end
end

local args = {...}
local p = process.running()

local sub = args[1]
table.remove(args, 1)

if sub == "download" then
	local argc = 1
	local path
	if args[argc] == "-f" then
		argc = argc+1
		path = args[argc]
		argc = argc+1
		if not path then
			shell.write("-f flag given, excpects file path after it")
		end
	end
	local id = args[argc]
	argc = argc+1

	if not path then
		path = id
	end

	path = filesystem.path(p.environment["PWD"], path)

	text, e = getPaste(id)
	if not text then
		return e
	end
	if path then
		local f = filesystem.open(path, "w")
		f:write(text)
		f:close()
	else
		shell.writeLine(text)
	end
elseif sub == "run" then
	local id = args[2]
	text, e = getPaste(id)
	if not text then
		return e
	end
	local f = filesystem.open("/tmp.lua", "w")
	f:write(text)
	f:close()
	local f = filesystem.loadFile("tmp.lua")
	f()
elseif sub == "install" then
	local id = args[1]
	if not id then
		shell.writeLine("no paste-id given to install!")
		return 1
	end
	install(id)
elseif sub == "uninstall" then
	local id = args[1]
	if not id then
		shell.writeLine("no paste-id given to install!")
		return 1
	end
	uninstall(id)
end

return 0