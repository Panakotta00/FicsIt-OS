local shell = require("shell")
local process = require("process")
local buffer = require("buffer")
local json = require("json")
local packageLib = require("package")

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
	if source.content then
		func(source.content)
	elseif source.type == "paste" then
		requestPaste(source.paste, func)
	elseif source.type == "url" then
		requestCode(source.url, func)
	end
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


local function savePackage(package)
	local copy = packageLib.convertPackageToSaved(package)
	filesystem.createDir("/.pastebin")
	local file = filesystem.open(filesystem.path("/.pastebin", copy.id .. ".json"), "w")
	file:write(json.encode(copy))
	file:close()
end

local function loadEvents(package, event)
	local function sourceVisitor(source)
		requestSource(source, function(data)
			source.content = data
		end)
	end
	
	packageLib.visitEvents(package, event, "pre", sourceVisitor)
	packageLib.visitEvents(package, event, "post", sourceVisitor)
	doAllRequests()
end

local function install(id)
	local packageScript = getPaste(id)
	local parser = packageLib.createPackageParser(id)
	parser:parse(packageScript)
	local package = parser.package
	
	loadEvents(package, "install")
	local function doSourceVisitor(source)
		local event = load(source.content)
		event()
	end
	
	-- call pre events
	packageLib.visitEvents(package, "install", "pre", doSourceVisitor)
	
	-- do folders
	table.sort(package.folders, function(f1, f2)
		return f1.path < f2.path
	end)
	for _, folder in pairs(package.folders) do
		filesystem.createDir(folder.path)
	end
	
	-- do files
	table.sort(package.files, function(f1, f2)
		return f1.path < f2.path
	end)
	for _, file in pairs(package.files) do
		print(file.path)
		requestSource(file, function(data)
			local file = filesystem.open(file.path, "w")
			file:write(data)
			file:close()
		end)
	end
	doAllRequests()
	
	-- call post
	packageLib.visitEvents(package, "install", "post", doSourceVisitor)
	
	-- save package
	savePackage(package)
end

local function uninstall(id)
	local path = filesystem.path("/.pastebin", id .. ".json")
	if not filesystem.isFile(path) then
		error("package '" .. id .. "' not yet installed")
	end
	local f = buffer.create("r", filesystem.open(path, "r"))
	local packageData = f:read("a")
	f:close()
	local package = json.decode(packageData)
	
	loadEvents(package, "uninstall")
	local function doSourceVisitor(source)
		local event = load(source.content)
		event()
	end
	
	-- call pre events
	packageLib.visitEvents(package, "uninstall", "pre", doSourceVisitor)
	
	-- remove files
	table.sort(package.files, function(f1, f2)
		return f1.path > f2.path
	end)
	for _, file in pairs(package.files) do
		filesystem.remove(file.path)
	end
	
	-- remove folder
	table.sort(package.folders, function(f1, f2)
		return f1.path > f2.path
	end)
	for _, folder in pairs(package.folders) do
		filesystem.remove(folder.path)
	end
	
	-- call post events
	packageLib.visitEvents(package, "uninstall", "post", doSourceVisitor)
	
	-- remove package cache
	filesystem.remove(path)
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