local mathLib = math


---Allows to make sure a given value is within a given range of values
---@param val number the value you want to clamp into range
---@param min number the lower limit of the value
---@param max number the upper limit of the value
---@return number the value clamped into the given range
function mathLib.clamp(val, min, max)
	return math.max(math.min(val, max), min)
end

return mathLib