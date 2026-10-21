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

-- ns.Lines, with each row's lines also as one text (`line`, joined by " / ") for comparing.
local function Lines(now, region)
	local rows = ns.Lines(now, region)
	for _, row in pairs(rows) do
		if type(row) == "table" then
			local texts = {}
			for i, line in ipairs(row.lines) do
				texts[i] = line.text
			end
			row.line = table.concat(texts, " / ")
		end
	end
	return rows
end
local failures = 0
local games = {} -- the stand-in games the current test plays (NewGame, below)

local function Test(name, func)
	games = {}
	local ok, problem = pcall(func)
	-- Whatever the test checks, it fails if the game refused the addon anything in combat.
	for _, game in ipairs(games) do
		if #game.blocked > 0 then
			problem = "ADDON_ACTION_BLOCKED in combat: " .. table.concat(game.blocked, ", ") .. (ok and "" or "; then " .. tostring(problem))
			ok = false
			break
		end
	end
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
	local beta = ns.CivilDay(2026, 10, 21)
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
			Equal(ns.DayLine(ns.CivilDay(2026, 10, 21), noon), "October 21 · Today", "UTC" .. (hours >= 0 and "+" or "") .. hours)
		end)
	end
end)

-- The tests below run in UTC unless they say otherwise.
Test("the beta ends October 23 at 10:00 PDT, 17:00 UTC, one moment in every region", function()
	for _, region in ipairs({ "US", "EU", "KR", "TW", "CN" }) do
		local lines = Lines(Utc(2026, 10, 23, 17) - 1, region)
		Equal(lines.betaEnds.title, "Beta ends", region .. ", a second before")
		Equal(lines.betaEnds.done, false, region .. ", not done a second before")
		lines = Lines(Utc(2026, 10, 23, 17), region)
		Equal(lines.betaEnds.title, "Beta ended", region .. ", at the moment")
		Equal(lines.betaEnds.done, true, region .. ", done at the moment")
	end
	local lines = Lines(Utc(2026, 10, 22, 12))
	Equal(lines.betaBegan.done, true, "beta began is always done")
	Equal(lines.betaBegan.line, "September 17 · " .. D_DAYS:format(35) .. " ago", "beta began, 35 days ago")
	Equal(Lines(Utc(2026, 10, 5, 12)).betaBegan.line, "September 17 · " .. D_DAYS:format(18) .. " ago", "beta began, 18 days ago")
end)

Test("name reservation where Blizzard gave no start time: starts until October 27 (Today on the day), then ends with November 3", function()
	local lines = Lines(Utc(2026, 10, 26, 12), "CN")
	Equal(lines.reservation.title, "Name reservation starts", "the day before")
	Equal(lines.reservation.line, "October 27 · in " .. D_DAYS:format(1), "the day before")
	lines = Lines(Utc(2026, 10, 27, 12), "CN")
	Equal(lines.reservation.title, "Name reservation starts", "the first day")
	Equal(lines.reservation.line, "October 27 · Today", "the first day")
	lines = Lines(Utc(2026, 10, 28, 12), "CN")
	Equal(lines.reservation.title, "Name reservation ends", "the second day")
	Equal(lines.reservation.line, "November 3 · in " .. D_DAYS:format(6), "the second day")
	lines = Lines(Utc(2026, 11, 3, 20), "CN")
	Equal(lines.reservation.line, "November 3 · Today", "the last day")
	Equal(lines.reservation.done, false, "not done on the last day")
	lines = Lines(Utc(2026, 11, 4, 9), "CN")
	Equal(lines.reservation.title, "Name reservation ended", "the day after")
	Equal(lines.reservation.line, "November 3 · " .. D_DAYS:format(1) .. " ago", "the day after")
	Equal(lines.reservation.done, true, "done the day after")
end)

