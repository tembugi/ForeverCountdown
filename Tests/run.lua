-- Runs every test of the rules in Countdown.lua: `luajit Tests/run.lua` in the addon folder.
-- Exits non-zero when a test fails.

-- This file runs under luajit, outside the game, and uses standard Lua's loadfile and os,
-- which the game doesn't have.
---@diagnostic disable: undefined-global, lowercase-global

-- The stand-in for the game takes over print for the addon's chat lines; the tests write with this.
local print = print

local stubs = dofile("Tests/game.lua")
local InZone, WithClock = stubs.InZone, stubs.WithClock

local ns = {}
assert(loadfile("Countdown.lua"))("ForeverCountdown", ns)

local DAY, HOUR = 86400, 3600
local failures = 0

local function Test(name, func)
	local ok, problem = pcall(func)
	if ok then
		print("ok    " .. name)
	else
		failures = failures + 1
		print("FAIL  " .. name .. ": " .. tostring(problem))
	end
end

local function Equal(actual, expected, what)
	if actual ~= expected then
		error(string.format("%s: expected %s, got %s", what, tostring(expected), tostring(actual)), 2)
	end
end

-- A moment in UTC, from its calendar date and time, worked out with os.date (which reads a
-- moment back into a UTC date) rather than with the addon's own CivilDay.
local MONTH_START = { 0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334 }
local function Utc(year, month, day, hour, minute)
	local rough = (year - 1970) * 365 + math.floor((year - 1969) / 4) + MONTH_START[month] + day - 1
	for days = rough - 3, rough + 3 do
		local t = os.date("!*t", days * DAY)
		if t.year == year and t.month == month and t.day == day then
			return days * DAY + (hour or 0) * HOUR + (minute or 0) * 60
		end
	end
	error("no such date")
end

Test("CivilDay gives each date back through os.date", function()
	for _, d in ipairs({ { 1970, 1, 1 }, { 2000, 2, 29 }, { 2000, 3, 1 }, { 2024, 12, 31 }, { 2026, 9, 17 }, { 2026, 10, 21 }, { 2026, 11, 4 }, { 2100, 3, 1 } }) do
		local t = os.date("!*t", ns.CivilDay(d[1], d[2], d[3]) * DAY)
		Equal(string.format("%d-%d-%d", t.year, t.month, t.day), string.format("%d-%d-%d", d[1], d[2], d[3]), "date")
		Equal(t.hour, 0, "midnight")
	end
end)

Test("the launch is November 4, 2026, 15:00 PST, which is 23:00 UTC", function()
	Equal(ns.LAUNCH, Utc(2026, 11, 4, 23), "launch")
end)

Test("a moment's day is the player's own, in any time zone", function()
	InZone(3, function()
		Equal(ns.LocalDay(Utc(2026, 10, 20, 20, 59)), ns.CivilDay(2026, 10, 20), "UTC+3, 23:59 on Oct 20")
		Equal(ns.LocalDay(Utc(2026, 10, 20, 21, 0)), ns.CivilDay(2026, 10, 21), "UTC+3, midnight starting Oct 21")
	end)
	InZone(-7, function()
		Equal(ns.LocalDay(Utc(2026, 10, 21, 6, 59)), ns.CivilDay(2026, 10, 20), "UTC-7, 23:59 on Oct 20")
		Equal(ns.LocalDay(Utc(2026, 10, 21, 7, 0)), ns.CivilDay(2026, 10, 21), "UTC-7, midnight starting Oct 21")
	end)
	InZone(9, function()
		Equal(ns.LocalDay(Utc(2026, 10, 20, 15, 0)), ns.CivilDay(2026, 10, 21), "UTC+9, midnight starting Oct 21")
	end)
end)

Test("a day's line says in how many days, Today on the day, and how many days ago once it has passed", function()
	local beta = ns.BETA_END
	InZone(3, function()
		Equal(ns.DayLine(beta, Utc(2026, 10, 4, 12)), "October 21 · in " .. D_DAYS:format(17), "17 days before")
		Equal(ns.DayLine(beta, Utc(2026, 10, 20, 20, 59)), "October 21 · in " .. D_DAYS:format(1), "the last minute before, local")
		Equal(ns.DayLine(beta, Utc(2026, 10, 20, 21, 0)), "October 21 · Today", "the day's first minute, local")
		Equal(ns.DayLine(beta, Utc(2026, 10, 21, 20, 59)), "October 21 · Today", "the day's last minute, local")
		Equal(ns.DayLine(beta, Utc(2026, 10, 21, 21, 0)), "October 21 · " .. D_DAYS:format(1) .. " ago", "the day after")
		Equal(ns.DayLine(beta, Utc(2026, 10, 31, 12)), "October 21 · " .. D_DAYS:format(10) .. " ago", "ten days after")
	end)
end)

