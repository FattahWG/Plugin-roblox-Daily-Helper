-- The dock window in Neo-Brutalism: a start screen with a liquid blob, an Information screen, and the
-- main screen with the tabs Scan, Findings and Log. The layout follows the FigCraft mockup v2.

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent.Theme)
local Log = require(script.Parent.Log)

local Font = Theme.Font
local BORDER, SHADOW, RADIUS = Theme.BORDER, Theme.SHADOW, Theme.RADIUS

local View = {}
View.__index = View

local PAGE_SIZE = 40
local TABS = { "Scan", "Findings", "Log" }
local FOOTER = "Lawak Studio © 2026"
local HEADER_HEIGHT = 116
local FOOTER_HEIGHT = 28

-- The liquid blob: { x, y, diameter } around the center, the same circles as the mockup.
local BLOB = { { -38, -18, 120 }, { 40, 6, 108 }, { -6, 44, 96 }, { 30, -50, 70 }, { -62, 40, 56 } }

-- Text size choices. Plugin windows get no Windows display scale, so on a 150% screen the
-- developer picks 150% and the panel matches the size of Studio's own text.
local SCALES = { 1, 1.25, 1.5, 1.75 }

local CHECK_COLORS = { ui = "yellow", tree = "Info", scripts = "Warning", security = "Error", performance = "ok", api = "ink" }

-- ===== small builders =====

local function make(className: string, props: { [string]: any }?, children: { Instance }?): any
	local item = Instance.new(className)
	for key, value in props or {} do
		if key ~= "Parent" then
			item[key] = value
		end
	end
	for _, child in children or {} do
		child.Parent = item
	end
	if props and props.Parent then
		item.Parent = props.Parent
	end
	return item
end

local function corner(radius: number)
	return make("UICorner", { CornerRadius = UDim.new(0, radius) })
end

local function round()
	return make("UICorner", { CornerRadius = UDim.new(1, 0) })
end

