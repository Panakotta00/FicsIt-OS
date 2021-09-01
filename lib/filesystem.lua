local filesystemLib = {}

function filesystemLib.readAll(filestream)
	local eof = false
	local buf = ""
	local str
	while not eof do
		str = filestream:read(1024)
		if str then
			buf = buf .. str
		else
			eof = true
		end
	end
	return buf
end

return filesystemLib