Test("the announced date says Today all over the world on that date", function()
	for _, hours in ipairs({ -10, -8, -7, -5, 0, 1, 2, 3, 5.5, 8, 9, 10, 12, 13 }) do
		InZone(hours, function()
			-- Noon on October 21 where the player is.
			local noon = Utc(2026, 10, 21, 12) - hours * 3600
			Equal(ns.DayLine(ns.BETA_END, noon), "October 21 · Today", "UTC" .. (hours >= 0 and "+" or "") .. hours)
		end)
	end
end)

-- The tests below run in UTC unless they say otherwise.
Test("the beta's line turns to Beta ended, greyed, the day after its last day", function()
	local lines = ns.Lines(Utc(2026, 10, 21, 12))
	Equal(lines.betaEnds.title, "Beta ends", "on the last day")
	Equal(lines.betaEnds.done, false, "not done on the last day")
	lines = ns.Lines(Utc(2026, 10, 22, 12))
	Equal(lines.betaEnds.title, "Beta ended", "the day after")
	Equal(lines.betaEnds.done, true, "done the day after")
	Equal(lines.betaBegan.done, true, "beta began is always done")
	Equal(lines.betaBegan.line, "September 17 · " .. D_DAYS:format(35) .. " ago", "beta began, 35 days ago")
	Equal(ns.Lines(Utc(2026, 10, 5, 12)).betaBegan.line, "September 17 · " .. D_DAYS:format(18) .. " ago", "beta began, 18 days ago")
end)

Test("name reservation: starts until October 27 (Today on the day), then ends with November 3", function()
	local lines = ns.Lines(Utc(2026, 10, 26, 12))
	Equal(lines.reservation.title, "Name reservation starts", "the day before")
	Equal(lines.reservation.line, "October 27 · in " .. D_DAYS:format(1), "the day before")
	lines = ns.Lines(Utc(2026, 10, 27, 12))
	Equal(lines.reservation.title, "Name reservation starts", "the first day")
	Equal(lines.reservation.line, "October 27 · Today", "the first day")
	lines = ns.Lines(Utc(2026, 10, 28, 12))
	Equal(lines.reservation.title, "Name reservation ends", "the second day")
	Equal(lines.reservation.line, "November 3 · in " .. D_DAYS:format(6), "the second day")
	lines = ns.Lines(Utc(2026, 11, 3, 20))
	Equal(lines.reservation.line, "November 3 · Today", "the last day")
	Equal(lines.reservation.done, false, "not done on the last day")
	lines = ns.Lines(Utc(2026, 11, 4, 9))
	Equal(lines.reservation.title, "Name reservation ended", "the day after")
	Equal(lines.reservation.line, "November 3 · " .. D_DAYS:format(1) .. " ago", "the day after")
	Equal(lines.reservation.done, true, "done the day after")
end)

Test("the clock counts days, hours, minutes and seconds to the launch, then stays at zeros", function()
	local left = 31 * DAY + 2 * HOUR + 3 * 60 + 4
	local d, h, m, s = ns.ClockParts(ns.LAUNCH - left)
	Equal(string.format("%d %d %d %d", d, h, m, s), "31 2 3 4", "31 days 2:03:04 before")
	d, h, m, s = ns.ClockParts(ns.LAUNCH - 1)
	Equal(string.format("%d %d %d %d", d, h, m, s), "0 0 0 1", "one second before")
	for _, after in ipairs({ 0, 60, 30 * DAY }) do
		d, h, m, s = ns.ClockParts(ns.LAUNCH + after)
		Equal(string.format("%d %d %d %d", d, h, m, s), "0 0 0 0", after .. " seconds after launch")
	end
	Equal(ns.Lines(ns.LAUNCH - 1).launched, false, "not launched a second before")
	Equal(ns.Lines(ns.LAUNCH).launched, true, "launched at launch")
end)

