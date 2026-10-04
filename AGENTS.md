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
- Width: at least a tracker section's 260, and wide enough for the longest line ("Forever launches" with the clock beside it, or the minimized header with its clock and button), measured from the texts once they are made. The same width open and minimized (the user asked, 0.1.1). The header is 26 tall with `UI-QuestTracker-Secondary-Objective-Header` art and the section minimize button (`UI-QuestTrackerButton-Secondary-Collapse`/`-Expand`, yellow highlight).
- Fonts and sizes: the tracker's own font objects as they are, `ObjectiveTrackerHeaderFont` for every header word and `ObjectiveTrackerLineFont` for the rows, so they follow its Text Size setting (Edit Mode swaps the font behind both; the user asked for the tracker's sizes, 0.1.2). The clock figures are 3 larger than the header font. The rows stack by their text's height, and a hook on `ObjectiveTrackerManager.SetTextSize` re-measures the clocks, the width and the height on the next frame; colors from `OBJECTIVE_TRACKER_COLOR` (Normal for lines, Complete for what is behind). Titles and the header's gold words use the game's bright gold, `NORMAL_FONT_COLOR` (the tracker's highlight gold): its resting Header gold read too dim in game (the user, 0.1.1).
- The header reads "Countdown to" (gold) then "Forever", both in the header font.
- Every "Forever" is white with a pale-blue glow that rises and fades (the word in pale blue a pixel out in eight directions behind it; the game's outlines are always black). A gleam sweeping across the word was dropped after the user saw it in game (0.1.1).
- Rows, as quests show in the tracker: a marker on the left, a title, and a dashed line under it (`QUEST_DASH`). What is behind is greyed (Complete).
  - "!" (the game's `QuestNormal` art), greyed and still: Beta began.
  - "?" (`QuestTurnin`): Beta ends. It wiggles from side to side on its base for attention, then rests, as a plain-Lua Rotation animation group (the user asked for a wiggle, not a bounce; turning the texture with `SetRotation` didn't show in game, 0.1.2). It stops once the beta is over.
  - A quill drawn in gold, writing a line of ink: Name reservation. The game has no quill art.
  - The infinity sign drawn from lines as a calligraphic silver ribbon (thick across a slanted nib, thin along it, dark edge, one strand over the other at the crossing), with a light running around it: Forever launches. Its glow read as a white smudge in game and was dropped (0.1.7). The game's only infinity art is 15 x 9. It is 24 wide, centered in the icon column, with strokes of 1.1 to 2.2 units (at 30 it ran into "Forever", 0.1.4). The infinity sign and the quill are drawn as overlapping discs of the game's round soft texture (`Interface\CharacterFrame\TempPortraitAlphaMask`) along their curves: drawn with Line objects (0.1.0 to 0.1.3) they never showed in game, and a square light looked like a rectangle (0.1.4).
- "Forever launches" has the clock to its right, centered on the line, with the launch date and time under it in the player's time zone and the game's 12/24-hour clock setting (`timeMgrUseMilitaryTime`, `TIME_TWELVEHOURAM`/`PM`, `TIME_TWENTYFOURHOURS`).
- The clock: days, hours, minutes and seconds in bold white, the tracker's header font with a black outline, 3 larger than the header text, with gold colons 4 larger than the figures, raised so their dots sit at the figures' middle, that stay still. Each pair of figures and each colon is its own self-sizing text, and each follows the one before it at a 1-unit gap; the game places them by their drawn size (the user asked for even gaps and readable colons, 0.1.6). Widths the addon measured itself came out wrong in game and spread the clock apart (0.1.4, 0.1.6), so no clock text is given a width. The clock shares the baseline of the text beside it: centered, its larger figures stood about 1.3 units low in game (0.1.7), so it is raised by 0.27 of the size difference. The seconds fade in as they tick. Minimizing fades the rows and the minimized clock (alpha) instead of hiding them.
- Days use the game's `D_DAYS`; "Today" on the day itself.
- Minimized (the minimize button): only the header, still reading "Countdown to Forever", with the clock after it (the user chose this over "Forever launches in", 0.1.3). After launch the clock is gone.
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
