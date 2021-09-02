local term = require("term")

_console = {
	current = nil
}

local console = {}

function console.writeLine(text)
	if _console.current then
		_console.current:write(text .. "\n")
	end
end

function console.createConsole()
	local shell = require("shell")
	
	local obj = term.createTTY()

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
				start = computer.millis()
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
			--print(string.byte(c))
		elseif e == "OnKeyChar" then
			if c == "\r" then
				c = "\n"
			end
			if b == 4 then
				c = ""
			end
			if c == "\x1B" then
				c = c .. "\x1B"
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
			text, token, tokendata = term.nextToken(text)
			if token == "csi" then
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

function console.readLine(input, output, extensionFunc)
	local inputText = ""
	output:write("\x1B[25h\x1B[6n")
	local startY, startX = console.readTillCPR(input)
	local buffer = ""
	local token, tokendata
	local update = false
	local cursorOffset = 0
	local continue = true
	while true do
		if buffer:len() == 0 then
			buffer = input:read()
		end
		if buffer:len() > 0 then
			buffer, token, tokendata = term.nextToken(buffer)
			if extensionFunc then
				continue, update, inputText, cursorOffset = extensionFunc(0, inputText, cursorOffset, token, tokendata)
			end
			if not continue then
			elseif token == "text" or token == "return" then
				output:write(tokendata .. inputText:sub(inputText:len() - cursorOffset + 1) .. "\x1B[" .. cursorOffset .. "D")
				inputText = inputText:sub(1, inputText:len() - cursorOffset) .. tokendata .. inputText:sub(inputText:len() - cursorOffset + 1)
			elseif token == "newline" then
				output:write(tokendata)
				output:write("\x1B[25l")
				return inputText
			elseif token == "backspace" then
				inputText = inputText:sub(1, inputText:len()-cursorOffset-1) .. inputText:sub(inputText:len()-cursorOffset+1)
				update = true
			elseif token == "csi" then
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