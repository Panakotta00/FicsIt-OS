local util = {
	string = {}
}

function util.default(value, default)
	if value then
		return value
	else
		return default
	end
end

function util.override(class, field, override)
	if override then
		local func = class[field]
		class[field] = function(...)
			func(...)
			override(...)
		end
	else
		return function(...)
			class(...)
			override(...)
		end
	end
end

function util.tryCall(func, ...)
	if func then
		return func(...)
	end
end

function util.string.beginsWith(str, start)
   return str:sub(1, #start) == start
end

function util.string.endsWith(str, ending)
   return ending == "" or str:sub(-#ending) == ending
end

function util.findScriptPath(scriptPath, sysPath)
	local path = sysPath .. scriptPath
	if not filesystem.isFile(path) then
		path = path .. ".lua"
		if not filesystem.isFile(path) then
			return nil
		end
	end
	return path
end

function util.isArgumentFlag(arg)
	return arg:sub(1, 1) == "-"
end

function util.deepCopy(table)
	local newTable = {}
	for k, v in pairs(table) do
		if type(v) == "table" then
			v = util.deepCopy(v)
		end
		newTable[k] = v
	end
	return newTable
end

return util