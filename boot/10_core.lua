_libCache = {}

function require(libName)
	local lib = _libCache[libName]
	if lib then
		return lib
	end
	local libPath = "/lib/" .. libName
	if not filesystem.isFile(libPath) then
		libPath = libPath .. ".lua"
		if not filesystem.isFile(libPath) then
			return nil
		end
	end
	print("Lib: load Lib '" .. libPath .. "'")
	local libFunc = filesystem.loadFile(libPath)
	if type(libFunc) ~= "function" then
		print("Lib: failed to load Lib '" .. libPath .. "'!")
		print(libFunc)
	else
		lib = libFunc()
		_libCache[libName] = lib
		return lib
	end
end

local process = require("process")

process.create(coroutine.running())