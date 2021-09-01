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
filesystem.mount("/dev/" .. drive, "/")
 
filesystem.doFile("/boot/run.lua")