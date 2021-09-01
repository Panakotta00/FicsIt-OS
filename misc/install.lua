computer.beep(5.0)
print("Load internet...")
internet = computer.getPCIDevices(findClass("FINInternetCard"))[1]
if not internet then
	print("ERROR! No internet-card found! Please install a internet card!")
	computer.beep(0.2)
	return
end

print("Load filesystem...")
filesystem.initFileSystem("/dev")

local drive = ""
for _,f in pairs(filesystem.childs("/dev")) do
	if not (f == "serial") then
		drive = f
		break
	end
end
if drive:len() < 1 then
	print("ERROR! Unable to find filesystem to install on! Please insert a drive or floppy!")
	computer.beep(0.2)
	return
end
filesystem.mount("/dev/" .. drive, "/")

requests = {}

function requestFile(url, path)
	print("Requests file '" .. path .. "' from '" .. url .. "'")
	local request = internet:request(url, "GET", "")
	table.insert(requests, {
		request = request,
		func = function(req)
			print("Write file '" .. path .. "'")
			local file = filesystem.open(path, "w")
			local code, data = req:get()
			if code ~= 200 or not data then
				print("ERROR! Unable to request file '" .. path .. "' from '" .. url .. "'")
				return false
			end
			file:write(data)
			file:close()
			return true
		end
	})
end

local tree = {
	"/",
	{
		"boot",
		{"10_core.lua"},
		{"50_gpu.lua"},
		{"100_shell.lua"},
		{"120_gui.lua"},
		{"run.lua"}
	},
	{
		"bin",
		{"cat.lua"},
		{"cd.lua"},
		{"clear.lua"},
		{"ls.lua"},
		{"mkdir.lua"},
		{"pastebin.lua"},
		{"rm.lua"},
		{"touch.lua"}
	},
	{
		"lib",
		{"buffer.lua"},
		{"console.lua"},
		{"event.lua"},
		{"filesystem.lua"},
		{"gui.lua"},
		{"math.lua"},
		{"process.lua"},
		{"shell.lua"},
		{"thread.lua"},
		{"util.lua"}
	}
}

function doEntry(parentPath, entry)
	if #entry == 1 then
		doFile(parentPath, entry)
	else
		doFolder(parentPath, entry)
	end
end

function doFile(parentPath, file)
	local path = filesystem.path(parentPath, file[1])
	requestFile("https://raw.githubusercontent.com/Panakotta00/FicsIt-OS/main/" .. path, path)
end

function doFolder(parentPath, folder)
	local path = filesystem.path(parentPath, folder[1])
	table.remove(folder, 1)
	filesystem.createDir(path)
	for _, child in pairs(folder) do
		doEntry(path, child)
	end
end

print("Process folder struct...")
doFolder("", tree)

print("Loading files...")
while #requests > 0 do
	local i = 1
	while i <= #requests do
		local request = requests[i]
		if request.request:canGet() then
			table.remove(requests, i)
			local done = request.func(request.request)
			if not done then
				computer.beep(0.2)
				return
			end
		end
		i = i + 1
	end
end

print("Request EEPROM BIOS...")
code, data = internet:request("https://raw.githubusercontent.com/Panakotta00/FicsIt-OS/main/misc/bootLoader.lua", "GET", ""):await()
if code ~= 200 or not data then
	print("ERROR! Failed to request EEPROM BIOS from 'https://raw.githubusercontent.com/Panakotta00/FicsIt-OS/main/misc/bootLoader.lua'")
	computer.beep(0.2)
	return
end

event.ignoreAll()
event.clear()
print("YOU HAVE TO CLOSE THE WINDOW with-in 10sec till the high beeps!")
for i=0, 10, 1 do
	event.pull(1)
	print(i .. "...")
	computer.beep(0.7)
end

print("Install EEPROM BIOS...")
computer.setEEPROM(data)

for i=0, 3, 1 do
	computer.beep(1.5)
	event.pull(0.2)
end

print("Installation Complete!")