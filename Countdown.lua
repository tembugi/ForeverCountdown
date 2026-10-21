-- The dates and the rules, without any frames: what each line of the panel says at a given
-- moment. Tests/run.lua loads this file outside the game.
local _, ns = ...

local DAY = 86400
local HOUR = 3600

-- Days since 1970-01-01 for a calendar date (the proleptic Gregorian calendar), so the dates
-- below don't depend on the computer's time zone.
local function CivilDay(year, month, day)
	if month <= 2 then
		year = year - 1
	end
	local era = math.floor(year / 400)
	local yearOfEra = year - era * 400
	local dayOfYear = math.floor((153 * (month + (month > 2 and -3 or 9)) + 2) / 5) + day - 1
	local dayOfEra = yearOfEra * 365 + math.floor(yearOfEra / 4) - math.floor(yearOfEra / 100) + dayOfYear
	return era * 146097 + dayOfEra - 719468
end
ns.CivilDay = CivilDay

-- The calendar day a moment (seconds since 1970, UTC) falls on in the player's own time zone,
-- as days since 1970. `date` reads the moment in the computer's time zone.
local function LocalDay(now)
	local t = date("*t", now)
	return CivilDay(tonumber(t.year) or 0, tonumber(t.month) or 0, tonumber(t.day) or 0)
end
ns.LocalDay = LocalDay

-- A moment, as seconds since 1970 UTC, from a UTC date and hour.
local function Utc(year, month, day, hour)
	return CivilDay(year, month, day) * DAY + hour * HOUR
end

-- The milestones, from Blizzard's announcements. A milestone with a time of day is a moment the
-- world over, shown in the player's own time zone with its time (the user asked, 1.2.0):
-- - the launch: November 4 at 3:00 p.m. PST (UTC-8), 23:00 UTC; the clock counts to it;
-- - the beta's end: October 23 at 10:00 a.m. PDT (UTC-7), 17:00 UTC (moved from October 21 in
--   Blizzard's post of October 20);
-- - the stress test (the same post): October 21, 2:00 to 6:00 p.m. PDT in the Americas and
--   Oceania, 6:00 to 10:00 a.m. on the 22nd in Seoul, 5:00 to 9:00 a.m. in Taipei, all
--   21:00 to 01:00 UTC; in Europe 19:00 CEST to 03:00, 17:00 to 01:00 UTC;
-- - name reservation's start (Blizzard's post of October 20): October 27 at 1:00 p.m. PDT in
--   North America, 18:00 CET in Europe, October 28 at 07:00 KST in Korea and 07:00 CST in Taiwan.
-- Start times that differ by region show for the player's region (GetCurrentRegionName). The
-- beta knows no region (seen in game, 1.2.0), so without one each region gets its own line (the
-- user asked, 1.2.0). A milestone with only a Pacific date (the beta's start, name reservation's
-- end, and the regional ones in a region Blizzard gave no time for) can't become a local moment:
-- it shows the date as announced and counts days on the player's own calendar, so on that date
-- the line says "Today" wherever the player is (the user asked for local time, 1.0.0; Pacific
-- days made "Today" start at 10:00 in Finland).
ns.BETA_START = { day = CivilDay(2026, 9, 17) }
ns.STRESS_TEST_START = {
	day = CivilDay(2026, 10, 21),
	US = Utc(2026, 10, 21, 21), KR = Utc(2026, 10, 21, 21), TW = Utc(2026, 10, 21, 21),
	EU = Utc(2026, 10, 21, 17),
}
ns.STRESS_TEST_END = { moment = Utc(2026, 10, 22, 1) } -- the same in every region
ns.BETA_END = { moment = Utc(2026, 10, 23, 17) }
ns.RESERVATION_START = {
	day = CivilDay(2026, 10, 27),
	US = Utc(2026, 10, 27, 20), EU = Utc(2026, 10, 27, 17), KR = Utc(2026, 10, 27, 22), TW = Utc(2026, 10, 27, 23),
}
ns.RESERVATION_END = { day = CivilDay(2026, 11, 3) }
ns.LAUNCH = Utc(2026, 11, 4, 23)

