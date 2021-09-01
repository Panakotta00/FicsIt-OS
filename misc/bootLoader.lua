event.ignoreAll()
event.clear()
 
filesystem.initFileSystem("/dev")
 
local drive = ""
for _,f in pairs(filesystem.childs("/dev")) do
	if not (f == "serial") then
 		drive = f
		break
	end
end
if drive:len() < 1 then
	print("ERROR! Failed to find filesystem! Please insert a drive or floppy with FicsIt-OS installed!")
	computer.beep(0.2)
	return
end
filesystem.mount("/dev/" .. drive, "/")
 
func = filesystem.loadFile("/boot/run.lua")

if func then
	computer.beep(5)
	func()
end