-- A moment's line, in the player's time zone with its time until it has passed.
Test("the beta's end reads in the player's own time, then how many days ago", function()
	InZone(3, function() -- Helsinki in October (EEST)
		Equal(Lines(Utc(2026, 10, 21, 12), "EU").betaEnds.line, "October 23, 8:00 PM · in " .. D_DAYS:format(2), "Helsinki, 12-hour")
		WithClock(true, function()
			Equal(Lines(Utc(2026, 10, 21, 12), "EU").betaEnds.line, "October 23, 20:00 · in " .. D_DAYS:format(2), "Helsinki, 24-hour")
			Equal(Lines(Utc(2026, 10, 22, 12), "EU").betaEnds.line, "October 23, 20:00 · in " .. D_DAYS:format(1), "Helsinki, a day and 5 hours before")
			Equal(Lines(Utc(2026, 10, 22, 17), "EU").betaEnds.line, "October 23, 20:00 · in " .. D_DAYS:format(1), "Helsinki, exactly a day before")
			Equal(Lines(Utc(2026, 10, 22, 17) + 1, "EU").betaEnds.line, "in 23:59:59", "Helsinki, under a day before: a countdown")
			Equal(Lines(Utc(2026, 10, 23, 9), "EU").betaEnds.line, "in 08:00:00", "Helsinki, that morning")
			Equal(Lines(Utc(2026, 10, 23, 17) - 1, "EU").betaEnds.line, "in 00:00:01", "Helsinki, a second before")
		end)
		Equal(Lines(Utc(2026, 10, 23, 17), "EU").betaEnds.line, "October 23 · Today", "Helsinki, once ended")
		Equal(Lines(Utc(2026, 10, 24, 9), "EU").betaEnds.line, "October 23 · " .. D_DAYS:format(1) .. " ago", "Helsinki, the day after")
	end)
	InZone(-7, function() -- California (PDT)
		Equal(Lines(Utc(2026, 10, 21, 20), "US").betaEnds.line, "October 23, 10:00 AM · in " .. D_DAYS:format(2), "California")
	end)
	InZone(13, function() -- Auckland (NZDT): already the 24th there
		Equal(Lines(Utc(2026, 10, 21, 20), "US").betaEnds.line, "October 24, 6:00 AM · in " .. D_DAYS:format(2), "Auckland")
	end)
end)

Test("the stress test: starts, then ends, then ended and greyed, at its region's times", function()
	-- Europe 17:00 to 01:00 UTC; the Americas, Oceania, Korea and Taiwan 21:00 to 01:00 UTC.
	local function Read(zone, region, now)
		local line
		InZone(zone, function()
			local lines = Lines(now, region)
			line = lines.stressTest.title .. " | " .. lines.stressTest.line .. " | " .. tostring(lines.stressTest.done)
		end)
		return line
	end
	local morning = Utc(2026, 10, 21, 9)
	Equal(Read(3, "EU", morning), "Stress test starts | in 08:00:00 | false", "Helsinki, that morning")
	Equal(Read(3, "EU", Utc(2026, 10, 21, 17)), "Stress test ends | in 08:00:00 | false", "Helsinki, as it starts")
	Equal(Read(3, "EU", Utc(2026, 10, 22, 1)), "Stress test ended | October 22 · Today | true", "Helsinki, as it ends")
	Equal(Read(1, "EU", morning), "Stress test starts | in 08:00:00 | false", "London (BST)")
	Equal(Read(-7, "US", morning), "Stress test starts | in 12:00:00 | false", "California")
	Equal(Read(-7, "US", Utc(2026, 10, 21, 21)), "Stress test ends | in 04:00:00 | false", "California, as it starts")
	Equal(Read(-4, "US", morning), "Stress test starts | in 12:00:00 | false", "New York")
	Equal(Read(13, "US", morning), "Stress test starts | in 12:00:00 | false", "Auckland")
	Equal(Read(9, "KR", morning), "Stress test starts | in 12:00:00 | false", "Seoul")
	Equal(Read(8, "TW", morning), "Stress test starts | in 12:00:00 | false", "Taipei")
	Equal(Read(3, "EU", Utc(2026, 10, 19, 9)), "Stress test starts | October 21, 8:00 PM · in " .. D_DAYS:format(2) .. " | false", "Helsinki, days before")
	-- Europe's start isn't the others': 18:00 UTC is during it in Europe, before it elsewhere.
	Equal(Read(0, "EU", Utc(2026, 10, 21, 18)):match("^[^|]*"), "Stress test ends ", "Europe at 18:00 UTC")
	Equal(Read(0, "US", Utc(2026, 10, 21, 18)):match("^[^|]*"), "Stress test starts ", "the Americas at 18:00 UTC")
	-- A region Blizzard gave no start time for: the start's date by the player's calendar, then
	-- the end, the same moment everywhere.
	Equal(Read(8, "CN", morning), "Stress test starts | October 21 · Today | false", "no start time, that day")
	Equal(Read(8, "CN", Utc(2026, 10, 21, 16)), "Stress test ends | in 09:00:00 | false", "no start time, the next day")
	Equal(Read(8, "CN", Utc(2026, 10, 22, 1)), "Stress test ended | October 22 · Today | true", "no start time, after")
end)