-- The regions Blizzard gave times for, in this order when their times are the same, and their
-- names: the game's own (EUROPE, KOREA, TAIWAN) and the addon's for the Americas, which the
-- game has no name for. Region keys as GetCurrentRegionName gives them.
local REGIONS = { "US", "EU", "KR", "TW" }
local function RegionName(region)
	if region == "US" then
		return ns.TEXT.americasOceania
	end
	return _G[({ EU = "EUROPE", KR = "KOREA", TW = "TAIWAN" })[region]] or region
end

-- English, like the rest of the addon's own words. The game has no strings for these.
ns.TEXT = {
	countdownTo = "Countdown to",
	forever = "Forever",
	betaBegan = "Beta began",
	stressTestStarts = "Stress test starts",
	stressTestEnds = "Stress test ends",
	stressTestEnded = "Stress test ended",
	betaEnds = "Beta ends",
	betaEnded = "Beta ended",
	reservationStarts = "Name reservation starts",
	reservationEnds = "Name reservation ends",
	reservationEnded = "Name reservation ended",
	launches = "launches",
	launched = "launched",
	welcomeTo = "Welcome to", -- then "Forever" and "!", the last line once Forever has launched
	welcomeEnd = "!",
	inDays = "in %s",
	americasOceania = "Americas & Oceania",
	restOfWorld = "Rest of the world", -- the regions the other lines don't name
	regionLine = "%s: %s", -- a region's name, then its line
	regionStarted = "%s: started %s", -- the same once it has started, greyed (the user asked)
}

-- Month and weekday names are the game's own, in the player's language (the global strings
-- FULLDATE_MONTH_* and WEEKDAY_*), as its calendar uses them.
local MONTH_KEYS = { "JANUARY", "FEBRUARY", "MARCH", "APRIL", "MAY", "JUNE", "JULY", "AUGUST", "SEPTEMBER", "OCTOBER", "NOVEMBER", "DECEMBER" }
local WEEKDAY_KEYS = { "SUNDAY", "MONDAY", "TUESDAY", "WEDNESDAY", "THURSDAY", "FRIDAY", "SATURDAY" }
local function MonthName(month)
	return _G["FULLDATE_MONTH_" .. MONTH_KEYS[month]]
end
local function WeekdayName(weekday)
	return _G["WEEKDAY_" .. WEEKDAY_KEYS[weekday]]
end

-- "October 21" for a calendar day as Blizzard announced it, the way the game's event scheduler
-- writes a day (EVENT_SCHEDULER_DAY_FORMAT, month name then day).
local function DayText(civilDay)
	local t = date("!*t", civilDay * DAY)
	return EVENT_SCHEDULER_DAY_FORMAT:format(MonthName(tonumber(t.month) or 1), tonumber(t.day) or 1)
end
ns.DayText = DayText

-- Days from now to a calendar day, on the player's own calendar: 0 on the day itself, negative
-- once it has passed.
local function DaysUntil(civilDay, now)
	return civilDay - LocalDay(now)
end
ns.DaysUntil = DaysUntil

-- "October 27 · in 22 Days" before the day (the user asked, 0.1.16), "October 21 · Today" on it,
-- and "September 17 · 18 Days ago" once it has passed (the user asked, 0.1.15). D_DAYS is the
-- game's own "%d |4Day:Days;" (the game picks the singular or plural when it shows it); "Today"
-- is the word the game's calendar writes for an event on the current day; "%s ago" is the
-- game's own too.
local function DayCount(civilDay, now)
	local days = DaysUntil(civilDay, now)
	if days > 0 then
		return " · " .. ns.TEXT.inDays:format(D_DAYS:format(days))
	elseif days == 0 then
		return " · " .. COMMUNITIES_CALENDAR_TODAY
	end
	return " · " .. (CURRENCY_TRANSFER_LOG_TIME_FORMAT or "%s ago"):format(D_DAYS:format(-days))
end

local function DayLine(civilDay, now)
	return DayText(civilDay) .. DayCount(civilDay, now)
end
ns.DayLine = DayLine