local function border(color: Color3, thickness: number?)
	return make("UIStroke", { Color = color, Thickness = thickness or BORDER, ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
end

local function padding(top: number, right: number?, bottom: number?, left: number?)
	return make("UIPadding", {
		PaddingTop = UDim.new(0, top),
		PaddingRight = UDim.new(0, right or top),
		PaddingBottom = UDim.new(0, bottom or top),
		PaddingLeft = UDim.new(0, left or right or top),
	})
end

local function list(direction: Enum.FillDirection, gap: number, align: Enum.HorizontalAlignment?)
	return make("UIListLayout", {
		FillDirection = direction,
		Padding = UDim.new(0, gap),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = align or Enum.HorizontalAlignment.Left,
		-- A row centers its items. A column starts at the top, also when it is short.
		VerticalAlignment = if direction == Enum.FillDirection.Horizontal then Enum.VerticalAlignment.Center
			else Enum.VerticalAlignment.Top,
	})
end

local function scroller(name: string, gap: number, sidePadding: number)
	return make("ScrollingFrame", {
		Name = name, BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1),
		CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 6, ScrollBarImageColor3 = Color3.fromHex("111111"),
		VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar, Visible = false,
	}, { padding(14, sidePadding, 18, sidePadding), list(Enum.FillDirection.Vertical, gap) })
end

-- Small text reads poorly in a narrow dock, so each small size goes up one step and 12 px is the floor.
local SIZE_UP = { [10] = 12, [11] = 12, [12] = 13, [13] = 14 }

function View:label(text: string, size: number, color: Color3, font: Font?, props: { [string]: any }?)
	local item = make("TextLabel", {
		BackgroundTransparency = 1, Text = text, TextSize = SIZE_UP[size] or size, TextColor3 = color, FontFace = font or Font.Regular,
		TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
		Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextWrapped = true, RichText = false,
		-- A little more space between wrapped lines keeps a paragraph easy to follow.
		LineHeight = 1.15,
	})
	for key, value in props or {} do
		item[key] = value
	end
	return item
end

-- A Neo-Brutalism box: a hard black shadow and a face with a thick black border.
-- opts: height (fixed) or none (the face grows with its content), shadow, radius, face ("Frame" or
-- "TextButton"), LayoutOrder, Parent, width (UDim, default full width).
function View:box(fill: Color3, opts)
	local C = self.C
	local shadow = opts.shadow or SHADOW
	local radius = opts.radius or RADIUS
	local width = opts.width or UDim.new(1, 0)
	local holder = make("Frame", {
		BackgroundTransparency = 1, LayoutOrder = opts.LayoutOrder or 0,
		Size = if opts.height then UDim2.new(width.Scale, width.Offset, 0, opts.height + shadow) else UDim2.new(width, UDim.new(0, 0)),
		AutomaticSize = if opts.height then Enum.AutomaticSize.None else Enum.AutomaticSize.Y,
		Position = opts.Position or UDim2.new(),
		AnchorPoint = opts.AnchorPoint or Vector2.zero,
	})
	local shade
	if shadow > 0 then
		shade = make("Frame", {
			Name = "Shadow", BackgroundColor3 = C.ink, BorderSizePixel = 0, Position = UDim2.fromOffset(shadow, shadow),
			Size = if opts.height then UDim2.new(1, -shadow, 1, -shadow) else UDim2.new(1, -shadow, 0, 0),
			Parent = holder,
		}, { corner(radius) })
	end
	local face = make(opts.face or "Frame", {
		Name = "Face", BackgroundColor3 = fill, BorderSizePixel = 0,
		Size = if opts.height then UDim2.new(1, -shadow, 1, -shadow) else UDim2.new(1, -shadow, 0, 0),
		AutomaticSize = if opts.height then Enum.AutomaticSize.None else Enum.AutomaticSize.Y,
		Parent = holder,
	}, { corner(radius), border(C.ink) })
	if face:IsA("TextButton") then
		face.AutoButtonColor = false
		face.Text = ""
	end
	-- A growing face moves its shadow with it. A scale size would feed back into the holder size.
	-- AbsoluteSize is in screen pixels, after the text size scale, so divide by that scale.
	if shade and not opts.height then
		local function follow()
			local scale = if self.uiScale then self.uiScale.Scale else 1
			shade.Size = UDim2.new(1, -shadow, 0, math.floor(face.AbsoluteSize.Y / scale + 0.5))
		end
		face:GetPropertyChangedSignal("AbsoluteSize"):Connect(follow)
		follow()
	end
	if opts.Parent then
		holder.Parent = opts.Parent
	end
	return holder, face
end

-- A pressable box: the face sinks onto its shadow while the mouse is down.
function View:button(text: string, fill: Color3, onClick: () -> (), opts)
	opts = opts or {}
	local C = self.C
	local size = opts.textSize or 13
	local shadow = opts.shadow or 3
	local width = opts.width or UDim.new(0, math.floor(#text * (SIZE_UP[size] or size) * 0.66) + 28)
	local holder, face = self:box(fill, {
		height = opts.height or 32, shadow = shadow, radius = opts.radius or 8, face = "TextButton", width = width,
		LayoutOrder = opts.LayoutOrder, Parent = opts.Parent, Position = opts.Position, AnchorPoint = opts.AnchorPoint,
	})
	self:label(text, size, opts.textColor or C.ink, opts.font or Font.Bold, {
		Size = UDim2.fromScale(1, 1), AutomaticSize = Enum.AutomaticSize.None,
		TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Center,
		TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd, Parent = face,
	})
	local function lift()
		face.Position = UDim2.new()
	end
	face.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 and shadow > 0 then
			face.Position = UDim2.fromOffset(shadow - 1, shadow - 1)
		end
	end)
	face.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			lift()
		end
	end)
	face.MouseLeave:Connect(lift)
	face.Activated:Connect(onClick)
	return holder, face
end

function View:checkbox(on: boolean, position: UDim2)
	local C = self.C
	local box = make("Frame", { BackgroundColor3 = if on then C.yellow else C.card, Position = position, Size = UDim2.fromOffset(18, 18) }, {
		corner(4), border(C.ink),
	})
	if on then
		self:label("✓", 14, C.ink, Font.Bold, {
			Size = UDim2.fromScale(1, 1), AutomaticSize = Enum.AutomaticSize.None,
			TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Center, Parent = box,
		})
	end
	return box
end

function View:tag(text: string, fill: Color3, order: number?)
	local C = self.C
	local tag = make("Frame", { BackgroundColor3 = fill, Size = UDim2.fromOffset(0, 24), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = order or 0 }, {
		corner(6), border(C.ink), padding(0, 8, 0, 8),
	})
	self:label(text, 10, C.ink, Font.Bold, {
		Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X, TextWrapped = false,
		TextYAlignment = Enum.TextYAlignment.Center, Parent = tag,
	})
	return tag
end

-- ===== the window =====

function View.new(widget, app)
	local self = setmetatable({}, View)
	self.widget = widget
	self.app = app
	self.shown = PAGE_SIZE
	self:build()
	return self
end

function View:build()
	self.C = Theme.colors()
	local C = self.C
	self:stopBlob()
	if self.root then
		self.root:Destroy()
	end
	self.widget.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local root = make("Frame", { Name = "DailyHelper", BackgroundColor3 = C.bg, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), ClipsDescendants = true })
	self.root = root
	self.uiScale = make("UIScale", { Parent = root })
	self:applyScale()

	self:label(FOOTER, 11, C.muted, Font.Medium, {
		Name = "Footer", AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, FOOTER_HEIGHT), AutomaticSize = Enum.AutomaticSize.None,
		TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Center, Parent = root,
	})
	local area = make("Frame", { Name = "Screens", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, -FOOTER_HEIGHT), Parent = root })

	self.intro = scroller("Start", 12, 20)
	self.intro.Parent = area
	self.info = scroller("Information", 14, 16)
	self.info.Parent = area

	-- Main screen: header, tabs, pages.
	local main = make("Frame", { Name = "Main", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false, Parent = area })
	self.main = main
	local header = make("Frame", { Name = "Header", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, HEADER_HEIGHT), Parent = main })
	self:label("Daily Helper", 21, C.ink, Font.Display, { Position = UDim2.fromOffset(16, 12), Size = UDim2.new(1, -170, 0, 26), AutomaticSize = Enum.AutomaticSize.None, Parent = header })
	self:label(self.app.versionText, 11, C.muted, Font.Medium, { Position = UDim2.fromOffset(16, 40), Size = UDim2.new(1, -170, 0, 14), AutomaticSize = Enum.AutomaticSize.None, Parent = header })
	local _, pill = self:box(C.card, {
		height = 26, shadow = 3, radius = 13, width = UDim.new(0, 100), Parent = header,
		AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -52, 0, 16),
	})
	self.apiDot = make("Frame", { BackgroundColor3 = C.muted, Position = UDim2.new(0, 10, 0.5, -4), Size = UDim2.fromOffset(8, 8), Parent = pill }, { round(), border(C.ink, 1) })
	self.apiText = self:label("API", 11, C.ink, Font.Bold, {
		Position = UDim2.fromOffset(24, 0), Size = UDim2.new(1, -28, 1, 0), AutomaticSize = Enum.AutomaticSize.None,
		TextYAlignment = Enum.TextYAlignment.Center, TextWrapped = false, Parent = pill,
	})
	self:button("i", C.card, function()
		self.app.actions.showInfo()
	end, { width = UDim.new(0, 28), height = 26, shadow = 3, radius = 13, textSize = 14, font = Font.Display, Parent = header, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 16) })

	local tabs = make("Frame", { Name = "Tabs", BackgroundTransparency = 1, Position = UDim2.fromOffset(16, 66), Size = UDim2.new(1, -32, 0, 38), Parent = header })
	self.tabs = tabs

	local body = make("Frame", { Name = "Body", BackgroundTransparency = 1, Position = UDim2.fromOffset(0, HEADER_HEIGHT), Size = UDim2.new(1, 0, 1, -HEADER_HEIGHT), Parent = main })
	self.pages = {}
	for _, name in TABS do
		self.pages[name] = scroller(name, 12, 16)
		self.pages[name].Parent = body
	end

	-- The search bar stays outside the list, so typing does not rebuild it and keeps the focus.
	local SEARCH_HEIGHT = 46
	local searchBar = make("Frame", { Name = "Search", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, SEARCH_HEIGHT), Visible = false, Parent = body }, {
		padding(8, 16, 0, 16),
	})
	self.searchBar = searchBar
	local _, searchFace = self:box(C.card, { height = 32, shadow = 3, radius = 8, Parent = searchBar })
	local searchBox = make("TextBox", {
		BackgroundTransparency = 1, ClearTextOnFocus = false, Text = self.app.state.query or "",
		PlaceholderText = "Search findings: title, script, text", PlaceholderColor3 = Color3.fromHex("6B6B6B"),
		TextColor3 = C.ink, TextSize = 14, FontFace = Font.Regular, TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -24, 1, 0), TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = searchFace,
	})
	self.searchBox = searchBox
	local searchSerial = 0
	searchBox:GetPropertyChangedSignal("Text"):Connect(function()
		-- Wait for a short pause in typing, then filter once.
		searchSerial += 1
		local serial = searchSerial
		task.delay(0.2, function()
			if serial == searchSerial and searchBox.Text ~= self.app.state.query then
				self.app.actions.setQuery(searchBox.Text)
			end
		end)
	end)
	self.pages.Findings.Position = UDim2.fromOffset(0, SEARCH_HEIGHT)
	self.pages.Findings.Size = UDim2.new(1, 0, 1, -SEARCH_HEIGHT)

	self.overlay = make("Frame", { Name = "Overlay", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 10, Visible = false, Parent = root })
	root.Parent = self.widget
	self:render()
