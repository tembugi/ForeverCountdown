-- Forever Countdown: a panel in the objective tracker's style that counts down to World of
-- Warcraft Forever's launch, with the beta's end and name reservation on the way. The dates and
-- what each line says are in Countdown.lua.
local ADDON_NAME, ns = ...

-- Keep equal to ## Version in the .toc.
local VERSION = "0.1.8"
ns.VERSION = VERSION
-- The addon's name as the player sees it: the start of chat lines.
local ADDON_TITLE = "Forever Countdown"

local T = ns.TEXT

-- Blizzard's values (ObjectiveTrackerModuleHeaderTemplate and its minimize button), used only
-- when the game's own objects are missing.
local HEADER_WIDTH = 260
local HEADER_HEIGHT = 26
local HEADER_TEXT_X = 7
local HEADER_ART = "UI-QuestTracker-Secondary-Objective-Header"
local COLLAPSE_ART = "UI-QuestTrackerButton-Secondary-Collapse"
local EXPAND_ART = "UI-QuestTrackerButton-Secondary-Expand"
local BUTTON_HIGHLIGHT_ART = "UI-QuestTrackerButton-Yellow-Highlight"
local BUTTON_SIZE = 16
-- The game's quest marker art: "!" for a quest to pick up, "?" for one to hand in.
local QUEST_AVAILABLE_ART = "QuestNormal"
local QUEST_TURN_IN_ART = "QuestTurnin"

-- The panel's own measures, in UI units, from the mockup the user chose (Z9, 2026-10-05).
-- Text sizes are the quest tracker's own (see Build): they follow its Text Size setting.
local ROW_TOP_GAP = 8 -- header to the first milestone
local ROW_GAP = 8 -- between milestones
local LINE_GAP = 2 -- a title to the line under it
local ICON_COLUMN = 20
local ICON_GAP = 6
local CLOCK_GAP = 15 -- "launches" to the clock
local INFINITY_WIDTH = 24
local CLOCK_EXTRA = 3 -- the clock figures' size over the header text's
-- How far a larger text is raised to share a smaller one's baseline, per unit of size difference,
-- for the tracker's font (measured from a screenshot in game, 0.1.7).
local BASELINE_RAISE = 0.27

-- Colors: the tracker's own when it is loaded, else Blizzard's usual values.
local function TrackerColor(key, r, g, b)
	local colors = OBJECTIVE_TRACKER_COLOR
	local color = colors and colors[key]
	if color then
		return color.r, color.g, color.b
	end
	return r, g, b
end
local GOLD = NORMAL_FONT_COLOR
local WHITE = HIGHLIGHT_FONT_COLOR
local GLOW = { 0.67, 0.84, 1 }

-- Every chat line starts with the addon's name in gold. The addon writes to chat only when
-- something stopped working: what stopped, in red, then what the player can do.
local function SayProblem(problem, advice)
	print(NORMAL_FONT_COLOR:WrapTextInColorCode(ADDON_TITLE) .. ": " .. RED_FONT_COLOR:WrapTextInColorCode(problem) .. " " .. advice)
end

local function Font(objectName, fallbackName)
	return _G[objectName] or _G[fallbackName]
end

-- A text in one of the game's fonts. Without a size it keeps the font object itself, so it
-- changes when the game changes that object (the tracker's Text Size setting swaps the font
-- behind ObjectiveTrackerLineFont and ObjectiveTrackerHeaderFont). It has the tracker's shadow.
local function CreateText(parent, fontObject, layer)
	local text = parent:CreateFontString(nil, layer or "ARTWORK")
	text:SetFontObject(fontObject)
	text:SetShadowOffset(1, -1)
	text:SetShadowColor(0, 0, 0, 1)
	text:SetJustifyH("LEFT")
	text:SetWordWrap(false)
	return text
end

-- Drawing ------------------------------------------------------------------------------------

