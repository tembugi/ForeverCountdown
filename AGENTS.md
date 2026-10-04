# Forever Countdown

Rules for this addon. The shared rules are in `../AGENTS.md`.

A panel in the objective tracker's style that counts down to World of Warcraft Forever's launch, with the beta's end and name reservation on the way. Agreed with the user on the design canvas (board Z9 with the "Forever launches in" minimized bar, 2026-10-05). Folder, repo and packages are `ForeverCountdown`. No GitHub repo or CurseForge project yet: ask before creating either.

## Dates

From Blizzard's announcements, in `Countdown.lua`. Everything the player sees is in their own time, computed from the official times (the user asked, 1.0.0):
- Launch: November 4, 2026 at 3:00 p.m. PST (UTC-8), so 23:00 UTC, one moment the world over. The clock counts to it with `GetServerTime()` (the realm's clock, right even when the computer's is off), and the launch line shows it in the player's own time zone with `date` and the game's 12/24-hour setting (Helsinki sees Thu, Nov 5, 1:00; California Wed, Nov 4, 3:00 PM).
- Beta began: September 17, 2026. Beta ends: October 21, 2026, the beta's last full day. Name reservation: October 27 through November 3, 2026; until October 27 (and on that day) the line says "Name reservation starts", then "Name reservation ends" with November 3.
- These have only a Pacific date, no time of day, so they can't become a local moment: the date shows as announced, and days are counted on the player's own calendar, so on that date the line says "Today" wherever the player is. (With Pacific days, "Today" started at 10:00 in Finland, 0.1.x.)
- Tests check players in time zones from UTC-10 to UTC+13 with a stand-in for `date` at fixed offsets.
- A date or time that changes needs a new release. When Blizzard announces a time of day for the beta's end or name reservation, ask the user whether to count those down to the second too.

## Look

The tracker's own pieces, read from the game while it runs, with Blizzard's values (from `ObjectiveTrackerModuleHeaderTemplate`) only as fallbacks:
- Width: at least a tracker section's 260, and wide enough for the longest line (the header with its clock and button, or "Forever launches"), measured from the texts once they are made. The same width open and minimized (the user asked, 0.1.1). The header is 26 tall with `UI-QuestTracker-Secondary-Objective-Header` art and the section minimize button (`UI-QuestTrackerButton-Secondary-Collapse`/`-Expand`, yellow highlight).
- Fonts and sizes: the tracker's own font objects as they are, `ObjectiveTrackerHeaderFont` for every header word and `ObjectiveTrackerLineFont` for the rows, so they follow its Text Size setting (Edit Mode swaps the font behind both; the user asked for the tracker's sizes, 0.1.2). The clock figures are 3 larger than the header font. The rows stack by their text's height, and a hook on `ObjectiveTrackerManager.SetTextSize` re-measures the clock, the width and the height on the next frame; colors from `OBJECTIVE_TRACKER_COLOR` (Normal for lines, Complete for what is behind). Titles and the header's gold words use the game's bright gold, `NORMAL_FONT_COLOR` (the tracker's highlight gold): its resting Header gold read too dim in game (the user, 0.1.1).
- The header reads "Countdown to" (gold) then "Forever", both in the header font.
- Every "Forever" is white with a pale-blue glow that rises and fades (the word in pale blue a pixel out in eight directions behind it; the game's outlines are always black). A gleam sweeping across the word was dropped after the user saw it in game (0.1.1).
- Rows, as quests show in the tracker: a marker on the left, a title, and a dashed line under it (`QUEST_DASH`). What is behind is greyed (Complete).
  - "!" (the game's `QuestNormal` art), greyed and still: Beta began.
  - "?" (`QuestTurnin`): Beta ends. It wiggles from side to side on its base for attention, then rests, as a plain-Lua Rotation animation group (the user asked for a wiggle, not a bounce; turning the texture with `SetRotation` didn't show in game, 0.1.2). It stops once the beta is over.
  - A quill drawn in gold, writing a line of ink: Name reservation. The game has no quill art.
  - The infinity sign as a calligraphic silver ribbon (thick across a slanted nib, thin along it, dark edge, one strand over the other at the crossing): Forever launches. It is `Infinity.tga` (128 x 64), drawn by `Art/make_art.py` (shape A, chosen by the user from real-size previews, 0.1.12), shown 24 units wide centered in the icon column. Drawn in game from Line objects it never showed (0.1.0 to 0.1.3), and from ~200 small discs it wobbled (0.1.4 to 0.1.12); the user then removed the shared no-bundled-art rule (2026-10-05). A light slides along it: a section of the ribbon lighting up (additive discs as wide as the ribbon over a faint halo 2.4 wider, brightest mid-section, fading at both ends, dimmed where it passes under the crossing); a single white disc read as a ball (0.1.11). The quill is still drawn from discs of the game's round soft texture (`Interface\CharacterFrame\TempPortraitAlphaMask`), unsnapped.
- The clock sits in the header after "Countdown to Forever", centered on it, 8 units after "Forever", open and minimized (the user asked, 0.1.17; it used to sit beside "Forever launches" while open). "Forever launches" has the launch date and time under it in the player's time zone and the game's 12/24-hour clock setting (`timeMgrUseMilitaryTime`, `TIME_TWELVEHOURAM`/`PM`, `TIME_TWENTYFOURHOURS`).
- The clock: days, hours, minutes and seconds in bold white, the tracker's header font with a black outline, 3 larger than the header text, with gold colons 4 larger than the figures, raised so their dots sit at the figures' middle, that stay still. Each pair of figures and each colon is its own self-sizing text, and each follows the one before it at a 1-unit gap; the game places them by their drawn size (the user asked for even gaps and readable colons, 0.1.6). Widths the addon measured itself came out wrong in game and spread the clock apart (0.1.4, 0.1.6), so no clock text is given a width. The clock is centered on the title (the user's choice, 0.1.14; a shared baseline in 0.1.8 and aligned tops in 0.1.9 were tried and dropped). The seconds fade in as they tick. Minimizing fades the rows (alpha) instead of hiding them.
- Days use the game's `D_DAYS`: an upcoming date reads "Oct 27 · in 22 Days" ("in %s" is the addon's own; the game has no such string; the user asked, 0.1.16); "Today" on the day itself; a date that has passed reads "Sep 17 · 18 Days ago" with the game's "%s ago" (`CURRENCY_TRANSFER_LOG_TIME_FORMAT`), the user asked for it on Beta began (0.1.15).
- Minimized (the minimize button): only the header, "Countdown to Forever" and the clock, as when open (the user chose this over "Forever launches in", 0.1.3). After launch the clock is gone.
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