end

-- The root is 1/scale of the window, and the UIScale grows it back to fill the window. Roblox
-- draws the text at the grown size, so it stays sharp.
function View:applyScale()
	local scale = self.app.state.scale
	self.uiScale.Scale = scale
	self.root.Size = UDim2.fromScale(1 / scale, 1 / scale)
end

function View:clear(target: Instance)
	for _, child in target:GetChildren() do
		if not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
			child:Destroy()
		end
	end
	return target
end

function View:render()
	local state = self.app.state
	local screen = state.screen
	self.intro.Visible = screen == "intro"
	self.info.Visible = screen == "info"
	self.main.Visible = screen == "main"
	if screen == "intro" then
		self:renderIntro()
	else
		self:stopBlob()
		if screen == "info" then
			self:renderInfo()
		else
			self:renderMain()
		end
	end
	self:renderOverlay()
end

-- ===== the liquid blob =====

function View:stopBlob()
	if self.blobConnection then
		self.blobConnection:Disconnect()
		self.blobConnection = nil
	end
end

-- Three layers of the same circles: shadow, black outline, yellow fill. The fill layer covers the
-- inner outlines, so the circles read as one liquid shape with one outline.
-- Motion: each circle sits on a rotating arm and travels a small circle. Roblox draws a moving
-- frame at whole pixels, so a slow Position change steps one pixel at a time and looks laggy. A
-- Rotation change draws with a smooth transform, so the arms move without steps.
function View:blob(parent: Instance)
	local C = self.C
	local stage = make("Frame", { Name = "Blob", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(240, 220), Parent = parent })
	local scale = make("UIScale", { Scale = 0.6, Parent = stage })

	-- One arm per circle and per layer. arms[i] holds the three arms of circle i.
	local arms = {}
	local function arm(layerFrame, x, y, reach, diameter, color, zIndex, outline)
		local pivot = make("Frame", {
			BackgroundTransparency = 1, Position = UDim2.new(0.5, x, 0.5, y), Size = UDim2.fromOffset(0, 0),
			ZIndex = zIndex, Parent = layerFrame,
		})
		local circle = make("Frame", {
			BackgroundColor3 = color, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(reach, 0), Size = UDim2.fromOffset(diameter, diameter), ZIndex = zIndex, Parent = pivot,
		}, { round() })
		if outline then
			border(C.ink).Parent = circle
		end
		return pivot
	end
	local layers = { { C.ink, 8, 0 }, { C.ink, 0, 6 }, { C.yellow, 0, 0 } }
	for index, spec in layers do
		local layerFrame = make("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = index, Parent = stage })
		for i, circle in BLOB do
			arms[i] = arms[i] or {}
			-- The reach and the speed differ per circle, so the outline keeps changing.
			local reach = 6 + (i % 3) * 2
			table.insert(arms[i], arm(layerFrame, circle[1] + spec[2], circle[2] + spec[2], reach, circle[3] + spec[3], spec[1], index, false))
		end
	end
	local DROPS = { { 100, -84, 22 }, { 118, -46, 13 } }
	local dropArms = {}
	for _, drop in DROPS do
		table.insert(dropArms, arm(stage, drop[1], drop[2], 5, drop[3], C.yellow, 5, true))
	end

	local started = os.clock()
	local function step()
		local t = os.clock() - started
		for i, group in arms do
			-- Degrees per second: 30 to 54, every second circle turns the other way.
			local speed = (30 + i * 6) * (if i % 2 == 0 then -1 else 1)
			local angle = i * 70 + t * speed
			for _, pivot in group do
				pivot.Rotation = angle
			end
		end
		for i, pivot in dropArms do
			pivot.Rotation = i * 120 + t * (if i == 1 then 60 else -80)
		end
	end
	step()
	self:stopBlob()
	self.blobConnection = RunService.RenderStepped:Connect(step)
	TweenService:Create(scale, TweenInfo.new(0.7, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

-- ===== start screen =====

function View:renderIntro()
	local C, app = self.C, self.app
	local target = self:clear(self.intro)

	local area = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 236), LayoutOrder = 1, Parent = target })
	self:blob(area)

	self:label("Daily Helper", 34, C.ink, Font.Display, { TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 2, Parent = target })
	self:label("A daily check-up for your Roblox place.", 14, C.body, Font.Medium, { TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 3, Parent = target })

	local _, card = self:box(C.card, { LayoutOrder = 4, Parent = target })
	padding(14).Parent = card
	list(Enum.FillDirection.Vertical, 8).Parent = card
	self:tag("LATEST ROBLOX API", C.yellow, 1).Parent = card
	self:label("Each scan reads the API of your Studio build from Roblox Creator. The checks know what Roblox marked deprecated this week.",
		13, C.body, Font.Regular, { LayoutOrder = 2, Parent = card })
	self:label(if app.apiVersion then "Last read: " .. app.apiVersion else "First read: when you run the first scan.",
		11, C.muted, Font.Mono, { LayoutOrder = 3, Parent = card })

	self:button("Start", C.yellow, app.actions.start, { width = UDim.new(1, 0), height = 50, shadow = 5, textSize = 17, font = Font.Title, LayoutOrder = 5, Parent = target })
	self:button("Information", C.card, app.actions.showInfo, { width = UDim.new(1, 0), height = 44, shadow = 4, textSize = 15, font = Font.Title, LayoutOrder = 6, Parent = target })
	self:scalePicker(7, target)