-- The game's round, soft-edged texture (Blizzard uses it as a circle mask). The infinity sign
-- and the quill are drawn as many small overlapping discs of it along their curves: drawn with
-- Line objects they didn't show in game (0.1.0 to 0.1.3), and a square light looked like a
-- rectangle.
local DISC = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local function Disc(frame, layer, sublevel, x, y, size, r, g, b, a)
	local disc = frame:CreateTexture(nil, layer, nil, sublevel)
	disc:SetTexture(DISC)
	disc:SetVertexColor(r, g, b, a or 1)
	disc:SetSize(size, size)
	disc:SetPoint("CENTER", frame, "TOPLEFT", x, -y)
	return disc
end

-- Points along a path, close enough together for discs of the given size to overlap.
local function Along(points, spacing)
	local out = { points[1] }
	for i = 1, #points - 1 do
		local p, q = points[i], points[i + 1]
		local steps = math.max(1, math.ceil(math.sqrt((q[1] - p[1]) ^ 2 + (q[2] - p[2]) ^ 2) / spacing))
		for k = 1, steps do
			out[#out + 1] = { p[1] + (q[1] - p[1]) * k / steps, p[2] + (q[2] - p[2]) * k / steps }
		end
	end
	return out
end

-- The infinity sign as a calligraphic silver ribbon, like the swash of the Forever logo: a
-- lemniscate, thick where it runs across a pen nib held at an angle and thin along it, with a
-- dark edge, and the strand through the crossing drawn again on top so one strand passes over
-- the other. A light runs around it (see Animate). A glow behind it read as a white smudge in
-- game and was dropped (0.1.7).
local INFINITY_STEPS = 120
local NIB = math.rad(-38)
local INFINITY_THIN = 1.1
local INFINITY_THICK = 2.2
local CROSSING_EDGE_TRIM = 5 -- steps at each end of the over strand without an edge, so it joins smoothly
local function CreateInfinity(parent, width)
	local height = width * 60 / 124
	local frame = CreateFrame("Frame", nil, parent)
	frame:SetSize(width, height)
	local ribbon = CreateFrame("Frame", nil, frame)
	ribbon:SetAllPoints()
	local scale = width / 124
	local points = {}
	for i = 0, INFINITY_STEPS do
		local t = 2 * math.pi * i / INFINITY_STEPS
		local d = 1 + math.sin(t) ^ 2
		points[i] = { (62 + 50 * math.cos(t) / d) * scale, (30 + 62.5 * math.sin(t) * math.cos(t) / d) * scale }
	end
	frame.points = points
	local function Width(i)
		local p, q = points[(i - 1) % INFINITY_STEPS], points[(i + 1) % INFINITY_STEPS]
		local angle = math.atan2(q[2] - p[2], q[1] - p[1])
		return INFINITY_THIN + (INFINITY_THICK - INFINITY_THIN) * math.abs(math.sin(angle - NIB))
	end
	local function Silver(f)
		if f < 0.55 then
			local k = f / 0.55
			return 1 - 0.18 * k, 1 - 0.21 * k, 1 - 0.29 * k
		end
		local k = (f - 0.55) / 0.45
		return 0.82 + 0.12 * k, 0.79 + 0.12 * k, 0.71 + 0.14 * k
	end
	local function Pass(target, first, last, layer, sublevel, extra, colorAt)
		for i = first, last - 1 do
			local p = points[i % INFINITY_STEPS]
			local r, g, b = colorAt(p[2] / height)
			Disc(target, layer, sublevel, p[1], p[2], Width(i) + extra, r, g, b)
		end
	end
	local function Edge()
		return 0.23, 0.16, 0.08
	end
	Pass(ribbon, 0, INFINITY_STEPS, "BORDER", 0, 0.9, Edge)
	Pass(ribbon, 0, INFINITY_STEPS, "ARTWORK", 0, 0, Silver)
	-- The strand through the crossing at a quarter of the way round, drawn over the other.
	local overFirst, overLast = math.floor(INFINITY_STEPS * 0.19), math.ceil(INFINITY_STEPS * 0.31)
	Pass(ribbon, overFirst + CROSSING_EDGE_TRIM, overLast - CROSSING_EDGE_TRIM, "OVERLAY", 0, 0.9, Edge)
	Pass(ribbon, overFirst, overLast, "OVERLAY", 1, 0, Silver)
	frame.spark = Disc(ribbon, "OVERLAY", 2, 0, 0, INFINITY_THICK + 1.5, 1, 1, 0.94, 0.9)
	frame.spark:SetBlendMode("ADD")
	return frame
end

-- The quill, drawn in gold: the shaft, the edge of the vane and the nib. It writes a line of
-- ink under itself (see Animate).
local function Bezier(p0, p1, p2, p3, steps)
	local points = {}
	for i = 0, steps do
		local t = i / steps
		local u = 1 - t
		points[#points + 1] = {
			u * u * u * p0[1] + 3 * u * u * t * p1[1] + 3 * u * t * t * p2[1] + t * t * t * p3[1],
			u * u * u * p0[2] + 3 * u * u * t * p1[2] + 3 * u * t * t * p2[2] + t * t * t * p3[2],
		}
	end
	return points
end
local SCRIBBLE = { { 3, 25 }, { 5, 23.5 }, { 8, 24 }, { 10, 23 }, { 13, 24 }, { 15, 23 }, { 18, 24 }, { 20, 23 }, { 22, 24 }, { 25, 23 } }
local QUILL_STROKE = 1.6
local function CreateQuill(parent, size)
	local scale = size / 30
	local frame = CreateFrame("Frame", nil, parent)
	frame:SetSize(size, size)
	local pen = CreateFrame("Frame", nil, frame)
	pen:SetSize(size, size)
	pen:SetPoint("TOPLEFT")
	local r, g, b = GOLD.r, GOLD.g, GOLD.b
	local function Scaled(points, factor)
		local out = {}
		for i, p in ipairs(points) do
			out[i] = { p[1] * factor, p[2] * factor }
		end
		return out
	end
	local function Stroke(target, points, thickness, list)
		for _, p in ipairs(Along(Scaled(points, scale), thickness / 3)) do
			local disc = Disc(target, "ARTWORK", 0, p[1], p[2], thickness, r, g, b)
			if list then
				list[#list + 1] = disc
			end
		end
	end
	Stroke(pen, Bezier({ 25, 3 }, { 16, 4 }, { 10, 11 }, { 7, 20 }, 8), QUILL_STROKE)
	Stroke(pen, Bezier({ 25, 3 }, { 24, 10 }, { 18, 15 }, { 11, 16 }, 8), QUILL_STROKE * 0.8)
	Stroke(pen, { { 7, 20 }, { 5, 24 } }, QUILL_STROKE)
	frame.pen = pen
	frame.ink = {}
	Stroke(frame, SCRIBBLE, QUILL_STROKE * 0.8, frame.ink)
	for _, disc in ipairs(frame.ink) do
		disc:SetAlpha(0)
	end
	return frame
end

-- "Forever" in white, the way the logo has it, with a soft pale-blue glow that rises and fades
-- (see Animate). The game's text outlines are always black, so the glow is the word again in
-- pale blue, a pixel out in each direction, behind it. (A gleam sweeping across the word was
-- tried in 0.1.0 and dropped by the user.)
local GLOW_OFFSETS = { { -1, 0 }, { 1, 0 }, { 0, 1 }, { 0, -1 }, { -1, 1 }, { 1, 1 }, { -1, -1 }, { 1, -1 } }
local function CreateShiningWord(parent, fontObject)
	local word = CreateText(parent, fontObject)
	word:SetText(T.forever)
	word:SetTextColor(WHITE.r, WHITE.g, WHITE.b)
	local glow = {}
	for i, offset in ipairs(GLOW_OFFSETS) do
		local copy = CreateText(parent, fontObject, "BACKGROUND")
		copy:SetText(T.forever)
		copy:SetTextColor(GLOW[1], GLOW[2], GLOW[3])
		copy:SetShadowOffset(0, 0)
		copy:SetPoint("CENTER", word, "CENTER", offset[1], offset[2])
		glow[i] = copy
	end
	return { word = word, glow = glow }
end

-- The countdown: days, hours, minutes and seconds in bold white (the tracker's header font with
-- a black outline, a few sizes larger than the header text, see Relayout), with larger gold
-- colons that stay still. Each pair of figures and each colon is a text of its own that sizes
-- itself to what it shows, and each follows the one before it at the same small gap: the game
-- places them by their drawn size. Widths the addon measured itself came out wrong in game and
-- spread the clock apart (0.1.4, 0.1.6), so nothing is given a width. The larger colons are
-- raised so their dots sit at the middle of the figures. The seconds fade in as they tick
-- (see Animate).
local CLOCK_FLAGS = "OUTLINE"
local CLOCK_GAP_INNER = 1 -- between a pair of figures and a colon
local COLON_EXTRA = 4 -- the colons' size over the figures'
local COLON_RAISE = 0.09 -- how far the colons are raised, as a share of their size
local function CreateClock(parent, fontObject)
	local file = fontObject:GetFont()
	local clock = CreateFrame("Frame", nil, parent)
	local figurePairs, colons = {}, {}
	for i = 1, 4 do
		local pair = CreateText(clock, fontObject)
		pair:SetTextColor(WHITE.r, WHITE.g, WHITE.b)
		figurePairs[i] = pair
		if i < 4 then
			local colon = CreateText(clock, fontObject)
			colon:SetText(":")
			colon:SetTextColor(GOLD.r, GOLD.g, GOLD.b)
			colons[i] = colon
		end
	end
	clock.secondsText = figurePairs[4]
	clock.tickedAt = 0
	function clock:Resize(size)
		local colonSize = size + COLON_EXTRA
		local raise = math.floor(colonSize * COLON_RAISE + 0.5)
		figurePairs[1]:ClearAllPoints()
		figurePairs[1]:SetPoint("LEFT")
		for i, pair in ipairs(figurePairs) do
			pair:SetFont(file, size, CLOCK_FLAGS)
			local colon = colons[i]
			if colon then
				colon:SetFont(file, colonSize, CLOCK_FLAGS)
				colon:ClearAllPoints()
				colon:SetPoint("LEFT", pair, "RIGHT", CLOCK_GAP_INNER, raise)
				local nextPair = figurePairs[i + 1]
				nextPair:ClearAllPoints()
				nextPair:SetPoint("LEFT", colon, "RIGHT", CLOCK_GAP_INNER, -raise)
			end
		end
		-- The frame's own size only feeds the panel's width (FitWidth): the figures at their
		-- widest, the colons and the gaps.
		local width = 0
		for i, pair in ipairs(figurePairs) do
			width = width + math.max(pair:GetStringWidth(), size * 1.2)
			if colons[i] then
				width = width + colons[i]:GetStringWidth() + 2 * CLOCK_GAP_INNER
			end
		end
		self:SetSize(math.ceil(width), colonSize + 4)
	end
	function clock:Set(days, hours, minutes, secs)
		figurePairs[1]:SetText(string.format("%02d", math.min(days, 99)))
		figurePairs[2]:SetText(string.format("%02d", hours))
		figurePairs[3]:SetText(string.format("%02d", minutes))
		figurePairs[4]:SetText(string.format("%02d", secs))
		if secs ~= self.seconds then
			self.seconds = secs
			self.tickedAt = GetTime()
		end
	end
	return clock
end

-- The panel ----------------------------------------------------------------------------------

local panel
local saved
local rows = {}
local shining = {}
local quill, infinity, turnInMarker, turnInWiggle
local headerFont, lineFont -- the tracker's own font objects
local launchRest -- "launches" after the shining "Forever" in the launch row
local launchWordText -- "Forever" in the launch row
local titleWidthTexts -- the header's "Countdown to" and "Forever"
local fullClock, miniClock

-- The panel is at least as wide as a tracker section, and wide enough for its longest line:
-- "Forever launches" with the clock beside it, or the minimized header ("Countdown to Forever",
-- the clock and the button). The width is the same open and minimized (the user asked, 0.1.1).
local RIGHT_MARGIN = 8
local function FitWidth()
	local launchLine = HEADER_TEXT_X + ICON_COLUMN + ICON_GAP + launchWordText:GetStringWidth() + 4
		+ launchRest:GetStringWidth() + CLOCK_GAP + fullClock:GetWidth() + RIGHT_MARGIN
	local miniLine = HEADER_TEXT_X + titleWidthTexts[1]:GetStringWidth() + 4 + titleWidthTexts[2]:GetStringWidth() + 8
		+ miniClock:GetWidth() + BUTTON_SIZE + RIGHT_MARGIN
	panel:SetWidth(math.ceil(math.max(HEADER_WIDTH, launchLine, miniLine)))
end

local function SavePosition()
	local left, top = panel:GetLeft(), panel:GetTop()
	if not left or not top then
		return
	end
	saved.position = { point = "TOPLEFT", x = left, y = top - UIParent:GetHeight() }
end

local function PlacePanel()
	panel:ClearAllPoints()
	if saved.position then
		panel:SetPoint(saved.position.point, UIParent, saved.position.point, saved.position.x, saved.position.y)
	elseif MinimapCluster then
		panel:SetPoint("TOPRIGHT", MinimapCluster, "TOPLEFT", -12, -8)
	else
		panel:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -260, -20)
	end
end

-- A milestone: a marker on the left, a title in gold and a line under it, as a quest shows in
-- the tracker; greyed once it is behind. The titles use the game's bright gold (the tracker's
-- highlight color): its resting header gold read too dim in game (the user, 0.1.1).
-- Each milestone sits under the one above it, so the rows follow the text's height.
local function CreateRow(parent, above)
	local row = CreateFrame("Frame", nil, parent)
	row:SetAllPoints()
	row.title = CreateText(row, lineFont)
	if above then
		row.title:SetPoint("TOPLEFT", above.line, "BOTTOMLEFT", 0, -ROW_GAP)
	else
		row.title:SetPoint("TOPLEFT", HEADER_TEXT_X + ICON_COLUMN + ICON_GAP, -HEADER_HEIGHT - ROW_TOP_GAP)
	end
	row.line = CreateText(row, lineFont)
	row.line:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -LINE_GAP)
	row.icon = CreateFrame("Frame", nil, row)
	row.icon:SetSize(ICON_COLUMN, ICON_COLUMN)
	row.icon:SetPoint("CENTER", row.title, "LEFT", -ICON_GAP - ICON_COLUMN / 2, 0)
	return row
