-- A stand-in for the game around ForeverCountdown.lua: UIParent, the minimap, the objective
-- tracker's fonts, header and Text Size setting, timers and the clock, so Tests/run.lua can run
-- the panel frame by frame, across the launch too, without the game.
-- `local NewGame = dofile("Tests/standin.lua")`, then `local game = NewGame(now)` for each test.
--
-- Blizzard's code below copies wow-ui-source (forever, 1.60.1), cut to what the addon touches:
--   Blizzard_ObjectiveTracker: Blizzard_ObjectiveTrackerFonts.xml, Blizzard_ObjectiveTrackerManager.lua
--     (SetTextSize), Blizzard_ObjectiveTrackerShared.lua (OBJECTIVE_TRACKER_COLOR) and
--     Blizzard_ObjectiveTrackerModule.xml (the section header's sizes)
--   Blizzard_SharedXML/Mainline/SoundKitConstants.lua
-- The widgets have only the methods Forever's widgets have (Tests/WidgetAPI.lua). In combat
-- (game:EnterCombat) the game refuses the addon's code moving, showing or hiding a protected
-- frame, as the game does (see Combat). What the stand-in assumes beyond the game's code is
-- marked ASSUMED: a stand-in that behaves better than the game hides bugs.

-- This file runs under luajit, outside the game, and uses standard Lua's dofile, loadfile and
-- debug, which the game doesn't have. It plays the game, so it sets the game's globals.
---@diagnostic disable: undefined-global, lowercase-global, create-global

local WIDGET_METHODS = {}
for widgetType, names in pairs(dofile("Tests/WidgetAPI.lua")) do
	local set = {}
	for _, name in ipairs(names) do
		set[name] = true
	end
	WIDGET_METHODS[widgetType] = set
end

local game -- the game the current test plays

--------------------------------------------------------------------------------
-- Combat. While InCombatLockdown() is true, the game refuses a protected frame's protected
-- methods when the addon's code calls them: the call does nothing and the game reports
-- ADDON_ACTION_BLOCKED. The stand-in does the same and lists each refusal in game.blocked; the
-- tests fail on any.
--------------------------------------------------------------------------------

-- The protected methods: those wow-ui-source marks IsProtectedFunction (forever,
-- Blizzard_APIDocumentationGenerated), by the part of the widget API they are in.
local PROTECTED_API = {
	-- SimpleScriptRegionAPIDocumentation.lua and SimpleScriptRegionResizingAPIDocumentation.lua
	ScriptRegion = {
		"AdjustPointsOffset", "ClearAllPoints", "ClearPoint", "ClearPointsOffset", "EnableMouse",
		"EnableMouseMotion", "EnableMouseWheel", "FocusEnter", "FocusExit", "MouseDown", "MouseUp",
		"SetAllPoints", "SetCollapsesLayout", "SetHeight", "SetMouseClickEnabled",
		"SetMouseMotionEnabled", "SetParent", "SetPassThroughButtons", "SetPoint", "SetPointsOffset",
		"SetPropagateMouseClicks", "SetPropagateMouseMotion", "SetRoundLayoutToNearestPixel",
		"SetSize", "SetWidth",
	},
	-- SimpleRegionAPIDocumentation.lua
	Region = { "SetIgnoreParentScale", "SetScale" },
	-- SimpleFrameAPIDocumentation.lua
	Frame = {
		"AddRoleset", "ClearAttribute", "ClearAttributes", "EnableGamePadButton",
		"EnableGamePadStick", "EnableKeyboard", "Hide", "Lower", "Raise", "RemoveRoleset",
		"ResizeToBoundsRect", "SetClampRectInsets", "SetClampedToScreen", "SetFixedFrameLevel",
		"SetFixedFrameStrata", "SetFrameLevel", "SetFrameStrata", "SetHitRectInsets",
		"SetHyperlinksEnabled", "SetID", "SetIgnoreParentScale", "SetRolesets", "SetScale",
		"SetShown", "SetToplevel", "SetUsingParentLevel", "Show", "StartMoving", "StartSizing",
		"StopMovingOrSizing",
	},
	-- SimpleButtonAPIDocumentation.lua
	Button = { "Disable", "Enable", "RegisterForClicks", "RegisterForMouse", "SetEnabled" },
}
-- The parts each widget type has (BlizzardInterfaceResources, Resources/WidgetAPI.lua): a
-- texture's Show, for one, is the region's and not protected.
local PROTECTED_METHODS = {}
for widgetType, parts in pairs({
	Frame = { "ScriptRegion", "Frame" },
	Button = { "ScriptRegion", "Frame", "Button" },
	Texture = { "ScriptRegion", "Region" },
	FontString = { "ScriptRegion", "Region" },
}) do
	local set = {}
	for _, part in ipairs(parts) do
		for _, name in ipairs(PROTECTED_API[part]) do
			set[name] = true
		end
	end
	PROTECTED_METHODS[widgetType] = set
end

local FRAME_TYPES = { Frame = true, Button = true }

-- Whether a widget is protected, as IsProtected says. A frame is protected explicitly
-- (widget.protected: protected="true" in its XML or its template's, as SecureFrameTemplate in
-- Blizzard_FrameXML/SecureTemplatesBase.xml, which the secure templates inherit), or because a
-- frame under it is: seen in game (taint log, 2026-10-17), the action bars, protected only
-- through their buttons, had SetPoint and ClearAllPoints blocked in combat. ASSUMED: a texture
-- or text is protected when its frame is (regions have protected methods, and nothing else
-- could make one protected).
local function IsProtected(widget)
	if widget.protected then
		return true
	end
	if FRAME_TYPES[widget.widgetType] then
		for _, child in ipairs(widget.children) do
			if FRAME_TYPES[child.widgetType] and IsProtected(child) then
				return true
			end
		end
		return false
	end
	return widget.parent ~= nil and IsProtected(widget.parent)
end

-- Whose code is calling, as the game taints a run of code. A run is what the game starts: an
-- event's handler, a frame's script, a timer, a call into Blizzard's code. It is the addon's
-- from the moment it enters a function from the addon's files to the end of the run, Blizzard's
-- code it calls on the way included; hooksecurefunc keeps its hook's taint inside the hook. An
-- event the game sends during a run goes to each handler in a run of its own, which starts with
-- the outer run's taint and gives none back: seen in game (Just the Trees' taint log,
-- 2026-10-17), an addon's ADDON_LOADED handler ran inside the player's first open of the talent
-- window, and nothing after it in that open ran tainted. A call the tests make outside a run is
-- the addon's when the addon's code is on the stack.
-- Not modeled: taint the addon leaves in Blizzard's tables for later (the game's taint log
-- finds that).
local ADDON_FILES = { ["@Countdown.lua"] = true, ["@ForeverCountdown.lua"] = true }

