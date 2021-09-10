local oldYield = coroutine.yield

coroutine.yield = function(...)
	oldYield(false, ...)
end

function coroutine.skip()
	oldYield(true)
end