end

-- A row of size chips: "Text size  100%  125%  150%  175%".
function View:scalePicker(order: number, parent: Instance)
	local C, app = self.C, self.app
	local row = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 30), LayoutOrder = order, Parent = parent }, {
		list(Enum.FillDirection.Horizontal, 6),
	})
	self:label("Text size", 12, C.ink, Font.Bold, {
		Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X, TextWrapped = false,
		TextYAlignment = Enum.TextYAlignment.Center, LayoutOrder = 0, Parent = row,
	})
	for index, scale in SCALES do
		local active = math.abs(app.state.scale - scale) < 0.01
		local chip = make("TextButton", {
			AutoButtonColor = false, BackgroundColor3 = if active then C.ink else C.card,
			Text = math.floor(scale * 100 + 0.5) .. "%", TextSize = 12, FontFace = Font.Bold,
			TextColor3 = if active then C.white else C.ink, Size = UDim2.fromOffset(0, 26),
			AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = index, Parent = row,
		}, { round(), padding(0, 9, 0, 9), border(C.ink) })
		chip.Activated:Connect(function()
			app.actions.setScale(scale)
		end)
	end
end

-- ===== Information screen =====

function View:renderInfo()
	local C, app = self.C, self.app
	local target = self:clear(self.info)

	local top = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 38), LayoutOrder = 1, Parent = target })
	self:button("← Back", C.card, app.actions.back, { width = UDim.new(0, 88), height = 32, Parent = top })
	self:label("Information", 22, C.ink, Font.Display, {
		Position = UDim2.fromOffset(104, 0), Size = UDim2.new(1, -104, 0, 34), AutomaticSize = Enum.AutomaticSize.None,
		TextYAlignment = Enum.TextYAlignment.Center, Parent = top,
	})

	local function card(order: number, fill: Color3, title: string)
		local _, face = self:box(fill, { LayoutOrder = order, Parent = target })
		padding(14).Parent = face
		list(Enum.FillDirection.Vertical, 8).Parent = face
		self:label(title, 11, if fill == C.card then C.muted else C.ink, Font.Bold, { LayoutOrder = 0, Parent = face })
		return face
	end

	local checks = card(2, C.card, "WHAT IT CHECKS")
	for index, check in app.checks do
		local row = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = index, Parent = checks })
		make("Frame", { BackgroundColor3 = C[CHECK_COLORS[check.id]] or C.yellow, Position = UDim2.fromOffset(0, 2), Size = UDim2.fromOffset(16, 16), Parent = row }, { corner(4), border(C.ink) })
		local text = make("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(28, 0), Size = UDim2.new(1, -28, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Parent = row }, {
			list(Enum.FillDirection.Vertical, 1),
		})
		self:label(check.name, 14, C.ink, Font.Bold, { LayoutOrder = 1, Parent = text })
		self:label(check.desc, 12, C.muted, Font.Regular, { LayoutOrder = 2, Parent = text })
	end

	local source = card(3, C.card, "WHERE THE KNOWLEDGE COMES FROM")
	self:label("The Roblox API dump for your Studio build, read from setup.rbxcdn.com. It updates when Roblox ships a new Studio, with no plugin update. "
		.. "A member that Roblox marks deprecated shows up in the next scan.", 13, C.body, Font.Regular, { LayoutOrder = 1, Parent = source })
	self:label(if app.apiVersion then "Last read: " .. app.apiVersion else "Not read yet.", 11, C.muted, Font.Mono, { LayoutOrder = 2, Parent = source })

	self:scalePicker(5, target)

	local safe = card(4, C.yellow, "YOUR PLACE STAYS YOURS")
	self:label("It only reads your place. It changes something only when you press Apply, and it asks first. "
		.. "The Log tab records every run and every choice. Nothing leaves your computer.", 13, C.ink, Font.Medium, { LayoutOrder = 1, Parent = safe })

	self:button(if app.state.infoFrom == "main" then "Back to the audit" else "Start", C.yellow, function()
		if app.state.infoFrom == "main" then
			app.actions.back()
		else
			app.actions.start()
		end
	end, { width = UDim.new(1, 0), height = 46, shadow = 5, textSize = 16, font = Font.Title, LayoutOrder = 6, Parent = target })