Test("with no region (the beta's), each time has its own line, earliest first, greyed and started once begun", function()
	local function Read(now, key)
		local rows
		InZone(3, function() -- UTC+3, Helsinki's summer time
			rows = ns.Lines(now, "")
		end)
		local row = rows[key]
		local texts = {}
		for i, line in ipairs(row.lines) do
			texts[i] = line.text .. (line.done and " (grey)" or "")
		end
		return row.title .. " | " .. table.concat(texts, " / ")
	end
	Equal(Read(Utc(2026, 10, 21, 9), "stressTest"), "Stress test starts | Europe: in 08:00:00 / Rest of the world: in 12:00:00", "the morning")
	Equal(Read(Utc(2026, 10, 21, 18), "stressTest"), "Stress test starts | Europe: started October 21 · Today (grey) / Rest of the world: in 03:00:00", "Europe has started")
	Equal(Read(Utc(2026, 10, 21, 21), "stressTest"), "Stress test ends | in 04:00:00", "all have started")
	Equal(Read(Utc(2026, 10, 22, 1), "stressTest"), "Stress test ended | October 22 · Today (grey)", "over")
	Equal(Read(Utc(2026, 10, 25, 12), "reservation"), "Name reservation starts | Europe: October 27, 8:00 PM · in " .. D_DAYS:format(2)
		.. " / Americas & Oceania: October 27, 11:00 PM · in " .. D_DAYS:format(2) .. " / Korea: October 28, 1:00 AM · in " .. D_DAYS:format(3)
		.. " / Taiwan: October 28, 2:00 AM · in " .. D_DAYS:format(3), "name reservation, days before")
	Equal(Read(Utc(2026, 10, 27, 22, 30), "reservation"), "Name reservation starts | Europe: started October 27 · " .. D_DAYS:format(1) .. " ago (grey)"
		.. " / Americas & Oceania: started October 27 · " .. D_DAYS:format(1) .. " ago (grey) / Korea: started October 28 · Today (grey)"
		.. " / Taiwan: in 00:30:00", "only Taiwan left, past midnight")
	Equal(Read(Utc(2026, 10, 27, 23), "reservation"), "Name reservation ends | November 3 · in " .. D_DAYS:format(6), "all have started")
	-- Regions with the same time share a line; when several such lines would, they name their regions.
	local twoShared = { US = 1, KR = 1, EU = 2, TW = 2, day = 0 }
	Equal(#ns.MilestoneLines(twoShared, "", 0, false), 2, "two shared lines")
	Equal(ns.MilestoneLines(twoShared, "", 0, false)[1].text:match("^[^:]*"), "Americas & Oceania, Korea", "named when two lines are shared")
	-- The beta's end is one moment everywhere: one line.
	Equal(Read(Utc(2026, 10, 21, 9), "betaEnds"), "Beta ends | October 23, 8:00 PM · in " .. D_DAYS:format(2), "the beta's end")
	-- nil, as the stand-in gives without GetCurrentRegionName, reads the same as "".
	Equal(#ns.Lines(Utc(2026, 10, 21, 9)).stressTest.lines, 2, "no region at all")
end)

Test("name reservation starts at its region's time, in the player's own time", function()
	local function Read(zone, region, now)
		local line
		InZone(zone, function()
			local lines = Lines(now, region)
			line = lines.reservation.title .. " | " .. lines.reservation.line
		end)
		return line
	end
	local before = Utc(2026, 10, 26, 12)
	Equal(Read(-7, "US", before), "Name reservation starts | October 27, 1:00 PM · in " .. D_DAYS:format(1), "California, 1:00 p.m. PDT")
	Equal(Read(1, "EU", before), "Name reservation starts | October 27, 6:00 PM · in " .. D_DAYS:format(1), "Paris, 18:00 CET")
	Equal(Read(2, "EU", before), "Name reservation starts | October 27, 7:00 PM · in " .. D_DAYS:format(1), "Helsinki (EET)")
	Equal(Read(9, "KR", before), "Name reservation starts | October 28, 7:00 AM · in " .. D_DAYS:format(2), "Seoul, 07:00 KST")
	Equal(Read(8, "TW", before), "Name reservation starts | October 28, 7:00 AM · in " .. D_DAYS:format(2), "Taipei, 07:00 CST")
	-- At its start it turns to the end, November 3, a date only.
	Equal(Read(-7, "US", Utc(2026, 10, 27, 20) - 1), "Name reservation starts | in 00:00:01", "California, a second before")
	Equal(Read(-7, "US", Utc(2026, 10, 27, 20)), "Name reservation ends | November 3 · in " .. D_DAYS:format(7), "California, at the start")
	Equal(Read(1, "EU", Utc(2026, 10, 27, 17)), "Name reservation ends | November 3 · in " .. D_DAYS:format(7), "Paris, at the start")
	Equal(Read(1, "US", Utc(2026, 10, 27, 17)):match("^[^|]*"), "Name reservation starts ", "an American realm at Europe's start")
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
	Equal(Lines(ns.LAUNCH - 1).launched, false, "not launched a second before")
	Equal(Lines(ns.LAUNCH).launched, true, "launched at launch")
end)

Test("the launch line: the moment before, then the launch's own date and how many days ago", function()
	InZone(2, function()
		local lines = Lines(ns.LAUNCH - 1)
		Equal(lines.launch.title, "launches", "Helsinki, a second before")
		Equal(lines.launch.line, ns.LaunchText(), "Helsinki, a second before")
		Equal(lines.launch.done, false, "not done before")
		lines = Lines(ns.LAUNCH)
		Equal(lines.launch.title, "launched", "Helsinki, at launch")
		-- 01:00 on November 5 in Helsinki: the launch is today there, on the 5th.
		Equal(lines.launch.line, "November 5 · Today", "Helsinki, at launch")
		Equal(lines.launch.done, true, "done at launch")
		Equal(Lines(Utc(2026, 11, 6, 22)).launch.line, "November 5 · " .. D_DAYS:format(2) .. " ago", "Helsinki, two days later")
	end)
	InZone(-8, function()
		Equal(Lines(ns.LAUNCH + 3600).launch.line, "November 4 · Today", "California, an hour after")
		Equal(Lines(ns.LAUNCH + 9 * 3600).launch.line, "November 4 · " .. D_DAYS:format(1) .. " ago", "California, the next morning")
	end)
end)

Test("after the launch every milestone is behind", function()
	local lines = Lines(ns.LAUNCH + 2 * DAY)
	for _, key in ipairs({ "betaBegan", "stressTest", "betaEnds", "reservation", "launch" }) do
		Equal(lines[key].done, true, key)
	end
	Equal(lines.stressTest.title, "Stress test ended", "stress test")
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

local StandIn = dofile("Tests/standin.lua")
local function NewGame(now)
	local game = StandIn(now)
	games[#games + 1] = game
	return game
end
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
	Has(game, "Stress test starts", "stress test")
	Has(game, "- Europe: October 21, 5:00 PM · in 16 Days", "stress test (UTC, the beta's no region)")
	Has(game, "- Taiwan: October 27, 11:00 PM · in 22 Days", "name reservation (UTC)")
	Has(game, "Beta ends", "beta")
	Has(game, "- October 23, 5:00 PM · in 18 Days", "beta")
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
	for _, title in ipairs({ "Beta began", "Stress test ended", "Beta ended", "Name reservation ended", "launched" }) do
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

Test("the panel lays out each region's line, and shrinks when the last region starts", function()
	local game = Panel(Utc(2026, 10, 21, 21) - 2)
	local before = game.panel:GetHeight()
	Has(game, "- Europe: started October 21 · Today", "Europe's line, started")
	Grey(game:Find("- Europe: started October 21 · Today"), "Europe's line")
	Has(game, "- Rest of the world: in 00:00:02", "the rest of the world's countdown")
	game:Frames(240, 4)
	Has(game, "Stress test ends", "all started")
	Equal(game:Find("- Europe: started October 21 · Today"), nil, "the region lines are gone")
	Equal(game.panel:GetHeight() < before, true, "the panel shrinks by a line")
	-- The row under it follows the last line shown.
	local beta = game:Find("Beta ends")
	local _, anchor = beta:GetPoint(1)
	Equal(anchor, game:Find("- in 03:59:58") or game:Find("- in 03:59:59"), "Beta ends under the stress test's one line")
	Clean(game, "regions")
	game = Panel(Utc(2026, 10, 21, 12))
	local width = game.panel:GetWidth()
	for _ = 1, 5 do
		game:Frames(60, 1)
		Equal(game.panel:GetWidth(), width, "the same width as the countdown ticks")
	end
	Clean(game, "countdown")
end)

Test("the stress test's blue \"!\" greys once the test is over", function()
	local function Marker(game)
		for _, widget in ipairs(game.widgets) do
			if widget.atlas == "QuestDaily" then
				return widget
			end
		end
	end
	local game = Panel(Utc(2026, 10, 22, 1) - 2)
	local marker = Marker(game)
	Equal(marker:IsDesaturated(), false, "in color during the test")
	Has(game, "Stress test ends", "during")
	game:Frames(240, 4)
	Equal(marker:IsDesaturated(), true, "greyed after")
	Grey(Has(game, "Stress test ended", "after"), "the title")
	Clean(game, "stress test")
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
	-- A realm with a region: one line per milestone, so the panel is a tracker section's width.
	local game = NewGame(Utc(2026, 10, 5, 12))
	game.region = "US"
	game:Load():Frames(2)
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
	-- game in Finland. The real build at the real launch moment must read the same, with the
	-- stress test row and the beta's new end added since (1.2.0).
	local game = NewGame(LAUNCH)
	game.InZone(2, function()
		game:Load():Frames(120, 2)
		Equal(game:Read(), "Countdown to | Forever | 00 | : | 00 | : | 00 | : | 00 | Beta began | - September 17 · 49 Days ago"
			.. " | Stress test ended | - October 22 · 14 Days ago"
			.. " | Beta ended | - October 23 · 13 Days ago | Name reservation ended | - November 3 · 2 Days ago"
			.. " | - November 5 · Today | Forever | launched | Welcome to | Forever | !", "the panel at the launch, Helsinki")
	end)
	Clean(game, "launch")
end)

Test("an error while loading goes to the game's error handler, says so once, and shows nothing", function()
	local game = NewGame(Utc(2026, 10, 5, 12))
	GetServerTime = function()
		error("broken clock")
	end
	game:Load():Frames(120, 2)
	Equal(#game.errors, 1, "one error to the game's handler")
	Equal(#game.chat, 1, "one chat line")
	Equal(game.chat[1]:find("stopped") ~= nil, true, "says it stopped")
	Equal(game.panel:IsShown(), false, "the half-built panel is hidden")
end)

Test("the minimize button is the tracker's own, or made like it when the tracker is missing", function()
	local game = Panel(Utc(2026, 10, 5, 12))
	local button = MinimizeButton(game)
	Equal(button.template, "ObjectiveTrackerModuleMinimizeButtonTemplate", "the tracker's template")
	Equal(button:GetWidth(), 16, "its size")
	game = NewGame(Utc(2026, 10, 5, 12))
	game.templates = {}
	game:Load():Frames(2)
	button = MinimizeButton(game)
	Equal(button.template, nil, "no template")
	Equal(button:GetWidth() .. " " .. button.normal.atlas .. " " .. button.highlight.atlas, "16 UI-QuestTrackerButton-Secondary-Collapse UI-QuestTrackerButton-Yellow-Highlight", "made like it")
	button:Click()
	Equal(button.normal.atlas, "UI-QuestTrackerButton-Secondary-Expand", "minimized")
	Clean(game, "fallback button")
end)

-- Combat: the game refuses the addon's code moving, showing or hiding a protected frame then
-- (see Combat in Tests/standin.lua); any refusal fails the test (see Test).

Test("in combat the panel runs as out of it; nothing waits for combat to end", function()
	-- A /reload in combat loads the addon in combat.
	local game = NewGame(Utc(2026, 10, 5, 12)):EnterCombat():Load():Frames(120, 2)
	local button = MinimizeButton(game)
	button:Click()
	button:Click()
	local header
	for _, widget in ipairs(game.widgets) do
		if widget.scripts.OnDragStart then
			header = widget
		end
	end
	game:RunScript(header, "OnDragStart")
	game:RunScript(header, "OnDragStop")
	ObjectiveTrackerManager:SetTextSize(16)
	-- The tracker moves; the panel follows it, as its own frame may in combat.
	game:Place(ObjectiveTrackerFrame, { 1500, 805, 1760, 400 })
	game:Frames(120, 2)
	Equal(select(4, game.panel:GetPoint()), 160, "followed the tracker in combat")
	local before = game:Read()
	game:LeaveCombat():Frames(60, 1)
	Equal(#game.events.PLAYER_REGEN_ENABLED, 0, "handlers waiting for combat to end")
	Equal(game:Read() ~= before, true, "the clock still ticks after combat")
	Clean(game, "combat")
end)

Test("the stand-in refuses the addon moving a protected frame in combat, and only the addon", function()
	local game = Panel(Utc(2026, 10, 5, 12))
	-- Code the stand-in counts as the addon's: chunks named after its file.
	local function AddonCode(code)
		return assert(load(code, "@ForeverCountdown.lua"))
	end
	local function BlizzardCode(code)
		return assert(load(code, "@Interface/AddOns/Blizzard_Test/Test.lua"))
	end
	local scale = AddonCode("UIParent:SetScale(0.9)")
	scale()
	Equal(#game.blocked .. " " .. UIParent:GetEffectiveScale(), "0 0.9", "out of combat")

	game:EnterCombat()
	AddonCode("UIParent:Hide() UIParent:SetPoint('CENTER')")()
	Equal(table.concat(game.blocked, ", "), "UIParent:Hide(), UIParent:SetPoint()", "the addon in combat")
	Equal(UIParent:IsShown(), true, "the refused Hide did nothing")
	game.blocked = {}
	AddonCode("local panel = ... panel:ClearAllPoints() panel:SetPoint('CENTER') panel:Hide() panel:Show()")(game.panel)
	Equal(#game.blocked, 0, "the addon's own frame in combat")
	BlizzardCode("UIParent:Hide() UIParent:Show()")()
	Equal(#game.blocked, 0, "Blizzard's code in combat")

	-- A run that enters the addon's code stays the addon's to its end, also through a tail call.
	local callback = AddonCode("return function() end")()
	local hideTail = AddonCode("return function() return UIParent:Hide() end")()
	local blizzard = BlizzardCode("local callback = ... callback() UIParent:SetPoint('TOPLEFT')")
	game.events.TEST_EVENT = {
		function()
			blizzard(callback)
		end,
		function()
			hideTail()
		end,
	}
	game:Fire("TEST_EVENT")
	Equal(table.concat(game.blocked, ", "), "UIParent:SetPoint(), UIParent:Hide()", "after the addon's code, in the same run")
	game.blocked = {}
	-- A hook's taint stays inside the hook.
	local blizzardTable = { Update = BlizzardCode("UIParent:SetPoint('TOPLEFT')") }
	hooksecurefunc(blizzardTable, "Update", callback)
	game.events.TEST_EVENT = {
		BlizzardCode("local t = ... t.Update() UIParent:SetPoint('TOPLEFT')"),
	}
	game:Fire("TEST_EVENT", blizzardTable)
	Equal(#game.blocked, 0, "Blizzard's code after a hooked call")

	game:LeaveCombat()
	scale()
	Equal(#game.blocked, 0, "after combat")
end)

if failures > 0 then
	print(failures .. " failed")
	os.exit(1)
end
print("all passed")