-- The same for a moment, on the day it falls on where the player is, with its time in the
-- player's own time zone until it has passed: "October 23, 19:00 · in 2 Days"; within a day only
-- a countdown, "in 04:12:33" (the user asked, 1.2.0: the date and time made it too busy); then
-- "October 23 · Today" and "October 23 · 2 Days ago". The time is the game's clock's
-- (GameTime_GetFormattedTime, its 12/24-hour setting).
local function MomentLine(moment, now)
	local day = LocalDay(moment)
	if now >= moment then
		return DayLine(day, now)
	end
	local left = moment - now
	if left < DAY then
		return ns.TEXT.inDays:format(string.format("%02d:%02d:%02d", math.floor(left / HOUR), math.floor(left / 60) % 60, math.floor(left % 60)))
	end
	local t = date("*t", moment)
	local time = GameTime_GetFormattedTime(tonumber(t.hour) or 0, tonumber(t.min) or 0, true)
	return DayText(day) .. ", " .. time .. DayCount(day, now)
end
ns.MomentLine = MomentLine

-- Whether the game named the player's region. The beta names none ("", seen in game, 1.2.0).
local function Known(region)
	return region ~= nil and region ~= ""
end

-- A milestone's moment in the player's region, or nil when it has only a date there.
local function MomentIn(milestone, region)
	return milestone.moment or (Known(region) and milestone[region]) or nil
end