Test("the launch line: the moment before, then the launch's own date and how many days ago", function()
	InZone(2, function()
		local lines = ns.Lines(ns.LAUNCH - 1)
		Equal(lines.launch.title, "launches", "Helsinki, a second before")
		Equal(lines.launch.line, ns.LaunchText(), "Helsinki, a second before")
		Equal(lines.launch.done, false, "not done before")
		lines = ns.Lines(ns.LAUNCH)
		Equal(lines.launch.title, "launched", "Helsinki, at launch")
		-- 01:00 on November 5 in Helsinki: the launch is today there, on the 5th.
		Equal(lines.launch.line, "November 5 · Today", "Helsinki, at launch")
		Equal(lines.launch.done, true, "done at launch")
		Equal(ns.Lines(Utc(2026, 11, 6, 22)).launch.line, "November 5 · " .. D_DAYS:format(2) .. " ago", "Helsinki, two days later")
	end)
	InZone(-8, function()
		Equal(ns.Lines(ns.LAUNCH + 3600).launch.line, "November 4 · Today", "California, an hour after")
		Equal(ns.Lines(ns.LAUNCH + 9 * 3600).launch.line, "November 4 · " .. D_DAYS:format(1) .. " ago", "California, the next morning")
	end)
end)

Test("after the launch every milestone is behind", function()
	local lines = ns.Lines(ns.LAUNCH + 2 * DAY)
	for _, key in ipairs({ "betaBegan", "betaEnds", "reservation", "launch" }) do
		Equal(lines[key].done, true, key)
	end
	Equal(lines.betaEnds.title, "Beta ended", "beta")
	Equal(lines.reservation.title, "Name reservation ended", "reservation")
end)

Test("a moment reads as the game writes a date and a time, with its 24-hour or 12-hour clock", function()
	local t = { year = 2026, month = 11, day = 5, wday = 5, hour = 1, min = 0 }
	WithClock(true, function()
		Equal(ns.FormatMoment(t), "Thursday, November 5 2026, 01:00", "24-hour")
	end)
	Equal(ns.FormatMoment(t), "Thursday, November 5 2026, 1:00 AM", "12-hour, 1 at night")
	t.hour = 0
	Equal(ns.FormatMoment(t), "Thursday, November 5 2026, 12:00 AM", "12-hour, midnight")
	t.hour = 12
	Equal(ns.FormatMoment(t), "Thursday, November 5 2026, 12:00 PM", "12-hour, noon")
	t.hour, t.min, t.wday, t.day = 15, 5, 4, 4
	Equal(ns.FormatMoment(t), "Wednesday, November 4 2026, 3:05 PM", "12-hour, afternoon")
	WithClock(true, function()
		Equal(ns.FormatMoment(t), "Wednesday, November 4 2026, 15:05", "24-hour, afternoon")
	end)
end)

Test("the launch reads in the player's own time zone", function()
	-- November 4 at 15:00 PST is 23:00 UTC: Helsinki (UTC+2 in November) sees 01:00 on Thursday,
	-- California (UTC-8) 15:00 on Wednesday, New York (UTC-5) 18:00, Tokyo (UTC+9) 08:00 Thursday.
	InZone(2, function()
		WithClock(true, function()
			Equal(ns.LaunchText(), "Thursday, November 5 2026, 01:00", "Helsinki, 24-hour")
		end)
		Equal(ns.LaunchText(), "Thursday, November 5 2026, 1:00 AM", "Helsinki, 12-hour")
	end)
	InZone(-8, function()
		WithClock(true, function()
			Equal(ns.LaunchText(), "Wednesday, November 4 2026, 15:00", "California, 24-hour")
		end)
		Equal(ns.LaunchText(), "Wednesday, November 4 2026, 3:00 PM", "California, 12-hour")
	end)
	InZone(-5, function()
		Equal(ns.LaunchText(), "Wednesday, November 4 2026, 6:00 PM", "New York")
	end)
	InZone(9, function()
		WithClock(true, function()
			Equal(ns.LaunchText(), "Thursday, November 5 2026, 08:00", "Tokyo")
		end)
	end)
end)

Test("the clock counts to the same moment in every time zone", function()
	local now = Utc(2026, 10, 5, 12)
	local expected
	for _, hours in ipairs({ -8, 0, 2, 9 }) do
		InZone(hours, function()
			local d, h, m, sec = ns.ClockParts(now)
			local text = string.format("%d %d %d %d", d, h, m, sec)
			expected = expected or text
			Equal(text, expected, "UTC" .. hours)
		end)
	end
	Equal(expected, "30 11 0 0", "30 days and 11 hours before")
end)

