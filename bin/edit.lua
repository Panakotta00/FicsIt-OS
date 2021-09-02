local shell = require("shell")
local console = require("console")
local term = require("term")
local buffer = require("buffer")

local args = {...}
local lines = {}
local startX, startY, width, height
local windowLeft = 1
local windowTop = 1
local cursorX = 1
local cursorY = 1
local inputBuffer = ""
local token, tokendata
local bUpdateScreen = false
local bUpdateCursor = false
local bUpdateMenu = false
local lastXCursor = 1
local redrawLines = {}
local redrawLinesUnder = 999999
local mode = 0
local menu = 0
local bInControl = false
local bDone = true

local function resize()
	shell.write("\x1B[3J\x1B[6n\x1B[999;999H\x1B[6n\x1B[2J\x1B[6n")
	startY, startX, _, rest = console.readTillCPR(shell.getInput())
	height, width, _, rest = console.readTillCPR(shell.getInput(), rest)
	local oheight, owidth, _, rest = console.readTillCPR(shell.getInput(), rest)
	height = height - oheight
	width = width - owidth
	shell.write("\x1B[" .. startY .. ";" .. startX .. "H\x1B[J")
end

local function updateCursor()
	shell.write("\x1B[" .. (startY + cursorY - windowTop) .. ";" .. (startX + cursorX - windowLeft) .. "H")
end

local function drawMenu()
	shell.write("\x1B[25l\x1B[" .. startY + height - 1 .. ";1H")
	if menu == 0 then
		shell.write("[ Save ]  Exit    Quit  ")
	elseif menu == 1 then
		shell.write("  Save  [ Exit ]  Quit  ")
	elseif menu == 2 then
		shell.write("  Save    Exit  [ Quit ]")
	end
	shell.write("\x1B[K")
end

