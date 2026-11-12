--[[
	UILibrary 2.0
	-------------
	local Library = require(game.ReplicatedStorage.UILibrary)

	local Window  = Library.Window("Title", {
		Logo = 123456, ToggleKey = Enum.KeyCode.RightShift,
		Folder = "MyHub",        -- config folder (defaults to the title)
		Scale = 1,               -- UI scale (0.5 - 2)
		Size = Vector2.new(506, 386),
		Resizable = true,        -- corner grip
		Search = true,           -- tab search bar
		Animate = true,          -- fade / scale open + close
		MobileButton = nil,      -- nil = auto (touch devices), true / false to force
	})
	local Tab     = Window.Tab(123456)                 -- icon id (or Window.Tab(iconId, "Name"))
	local Section = Tab.Section("Aimbot")              -- auto Left / Right, or Tab.Section("Aimbot", "Right")
	                                                   -- 3rd arg: { Collapsed = true }
	local Sub     = Tab.SubTab("Visuals")              -- sub-tabs; Sub.Section(...) works like Tab.Section(...)

	Elements (every one returns an object; see "Common element API" below)
	  Section.Toggle("Enable", true, function(on) end, { Save = true })
	      :AddKeybind(Enum.KeyCode.E, changedCb, pressedCb, { Mode = "Hold" })   -- inline add-ons
	      :AddColorPicker(Color3.new(1, 0, 0), function(color, alpha) end)
	  Section.Slider("FOV", 0, 360, 116, cb, 1, { Suffix = "°", ShowMinMax = true })
	      -- or (name, {Min, Max, Default, Increment, Suffix, ShowMinMax}, cb). Click the value to type one in.
	  Section.Keybind("Aim Key :", Enum.UserInputType.MouseButton2, changedCb, pressedCb,
	      { Mode = "Hold" | "Toggle" | "Always", OnState = function(active) end, ShowInList = true })
	      -- right-click the button to change the mode. :GetState() / :IsDown() respect the mode.
	  Section.Dropdown("Bone :", {"Head", "Torso"}, "Head", cb, { Multi = false, Search = false, MaxVisible = 6 })
	  Section.PlayerDropdown("Target :", nil, cb, { Multi = false, IncludeLocal = false })   -- auto-refreshes
	  Section.ListBox("Items", {"A", "B"}, nil, cb, { Multi = true, Search = true, Height = 120 })
	  Section.ColorPicker("ESP Color", Color3.fromRGB(66, 133, 230), function(color, alpha) end,
	      { Alpha = true, Rainbow = true, Palette = true })
	  Section.Button("Click me", function() end)
	  Section.TextBox("Name :", "placeholder", function(text, enterPressed) end)
	  Section.Label("Some text")                        -- wraps + auto-sizes
	  Section.Paragraph("Title", "Long body text...")   -- or Paragraph("Body only")
	  Section.Divider() / Section.Divider("Label") / Section.Spacer(8)
	  Section.ProgressBar("Loading", 0, 100, 25)        -- :Set(v)
	  Section.Image(assetId, { Height = 90 })           -- :Set(assetId)
	  Section.ConfigManager()                           -- create / load / overwrite / delete / autoload / export / import
	  Section.WindowSettings()                          -- UI scale, menu key, watermark, keybind list, mobile button

	Common element API (every element):
	  :SetVisible(bool)  :SetDisabled(bool)  :SetName(text)  :SetTooltip(text)  :Destroy()
	  .OnChanged:Connect(function(...) end)             -- separate from the construction callback
	  Most elements also have :Set(value) / :Get().

	Window API
	  Window.Notify({ Title, Text, Duration, Type })    -- also Library.Notify(...), see below
	  Window.SetScale(n)  Window.SetSize(Vector2)  Window.SetVisible(b)  Window.Toggle()  Window.IsVisible()
	  Window.SetToggleKey(key)  Window.SetLogo(id)  Window.SetMobileButton(b)
	  Window.Watermark({ Text, ShowFPS, ShowPing, ShowTime })  Window.SetWatermarkVisible(b)
	  Window.KeybindList()  Window.SetKeybindListVisible(b)
	  Window.Destroy()

	Notifications (no window needed)
	  Library.Notify({ Title = "Hi", Text = "Body", Duration = 4, Type = "Info" | "Success" | "Warning" | "Error" })
	  Library.SetNotifyPosition("BottomRight" | "BottomLeft" | "TopRight" | "TopLeft")

	Configs
	-------
	Every Toggle / Slider / Keybind / Dropdown / ListBox / ColorPicker / TextBox is saved automatically, keyed by
	Tab / Section / Element name (keep names unique and stable). Pass { Save = false } in an element's options to
	exclude it. Files live in <Folder>/configs/<name>.json, autoload in <Folder>/autoload.txt.

	Window.SaveConfig(name) / LoadConfig(name) / DeleteConfig(name) / ListConfigs() / ConfigExists(name)
	Window.SetAutoload(name) / ClearAutoload() / GetAutoload() / LoadAutoload()
	Window.ExportConfig() -> json string        Window.ImportConfig(json) -> ok, label, report
	LoadConfig / ImportConfig return a report: { Unknown = {keys in the file with no element},
	                                             Missing = {elements that weren't in the file} }

	Flags
	-----
	Library.Flags["Tab/Section/Element"] and Window.Flags[...] read the live raw value (booleans, numbers, strings,
	Color3 for pickers, { Key, Mode, Active } for keybinds). Window.GetFlags() returns a snapshot table.

	Misc
	----
	Library.Version, Library.Debug = true (warns with the element name when a callback errors).
	Both dot (Window.Tab) and colon (Window:Tab) calls work.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")
local HttpService = game:GetService("HttpService")
local Stats = game:GetService("Stats")

local Library = {}

Library.Version = "2.0.0"
Library.ConfigVersion = 2
Library.Debug = false
Library.Windows = {}

-- Reads the live raw value of a flag from whichever window owns it
Library.Flags = setmetatable({}, {
	__index = function(_, key)
		for _, w in Library.Windows do
			local flag = w._flags[key]
			if flag then
				local ok, value = pcall(flag.raw)
				if ok then
					return value
				end
			end
		end
		return nil
	end,
})

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
local MIN_WINDOW = Vector2.new(420, 300)
local SIDEBAR_WIDTH = 62
local CONTENT_LEFT, CONTENT_TOP, CONTENT_RIGHT, CONTENT_BOTTOM = 9, 57, 14, 36
local COLUMN_GAP = 37
local SECTION_GAP = 10
local ITEMS_TOP = 42
local COLLAPSED_HEIGHT = 48

local PICKER_WIDTH = 196
local MAX_PALETTE = 8
local MODES = { "Hold", "Toggle", "Always" }

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

-- Wraps a user callback so errors can be reported with the element name when Library.Debug is on
local function guard(callback, label)
	if typeof(callback) ~= "function" then
		return nil
	end
	return function(...)
		if not Library.Debug then
			return callback(...)
		end
		local ok, err = xpcall(callback, debug.traceback, ...)
		if not ok then
			warn(string.format("[UILibrary] error in %s callback: %s", label, tostring(err)))
		end
	end
end

-- Small signal object: sig:Connect(fn) -> { Disconnect }, emit(...) fires every handler
local function newSignal()
	local handlers = {}
	local sig = {}
	method(sig, "Connect", function(fn)
		table.insert(handlers, fn)
		local conn = {}
		method(conn, "Disconnect", function()
			local i = table.find(handlers, fn)
			if i then
				table.remove(handlers, i)
			end
		end)
		return conn
	end)
	local function emit(...)
		for _, fn in table.clone(handlers) do
			fire(fn, ...)
		end
	end
	return sig, emit
end

-- Returns (OnChanged signal, notify) where notify(...) runs the user callback and the signal
local function listener(callback, label)
	local sig, emit = newSignal()
	local cb = guard(callback, label)
	return sig, function(...)
		if cb then
			fire(cb, ...)
		end
		emit(...)
	end
end

local function isClick(input)
	return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
end

local function isMove(input)
	return input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch
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

local function escapeRich(s)
	return (tostring(s):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
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

-- gethui() -> CoreGui -> PlayerGui, whichever works first
local function getGuiParent()
	if typeof(gethui) == "function" then
		local ok, ui = pcall(gethui)
		if ok and typeof(ui) == "Instance" then
			return ui
		end
	end
	local ok = pcall(function()
		local probe = Instance.new("Folder")
		probe.Parent = game:GetService("CoreGui")
		probe:Destroy()
	end)
	if ok then
		return game:GetService("CoreGui")
	end
	local player = Players.LocalPlayer
	if player then
		return player:WaitForChild("PlayerGui")
	end
	return nil
end

local function getPing()
	local ok, value = pcall(function()
		return Stats.Network.ServerStatsItem["Data Ping"]:GetValue()
	end)
	if ok and typeof(value) == "number" then
		return math.floor(value + 0.5)
	end
	local ok2, ping = pcall(function()
		return Players.LocalPlayer:GetNetworkPing()
	end)
	if ok2 and typeof(ping) == "number" then
		return math.floor(ping * 2000 + 0.5)
	end
	return 0
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
-- Notifications
----------------------------------------------------------------------------

local NOTIFY_WIDTH = 260
local MAX_NOTIFICATIONS = 6
local notifyGui, notifyHolder, notifyLayout
local notifyPosition = "BottomRight"
local notifyCount = 0
local notifyActive = {}

local function notifySide()
	return string.find(notifyPosition, "Right") ~= nil, string.find(notifyPosition, "Top") ~= nil
end

local function applyNotifyPosition()
	if not notifyHolder then
		return
	end
	local right, top = notifySide()
	notifyHolder.AnchorPoint = Vector2.new(right and 1 or 0, top and 0 or 1)
	notifyHolder.Position = UDim2.new(right and 1 or 0, right and -12 or 12, top and 0 or 1, top and 12 or -12)
	notifyLayout.HorizontalAlignment = right and Enum.HorizontalAlignment.Right or Enum.HorizontalAlignment.Left
	notifyLayout.VerticalAlignment = top and Enum.VerticalAlignment.Top or Enum.VerticalAlignment.Bottom
end

local function ensureNotifyHost()
	if notifyGui and notifyGui.Parent then
		return
	end
	local parent = getGuiParent()
	assert(parent, "[UILibrary] Library.Notify has nowhere to parent its ScreenGui")
	notifyGui = new("ScreenGui", {
		Name = "UILibraryNotifications",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 1000,
		Parent = parent,
	})
	notifyHolder = new("Frame", {
		Name = "Stack",
		BackgroundTransparency = 1,
		Size = UDim2.new(0, NOTIFY_WIDTH, 1, -24),
		Parent = notifyGui,
	})
	notifyLayout = new("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 8),
		Parent = notifyHolder,
	})
	applyNotifyPosition()
end

function Library.SetNotifyPosition(position)
	if typeof(position) == "string" then
		notifyPosition = position
		applyNotifyPosition()
	end
end

function Library.Notify(a, b, c)
	local Theme = Library.Theme
	local opts
	if typeof(a) == "table" then
		opts = a
	else
		opts = { Title = a, Text = b, Duration = c }
	end
	ensureNotifyHost()

	notifyCount += 1
	local id = notifyCount
	local right, top = notifySide()
	local offscreen = right and (NOTIFY_WIDTH + 24) or -(NOTIFY_WIDTH + 24)
	local colors = {
		Info = Theme.Accent,
		Success = Color3.fromRGB(80, 200, 120),
		Warning = Color3.fromRGB(240, 180, 60),
		Error = Color3.fromRGB(230, 80, 80),
	}
	local accent = colors[opts.Type or "Info"] or Theme.Accent
	local duration = opts.Duration
	if duration == nil then
		duration = 4
	end

	local wrapper = new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(NOTIFY_WIDTH, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = top and -id or id,
		Parent = notifyHolder,
	})
	local card = new("Frame", {
		BackgroundColor3 = Theme.Panel,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Position = UDim2.fromOffset(offscreen, 0),
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = wrapper,
	})
	corner(card, 4)
	new("UIStroke", { Color = Theme.Stroke, Thickness = 1, Parent = card })
	new("Frame", {
		BackgroundColor3 = accent,
		BorderSizePixel = 0,
		Size = UDim2.new(0, 3, 1, 0),
		Parent = card,
	})

	local content = new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = card,
	})
	new("UIPadding", {
		PaddingLeft = UDim.new(0, 14),
		PaddingRight = UDim.new(0, 10),
		PaddingTop = UDim.new(0, 8),
		PaddingBottom = UDim.new(0, 10),
		Parent = content,
	})
	new("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder, Parent = content })

	if opts.Title and opts.Title ~= "" then
		text({
			Text = tostring(opts.Title),
			FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold),
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = 1,
			Parent = content,
		})
	end
	if opts.Text and opts.Text ~= "" then
		text({
			Text = tostring(opts.Text),
			TextColor3 = Theme.SubText,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = 2,
			Parent = content,
		})
	end

	local closed = false
	local handle = {}
	local function close()
		if closed then
			return
		end
		closed = true
		local i = table.find(notifyActive, handle)
		if i then
			table.remove(notifyActive, i)
		end
		local t = tween(card, 0.2, { Position = UDim2.fromOffset(offscreen, 0) })
		t.Completed:Once(function()
			wrapper:Destroy()
		end)
	end
	method(handle, "Close", close)

	local clickArea = new("TextButton", {
		Text = "",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 5,
		Parent = card,
	})
	clickArea.Activated:Connect(close)

	if typeof(duration) == "number" and duration > 0 and duration < math.huge then
		local bar = new("Frame", {
			BackgroundColor3 = accent,
			BackgroundTransparency = 0.3,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.new(1, 0, 0, 2),
			ZIndex = 4,
			Parent = card,
		})
		TweenService:Create(bar, TweenInfo.new(duration, Enum.EasingStyle.Linear), { Size = UDim2.new(0, 0, 0, 2) }):Play()
		task.delay(duration, close)
	end

	table.insert(notifyActive, handle)
	if #notifyActive > MAX_NOTIFICATIONS then
		local oldest = notifyActive[1]
		oldest.Close()
	end

	tween(card, 0.25, { Position = UDim2.fromOffset(0, 0) })
	return handle
end

----------------------------------------------------------------------------
-- Shared widgets
----------------------------------------------------------------------------

-- Selection model shared by Dropdown and ListBox (single or multi)
local function selectionModel(list, multi, default)
	local m = { List = list, Selected = {}, Value = nil }

	function m.Assign(v)
		table.clear(m.Selected)
		m.Value = nil
		if multi then
			if typeof(v) == "table" then
				for _, o in v do
					m.Selected[o] = true
				end
			elseif v ~= nil then
				m.Selected[v] = true
			end
		else
			m.Value = v
		end
	end

	function m.IsSelected(o)
		if multi then
			return m.Selected[o] == true
		end
		return o == m.Value
	end

	function m.Pick(o)
		if multi then
			m.Selected[o] = not m.Selected[o] or nil
		else
			m.Value = o
		end
	end

	function m.Get()
		if multi then
			local out = {}
			for _, o in m.List do
				if m.Selected[o] then
					table.insert(out, o)
				end
			end
			return out
		end
		return m.Value
	end

	function m.Text()
		if multi then
			local l = m.Get()
			if #l == 0 then
				return "..."
			end
			local parts = {}
			for _, o in l do
				table.insert(parts, tostring(o))
			end
			return table.concat(parts, ", ")
		end
		return m.Value ~= nil and tostring(m.Value) or "..."
	end

	-- Drops selections that are no longer in the list. Returns true if anything changed.
	function m.Prune()
		local changed = false
		if multi then
			for o in m.Selected do
				if not table.find(m.List, o) then
					m.Selected[o] = nil
					changed = true
				end
			end
		elseif m.Value ~= nil and not table.find(m.List, m.Value) then
			m.Value = nil
			changed = true
		end
		return changed
	end

	-- Returns a version of v that only contains options present in the list
	function m.Sanitize(v)
		if multi then
			if typeof(v) ~= "table" then
				return nil
			end
			local out = {}
			for _, o in v do
				if table.find(m.List, o) then
					table.insert(out, o)
				end
			end
			return out
		end
		if v ~= nil and table.find(m.List, v) then
			return v
		end
		return nil
	end

	m.Assign(default)
	return m
end

-- Scrollable list of option rows, with optional search filtering
local function createOptionList(scroll, rowHeight, multi)
	local Theme = Library.Theme
	new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Parent = scroll })
	local self = { Filter = "", Entries = {}, Count = 0 }

	function self.Paint(isSelected)
		for _, e in self.Entries do
			local sel = isSelected(e.Opt)
			e.Label.TextColor3 = sel and Theme.Accent or Theme.Text
			e.Mark.Visible = multi and sel
		end
	end

	function self.Build(list, isSelected, onPick)
		for _, child in scroll:GetChildren() do
			if child:IsA("TextButton") then
				child:Destroy()
			end
		end
		table.clear(self.Entries)
		local filter = string.lower(self.Filter)
		local n = 0
		for _, opt in list do
			local label = tostring(opt)
			if filter == "" or string.find(string.lower(label), filter, 1, true) then
				n += 1
				local b = new("TextButton", {
					Text = "",
					AutoButtonColor = false,
					BackgroundColor3 = Theme.HeaderHover,
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Size = UDim2.new(1, 0, 0, rowHeight),
					LayoutOrder = n,
					Parent = scroll,
				})
				local lbl = text({
					Text = label,
					Position = UDim2.fromOffset(10, 0),
					Size = UDim2.new(1, -(multi and 34 or 20), 1, 0),
					TextXAlignment = Enum.TextXAlignment.Left,
					TextTruncate = Enum.TextTruncate.AtEnd,
					Parent = b,
				})
				local mark = new("Frame", {
					BackgroundColor3 = Theme.Accent,
					BorderSizePixel = 0,
					AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.new(1, -10, 0.5, 0),
					Size = UDim2.fromOffset(8, 8),
					Visible = false,
					Parent = b,
				})
				corner(mark, 2)
				b.MouseEnter:Connect(function()
					tween(b, 0.1, { BackgroundTransparency = 0.3 })
				end)
				b.MouseLeave:Connect(function()
					tween(b, 0.1, { BackgroundTransparency = 1 })
				end)
				b.Activated:Connect(function()
					onPick(opt)
				end)
				table.insert(self.Entries, { Opt = opt, Label = lbl, Mark = mark })
			end
		end
		self.Count = n
		scroll.CanvasSize = UDim2.fromOffset(0, n * rowHeight)
		self.Paint(isSelected)
	end

	return self
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

	-- Visible sections size to their content; the last open one stretches to fill the column.
	function column.Refresh()
		local visible = {}
		for _, s in column.Sections do
			if s.Frame.Visible then
				table.insert(visible, s)
			end
		end
		local total = 0
		for _, s in visible do
			total += s.ContentHeight()
		end
		total += SECTION_GAP * math.max(#visible - 1, 0)
		local extra = math.max(frame.AbsoluteSize.Y - total, 0)
		for i, s in visible do
			local h = s.ContentHeight()
			if i == #visible and not s.Collapsed then
				h += extra
			end
			s.Frame.Size = UDim2.new(1, 0, 0, h)
		end
		frame.CanvasSize = UDim2.fromOffset(0, total)
	end

	frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(column.Refresh)
	return column
end

local function createSection(window, column, name, tabName, sectionOptions)
	local Theme = Library.Theme
	local connections = window._connections
	sectionOptions = sectionOptions or {}
	local noRegister = false
	local entries = {}
	local Section = {}

	local frame = new("Frame", {
		Name = name,
		BackgroundColor3 = Theme.Panel,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 100),
		LayoutOrder = #column.Sections + 1,
		Parent = column.Frame,
	})
	corner(frame, 4)

	local header = new("TextButton", {
		Name = "Header",
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Theme.Header,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(12, 12),
		Size = UDim2.new(1, -24, 0, 24),
		Parent = frame,
	})
	corner(header, 3)
	text({ Text = name, Size = UDim2.fromScale(1, 1), Parent = header })
	local arrow = text({
		Text = "V",
		TextColor3 = Theme.SubText,
		TextSize = 11,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -8, 0.5, 0),
		Size = UDim2.fromOffset(12, 12),
		Parent = header,
	})
	header.MouseEnter:Connect(function()
		tween(header, 0.12, { BackgroundColor3 = Theme.HeaderHover })
	end)
	header.MouseLeave:Connect(function()
		tween(header, 0.12, { BackgroundColor3 = Theme.Header })
	end)

	local items = new("Frame", {
		Name = "Items",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, ITEMS_TOP),
		Size = UDim2.new(1, 0, 0, 0),
		Parent = frame,
	})
	new("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), Parent = items })
	local layout = new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Parent = items })

	local data = { Frame = frame, Collapsed = false, FilteredOut = false }
	function data.ContentHeight()
		if data.Collapsed then
			return COLLAPSED_HEIGHT
		end
		return ITEMS_TOP + layout.AbsoluteContentSize.Y + 12
	end

	local function setCollapsed(state)
		data.Collapsed = state == true
		items.Visible = not data.Collapsed
		tween(arrow, 0.15, { Rotation = data.Collapsed and -90 or 0 })
		column.Refresh()
	end
	header.Activated:Connect(function()
		setCollapsed(not data.Collapsed)
	end)

	-- Hides elements that don't match the tab search query (and the whole section if nothing matches)
	function data.Filter(query)
		query = string.lower(query or "")
		local sectionMatch = query == "" or string.find(string.lower(name), query, 1, true) ~= nil
		local any = sectionMatch
		for _, e in entries do
			local match = sectionMatch or string.find(string.lower(tostring(e.Name or "")), query, 1, true) ~= nil
			e.Filtered = not match
			e.Apply()
			if match then
				any = true
			end
		end
		data.FilteredOut = not any
		frame.Visible = any
		column.Refresh()
	end

	table.insert(column.Sections, data)

	layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		items.Size = UDim2.new(1, 0, 0, layout.AbsoluteContentSize.Y)
		column.Refresh()
	end)
	column.Refresh()

	Section.Frame = frame
	method(Section, "SetCollapsed", setCollapsed)
	method(Section, "IsCollapsed", function()
		return data.Collapsed
	end)

	local order = 0

	local function track(entry, c)
		table.insert(connections, c)
		if entry then
			table.insert(entry.Conns, c)
		end
		return c
	end

	-- Registers an element so configs and Flags can see it
	local function register(entry, elementName, serialGet, serialSet, rawGet, save)
		if noRegister then
			return
		end
		local base = tostring(tabName) .. "/" .. tostring(name) .. "/" .. tostring(elementName)
		local n = (window._flagCounts[base] or 0) + 1
		window._flagCounts[base] = n
		local key = n == 1 and base or (base .. "#" .. n)
		window._flags[key] = { get = serialGet, set = serialSet, raw = rawGet or serialGet, save = save ~= false }
		table.insert(entry.FlagKeys, key)
	end

	local function row(height, elementName)
		order += 1
		local r = new("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, height),
			LayoutOrder = order,
			Parent = items,
		})
		local entry = {
			Row = r,
			Name = elementName,
			Hidden = false,
			Filtered = false,
			Disabled = false,
			Tooltip = nil,
			Conns = {},
			FlagKeys = {},
			Cleanup = {},
		}
		function entry.Apply()
			r.Visible = not entry.Hidden and not entry.Filtered
		end
		table.insert(entries, entry)
		r.MouseEnter:Connect(function()
			if entry.Tooltip then
				window._tooltipShow(entry.Tooltip)
			end
		end)
		r.MouseLeave:Connect(function()
			window._tooltipHide()
		end)
		return r, entry
	end

	local function destroyEntry(entry)
		window._tooltipHide()
		for _, fn in entry.Cleanup do
			pcall(fn)
		end
		for _, c in entry.Conns do
			c:Disconnect()
		end
		for _, key in entry.FlagKeys do
			window._flags[key] = nil
		end
		local i = table.find(entries, entry)
		if i then
			table.remove(entries, i)
		end
		entry.Row:Destroy()
	end

	-- Builds the object returned to the user, adding the common element API
	local function element(api, entry, nameLabel, sig)
		local obj = {}
		for k, fn in api do
			method(obj, k, fn)
		end
		obj.OnChanged = sig
		method(obj, "SetVisible", function(v)
			entry.Hidden = v == false
			entry.Apply()
		end)
		method(obj, "SetDisabled", function(v)
			entry.Disabled = v == true
			if not entry.Overlay then
				if not entry.Disabled then
					return
				end
				entry.Overlay = new("Frame", {
					BackgroundColor3 = Theme.Panel,
					BackgroundTransparency = 0.45,
					BorderSizePixel = 0,
					Size = UDim2.fromScale(1, 1),
					Active = true,
					ZIndex = 20,
					Parent = entry.Row,
				})
			end
			entry.Overlay.Visible = entry.Disabled
		end)
		method(obj, "SetName", function(t)
			entry.Name = tostring(t)
			if nameLabel then
				nameLabel.Text = entry.Name
			end
		end)
		method(obj, "SetTooltip", function(t)
			entry.Tooltip = t
		end)
		method(obj, "Destroy", function()
			destroyEntry(entry)
		end)
		return obj
	end

	-- Object for inline add-ons (toggle keybinds / color pickers)
	local function addon(api, sig, ui)
		local obj = {}
		for k, fn in api do
			method(obj, k, fn)
		end
		obj.OnChanged = sig
		method(obj, "SetVisible", function(v)
			ui.Visible = v ~= false
		end)
		return obj
	end

	------------------------------------------------------------------ Keybind core (shared by Keybind + Toggle:AddKeybind)
	local function bindCore(entry, label, default, callback, pressedCallback, options, button, modeLabel)
		options = options or {}
		local key = default
		local mode = table.find(MODES, options.Mode) and options.Mode or "Hold"
		local state = false
		local binding = false
		local lastBind = 0
		local sig, notify = listener(callback, "Keybind '" .. label .. "'")
		local pressedFn = guard(pressedCallback, "Keybind '" .. label .. "' pressed")
		local stateFn = guard(options.OnState, "Keybind '" .. label .. "' state")
		local modeFn = guard(options.OnModeChanged, "Keybind '" .. label .. "' mode")

		local function physicallyDown()
			if key == nil then
				return false
			end
			if key.EnumType == Enum.KeyCode then
				return UserInputService:IsKeyDown(key)
			end
			return UserInputService:IsMouseButtonPressed(key)
		end

		local function setState(v)
			v = v == true
			if v == state then
				return
			end
			state = v
			window._kbDirty = true
			fire(stateFn, state)
		end

		local function refreshState()
			if mode == "Always" then
				setState(true)
			elseif mode == "Hold" then
				setState(physicallyDown())
			else
				setState(false)
			end
		end

		local function setMode(m, silent)
			if not table.find(MODES, m) then
				return
			end
			mode = m
			if modeLabel then
				modeLabel.Text = m
			end
			refreshState()
			window._kbDirty = true
			if not silent then
				fire(modeFn, m)
			end
		end

		local function set(newKey, silent)
			key = newKey
			button.Text = Library.FormatKey(key)
			button.TextColor3 = Theme.Text
			refreshState()
			window._kbDirty = true
			if not silent then
				notify(key)
			end
		end

		local function matches(input)
			if key == nil then
				return false
			end
			if key.EnumType == Enum.KeyCode then
				return input.KeyCode == key
			end
			return input.UserInputType == key
		end

		button.Text = Library.FormatKey(key)
		if modeLabel then
			modeLabel.Text = mode
		end
		refreshState()

		button.Activated:Connect(function()
			if binding then
				return
			end
			task.defer(function()
				binding = true
				window._binding = true
				button.Text = "..."
				button.TextColor3 = Theme.SubText
			end)
		end)

		button.MouseButton2Click:Connect(function()
			if binding or os.clock() - lastBind < 0.3 then
				return
			end
			window._openModeMenu(button, mode, function(m)
				setMode(m)
			end)
		end)

		track(entry, UserInputService.InputBegan:Connect(function(input, processed)
			if binding then
				local t = input.UserInputType
				if t == Enum.UserInputType.Keyboard then
					binding = false
					window._binding = false
					lastBind = os.clock()
					if input.KeyCode == Enum.KeyCode.Escape then
						set(key, true) -- cancel
					elseif input.KeyCode == Enum.KeyCode.Backspace then
						set(nil) -- clear
					else
						set(input.KeyCode)
					end
				elseif t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.MouseButton2 or t == Enum.UserInputType.MouseButton3 then
					binding = false
					window._binding = false
					lastBind = os.clock()
					set(t)
				end
				return
			end
			if entry.Disabled then
				return
			end
			if matches(input) and not (processed and input.UserInputType == Enum.UserInputType.Keyboard) then
				fire(pressedFn, key)
				if mode == "Hold" then
					setState(true)
				elseif mode == "Toggle" then
					setState(not state)
				end
			end
		end))

		track(entry, UserInputService.InputEnded:Connect(function(input)
			if mode == "Hold" and not binding and matches(input) then
				setState(false)
			end
		end))

		local info = {
			Name = options.ListName or label,
			Show = options.ShowInList ~= false,
			GetKey = function()
				return key
			end,
			GetState = function()
				return state
			end,
			GetMode = function()
				return mode
			end,
		}
		table.insert(window._keybinds, info)
		table.insert(entry.Cleanup, function()
			local i = table.find(window._keybinds, info)
			if i then
				table.remove(window._keybinds, i)
			end
			window._kbDirty = true
		end)

		register(entry, label, function()
			if key == nil then
				return { None = true, Mode = mode }
			end
			return { Type = key.EnumType == Enum.KeyCode and "KeyCode" or "UserInputType", Name = key.Name, Mode = mode }
		end, function(d)
			if d == false then
				set(nil)
			elseif typeof(d) == "table" then
				if d.Mode then
					setMode(d.Mode)
				end
				if d.None then
					set(nil)
				elseif d.Type == "KeyCode" or d.Type == "UserInputType" then
					local ok, e = pcall(function()
						return Enum[d.Type][d.Name]
					end)
					if ok and e then
						set(e)
					end
				end
			end
		end, function()
			return { Key = key, Mode = mode, Active = state }
		end, options.Save)

		local function isActive()
			if mode == "Hold" then
				return physicallyDown()
			end
			return state
		end

		return {
			Signal = sig,
			Api = {
				Set = set,
				Get = function()
					return key
				end,
				GetState = isActive,
				IsDown = isActive,
				SetMode = setMode,
				GetMode = function()
					return mode
				end,
			},
		}
	end

	------------------------------------------------------------------ Color picker core (shared by ColorPicker + Toggle:AddColorPicker)
	local function pickerCore(entry, label, default, callback, options, swatch, save)
		options = options or {}
		local useAlpha = options.Alpha ~= false
		local useRainbow = options.Rainbow ~= false
		local usePalette = options.Palette ~= false

		local color = typeof(default) == "Color3" and default or Color3.new(1, 1, 1)
		local h, s, v = color:ToHSV()
		local alpha = math.clamp(options.DefaultAlpha or 1, 0, 1)
		local rainbow = false
		local open = false
		local dragMode = nil -- "sv" | "hue" | "alpha" | nil
		local follow = nil
		local rainbowConn = nil
		local sig, notify = listener(callback, "ColorPicker '" .. label .. "'")

		-- Popup layout
		local y = 10 + 120 + 8
		local alphaY, hexY, paletteY
		if useAlpha then
			alphaY = y
			y += 12 + 8
		end
		hexY = y
		y += 26
		if usePalette then
			y += 8
			paletteY = y
			y += 16
		end
		local popupHeight = y + 10

		swatch.BackgroundColor3 = color
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
			Size = UDim2.fromOffset(PICKER_WIDTH, popupHeight),
			Visible = false,
			Active = true,
			ZIndex = 100,
			Parent = window._gui,
		})
		corner(popup, 4)
		new("UIStroke", { Color = Theme.Stroke, Thickness = 1, Parent = popup })
		window._trackScale(popup)

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
			ZIndex = 103,
			Parent = sv,
		})
		corner(svCursor, 5)
		new("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 1, Parent = svCursor })
		local svHit = new("TextButton", {
			Text = "",
			AutoButtonColor = false,
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 104,
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
			ZIndex = 103,
			Parent = hue,
		})
		corner(hueCursor, 2)
		new("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 1, Parent = hueCursor })
		local hueHit = new("TextButton", {
			Text = "",
			AutoButtonColor = false,
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 104,
			Parent = hue,
		})

		-- Alpha bar
		local alphaFill, alphaCursor, alphaHit, alphaBar
		if useAlpha then
			alphaBar = new("Frame", {
				BackgroundColor3 = Theme.Track,
				BorderSizePixel = 0,
				Position = UDim2.fromOffset(10, alphaY),
				Size = UDim2.fromOffset(176, 12),
				Parent = popup,
			})
			corner(alphaBar, 3)
			alphaFill = new("Frame", {
				BackgroundColor3 = color,
				BorderSizePixel = 0,
				Size = UDim2.fromScale(1, 1),
				Parent = alphaBar,
			})
			corner(alphaFill, 3)
			new("UIGradient", { Transparency = NumberSequence.new(1, 0), Parent = alphaFill })
			alphaCursor = new("Frame", {
				BackgroundColor3 = Color3.new(1, 1, 1),
				BorderSizePixel = 0,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Size = UDim2.new(0, 4, 1, 4),
				ZIndex = 103,
				Parent = alphaBar,
			})
			corner(alphaCursor, 2)
			new("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 1, Parent = alphaCursor })
			alphaHit = new("TextButton", {
				Text = "",
				AutoButtonColor = false,
				BackgroundTransparency = 1,
				Size = UDim2.fromScale(1, 1),
				ZIndex = 104,
				Parent = alphaBar,
			})
		end

		-- Hex input (+ rainbow button)
		local hexHolder = new("Frame", {
			BackgroundColor3 = Theme.Element,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(10, hexY),
			Size = UDim2.fromOffset(useRainbow and 118 or 176, 26),
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

		local rainbowBtn
		if useRainbow then
			rainbowBtn = new("TextButton", {
				Text = "Rainbow",
				AutoButtonColor = false,
				BackgroundColor3 = Theme.Element,
				BorderSizePixel = 0,
				Position = UDim2.fromOffset(134, hexY),
				Size = UDim2.fromOffset(52, 26),
				FontFace = Theme.Font,
				TextSize = 11,
				TextColor3 = Theme.SubText,
				Parent = popup,
			})
			corner(rainbowBtn, 3)
		end

		-- Saved color palette (shared by every picker in the window)
		local paletteHolder
		if usePalette then
			paletteHolder = new("Frame", {
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(10, paletteY),
				Size = UDim2.fromOffset(176, 16),
				Parent = popup,
			})
		end

		local function render()
			color = Color3.fromHSV(h, s, v)
			swatch.BackgroundColor3 = color
			sv.BackgroundColor3 = Color3.fromHSV(h, 1, 1)
			svCursor.Position = UDim2.fromScale(s, 1 - v)
			hueCursor.Position = UDim2.fromScale(0.5, h)
			if alphaFill then
				alphaFill.BackgroundColor3 = color
				alphaCursor.Position = UDim2.fromScale(alpha, 0.5)
			end
			if not hexBox:IsFocused() then
				hexBox.Text = "#" .. string.upper(color:ToHex())
			end
		end

		local function setRainbow(on)
			rainbow = on == true
			if rainbowBtn then
				rainbowBtn.BackgroundColor3 = rainbow and Theme.Accent or Theme.Element
				rainbowBtn.TextColor3 = rainbow and Color3.new(1, 1, 1) or Theme.SubText
			end
			if rainbowConn then
				rainbowConn:Disconnect()
				rainbowConn = nil
			end
			if rainbow then
				if s < 0.2 then
					s = 1
				end
				if v < 0.2 then
					v = 1
				end
				local acc = 0
				rainbowConn = RunService.Heartbeat:Connect(function(dt)
					h = (h + dt * 0.25) % 1
					render()
					acc += dt
					if acc >= 1 / 30 then
						acc = 0
						notify(color, alpha)
					end
				end)
			end
		end

		local function updateSV(input)
			local p = screenPos(input)
			s = math.clamp((p.X - sv.AbsolutePosition.X) / math.max(sv.AbsoluteSize.X, 1), 0, 1)
			v = 1 - math.clamp((p.Y - sv.AbsolutePosition.Y) / math.max(sv.AbsoluteSize.Y, 1), 0, 1)
			render()
			notify(color, alpha)
		end

		local function updateHue(input)
			local p = screenPos(input)
			h = math.clamp((p.Y - hue.AbsolutePosition.Y) / math.max(hue.AbsoluteSize.Y, 1), 0, 1)
			render()
			notify(color, alpha)
		end

		local function updateAlpha(input)
			local p = screenPos(input)
			alpha = math.clamp((p.X - alphaBar.AbsolutePosition.X) / math.max(alphaBar.AbsoluteSize.X, 1), 0, 1)
			render()
			notify(color, alpha)
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
				if rainbow then
					setRainbow(false)
				end
				updateHue(input)
			end
		end)
		if alphaHit then
			alphaHit.InputBegan:Connect(function(input)
				if isClick(input) then
					dragMode = "alpha"
					updateAlpha(input)
				end
			end)
		end
		track(entry, UserInputService.InputChanged:Connect(function(input)
			if not dragMode or not isMove(input) then
				return
			end
			if dragMode == "sv" then
				updateSV(input)
			elseif dragMode == "hue" then
				updateHue(input)
			else
				updateAlpha(input)
			end
		end))
		track(entry, UserInputService.InputEnded:Connect(function(input)
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
				if rainbow then
					setRainbow(false)
				end
				h, s, v = c:ToHSV()
				render()
				notify(color, alpha)
			else
				render()
			end
		end)

		if rainbowBtn then
			rainbowBtn.Activated:Connect(function()
				setRainbow(not rainbow)
				notify(color, alpha)
			end)
		end

		local function setColor(c)
			if rainbow then
				setRainbow(false)
			end
			h, s, v = c:ToHSV()
			render()
			notify(color, alpha)
		end

		local function refreshPalette()
			if not paletteHolder then
				return
			end
			for _, child in paletteHolder:GetChildren() do
				if child:IsA("TextButton") then
					child:Destroy()
				end
			end
			local addBtn = new("TextButton", {
				Text = "+",
				AutoButtonColor = false,
				BackgroundColor3 = Theme.Element,
				BorderSizePixel = 0,
				Position = UDim2.fromOffset(0, 0),
				Size = UDim2.fromOffset(16, 16),
				FontFace = Theme.Font,
				TextSize = 14,
				TextColor3 = Theme.SubText,
				ZIndex = 101,
				Parent = paletteHolder,
			})
			corner(addBtn, 3)
			addBtn.Activated:Connect(function()
				window._addPalette(color)
			end)
			for i, c in window._palette do
				local cell = new("TextButton", {
					Text = "",
					AutoButtonColor = false,
					BackgroundColor3 = c,
					BorderSizePixel = 0,
					Position = UDim2.fromOffset(i * 20, 0),
					Size = UDim2.fromOffset(16, 16),
					ZIndex = 101,
					Parent = paletteHolder,
				})
				corner(cell, 3)
				new("UIStroke", { Color = Theme.Stroke, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = cell })
				cell.Activated:Connect(function()
					setColor(c)
				end)
				cell.MouseButton2Click:Connect(function()
					window._removePalette(i)
				end)
			end
		end
		if usePalette then
			table.insert(window._paletteViews, refreshPalette)
			refreshPalette()
		end

		-- Open / close
		local function reposition()
			local gs = window._gui.AbsoluteSize
			local sc = window._scale
			local pw, ph = PICKER_WIDTH * sc, popupHeight * sc
			local ap, as = swatch.AbsolutePosition, swatch.AbsoluteSize
			local x = math.clamp(ap.X + as.X - pw, 4, math.max(gs.X - pw - 4, 4))
			local py = ap.Y + as.Y + 6
			if py + ph > gs.Y - 4 then
				py = ap.Y - ph - 6
			end
			popup.Position = UDim2.fromOffset(x, math.max(py, 4))
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
		track(entry, UserInputService.InputBegan:Connect(function(input)
			if open and isClick(input) then
				local p = screenPos(input)
				if not isInside(popup, p) and not isInside(swatch, p) then
					close()
				end
			end
		end))

		local function cleanup()
			if rainbowConn then
				rainbowConn:Disconnect()
				rainbowConn = nil
			end
			close()
		end
		table.insert(entry.Cleanup, function()
			cleanup()
			popup:Destroy()
		end)
		table.insert(window._cleanups, cleanup)

		local function set(value, a, silent)
			if typeof(a) == "boolean" then
				silent = a
				a = nil
			end
			if typeof(value) ~= "Color3" then
				return
			end
			if typeof(a) == "number" then
				alpha = math.clamp(a, 0, 1)
			end
			h, s, v = value:ToHSV()
			render()
			if not silent then
				notify(color, alpha)
			end
		end

		render()
		notify(color, alpha)

		register(entry, label, function()
			return {
				R = math.floor(color.R * 255 + 0.5),
				G = math.floor(color.G * 255 + 0.5),
				B = math.floor(color.B * 255 + 0.5),
				A = math.floor(alpha * 100 + 0.5) / 100,
				Rainbow = rainbow,
			}
		end, function(d)
			if typeof(d) ~= "table" then
				return
			end
			local r, g, b = d.R or d[1], d.G or d[2], d.B or d[3]
			if typeof(r) == "number" and typeof(g) == "number" and typeof(b) == "number" then
				set(Color3.fromRGB(r, g, b), typeof(d.A) == "number" and d.A or nil)
				if d.Rainbow ~= nil then
					setRainbow(d.Rainbow)
				end
			end
		end, function()
			return color
		end, save)

		if options.DefaultRainbow == true then
			setRainbow(true)
		end

		return {
			Signal = sig,
			Api = {
				Set = set,
				Get = function()
					return color
				end,
				GetAlpha = function()
					return alpha
				end,
				SetAlpha = function(a)
					alpha = math.clamp(tonumber(a) or 1, 0, 1)
					render()
					notify(color, alpha)
				end,
				SetRainbow = function(on)
					setRainbow(on)
					notify(color, alpha)
				end,
				IsRainbow = function()
					return rainbow
				end,
				Close = close,
			},
		}
	end

	------------------------------------------------------------------ Toggle
	method(Section, "Toggle", function(name, default, callback, options)
		options = options or {}
		local label = tostring(name)
		local state = default == true
		local sig, notify = listener(callback, "Toggle '" .. label .. "'")
		local r, entry = row(22, label)
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

		local nameLabel = text({
			Text = label,
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
				notify(state)
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
			notify(state)
		end

		register(entry, label, function()
			return state
		end, function(d)
			if typeof(d) == "boolean" then
				set(d)
			end
		end, function()
			return state
		end, options.Save)

		local obj = element({
			Set = set,
			Get = function()
				return state
			end,
		}, entry, nameLabel, sig)

		-- Inline add-ons sit on the right side of the toggle row
		local used = 0
		local function reserve(width)
			local offset = 14 + used
			used += width + 6
			nameLabel.Size = UDim2.new(1, -(18 + 14 + used), 1, 0)
			return offset
		end

		method(obj, "AddKeybind", function(keyDefault, cb, pressedCb, opts)
			opts = opts or {}
			local width = 54
			local offset = reserve(width)
			local kb = new("TextButton", {
				Text = "",
				AutoButtonColor = false,
				BackgroundColor3 = Theme.Element,
				BorderSizePixel = 0,
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -offset, 0.5, 0),
				Size = UDim2.fromOffset(width, 18),
				FontFace = Theme.Font,
				TextSize = 12,
				TextColor3 = Theme.Text,
				Parent = r,
			})
			corner(kb, 3)
			kb.MouseEnter:Connect(function()
				tween(kb, 0.12, { BackgroundColor3 = Theme.Header })
			end)
			kb.MouseLeave:Connect(function()
				tween(kb, 0.12, { BackgroundColor3 = Theme.Element })
			end)
			opts.ListName = opts.ListName or label
			local core = bindCore(entry, label .. " Key", keyDefault, cb, pressedCb, opts, kb, nil)
			return addon(core.Api, core.Signal, kb)
		end)

		method(obj, "AddColorPicker", function(colorDefault, cb, opts)
			opts = opts or {}
			local offset = reserve(16)
			local sw = new("TextButton", {
				Text = "",
				AutoButtonColor = false,
				BackgroundColor3 = Color3.new(1, 1, 1),
				BorderSizePixel = 0,
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -offset, 0.5, 0),
				Size = UDim2.fromOffset(16, 16),
				Parent = r,
			})
			corner(sw, 3)
			local core = pickerCore(entry, label .. " Color", colorDefault, cb, opts, sw, opts.Save)
			return addon(core.Api, core.Signal, sw)
		end)

		return obj
	end)

	------------------------------------------------------------------ Slider
	method(Section, "Slider", function(name, min, max, default, callback, increment, options)
		local opts = {}
		if typeof(min) == "table" then
			opts = min
			local cb = max
			min, max, default, increment = opts.Min, opts.Max, opts.Default, opts.Increment
			callback = cb or opts.Callback
		elseif typeof(options) == "table" then
			opts = options
		end
		min = min or 0
		max = max or 100
		increment = increment or 1
		local label = tostring(name)
		local suffix = opts.Suffix or ""
		local showMinMax = opts.ShowMinMax == true
		local decimals = increment < 1 and math.max(0, math.ceil(-math.log10(increment) - 1e-9)) or 0
		local value = math.clamp(default or min, min, max)
		local sig, notify = listener(callback, "Slider '" .. label .. "'")

		local r, entry = row(43 + (showMinMax and 13 or 0), label)
		local nameLabel = text({
			Text = label,
			Size = UDim2.new(1, -74, 0, 18),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Parent = r,
		})
		-- The value is a TextBox so a click lets the user type an exact number
		local valueBox = new("TextBox", {
			Text = "",
			ClearTextOnFocus = false,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -14, 0, 0),
			Size = UDim2.fromOffset(70, 18),
			TextXAlignment = Enum.TextXAlignment.Right,
			FontFace = Theme.Font,
			TextSize = Theme.TextSize,
			TextColor3 = Theme.Text,
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

		if showMinMax then
			text({
				Text = format(min) .. suffix,
				TextColor3 = Theme.SubText,
				TextSize = 11,
				Position = UDim2.fromOffset(0, 37),
				Size = UDim2.fromOffset(60, 12),
				TextXAlignment = Enum.TextXAlignment.Left,
				Parent = r,
			})
			text({
				Text = format(max) .. suffix,
				TextColor3 = Theme.SubText,
				TextSize = 11,
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -14, 0, 37),
				Size = UDim2.fromOffset(60, 12),
				TextXAlignment = Enum.TextXAlignment.Right,
				Parent = r,
			})
		end

		local function display()
			if not valueBox:IsFocused() then
				valueBox.Text = format(value) .. suffix
			end
		end

		local function set(v, silent, instant)
			v = tonumber(v) or min
			v = min + math.floor((v - min) / increment + 0.5) * increment
			v = math.clamp(v, min, max)
			v = tonumber(format(v))
			local changed = v ~= value
			value = v
			local pct = max > min and (v - min) / (max - min) or 0
			display()
			local t = instant and 0 or 0.08
			tween(fill, t, { Size = UDim2.fromScale(pct, 1) })
			tween(knob, t, { Position = UDim2.fromScale(pct, 0.5) })
			if changed and not silent then
				notify(v)
			end
		end

		valueBox.Focused:Connect(function()
			valueBox.Text = format(value)
			valueBox.TextColor3 = Theme.Accent
		end)
		valueBox.FocusLost:Connect(function()
			valueBox.TextColor3 = Theme.Text
			local n = tonumber(string.match(valueBox.Text, "^%s*(-?%d*%.?%d+)"))
			if n then
				set(n)
			end
			display()
		end)

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
		track_ = nil
		table.insert(connections, UserInputService.InputChanged:Connect(function(input)
			if dragging and isMove(input) then
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
		notify(value)

		register(entry, label, function()
			return value
		end, function(d)
			if typeof(d) == "number" then
				set(d)
			end
		end, function()
			return value
		end, opts.Save)

		return element({
			Set = set,
			Get = function()
				return value
			end,
		}, entry, nameLabel, sig)
	end)

	------------------------------------------------------------------ Keybind
	method(Section, "Keybind", function(name, default, callback, pressedCallback, options)
		options = options or {}
		local label = tostring(name)
		local r, entry = row(52, label)
		local nameLabel = text({
			Text = label,
			Size = UDim2.new(1, 0, 0, 18),
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = r,
		})
		local button = new("TextButton", {
			Text = "",
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
		local modeLabel = text({
			Text = "Hold",
			TextColor3 = Theme.SubText,
			TextSize = 11,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 0),
			Size = UDim2.fromOffset(50, 16),
			TextXAlignment = Enum.TextXAlignment.Right,
			Parent = button,
		})
		button.MouseEnter:Connect(function()
			tween(button, 0.12, { BackgroundTransparency = 0.4 })
		end)
		button.MouseLeave:Connect(function()
			tween(button, 0.12, { BackgroundTransparency = 1 })
		end)

		local core = bindCore(entry, label, default, callback, pressedCallback, options, button, modeLabel)
		return element(core.Api, entry, nameLabel, core.Signal)
	end)

	------------------------------------------------------------------ Dropdown
	method(Section, "Dropdown", function(name, list, default, callback, options)
		options = options or {}
		list = list or {}
		local label = tostring(name)
		local multi = options.Multi == true
		local searchable = options.Search == true
		local maxVisible = options.MaxVisible or 6
		local OPTION_HEIGHT, BASE_HEIGHT, SEARCH_HEIGHT = 24, 56, 28
		local open = false
		local sig, notify = listener(callback, "Dropdown '" .. label .. "'")
		local model = selectionModel(list, multi, default)

		local r, entry = row(BASE_HEIGHT, label)
		local nameLabel = text({
			Text = label,
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
			Text = model.Text(),
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

		local searchBox
		local searchH = searchable and SEARCH_HEIGHT or 0
		if searchable then
			local holder = new("Frame", {
				BackgroundColor3 = Theme.Header,
				BorderSizePixel = 0,
				Size = UDim2.new(1, 0, 0, SEARCH_HEIGHT),
				Parent = listFrame,
			})
			searchBox = new("TextBox", {
				Text = "",
				PlaceholderText = "Search...",
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
		end

		local scroll = new("ScrollingFrame", {
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(0, searchH),
			Size = UDim2.new(1, 0, 1, -searchH),
			CanvasSize = UDim2.new(),
			ScrollBarThickness = 2,
			ScrollBarImageColor3 = Theme.HeaderHover,
			ScrollingDirection = Enum.ScrollingDirection.Y,
			Parent = listFrame,
		})
		local ol = createOptionList(scroll, OPTION_HEIGHT, multi)

		local setOpen

		local function refreshDisplay()
			valueLabel.Text = model.Text()
			ol.Paint(model.IsSelected)
		end

		local function pick(opt)
			model.Pick(opt)
			refreshDisplay()
			notify(model.Get())
			if not multi then
				setOpen(false)
			end
		end

		local function build()
			ol.Build(model.List, model.IsSelected, pick)
		end

		local function listHeight()
			return searchH + math.min(ol.Count, maxVisible) * OPTION_HEIGHT
		end

		function setOpen(state)
			open = state
			local height = state and listHeight() or 0
			if state then
				listFrame.Visible = true
			elseif searchBox then
				searchBox.Text = ""
			end
			tween(arrow, 0.15, { Rotation = state and 180 or 0 })
			tween(r, 0.15, { Size = UDim2.new(1, 0, 0, BASE_HEIGHT + (state and height + 2 or 0)) })
			local t = tween(listFrame, 0.15, { Size = UDim2.new(1, -30, 0, height) })
			if not state then
				t.Completed:Once(function()
					if not open then
						listFrame.Visible = false
					end
				end)
			end
		end

		if searchBox then
			searchBox:GetPropertyChangedSignal("Text"):Connect(function()
				ol.Filter = searchBox.Text
				build()
				if open then
					setOpen(true)
				end
			end)
		end

		local function set(opt, silent)
			model.Assign(opt)
			refreshDisplay()
			if not silent then
				notify(model.Get())
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
		if multi or model.Value ~= nil then
			notify(model.Get())
		end

		register(entry, label, function()
			return model.Get()
		end, function(d)
			local clean = model.Sanitize(d)
			if multi then
				if clean then
					set(clean)
				end
			elseif clean ~= nil then
				set(clean)
			end
		end, function()
			return model.Get()
		end, options.Save)

		return element({
			Set = set,
			Get = function()
				return model.Get()
			end,
			Refresh = function(newList, keepValue, doNotify)
				model.List = newList or {}
				local changed = false
				if keepValue then
					changed = model.Prune()
				else
					changed = model.Clear and false or false
					model.Assign(nil)
					changed = true
				end
				build()
				refreshDisplay()
				if open then
					setOpen(true)
				end
				if changed and doNotify then
					notify(model.Get())
				end
			end,
		}, entry, nameLabel, sig)
	end)

	------------------------------------------------------------------ PlayerDropdown
	method(Section, "PlayerDropdown", function(name, default, callback, options)
		options = options or {}
		local function names(leaving)
			local out = {}
			for _, p in Players:GetPlayers() do
				if p ~= leaving and (options.IncludeLocal or p ~= Players.LocalPlayer) then
					table.insert(out, p.Name)
				end
			end
			table.sort(out, function(a, b)
				return string.lower(a) < string.lower(b)
			end)
			return out
		end

		local dd = Section.Dropdown(name, names(), default, callback, {
			Multi = options.Multi,
			Search = options.Search ~= false,
			MaxVisible = options.MaxVisible,
			Save = options.Save == true, -- player names are rarely worth saving
		})

		local added = Players.PlayerAdded:Connect(function()
			dd.Refresh(names(), true, true)
		end)
		local removing = Players.PlayerRemoving:Connect(function(p)
			dd.Refresh(names(p), true, true)
		end)
		table.insert(connections, added)
		table.insert(connections, removing)

		local baseDestroy = dd.Destroy
		method(dd, "Destroy", function()
			added:Disconnect()
			removing:Disconnect()
			baseDestroy()
		end)
		return dd
	end)

	------------------------------------------------------------------ ListBox
	method(Section, "ListBox", function(name, list, default, callback, options)
		options = options or {}
		list = list or {}
		local label = tostring(name)
		local multi = options.Multi == true
		local searchable = options.Search == true
		local height = options.Height or 120
		local ROW = 24
		local sig, notify = listener(callback, "ListBox '" .. label .. "'")
		local model = selectionModel(list, multi, default)
		local searchH = searchable and 30 or 0

		local r, entry = row(20 + searchH + height + 6, label)
		local nameLabel = text({
			Text = label,
			Size = UDim2.new(1, 0, 0, 18),
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = r,
		})

		local searchBox
		if searchable then
			local holder = new("Frame", {
				BackgroundColor3 = Theme.Element,
				BorderSizePixel = 0,
				Position = UDim2.fromOffset(0, 20),
				Size = UDim2.new(1, -14, 0, 26),
				Parent = r,
			})
			corner(holder, 3)
			searchBox = new("TextBox", {
				Text = "",
				PlaceholderText = "Search...",
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
		end

		local panel = new("Frame", {
			BackgroundColor3 = Theme.Element,
			BorderSizePixel = 0,
			ClipsDescendants = true,
			Position = UDim2.fromOffset(0, 20 + searchH),
			Size = UDim2.new(1, -14, 0, height),
			Parent = r,
		})
		corner(panel, 3)
		local scroll = new("ScrollingFrame", {
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Size = UDim2.fromScale(1, 1),
			CanvasSize = UDim2.new(),
			ScrollBarThickness = 2,
			ScrollBarImageColor3 = Theme.HeaderHover,
			ScrollingDirection = Enum.ScrollingDirection.Y,
			Parent = panel,
		})
		local ol = createOptionList(scroll, ROW, multi)

		local function pick(opt)
			model.Pick(opt)
			ol.Paint(model.IsSelected)
			notify(model.Get())
		end
		local function build()
			ol.Build(model.List, model.IsSelected, pick)
		end
		if searchBox then
			searchBox:GetPropertyChangedSignal("Text"):Connect(function()
				ol.Filter = searchBox.Text
				build()
			end)
		end

		local function set(v, silent)
			model.Assign(v)
			ol.Paint(model.IsSelected)
			if not silent then
				notify(model.Get())
			end
		end

		build()
		if multi or model.Value ~= nil then
			notify(model.Get())
		end

		register(entry, label, function()
			return model.Get()
		end, function(d)
			local clean = model.Sanitize(d)
			if multi then
				if clean then
					set(clean)
				end
			elseif clean ~= nil then
				set(clean)
			end
		end, function()
			return model.Get()
		end, options.Save)

		return element({
			Set = set,
			Get = function()
				return model.Get()
			end,
			Refresh = function(newList, keepValue, doNotify)
				model.List = newList or {}
				local changed
				if keepValue then
					changed = model.Prune()
				else
					model.Assign(nil)
					changed = true
				end
				build()
				if changed and doNotify then
					notify(model.Get())
				end
			end,
		}, entry, nameLabel, sig)
	end)

	------------------------------------------------------------------ ColorPicker
	method(Section, "ColorPicker", function(name, default, callback, options)
		options = options or {}
		local label = tostring(name)
		local r, entry = row(24, label)
		local nameLabel = text({
			Text = label,
			Size = UDim2.new(1, -34, 1, 0),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Parent = r,
		})
		local swatch = new("TextButton", {
			Text = "",
			AutoButtonColor = false,
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -14, 0.5, 0),
			Size = UDim2.fromOffset(16, 16),
			Parent = r,
		})
		corner(swatch, 3)
		local core = pickerCore(entry, label, default, callback, options, swatch, options.Save)
		return element(core.Api, entry, nameLabel, core.Signal)
	end)

	------------------------------------------------------------------ Button
	method(Section, "Button", function(name, callback)
		local label = tostring(name)
		local sig, notify = listener(callback, "Button '" .. label .. "'")
		local r, entry = row(30, label)
		local button = new("TextButton", {
			Text = label,
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
			if entry.Disabled then
				return
			end
			button.BackgroundColor3 = Theme.Accent
			tween(button, 0.3, { BackgroundColor3 = Theme.HeaderHover })
			notify()
		end)
		return element({
			SetText = function(t)
				button.Text = tostring(t)
			end,
		}, entry, button, sig)
	end)

	------------------------------------------------------------------ TextBox
	method(Section, "TextBox", function(name, placeholder, callback, options)
		options = options or {}
		local label = tostring(name)
		local sig, notify = listener(callback, "TextBox '" .. label .. "'")
		local r, entry = row(56, label)
		local nameLabel = text({
			Text = label,
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
			notify(box.Text, enter)
		end)
		register(entry, label, function()
			return box.Text
		end, function(d)
			if typeof(d) == "string" then
				box.Text = d
				notify(d, false)
			end
		end, function()
			return box.Text
		end, options.Save)

		return element({
			Set = function(t)
				box.Text = tostring(t)
			end,
			Get = function()
				return box.Text
			end,
		}, entry, nameLabel, sig)
	end)

	------------------------------------------------------------------ Label
	method(Section, "Label", function(content)
		local r, entry = row(20, content)
		r.AutomaticSize = Enum.AutomaticSize.Y
		local lbl = text({
			Text = content or "",
			Size = UDim2.new(1, -14, 0, 20),
			AutomaticSize = Enum.AutomaticSize.Y,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextWrapped = true,
			Parent = r,
		})
		return element({
			Set = function(t)
				lbl.Text = tostring(t)
				entry.Name = tostring(t)
			end,
		}, entry, lbl, nil)
	end)

	------------------------------------------------------------------ Paragraph
	method(Section, "Paragraph", function(a, b)
		local title, body = a, b
		if b == nil then
			title, body = nil, a
		end
		local r, entry = row(0, tostring(title or "") .. " " .. tostring(body or ""))
		r.AutomaticSize = Enum.AutomaticSize.Y
		new("UIPadding", { PaddingTop = UDim.new(0, 3), PaddingBottom = UDim.new(0, 5), Parent = r })
		local lbl = text({
			RichText = true,
			TextColor3 = Theme.SubText,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			Size = UDim2.new(1, -14, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Parent = r,
		})
		local function render(t, bd)
			local out = ""
			if t and t ~= "" then
				out = '<b><font color="#' .. Theme.Text:ToHex() .. '">' .. escapeRich(t) .. "</font></b>\n"
			end
			lbl.Text = out .. escapeRich(bd or "")
			entry.Name = tostring(t or "") .. " " .. tostring(bd or "")
		end
		render(title, body)
		return element({
			Set = function(t, bd)
				if bd == nil then
					render(nil, t)
				else
					render(t, bd)
				end
			end,
		}, entry, nil, nil)
	end)

	------------------------------------------------------------------ Divider / Spacer
	method(Section, "Divider", function(content)
		local r, entry = row(content and 18 or 12, content or "")
		new("Frame", {
			BackgroundColor3 = Theme.Stroke,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromScale(0, 0.5),
			Size = UDim2.new(1, -14, 0, 1),
			Parent = r,
		})
		if content then
			local lbl = text({
				Text = content,
				TextColor3 = Theme.SubText,
				TextSize = 11,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0.5, -7, 0.5, 0),
				Size = UDim2.fromOffset(0, 14),
				AutomaticSize = Enum.AutomaticSize.X,
				Parent = r,
			})
			lbl.BackgroundTransparency = 0
			lbl.BackgroundColor3 = Theme.Panel
			new("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6), Parent = lbl })
		end
		return element({}, entry, nil, nil)
	end)

	method(Section, "Spacer", function(height)
		local _, entry = row(height or 8, "")
		return element({}, entry, nil, nil)
	end)

	------------------------------------------------------------------ ProgressBar
	method(Section, "ProgressBar", function(name, min, max, default, options)
		options = options or {}
		local label = tostring(name)
		min = min or 0
		max = max or 100
		local value = math.clamp(default or min, min, max)
		local r, entry = row(36, label)
		local nameLabel = text({
			Text = label,
			Size = UDim2.new(1, -74, 0, 18),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Parent = r,
		})
		local valueLabel = text({
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -14, 0, 0),
			Size = UDim2.fromOffset(70, 18),
			TextXAlignment = Enum.TextXAlignment.Right,
			Parent = r,
		})
		local track = new("Frame", {
			BackgroundColor3 = Theme.Track,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(0, 24),
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

		local function set(v, instant)
			value = math.clamp(tonumber(v) or min, min, max)
			local pct = max > min and (value - min) / (max - min) or 0
			if typeof(options.Format) == "function" then
				valueLabel.Text = tostring(options.Format(value, pct))
			elseif options.Suffix then
				valueLabel.Text = tostring(math.floor(value * 100 + 0.5) / 100) .. options.Suffix
			else
				valueLabel.Text = math.floor(pct * 100 + 0.5) .. "%"
			end
			tween(fill, instant and 0 or 0.2, { Size = UDim2.fromScale(pct, 1) })
		end
		set(value, true)

		return element({
			Set = set,
			Get = function()
				return value
			end,
		}, entry, nameLabel, nil)
	end)

	------------------------------------------------------------------ Image
	method(Section, "Image", function(image, options)
		options = options or {}
		local height = options.Height or 90
		local r, entry = row(height + 6, options.Name or "Image")
		local holder = new("Frame", {
			BackgroundColor3 = Theme.Element,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(0, 3),
			Size = UDim2.new(1, -14, 0, height),
			Parent = r,
		})
		corner(holder, 3)
		local img = new("ImageLabel", {
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			Image = asset(image),
			ImageColor3 = options.Color or Color3.new(1, 1, 1),
			ScaleType = options.ScaleType or Enum.ScaleType.Fit,
			Parent = holder,
		})
		return element({
			Set = function(id)
				img.Image = asset(id)
			end,
		}, entry, nil, nil)
	end)

	------------------------------------------------------------------ ConfigManager
	method(Section, "ConfigManager", function()
		noRegister = true -- the manager's own widgets must not end up inside configs

		local fs = fsAvailable()
		local selected = nil
		local nameBox, dropdown, autoLabel, status, importBox, deleteBtn

		local function say(msg)
			if status then
				status.Set(msg)
			end
		end

		local function describe(rep)
			if not rep then
				return ""
			end
			local u, m = #rep.Unknown, #rep.Missing
			if Library.Debug and (u > 0 or m > 0) then
				warn("[UILibrary] unknown keys: " .. table.concat(rep.Unknown, ", "))
				warn("[UILibrary] missing keys: " .. table.concat(rep.Missing, ", "))
			end
			if u == 0 and m == 0 then
				return ""
			end
			return string.format(" (%d unknown, %d missing)", u, m)
		end

		local function updateAutoLabel()
			if autoLabel then
				autoLabel.Set("Autoload: " .. (window.GetAutoload() or "none"))
			end
		end

		local function refresh(select)
			if not dropdown then
				return
			end
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

		if fs then
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
			end, { Search = true, MaxVisible = 5 })

			Section.Button("Load selected", function()
				if needSelected() then
					local ok, msg, rep = window.LoadConfig(selected)
					say(ok and ("Loaded" .. describe(rep)) or msg)
				end
			end)

			Section.Button("Overwrite selected", function()
				if needSelected() then
					local ok, msg = window.SaveConfig(selected)
					say(ok and "Overwritten" or msg)
				end
			end)

			-- Two-step delete: first press arms the button, second press within 3s deletes
			local pendingName, pendingTime = nil, 0
			deleteBtn = Section.Button("Delete selected", function()
				if not needSelected() then
					return
				end
				if pendingName == selected and os.clock() - pendingTime < 3 then
					pendingName = nil
					deleteBtn.SetText("Delete selected")
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
				else
					pendingName, pendingTime = selected, os.clock()
					deleteBtn.SetText("Click again to confirm")
					say("Press again within 3s to delete")
					local mine = pendingTime
					task.delay(3, function()
						if pendingTime == mine and pendingName then
							pendingName = nil
							deleteBtn.SetText("Delete selected")
						end
					end)
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
		else
			Section.Label("File saving isn't supported in this environment, but export / import still works.")
		end

		Section.Divider("Share")

		Section.Button("Export to clipboard", function()
			local json = window.ExportConfig()
			if typeof(setclipboard) == "function" then
				setclipboard(json)
				say("Copied to clipboard")
			else
				importBox.Set(json)
				say("No clipboard access - copy it from the box")
			end
		end)

		importBox = Section.TextBox("Import config :", "paste config JSON", nil)

		Section.Button("Import from box", function()
			local raw = importBox.Get()
			if raw == "" and typeof(getclipboard) == "function" then
				local ok, clip = pcall(getclipboard)
				if ok and typeof(clip) == "string" then
					raw = clip
				end
			end
			if raw == "" then
				say("Paste a config first")
				return
			end
			local ok, msg, rep = window.ImportConfig(raw)
			say(ok and ("Imported" .. describe(rep)) or msg)
		end)

		status = Section.Label("Ready")
		updateAutoLabel()
		noRegister = false

		-- Apply the autoload config once the script has finished building the UI
		if fs then
			task.defer(function()
				local ok, name, rep = window.LoadAutoload()
				if ok then
					refresh(name)
					say("Autoload applied" .. describe(rep))
				end
			end)
		end

		return element({
			Refresh = refresh,
		}, { Row = frame, Conns = {}, FlagKeys = {}, Cleanup = {}, Apply = function() end }, nil, nil)
	end)

	------------------------------------------------------------------ WindowSettings
	method(Section, "WindowSettings", function(options)
		options = options or {}
		Section.Slider("UI Scale", 50, 150, math.floor(window._scale * 100 + 0.5), function(v)
			window.SetScale(v / 100)
		end, 5, { Suffix = "%" })
		Section.Keybind("Menu Key :", window.GetToggleKey(), function(k)
			window.SetToggleKey(k)
		end, nil, { Save = false, ShowInList = false })
		Section.Toggle("Watermark", window.IsWatermarkVisible(), function(on)
			window.SetWatermarkVisible(on)
		end)
		Section.Toggle("Keybind List", window.IsKeybindListVisible(), function(on)
			window.SetKeybindListVisible(on)
		end)
		Section.Toggle("Mobile Button", window.IsMobileButtonVisible(), function(on)
			window.SetMobileButton(on)
		end)
		return Section
	end)

	if sectionOptions.Collapsed then
		setCollapsed(true)
	end

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

	local parent = options.Parent or getGuiParent()
	assert(parent, "[UILibrary] Couldn't find a place to parent the UI (pass options.Parent)")

	local Window = {
		_connections = {},
		_cleanups = {},
		_closePopup = nil,
		_flags = {},
		_flagCounts = {},
		_palette = {},
		_paletteViews = {},
		_keybinds = {},
		_kbDirty = true,
		_binding = false,
		_popupScales = {},
	}
	local connections = Window._connections
	local tabs = {}
	local toggleKey = options.ToggleKey or Enum.KeyCode.RightShift
	local animate = options.Animate ~= false

	table.insert(Library.Windows, Window)

	Window.Flags = setmetatable({}, {
		__index = function(_, key)
			local flag = Window._flags[key]
			if flag then
				local ok, value = pcall(flag.raw)
				if ok then
					return value
				end
			end
			return nil
		end,
	})

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

	-- Holder carries position / size / user scale; Main carries the open-close animation
	local startSize = typeof(options.Size) == "Vector2" and options.Size or WINDOW_SIZE
	local holder = new("Frame", {
		Name = "Window",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(startSize.X, startSize.Y),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	local userScale = new("UIScale", { Scale = math.clamp(options.Scale or 1, 0.5, 2), Parent = holder })
	Window._scale = userScale.Scale

	local main = new("CanvasGroup", {
		Name = "Main",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Background,
		BackgroundTransparency = Theme.BackgroundTransparency,
		BorderSizePixel = 0,
		Active = true,
		Parent = holder,
	})
	local animScale = new("UIScale", { Scale = 1, Parent = main })
	corner(main, 4)
	new("UIStroke", { Color = Theme.Stroke, Transparency = 0.3, Thickness = 1, Parent = main })

	-- Popups on the ScreenGui follow the window scale
	function Window._trackScale(popup)
		local s = new("UIScale", { Scale = Window._scale, Parent = popup })
		table.insert(Window._popupScales, s)
		return s
	end

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

	-- Search bar (a sibling of the drag strip so clicking it never starts a drag)
	local searchHolder = new("Frame", {
		Name = "Search",
		BackgroundColor3 = Theme.Element,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -CONTENT_RIGHT, 0, 16),
		Size = UDim2.fromOffset(150, 26),
		Visible = options.Search ~= false,
		ZIndex = 2,
		Parent = main,
	})
	corner(searchHolder, 3)
	local searchBox = new("TextBox", {
		Text = "",
		PlaceholderText = "Search...",
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
		ZIndex = 3,
		Parent = searchHolder,
	})

	local function applySearch()
		local q = searchBox.Text
		for _, t in tabs do
			for _, sub in t.Subs do
				for _, col in { sub.Left, sub.Right } do
					for _, s in col.Sections do
						s.Filter(q)
					end
				end
			end
		end
	end
	searchBox:GetPropertyChangedSignal("Text"):Connect(applySearch)

	-- Generic dragging (window, watermark, keybind list, mobile button)
	local function makeDraggable(handle, target, opts)
		opts = opts or {}
		local dragging, moved, startMouse, startPos = false, 0, nil, nil
		handle.InputBegan:Connect(function(input)
			if isClick(input) then
				dragging = true
				moved = 0
				startMouse = input.Position
				startPos = target.Position
				if opts.OnBegin then
					opts.OnBegin()
				end
			end
		end)
		table.insert(connections, UserInputService.InputChanged:Connect(function(input)
			if dragging and isMove(input) then
				local delta = input.Position - startMouse
				moved = math.max(moved, math.sqrt(delta.X * delta.X + delta.Y * delta.Y))
				target.Position = UDim2.new(
					startPos.X.Scale, startPos.X.Offset + delta.X,
					startPos.Y.Scale, startPos.Y.Offset + delta.Y
				)
			end
		end))
		table.insert(connections, UserInputService.InputEnded:Connect(function(input)
			if dragging and isClick(input) then
				dragging = false
				if opts.OnClick and moved < 6 then
					opts.OnClick()
				end
			end
		end))
	end

	makeDraggable(sidebar, holder, { OnBegin = closePopup })
	makeDraggable(topStrip, holder, { OnBegin = closePopup })

	-- Resize grip
	local grip = new("TextButton", {
		Name = "ResizeGrip",
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.fromScale(1, 1),
		Size = UDim2.fromOffset(16, 16),
		ZIndex = 10,
		Visible = options.Resizable ~= false,
		Parent = main,
	})
	new("Frame", {
		BackgroundColor3 = Theme.SubText,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(9, 9),
		Size = UDim2.fromOffset(12, 1),
		Rotation = -45,
		ZIndex = 11,
		Parent = grip,
	})
	new("Frame", {
		BackgroundColor3 = Theme.SubText,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(12, 12),
		Size = UDim2.fromOffset(6, 1),
		Rotation = -45,
		ZIndex = 11,
		Parent = grip,
	})

	local resizing, resizeStartMouse, resizeStartSize = false, nil, nil
	grip.InputBegan:Connect(function(input)
		if isClick(input) then
			closePopup()
			resizing = true
			resizeStartMouse = Vector2.new(input.Position.X, input.Position.Y)
			resizeStartSize = Vector2.new(holder.Size.X.Offset, holder.Size.Y.Offset)
		end
	end)
	table.insert(connections, UserInputService.InputChanged:Connect(function(input)
		if resizing and isMove(input) then
			local scale = userScale.Scale
			local d = (Vector2.new(input.Position.X, input.Position.Y) - resizeStartMouse) / scale
			local screen = gui.AbsoluteSize / scale
			local newW = math.clamp(resizeStartSize.X + d.X, MIN_WINDOW.X, math.max(MIN_WINDOW.X, screen.X - 20))
			local newH = math.clamp(resizeStartSize.Y + d.Y, MIN_WINDOW.Y, math.max(MIN_WINDOW.Y, screen.Y - 20))
			local dw, dh = newW - holder.Size.X.Offset, newH - holder.Size.Y.Offset
			holder.Size = UDim2.fromOffset(newW, newH)
			-- keep the top-left corner fixed while the (centre-anchored) window grows
			holder.Position = holder.Position + UDim2.fromOffset(dw * scale / 2, dh * scale / 2)
		end
	end))
	table.insert(connections, UserInputService.InputEnded:Connect(function(input)
		if resizing and isClick(input) then
			resizing = false
		end
	end))

	------------------------------------------------------------------ Tooltips
	local tip = new("Frame", {
		Name = "Tooltip",
		BackgroundColor3 = Theme.Header,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		Visible = false,
		ZIndex = 300,
		Parent = gui,
	})
	corner(tip, 3)
	new("UIStroke", { Color = Theme.Stroke, Thickness = 1, Parent = tip })
	new("UIPadding", {
		PaddingLeft = UDim.new(0, 8),
		PaddingRight = UDim.new(0, 8),
		PaddingTop = UDim.new(0, 5),
		PaddingBottom = UDim.new(0, 5),
		Parent = tip,
	})
	local tipLabel = text({
		Text = "",
		TextSize = 12,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		ZIndex = 301,
		Parent = tip,
	})
	new("UISizeConstraint", { MaxSize = Vector2.new(240, math.huge), Parent = tipLabel })

	local tipToken, tipConn = 0, nil
	local function tipReposition()
		local m = UserInputService:GetMouseLocation()
		local gs = gui.AbsoluteSize
		local sz = tip.AbsoluteSize
		local x = math.clamp(m.X + 14, 4, math.max(gs.X - sz.X - 4, 4))
		local y = m.Y + 18
		if y + sz.Y > gs.Y - 4 then
			y = m.Y - sz.Y - 10
		end
		tip.Position = UDim2.fromOffset(x, math.max(y, 4))
	end
	function Window._tooltipHide()
		tipToken += 1
		tip.Visible = false
		if tipConn then
			tipConn:Disconnect()
			tipConn = nil
		end
	end
	function Window._tooltipShow(t)
		tipToken += 1
		local token = tipToken
		task.delay(0.35, function()
			if token ~= tipToken then
				return
			end
			tipLabel.Text = tostring(t)
			tip.Visible = true
			tipReposition()
			if tipConn then
				tipConn:Disconnect()
			end
			tipConn = RunService.RenderStepped:Connect(tipReposition)
		end)
	end
	table.insert(Window._cleanups, Window._tooltipHide)

	------------------------------------------------------------------ Keybind mode menu
	local MENU_ITEM = 24
	local modeMenu = new("Frame", {
		Name = "ModeMenu",
		BackgroundColor3 = Theme.Panel,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(84, #MODES * MENU_ITEM + 8),
		Visible = false,
		Active = true,
		ZIndex = 150,
		Parent = gui,
	})
	corner(modeMenu, 4)
	new("UIStroke", { Color = Theme.Stroke, Thickness = 1, Parent = modeMenu })
	new("UIPadding", {
		PaddingLeft = UDim.new(0, 4),
		PaddingRight = UDim.new(0, 4),
		PaddingTop = UDim.new(0, 4),
		PaddingBottom = UDim.new(0, 4),
		Parent = modeMenu,
	})
	new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Parent = modeMenu })
	Window._trackScale(modeMenu)

	local modeButtons, modeCallback = {}, nil
	local function closeModeMenu()
		modeMenu.Visible = false
		if Window._closePopup == closeModeMenu then
			Window._closePopup = nil
		end
	end
	for i, m in MODES do
		local b = new("TextButton", {
			Text = m,
			AutoButtonColor = false,
			BackgroundColor3 = Theme.HeaderHover,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, MENU_ITEM),
			LayoutOrder = i,
			FontFace = Theme.Font,
			TextSize = Theme.TextSize,
			TextColor3 = Theme.Text,
			ZIndex = 151,
			Parent = modeMenu,
		})
		corner(b, 3)
		b.MouseEnter:Connect(function()
			tween(b, 0.1, { BackgroundTransparency = 0.3 })
		end)
		b.MouseLeave:Connect(function()
			tween(b, 0.1, { BackgroundTransparency = 1 })
		end)
		b.Activated:Connect(function()
			local cb = modeCallback
			closeModeMenu()
			if cb then
				cb(m)
			end
		end)
		modeButtons[m] = b
	end
	function Window._openModeMenu(anchor, current, onPick)
		closePopup()
		modeCallback = onPick
		for m, b in modeButtons do
			b.TextColor3 = m == current and Theme.Accent or Theme.Text
		end
		local ap, as = anchor.AbsolutePosition, anchor.AbsoluteSize
		local sc = Window._scale
		local w, h = 84 * sc, (#MODES * MENU_ITEM + 8) * sc
		local gs = gui.AbsoluteSize
		local x = math.clamp(ap.X + as.X - w, 4, math.max(gs.X - w - 4, 4))
		local y = ap.Y + as.Y + 4
		if y + h > gs.Y - 4 then
			y = ap.Y - h - 4
		end
		modeMenu.Position = UDim2.fromOffset(x, y)
		modeMenu.Visible = true
		Window._closePopup = closeModeMenu
	end
	table.insert(connections, UserInputService.InputBegan:Connect(function(input)
		if modeMenu.Visible and isClick(input) and not isInside(modeMenu, screenPos(input)) then
			closeModeMenu()
		end
	end))

	------------------------------------------------------------------ Shared color palette
	local function refreshPaletteViews()
		for _, view in Window._paletteViews do
			pcall(view)
		end
	end
	function Window._addPalette(color)
		for _, c in Window._palette do
			if c == color then
				return
			end
		end
		if #Window._palette >= MAX_PALETTE then
			table.remove(Window._palette, 1)
		end
		table.insert(Window._palette, color)
		refreshPaletteViews()
	end
	function Window._removePalette(index)
		table.remove(Window._palette, index)
		refreshPaletteViews()
	end
	Window._flags["__palette"] = {
		save = true,
		internal = true,
		get = function()
			local out = {}
			for _, c in Window._palette do
				table.insert(out, {
					math.floor(c.R * 255 + 0.5),
					math.floor(c.G * 255 + 0.5),
					math.floor(c.B * 255 + 0.5),
				})
			end
			return out
		end,
		set = function(d)
			if typeof(d) ~= "table" then
				return
			end
			table.clear(Window._palette)
			for _, c in d do
				if typeof(c) == "table" and typeof(c[1]) == "number" and typeof(c[2]) == "number" and typeof(c[3]) == "number" then
					if #Window._palette < MAX_PALETTE then
						table.insert(Window._palette, Color3.fromRGB(c[1], c[2], c[3]))
					end
				end
			end
			refreshPaletteViews()
		end,
		raw = function()
			return Window._palette
		end,
	}

	------------------------------------------------------------------ Show / hide
	local visible = options.Visible ~= false
	if not visible then
		holder.Visible = false
	end

	local function setVisible(state)
		state = state == true
		if state == visible then
			return
		end
		visible = state
		closePopup()
		Window._tooltipHide()
		if state then
			holder.Visible = true
			if animate then
				main.GroupTransparency = 1
				animScale.Scale = 0.94
				tween(main, 0.18, { GroupTransparency = 0 })
				tween(animScale, 0.18, { Scale = 1 })
			else
				main.GroupTransparency = 0
				animScale.Scale = 1
			end
		elseif animate then
			tween(main, 0.15, { GroupTransparency = 1 })
			local t = tween(animScale, 0.15, { Scale = 0.94 })
			t.Completed:Once(function()
				if not visible then
					holder.Visible = false
				end
			end)
		else
			holder.Visible = false
		end
	end

	table.insert(connections, UserInputService.InputBegan:Connect(function(input, processed)
		if processed or Window._binding or not toggleKey then
			return
		end
		local hit
		if toggleKey.EnumType == Enum.KeyCode then
			hit = input.KeyCode == toggleKey
		else
			hit = input.UserInputType == toggleKey
		end
		if hit then
			setVisible(not visible)
		end
	end))

	------------------------------------------------------------------ Tabs
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

	local function collectFlags()
		local data = {}
		for key, flag in Window._flags do
			if flag.save then
				local ok, value = pcall(flag.get)
				if ok and value ~= nil then
					data[key] = value
				end
			end
		end
		return data
	end

	local function applyFlags(data)
		local report = { Unknown = {}, Missing = {} }
		for key, value in data do
			local flag = Window._flags[key]
			if flag then
				if flag.save then
					pcall(flag.set, value)
				end
			else
				table.insert(report.Unknown, key)
			end
		end
		for key, flag in Window._flags do
			if flag.save and not flag.internal and data[key] == nil then
				table.insert(report.Missing, key)
			end
		end
		table.sort(report.Unknown)
		table.sort(report.Missing)
		return report
	end

	local function encodeConfig(flags)
		return HttpService:JSONEncode({ Version = Library.ConfigVersion, Library = Library.Version, Flags = flags })
	end

	-- Accepts v2 files ({ Version, Flags }) and the older flat format
	local function decodeConfig(raw)
		local ok, parsed = pcall(function()
			return HttpService:JSONDecode(raw)
		end)
		if not ok or typeof(parsed) ~= "table" then
			return nil
		end
		if parsed.Version ~= nil and typeof(parsed.Flags) == "table" then
			return parsed.Flags
		end
		return parsed
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
		local ok = pcall(function()
			ensureFolders()
			writefile(configPath(name), encodeConfig(collectFlags()))
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
		local okRead, raw = pcall(readfile, configPath(name))
		if not okRead then
			return false, "Couldn't read config"
		end
		local flags = decodeConfig(raw)
		if not flags then
			return false, "Couldn't read config"
		end
		return true, name, applyFlags(flags)
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

	method(Window, "ExportConfig", function()
		return encodeConfig(collectFlags())
	end)

	method(Window, "ImportConfig", function(raw)
		if typeof(raw) ~= "string" or raw == "" then
			return false, "Nothing to import"
		end
		local flags = decodeConfig(raw)
		if not flags then
			return false, "Invalid config"
		end
		return true, "imported", applyFlags(flags)
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

	method(Window, "GetFlags", function()
		local out = {}
		for key, flag in Window._flags do
			if not flag.internal then
				local ok, value = pcall(flag.raw)
				if ok then
					out[key] = value
				end
			end
		end
		return out
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
		local subBar = new("Frame", {
			Name = "SubTabs",
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 26),
			Visible = false,
			Parent = page,
		})
		new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 4),
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = subBar,
		})

		local tabData = {
			Page = page,
			Icon = iconObj,
			ColorProperty = colorProperty,
			Subs = {},
			ExplicitSubs = false,
			ActiveSub = nil,
		}
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

		-- Sub-tabs
		local function layoutSubs()
			local explicit = tabData.ExplicitSubs
			subBar.Visible = explicit
			for _, sub in tabData.Subs do
				sub.Frame.Position = UDim2.fromOffset(0, explicit and 32 or 0)
				sub.Frame.Size = UDim2.new(1, 0, 1, explicit and -32 or 0)
			end
		end

		local function selectSub(sub)
			closePopup()
			tabData.ActiveSub = sub
			for _, s in tabData.Subs do
				local active = s == sub
				s.Frame.Visible = active
				if s.Button then
					tween(s.Button, 0.12, {
						BackgroundTransparency = active and 0 or 1,
						TextColor3 = active and Theme.Text or Theme.SubText,
					})
				end
			end
		end

		local function ensureButton(sub)
			if sub.Button then
				return
			end
			local b = new("TextButton", {
				Text = sub.Name,
				AutoButtonColor = false,
				BackgroundColor3 = Theme.Header,
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.fromOffset(0, 24),
				LayoutOrder = sub.Index,
				FontFace = Theme.Font,
				TextSize = Theme.TextSize,
				TextColor3 = Theme.SubText,
				Parent = subBar,
			})
			corner(b, 3)
			new("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), Parent = b })
			b.Activated:Connect(function()
				selectSub(sub)
			end)
			sub.Button = b
		end

		local function newSub(subName)
			local frame = new("Frame", {
				Name = subName,
				BackgroundTransparency = 1,
				Visible = false,
				Parent = page,
			})
			local sub = {
				Name = subName,
				Index = #tabData.Subs + 1,
				Frame = frame,
				Left = createColumn(frame, "Left"),
				Right = createColumn(frame, "Right"),
				Count = 0,
			}
			table.insert(tabData.Subs, sub)
			if tabData.ExplicitSubs then
				ensureButton(sub)
			end
			layoutSubs()
			if not tabData.ActiveSub then
				selectSub(sub)
			end
			return sub
		end

		-- Section factory shared by the Tab and each SubTab
		local function sectionApi(getSub)
			local api = {}
			method(api, "Section", function(sectionName, side, sectionOptions)
				if typeof(side) == "table" then
					sectionOptions, side = side, nil
				end
				local sub = getSub()
				sub.Count += 1
				if side ~= "Left" and side ~= "Right" then
					side = (sub.Count % 2 == 1) and "Left" or "Right"
				end
				return createSection(
					Window,
					side == "Right" and sub.Right or sub.Left,
					sectionName or "Section",
					name,
					sectionOptions
				)
			end)
			return api
		end

		local Tab = sectionApi(function()
			if #tabData.Subs == 0 then
				return newSub("Main")
			end
			return tabData.Subs[1]
		end)
		Tab.Page = page

		method(Tab, "SubTab", function(subName)
			if not tabData.ExplicitSubs then
				tabData.ExplicitSubs = true
				for _, existing in tabData.Subs do
					ensureButton(existing)
				end
				layoutSubs()
			end
			local sub = newSub(tostring(subName or ("Sub" .. (#tabData.Subs + 1))))
			local SubTab = sectionApi(function()
				return sub
			end)
			method(SubTab, "Select", function()
				selectSub(sub)
			end)
			SubTab.Name = sub.Name
			return SubTab
		end)
		method(Tab, "Select", function()
			selectTab(tabData)
		end)
		return Tab
	end)

	------------------------------------------------------------------ Watermark / keybind list / mobile button
	local watermark = new("Frame", {
		Name = "Watermark",
		BackgroundColor3 = Theme.Background,
		BackgroundTransparency = Theme.BackgroundTransparency,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(10, 10),
		Size = UDim2.fromOffset(0, 24),
		AutomaticSize = Enum.AutomaticSize.X,
		Active = true,
		Visible = false,
		Parent = gui,
	})
	corner(watermark, 4)
	new("UIStroke", { Color = Theme.Stroke, Transparency = 0.3, Thickness = 1, Parent = watermark })
	new("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), Parent = watermark })
	local watermarkLabel = text({
		Text = title or "UILibrary",
		Size = UDim2.new(0, 0, 1, 0),
		AutomaticSize = Enum.AutomaticSize.X,
		Parent = watermark,
	})
	makeDraggable(watermark, watermark)

	local wmOptions = { Text = title or "UILibrary", ShowFPS = true, ShowPing = true, ShowTime = false }
	local lastFps = 60
	local function updateWatermark()
		local parts = { wmOptions.Text }
		if wmOptions.ShowFPS then
			table.insert(parts, lastFps .. " fps")
		end
		if wmOptions.ShowPing then
			table.insert(parts, getPing() .. " ms")
		end
		if wmOptions.ShowTime then
			table.insert(parts, os.date("%H:%M"))
		end
		watermarkLabel.Text = table.concat(parts, "  |  ")
	end

	local kbFrame = new("Frame", {
		Name = "KeybindList",
		BackgroundColor3 = Theme.Background,
		BackgroundTransparency = Theme.BackgroundTransparency,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(10, 44),
		Size = UDim2.fromOffset(170, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Active = true,
		Visible = false,
		Parent = gui,
	})
	corner(kbFrame, 4)
	new("UIStroke", { Color = Theme.Stroke, Transparency = 0.3, Thickness = 1, Parent = kbFrame })
	new("UIPadding", {
		PaddingLeft = UDim.new(0, 10),
		PaddingRight = UDim.new(0, 10),
		PaddingTop = UDim.new(0, 6),
		PaddingBottom = UDim.new(0, 6),
		Parent = kbFrame,
	})
	new("UIListLayout", { Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder, Parent = kbFrame })
	local kbHeader = text({
		Text = "Keybinds",
		TextColor3 = Theme.SubText,
		Size = UDim2.new(1, 0, 0, 16),
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = 0,
		Parent = kbFrame,
	})
	makeDraggable(kbFrame, kbFrame)

	local function rebuildKeybindList()
		for _, child in kbFrame:GetChildren() do
			if child:IsA("TextLabel") and child ~= kbHeader then
				child:Destroy()
			end
		end
		local i = 0
		for _, kb in Window._keybinds do
			local key = kb.GetKey()
			if kb.Show and key ~= nil and kb.GetState() then
				i += 1
				text({
					Text = string.format("%s  [%s]  %s", kb.Name, Library.FormatKey(key), kb.GetMode()),
					Size = UDim2.new(1, 0, 0, 16),
					TextXAlignment = Enum.TextXAlignment.Left,
					TextTruncate = Enum.TextTruncate.AtEnd,
					LayoutOrder = i,
					Parent = kbFrame,
				})
			end
		end
	end

	do
		local frames, acc = 0, 0
		table.insert(connections, RunService.Heartbeat:Connect(function(dt)
			frames += 1
			acc += dt
			if acc >= 0.5 then
				lastFps = math.floor(frames / acc + 0.5)
				frames, acc = 0, 0
				if watermark.Visible then
					updateWatermark()
				end
			end
			if Window._kbDirty and kbFrame.Visible then
				Window._kbDirty = false
				rebuildKeybindList()
			end
		end))
	end

	local mobileBtn = new("TextButton", {
		Name = "MobileToggle",
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Theme.Sidebar,
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 12, 0.3, 0),
		Size = UDim2.fromOffset(42, 42),
		Active = true,
		Visible = false,
		Parent = gui,
	})
	corner(mobileBtn, 21)
	new("UIStroke", { Color = Theme.Stroke, Thickness = 1, Parent = mobileBtn })
	if isAsset(options.Logo) then
		new("ImageLabel", {
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(24, 24),
			Image = asset(options.Logo),
			ScaleType = Enum.ScaleType.Fit,
			Parent = mobileBtn,
		})
	else
		text({
			Text = "UI",
			FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold),
			Size = UDim2.fromScale(1, 1),
			Parent = mobileBtn,
		})
	end
	makeDraggable(mobileBtn, mobileBtn, {
		OnClick = function()
			setVisible(not visible)
		end,
	})
	if options.MobileButton == nil then
		mobileBtn.Visible = UserInputService.TouchEnabled
	else
		mobileBtn.Visible = options.MobileButton == true
	end

	------------------------------------------------------------------ Window methods
	method(Window, "SetLogo", function(id)
		logo.Image = asset(id)
	end)
	method(Window, "SetVisible", function(state)
		setVisible(state)
	end)
	method(Window, "IsVisible", function()
		return visible
	end)
	method(Window, "Toggle", function()
		setVisible(not visible)
	end)
	method(Window, "SetToggleKey", function(key)
		toggleKey = key
	end)
	method(Window, "GetToggleKey", function()
		return toggleKey
	end)
	method(Window, "SetScale", function(scale)
		scale = math.clamp(tonumber(scale) or 1, 0.5, 2)
		userScale.Scale = scale
		Window._scale = scale
		for _, s in Window._popupScales do
			if s.Parent then
				s.Scale = scale
			end
		end
		closePopup()
	end)
	method(Window, "GetScale", function()
		return userScale.Scale
	end)
	method(Window, "SetSize", function(size)
		if typeof(size) == "Vector2" then
			holder.Size = UDim2.fromOffset(math.max(size.X, MIN_WINDOW.X), math.max(size.Y, MIN_WINDOW.Y))
		end
	end)
	method(Window, "GetSize", function()
		return Vector2.new(holder.Size.X.Offset, holder.Size.Y.Offset)
	end)
	method(Window, "SetMobileButton", function(state)
		mobileBtn.Visible = state == true
	end)
	method(Window, "IsMobileButtonVisible", function()
		return mobileBtn.Visible
	end)
	method(Window, "Watermark", function(opts)
		if typeof(opts) == "table" then
			for k, v in opts do
				wmOptions[k] = v
			end
		elseif typeof(opts) == "string" then
			wmOptions.Text = opts
		end
		updateWatermark()
		watermark.Visible = true
	end)
	method(Window, "SetWatermarkVisible", function(state)
		watermark.Visible = state == true
		if watermark.Visible then
			updateWatermark()
		end
	end)
	method(Window, "IsWatermarkVisible", function()
		return watermark.Visible
	end)
	method(Window, "KeybindList", function()
		Window._kbDirty = true
		kbFrame.Visible = true
	end)
	method(Window, "SetKeybindListVisible", function(state)
		kbFrame.Visible = state == true
		Window._kbDirty = true
	end)
	method(Window, "IsKeybindListVisible", function()
		return kbFrame.Visible
	end)
	method(Window, "Notify", function(...)
		return Library.Notify(...)
	end)
	method(Window, "Destroy", function()
		closePopup()
		for _, fn in Window._cleanups do
			pcall(fn)
		end
		for _, c in connections do
			c:Disconnect()
		end
		table.clear(connections)
		local i = table.find(Library.Windows, Window)
		if i then
			table.remove(Library.Windows, i)
		end
		gui:Destroy()
	end)

	Window.Gui = gui
	Window.Holder = holder
	Window.Main = main
	return Window
end

return Library
