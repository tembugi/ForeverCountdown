# Forever Countdown

Rules for this addon. The shared rules are in `../AGENTS.md`.

A panel in the objective tracker's style that counts down to World of Warcraft Forever's launch, with the beta's end and name reservation on the way. Agreed with the user on the design canvas (board Z9 with the "Forever launches in" minimized bar, 2026-10-05). Folder, repo and packages are `ForeverCountdown`. No GitHub repo or CurseForge project yet: ask before creating either.

## Dates

From Blizzard's announcements, in `Countdown.lua`. Blizzard gave times of day only for the launch, so the other milestones count whole Pacific calendar days (the user chose days until times are known).
- Beta began: September 17, 2026 (always shown as done).
- Beta ends: October 21, 2026, the beta's last full day.
- Name reservation: October 27 through November 3, 2026. Until October 27 (and on that day) the line says "Name reservation starts", then "Name reservation ends" with November 3.
- Launch: November 4, 2026 at 3:00 p.m. PST (23:00 UTC), counted down to the second.
- Days are Pacific days: daylight saving time ends November 1, 2026 at 09:00 UTC (UTC-7 before, UTC-8 after). The clock uses `GetServerTime()`.
- A date or time that changes needs a new release. When Blizzard announces a time of day for the beta's end or name reservation, ask the user whether to count those down to the second too.

## Look

The tracker's own pieces, read from the game while it runs, with Blizzard's values (from `ObjectiveTrackerModuleHeaderTemplate`) only as fallbacks:
- Width: the objective tracker's (`ObjectiveTrackerFrame`), else 260. The header is 26 tall with `UI-QuestTracker-Secondary-Objective-Header` art and the section minimize button (`UI-QuestTrackerButton-Secondary-Collapse`/`-Expand`, yellow highlight).
- Fonts: `ObjectiveTrackerHeaderFont` for the header and `ObjectiveTrackerLineFont` for the lines; colors from `OBJECTIVE_TRACKER_COLOR` (Header for titles, Normal for lines, Complete for what is behind).
- The header reads "Countdown to" (gold, 0.9 of the header font) then "Forever".
- Every "Forever" is white and shines: a pale-blue glow that rises and fades (the word in pale blue a pixel out in eight directions behind it; the game's outlines are always black) and a gleam sweeping across it. The game can't light the inside of letters, so the gleam lights the word's box.
- Rows, as quests show in the tracker: a marker on the left, a title, and a dashed line under it (`QUEST_DASH`). What is behind is greyed (Complete).
  - "!" (the game's `QuestNormal` art), greyed and still: Beta began.
  - "?" (`QuestTurnin`): Beta ends. It shakes from side to side for attention, then rests (the user asked for a shake, not a bounce).
  - A quill drawn from lines in gold, writing a line of ink: Name reservation. The game has no quill art.
  - The infinity sign drawn from lines as a calligraphic silver ribbon (thick across a slanted nib, thin along it, dark edge, one strand over the other at the crossing), with a light running around it and a pulsing glow: Forever launches. The game's only infinity art is 15 x 9.
- "Forever launches" has the clock to its right, centered on the line, with the launch date and time under it in the player's time zone and the game's 12/24-hour clock setting (`timeMgrUseMilitaryTime`, `TIME_TWELVEHOURAM`/`PM`, `TIME_TWENTYFOURHOURS`).
- The clock: days, hours, minutes and seconds in the game's heavy number font (`NumberFont_Outline_Huge`'s), white, with gold colons that stay still. Each figure sits in a box as wide as the widest figure, so it doesn't jiggle. The seconds fade in as they tick.
- Days use the game's `D_DAYS`; "Today" on the day itself.
- Minimized (the minimize button): only the header, reading the shining "Forever", "launches in" (the size of "Countdown to") and the clock. After launch: "Forever launched".
- Unit labels under the clock, progress bars, paw prints, window borders, close buttons and stamps were tried on the canvas and rejected.
- Look changes are mocked on the design canvas first (https://claude.ai/artifact/TP8ZFtWEZYej4VEp7DwVKh) and built after the user picks.

## Behavior

- The panel can be dragged by its header anywhere on the screen; the place is saved. Until it is moved, it sits left of the minimap.
- One OnUpdate drives everything that moves, and the game runs it only while the panel is shown. The texts change once a second. Nothing else runs.
- No slash commands, options or tooltips (none asked for).

## Saved data

`ForeverCountdownDB` (account-wide): the save format, whether the panel is minimized, and where it was moved (a point of the panel on the same point of the screen, and an offset). `NormalizeSaved` rebuilds it on every load.

## Chat

- Every line starts with "Forever Countdown:" in gold.
- The addon writes only when something stopped working: if the animation driver fails, the error goes to the game's error handler, the panel stops updating, and chat says so once.