end

-- ===== main screen =====

function View:renderMain()
	local C, state = self.C, self.app.state
	local status = state.apiStatus
	self.apiText.Text = if status == "live" then "API live" elseif status == "cached" then "API cached"
		elseif status == "offline" then "API offline" else "API ready"
	self.apiDot.BackgroundColor3 = if status == "live" then C.ok elseif status == "cached" then C.Warning
		elseif status == "offline" then C.Error else C.muted

	self:clear(self.tabs)
	local count = #state.findings
	for index, name in TABS do
		local active = state.tab == name
		self:button(if name == "Findings" and count > 0 then "Findings " .. count else name, if active then C.yellow else C.card, function()
			self.app.actions.setTab(name)
		end, {
			width = UDim.new(1 / #TABS, -6), height = 34, shadow = if active then 3 else 0, textSize = 13,
			Position = UDim2.new((index - 1) / #TABS, (index - 1) * 3, 0, 0), Parent = self.tabs,
		})
	end
	for name, page in self.pages do
		page.Visible = state.tab == name
	end
	self.searchBar.Visible = state.tab == "Findings" and state.stats ~= nil
	if state.tab == "Scan" then
		self:renderScan()
	elseif state.tab == "Findings" then
		self:renderFindings()
	else
		self:renderLog()
	end
end

function View:section(text: string, order: number, parent: Instance)
	return self:label(text, 11, self.C.muted, Font.Bold, { LayoutOrder = order, Parent = parent })
end

function View:renderScan()
	local C, state, actions = self.C, self.app.state, self.app.actions
	local target = self:clear(self.pages.Scan)
	local order = 0
	local function nextOrder()
		order += 1
		return order
	end

	self:section("SCOPE", nextOrder(), target)
	local _, segment = self:box(C.card, { height = 38, shadow = 3, radius = 8, LayoutOrder = nextOrder(), Parent = target })
	for index, option in { { "place", "Whole place" }, { "selection", "Selection" } } do
		local active = state.scope == option[1]
		local choice = make("TextButton", {
			AutoButtonColor = false, BackgroundColor3 = C.yellow, BackgroundTransparency = if active then 0 else 1,
			Text = option[2], TextSize = 13, FontFace = Font.Bold, TextColor3 = if active then C.ink else C.muted,
			Position = UDim2.new((index - 1) * 0.5, if index == 1 then 4 else 2, 0, 4), Size = UDim2.new(0.5, -6, 1, -8),
			Parent = segment,
		}, { corner(6) })
		if active then
			border(C.ink).Parent = choice
		end
		choice.Activated:Connect(function()
			actions.setScope(option[1])
		end)
	end

	self:section("CHECKS", nextOrder(), target)
	for _, check in self.app.checks do
		local on = state.enabled[check.id]
		local _, row = self:box(C.card, { height = 50, shadow = if on then 3 else 0, radius = 8, face = "TextButton", LayoutOrder = nextOrder(), Parent = target })
		self:checkbox(on, UDim2.fromOffset(12, 15)).Parent = row
		self:label(check.name, 14, C.ink, Font.Bold, { Position = UDim2.fromOffset(42, 7), Size = UDim2.new(1, -54, 0, 18), AutomaticSize = Enum.AutomaticSize.None, Parent = row })
		self:label(check.desc, 12, C.muted, Font.Regular, {
			Position = UDim2.fromOffset(42, 26), Size = UDim2.new(1, -54, 0, 14), AutomaticSize = Enum.AutomaticSize.None,
			TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd, Parent = row,
		})
		row.Activated:Connect(function()
			actions.toggleCheck(check.id)
		end)
	end

	local _, run = self:button(if state.running then state.progress else "Run Audit", if state.running then C.card else C.yellow, function()
		if not state.running then
			actions.run()
		end
	end, { width = UDim.new(1, 0), height = 48, shadow = if state.running then 0 else 5, textSize = 16, font = Font.Title, LayoutOrder = nextOrder(), Parent = target })
	self.runLabel = run:FindFirstChildOfClass("TextLabel")

	local stats = state.stats
	if stats then
		local _, card = self:box(C.card, { height = 118, LayoutOrder = nextOrder(), Parent = target })
		self:label("LAST AUDIT  ·  " .. Log.day(stats.time), 11, C.muted, Font.Bold, { Position = UDim2.fromOffset(14, 12), Size = UDim2.new(1, -28, 0, 14), AutomaticSize = Enum.AutomaticSize.None, Parent = card })
		self:label(string.format('%d<font size="13" color="#%s"> / 100</font>', stats.score, C.muted:ToHex()), 42, C.ink, Font.Display, {
			RichText = true, Position = UDim2.fromOffset(14, 32), Size = UDim2.fromOffset(140, 48), AutomaticSize = Enum.AutomaticSize.None, Parent = card,
		})
		local counts = make("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 32), Size = UDim2.fromOffset(118, 56), Parent = card })
		for index, kind in { "Error", "Warning", "Info" } do
			local value = stats.counts[kind] or 0
			local word = if kind == "Info" then "info" else string.lower(kind) .. (if value == 1 then "" else "s")
			make("Frame", { BackgroundColor3 = C[kind], Position = UDim2.fromOffset(0, (index - 1) * 19 + 3), Size = UDim2.fromOffset(11, 11), Parent = counts }, { corner(3), border(C.ink, 1.5) })
			self:label(value .. " " .. word, 13, C.ink, Font.Bold, { Position = UDim2.fromOffset(18, (index - 1) * 19), Size = UDim2.new(1, -18, 0, 17), AutomaticSize = Enum.AutomaticSize.None, Parent = counts })
		end
		self:label(string.format("%d scripts  ·  %d instances  ·  %.1f s", stats.scripts, stats.instances, stats.seconds), 12, C.muted, Font.Medium, {
			Position = UDim2.fromOffset(14, 90), Size = UDim2.new(1, -28, 0, 14), AutomaticSize = Enum.AutomaticSize.None, Parent = card,
		})
	end
end

function View:setProgress(text: string)
	if self.runLabel and self.runLabel.Parent then
		self.runLabel.Text = text
	end
end

-- ===== Findings =====

local FILTERS = { { "All", "All" }, { "Error", "Errors" }, { "Warning", "Warnings" }, { "Info", "Info" } }

local PREVIEW_COLORS = { ["-"] = Color3.fromHex("FFD9D9"), ["+"] = Color3.fromHex("D4F5E6") }

-- The before/after lines of a script fix, computed from the script as it is now.
function View:preview(finding, parent: Instance)
	local C = self.C
	local ok, rows, reason = pcall(finding.fix.preview)
	local box = make("Frame", {
		BackgroundColor3 = C.bg, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 5,
		Parent = parent,
	}, { corner(6), border(C.ink, 1.5), padding(6, 8, 6, 8), list(Enum.FillDirection.Vertical, 2) })
	if not ok or not rows then
		self:label(if ok then tostring(reason) else "No preview: " .. tostring(rows), 12, C.ink, Font.Bold, { Parent = box })
		return
	end
	for index, row in rows do
		local text = string.gsub(string.gsub(row.text, "	", "  "), "^%s+", function(space)
			return string.rep(" ", math.min(#space, 8))
		end)
		self:label(string.format("%s %4d  %s", row.kind, row.line, text), 11, C.ink, Font.Mono, {
			BackgroundTransparency = 0, BackgroundColor3 = PREVIEW_COLORS[row.kind], TextWrapped = false,
			TextTruncate = Enum.TextTruncate.AtEnd, LayoutOrder = index, Parent = box,
		})
	end
end

function View:card(finding, order: number)
	local C, actions = self.C, self.app.actions
	local decided = finding.status ~= nil and finding.status ~= "Failed"
	local holder, face = self:box(if decided then C.bg else C.card, { shadow = if decided then 0 else SHADOW, LayoutOrder = order })
	padding(12, 14, 12, 14).Parent = face
	list(Enum.FillDirection.Vertical, 6).Parent = face

	local tags = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 24), LayoutOrder = 1, Parent = face }, { list(Enum.FillDirection.Horizontal, 6) })
	self:tag(finding.tag, C[finding.severity] or C.yellow, 1).Parent = tags
	if finding.status then
		self:tag(string.upper(finding.status), if finding.status == "Applied" then C.ok elseif finding.status == "Failed" then C.Error else C.card, 2).Parent = tags
	end

	self:label(finding.title, 15, C.ink, Font.Bold, { LayoutOrder = 2, Parent = face })
	self:label(finding.path, 11, C.muted, Font.Mono, { LayoutOrder = 3, Parent = face })
	self:label(finding.text, 13, C.body, Font.Regular, { LayoutOrder = 4, Parent = face })
	if finding.fix then
		self:label("Change: " .. finding.fix.label, 12, C.ink, Font.Bold, { LayoutOrder = 4, Parent = face })
	end
	if finding.fix and finding.fix.preview and not decided then
		self:preview(finding, face)
	end
	if finding.note then
		self:label(finding.note, 12, C.Error, Font.Bold, { LayoutOrder = 6, Parent = face })
	end

	local row = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 35), LayoutOrder = 7, Parent = face }, {
		list(Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Right),
	})
	local buttonOrder = 0
	local function add(text, fill, onClick)
		buttonOrder += 1
		self:button(text, fill, onClick, { LayoutOrder = buttonOrder, Parent = row })
	end
	if finding.target then
		local isScript = typeof(finding.target) == "Instance" and finding.target:IsA("LuaSourceContainer")
		add(if isScript then "Open" else "Select", C.card, function()
			actions.open(finding)
		end)
	end
	if finding.status == "Applied" and finding.snapshots then
		add("Restore", C.card, function()
			actions.restore(finding)
		end)
	end
	if not decided then
		if finding.fix then
			add("Skip", C.card, function()
				actions.skip(finding)
			end)
			add("Apply", C.yellow, function()
				actions.apply(finding)
			end)
		else
			add("Mark reviewed", C.card, function()
				actions.review(finding)
			end)
		end
	end
	return holder