local function AddonOnStack()
	local level = 3
	while true do
		local info = debug.getinfo(level, "S")
		if not info then
			return false
		end
		if ADDON_FILES[info.source] then
			return true
		end
		level = level + 1
	end
end

-- In combat, a debug hook marks the run tainted as it enters the addon's code (tail calls too,
-- which leave no trace on the stack).
local function OnCall()
	local run = game.run
	if run and not run.tainted then
		local info = debug.getinfo(2, "S")
		if info and ADDON_FILES[info.source] then
			run.tainted = true
		end
	end
end

local function AddonCalling()
	return (game.run ~= nil and game.run.tainted) or AddonOnStack()
end

local function EndRun(run, ...)
	if game.run == run then
		game.run = nil
	end
	return ...
end

-- Runs func as the game runs code. Within a run, it is part of that run.
local function Run(func, ...)
	if game.run then
		return func(...)
	end
	local run = { tainted = AddonOnStack() }
	game.run = run
	return EndRun(run, func(...))
end

local function EndRunApart(outer, ...)
	game.run = outer
	return ...
end

-- Runs an event's handler: a run of its own, even within another run.
local function RunApart(func, ...)
	local outer = game.run
	game.run = { tainted = outer and outer.tainted or AddonOnStack() }
	return EndRunApart(outer, func(...))
end

-- A hook's taint stays inside the hook (hooksecurefunc).
local function RunHook(hook, ...)
	local run = game.run
	local tainted = run and run.tainted
	hook(...)
	if run then
		run.tainted = tainted
	end
end

