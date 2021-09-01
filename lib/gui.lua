local event = require("event")
local util = require("util")

local gui = {}

__windowManager = {
	windows = {},
	windowIndexMap = {},
	inputCapturedBy = nil,
	onMouseUp = function() end,
	onMouseDown = function() end,
	onMouseMove = function() end,
	gpu = computer.getPCIDevices(findClass("GPU_T1_C"))[1],
	lastMouseMoveTrace = {},
	lastMouseHoveredMap = {},
}

gui.defaultStyle = {
	windowBackground = {0.1,0.1,0.1,1},
	windowCloseButtonTextColor = {1,1,1,1},
	windowCloseButtonBackgroundColor = {1,0,0,1},
	windowTitleBarTextColor = {1,1,1,1},
	windowTitleBarColor = {0.3,0.3,0.3,1},
	textColor = {1,1,1,1},
	textBackground = {1, 1, 1, 0},
	editableTextColor = {1,1,1,1},
	editableTextBackground = {0.2, 0.2, 0.2, 1},
	buttonBGNormal = {0.2, 0.2, 0.2, 1},
	buttonBGHovered = {0.25, 0.25, 0.25, 1},
	buttonBGClicked = {0.15, 0.15, 0.15, 1},
}

function __windowManager:addWindow(window)
	local i = self.windowIndexMap[window]
	if i then
		return
	end
	table.insert(self.windows, window)
	self.windowIndexMap[window] = #self.windows
end

function __windowManager:removeWindow(window)
	local i = self.windowIndexMap[window]
	if not i then
		return
	end
	table.remove(self.windows, i)
	self.windowIndexMap[window] = nil
	for k,v in pairs(self.windowIndexMap) do
		if v > i then
			self.windowIndexMap[k] = v-1
		end
	end
	if inputCapturedBy == window then
		inputCapturedBy = nil
	end
end

function __windowManager:getAlignedChildren(geometry)
	local children = {}

	for _, window in pairs(self.windows) do
		table.insert(children, gui.alignedChild(geometry, window, window.x, window.y, window.width, window.height))
	end

	return children
end

function __windowManager:paint()
	local gpu = self.gpu

	local w, h = gpu:getSize()
	gpu:setForeground(1,1,1,1)
	gpu:setBackground(0,0,0,0)
	gpu:fill(0, 0, w, h, " ")
	local gpuBuf = gpu:getBuffer()

	for _, window in pairs(self:getAlignedChildren(gui.alignedChild(nil, self, 0, 0, w, h))) do
		local buf = gpu:getBuffer()
		buf:setSize(window.width, window.height)
		window.child:paint(window, buf)
		gpuBuf:copy(window.x, window.y, buf, 0, 0, 0)
	end

	gpu:setBuffer(gpuBuf)
	gpu:flush()
end

function __windowManager:focus(widget)
	if not self.windowIndexMap[widget] then
		return
	end
	self:removeWindow(widget)
	self:addWindow(widget)
end

function __windowManager:findWidgetsAtPos(x, y, aligned)
	local result = {}
	if not aligned then
		aligned = gui.alignedChild(nil, self, 0, 0, self.gpu:getSize())
	end
	local childs = util.tryCall(aligned.child.getAlignedChildren, aligned.child, aligned)
	if not childs then
		return result
	end
	for _, child in pairs(childs) do
		if child.absoluteX <= x and child.absoluteY <= y and child.absoluteX + child.width > x and child.absoluteY + child.height > y then
			table.insert(result, child)
		end
	end
	return result
end