end

function View:renderFindings()
	local C, state, actions = self.C, self.app.state, self.app.actions
	local target = self.pages.Findings
	local keep = target.CanvasPosition
	self:clear(target)

	if not state.stats then
		self:label("Run an audit on the Scan tab to see findings here.", 14, C.muted, Font.Medium, { LayoutOrder = 1, Parent = target })
		return
	end

	local pending = self.app.pendingFixes()
	if #pending > 0 then
		local _, banner = self:box(C.yellow, { LayoutOrder = 1, Parent = target })
		padding(14).Parent = banner
		list(Enum.FillDirection.Vertical, 8).Parent = banner
		self:label(string.format("%d %s a recommended change.", #pending, if #pending == 1 then "finding has" else "findings have"),
			15, C.ink, Font.Bold, { LayoutOrder = 1, Parent = banner })
		self:label("You know your map best. Read each one, then apply or skip it.", 13, C.ink, Font.Medium, { LayoutOrder = 2, Parent = banner })
		self:button("Review changes", C.card, actions.openPrompt, { LayoutOrder = 3, Parent = banner })
	end

	local chips = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 28), LayoutOrder = 2, Parent = target }, { list(Enum.FillDirection.Horizontal, 6) })
	for index, filter in FILTERS do
		local amount = if filter[1] == "All" then #state.findings else (state.stats.counts[filter[1]] or 0)
		local active = state.filter == filter[1]
		local chip = make("TextButton", {
			AutoButtonColor = false, BackgroundColor3 = if active then C.ink else C.card,
			Text = filter[2] .. " " .. amount, TextSize = 12, FontFace = Font.Bold,
			TextColor3 = if active then C.white else C.ink, Size = UDim2.fromOffset(0, 28),
			AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = index, Parent = chips,
		}, { round(), padding(0, 11, 0, 11), border(C.ink) })
		chip.Activated:Connect(function()
			actions.setFilter(filter[1])
		end)
	end

	local query = string.lower(state.query or "")
	local function matches(finding): boolean
		if query == "" then
			return true
		end
		local text = string.lower(table.concat({ finding.title, finding.path, finding.text, finding.tag or "",
			if finding.fix then finding.fix.label else "" }, " "))
		return string.find(text, query, 1, true) ~= nil
	end

	local shown, total = 0, 0
	for _, finding in state.findings do
		if (state.filter == "All" or finding.severity == state.filter) and matches(finding) then
			total += 1
			if shown < self.shown then
				shown += 1
				self:card(finding, 10 + shown).Parent = target
			end
		end
	end
	if total == 0 then
		self:label(if query ~= "" then "No finding matches \"" .. state.query .. "\"." else "Nothing here. Good work.",
			14, C.muted, Font.Medium, { LayoutOrder = 3, Parent = target })
	elseif total > shown then
		self:button(string.format("Show more (%d left)", total - shown), C.card, function()
			self.shown += PAGE_SIZE
			self:render()
		end, { width = UDim.new(1, 0), height = 38, LayoutOrder = 100000, Parent = target })
	end
	task.defer(function()
		target.CanvasPosition = keep
	end)