--------------------------------------------------------------------------------
-- Widgets. A widget has only the methods its type has in Forever. The ones below do what the
-- game does with what the tests look at; any other method only records its last arguments in
-- widget.calls. Every call is counted in game.calls.
--------------------------------------------------------------------------------

local Widget = {}

local WidgetMeta = {
	__index = function(widget, key)
		local widgetType = rawget(widget, "widgetType")
		if not WIDGET_METHODS[widgetType][key] then
			return nil
		end
		local method = Widget[key]
		local protectedMethod = PROTECTED_METHODS[widgetType] and PROTECTED_METHODS[widgetType][key]
		return function(self, ...)
			game.calls[key] = (game.calls[key] or 0) + 1
			if protectedMethod and game.combat and IsProtected(self) and AddonCalling() then
				game.blocked[#game.blocked + 1] = (self.name or "a protected " .. widgetType) .. ":" .. key .. "()"
				return
			end
			if method then
				return method(self, ...)
			end
			self.calls[key] = { ... }
		end
	end,
}

local function NewWidget(widgetType, parent)
	assert(WIDGET_METHODS[widgetType], "no such widget type: " .. tostring(widgetType))
	local widget = setmetatable({
		widgetType = widgetType,
		parent = parent,
		children = {},
		shown = true,
		alpha = 1,
		width = 0,
		height = 0,
		scripts = {},
		calls = {},
		anchors = {},
	}, WidgetMeta)
	if parent then
		parent.children[#parent.children + 1] = widget
	end
	game.widgets[#game.widgets + 1] = widget
	return widget
end

function Widget:GetObjectType()
	return self.widgetType
end
function Widget:IsProtected()
	return IsProtected(self), self.protected == true
end
function Widget:GetParent()
	return self.parent
end
function Widget:SetParent(parent)
	self.parent = parent
end
function Widget:IsShown()
	return self.shown
end
function Widget:IsVisible()
	return self.shown and (self.parent == nil or self.parent:IsVisible())
end
function Widget:SetShown(shown)
	self.shown = not not shown
end
function Widget:Show()
	self.shown = true
end
function Widget:Hide()
	self.shown = false
end
function Widget:SetAlpha(alpha)
	self.alpha = alpha
end
function Widget:GetAlpha()
	return self.alpha
end
function Widget:SetScript(name, func)
	self.scripts[name] = func
end
function Widget:GetScript(name)
	return self.scripts[name]
end

-- Events a frame registers go to its OnEvent script, with the frame and the event first, until
-- it unregisters them.
function Widget:RegisterEvent(event)
	self.registered = self.registered or {}
	if self.registered[event] then
		return
	end
	local handler
	handler = function(...)
		if self.registered[event] ~= handler then
			return true -- unregistered: the game sends it no more
		end
		local script = self.scripts.OnEvent
		if script then
			script(self, event, ...)
		end
		return false
	end
	self.registered[event] = handler
	local list = game.events[event] or {}
	game.events[event] = list
	list[#list + 1] = handler
end
function Widget:UnregisterEvent(event)
	if self.registered then
		self.registered[event] = nil
	end
end

-- Anchors: kept as given. A point set again replaces its earlier anchor, as in the game.
function Widget:SetPoint(point, a, b, c, d)
	local relativeTo, relativePoint, x, y = self.parent, point, 0, 0
	if type(a) == "number" then
		x, y = a, b or 0
	elseif a ~= nil then
		relativeTo = a
		if type(b) == "string" then
			relativePoint, x, y = b, c or 0, d or 0
		elseif type(b) == "number" then
			x, y = b, c or 0
		end
	end
	for _, anchor in ipairs(self.anchors) do
		if anchor[1] == point then
			anchor[2], anchor[3], anchor[4], anchor[5] = relativeTo, relativePoint, x, y
			return
		end
	end
	self.anchors[#self.anchors + 1] = { point, relativeTo, relativePoint, x, y }
end
function Widget:SetAllPoints()
	self:SetPoint("TOPLEFT")
	self:SetPoint("BOTTOMRIGHT")
end
function Widget:ClearAllPoints()
	self.anchors = {}
end
function Widget:GetNumPoints()
	return #self.anchors
end
function Widget:GetPoint(index)
	local anchor = self.anchors[index or 1]
	if anchor then
		return unpack(anchor)
	end
end
-- ASSUMED: a region anchored by its top left and its top right (the header) is as wide as its
-- parent; the stand-in does no other layout.
function Widget:GetWidth()
	if self.widgetType == "FontString" then
		return self:GetStringWidth()
	end
	if self.width == 0 and #self.anchors >= 2 and self.parent then
		return self.parent:GetWidth()
	end
	return self.width
end
function Widget:GetHeight()
	if self.widgetType == "FontString" then
		return self:GetStringHeight()
	end
	return self.height
end
function Widget:SetSize(width, height)
	self.width, self.height = width, height
end
function Widget:SetWidth(width)
	self.width = width
end
function Widget:SetHeight(height)
	self.height = height
end
function Widget:GetSize()
	return self:GetWidth(), self:GetHeight()
end
-- ASSUMED: the stand-in does no layout; a frame's place on the screen is what a test gives it
-- (widget.rect = { left, top, right, bottom }, in its own units), else none.
function Widget:GetLeft()
	return self.rect and self.rect[1]
end
function Widget:GetTop()
	return self.rect and self.rect[2]
end
function Widget:GetRight()
	return self.rect and self.rect[3]
end
function Widget:GetBottom()
	return self.rect and self.rect[4]
end
function Widget:SetScale(scale)
	self.scale = scale
end
function Widget:GetEffectiveScale()
	return (self.scale or 1) * (self.parent and self.parent:GetEffectiveScale() or 1)
end

function Widget:CreateTexture(_, layer)
	local texture = NewWidget("Texture", self)
	texture.layer = layer
	return texture
end
function Widget:CreateFontString(_, layer)
	local text = NewWidget("FontString", self)
	text.layer = layer
	return text
end
function Widget:CreateAnimationGroup()
	local group = NewWidget("AnimationGroup", self)
	group.animations = {}
	return group
end

-- Textures.
function Widget:SetTexture(file)
	self.texture = file
end
-- The atlases the addon uses, at their size in UI units (BlizzardInterfaceResources, forever,
-- Resources/AtlasInfo.lua: interface/questframe/questtracker and interface/minimap/objecticonsatlas).
-- The game finds an atlas whatever the case of its name (Blizzard's own files spell these both ways).
local ATLAS_SIZES = {
	["ui-questtracker-secondary-objective-header"] = { 300, 30 },
	["ui-questtrackerbutton-secondary-collapse"] = { 16, 16 },
	["ui-questtrackerbutton-secondary-collapse-pressed"] = { 16, 16 },
	["ui-questtrackerbutton-secondary-expand"] = { 16, 16 },
	["ui-questtrackerbutton-secondary-expand-pressed"] = { 16, 16 },
	["ui-questtrackerbutton-yellow-highlight"] = { 16, 16 },
	questnormal = { 64, 64 },
	questturnin = { 32, 32 },
	questdaily = { 32, 32 },
}
function Widget:SetAtlas(atlas, useAtlasSize)
	self.atlas = atlas
	local size = ATLAS_SIZES[atlas:lower()]
	if useAtlasSize and size then
		self.width, self.height = size[1], size[2]
	end
	return size ~= nil
end
function Widget:GetAtlas()
	return self.atlas
end
function Widget:SetDesaturated(desaturated)
	self.desaturated = not not desaturated
end
function Widget:IsDesaturated()
	return self.desaturated == true
end
function Widget:SetVertexColor(r, g, b, a)
	self.color = { r, g, b, a or 1 }
end
function Widget:GetVertexColor()
	local color = self.color or { 1, 1, 1, 1 }
	return color[1], color[2], color[3], color[4]
end

-- Buttons: their textures are made by the atlas setters; a click runs OnClick.
function Widget:SetNormalAtlas(atlas)
	self.normal = self.normal or NewWidget("Texture", self)
	self.normal.atlas = atlas
end
function Widget:SetPushedAtlas(atlas)
	self.pushed = self.pushed or NewWidget("Texture", self)
	self.pushed.atlas = atlas
end
function Widget:SetHighlightAtlas(atlas)
	self.highlight = self.highlight or NewWidget("Texture", self)
	self.highlight.atlas = atlas
end
function Widget:GetNormalTexture()
	return self.normal
end
function Widget:GetPushedTexture()
	return self.pushed
end
function Widget:Click()
	local script = self.scripts.OnClick
	if script then
		Run(script, self, "LeftButton", false)
	end
end

-- Fonts and texts. A text set to a font object follows that object when the game changes it
-- (Text Size swaps the font behind the tracker's objects) until the text is given a font of its
-- own with SetFont.
local function CurrentFont(holder)
	if holder.font then
		return holder.font[1], holder.font[2], holder.font[3]
	end
	if holder.fontObject then
		return CurrentFont(holder.fontObject)
	end
	return "Fonts\\FRIZQT__.TTF", 12, ""
end
function Widget:SetFontObject(font)
	if type(font) == "string" then
		font = assert(_G[font], "no font object " .. font)
	end
	self.fontObject, self.font = font, nil
end
function Widget:GetFontObject()
	return self.fontObject
end
function Widget:SetFont(file, size, flags)
	self.font = { file, size, flags or "" }
	return true
end
function Widget:GetFont()
	return CurrentFont(self)
end
function Widget:SetText(text)
	self.text = text
end
function Widget:GetText()
	return self.text
end
function Widget:SetTextColor(r, g, b, a)
	self.textColor = { r, g, b, a or 1 }
end
function Widget:GetTextColor()
	local color = self.textColor or { 1, 1, 1, 1 }
	return color[1], color[2], color[3], color[4]
end
-- What the player reads: the game's |4singular:plural; picks by the number just before it.
local function Shown(text)
	return (text or ""):gsub("(%d+)(%s*)|4([^:]*):([^;]*);", function(number, between, one, many)
		return number .. between .. (tonumber(number) == 1 and one or many)
	end)
end
-- ASSUMED: a glyph is half as wide as the font's size, and a line as tall as the size. As in
-- the game, a hidden text measures at the font's default size, not its own (seen in game, 0.1.5).
local function TextSize(text)
	local _, size = CurrentFont(text)
	if not text:IsVisible() then
		size = 12
	end
	return size
end
function Widget:GetStringWidth()
	local count = select(2, Shown(self.text):gsub("[^\128-\191]", ""))
	return count * TextSize(self) * 0.5
end
Widget.GetUnboundedStringWidth = Widget.GetStringWidth
function Widget:GetStringHeight()
	if (self.text or "") == "" then
		return 0
	end
	return TextSize(self)
end

-- Animation groups.
function Widget:CreateAnimation(animationType)
	local animation = NewWidget(animationType, self)
	self.animations[#self.animations + 1] = animation
	return animation
end
function Widget:Play()
	self.playing = true
end
function Widget:Stop()
	self.playing = false
end
function Widget:IsPlaying()
	return self.playing == true
end

--------------------------------------------------------------------------------
-- The game.
--------------------------------------------------------------------------------

local function Font(file, size)
	local font = NewWidget("Font")
	font.font = { file, size, "" }
	return font
end

local function NewGame(now)
	game = {
		widgets = {},
		calls = {},
		timers = {},
		events = {},
		chat = {},
		errors = {},
		sounds = {},
		blocked = {}, -- what the game refused the addon in combat (ADDON_ACTION_BLOCKED)
		combat = false,
		now = now,
		time = 1000,
		loggedIn = false,
	}
	debug.sethook() -- a test that failed in combat may have left the hook on

	local stubs = dofile("Tests/game.lua")
	game.InZone, game.WithClock = stubs.InZone, stubs.WithClock
	QUEST_DASH = "- "
	SOUNDKIT = { IG_MAINMENU_OPTION_CHECKBOX_ON = 856 }
	function PlaySound(sound)
		game.sounds[#game.sounds + 1] = sound
	end

	local function Color(r, g, b)
		return {
			r = r, g = g, b = b,
			WrapTextInColorCode = function(_, text)
				return string.format("|cff%02x%02x%02x%s|r", r * 255, g * 255, b * 255, text)
			end,
		}
	end
	NORMAL_FONT_COLOR = Color(1, 0.82, 0)
	HIGHLIGHT_FONT_COLOR = Color(1, 1, 1)
	RED_FONT_COLOR = Color(1, 0.125, 0.125)
	OBJECTIVE_TRACKER_COLOR = {
		Normal = { r = 0.8, g = 0.8, b = 0.8 },
		Complete = { r = 0.6, g = 0.6, b = 0.6 },
	}

	function GetServerTime()
		return game.now
	end
	-- The realm's region. Blizzard's code compares it with "US" and "CN" (wow-ui-source, forever).
	-- ASSUMED: "EU", "KR" and "TW" for the other regions, and "EU" for the user's own (Finland).
	game.region = "EU"
	function GetCurrentRegionName()
		return game.region
	end
	function GetTime()
		return game.time
	end
	C_Timer = {
		After = function(_, callback)
			game.timers[#game.timers + 1] = callback
		end,
	}
	function hooksecurefunc(table, name, hook)
		local original = table[name]
		table[name] = function(...)
			return Run(function(...)
				local a, b, c, d = original(...)
				RunHook(hook, ...)
				return a, b, c, d
			end, ...)
		end
	end
	function InCombatLockdown()
		return game.combat
	end
	function CallErrorHandler(problem)
		game.errors[#game.errors + 1] = problem
	end
	function print(...)
		game.chat[#game.chat + 1] = table.concat({ ... }, " ")
	end

	-- The templates the addon uses, as Blizzard_ObjectiveTracker/Blizzard_ObjectiveTrackerModule.xml
	-- has them; the tracker loads before the addon (## OptionalDeps).
	local TEMPLATES = {
		ObjectiveTrackerModuleMinimizeButtonTemplate = function(button)
			button.smartNavigationIgnored = true
			button:SetSize(16, 16)
			for _, part in ipairs({ { "normal", "ui-questtrackerbutton-secondary-collapse" }, { "pushed", "ui-questtrackerbutton-secondary-collapse-pressed" }, { "highlight", "ui-questtrackerbutton-yellow-highlight" } }) do
				local texture = NewWidget("Texture", button)
				texture:SetAtlas(part[2], true)
				button[part[1]] = texture
			end
		end,
	}
	game.templates = TEMPLATES
	C_XMLUtil = {
		GetTemplateInfo = function(name)
			if game.templates[name] then
				return { type = "Button", width = 16, height = 16 }
			end
		end,
	}
	function CreateFrame(frameType, name, parent, template)
		local frame = NewWidget(frameType, parent)
		frame.name = name
		if template then
			frame.template = template
			assert(game.templates[template], "no such template in the stand-in: " .. template)(frame)
		end
		return frame
	end
	UIParent = NewWidget("Frame")
	UIParent.name = "UIParent"
	UIParent:SetSize(1920, 1080)
	UIParent.rect = { 0, 1080, 1920, 0 }
	-- UIParent is protected through the frames under it: the action bars, PlayerFrame and more
	-- (parent="UIParent" in Blizzard_ActionBar/Mainline/MainActionBar.xml and
	-- Blizzard_UnitFrame/Mainline/PlayerFrame.xml). The stand-in doesn't make those, so it marks
	-- UIParent itself.
	UIParent.protected = true
	-- The objective tracker where Edit Mode's preset layouts put it: 110 in from the right, 275
	-- down (Blizzard_EditMode/Mainline/EditModePresetLayouts.lua), 260 wide.
	ObjectiveTrackerFrame = NewWidget("Frame", UIParent)
	ObjectiveTrackerFrame.rect = { 1550, 805, 1810, 400 }

	-- The tracker: its fonts, a size per Text Size step (Blizzard_ObjectiveTrackerFonts.xml,
	-- roman), the quest section's header (ObjectiveTrackerModuleHeaderTemplate) and SetTextSize.
	for size = 12, 22 do
		_G["ObjectiveTrackerFont" .. size] = Font("Fonts\\FRIZQT__.TTF", size)
	end
	ObjectiveTrackerLineFont = NewWidget("Font")
	ObjectiveTrackerLineFont:SetFontObject("ObjectiveTrackerFont12")
	ObjectiveTrackerHeaderFont = NewWidget("Font")
	ObjectiveTrackerHeaderFont:SetFontObject("ObjectiveTrackerFont14")
	local header = NewWidget("Frame", UIParent)
	header:SetSize(260, 26)
	header.Text = header:CreateFontString()
	header.Text:SetPoint("LEFT", 7, 0)
	header.MinimizeButton = NewWidget("Button", header)
	header.MinimizeButton:SetSize(16, 16)
	QuestObjectiveTracker = { Header = header }
	local minLineFontSize, maxLineFontSize, headerExtraSize = 12, 20, 2
	ObjectiveTrackerManager = {
		UpdateAll = function() end,
	}
	function ObjectiveTrackerManager:SetTextSize(textSize)
		if textSize < minLineFontSize or textSize > maxLineFontSize then
			return
		end
		local lineFont = "ObjectiveTrackerFont" .. textSize
		local headerFont = "ObjectiveTrackerFont" .. (textSize + headerExtraSize)
		ObjectiveTrackerLineFont:SetFontObject(lineFont)
		ObjectiveTrackerHeaderFont:SetFontObject(headerFont)
		self:UpdateAll()
	end

	-- The addon, as the game loads it: its files with one namespace, then its saved data.
	function game:Load(saved)
		ForeverCountdownDB = saved
		local ns = {}
		for _, file in ipairs({ "Countdown.lua", "ForeverCountdown.lua" }) do
			Run(assert(loadfile(file)), "ForeverCountdown", ns)
		end
		self.ns = ns
		self:Fire("ADDON_LOADED", "ForeverCountdown")
		self.loggedIn = true
		self:Fire("PLAYER_LOGIN")
		self.panel = UIParent.children[#UIParent.children]
		return self
	end

	-- Puts a frame somewhere on the screen (see GetLeft), or nowhere.
	function game:Place(frame, rect)
		frame.rect = rect
	end

	function game:Fire(event, ...)
		local list = self.events[event] or {}
		local kept = {}
		for _, handler in ipairs(list) do
			if not RunApart(handler, ...) then
				kept[#kept + 1] = handler
			end
		end
		self.events[event] = kept
	end

	-- Runs a frame's script as the game does when the player acts (OnDragStart and the like).
	function game:RunScript(widget, name, ...)
		local script = widget.scripts[name]
		if script then
			Run(script, widget, ...)
		end
	end

	-- Combat, as the game has it: PLAYER_REGEN_DISABLED, then InCombatLockdown() is true until
	-- combat ends, then PLAYER_REGEN_ENABLED. ASSUMED: the game sends PLAYER_REGEN_DISABLED just
	-- before the lockdown starts and PLAYER_REGEN_ENABLED just after it ends.
	function game:EnterCombat()
		self:Fire("PLAYER_REGEN_DISABLED")
		self.combat = true
		debug.sethook(OnCall, "c")
		return self
	end
	function game:LeaveCombat()
		self.combat = false
		debug.sethook()
		self:Fire("PLAYER_REGEN_ENABLED")
		return self
	end

	-- Frames: the timers set for the next frame run, then OnUpdate for each shown frame.
	function game:Frames(count, seconds)
		local step = (seconds or count / 60) / count
		for _ = 1, count do
			self.time = self.time + step
			self.clock = (self.clock or 0) + step
			self.now = self.now + math.floor(self.clock)
			self.clock = self.clock - math.floor(self.clock)
			local timers = self.timers
			self.timers = {}
			for _, timer in ipairs(timers) do
				Run(timer)
			end
			for _, widget in ipairs(self.widgets) do
				local update = widget.scripts.OnUpdate
				if update and widget:IsVisible() then
					Run(update, widget, step)
				end
			end
		end
		return self
	end

	-- The texts the player can read, with their colors, in the order they were made.
	function game:Texts()
		local texts = {}
		for _, widget in ipairs(self.widgets) do
			if widget.widgetType == "FontString" and widget:IsVisible() and (widget.text or "") ~= "" and widget.layer ~= "BACKGROUND" then
				texts[#texts + 1] = widget
			end
		end
		return texts
	end

	function game:Find(text)
		for _, widget in ipairs(self:Texts()) do
			if Shown(widget.text) == text then
				return widget
			end
		end
	end

	function game:Read()
		local lines = {}
		for _, widget in ipairs(self:Texts()) do
			lines[#lines + 1] = Shown(widget.text)
		end
		return table.concat(lines, " | ")
	end

	return game
end

return NewGame
