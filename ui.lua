--[[
	UILibrary
	---------
	local Library = require(game.ReplicatedStorage.UILibrary)

	local Window  = Library.Window("Title", { Logo = 123456, ToggleKey = Enum.KeyCode.RightShift })
	local Tab     = Window.Tab(123456)                 -- icon id (or Window.Tab(iconId, "Name"))
	local Section = Tab.Section("Aimbot")              -- auto Left / Right, or Tab.Section("Aimbot", "Right")

	Section.Toggle("Enable Aimbot", true, function(on) end)
	Section.Slider("FOV Value", 0, 360, 116, function(v) end)      -- or (name, {Min, Max, Default, Increment}, cb)
	Section.Keybind("Aimbot Key :", Enum.UserInputType.MouseButton2, function(key) end, function() end) -- changed, pressed
	Section.Dropdown("Target Bone :", {"Head", "Torso"}, "Head", function(opt) end)
	Section.ColorPicker("ESP Color", Color3.fromRGB(66, 133, 230), function(color) end)
	Section.Button("Click me", function() end)
	Section.TextBox("Name :", "placeholder", function(text) end)
	Section.Label("Some text")
	Section.ConfigManager()                            -- config UI: name box, create / load / overwrite / delete / autoload

	Configs
	-------
	Every Toggle / Slider / Keybind / Dropdown / ColorPicker / TextBox is saved automatically, keyed by
	Tab / Section / Element name (so keep those names unique and stable between versions).
	Files are written to the executor's workspace: <Folder>/configs/<name>.json  (Folder defaults to the window title,
	or pass { Folder = "MyHub" } in the Window options). Autoload is stored in <Folder>/autoload.txt and is applied
	automatically once your script finishes building the UI, or manually with Window.LoadAutoload().

	Window.SaveConfig(name) / Window.LoadConfig(name) / Window.DeleteConfig(name) / Window.ListConfigs()
	Window.SetAutoload(name) / Window.ClearAutoload() / Window.GetAutoload() / Window.LoadAutoload()

	Every element returns an object with :Set(value) / :Get().
	Both dot (Window.Tab) and colon (Window:Tab) calls work.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")
local HttpService = game:GetService("HttpService")

local Library = {}

Library.Theme = {
	Background = Color3.fromRGB(24, 24, 27),
	BackgroundTransparency = 0.08,
	Sidebar = Color3.fromRGB(17, 17, 19),
	Stroke = Color3.fromRGB(48, 48, 53),
	Panel = Color3.fromRGB(31, 31, 34),
	Header = Color3.fromRGB(45, 45, 49),
	HeaderHover = Color3.fromRGB(55, 55, 60),
	Element = Color3.fromRGB(38, 38, 42),
	Checkbox = Color3.fromRGB(50, 50, 55),
	CheckboxHover = Color3.fromRGB(60, 60, 66),
	Track = Color3.fromRGB(42, 42, 46),
	Accent = Color3.fromRGB(66, 133, 230),
	Text = Color3.fromRGB(235, 235, 235),
	SubText = Color3.fromRGB(115, 115, 120),
	IconIdle = Color3.fromRGB(240, 240, 240),
	IconActive = Color3.fromRGB(150, 182, 230),
	Font = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Medium),
	TextSize = 13,
}

-- Window geometry (matches the reference 506x386 layout)
local WINDOW_SIZE = Vector2.new(506, 386)
local SIDEBAR_WIDTH = 62
local CONTENT_LEFT, CONTENT_TOP, CONTENT_RIGHT, CONTENT_BOTTOM = 9, 57, 14, 36
local COLUMN_GAP = 37
local SECTION_GAP = 10
local ITEMS_TOP = 42

-- Color picker popup geometry
local PICKER_WIDTH, PICKER_HEIGHT = 196, 176

----------------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------------

local function new(className, props)
	local inst = Instance.new(className)
	local parent = props.Parent
	props.Parent = nil
	for k, v in props do
		inst[k] = v
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

local function corner(parent, radius)
	return new("UICorner", { CornerRadius = UDim.new(0, radius), Parent = parent })
end

local function tween(obj, time, props)
	local t = TweenService:Create(obj, TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props)
	t:Play()
	return t
end

local function text(props)
	local Theme = Library.Theme
	props.BackgroundTransparency = 1
	props.BorderSizePixel = 0
	props.FontFace = props.FontFace or Theme.Font
	props.TextSize = props.TextSize or Theme.TextSize
	props.TextColor3 = props.TextColor3 or Theme.Text
	return new("TextLabel", props)
end

local function isAsset(id)
	if typeof(id) == "number" then
		return true
	end
	if typeof(id) ~= "string" or id == "" then
		return false
	end
	return id:match("^%d+$") ~= nil or id:find("://") ~= nil
end

local function asset(id)
	if typeof(id) == "number" or (typeof(id) == "string" and id:match("^%d+$")) then
		return "rbxassetid://" .. id
	end
	return id or ""
end

-- Makes obj.name work with both obj.name(...) and obj:name(...)
local function method(obj, name, fn)
	obj[name] = function(first, ...)
		if first == obj then
			return fn(...)
		end
		return fn(first, ...)
	end
end

local function fire(callback, ...)
	if typeof(callback) == "function" then
		task.spawn(callback, ...)
	end
end

local function isClick(input)
	return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
end

-- Input position in the same coordinate space as an IgnoreGuiInset ScreenGui's AbsolutePosition
local function screenPos(input)
	local inset = GuiService:GetGuiInset()
	return Vector2.new(input.Position.X + inset.X, input.Position.Y + inset.Y)
end

local function isInside(guiObject, point)
	local p, s = guiObject.AbsolutePosition, guiObject.AbsoluteSize
	return point.X >= p.X and point.X <= p.X + s.X and point.Y >= p.Y and point.Y <= p.Y + s.Y
end

local function fsAvailable()
	return typeof(writefile) == "function"
		and typeof(readfile) == "function"
		and typeof(isfile) == "function"
		and typeof(isfolder) == "function"
		and typeof(makefolder) == "function"
		and typeof(listfiles) == "function"
		and typeof(delfile) == "function"
end

