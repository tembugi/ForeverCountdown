-- A stand-in for the game around ForeverCountdown.lua: UIParent, the minimap, the objective
-- tracker's fonts, header and Text Size setting, timers and the clock, so Tests/run.lua can run
-- the panel frame by frame, across the launch too, without the game.
-- `local NewGame = dofile("Tests/standin.lua")`, then `local game = NewGame(now)` for each test.
--
-- Blizzard's code below copies wow-ui-source (forever, 1.60.1), cut to what the addon touches:
--   Blizzard_ObjectiveTracker: Blizzard_ObjectiveTrackerFonts.xml, Blizzard_ObjectiveTrackerManager.lua
--     (SetTextSize), Blizzard_ObjectiveTrackerShared.lua (OBJECTIVE_TRACKER_COLOR) and
--     Blizzard_ObjectiveTrackerModule.xml (the section header's sizes)
--   Blizzard_SharedXML: EventUtil.lua; Blizzard_SharedXML/Mainline/SoundKitConstants.lua
-- The widgets have only the methods Forever's widgets have (Tests/WidgetAPI.lua). What the
-- stand-in assumes beyond the game's code is marked ASSUMED: a stand-in that behaves better
-- than the game hides bugs.

-- This file runs under luajit, outside the game, and uses standard Lua's dofile and loadfile.
-- It plays the game, so it sets the game's globals.
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
		return function(self, ...)
			game.calls[key] = (game.calls[key] or 0) + 1
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
-- ASSUMED: the panel stays where it was put; only dragging (not tested) reads these.
function Widget:GetLeft()
	return 0
end
function Widget:GetTop()
	return 0
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
function Widget:SetAtlas(atlas)
	self.atlas = atlas
	return true
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
		script(self, "LeftButton", false)
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
		now = now,
		time = 1000,
		loggedIn = false,
	}

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
			local a, b, c, d = original(...)
			hook(...)
			return a, b, c, d
		end
	end
	function CallErrorHandler(problem)
		game.errors[#game.errors + 1] = problem
	end
	function print(...)
		game.chat[#game.chat + 1] = table.concat({ ... }, " ")
	end

	-- EventUtil, as Blizzard_SharedXML/EventUtil.lua has it.
	function IsLoggedIn()
		return game.loggedIn
	end
	C_AddOns = {
		IsAddOnLoaded = function(name)
			return game.loaded == name, game.loaded == name
		end,
	}
	EventUtil = {}
	function EventUtil.RegisterOnceFrameEventAndCallback(event, callback, ...)
		local required = { ... }
		local list = game.events[event] or {}
		game.events[event] = list
		list[#list + 1] = function(...)
			for i, value in ipairs(required) do
				if select(i, ...) ~= value then
					return false
				end
			end
			callback(...)
			return true
		end
	end
	function EventUtil.ContinueOnAddOnLoaded(name, callback)
		local _, isLoaded = C_AddOns.IsAddOnLoaded(name)
		if isLoaded then
			callback()
			return
		end
		EventUtil.RegisterOnceFrameEventAndCallback("ADDON_LOADED", callback, name)
	end
	function EventUtil.ContinueOnPlayerLogin(callback)
		if IsLoggedIn() then
			callback()
			return
		end
		EventUtil.RegisterOnceFrameEventAndCallback("PLAYER_LOGIN", callback)
	end

	function CreateFrame(frameType, _, parent, template)
		assert(template == nil, "the stand-in has no templates")
		return NewWidget(frameType, parent)
	end
	UIParent = NewWidget("Frame")
	UIParent:SetSize(1920, 1080)
	MinimapCluster = NewWidget("Frame", UIParent)
	MinimapCluster:SetSize(256, 256)

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
			assert(loadfile(file))("ForeverCountdown", ns)
		end
		self.ns = ns
		self.loaded = "ForeverCountdown"
		self:Fire("ADDON_LOADED", "ForeverCountdown")
		self.loggedIn = true
		self:Fire("PLAYER_LOGIN")
		self.panel = UIParent.children[#UIParent.children]
		return self
	end

	function game:Fire(event, ...)
		local list = self.events[event] or {}
		local kept = {}
		for _, handler in ipairs(list) do
			if not handler(...) then
				kept[#kept + 1] = handler
			end
		end
		self.events[event] = kept
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
				timer()
			end
			for _, widget in ipairs(self.widgets) do
				local update = widget.scripts.OnUpdate
				if update and widget:IsVisible() then
					update(widget, step)
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
