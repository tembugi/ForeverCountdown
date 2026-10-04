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

-- Blizzard announced the dates in Pacific time. Daylight saving time ends on November 1, 2026,
-- at 2:00 (09:00 UTC): before that Pacific time is UTC-7, after it UTC-8.
local DST_END = CivilDay(2026, 11, 1) * DAY + 9 * HOUR

-- The Pacific calendar day a moment (seconds since 1970, UTC) falls on, as days since 1970.
local function PacificDay(now)
	local offset = now < DST_END and 7 or 8
	return math.floor((now - offset * HOUR) / DAY)
end
ns.PacificDay = PacificDay

-- The milestones. The beta's last full day is October 21. Name reservation runs from
-- October 27 through November 3. Launch is November 4 at 3:00 p.m. Pacific (PST), 23:00 UTC.
ns.BETA_START = CivilDay(2026, 9, 17)
ns.BETA_END = CivilDay(2026, 10, 21)
ns.RESERVATION_START = CivilDay(2026, 10, 27)
ns.RESERVATION_END = CivilDay(2026, 11, 3)
ns.LAUNCH = CivilDay(2026, 11, 4) * DAY + 23 * HOUR

-- English, like the rest of the addon's own words. The game has no strings for these.
ns.TEXT = {
	countdownTo = "Countdown to",
	forever = "Forever",
	betaBegan = "Beta began",
	betaEnds = "Beta ends",
	betaEnded = "Beta ended",
	reservationStarts = "Name reservation starts",
	reservationEnds = "Name reservation ends",
	reservationEnded = "Name reservation ended",
	launches = "launches",
	launched = "launched",
	today = "Today",
}

local MONTHS = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" }

-- "Oct 21" for a calendar day, as Blizzard announced it (no time zone applies).
local function DayText(civilDay)
	local t = date("!*t", civilDay * DAY)
	return MONTHS[t.month] .. " " .. t.day
end
ns.DayText = DayText

-- Days from now to a Pacific calendar day: 0 on the day itself, negative once it has passed.
local function DaysUntil(civilDay, now)
	return civilDay - PacificDay(now)
end
ns.DaysUntil = DaysUntil

-- "Oct 21 · 17 Days", "Oct 21 · Today", or just "Oct 21" once the day has passed. D_DAYS is
-- the game's own "%d |4Day:Days;" (the game picks the singular or plural when it shows it).
local function DayLine(civilDay, now)
	local days = DaysUntil(civilDay, now)
	local text = DayText(civilDay)
	if days > 0 then
		return text .. " · " .. D_DAYS:format(days)
	elseif days == 0 then
		return text .. " · " .. ns.TEXT.today
	end
	return text
end
ns.DayLine = DayLine

-- Days, hours, minutes and seconds left to launch, or nil once Forever has launched.
function ns.ClockParts(now)
	local left = ns.LAUNCH - now
	if left <= 0 then
		return nil
	end
	local days = math.floor(left / DAY)
	local hours = math.floor(left / HOUR) % 24
	local minutes = math.floor(left / 60) % 60
	local seconds = left % 60
	return days, hours, minutes, math.floor(seconds)
end

-- A moment as "Thu, Nov 5, 1:00" or, with the game's 12-hour clock, "Thu, Nov 5, 1:00 AM",
-- from a date table (date's "*t") and the weekday's short name. The time uses the game's own
-- formats.
function ns.FormatMoment(t, weekday, twentyFourHours)
	local clock
	if twentyFourHours then
		clock = TIME_TWENTYFOURHOURS:format(t.hour, t.min)
	else
		local hour = t.hour % 12
		if hour == 0 then
			hour = 12
		end
		clock = (t.hour < 12 and TIME_TWELVEHOURAM or TIME_TWELVEHOURPM):format(hour, t.min)
	end
	return weekday .. ", " .. MONTHS[t.month] .. " " .. t.day .. ", " .. clock
end

-- The launch moment in the player's own time zone.
function ns.LaunchText(twentyFourHours)
	return ns.FormatMoment(date("*t", ns.LAUNCH), tostring(date("%a", ns.LAUNCH)), twentyFourHours)
end

-- What each line of the panel says at a moment: a title, the line under it, and whether the
-- milestone is behind (shown greyed like a finished quest line).
function ns.Lines(now)
	local T = ns.TEXT
	local lines = {}
	lines.betaBegan = { title = T.betaBegan, line = DayText(ns.BETA_START), done = true }
	local betaOver = DaysUntil(ns.BETA_END, now) < 0
	lines.betaEnds = { title = betaOver and T.betaEnded or T.betaEnds, line = DayLine(ns.BETA_END, now), done = betaOver }
	-- On October 27 itself it still says "starts · Today": Blizzard gave no time of day.
	if DaysUntil(ns.RESERVATION_START, now) >= 0 then
		lines.reservation = { title = T.reservationStarts, line = DayLine(ns.RESERVATION_START, now), done = false }
	elseif DaysUntil(ns.RESERVATION_END, now) >= 0 then
		lines.reservation = { title = T.reservationEnds, line = DayLine(ns.RESERVATION_END, now), done = false }
	else
		lines.reservation = { title = T.reservationEnded, line = DayText(ns.RESERVATION_END), done = true }
	end
	lines.launched = ns.ClockParts(now) == nil
	return lines
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
