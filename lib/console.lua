local util = require("util")
local math = require("math")

_console = {
	current = nil
}

local console = {}

function console.writeLine(text)
	if _console.current then
		_console.current:write(text .. "\n")
	end
end

function console.nextToken(text) -- leftover, tokentype, tokendata
	if text:len() == 0 then
		return text, nil, nil
	end
	local escPos = text:find("[\x1B\n\r\x08]")
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
	if c == "\x1B" and text:len() > 2 then
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
					return text:sub(abbrPos+1), "esc", {c=e, p1=p1, p2=p2, t=a}
				else
					return text:sub(3), "text", text:sub(1, 2)
				end
			end
		end
		return text:sub(2), "text", text:sub(1,1)
	end
	return text, nil, nil
end

function console.createTTY(input, output)
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
	}
	_console.current = obj
	
	local function fixScroll(self)
		local bottom = #self.cachedLines - self.scroll
		local top = bottom - self.lastScreenHeight + 1
		if bottom < self.cursorPosY then
			print("fix scroll")
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

	function obj:write(text)
		self.buffer = self.buffer .. text
		local token, tokendata
		while self.buffer:len() > 0 do
			-- get end of this draw line from text
			self.buffer, token, tokendata = console.nextToken(self.buffer)
			if token == "newline" then
				self:setCursor(1, self.cursorPosY+1)
			elseif token == "return" then
				self:setCursor(1, self.cursorPosY)
			elseif token == "esc" then
				local c = tokendata.c
				if c == "A" then
					-- move up
					self:setCursor(self.cursorPosX, self.cursorPosY - (tokendata.p1 or 1))
				elseif c == "B" then
					-- move down
					self:setCursor(self.cursorPosX, self.cursorPosY + (tokendata.p1 or 1))
				elseif c == "C" then
					-- move right
					self:setCursor(self.cursorPosX + (tokendata.p1 or 1), self.cursorPosY)
				elseif c == "D" then
					-- move left
					self:setCursor(self.cursorPosX - (tokendata.p1 or 1), self.cursorPosY)
				elseif c == "E" then
					-- move next line beginning
					self:setCursor(1, self.cursorPosY + (tokendata.p1 or 1))
				elseif c == "F" then
					-- move prev line beginning
					self:setCursor(1, self.cursorPosY - (tokendata.p1 or 1))
				elseif c == "G" then
					-- set column
					self:setCursor(tokendata.p1 or 1, self.cursorPosY)
				elseif c == "H" then
					-- set cursor pos
					self:setCursor(tokendata.p2 or 1, tokendata.p1 or 1)
				elseif c == "J" then
					if (tokendata.p1 or 0) == 0 then
						-- clear from cursor till end of screen
						self.cachedLines[self.cursorPosY] = self.cachedLines[self.cursorPosY]:sub(1, self.cursorPosX-1)
						while #self.cachedLines > self.cursorPosY do
							table.remove(self.cachedLines)
						end
					elseif tokendata.p1 == 1 then
						-- clear from cursor till beginning of screen
						self.cachedLines[self.cursorPosY] = string.rep(" ", self.cursorPosX) .. self.cachedLines[self.cursorPosY]:sub(self.cursorPosX+1)
						-- TODO: clear lines from top till cursor
					elseif tokendata.p1 == 2 then
						-- clear screen
					elseif tokendata.p1 == 3 then
						-- clear everything
						self.cachedLines = {""}
					end
				elseif c == "K" then
					if (tokendata.p1 or 0) == 0 then
						-- clear from cursor till end of line
						self.cachedLines[self.cursorPosY] = self.cachedLines[self.cursorPosY]:sub(1, self.cursorPosX)
					elseif tokendata.p1 == 1 then
						-- clear from cursor till beginning of line
						self.cachedLines[self.cursorPosY] = string.rep(" ", self.cursorPosX) .. self.cachedLines[self.cursorPosY]:sub(self.cursorPosX+1)
					elseif tokendata.p1 == 2 then
						-- clear entire line
						self.cachedLines[self.cursorPosY] = ""
					end
				elseif c == "S" then
					-- scroll up
					self:setScroll(self.scroll+1)
				elseif c == "T" then
					-- scoll down
					self:setScroll(self.scroll-1)
				elseif c == "n" then
					if tokendata.p1 == 6 then
						-- request cursor pos
						self.output:write("\x1B[" .. tostring(self.cursorPosY) .. ";" .. tostring(self.cursorPosX) .. "R")
					end
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

