local util = require("util")
local math = require("math")
local term = {}

_term = {}

function term.nextToken(text) -- leftover, tokentype, tokendata
	if text:len() == 0 then
		return text, nil, nil
	end
	local escPos = text:find("[\x1B\n\r\x08\x04]")
	if not escPos then
		return "", "text", text
	end
	if escPos > 1 then
		return text:sub(escPos), "text", text:sub(1, escPos-1)
	end
	local c = text:sub(1,1)
	if c == "\n" then
		return text:sub(2), "newline", "\n"
	end
	if c == "\r" then
		return text:sub(2), "return", "\r"
	end
	if c == "\x08" then
		return text:sub(2), "backspace", "\x08"
	end
	if c == "\x04" then
		return text:sub(2), nil, nil
	end
	if c == "\x1B" and text:len() >= 2 then
		local head = "(\x1B%[)"
		if text:find("^" .. head) then
			local abbr = "([A-Za-z])"
			local abbrPos = text:find(abbr)
			if abbrPos then
				local params = "(%d*)(;?)(%d*)"
				local a, h, p1, s, p2, e = text:match("^(" .. head .. params .. abbr .. ")")
				if a then
					if not s then
						p1 = p1 .. p2
						p2 = nil
					end
					if p1 then
						if p1:len() == 0 then
							p1 = nil
						else
							p1 = tonumber(p1)
						end
					end
					if p2 then
						if p2:len() == 0 then
							p2 = nil
						else
							p2 = tonumber(p2)
						end
					end
					return text:sub(abbrPos+1), "csi", {c=e, p1=p1, p2=p2, t=a}
				else
					return text:sub(3), "text", text:sub(1, 2)
				end
			end
		end
		if text:sub(2,2) == "\x1B" then
			text = text:sub(2)
		end
		return text:sub(2), "esc", text:sub(1,1)
	end
	return text, nil, nil
end