local function cleanConfigName(name)
	name = tostring(name or ""):gsub("[^%w _%-]", "")
	name = name:match("^%s*(.-)%s*$") or ""
	return name:sub(1, 32)
end

local KEY_NAMES = {
	One = "1", Two = "2", Three = "3", Four = "4", Five = "5",
	Six = "6", Seven = "7", Eight = "8", Nine = "9", Zero = "0",
	MouseButton1 = "Mouse1", MouseButton2 = "Mouse2", MouseButton3 = "Mouse3",
}

-- Shows the key exactly as pressed (E, LeftShift, F5, Mouse2...).
-- Override this if you want a different key display style.
function Library.FormatKey(key)
	if key == nil then
		return "None"
	end
	return KEY_NAMES[key.Name] or key.Name
end

----------------------------------------------------------------------------
-- Columns / Sections / Elements
----------------------------------------------------------------------------

local function createColumn(page, side)
	local Theme = Library.Theme
	local right = side == "Right"
	local frame = new("ScrollingFrame", {
		Name = side,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(right and 1 or 0, 0),
		Position = UDim2.fromScale(right and 1 or 0, 0),
		Size = UDim2.new(0.5, -COLUMN_GAP / 2, 1, 0),
		CanvasSize = UDim2.new(),
		ScrollBarThickness = 2,
		ScrollBarImageColor3 = Theme.Header,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar,
		Parent = page,
	})
	new("UIListLayout", { Padding = UDim.new(0, SECTION_GAP), SortOrder = Enum.SortOrder.LayoutOrder, Parent = frame })

	local column = { Frame = frame, Sections = {} }

	-- Sections size to their content; the last one stretches to fill the column.
	function column.Refresh()
		local sections = column.Sections
		local total = 0
		for _, s in sections do
			total += s.ContentHeight()
		end
		total += SECTION_GAP * math.max(#sections - 1, 0)
		local extra = math.max(frame.AbsoluteSize.Y - total, 0)
		for i, s in sections do
			local h = s.ContentHeight()
			if i == #sections then
				h += extra
			end
			s.Frame.Size = UDim2.new(1, 0, 0, h)
		end
		frame.CanvasSize = UDim2.fromOffset(0, total)
	end

	frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(column.Refresh)
	return column
end

local function createSection(window, column, name, tabName)
	local Theme = Library.Theme
	local connections = window._connections
	local sectionKey = name
	local noRegister = false

	-- Registers an element so configs can save / load it
	local function register(elementName, getFn, setFn)
		if noRegister then
			return
		end
		local base = tostring(tabName) .. "/" .. tostring(sectionKey) .. "/" .. tostring(elementName)
		local n = (window._flagCounts[base] or 0) + 1
		window._flagCounts[base] = n
		local key = n == 1 and base or (base .. "#" .. n)
		window._flags[key] = { get = getFn, set = setFn }
	end

	local frame = new("Frame", {
		Name = name,
		BackgroundColor3 = Theme.Panel,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 100),
		LayoutOrder = #column.Sections + 1,
		Parent = column.Frame,
	})
	corner(frame, 4)

	local header = new("Frame", {
		Name = "Header",
		BackgroundColor3 = Theme.Header,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(12, 12),
		Size = UDim2.new(1, -24, 0, 24),
		Parent = frame,
	})
	corner(header, 3)
	text({ Text = name, Size = UDim2.fromScale(1, 1), Parent = header })

	local items = new("Frame", {
		Name = "Items",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, ITEMS_TOP),
		Size = UDim2.new(1, 0, 0, 0),
		Parent = frame,
	})
	new("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), Parent = items })
	local layout = new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Parent = items })

	local data = { Frame = frame }
	function data.ContentHeight()
		return ITEMS_TOP + layout.AbsoluteContentSize.Y + 12
	end
	table.insert(column.Sections, data)

	layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		items.Size = UDim2.new(1, 0, 0, layout.AbsoluteContentSize.Y)
		column.Refresh()
	end)
	column.Refresh()

	local Section = { Frame = frame }
	local order = 0
	local function row(height)
		order += 1
		return new("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, height),
			LayoutOrder = order,
			Parent = items,
		})
	end

	local function element(api)
		local obj = {}
		for k, fn in api do
			method(obj, k, fn)
		end
		return obj
	end

	------------------------------------------------------------------ Toggle
	method(Section, "Toggle", function(name, default, callback)
		local state = default == true
		local r = row(22)
		local button = new("TextButton", {
			Text = "",
			AutoButtonColor = false,
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			Parent = r,
		})
		local box = new("Frame", {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromScale(0, 0.5),
			Size = UDim2.fromOffset(12, 12),
			BackgroundColor3 = Theme.Checkbox,
			BorderSizePixel = 0,
			Parent = button,
		})
		corner(box, 2)

		-- Checkmark drawn from two rotated bars (no image asset needed)
		local check = new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false, Parent = box })
		new("Frame", {
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(3.9 / 12, 7 / 12),
			Size = UDim2.fromOffset(5, 2),
			Rotation = 45,
			Parent = check,
		})
		new("Frame", {
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(7.1 / 12, 5.9 / 12),
			Size = UDim2.fromOffset(8, 2),
			Rotation = -50,
			Parent = check,
		})

		text({
			Text = name,
			Position = UDim2.fromOffset(18, 0),
			Size = UDim2.new(1, -18, 1, 0),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Parent = button,
		})

		local hovering = false
		local function render()
			check.Visible = state
			tween(box, 0.12, {
				BackgroundColor3 = state and Theme.Accent or (hovering and Theme.CheckboxHover or Theme.Checkbox),
			})
		end

		local function set(value, silent)
			state = value == true
			render()
			if not silent then
				fire(callback, state)
			end
		end

		button.MouseEnter:Connect(function()
			hovering = true
			render()
		end)
		button.MouseLeave:Connect(function()
			hovering = false
			render()
		end)
		button.Activated:Connect(function()
			set(not state)
		end)

		render()
		if state then
			fire(callback, state)
		end

		register(name, function()
			return state
		end, function(d)
			if typeof(d) == "boolean" then
				set(d)
			end
		end)

		return element({
			Set = set,
			Get = function()
				return state
			end,
		})
	end)

	------------------------------------------------------------------ Slider
	method(Section, "Slider", function(name, min, max, default, callback, increment)
		if typeof(min) == "table" then
			local o = min
			callback = max
			min, max, default, increment = o.Min, o.Max, o.Default, o.Increment
			callback = callback or o.Callback
		end
		min = min or 0
		max = max or 100
		increment = increment or 1
		local decimals = increment < 1 and math.max(0, math.ceil(-math.log10(increment) - 1e-9)) or 0
		local value = math.clamp(default or min, min, max)

		local r = row(43)
		text({
			Text = name,
			Size = UDim2.new(1, -50, 0, 18),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Parent = r,
		})
		local valueLabel = text({
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -14, 0, 0),
			Size = UDim2.fromOffset(50, 18),
			TextXAlignment = Enum.TextXAlignment.Right,
			Parent = r,
		})

		local track = new("Frame", {
			BackgroundColor3 = Theme.Track,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(0, 27),
			Size = UDim2.new(1, -14, 0, 6),
			Parent = r,
		})
		corner(track, 3)
		local fill = new("Frame", {
			BackgroundColor3 = Theme.Accent,
			BorderSizePixel = 0,
			Size = UDim2.fromScale(0, 1),
			Parent = track,
		})
		corner(fill, 3)
		local knob = new("Frame", {
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0, 0.5),
			Size = UDim2.fromOffset(12, 12),
			ZIndex = 2,
			Parent = track,
		})
		corner(knob, 6)
		local hit = new("TextButton", {
			Text = "",
			AutoButtonColor = false,
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, -6, 0.5, 0),
			Size = UDim2.new(1, 12, 0, 18),
			ZIndex = 3,
			Parent = track,
		})

		local function format(v)
			return string.format("%." .. decimals .. "f", v)
		end

		local function set(v, silent, instant)
			v = tonumber(v) or min
			v = min + math.floor((v - min) / increment + 0.5) * increment
			v = math.clamp(v, min, max)
			v = tonumber(format(v))
			local changed = v ~= value
			value = v
			local pct = max > min and (v - min) / (max - min) or 0
			valueLabel.Text = format(v)
			local t = instant and 0 or 0.08
			tween(fill, t, { Size = UDim2.fromScale(pct, 1) })
			tween(knob, t, { Position = UDim2.fromScale(pct, 0.5) })
			if changed and not silent then
				fire(callback, v)
			end
		end

		local dragging = false
		local function update(x)
			local pct = math.clamp((x - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1), 0, 1)
			set(min + (max - min) * pct)
		end

		hit.InputBegan:Connect(function(input)
			if isClick(input) then
				dragging = true
				tween(knob, 0.1, { Size = UDim2.fromOffset(14, 14) })
				update(input.Position.X)
			end
		end)
		table.insert(connections, UserInputService.InputChanged:Connect(function(input)
			if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
				update(input.Position.X)
			end
		end))
		table.insert(connections, UserInputService.InputEnded:Connect(function(input)
			if dragging and isClick(input) then
				dragging = false
				tween(knob, 0.1, { Size = UDim2.fromOffset(12, 12) })
			end
		end))

		value = nil
		set(math.clamp(default or min, min, max), true, true)
		fire(callback, value)

		register(name, function()
			return value
		end, function(d)
			if typeof(d) == "number" then
				set(d)
			end
		end)

		return element({
			Set = set,
			Get = function()
				return value
			end,
		})
	end)

	------------------------------------------------------------------ Keybind
	method(Section, "Keybind", function(name, default, callback, pressedCallback)
		local key = default
		local binding = false

		local r = row(52)
		text({
			Text = name,
			Size = UDim2.new(1, 0, 0, 18),
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = r,
		})
		local button = new("TextButton", {
			Text = Library.FormatKey(key),
			AutoButtonColor = false,
			BackgroundColor3 = Theme.Element,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(0, 20),
			Size = UDim2.new(1, -14, 0, 26),
			FontFace = Theme.Font,
			TextSize = Theme.TextSize,
			TextColor3 = Theme.Text,
			Parent = r,
		})
		corner(button, 3)

		button.MouseEnter:Connect(function()
			tween(button, 0.12, { BackgroundTransparency = 0.4 })
		end)
		button.MouseLeave:Connect(function()
			tween(button, 0.12, { BackgroundTransparency = 1 })
		end)

		local function set(newKey, silent)
			key = newKey
			button.Text = Library.FormatKey(key)
			button.TextColor3 = Theme.Text
			if not silent then
				fire(callback, key)
			end
		end

		button.Activated:Connect(function()
			if binding then
				return
			end
			task.defer(function()
				binding = true
				button.Text = "..."
				button.TextColor3 = Theme.SubText
			end)
		end)

		local function matches(input)
			if key == nil then
				return false
			end
			if key.EnumType == Enum.KeyCode then
				return input.KeyCode == key
			end
			return input.UserInputType == key
		end

		table.insert(connections, UserInputService.InputBegan:Connect(function(input, processed)
			if binding then
				local t = input.UserInputType
				if t == Enum.UserInputType.Keyboard then
					binding = false
					if input.KeyCode == Enum.KeyCode.Escape then
						set(key, true) -- cancel
					elseif input.KeyCode == Enum.KeyCode.Backspace then
						set(nil) -- clear
					else
						set(input.KeyCode)
					end
				elseif t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.MouseButton2 or t == Enum.UserInputType.MouseButton3 then
					binding = false
					set(t)
				end
				return
			end
			if matches(input) and not (processed and input.UserInputType == Enum.UserInputType.Keyboard) then
				fire(pressedCallback, key)
			end
		end))

		register(name, function()
			if key == nil then
				return false
			end
			return { Type = key.EnumType == Enum.KeyCode and "KeyCode" or "UserInputType", Name = key.Name }
		end, function(d)
			if d == false then
				set(nil)
			elseif typeof(d) == "table" and (d.Type == "KeyCode" or d.Type == "UserInputType") then
				local ok, e = pcall(function()
					return Enum[d.Type][d.Name]
				end)
				if ok and e then
					set(e)
				end
			end
		end)

		return element({
			Set = set,
			Get = function()
				return key
			end,
			IsDown = function()
				if key == nil then
					return false
				end
				if key.EnumType == Enum.KeyCode then
					return UserInputService:IsKeyDown(key)
				end
				return UserInputService:IsMouseButtonPressed(key)
			end,
		})
	end)

	------------------------------------------------------------------ Dropdown
	method(Section, "Dropdown", function(name, list, default, callback)
		list = list or {}
		local value = default
		local open = false
		local OPTION_HEIGHT = 24
		local BASE_HEIGHT = 56

		local r = row(BASE_HEIGHT)
		text({
			Text = name,
			Size = UDim2.new(1, 0, 0, 18),
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = r,
		})
		local box = new("TextButton", {
			Text = "",
			AutoButtonColor = false,
			BackgroundColor3 = Theme.Element,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(0, 20),
			Size = UDim2.new(1, -30, 0, 30),
			Parent = r,
		})
		corner(box, 3)
		local valueLabel = text({
			Text = value ~= nil and tostring(value) or "...",
			TextColor3 = Theme.SubText,
			Position = UDim2.fromOffset(10, 0),
			Size = UDim2.new(1, -36, 1, 0),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Parent = box,
		})
		local arrow = text({
			Text = "V",
			TextColor3 = Theme.SubText,
			TextSize = 12,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(1, -16, 0.5, 0),
			Size = UDim2.fromOffset(12, 12),
			Parent = box,
		})

		local listFrame = new("Frame", {
			BackgroundColor3 = Theme.Element,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(0, 54),
			Size = UDim2.new(1, -30, 0, 0),
			ClipsDescendants = true,
			Visible = false,
			Parent = r,
		})
		corner(listFrame, 3)
		new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Parent = listFrame })

		local optionButtons = {}
		local set, setOpen

		local function paint()
			for opt, lbl in optionButtons do
				lbl.TextColor3 = opt == value and Theme.Accent or Theme.Text
			end
		end

		local function build()
			for _, child in listFrame:GetChildren() do
				if child:IsA("TextButton") then
					child:Destroy()
				end
			end
			table.clear(optionButtons)
			for i, opt in list do
				local b = new("TextButton", {
					Text = "",
					AutoButtonColor = false,
					BackgroundColor3 = Theme.HeaderHover,
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Size = UDim2.new(1, 0, 0, OPTION_HEIGHT),
					LayoutOrder = i,
					Parent = listFrame,
				})
				optionButtons[opt] = text({
					Text = tostring(opt),
					Position = UDim2.fromOffset(10, 0),
					Size = UDim2.new(1, -20, 1, 0),
					TextXAlignment = Enum.TextXAlignment.Left,
					TextTruncate = Enum.TextTruncate.AtEnd,
					Parent = b,
				})
				b.MouseEnter:Connect(function()
					tween(b, 0.1, { BackgroundTransparency = 0.3 })
				end)
				b.MouseLeave:Connect(function()
					tween(b, 0.1, { BackgroundTransparency = 1 })
				end)
				b.Activated:Connect(function()
					set(opt)
					setOpen(false)
				end)
			end
			paint()
		end

		function setOpen(state)
			open = state
			local listHeight = state and #list * OPTION_HEIGHT or 0
			if state then
				listFrame.Visible = true
			end
			tween(arrow, 0.15, { Rotation = state and 180 or 0 })
			tween(r, 0.15, { Size = UDim2.new(1, 0, 0, BASE_HEIGHT + (state and listHeight + 2 or 0)) })
			local t = tween(listFrame, 0.15, { Size = UDim2.new(1, -30, 0, listHeight) })
			if not state then
				t.Completed:Once(function()
					if not open then
						listFrame.Visible = false
					end
				end)
			end
		end

		function set(opt, silent)
			value = opt
			valueLabel.Text = opt ~= nil and tostring(opt) or "..."
			paint()
			if not silent then
				fire(callback, opt)
			end
		end

		box.MouseEnter:Connect(function()
			tween(box, 0.12, { BackgroundColor3 = Theme.Header })
		end)
		box.MouseLeave:Connect(function()
			tween(box, 0.12, { BackgroundColor3 = Theme.Element })
		end)
		box.Activated:Connect(function()
			setOpen(not open)
		end)

		build()
		if value ~= nil then
			fire(callback, value)
		end

		register(name, function()
			return value
		end, function(d)
			if d ~= nil and table.find(list, d) then
				set(d)
			end
		end)

		return element({
			Set = set,
			Get = function()
				return value
			end,
			Refresh = function(newList, keepValue)
				list = newList or {}
				if not keepValue then
					set(nil, true)
				end
				build()
				if open then
					setOpen(true)
				end
			end,
		})
	end)

	------------------------------------------------------------------ ColorPicker
	method(Section, "ColorPicker", function(name, default, callback)
		local color = typeof(default) == "Color3" and default or Color3.new(1, 1, 1)
		local h, s, v = color:ToHSV()
		local open = false
		local dragMode = nil -- "sv" | "hue" | nil
		local follow = nil

		-- Row: label on the left, colour square on the right
		local r = row(24)
		text({
			Text = name,
			Size = UDim2.new(1, -34, 1, 0),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Parent = r,
		})
		local swatch = new("TextButton", {
			Text = "",
			AutoButtonColor = false,
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -14, 0.5, 0),
			Size = UDim2.fromOffset(16, 16),
			Parent = r,
		})
		corner(swatch, 3)
		local swatchStroke = new("UIStroke", {
			Color = Theme.Stroke,
			Thickness = 1,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			Parent = swatch,
		})
		swatch.MouseEnter:Connect(function()
			tween(swatchStroke, 0.12, { Color = Theme.SubText })
		end)
		swatch.MouseLeave:Connect(function()
			if not open then
				tween(swatchStroke, 0.12, { Color = Theme.Stroke })
			end
		end)

		-- Popup lives on the ScreenGui so the scrolling column never clips it
		local popup = new("Frame", {
			Name = "ColorPicker",
			BackgroundColor3 = Theme.Panel,
			BorderSizePixel = 0,
			Size = UDim2.fromOffset(PICKER_WIDTH, PICKER_HEIGHT),
			Visible = false,
			Active = true,
			ZIndex = 100,
			Parent = window._gui,
		})
		corner(popup, 4)
		new("UIStroke", { Color = Theme.Stroke, Thickness = 1, Parent = popup })

		-- Saturation / Value square
		local sv = new("Frame", {
			BackgroundColor3 = Color3.fromHSV(h, 1, 1),
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(10, 10),
			Size = UDim2.fromOffset(150, 120),
			Parent = popup,
		})
		corner(sv, 3)
		local white = new("Frame", {
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
			Size = UDim2.fromScale(1, 1),
			Parent = sv,
		})
		corner(white, 3)
		new("UIGradient", { Transparency = NumberSequence.new(0, 1), Parent = white })
		local black = new("Frame", {
			BackgroundColor3 = Color3.new(0, 0, 0),
			BorderSizePixel = 0,
			Size = UDim2.fromScale(1, 1),
			Parent = sv,
		})
		corner(black, 3)
		new("UIGradient", { Rotation = 90, Transparency = NumberSequence.new(1, 0), Parent = black })

		local svCursor = new("Frame", {
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(10, 10),
			ZIndex = 3,
			Parent = sv,
		})
		corner(svCursor, 5)
		new("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 1, Parent = svCursor })
		local svHit = new("TextButton", {
			Text = "",
			AutoButtonColor = false,
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 4,
			Parent = sv,
		})

		-- Hue bar
		local hue = new("Frame", {
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(168, 10),
			Size = UDim2.fromOffset(18, 120),
			Parent = popup,
		})
		corner(hue, 3)
		local keypoints = {}
		for i = 0, 6 do
			table.insert(keypoints, ColorSequenceKeypoint.new(i / 6, Color3.fromHSV((i % 6) / 6, 1, 1)))
		end
		new("UIGradient", { Rotation = 90, Color = ColorSequence.new(keypoints), Parent = hue })
		local hueCursor = new("Frame", {
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.new(1, 4, 0, 4),
			ZIndex = 3,
			Parent = hue,
		})
		corner(hueCursor, 2)
		new("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 1, Parent = hueCursor })
		local hueHit = new("TextButton", {
			Text = "",
			AutoButtonColor = false,
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 4,
			Parent = hue,
		})

		-- Hex input
		local hexHolder = new("Frame", {
			BackgroundColor3 = Theme.Element,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(10, 138),
			Size = UDim2.fromOffset(176, 28),
			Parent = popup,
		})
		corner(hexHolder, 3)
		local hexBox = new("TextBox", {
			Text = "",
			PlaceholderText = "#RRGGBB",
			PlaceholderColor3 = Theme.SubText,
			ClearTextOnFocus = false,
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			TextXAlignment = Enum.TextXAlignment.Center,
			FontFace = Theme.Font,
			TextSize = Theme.TextSize,
			TextColor3 = Theme.Text,
			Parent = hexHolder,
		})

		local function render()
			color = Color3.fromHSV(h, s, v)
			swatch.BackgroundColor3 = color
			sv.BackgroundColor3 = Color3.fromHSV(h, 1, 1)
			svCursor.Position = UDim2.fromScale(s, 1 - v)
			hueCursor.Position = UDim2.fromScale(0.5, h)
			if not hexBox:IsFocused() then
				hexBox.Text = "#" .. string.upper(color:ToHex())
			end
		end

		local function updateSV(input)
			local p = screenPos(input)
			s = math.clamp((p.X - sv.AbsolutePosition.X) / math.max(sv.AbsoluteSize.X, 1), 0, 1)
			v = 1 - math.clamp((p.Y - sv.AbsolutePosition.Y) / math.max(sv.AbsoluteSize.Y, 1), 0, 1)
			render()
			fire(callback, color)
		end

		local function updateHue(input)
			local p = screenPos(input)
			h = math.clamp((p.Y - hue.AbsolutePosition.Y) / math.max(hue.AbsoluteSize.Y, 1), 0, 1)
			render()
			fire(callback, color)
		end

		svHit.InputBegan:Connect(function(input)
			if isClick(input) then
				dragMode = "sv"
				updateSV(input)
			end
		end)
		hueHit.InputBegan:Connect(function(input)
			if isClick(input) then
				dragMode = "hue"
				updateHue(input)
			end
		end)
		table.insert(connections, UserInputService.InputChanged:Connect(function(input)
			if not dragMode then
				return
			end
			if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
				if dragMode == "sv" then
					updateSV(input)
				else
					updateHue(input)
				end
			end
		end))
		table.insert(connections, UserInputService.InputEnded:Connect(function(input)
			if dragMode and isClick(input) then
				dragMode = nil
			end
		end))

		hexBox.FocusLost:Connect(function()
			local t = hexBox.Text:gsub("[#%s]", "")
			if #t == 3 then
				t = t:gsub(".", "%0%0")
			end
			if #t == 6 and t:match("^%x+$") then
				local c = Color3.fromRGB(
					tonumber(t:sub(1, 2), 16),
					tonumber(t:sub(3, 4), 16),
					tonumber(t:sub(5, 6), 16)
				)
				h, s, v = c:ToHSV()
				render()
				fire(callback, color)
			else
				render()
			end
		end)

		-- Open / close
		local function reposition()
			local gui = window._gui
			local gs = gui.AbsoluteSize
			local ap, as = swatch.AbsolutePosition, swatch.AbsoluteSize
			local x = math.clamp(ap.X + as.X - PICKER_WIDTH, 4, math.max(gs.X - PICKER_WIDTH - 4, 4))
			local y = ap.Y + as.Y + 6
			if y + PICKER_HEIGHT > gs.Y - 4 then
				y = ap.Y - PICKER_HEIGHT - 6
			end
			popup.Position = UDim2.fromOffset(x, math.max(y, 4))
		end

		local function close()
			if not open then
				return
			end
			open = false
			dragMode = nil
			popup.Visible = false
			if follow then
				follow:Disconnect()
				follow = nil
			end
			if window._closePopup == close then
				window._closePopup = nil
			end
			tween(swatchStroke, 0.12, { Color = Theme.Stroke })
		end

		local function openPicker()
			if window._closePopup then
				window._closePopup()
			end
			open = true
			reposition()
			popup.Visible = true
			window._closePopup = close
			tween(swatchStroke, 0.12, { Color = Theme.Accent })
			follow = RunService.RenderStepped:Connect(reposition)
		end

		swatch.Activated:Connect(function()
			if open then
				close()
			else
				openPicker()
			end
		end)

		-- Click anywhere outside the popup to close it
		table.insert(connections, UserInputService.InputBegan:Connect(function(input)
			if open and isClick(input) then
				local p = screenPos(input)
				if not isInside(popup, p) and not isInside(swatch, p) then
					close()
				end
			end
		end))

		local function set(value, silent)
			if typeof(value) ~= "Color3" then
				return
			end
			h, s, v = value:ToHSV()
			render()
			if not silent then
				fire(callback, color)
			end
		end

		render()
		fire(callback, color)

		register(name, function()
			return {
				math.floor(color.R * 255 + 0.5),
				math.floor(color.G * 255 + 0.5),
				math.floor(color.B * 255 + 0.5),
			}
		end, function(d)
			if typeof(d) == "table" and typeof(d[1]) == "number" and typeof(d[2]) == "number" and typeof(d[3]) == "number" then
				set(Color3.fromRGB(d[1], d[2], d[3]))
			end
		end)

		return element({
			Set = set,
			Get = function()
				return color
			end,
			Close = close,
		})
	end)

	------------------------------------------------------------------ ConfigManager
	method(Section, "ConfigManager", function()
		noRegister = true -- the manager's own widgets must not end up inside configs

		if not fsAvailable() then
			Section.Label("Config saving isn't supported")
			Section.Label("in this environment.")
			noRegister = false
			return element({})
		end

		local selected = nil
		local nameBox, dropdown, autoLabel, status

		local function say(msg)
			status.Set(msg)
		end

		local function updateAutoLabel()
			autoLabel.Set("Autoload: " .. (window.GetAutoload() or "none"))
		end

		local function refresh(select)
			local list = window.ListConfigs()
			dropdown.Refresh(list, true)
			if select ~= nil then
				selected = select
			end
			if selected and table.find(list, selected) then
				dropdown.Set(selected, true)
			else
				selected = nil
				dropdown.Set(nil, true)
			end
		end

		local function needSelected()
			if not selected then
				say("Select a config first")
				return false
			end
			return true
		end

		nameBox = Section.TextBox("Config name :", "enter a name", nil)

		Section.Button("Create config", function()
			local n = cleanConfigName(nameBox.Get())
			if n == "" then
				say("Enter a name first")
			elseif window.ConfigExists(n) then
				say("Already exists")
			else
				local ok, msg = window.SaveConfig(n)
				if ok then
					nameBox.Set("")
					refresh(n)
					say("Created")
				else
					say(msg)
				end
			end
		end)

		dropdown = Section.Dropdown("Configs :", window.ListConfigs(), nil, function(opt)
			selected = opt
		end)

		Section.Button("Load selected", function()
			if needSelected() then
				local ok, msg = window.LoadConfig(selected)
				say(ok and "Loaded" or msg)
			end
		end)

		Section.Button("Overwrite selected", function()
			if needSelected() then
				local ok, msg = window.SaveConfig(selected)
				say(ok and "Overwritten" or msg)
			end
		end)

		Section.Button("Delete selected", function()
			if needSelected() then
				local ok, msg = window.DeleteConfig(selected)
				if ok then
					if window.GetAutoload() == selected then
						window.ClearAutoload()
					end
					selected = nil
					refresh()
					updateAutoLabel()
					say("Deleted")
				else
					say(msg)
				end
			end
		end)

		Section.Button("Set as autoload", function()
			if needSelected() then
				local ok, msg = window.SetAutoload(selected)
				updateAutoLabel()
				say(ok and "Autoload set" or msg)
			end
		end)

		Section.Button("Clear autoload", function()
			window.ClearAutoload()
			updateAutoLabel()
			say("Autoload cleared")
		end)

		autoLabel = Section.Label("")
		status = Section.Label("Ready")
		updateAutoLabel()
		noRegister = false

		-- Apply the autoload config once the script has finished building the UI
		task.defer(function()
			local ok, name = window.LoadAutoload()
			if ok then
				refresh(name)
				say("Autoload applied")
			end
		end)

		return element({
			Refresh = refresh,
		})
	end)

	------------------------------------------------------------------ Button
	method(Section, "Button", function(name, callback)
		local r = row(30)
		local button = new("TextButton", {
			Text = name,
			AutoButtonColor = false,
			BackgroundColor3 = Theme.Header,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(0, 3),
			Size = UDim2.new(1, -14, 0, 24),
			FontFace = Theme.Font,
			TextSize = Theme.TextSize,
			TextColor3 = Theme.Text,
			Parent = r,
		})
		corner(button, 3)
		button.MouseEnter:Connect(function()
			tween(button, 0.12, { BackgroundColor3 = Theme.HeaderHover })
		end)
		button.MouseLeave:Connect(function()
			tween(button, 0.12, { BackgroundColor3 = Theme.Header })
		end)
		button.Activated:Connect(function()
			button.BackgroundColor3 = Theme.Accent
			tween(button, 0.3, { BackgroundColor3 = Theme.HeaderHover })
			fire(callback)
		end)
		return element({
			SetText = function(t)
				button.Text = t
			end,
		})
	end)

	------------------------------------------------------------------ TextBox
	method(Section, "TextBox", function(name, placeholder, callback)
		local r = row(56)
		text({
			Text = name,
			Size = UDim2.new(1, 0, 0, 18),
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = r,
		})
		local holder = new("Frame", {
			BackgroundColor3 = Theme.Element,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(0, 20),
			Size = UDim2.new(1, -30, 0, 30),
			Parent = r,
		})
		corner(holder, 3)
		local box = new("TextBox", {
			Text = "",
			PlaceholderText = placeholder or "",
			PlaceholderColor3 = Theme.SubText,
			ClearTextOnFocus = false,
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(10, 0),
			Size = UDim2.new(1, -20, 1, 0),
			TextXAlignment = Enum.TextXAlignment.Left,
			ClipsDescendants = true,
			FontFace = Theme.Font,
			TextSize = Theme.TextSize,
			TextColor3 = Theme.Text,
			Parent = holder,
		})
		box.Focused:Connect(function()
			tween(holder, 0.12, { BackgroundColor3 = Theme.Header })
		end)
		box.FocusLost:Connect(function(enter)
			tween(holder, 0.12, { BackgroundColor3 = Theme.Element })
			fire(callback, box.Text, enter)
		end)
		register(name, function()
			return box.Text
		end, function(d)
			if typeof(d) == "string" then
				box.Text = d
				fire(callback, d, false)
			end
		end)

		return element({
			Set = function(t)
				box.Text = tostring(t)
			end,
			Get = function()
				return box.Text
			end,
		})
	end)

	------------------------------------------------------------------ Label
	method(Section, "Label", function(content)
		local r = row(20)
		local lbl = text({
			Text = content or "",
			Size = UDim2.fromScale(1, 1),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextWrapped = true,
			Parent = r,
		})
		return element({
			Set = function(t)
				lbl.Text = tostring(t)
			end,
		})
	end)

	return Section
end

----------------------------------------------------------------------------
-- Window
----------------------------------------------------------------------------

Library.Window = function(...)
	local args = { ... }
	if args[1] == Library then
		table.remove(args, 1)
	end
	local title, options = args[1], args[2]
	if typeof(options) ~= "table" then
		options = { Logo = options }
	end
	local Theme = Library.Theme

	local parent = options.Parent
	if not parent then
		local player = Players.LocalPlayer
		assert(player, "[UILibrary] Library.Window must be called from a LocalScript (or pass options.Parent)")
		parent = player:WaitForChild("PlayerGui")
	end

	local Window = { _connections = {}, _closePopup = nil, _flags = {}, _flagCounts = {} }
	local connections = Window._connections
	local tabs = {}
	local toggleKey = options.ToggleKey or Enum.KeyCode.RightShift

	local gui = new("ScreenGui", {
		Name = title or "UILibrary",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 100,
		Parent = parent,
	})
	Window._gui = gui

	local function closePopup()
		if Window._closePopup then
			Window._closePopup()
		end
	end

	local main = new("Frame", {
		Name = "Main",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(WINDOW_SIZE.X, WINDOW_SIZE.Y),
		BackgroundColor3 = Theme.Background,
		BackgroundTransparency = Theme.BackgroundTransparency,
		BorderSizePixel = 0,
		Active = true,
		Parent = gui,
	})
	corner(main, 4)
	new("UIStroke", { Color = Theme.Stroke, Transparency = 0.3, Thickness = 1, Parent = main })

	-- Sidebar
	local sidebar = new("Frame", {
		Name = "Sidebar",
		BackgroundColor3 = Theme.Sidebar,
		BackgroundTransparency = Theme.BackgroundTransparency,
		BorderSizePixel = 0,
		Size = UDim2.new(0, SIDEBAR_WIDTH, 1, 0),
		Active = true,
		Parent = main,
	})
	corner(sidebar, 4)
	new("Frame", { -- squares off the sidebar's right corners
		BackgroundColor3 = Theme.Sidebar,
		BackgroundTransparency = Theme.BackgroundTransparency,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0, 4, 1, 0),
		Parent = sidebar,
	})

	local logo = new("ImageLabel", {
		Name = "Logo",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, 35),
		Size = UDim2.fromOffset(32, 32),
		Image = asset(options.Logo),
		ScaleType = Enum.ScaleType.Fit,
		Parent = sidebar,
	})

	local tabHolder = new("Frame", {
		Name = "Tabs",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 63),
		Size = UDim2.new(1, 0, 1, -63),
		Parent = sidebar,
	})
	new("UIListLayout", { Padding = UDim.new(0, 7), SortOrder = Enum.SortOrder.LayoutOrder, Parent = tabHolder })

	-- Drag strip across the top of the content area
	local topStrip = new("Frame", {
		Name = "DragArea",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(SIDEBAR_WIDTH, 0),
		Size = UDim2.new(1, -SIDEBAR_WIDTH, 0, CONTENT_TOP),
		Active = true,
		Parent = main,
	})

	local content = new("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(SIDEBAR_WIDTH + CONTENT_LEFT, CONTENT_TOP),
		Size = UDim2.new(1, -(SIDEBAR_WIDTH + CONTENT_LEFT + CONTENT_RIGHT), 1, -(CONTENT_TOP + CONTENT_BOTTOM)),
		Parent = main,
	})

	-- Dragging
	local dragging, dragStart, startPos
	local function beginDrag(input)
		if isClick(input) then
			closePopup()
			dragging = true
			dragStart = input.Position
			startPos = main.Position
		end
	end
	sidebar.InputBegan:Connect(beginDrag)
	topStrip.InputBegan:Connect(beginDrag)
	table.insert(connections, UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			local delta = input.Position - dragStart
			main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
		end
	end))
	table.insert(connections, UserInputService.InputEnded:Connect(function(input)
		if isClick(input) then
			dragging = false
		end
	end))

	-- Show / hide
	table.insert(connections, UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and toggleKey and input.KeyCode == toggleKey then
			main.Visible = not main.Visible
			closePopup()
		end
	end))

	local function selectTab(tab)
		closePopup()
		for _, t in tabs do
			local active = t == tab
			t.Page.Visible = active
			tween(t.Icon, 0.15, { [t.ColorProperty] = active and Theme.IconActive or Theme.IconIdle })
		end
	end

	------------------------------------------------------------------ Configs
	local rootFolder = options.Folder
	if not rootFolder then
		rootFolder = cleanConfigName(title)
		if rootFolder == "" then
			rootFolder = "UILibrary"
		end
	end
	local configFolder = rootFolder .. "/configs"
	local autoloadFile = rootFolder .. "/autoload.txt"

	local function configPath(name)
		return configFolder .. "/" .. name .. ".json"
	end

	local function ensureFolders()
		if not isfolder(rootFolder) then
			makefolder(rootFolder)
		end
		if not isfolder(configFolder) then
			makefolder(configFolder)
		end
	end

	method(Window, "ConfigExists", function(name)
		name = cleanConfigName(name)
		if name == "" or not fsAvailable() then
			return false
		end
		local ok, result = pcall(function()
			return isfile(configPath(name))
		end)
		return ok and result == true
	end)

	method(Window, "ListConfigs", function()
		local names = {}
		if not fsAvailable() then
			return names
		end
		pcall(function()
			ensureFolders()
			for _, path in listfiles(configFolder) do
				local n = tostring(path):match("([^/\\]+)%.json$")
				if n then
					table.insert(names, n)
				end
			end
		end)
		table.sort(names)
		return names
	end)

	method(Window, "SaveConfig", function(name)
		name = cleanConfigName(name)
		if name == "" then
			return false, "Invalid name"
		end
		if not fsAvailable() then
			return false, "No file access"
		end
		local data = {}
		for key, flag in Window._flags do
			local ok, value = pcall(flag.get)
			if ok and value ~= nil then
				data[key] = value
			end
		end
		local ok, err = pcall(function()
			ensureFolders()
			writefile(configPath(name), HttpService:JSONEncode(data))
		end)
		if not ok then
			return false, "Save failed"
		end
		return true, name
	end)

	method(Window, "LoadConfig", function(name)
		name = cleanConfigName(name)
		if name == "" then
			return false, "Invalid name"
		end
		if not fsAvailable() then
			return false, "No file access"
		end
		local ok, data = pcall(function()
			return HttpService:JSONDecode(readfile(configPath(name)))
		end)
		if not ok or typeof(data) ~= "table" then
			return false, "Couldn't read config"
		end
		for key, value in data do
			local flag = Window._flags[key]
			if flag then
				pcall(flag.set, value)
			end
		end
		return true, name
	end)

	method(Window, "DeleteConfig", function(name)
		name = cleanConfigName(name)
		if name == "" then
			return false, "Invalid name"
		end
		if not fsAvailable() then
			return false, "No file access"
		end
		local ok = pcall(function()
			if isfile(configPath(name)) then
				delfile(configPath(name))
			end
		end)
		return ok, ok and name or "Delete failed"
	end)

	method(Window, "GetAutoload", function()
		if not fsAvailable() then
			return nil
		end
		local ok, result = pcall(function()
			if isfile(autoloadFile) then
				return cleanConfigName(readfile(autoloadFile))
			end
			return nil
		end)
		if ok and result and result ~= "" then
			return result
		end
		return nil
	end)

	method(Window, "SetAutoload", function(name)
		name = cleanConfigName(name)
		if name == "" then
			return false, "Invalid name"
		end
		if not fsAvailable() then
			return false, "No file access"
		end
		local ok = pcall(function()
			ensureFolders()
			writefile(autoloadFile, name)
		end)
		return ok, ok and name or "Save failed"
	end)

	method(Window, "ClearAutoload", function()
		if not fsAvailable() then
			return false
		end
		local ok = pcall(function()
			if isfile(autoloadFile) then
				delfile(autoloadFile)
			end
		end)
		return ok
	end)

	method(Window, "LoadAutoload", function()
		local name = Window.GetAutoload()
		if name and Window.ConfigExists(name) then
			return Window.LoadConfig(name)
		end
		return false
	end)

	------------------------------------------------------------------ Tab
	method(Window, "Tab", function(icon, name)
		if icon ~= nil and not isAsset(icon) and name == nil then
			name, icon = icon, nil
		end
		local index = #tabs + 1
		name = name or ("Tab" .. index)

		local button = new("TextButton", {
			Name = name,
			Text = "",
			AutoButtonColor = false,
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 30),
			LayoutOrder = index,
			Parent = tabHolder,
		})

		local iconObj, colorProperty
		if isAsset(icon) then
			iconObj = new("ImageLabel", {
				BackgroundTransparency = 1,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(17, 17),
				Image = asset(icon),
				ImageColor3 = Theme.IconIdle,
				ScaleType = Enum.ScaleType.Fit,
				Parent = button,
			})
			colorProperty = "ImageColor3"
		else
			iconObj = text({
				Text = string.upper(string.sub(name, 1, 1)),
				FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold),
				TextSize = 15,
				TextColor3 = Theme.IconIdle,
				Size = UDim2.fromScale(1, 1),
				Parent = button,
			})
			colorProperty = "TextColor3"
		end

		local page = new("Frame", {
			Name = name,
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			Visible = false,
			Parent = content,
		})
		local left = createColumn(page, "Left")
		local right = createColumn(page, "Right")

		local tabData = { Page = page, Icon = iconObj, ColorProperty = colorProperty }
		table.insert(tabs, tabData)

		button.MouseEnter:Connect(function()
			tween(button, 0.1, { BackgroundTransparency = 0.9 })
		end)
		button.MouseLeave:Connect(function()
			tween(button, 0.1, { BackgroundTransparency = 1 })
		end)
		button.Activated:Connect(function()
			selectTab(tabData)
		end)

		if index == 1 then
			selectTab(tabData)
		end

		local Tab = { Page = page }
		local count = 0
		method(Tab, "Section", function(sectionName, side)
			count += 1
			if side ~= "Left" and side ~= "Right" then
				side = (count % 2 == 1) and "Left" or "Right"
			end
			return createSection(Window, side == "Right" and right or left, sectionName or "Section", name)
		end)
		method(Tab, "Select", function()
			selectTab(tabData)
		end)
		return Tab
	end)

	method(Window, "SetLogo", function(id)
		logo.Image = asset(id)
	end)
	method(Window, "SetVisible", function(state)
		main.Visible = state
		closePopup()
	end)
	method(Window, "Toggle", function()
		main.Visible = not main.Visible
		closePopup()
	end)
	method(Window, "SetToggleKey", function(key)
		toggleKey = key
	end)
	method(Window, "Destroy", function()
		closePopup()
		for _, c in connections do
			c:Disconnect()
		end
		table.clear(connections)
		gui:Destroy()
	end)

	Window.Gui = gui
	Window.Main = main
	return Window
end

return Library