Test("NormalizeSaved starts fresh from nothing, another format or something broken", function()
	for what, old in pairs({ ["nothing"] = false, ["a number"] = 5, ["another format"] = { format = 99, minimized = true }, ["no format"] = { minimized = true } }) do
		local clean = ns.NormalizeSaved(old or nil)
		Equal(clean.format, ns.SAVE_FORMAT, what .. ": format")
		Equal(clean.minimized, false, what .. ": minimized")
		Equal(clean.position, nil, what .. ": position")
	end
end)

Test("NormalizeSaved keeps valid data and drops leftovers", function()
	local clean = ns.NormalizeSaved({ format = ns.SAVE_FORMAT, minimized = true, position = { point = "TOPLEFT", x = 812.5, y = -140, extra = 1 }, oldField = "x" })
	Equal(clean.minimized, true, "minimized")
	Equal(clean.position.point, "TOPLEFT", "point")
	Equal(clean.position.x, 812.5, "x")
	Equal(clean.position.y, -140, "y")
	Equal(clean.position.extra, nil, "a leftover inside the position")
	Equal(clean.oldField, nil, "a leftover field")
end)

Test("NormalizeSaved drops broken entries", function()
	local broken = {
		{ point = "MIDDLE", x = 1, y = 1 },
		{ point = "TOPLEFT", x = 0 / 0, y = 1 },
		{ point = "TOPLEFT", x = 1, y = 1e9 },
		{ point = "TOPLEFT", x = "1", y = 1 },
		"TOPLEFT",
	}
	for i, position in ipairs(broken) do
		Equal(ns.NormalizeSaved({ format = ns.SAVE_FORMAT, position = position }).position, nil, "broken position " .. i)
	end
	Equal(ns.NormalizeSaved({ format = ns.SAVE_FORMAT, minimized = "yes" }).minimized, false, "minimized that isn't true")
end)

--------------------------------------------------------------------------------
-- The panel, in the stand-in for the game (Tests/standin.lua), frame by frame.
--------------------------------------------------------------------------------

local NewGame = dofile("Tests/standin.lua")
local INFINITY_ART = "Interface\\AddOns\\ForeverCountdown\\Infinity"
local DISC = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local LAUNCH = ns.LAUNCH

local function Panel(now, saved)
	return NewGame(now):Load(saved):Frames(2)
end

