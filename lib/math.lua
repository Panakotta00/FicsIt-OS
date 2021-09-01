local mathLib = math

function mathLib.clamp(val, min, max)
	return math.max(math.min(val, max), min)
end

return mathLib