function term.createTTY(input, output)
	local obj = {
		backgroundColor = {0,0,0,0},
		cachedLines = {""},
		cursorPosX = 1,
		cursorPosY = 1,
		lastScreenWidth = 100,
		lastScreenHeight = 100,
		scroll = 0,
		buffer = "",
		input = input or require("shell").getInput(),
		output = output or require("shell").getOutput(),
		alternative = {
			cachedLines = {""},
			cursorPosX = 1,
			cursorPosY = 1,
			scroll = 0
		},
		bUseAlternative = false
	}
	_term.current = obj
	obj.input.isTTY = true
	obj.output.isTTY = true
	
	local function fixScroll(self)
		local bottom = #self.cachedLines - self.scroll
		local top = bottom - self.lastScreenHeight + 1
		if bottom < self.cursorPosY then
			self:setScroll(self.scroll - (self.cursorPosY - bottom))
		elseif top > self.cursorPosY then
			self:setScroll(self.scroll + (top - self.cursorPosY))
		end
	end
	
	function obj:setCursor(x, y)
		y = math.max(1, y + math.floor((x-1) / self.lastScreenWidth))
		if x < 0 then
			y = y + 0
		end
		x = ((x-1) % (self.lastScreenWidth)) + 1
		self.cursorPosX = x
		self.cursorPosY = y
		local lines = self.cachedLines
		while #lines < y do
			table.insert(lines, "")
		end
		lines[y] = lines[y] .. string.rep(" ", self.lastScreenWidth - string.len(lines[y]))
		fixScroll(self)
	end
	
	function obj:getCursor()
		return self.cursorPosX, self.cursorPosY
	end
	
	function obj:setScroll(val)
		self.scroll = math.clamp(val, 0, math.max(0, #self.cachedLines - self.lastScreenHeight))
	end
	
	local function insertLine(self, inLine)
		local line
		while inLine:len() > 0 do
			line = inLine:sub(1, self.lastScreenWidth - self.cursorPosX + 1)
			inLine = inLine:sub(self.lastScreenWidth - self.cursorPosX + 2)
			
			local currentline = self.cachedLines[self.cursorPosY]
			local newline = ""
			if self.cursorPosX > 1 then
				newline = currentline:sub(1, self.cursorPosX-1)
			end
			newline = newline .. line
			if string.len(currentline) >= string.len(newline) then
				newline = newline .. currentline:sub(self.cursorPosX + string.len(line))
			end
			self.cachedLines[self.cursorPosY] = newline
			self:setCursor(self.cursorPosX + string.len(line), self.cursorPosY)
			fixScroll(self)
		end
	end
	
	local function swap(t1, t2, name)
		local val = t1[name]
		t1[name] = t2[name]
		t2[name] = val
	end
	
	local csiHandlers = {
		A = function(self, c, p1, p2)
			-- move up
			self:setCursor(self.cursorPosX, self.cursorPosY - (p1 or 1))
		end,
		B = function(self, c, p1, p2)
			-- move down
			self:setCursor(self.cursorPosX, self.cursorPosY + (p1 or 1))
		end,
		C = function(self, c, p1, p2)
			-- move right
			self:setCursor(self.cursorPosX + (p1 or 1), self.cursorPosY)
		end,
		D = function(self, c, p1, p2)
			-- move left
			self:setCursor(self.cursorPosX - (p1 or 1), self.cursorPosY)
		end,
		E = function(self, c, p1, p2)
			-- move next line beginning
			self:setCursor(1, self.cursorPosY + (p1 or 1))
		end,
		F = function(self, c, p1, p2)
			-- move prev line beginning
			self:setCursor(1, self.cursorPosY - (p1 or 1))
		end,
		G = function(self, c, p1, p2)
			-- set column
			local num = math.clamp(p1 or 1, 1, self.lastScreenWidth)
			self:setCursor(num, self.cursorPosY)
		end,
		H = function(self, c, p1, p2)
			-- set cursor pos
			local num1 = math.clamp(p2 or 1, 1, self.lastScreenWidth)
			local num2 = math.clamp(p1 or 1, 1, math.max(self.lastScreenHeight, #self.cachedLines))
			self:setCursor(num1, num2)
		end,
		J = function(self, c, p1, p2)
			if (p1 or 0) == 0 then
				-- clear from cursor till end of screen
				self.cachedLines[self.cursorPosY] = self.cachedLines[self.cursorPosY]:sub(1, self.cursorPosX-1)
				while #self.cachedLines > self.cursorPosY do
					table.remove(self.cachedLines)
				end
			elseif p1 == 1 then
				-- clear from cursor till beginning of screen
				self.cachedLines[self.cursorPosY] = string.rep(" ", self.cursorPosX) .. self.cachedLines[self.cursorPosY]:sub(self.cursorPosX+1)
				-- TODO: clear lines from top till cursor
			elseif p1 == 2 then
				-- clear screen
				for i=1,self.lastScreenHeight,1 do
					self.cachedLines[math.max(1, #self.cachedLines - self.scroll - i + 1)] = ""
				end
				self:setCursor(1, math.max(1, #self.cachedLines + self.scroll - self.lastScreenHeight))
			elseif p1 == 3 then
				-- clear everything
				self.cachedLines = {""}
				self:setCursor(1, 1)
			end
		end,
		K = function(self, c, p1, p2)
			if (p1 or 0) == 0 then
				-- clear from cursor till end of line
				self.cachedLines[self.cursorPosY] = self.cachedLines[self.cursorPosY]:sub(1, self.cursorPosX)
			elseif p1 == 1 then
				-- clear from cursor till beginning of line
				self.cachedLines[self.cursorPosY] = string.rep(" ", self.cursorPosX) .. self.cachedLines[self.cursorPosY]:sub(self.cursorPosX+1)
			elseif p1 == 2 then
				-- clear entire line
				self.cachedLines[self.cursorPosY] = ""
			end
		end,
		S = function(self, c, p1, p2)
			-- scroll up
			self:setScroll(self.scroll+1)
		end,
		T = function(self, c, p1, p2)
			-- scoll down
			self:setScroll(self.scroll-1)
		end,
		n = function(self, c, p1, p2)
			if p1 == 6 then
				-- request cursor pos
				self.output:write("\x1B[" .. tostring(self.cursorPosY) .. ";" .. tostring(self.cursorPosX) .. "R")
			end
		end,
		h = function(self, c, p1, p2)
			if p1 == 1049 and not self.bUseAlternative then
				swap(self.alternative, self, "cachedLines")
				swap(self.alternative, self, "cursorPosX")
				swap(self.alternative, self, "cursorPosY")
				swap(self.alternative, self, "scroll")
				self.bUseAlternative = true
			end
		end,
		l = function(self, c, p1, p2)
			if p1 == 1049 and self.bUseAlternative then
				swap(self.alternative, self, "cachedLines")
				swap(self.alternative, self, "cursorPosX")
				swap(self.alternative, self, "cursorPosY")
				swap(self.alternative, self, "scroll")
				self.bUseAlternative = false
			end
		end
	}
	
	function obj:write(text)
		self.buffer = self.buffer .. text
		local token, tokendata
		while self.buffer:len() > 0 do
			computer.skip()
			-- get end of this draw line from text
			self.buffer, token, tokendata = term.nextToken(self.buffer)
			if token == "newline" then
				self:setCursor(1, self.cursorPosY+1)
			elseif token == "return" then
				self:setCursor(1, self.cursorPosY)
			elseif token == "csi" then
				local handler = csiHandlers[tokendata.c]
				if handler and not fuck then
					handler(self, c, tokendata.p1, tokendata.p2)
				end
			elseif token then
				insertLine(self, tokendata)
			end
		end
	end
	
	function obj:clearLine()
		local newline = ""
		if self.cursorPosX > 0 then
			newline = self.cachedLines[self.cursorPosY]:sub(1, self.cursorPosX)
		end
		self.cachedLines[self.cursorPosY] = newline
	end
	
	function obj:setCursorVisibility(visibility)
		self.cursorVisible = visibility
	end
	
	function obj:paint(buffer)
		local w, h = buffer:getSize()
		self.lastScreenWidth = w
		self.lastScreenHeight = h
		buffer:fill(0, 0, w, h, " ", nil, backgroundColor)
		local lineIndex = #self.cachedLines - math.clamp(self.scroll, 0, math.max(0, #self.cachedLines - h))
		local y = h - math.max(0, h - #self.cachedLines)
		while y > 0 do
			local line = self.cachedLines[lineIndex]
			
			buffer:setText(0, y-1, line, {1,1,1,1}, nil)
			
			if lineIndex == self.cursorPosY then
				c, f, b = buffer:get(self.cursorPosX-1, y-1)
				if not f or f.a <= 0 then
					f = {1,1,1,1}
				end
				if not b or b.a <= 0 then
					b = {0,0,0,1}
				end
				
				buffer:set(self.cursorPosX-1, y-1, c, b, f)
			end
			
			lineIndex = lineIndex - 1
			if lineIndex < 1 then
				break
			end
			y = y - 1
		end
	end
	
	return obj
end

function term.isTTY(stream)
	if stream.stream then
	
	end
end

return term