function console.createConsole()
	local shell = require("shell")
	
	local obj = console.createTTY()

	function obj:tick()
		local str = self.input:read()
		self:write(str)
	end

	function obj:handleInput(e, s, c, b, m)
		if e == "OnKeyDown" then
			local text = self.inputText
			if b == 35 then
				-- end
			elseif b == 36 then
				-- pos^1
			elseif b == 37 then
				-- left
				self.output:write("\x1B[1D")
			elseif b == 38 then
				-- up
				if m & 4 > 0 then
					self.output:write("\x1B[1S")
				else
					self.output:write("\x1B[1A")
				end
			elseif b == 39 then
				-- right
				self.output:write("\x1B[1C")
			elseif b == 40 then
				-- down
				if m & 4 > 0 then
					self.output:write("\x1B[1T")
				else
					self.output:write("\x1B[1B")
				end
			elseif b == 46 then
				-- del
			end
			--print("key:", b)
		elseif e == "OnKeyChar" then
			--print(string.byte(c))
			if c == "\r" then
				c = "\n"
			end
			self.output:write(c)
		end
		
		return not not e
	end

	return obj
end

function console.readTillCPR(stream, text)
	text = text or ""
	local prev = ""
	local token, tokendata
	while true do
		if text:len() == 0 then
			text = text .. stream:read()
		end
		if text:len() > 0 then
			text, token, tokendata = console.nextToken(text)
			if token == "esc" then
				if tokendata.c == "R" then
					return tokendata.p1, tokendata.p2, prev, text
				else
					prev = prev .. tokendata.t
				end
			else
				prev = prev .. tokendata
			end
		else
			coroutine.yield()
			computer.skip()
		end
	end
end

function console.readLine(input, output)
	local shell = require("shell")
	input = input or shell.getInput()
	output = output or shell.getOutput()
	local inputText = ""
	output:write("\x1B[6n")
	local startY, startX = console.readTillCPR(input)
	local buffer = ""
	local token, tokendata
	local update = false
	local cursorOffset = 0
	while true do
		if buffer:len() == 0 then
			buffer = input:read()
		end
		if buffer:len() > 0 then
			buffer, token, tokendata = console.nextToken(buffer)
			if token == "text" or token == "return" then
				output:write(tokendata .. inputText:sub(inputText:len() - cursorOffset + 1) .. "\x1B[" .. cursorOffset .. "D")
				inputText = inputText:sub(1, inputText:len() - cursorOffset) .. tokendata .. inputText:sub(inputText:len() - cursorOffset + 1)
			elseif token == "newline" then
				output:write(tokendata)
				return inputText
			elseif token == "backspace" then
				inputText = inputText:sub(1, inputText:len()-cursorOffset-1) .. inputText:sub(inputText:len()-cursorOffset+1)
				update = true
			elseif token == "esc" then
				if tokendata.c == "S" or tokendata.c == "T" then
					output:write(tokendata.t)
                elseif tokendata.c == "C" then
                    -- move right
                    if cursorOffset > 0 then
                        cursorOffset = cursorOffset - 1
                        output:write("\x1B[1C")
                    end
                elseif tokendata.c == "D" then
                    -- move left
                    if cursorOffset < inputText:len() then
                        cursorOffset = cursorOffset + 1
                        output:write("\x1B[1D")
                    end
				end
			end
		else
			if update then
				update = false,
				output:write("\x1B[" .. startY .. ";" .. startX .. "H\x1B[J" .. inputText .. "\x1B[" .. cursorOffset .. "D")
			end
			coroutine.yield()
			computer.skip()
		end
	end
end

return console