local shell = require("shell")
local process = require("process")
local buffer = require("buffer")
local console = require("console")

local historyOffset = -1
local maxHistoryOffset = 0

local function getHistoryPath()
	return process.running().environment["shell_history"] or "/.shell_history"
end

local function getHistory(offset)
	offset = offset or historyOffset
	if not filesystem.isFile(getHistoryPath()) then
		return ""
	end
	local file = buffer.create("r", filesystem.open(getHistoryPath(), "r"))
	local history = {}
	for line in file:lines() do
		table.insert(history, line)
	end
	file:close()
	maxHistoryOffset = #history - 1
	return history[#history - offset] or ""
end

local function addHistory(cmd)
	local o_cmd = getHistory(0)
	if o_cmd == cmd then
		return
	end
	local file = filesystem.open(getHistoryPath(), "a")
	file:write(cmd .. "\n")
	file:close()
	maxHistoryOffset = maxHistoryOffset + 1
end

while true do
	shell.write(process.running().environment["PWD"] .. " > ")
	local tabIndex = 0
	local prevText, prevOff = nil, nil
	local cmd = console.readLine(shell.getInput(), shell.getOutput(), function(arg, text, off, token, data)
		if arg == 0 then
			if token == "text" then
				if data == "\t" then
					text = prevText or text
					off = prevOff or off
					prevText = text
					prevOff = off
					tabIndex = tabIndex + 1
					local lexer = shell.createLexer()
					lexer:tokenize(text)
					local parser = shell.createParser(lexer)
					local token, start, stop = nil, 1, 1
					while true do
						local ntoken, nstart, nstop = parser:parseToken()
						if not ntoken or nstart > text:len()-off then
							break
						end
						token, start, stop = ntoken, nstart, nstop
					end
					local complete = ""
					if token then
						complete = token
					end
					
					local completions = shell.completions(complete, not token or start == 1)
					tabIndex = tabIndex % (#completions+1 or 1)
					if tabIndex > 0 then
						local completion = completions[tabIndex]
						local endPart = text:sub(stop+1)
						text = text:sub(1, start-1) .. completion .. endPart
						off = endPart:len()
					else
						text = prevText
						off = prevOff
					end
					return false, true, text, off
				end
			end
			prevText = nil
			prevOff = nil
			tabIndex = 0
			if token == "csi" then
				if data.c == "A" then
					historyOffset = math.min(maxHistoryOffset, historyOffset + 1)
					return false, true, getHistory(), 0
				elseif data.c == "B" then
					historyOffset = math.max(0, historyOffset - 1)
					return false, true, getHistory(), 0
				end
			end
		end
		return true, false, text, off
	end)
	addHistory(cmd)
	historyOffset = -1
	local status_code, err, ret = (xpcall or pcall)(function()
		shell.execute(cmd)
	end)
	if not status_code then
		shell.writeLine(err.message .. "\n" .. (err.trace or ""))
	end
end
