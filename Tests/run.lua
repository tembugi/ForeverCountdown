-- Runs every test of the rules in Countdown.lua: `luajit Tests/run.lua` in the addon folder.
-- Exits non-zero when a test fails.

-- This file runs under luajit, outside the game, and uses standard Lua's loadfile and os,
-- which the game doesn't have.
---@diagnostic disable: undefined-global, lowercase-global

-- What Countdown.lua uses from the game, as the game has it: `date` is standard Lua's os.date
-- (the game's own copy of it), and the strings are the game's enUS ones
-- (BlizzardInterfaceResources, forever branch, GlobalStrings/enUS.lua). To test players in
-- different time zones, `date` reads local times at a fixed offset from UTC (InZone); os.date
-- does the same for the computer's own zone. "!" formats are UTC either way.
local zoneOffset = 0
date = function(format, moment)
	if format:sub(1, 1) == "!" then
		return os.date(format, moment)
	end
	return os.date("!" .. format, (moment or os.time()) + zoneOffset * 3600)
end
local function InZone(hours, func)
	local before = zoneOffset
	zoneOffset = hours
	local ok, problem = pcall(func)
	zoneOffset = before
	if not ok then
		error(problem, 0)
	end
end
D_DAYS = "%d |4Day:Days;"
TIME_TWELVEHOURAM = "%d:%02d AM"
TIME_TWELVEHOURPM = "%d:%02d PM"
TIMEMANAGER_TICKER_12HOUR = "%d:%02d"
TIMEMANAGER_TICKER_24HOUR = "%02d:%02d"
CURRENCY_TRANSFER_LOG_TIME_FORMAT = "%s ago"
FULLDATE = "%1$s, %2$s %3$d %4$d"
EVENT_SCHEDULER_DAY_FORMAT = "%1$s %2$d"
for i, name in ipairs({ "January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December" }) do
	_G["FULLDATE_MONTH_" .. name:upper()] = name
end
for _, name in ipairs({ "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday" }) do
	_G["WEEKDAY_" .. name:upper()] = name
end

-- The game's format takes numbered placeholders ("%1$s", as Blizzard's calendar formats FULLDATE
-- with format); standard Lua's doesn't, so this puts the arguments in the order they ask for.
local plainFormat = string.format
string.format = function(text, ...)
	if not text:find("%%%d+%$") then
		return plainFormat(text, ...)
	end
	local args, ordered = { ... }, {}
	local converted = text:gsub("%%(%d+)%$", function(n)
		ordered[#ordered + 1] = args[tonumber(n)]
		return "%"
	end)
	return plainFormat(converted, unpack(ordered))
end

-- The game's clock setting and its time formatter, copied from wow-ui-source (forever,
-- Blizzard_FrameXMLUtil/GameTimeUtil.lua).
local militaryTime = false
function GetCVarBool(name)
	if name == "timeMgrUseMilitaryTime" then
		return militaryTime
	end
end
function GameTime_GetFormattedTime(hour, minute, wantAMPM)
	if ( GetCVarBool("timeMgrUseMilitaryTime") ) then
		return format(TIMEMANAGER_TICKER_24HOUR, hour, minute);
	else
		if ( wantAMPM ) then
			local timeFormat = TIME_TWELVEHOURAM;
			if ( hour == 0 ) then
				hour = 12;
			elseif ( hour == 12 ) then
				timeFormat = TIME_TWELVEHOURPM;
			elseif ( hour > 12 ) then
				timeFormat = TIME_TWELVEHOURPM;
				hour = hour - 12;
			end
			return format(timeFormat, hour, minute);
		else
			if ( hour == 0 ) then
				hour = 12;
			elseif ( hour > 12 ) then
				hour = hour - 12;
			end
			return format(TIMEMANAGER_TICKER_12HOUR, hour, minute);
		end
	end
end
format = string.format
local function WithClock(twentyFourHours, func)
	militaryTime = twentyFourHours
	local ok, problem = pcall(func)
	militaryTime = false
	if not ok then
		error(problem, 0)
	end
end

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

Test("the clock counts days, hours, minutes and seconds to the launch, then stops", function()
	local left = 31 * DAY + 2 * HOUR + 3 * 60 + 4
	local d, h, m, s = ns.ClockParts(ns.LAUNCH - left)
	Equal(string.format("%d %d %d %d", d, h, m, s), "31 2 3 4", "31 days 2:03:04 before")
	d, h, m, s = ns.ClockParts(ns.LAUNCH - 1)
	Equal(string.format("%d %d %d %d", d, h, m, s), "0 0 0 1", "one second before")
	Equal(ns.ClockParts(ns.LAUNCH), nil, "at launch")
	Equal(ns.ClockParts(ns.LAUNCH + 60), nil, "after launch")
	Equal(ns.Lines(ns.LAUNCH - 1).launched, false, "not launched a second before")
	Equal(ns.Lines(ns.LAUNCH).launched, true, "launched at launch")
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

if failures > 0 then
	print(failures .. " failed")
	os.exit(1)
end
print("all passed")