end

-- ===== Log =====

local KIND_COLORS = { done = "ok", applied = "yellow", undo = "Info", redo = "Info", reviewed = "Warning", failed = "Error", skipped = "card", info = "card" }

function View:renderLog()
	local C, app = self.C, self.app
	local target = self:clear(self.pages.Log)

	local top = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 35), LayoutOrder = 1, Parent = target })
	self:label("Session log", 17, C.ink, Font.Display, {
		Size = UDim2.new(1, -160, 1, 0), AutomaticSize = Enum.AutomaticSize.None, TextYAlignment = Enum.TextYAlignment.Center, Parent = top,
	})
	local buttons = make("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0, 160, 1, 0), Parent = top }, {
		list(Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Right),
	})
	self:button("Copy", C.card, app.actions.openCopy, { LayoutOrder = 1, Parent = buttons })
	self:button("Clear", C.card, app.actions.clearLog, { LayoutOrder = 2, Parent = buttons })

	local _, box = self:box(C.card, { LayoutOrder = 2, Parent = target })
	padding(12).Parent = box
	list(Enum.FillDirection.Vertical, 10).Parent = box
	local entries = app.log.entries
	if #entries == 0 then
		self:label("No entries yet. A run, an apply, a skip and an undo each add a line.", 13, C.muted, Font.Regular, { Parent = box })
	end
	-- Newest first, thus the last choice shows without a scroll.
	local first = math.max(1, #entries - 149)
	for index = #entries, first, -1 do
		local entry = entries[index]
		local line = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = #entries - index, Parent = box })
		self:label(Log.clock(entry.time), 11, C.muted, Font.Mono, { Size = UDim2.new(0, 64, 0, 16), AutomaticSize = Enum.AutomaticSize.None, Parent = line })
		make("Frame", { BackgroundColor3 = C[KIND_COLORS[entry.kind] or "card"], Position = UDim2.fromOffset(68, 3), Size = UDim2.fromOffset(10, 10), Parent = line }, { corner(3), border(C.ink, 1.5) })
		self:label(entry.text, 13, C.body, Font.Regular, { Position = UDim2.fromOffset(86, 0), Size = UDim2.new(1, -86, 0, 0), Parent = line })
	end

	local _, note = self:box(C.yellow, { shadow = 0, LayoutOrder = 3, Parent = target })
	padding(12, 14, 12, 14).Parent = note
	list(Enum.FillDirection.Vertical, 6).Parent = note
	self:label("The log stays in the plugin settings for this place. The plugin changes your place only when you press Apply.", 12, C.ink, Font.Medium, { LayoutOrder = 1, Parent = note })
	self:label("Copy shows the log as text that you can select and copy.", 12, C.ink, Font.Regular, { LayoutOrder = 2, Parent = note })
end

-- ===== Overlays: the apply prompt and the copy box =====

function View:dimmer()
	local C = self.C
	self:clear(self.overlay)
	make("TextButton", {
		AutoButtonColor = false, Text = "", BackgroundColor3 = C.dim, BackgroundTransparency = 0.45,
		Size = UDim2.fromScale(1, 1), Parent = self.overlay,
	})
	local holder, face = self:box(C.card, {
		Parent = self.overlay, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), width = UDim.new(1, -28),
	})
	make("UISizeConstraint", { MaxSize = Vector2.new(460, math.huge), Parent = holder })
	padding(18).Parent = face
	list(Enum.FillDirection.Vertical, 10).Parent = face
	return face