end

local function SetRow(row, title, line, done)
	row.title:SetText(title)
	row.line:SetText(QUEST_DASH .. line)
	if done then
		row.title:SetTextColor(TrackerColor("Complete", 0.6, 0.6, 0.6))
		row.line:SetTextColor(TrackerColor("Complete", 0.6, 0.6, 0.6))
	else
		row.title:SetTextColor(GOLD.r, GOLD.g, GOLD.b)
		row.line:SetTextColor(TrackerColor("Normal", 0.8, 0.8, 0.8))
	end
end

local function Marker(row, atlas, size, greyed)
	local marker = row.icon:CreateTexture(nil, "ARTWORK")
	marker:SetAtlas(atlas)
	marker:SetSize(size, size)
	marker:SetPoint("CENTER")
	if greyed then
		marker:SetDesaturated(true)
		marker:SetVertexColor(0.75, 0.75, 0.75)
	end
	return marker
end

local function Refresh()
	local now = GetServerTime()
	local lines = ns.Lines(now)
	SetRow(rows[1], lines.betaBegan.title, lines.betaBegan.line, true)
	SetRow(rows[2], lines.betaEnds.title, lines.betaEnds.line, lines.betaEnds.done)
	SetRow(rows[3], lines.reservation.title, lines.reservation.line, lines.reservation.done)
	turnInMarker:SetDesaturated(lines.betaEnds.done)
	if lines.betaEnds.done then
		turnInWiggle:Stop()
	elseif not turnInWiggle:IsPlaying() then
		turnInWiggle:Play()
	end
	local launchRow = rows[4]
	launchRow.line:SetText(QUEST_DASH .. ns.LaunchText(GetCVarBool("timeMgrUseMilitaryTime")))
	local days, hours, minutes, seconds = ns.ClockParts(now)
	if days then
		launchRest:SetText(T.launches)
		fullClock:Set(days, hours, minutes, seconds)
		miniClock:Set(days, hours, minutes, seconds)
		fullClock:Show()
		miniClock:Show()
	else
		launchRest:SetText(T.launched)
		fullClock:Hide()
		miniClock:Hide()
	end