-- A milestone's moment in each region Blizzard gave a time for, earliest first, when the
-- player's region isn't known and the times differ by region; nil otherwise. Regions with the
-- same time share a line (the user asked, 1.2.0): when only one line covers several regions,
-- it is everyone the other lines don't name, "Rest of the world"; otherwise their names.
local function RegionMoments(milestone, region)
	if milestone.moment or Known(region) or not milestone[REGIONS[1]] then
		return nil
	end
	local list, byMoment = {}, {}
	for _, key in ipairs(REGIONS) do
		local moment = milestone[key]
		local group = byMoment[moment]
		if not group then
			group = { moment = moment, regions = {} }
			byMoment[moment] = group
			list[#list + 1] = group
		end
		group.regions[#group.regions + 1] = key
	end
	table.sort(list, function(a, b)
		return a.moment < b.moment
	end)
	local shared = 0
	for _, group in ipairs(list) do
		if #group.regions > 1 then
			shared = shared + 1
		end
	end
	for _, group in ipairs(list) do
		if #group.regions == 1 then
			group.name = RegionName(group.regions[1])
		elseif shared == 1 then
			group.name = ns.TEXT.restOfWorld
		else
			local names = {}
			for i, key in ipairs(group.regions) do
				names[i] = RegionName(key)
			end
			group.name = table.concat(names, ", ")
		end
	end
	return list
end

-- Whether a milestone is behind: its moment has come (in every region, when the player's isn't
-- known), or its date has passed on the player's own calendar.
local function Passed(milestone, region, now)
	local regions = RegionMoments(milestone, region)
	if regions then
		return now >= regions[#regions].moment
	end
	local moment = MomentIn(milestone, region)
	if moment then
		return now >= moment
	end
	return DaysUntil(milestone.day, now) < 0
end
ns.Passed = Passed

-- A milestone's lines, each { text = ..., done = ... }: its moment or date, or, when the player's
-- region isn't known and the times differ by region, a line for each time, greyed and saying
-- "started" once that region's time has come (the user asked, 1.2.0).
local function MilestoneLines(milestone, region, now, done)
	local regions = RegionMoments(milestone, region)
	if regions then
		local lines = {}
		for i, entry in ipairs(regions) do
			local started = now >= entry.moment
			local format = started and ns.TEXT.regionStarted or ns.TEXT.regionLine
			lines[i] = { text = format:format(entry.name, MomentLine(entry.moment, now)), done = started }
		end
		return lines
	end
	local moment = MomentIn(milestone, region)
	local text = moment and MomentLine(moment, now) or DayLine(milestone.day, now)
	return { { text = text, done = done } }
end
ns.MilestoneLines = MilestoneLines

-- Days, hours, minutes and seconds left to launch. Once Forever has launched the clock stays at
-- zeros (the user asked, 1.1.0).
function ns.ClockParts(now)
	local left = ns.LAUNCH - now
	if left <= 0 then
		return 0, 0, 0, 0
	end
	local days = math.floor(left / DAY)
	local hours = math.floor(left / HOUR) % 24
	local minutes = math.floor(left / 60) % 60
	local seconds = left % 60
	return days, hours, minutes, math.floor(seconds)
end

-- A moment, from a date table (date's "*t"), as the game writes a date and a time: its full date
-- (FULLDATE, in the player's language and order) and its clock's time (GameTime_GetFormattedTime,
-- which follows the 12/24-hour setting as the clock by the minimap does): "Thursday, November 5
-- 2026, 01:00" or "..., 1:00 AM".
function ns.FormatMoment(t)
	local day = FULLDATE:format(WeekdayName(t.wday), MonthName(t.month), t.day, t.year)
	return day .. ", " .. GameTime_GetFormattedTime(t.hour, t.min, true)
end

-- The launch moment in the player's own time zone.
function ns.LaunchText()
	return ns.FormatMoment(date("*t", ns.LAUNCH))
end

-- Whether Forever has launched at a moment.
function ns.HasLaunched(now)
	return now >= ns.LAUNCH
end

-- What each row of the panel says at a moment: a title, the lines under it (each
-- { text = ..., done = ... }), and whether the milestone is behind (shown greyed like a finished
-- quest line). Before the launch its line is the launch moment in the player's own time; after
-- it, the launch's own local date with how many days ago, like the others (the user chose this,
-- 1.1.0). `region` is the player's (GetCurrentRegionName), for the start times that differ by
-- region.
function ns.Lines(now, region)
	local T = ns.TEXT
	local rows = {}
	local function Row(title, milestone, done)
		return { title = title, lines = MilestoneLines(milestone, region, now, done), done = done }
	end
	rows.betaBegan = Row(T.betaBegan, ns.BETA_START, true)
	-- A milestone with a start and an end: "starts" until its start, "ends" until its end, then
	-- "ended", greyed.
	local function Span(start, finish, starts, ends, ended)
		if not Passed(start, region, now) then
			return Row(starts, start, false)
		elseif not Passed(finish, region, now) then
			return Row(ends, finish, false)
		end
		return Row(ended, finish, true)
	end
	-- The stress test, between the beta's start and end (the user asked for its own row, 1.2.0).
	rows.stressTest = Span(ns.STRESS_TEST_START, ns.STRESS_TEST_END, T.stressTestStarts, T.stressTestEnds, T.stressTestEnded)
	local betaOver = Passed(ns.BETA_END, region, now)
	rows.betaEnds = Row(betaOver and T.betaEnded or T.betaEnds, ns.BETA_END, betaOver)
	rows.reservation = Span(ns.RESERVATION_START, ns.RESERVATION_END, T.reservationStarts, T.reservationEnds, T.reservationEnded)
	local launched = ns.HasLaunched(now)
	rows.launched = launched
	if launched then
		rows.launch = { title = T.launched, lines = { { text = DayLine(LocalDay(ns.LAUNCH), now), done = true } }, done = true }
	else
		rows.launch = { title = T.launches, lines = { { text = ns.LaunchText(), done = false } }, done = false }
	end
	return rows
end

-- The saved layout's version. Raise it only when a change stores the data differently, and
-- convert the older layout in NormalizeSaved.
local SAVE_FORMAT = 1
ns.SAVE_FORMAT = SAVE_FORMAT

local POINTS = {
	TOPLEFT = true, TOP = true, TOPRIGHT = true, LEFT = true, CENTER = true,
	RIGHT = true, BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true,
}
-- Offsets beyond this are no place on any screen.
local MAX_OFFSET = 10000

local function IsOffset(value)
	return type(value) == "number" and value == value and value >= -MAX_OFFSET and value <= MAX_OFFSET
end

-- Runs on every load with the saved ForeverCountdownDB and returns it rebuilt from the fields
-- the addon uses: the save format, whether the panel is minimized, and where the player moved
-- it (a point of the panel on the same point of the screen, and an offset), or no position
-- when it was never moved. Anything else, left by older versions or damaged, is dropped. A new
-- saved field has to be added here too, or it is dropped on the next load.
function ns.NormalizeSaved(old)
	local clean = { format = SAVE_FORMAT, minimized = false }
	if type(old) ~= "table" or old.format ~= SAVE_FORMAT then
		return clean
	end
	clean.minimized = old.minimized == true
	local position = old.position
	if type(position) == "table" and POINTS[position.point] and IsOffset(position.x) and IsOffset(position.y) then
		clean.position = { point = position.point, x = position.x, y = position.y }
	end
	return clean
end