end

function View:renderOverlay()
	local state = self.app.state
	if state.screen == "main" and state.overlay == "prompt" then
		self:renderPrompt()
	elseif state.screen == "main" and state.overlay == "copy" then
		self:renderCopy()
	else
		self.overlay.Visible = false
		self:clear(self.overlay)
	end
end

function View:renderPrompt()
	local C, app = self.C, self.app
	local state, actions = app.state, app.actions
	local pending = app.pendingFixes()
	if #pending == 0 then
		state.overlay = nil
		self.overlay.Visible = false
		return
	end
	self.overlay.Visible = true
	local card = self:dimmer()
	self:label("Apply recommended changes?", 18, C.ink, Font.Display, { LayoutOrder = 1, Parent = card })
	self:label(string.format("The audit can make %s for you. Pick only the ones that fit your map. Nothing changes until you press Apply.",
		if #pending == 1 then "1 change" else #pending .. " changes"), 13, C.body, Font.Regular, { LayoutOrder = 2, Parent = card })

	local scroll = make("ScrollingFrame", {
		BackgroundTransparency = 1, BorderSizePixel = 0, LayoutOrder = 3, Parent = card,
		Size = UDim2.new(1, 0, 0, math.min(#pending * 62, 260)), CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 6, ScrollBarImageColor3 = C.ink,
		VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar,
	}, { list(Enum.FillDirection.Vertical, 8), padding(0, 4, 4, 0) })
	local picked = 0
	for index, finding in pending do
		local on = state.picked[finding] == true
		if on then
			picked += 1
		end
		local _, row = self:box(if on then C.card else C.bg, { height = 50, shadow = if on then 3 else 0, radius = 8, face = "TextButton", LayoutOrder = index, Parent = scroll })
		self:checkbox(on, UDim2.fromOffset(12, 15)).Parent = row
		self:label(finding.fix.label .. (if finding.fix.risky then "   (check first)" else ""), 13, C.ink, Font.Bold, {
			Position = UDim2.fromOffset(42, 7), Size = UDim2.new(1, -54, 0, 18), AutomaticSize = Enum.AutomaticSize.None,
			TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd, Parent = row,
		})
		self:label(finding.path, 11, C.muted, Font.Mono, {
			Position = UDim2.fromOffset(42, 27), Size = UDim2.new(1, -54, 0, 14), AutomaticSize = Enum.AutomaticSize.None,
			TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd, Parent = row,
		})
		row.Activated:Connect(function()
			actions.togglePick(finding)
		end)
	end

	self:label("Property changes undo with Ctrl+Z. Script changes undo in the script editor. The Log tab records every choice.",
		12, C.muted, Font.Regular, { LayoutOrder = 4, Parent = card })
	local row = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 44), LayoutOrder = 5, Parent = card })
	self:button("Not now", C.card, actions.closeOverlay, { width = UDim.new(0.5, -6), height = 40, textSize = 14, Parent = row })
	self:button(if picked > 0 then string.format("Apply %d selected", picked) else "Pick a change", if picked > 0 then C.yellow else C.bg, function()
		if picked > 0 then
			actions.applyPicked()
		end
	end, { width = UDim.new(0.5, -6), height = 40, textSize = 14, shadow = if picked > 0 then 3 else 0, Position = UDim2.new(0.5, 6, 0, 0), Parent = row })
end

function View:renderCopy()
	local C, app = self.C, self.app
	self.overlay.Visible = true
	local card = self:dimmer()
	self:label("Copy the log", 18, C.ink, Font.Display, { LayoutOrder = 1, Parent = card })
	self:label("Click the text, press Ctrl+A, then Ctrl+C.", 13, C.body, Font.Regular, { LayoutOrder = 2, Parent = card })
	local scroll = make("ScrollingFrame", {
		BackgroundColor3 = C.bg, BorderSizePixel = 0, LayoutOrder = 3, Parent = card, Size = UDim2.new(1, 0, 0, 260),
		CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 6, ScrollBarImageColor3 = C.ink,
	}, { corner(8), border(C.ink), padding(10) })
	local text = app.log:text()
	local box = make("TextBox", {
		BackgroundTransparency = 1, ClearTextOnFocus = false, TextEditable = false, MultiLine = true,
		Text = if text == "" then "(empty)" else text, TextSize = 12, FontFace = Font.Mono, TextColor3 = C.body,
		TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = true,
		Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Parent = scroll,
	})
	box.Focused:Connect(function()
		box.SelectionStart = 1
		box.CursorPosition = #box.Text + 1
	end)
	self:button("Close", C.card, app.actions.closeOverlay, { width = UDim.new(1, 0), height = 38, textSize = 14, LayoutOrder = 4, Parent = card })
end

return View
