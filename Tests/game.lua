-- What the addon uses from the game outside its frames, as the game has it, for Tests/run.lua
-- and Tests/standin.lua: `local game = dofile("Tests/game.lua")`.

-- This file runs under luajit, outside the game, and uses standard Lua's os, which the game
-- doesn't have. It plays the game, so it sets the game's globals.
---@diagnostic disable: undefined-global, lowercase-global, create-global

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
COMMUNITIES_CALENDAR_TODAY = "Today"
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

return { InZone = InZone, WithClock = WithClock }