end

local function SetMinimized(minimized)
	saved.minimized = minimized
	panel.body:SetAlpha(minimized and 0 or 1)
	panel.mini:SetAlpha(minimized and 1 or 0)
	local art = minimized and EXPAND_ART or COLLAPSE_ART
	panel.button:GetNormalTexture():SetAtlas(art)
	panel.button:GetPushedTexture():SetAtlas(art .. "-Pressed")
	panel:SetHeight(minimized and HEADER_HEIGHT or panel.openHeight or HEADER_HEIGHT)
end

-- Animation ----------------------------------------------------------------------------------

-- One driver for every moving part, run each frame while the panel is shown (the game skips
-- OnUpdate for hidden frames): the texts once a second, the seconds' tick, the quill writing, the light around the infinity sign and the
-- glow of "Forever".
local QUILL_PERIOD = 2.4
-- Where the pen is over one writing stroke: share of the period, then x right and y up, in UI
-- units from its rest position.
local PEN_PATH = { { 0, -1, 0 }, { 0.1, 0.5, 1 }, { 0.2, 2, 0 }, { 0.3, 3.5, 1 }, { 0.4, 5, 0 }, { 0.55, 7, 0.5 }, { 0.7, 7, 3 }, { 1, -1, 0 } }
local TRACE_PERIOD = 4
local GLOW_PERIOD = 3.6
local GLOW_STRENGTH = 0.35 -- the glow at its brightest, softened in 0.1.5 (it blurred "Forever")