local function Clean(game, what)
	Equal(#game.errors, 0, what .. ": errors (" .. tostring(game.errors[1]) .. ")")
	Equal(#game.chat, 0, what .. ": chat lines (" .. tostring(game.chat[1]) .. ")")
end

local function Has(game, text, what)
	if not game:Find(text) then
		error(what .. ": no \"" .. text .. "\" in: " .. game:Read(), 2)
	end
	return game:Find(text)
end

local function Grey(widget, what)
	local r, g, b = widget:GetTextColor()
	Equal(string.format("%.2f %.2f %.2f", r, g, b), "0.60 0.60 0.60", what .. " greyed")
end

local function Count(game, test)
	local n = 0
	for _, widget in ipairs(game.widgets) do
		if test(widget) then
			n = n + 1
		end
	end
	return n
end

-- The two infinity signs: their art, and the light's discs drawn over each.
local function InfinitySigns(game)
	local signs = {}
	for _, widget in ipairs(game.widgets) do
		if widget.texture == INFINITY_ART then
			local discs = {}
			for _, child in ipairs(widget.parent.children) do
				if child.texture == DISC then
					discs[#discs + 1] = child
				end
			end
			signs[#signs + 1] = { art = widget, discs = discs }
		end
	end
	return signs
end

local function MinimizeButton(game)
	for _, widget in ipairs(game.widgets) do
		if widget.widgetType == "Button" and widget.normal then
			return widget
		end
	end
end

Test("the panel before the launch: the milestones, the clock, no last line", function()
	local game = Panel(Utc(2026, 10, 5, 12))
	Clean(game, "before")
	Has(game, "Countdown to", "header")
	Has(game, "- September 17 · 18 Days ago", "beta began")
	Has(game, "Beta ends", "beta")
	Has(game, "- October 21 · in 16 Days", "beta")
	Has(game, "Name reservation starts", "reservation")
	Has(game, "launches", "launch")
	Has(game, "30", "days on the clock")
	Equal(game:Find("Welcome to"), nil, "no welcome before the launch")
	for _, sign in ipairs(InfinitySigns(game)) do
		if sign.art:IsVisible() then
			Equal(sign.art:IsDesaturated(), false, "the visible sign is lit")
		end
	end
	Equal(game.panel:GetWidth() >= 260, true, "at least a tracker section wide")
end)

Test("at the launch everything greys, the clock stays at zeros and the last line welcomes the player", function()
	local game = Panel(LAUNCH - 2)
	local before = game.panel:GetHeight()
	game:Frames(240, 4)
	Clean(game, "after")
	for _, title in ipairs({ "Beta began", "Beta ended", "Name reservation ended", "launched" }) do
		Grey(Has(game, title, "after"), title)
	end
	Grey(Has(game, "- November 4 · Today", "launch line (UTC)"), "the launch line")
	Equal(Count(game, function(w) return w.widgetType == "FontString" and w:IsVisible() and w.text == "00" end), 4, "the clock's zeros")
	Has(game, "Welcome to", "welcome")
	Has(game, "!", "welcome")
	Equal(game.panel:GetHeight() > before, true, "the panel grows by the last line")
	local welcome = 0
	for _, text in ipairs({ "Welcome to", "!" }) do
		welcome = welcome + game:Find(text):GetStringWidth()
	end
	Equal(game.panel:GetWidth() >= welcome + 33, true, "wide enough for the last line")
	-- "Forever" glows in the header and the last line; the launch row's is grey without glow.
	local glowing = Count(game, function(w) return w.layer == "BACKGROUND" and w:IsVisible() and w.text == "Forever" end)
	Equal(glowing, 16, "glowing copies of Forever")
	-- The sign by "Forever launched" is greyed and still; the one by the last line is lit.
	local signs = InfinitySigns(game)
	Equal(#signs, 2, "two signs")
	local greyed, lit = signs[1], signs[2]
	Equal(greyed.art:IsDesaturated(), true, "the launch row's sign is greyed")
	for _, disc in ipairs(greyed.discs) do
		Equal(disc:IsShown(), false, "no light on the greyed sign")
	end
	Equal(lit.art:IsDesaturated() or not lit.art:IsVisible(), false, "the last line's sign is lit")
	local x1 = select(4, lit.discs[1]:GetPoint())
	game:Frames(3)
	Equal(select(4, lit.discs[1]:GetPoint()) ~= x1, true, "its light moves")
	-- The quill rests, greyed.
	local quillDiscs = Count(game, function(w) return w.texture == DISC and w.parent and w.parent.texture == nil and not w.calls.SetBlendMode and (w.color and w.color[1] ~= w.color[3]) end)
	Equal(quillDiscs, 0, "no gold left on the quill")
end)

Test("a reload after the launch shows the launched panel at once", function()
	local game = Panel(LAUNCH + 86400)
	Clean(game, "reload")
	Has(game, "Welcome to", "reload")
	Has(game, "- November 4 · 1 Day ago", "reload")
	local open = NewGame(LAUNCH - 86400):Load():Frames(2).panel:GetHeight()
	Equal(game.panel:GetHeight() > open, true, "taller than before the launch")
end)

Test("the minimize button clicks like the tracker's own and keeps only the header", function()
	local game = Panel(Utc(2026, 10, 5, 12))
	local open = game.panel:GetHeight()
	local button = MinimizeButton(game)
	button:Click()
	Equal(game.sounds[1], 856, "the tracker's click sound")
	Equal(game.panel:GetHeight(), 26, "only the header")
	Equal(button.normal.atlas, "UI-QuestTrackerButton-Secondary-Expand", "the expand art")
	button:Click()
	Equal(game.panel:GetHeight(), open, "open again")
	Equal(ForeverCountdownDB.minimized, false, "saved open")
	Clean(game, "minimize")
end)

Test("the tracker's Text Size: the clock stays 3 larger than the header, the panel widens", function()
	local game = Panel(Utc(2026, 10, 5, 12))
	local width = game.panel:GetWidth()
	ObjectiveTrackerManager:SetTextSize(16)
	game:Frames(2)
	local sizes = {}
	for _, widget in ipairs(game.widgets) do
		if widget.widgetType == "FontString" and widget.font then
			sizes[widget.font[2]] = true
		end
	end
	Equal(sizes[21] and sizes[25], true, "figures 18 + 3 and colons 4 larger")
	Equal(game.panel:GetWidth() > width, true, "wider with the larger text")
	Clean(game, "text size")
end)

Test("the panel takes its sizes from the tracker's own header", function()
	local game = NewGame(Utc(2026, 10, 5, 12))
	QuestObjectiveTracker.Header:SetSize(400, 30)
	game:Load():Frames(2)
	Equal(game.panel:GetWidth() >= 400, true, "a section's width")
	MinimizeButton(game):Click()
	Equal(game.panel:GetHeight(), 30, "a section header's height")
	Clean(game, "sizes")
end)

local function Anchor(game)
	local point, relativeTo, relativePoint, x, y = game.panel:GetPoint(1)
	return string.format("%s %s %s %d %d", point, relativeTo == UIParent and "UIParent" or "?", relativePoint, x, y)
end

Test("until moved, the panel mirrors the objective tracker on the left of the screen", function()
	local game = Panel(Utc(2026, 10, 5, 12))
	Equal(Anchor(game), "TOPLEFT UIParent TOPLEFT 110 -275", "mirrors the tracker")
	-- Edit Mode moves the tracker: the panel follows within a second.
	game:Place(ObjectiveTrackerFrame, { 1400, 700, 1660, 300 })
	game:Frames(70)
	Equal(Anchor(game), "TOPLEFT UIParent TOPLEFT 260 -380", "follows the tracker")
	-- A tracker at another scale: its place in the screen's units.
	ObjectiveTrackerFrame:SetScale(0.5)
	game:Place(ObjectiveTrackerFrame, { 3000, 1600, 3520, 800 })
	game:Frames(70)
	Equal(Anchor(game), "TOPLEFT UIParent TOPLEFT 160 -280", "a tracker at half scale")
	Clean(game, "follow")
end)

Test("before the tracker has a place, the panel uses Blizzard's; once moved it stays", function()
	local game = NewGame(Utc(2026, 10, 5, 12))
	game:Place(ObjectiveTrackerFrame, nil)
	game:Load():Frames(2)
	Equal(Anchor(game), "TOPLEFT UIParent TOPLEFT 110 -275", "Blizzard's place for the tracker")
	game = Panel(Utc(2026, 10, 5, 12), { format = 1, minimized = false, position = { point = "TOPLEFT", x = 500, y = -40 } })
	game:Place(ObjectiveTrackerFrame, { 1400, 700, 1660, 300 })
	game:Frames(70)
	Equal(Anchor(game), "TOPLEFT UIParent TOPLEFT 500 -40", "where the player put it")
	Clean(game, "moved")
end)

Test("the header's art keeps its size, or stretches to a panel wider than it", function()
	local game = Panel(Utc(2026, 10, 5, 12))
	local art
	for _, widget in ipairs(game.widgets) do
		if widget.atlas == "UI-QuestTracker-Secondary-Objective-Header" then
			art = widget
		end
	end
	Equal(game.panel:GetWidth() < 300 and art:GetWidth(), 300, "its own width at the tracker's usual text")
	ObjectiveTrackerManager:SetTextSize(20)
	game:Frames(2)
	Equal(game.panel:GetWidth() > 300, true, "a wider panel at the largest text")
	Equal(art:GetWidth(), game.panel:GetWidth(), "the art as wide as the panel")
	Clean(game, "art")
end)

Test("the animation sets only what changes", function()
	for _, minimized in ipairs({ false, true }) do
		local game = Panel(Utc(2026, 10, 5, 12), { format = 1, minimized = minimized }):Frames(70)
		game.calls = {}
		game:Frames(600, 10)
		local sets = 0
		for name, count in pairs(game.calls) do
			if name:find("^Set") then
				sets = sets + count
			end
		end
		local limit = minimized and 10 or 80
		Equal(sets / 600 <= limit, true, string.format("%s: %.1f calls that set something per frame, at most %d", minimized and "minimized" or "open", sets / 600, limit))
		Clean(game, "animation")
	end
end)

Test("at the real launch the panel reads as the user saw it in game in the launch preview", function()
	-- The preview build (1.1.7, 2026-10-05) ran the clock ahead to the launch; the user saw this in
	-- game in Finland. The real build at the real launch moment must read the same.
	local game = NewGame(LAUNCH)
	game.InZone(2, function()
		game:Load():Frames(120, 2)
		Equal(game:Read(), "Countdown to | Forever | 00 | : | 00 | : | 00 | : | 00 | Beta began | - September 17 · 49 Days ago"
			.. " | Beta ended | - October 21 · 15 Days ago | Name reservation ended | - November 3 · 2 Days ago"
			.. " | - November 5 · Today | Forever | launched | Welcome to | Forever | !", "the panel at the launch, Helsinki")
	end)
	Clean(game, "launch")
end)

if failures > 0 then
	print(failures .. " failed")
	os.exit(1)
end
print("all passed")