local function draw()
	local str = "\x1B[25h\x1B[" .. startY .. ";" .. startX .. "H\x1B[J"
	local visible
	for y=windowTop, math.min(#lines, windowTop+height-1), 1 do
		visible = lines[y]:sub(windowLeft, windowLeft+width)
		if visible:len() < width then
			visible = visible .. "\n"
		end
		str = str .. visible
	end
	shell.write(str)
	updateCursor()
	if mode == 1 then
		drawMenu()
	end
end

local function loadFile(path)
	lines = {}
	if filesystem.exists(path) and filesystem.isFile(path) then
		local file = buffer.create("r", filesystem.open(path, "r"))
		for line in file:lines() do
			table.insert(lines, line)
		end
	end
end

local function setCursor(x, y, rollover)
	cursorX = x
	cursorY = y
	if rollover then
		while cursorX < 1 do
			if cursorY-1 > 0 then
				cursorY = math.clamp(cursorY-1, 1, #lines+1)
				cursorX = (lines[cursorY] or ""):len() + cursorX + 1
			else
				cursorX = 1
			end
		end
		while cursorX > (lines[cursorY] or ""):len()+1 do
			local oldLen = (lines[cursorY] or ""):len()+1
			cursorY = math.clamp(cursorY+1, 1, #lines+1)
			cursorX = cursorX - oldLen
		end
	end
	cursorY = math.clamp(cursorY, 1, #lines+1)
	cursorX = math.clamp(cursorX, 1, (lines[cursorY] or ""):len()+1)
	local cursorXDiff = cursorX - (windowLeft + width - 1)
	if cursorXDiff > 0 then
		windowLeft = windowLeft + cursorXDiff
		bUpdateScreen = true
	elseif cursorXDiff <= -width then
		windowLeft = windowLeft + (cursorXDiff+width-1)
		bUpdateScreen = true
	end
	local cursorYDiff = cursorY - (windowTop + height - 1)
	if cursorYDiff > 0 then
		windowTop = windowTop + cursorYDiff
		bUpdateScreen = true
	elseif cursorYDiff <= -height then
		windowTop = windowTop + (cursorYDiff+height-1)
		bUpdateScreen = true
	end
end

local function insertText(text)
	while not lines[cursorY] do
		table.insert(lines, "")
	end
	lines[cursorY] = lines[cursorY]:sub(1, cursorX-1) .. text .. lines[cursorY]:sub(cursorX)
	setCursor(cursorX + text:len(), cursorY)
	redrawLines[cursorY] = true
end

local function isLineInRange(line)
	return line >= windowTop and line < windowTop + height
end

local function drawLine(line)
	shell.write("\x1B[" .. line - windowTop + startY .. ";1H\x1B[K" .. (lines[line] or ""):sub(windowLeft, windowLeft + width - 1))
end

local function drawLineRange(start, stop)
	shell.write("\x1B[" .. start - windowTop + startY .. ";1H\x1B[J")
	stop = math.min(stop, #lines)
	for line=start,stop,1 do
		local visible = lines[line]:sub(windowLeft, windowLeft + width - 1)
		if visible:len() < width then
			visible = visible .. "\n"
		end
		shell.write(visible)
	end
end

local function editMode(token, tokendata)
	if token == "csi" then
		if tokendata.c == "A" then
			-- move up
			setCursor(lastXCursor, cursorY - 1)
			bUpdateCursor = true
		elseif tokendata.c == "B" then
			-- move down
			setCursor(lastXCursor, cursorY + 1)
			bUpdateCursor = true
		elseif tokendata.c == "C" then
			-- move right
			setCursor(cursorX + 1, cursorY, true)
			bUpdateCursor = true
			lastXCursor = cursorX
		elseif tokendata.c == "D" then
			-- move left
			setCursor(cursorX - 1, cursorY, true)
			bUpdateCursor = true
			lastXCursor = cursorX
		elseif tokendata.c == "R" then
			bDone = true
		end
	elseif token == "text" or token == "return" then
		insertText(tokendata)
	elseif token == "newline" then
		bInControl = false
		if not lines[cursorY] then
			lines[cursorY] = ""
			bUpdateCursor = true
		else
			table.insert(lines, cursorY+1, lines[cursorY]:sub(cursorX))
			lines[cursorY] = lines[cursorY]:sub(1, cursorX-1)
			redrawLinesUnder = math.min(redrawLinesUnder, cursorY)
		end
		setCursor(1, cursorY+1)
		lastXCursor = cursorX
	elseif token == "backspace" then
		if cursorX == 1 and cursorY > 1 then
			local len = lines[cursorY-1]:len()+1
			if #lines >= cursorY then
				lines[cursorY-1] = lines[cursorY-1] .. lines[cursorY]
				table.remove(lines, cursorY)
			end
			setCursor(len, cursorY-1)
			lastXCursor = cursorX
			redrawLinesUnder = math.min(redrawLinesUnder, cursorY)
		elseif cursorX > 1 then
			lines[cursorY] = lines[cursorY]:sub(1, cursorX-2) .. lines[cursorY]:sub(cursorX)
			setCursor(cursorX-1, cursorY)
			redrawLines[cursorY] = true
		end
	elseif token == "esc" then
		mode = 1
		bUpdateScreen = true
	end
end

local function linesToString()
	local text = ""
	for _, line in pairs(lines) do
		text = text .. line .. "\n"
	end
	text = text:sub(1, text:len()-1)
	return text
end

local function saveFile()
	local file = filesystem.open(args[1], "w")
	file:write(linesToString())
	file:close()
end

local function commitMenu()
	mode = 0
	bUpdateScreen = true
	if menu == 0 then
		saveFile()
	elseif menu == 1 then
		shell.write("\x1B[1049l")
		return true, 0
	end
end

local function menuMode(token, tokendata)
	if token == "csi" then
		if tokendata.c == "C" then
			-- move right
			menu = (menu + 1) % 3
			bUpdateMenu = true
		elseif tokendata.c == "D" then
			-- move left
			menu = (menu - 1) % 3
			bUpdateMenu = true
		elseif tokendata.c == "R" then
			bDone = true
		end
	elseif token == "newline" then
		return commitMenu()
	elseif token == "esc" then
		mode = 0
		bUpdateScreen = true
	end
end

if #args > 0 then
	loadFile(args[1])
end

shell.write("\x1B[1049h")

resize()
draw()

while true do
	if inputBuffer:len() == 0 then
		inputBuffer = shell.read()
	end
	if inputBuffer:len() > 0 then
		inputBuffer, token, tokendata = term.nextToken(inputBuffer)
		if mode == 0 then
			editMode(token, tokendata)
		elseif mode == 1 then
			local r, c = menuMode(token, tokendata)
			if r then
				return c
			end
		end
	else
		if bDone then
			if bUpdateScreen then
				bUpdateScreen = false,
				draw()
				bDone = false
			end
			for line in pairs(redrawLines) do
				if isLineInRange(line) then
					drawLine(line)
					bDone = false
				end
				bUpdateCursor = true
			end
			if redrawLinesUnder < windowTop + height - 1 then
				drawLineRange(redrawLinesUnder, windowTop + height - 1)
				bDone = false
				bUpdateCursor = true
			end
			redrawLines = {}
			redrawLinesUnder = math.max(windowTop + height, #lines)
			if bUpdateCursor then
				bUpdateCursor = false
				updateCursor()
				bDone = false
			end
			if bUpdateMenu then
				bUpdateMenu = false
				drawMenu()
				print("yay")
				bDone = false
			end
			if not bDone then
				shell.write("\x1B[6n")
			end
		end
		coroutine.yield()
		computer.skip()
	end
end
