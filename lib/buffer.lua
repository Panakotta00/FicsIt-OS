local bufferLib = {}

function bufferLib.create(mode, stream)
	local buffer = {
		stream = stream,
		buffer = "",
		isTTY = stream.isTTY
	}
	
	local function readAll(self)
		while self:readChunk() do end
		local buf = self.buffer
		self.buffer = ""
		return buf
	end
	
	local function readLine(self)
		local line = ""
		while self.buffer:len() > 0 or self:readChunk() do
			local startPos = self.buffer:find("\r\n")
			local len = 2
			if not startPos then
				len = 1
				startPos = self.buffer:find("\n")
			end
			if startPos and self.buffer:len() > 0 then
				line = line .. self.buffer:sub(1, startPos-1)
				self.buffer = self.buffer:sub(startPos+len)
				break
			else
				line = line .. self.buffer
				self.buffer = ""
			end
		end
		return line
	end
	
	local function readNumber(self)
		local numberStr = ""
		local startPos, endPos
		local signage = "[+-]*"
		local decimal = "[%d]+[.]"
		local pattern, str
		while self.buffer:len() > 0 or self:readChunk() do
			pattern = "^" .. signage .. decimal .. "[%d]+"
			startPos, endPos = self.buffer:find(pattern)
			if not startPos and decimal:len() > 0 then
				decimal = ""
				pattern = "^" .. signage .. "[%d]+"
				startPos, endPos = self.buffer:find(pattern)
			end
			if startPos then
				str = self.buffer:sub(startPos, endPos)
				self.buffer = self.buffer:sub(endPos+1)
				numberStr = numberStr .. str
				signage = ""
				if decimal:len() > 0 and str:find(".") then
					decimal = ""
				end
			end
			if (not startPos and self.buffer:len() > 0) or self.buffer:len() > 0 then
				break
			end
		end
		return tonumber(numberStr)
	end
	
	function buffer:readChunk()
		local str = self.stream:read(8192)
		if str then
			if str:len() > 0 then
				self.buffer = self.buffer .. str
			end
			return str
		end
		return nil
	end
	
	function buffer:read(mode)
		if type(mode) == "string" then
			if mode:sub(1,1) == "*" then
				mode = mode:sub(2)
			end
			local format = mode:sub(1,1)
			if format == "n" then
				local n = readNumber(self)
				return n
			elseif format == "l" or format == "L" then
				local l = readLine(self)
				return l
			elseif format == "a" then
				local a = readAll(self)
				return a
			else
				error("invalid read format given")
			end
		elseif mode then
			local c = self.stream:read(mode)
			return c
		else
			if self.buffer:len() == 0 then
				self:readChunk()
			end
			local str = self.buffer
			self.buffer = ""
			return str
		end
	end
	
	function buffer:lines()
		return function()
			if self.buffer:len() == 0 and not self:readChunk() then
				return nil
			end
			local l = readLine(self)
			return l
		end
	end
	
	function buffer:write(str)
		self.stream:write(str)
	end
	
	function buffer:close()
		self.stream:close()
	end
	
	function buffer:seek(whence, offset)
		local off, reason = self.stream:seek(whence, offset)
		if off then
			self.buffer = ""
		end
		return off, reason
	end
	
	return buffer
end

function bufferLib.stringstream(string)
	local stringstream = {
		buffer = string
	}
	
	function stringstream:write(write)
		self.buffer = self.buffer .. write
	end
	
	function stringstream:read(num)
		if self.buffer:len() < 1 then
			return nil
		end
		local read = self.buffer:sub(1, num)
		self.buffer = self.buffer:sub(num+1)
		return read
	end
	
	function stringstream:seek()
		return 0
	end
	
	return stringstream
end

return bufferLib