local lastSecond
local function Animate()
	local second = GetServerTime()
	if second ~= lastSecond then
		lastSecond = second
		Refresh()
	end
	local time = GetTime()
	-- The seconds fade in as they change.
	for _, clock in ipairs({ fullClock, miniClock }) do
		local fade = math.min(1, (time - clock.tickedAt) / 0.35)
		clock.secondsText:SetAlpha(0.3 + 0.7 * fade)
	end
	-- "Forever": the glow rises and fades.
	local glowAlpha = 0.25 + 0.35 * (0.5 - 0.5 * math.cos(2 * math.pi * (time % GLOW_PERIOD) / GLOW_PERIOD))
	for _, shine in ipairs(shining) do
		if shine.word:IsVisible() then
			for _, copy in ipairs(shine.glow) do
				copy:SetAlpha(glowAlpha * GLOW_STRENGTH)
			end
		end
	end
	if saved.minimized then
		return
	end
	-- The quill writes a line, lifts, and the ink fades before the next one.
	local phase = (time % QUILL_PERIOD) / QUILL_PERIOD
	for i = 1, #PEN_PATH - 1 do
		local a, b = PEN_PATH[i], PEN_PATH[i + 1]
		if phase <= b[1] then
			local k = (phase - a[1]) / (b[1] - a[1])
			quill.pen:SetPoint("TOPLEFT", a[2] + (b[2] - a[2]) * k, a[3] + (b[3] - a[3]) * k)
			break
		end
	end
	local written = math.min(1, phase / 0.55) * #quill.ink
	local inkAlpha = phase < 0.8 and 1 or math.max(0, 1 - (phase - 0.8) / 0.2)
	for i, ink in ipairs(quill.ink) do
		ink:SetAlpha(i <= written and inkAlpha or 0)
	end
	-- A light runs around the infinity sign.
	local points = infinity.points
	local position = (time % TRACE_PERIOD) / TRACE_PERIOD * INFINITY_STEPS
	local index = math.floor(position)
	local p, q = points[index], points[(index + 1) % INFINITY_STEPS]
	local k = position - index
	infinity.spark:SetPoint("CENTER", infinity, "TOPLEFT", p[1] + (q[1] - p[1]) * k, -(p[2] + (q[2] - p[2]) * k))