function __windowManager:traceWidget(x, y, width, height)
	local trace = {}

	local widget = gui.alignedChild(nil,self,0,0,width,height)
	while widget do
		table.insert(trace, widget)
		local children = self:findWidgetsAtPos(x, y, widget)
		if #children > 0 then
			widget = children[#children]
		else
			widget = nil
		end
	end

	return trace
end

function __windowManager:handleReply(window, reply)
	if not reply then
		return false
	end
	if self.inputCapturedBy then
		if self.inputCapturedBy.child == window.child then
			if reply.__release then
				self.inputCapturedBy = nil
			end
		end
	elseif reply.__capture then
		self.inputCapturedBy = window
	end
		
	return reply.__handled
end

function __windowManager:handleInput(functionName, x, y, ...)
	-- try capture
	local child = self.inputCapturedBy
	if child then
		child:update()
		local widget = child.child
		local wx, wy = child:absToLoc(x, y)
		local reply = util.tryCall(widget[functionName], widget, wx, wy, ...)
		if self:handleReply(child, reply) then
			return true, {child}
		end
		return true, nil
	end

	-- bubble input
	local trace = self:traceWidget(x, y, self.gpu:getSize())
	for i=#trace, 1, -1 do
		child = trace[i]
		local widget = child.child
		local wx, wy = child:absToLoc(x, y)
		local reply = util.tryCall(widget[functionName], widget, wx, wy, ...)
		if self:handleReply(child, reply) then
			return true, trace
		end
	end

	return false, trace
end

event.subscribe("OnMouseDown", function(gpu, x, y, btn)
	if not __windowManager:handleInput("onMouseDown", x, y, btn) then
--		__windowManager:onMouseDown(x, y, btn)
	end
end)

event.subscribe("OnMouseUp", function(gpu, x, y, btn)
	if not __windowManager:handleInput("onMouseUp", x, y, btn) then
--		__windowManager:onMouseUp(x, y, btn)
	end
end)

event.subscribe("OnMouseMove", function(gpu, x, y, btn)
	local found, trace = __windowManager:handleInput("onMouseMove", x, y, btn)
	if trace then
		local hovered = {}
		for _, widget in pairs(trace) do
			hovered[widget.child] = true
			if not __windowManager.lastMouseHoveredMap[widget.child] then
				util.tryCall(widget.child.onMouseEnter, widget.child, widget:absToLoc(x, y), btn)
			end
		end
		for _, widget in pairs(__windowManager.lastMouseMoveTrace) do
			if not hovered[widget.child] then
				util.tryCall(widget.child.onMouseLeave, widget.child, widget:absToLoc(x, y), btn)
			end
		end
		__windowManager.lastMouseMoveTrace = trace
		__windowManager.lastMouseHoveredMap = hovered
	end
	if not found then
		__windowManager:onMouseMove(x, y, btn)
	end
end)

function gui.reply()
	local reply = {
		__capture = false,
		__release = false,
		__handled = false,
	}

	function reply:capture()
		self.__capture = true
		return self
	end

	function reply:release()
		self.__release = true
		return self
	end

	function reply:handled()
		self.__handled = true
		return self
	end

	return reply
end

function gui.getWindowManager()
	return __windowManager
end

function gui.createBuffer(width, height)
	local buf = __windowManager.gpu:getBuffer()
	buf:setSize(width, height)
	return buf
end

function gui.geometry(parent, x, y, width, height)
	local geometry = {
		parent = parent,
		x = math.floor(x),
		y = math.floor(y),
		width = math.floor(width),
		height = math.floor(height),
		absoluteX = math.floor(x),
		absoluteY = math.floor(y),
	}
	
	if parent then
		geometry.absoluteX = geometry.absoluteX + parent.absoluteX
		geometry.absoluteY = geometry.absoluteY + parent.absoluteY
	end

	function geometry:absToLoc(x, y)
		return math.floor(x - self.absoluteX), math.floor(y - self.absoluteY)
	end

	return geometry
end

function gui.createWidget()
	local widget = {}
	widget.clickable = false
	widget.clicked = false
	widget.hovered = false

	function widget:paint(geometry, buffer) end

	function widget:getDesiredSize()
		return 30, 10
	end

	function widget:onMouseDown(x, y, btn)
		local reply = gui.reply()
		if self.clickable then
			self.clicked = true
			reply:handled():capture()
		end
		return reply
	end

	function widget:onMouseUp(x, y, btn)
		local reply = gui.reply()
		if self.clicked then
			self:onClick(x, y, btn)
			reply:handled():release()
			self.clicked = false
		end
		return reply
	end

	function widget:onMouseMove(x, y, btn)
		return gui.reply()
	end

	function widget:onMouseEnter(x, y, btn)
		self.hovered = true
	end

	function widget:onMouseLeave(x, y, btn)
		self.hovered = false
	end

	function widget:onClick(x, y, btn)
		return gui.reply()
	end

	return widget
end

function gui.alignedChild(parent, widget, x, y, width, height)
	local child = gui.geometry(parent, x, y, width, height)
	child.child = widget

	function child:update()
		if self.parent then
			self.parent:update()

			for _, child in pairs(self.parent.child:getAlignedChildren(self.parent)) do
				if child.child == self.child then
					self.x = child.x
					self.y = child.y
					self.width = child.width
					self.height = child.height
					break
				end
			end

			self.absoluteX = self.parent.absoluteX + self.x
			self.absoluteY = self.parent.absoluteY + self.y
		end
	end

	return child
end

function gui.createPanel()
	local panel = gui.createWidget()

	function panel:getAlignedChildren(geometry)
		return {}
	end

	return panel
end

function gui.createWindow(title, closeable)
	local window = gui.createPanel()
	window.title = title
	window.closeable = closeable
	window.width = 30
	window.height = 10
	window.x = 0
	window.y = 0
	window.titleTextColor = gui.defaultStyle.windowTitleBarTextColor
	window.titleBarColor = gui.defaultStyle.windowTitleBarColor
	window.closeButtonColor = gui.defaultStyle.windowCloseButtonBackgroundColor
	window.closeButtonTextColor = gui.defaultStyle.windowCloseButtonTextColor
	window.windowBackgroundColor = gui.defaultStyle.windowBackground
	window.child = nil

	function window:paint(geometry, buffer)
		local w, h = buffer:getSize()
		buffer:fill(0, 1, w, h-1, " ", {1,1,1,1}, self.windowBackgroundColor)
		buffer:fill(0, 0, w, 1, " ", {}, self.titleBarColor)
		buffer:setText(0, 0, self.title, self.titleTextColor, self.titleBarColor)
		if self.closeable then
			buffer:setText(w-1, 0, "X", self.closeButtonTextColor, self.closeButtonColor)
		end

		local aligned = self:getAlignedChildren(geometry)
		if #aligned > 0 then
			aligned = aligned[1]
			local childBuffer = gui.createBuffer(aligned.width, aligned.height)
			aligned.child:paint(aligned, childBuffer)
			buffer:copy(aligned.x, aligned.y, childBuffer, 1, 1, 1)
		end
	end

	function window:onMouseDown(x, y)
		if x == window.width-1 and y == 0 then
			self:close()
		end
		self.mouseMoveStart = {x,y}
		gui.getWindowManager():focus(self)
		return gui.reply():capture():handled()
	end

	function window:onMouseUp(x, y)
		self.mouseMoveStart = nil
		return gui.reply():release():handled()
	end

	function window:onMouseMove(x, y)
		if self.mouseMoveStart then
			self.x = self.x + (x - self.mouseMoveStart[1])
			self.y = self.y + (y - self.mouseMoveStart[2])
			return gui.reply():handled()
		end
		return gui.reply()
	end

	function window:getDesiredSize()
		return self.width, self.height
	end

	function window:close()
		__windowManager:removeWindow(self)
	end

	function window:show()
		__windowManager:addWindow(self)
	end

	function window:getAlignedChildren(geometry)
		if not self.child then
			return {}
		end

		local aligned = gui.alignedChild(geometry, self.child, 0, 1, geometry.width, geometry.height-1)
		return {aligned}
	end

	function window:setChild(child)
		self.child = child
	end

	return window
end

function gui.createCanvasPanel()
	local canvas = gui.createPanel()
	canvas.children = {}
	canvas.slots = {}

	function canvas:getAlignedChildren(geometry)
		local children = {}
		for _, child in pairs(self.children) do
			local slot = self.slots[child]
			local aligned = gui.alignedChild(geometry, child, slot.x, slot.y, child:getDesiredSize())
			table.insert(children, aligned)
		end
		return children
	end

	function canvas:addChild(widget, x, y)
		table.insert(self.children, widget)
		self.slots[widget] = {
			x = x,
			y = y
		}
	end

	function canvas:paint(geometry, buffer)
		local width, height = buffer:getSize()
		buffer:fill(0, 0, width, height, " ", {}, {})
		for _, child in pairs(self:getAlignedChildren(geometry)) do
			local childBuffer = gui.createBuffer(child.width, child.height)
			child.child:paint(child, childBuffer)
			buffer:copy(child.x, child.y, childBuffer, 1, 1, 1)
		end
	end

	function canvas:getDesiredSize()
		-- TODO: Maybe figure out fitting size by finding borders of children
		return 0, 0
	end

	return canvas
end

function gui.createText(text, foregroud, background)
	local widget = gui.createWidget()
	widget.text = text
	widget.foreground = util.default(foreground, gui.defaultStyle.textColor)
	widget.background = util.default(background, gui.defaultStyle.textBackground)
	widget.width = math.max(1, string.len(widget.text))
	widget.height = 1
	widget.vAlign = "center"
	widget.hAlign = "center"

	function widget:paint(geometry, buffer)
		local bwidth, bheight = buffer:getSize()
		local offsetX = math.floor(bwidth/2 - string.len(self.text)/2)
		local offsetY = math.floor(bheight/2)
		if self.hAlign == "left" then
			offsetX = 0
		elseif self.hAlign == "right" then
			offsetX = bwidth - string.len(self.text)
		end
		if self.vAlign == "top" then
			offsetY = 0
		elseif self.vAlign == "bottom" then
			offsetY = bwidth-1
		end
		buffer:fill(0, 0, bwidth, bheight, " ", {}, {})
		buffer:setText(offsetX, offsetY, self.text, self.foreground, self.background)
	end

	function widget:getDesiredSize()
		return self.width, self.height
	end

	return widget
end

function gui.createButton(onClickEvent, child, backgroundNormal, backgroundHovered, backgroundClicked)
	local button = gui.createPanel()
	button.child = child
	button.backgroundNormal = util.default(backgroundNormal, gui.defaultStyle.buttonBGNormal)
	button.backgroundHovered = util.default(backgroundHovered, gui.defaultStyle.buttonBGHovered)
	button.backgroundClicked = util.default(backgroundClicked, gui.defaultStyle.buttonBGClicked)
	button.onClickEvent = onClickEvent
	button.clickable = true

	function button:paint(geometry, buffer)
		local width, height = buffer:getSize()
		local background = self.backgroundNormal
		if self.clicked then
			background = self.backgroundClicked
		elseif self.hovered then
			background = self.backgroundHovered
		end
		buffer:fill(0, 0, width, height, " ", {}, background)
		local aligned = self:getAlignedChildren(geometry)
		if #aligned > 0 then
			aligned = aligned[1]
			local childBuffer = buffer:clone()
			childBuffer:setSize(aligned.width, aligned.height)
			aligned.child:paint(aligned, childBuffer)
			buffer:copy(aligned.x, aligned.y, childBuffer, 1, 1, 1)
		end
	end

	util.override(button, "onClick", function(self, x, y)
		util.tryCall(self.onClickEvent, self)
	end)

	function button:getDesiredSize()
		if child then
			--return child:getDesiredSize()
		end
		return 10, 1
	end

	function button:getAlignedChildren(geometry)
		return {gui.alignedChild(geometry, self.child, 0, 0, geometry.width, geometry.height)}
	end

	return button
end

return gui