end

local stopped = false
local function SafeAnimate()
	if stopped then
		return
	end
	if not xpcall(Animate, CallErrorHandler) then
		stopped = true
		panel:SetScript("OnUpdate", nil)
		SayProblem("the countdown stopped.", "Type /reload to start it again.")
	end
end

-- The "?" wiggles from side to side on its base, then rests: a quest waiting to be handed in,
-- asking for attention. Built in plain Lua (an animation group made from an XML template gets
-- no mixin in Forever).
local WIGGLE = { -18, 34, -30, 24, -16, 6 } -- degrees, each from where the last one ended
local WIGGLE_STEP = 0.06
local WIGGLE_REST = 2.6
local function CreateWiggle(texture)
	local group = texture:CreateAnimationGroup()
	group:SetLooping("REPEAT")
	for i, degrees in ipairs(WIGGLE) do
		local turn = group:CreateAnimation("Rotation")
		turn:SetDegrees(degrees)
		turn:SetDuration(WIGGLE_STEP)
		turn:SetOrigin("BOTTOM", 0, 0)
		turn:SetOrder(i)
		if i == 1 then
			turn:SetStartDelay(WIGGLE_REST)
		end
	end
	return group
end

-- Sizes that follow the tracker's text: the clocks are as tall as its header text, the panel
-- as wide as its longest line and as tall as its rows. Runs once built and again whenever the
-- tracker's Text Size setting changes.
local function Relayout()
	local headerSize = select(2, headerFont:GetFont())
	local lineSize = select(2, lineFont:GetFont())
	local clockSize = headerSize + CLOCK_EXTRA
	fullClock:Resize(clockSize)
	miniClock:Resize(clockSize)
	-- The clock is larger than the text beside it; centered on it, its figures stood lower than
	-- the text's baseline (0.1.7). Raised by a share of the size difference, the baselines meet.
	fullClock:ClearAllPoints()
	fullClock:SetPoint("LEFT", launchRest, "RIGHT", CLOCK_GAP, (clockSize - lineSize) * BASELINE_RAISE)
	miniClock:ClearAllPoints()
	miniClock:SetPoint("LEFT", titleWidthTexts[2], "RIGHT", 8, (clockSize - headerSize) * BASELINE_RAISE)
	FitWidth()
	local height = HEADER_HEIGHT + ROW_TOP_GAP
	for i, row in ipairs(rows) do
		local titleHeight = row.title:GetStringHeight()
		if i == 4 then
			titleHeight = math.max(launchWordText:GetStringHeight(), fullClock:GetHeight())
		end
		height = height + titleHeight + LINE_GAP + row.line:GetStringHeight() + (i < #rows and ROW_GAP or 4)
	end
	panel.openHeight = math.ceil(height)
	SetMinimized(saved.minimized)
end

local function SafeRelayout()
	if stopped then
		return
	end
	if not xpcall(Relayout, CallErrorHandler) then
		stopped = true
		panel:SetScript("OnUpdate", nil)
		SayProblem("the countdown stopped.", "Type /reload to start it again.")
	end
end

local function Build()
	headerFont = Font("ObjectiveTrackerHeaderFont", "GameFontNormalMed2")
	lineFont = Font("ObjectiveTrackerLineFont", "GameFontHighlight")

	panel = CreateFrame("Frame", nil, UIParent)
	panel:SetSize(HEADER_WIDTH, HEADER_HEIGHT)
	panel:SetMovable(true)
	panel:SetClampedToScreen(true)
	panel:SetDontSavePosition(true)
	PlacePanel()

	-- The header, as the tracker draws a section's: its art, the title, the minimize button.
	local header = CreateFrame("Frame", nil, panel)
	header:SetPoint("TOPLEFT")
	header:SetPoint("TOPRIGHT")
	header:SetHeight(HEADER_HEIGHT)
	header:EnableMouse(true)
	header:RegisterForDrag("LeftButton")
	header:SetScript("OnDragStart", function()
		panel:StartMoving()
	end)
	header:SetScript("OnDragStop", function()
		panel:StopMovingOrSizing()
		SavePosition()
		-- Anchor by the top left again, so minimizing keeps the header where it was dropped.
		PlacePanel()
	end)
	local art = header:CreateTexture(nil, "BACKGROUND")
	art:SetAtlas(HEADER_ART, true)
	art:SetPoint("CENTER")

	-- "Countdown to" in gold, then the shining "Forever", in the tracker's header font. It stays
	-- when minimized (the user asked, 0.1.3).
	local full = CreateFrame("Frame", nil, header)
	full:SetAllPoints()
	local countdownTo = CreateText(full, headerFont)
	countdownTo:SetText(T.countdownTo)
	countdownTo:SetTextColor(GOLD.r, GOLD.g, GOLD.b)
	countdownTo:SetPoint("LEFT", HEADER_TEXT_X, 0)
	local fullWord = CreateShiningWord(full, headerFont)
	fullWord.word:SetPoint("LEFT", countdownTo, "RIGHT", 4, 0)
	shining[#shining + 1] = fullWord
	titleWidthTexts = { countdownTo, fullWord.word }

	-- Minimized, the clock follows the title.
	local mini = CreateFrame("Frame", nil, header)
	mini:SetAllPoints()
	miniClock = CreateClock(mini, headerFont)
	panel.mini = mini

	local button = CreateFrame("Button", nil, header)
	button:SetSize(BUTTON_SIZE, BUTTON_SIZE)
	button:SetPoint("RIGHT", 1, 0)
	button:SetNormalAtlas(COLLAPSE_ART)
	button:SetPushedAtlas(COLLAPSE_ART .. "-Pressed")
	button:SetHighlightAtlas(BUTTON_HIGHLIGHT_ART, "ADD")
	button:SetScript("OnClick", function()
		SetMinimized(not saved.minimized)
	end)
	panel.button = button

	-- The milestones, in the tracker's line font.
	local body = CreateFrame("Frame", nil, panel)
	body:SetAllPoints()
	panel.body = body
	for i = 1, 4 do
		rows[i] = CreateRow(body, rows[i - 1])
	end
	Marker(rows[1], QUEST_AVAILABLE_ART, 20, true)
	turnInMarker = Marker(rows[2], QUEST_TURN_IN_ART, 16)
	turnInWiggle = CreateWiggle(turnInMarker)
	quill = CreateQuill(rows[3].icon, 15)
	quill:SetPoint("CENTER", 0, 1)

	-- "Forever launches", with the clock beside it. Its title is two texts, the shining
	-- "Forever" and "launches", so the row's own title stays empty.
	local launchRow = rows[4]
	local launchWord = CreateShiningWord(launchRow, lineFont)
	launchWord.word:SetPoint("TOPLEFT", launchRow.title)
	shining[#shining + 1] = launchWord
	launchWordText = launchWord.word
	launchRest = CreateText(launchRow, lineFont)
	launchRest:SetTextColor(GOLD.r, GOLD.g, GOLD.b)
	launchRest:SetPoint("LEFT", launchWord.word, "RIGHT", 4, 0)
	fullClock = CreateClock(launchRow, headerFont)
	launchRow.line:ClearAllPoints()
	launchRow.line:SetPoint("TOPLEFT", launchWord.word, "BOTTOMLEFT", 0, -LINE_GAP)
	launchRow.icon:ClearAllPoints()
	launchRow.icon:SetPoint("CENTER", launchWord.word, "LEFT", -ICON_GAP - ICON_COLUMN / 2, 0)
	infinity = CreateInfinity(launchRow.icon, INFINITY_WIDTH)
	infinity:SetPoint("CENTER")

	Refresh()
	Relayout()
	-- Measure again on the next frame, once the game has laid the new texts out.
	C_Timer.After(0, SafeRelayout)
	if ObjectiveTrackerManager and ObjectiveTrackerManager.SetTextSize then
		hooksecurefunc(ObjectiveTrackerManager, "SetTextSize", function()
			-- The game has swapped the fonts; measure them on the next frame.
			C_Timer.After(0, SafeRelayout)
		end)
	end
	panel:SetScript("OnUpdate", SafeAnimate)
end

EventUtil.ContinueOnAddOnLoaded(ADDON_NAME, function()
	ForeverCountdownDB = ns.NormalizeSaved(ForeverCountdownDB)
	saved = ForeverCountdownDB
	if IsLoggedIn() then
		Build()
	else
		EventUtil.RegisterOnceFrameEventAndCallback("PLAYER_LOGIN", Build)
	end
end)
