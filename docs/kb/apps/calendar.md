# Calendar

## What it is
Pocket's own calendar. Events live in Pocket's vault, not in the Mac's Calendar app: there is no EventKit and no Calendars permission any more.

- **Catalog:** `id: "calendar"`, symbol `calendar`, shortcut ⌥D (`kVK_ANSI_D`). No glyph, no badge.
- **Dropdown:** fixed 400×600, not resizable. Month title with year, Today (when away from the current month), ‹ ›, + (new event on the selected day) and expand. A 6×7 grid of day cells with up to three colour dots each; today has an accent edge, the selected day an accent fill; double-click a day to add an event. Below a hairline, the selected day's agenda ("TODAY · …"), each row showing the colour bar, title, time, location, repeat and a bell when an alert is set. Clicking a row opens it in the window's editor.
- **Expanded window** (`CalendarBoardWindow`, 1080×720, min 760×560, autosaved as `calendar.board`): sidebar (TODAY and THIS WEEK counts, UP NEXT list of the next six occurrences, ALERTS default for new events, and a link to Notification Settings when notifications are off); top bar with the sidebar toggle, a Month / Week glass toggle, the range title, Today, ‹ ›, and **New event**.
  - **Month:** 6×7 cells that grow with the window, chips per event (all-day as tinted pills, timed with a dot and start time), "+N more" when they don't fit. Click selects, double-click adds, click a chip to edit.
  - **Week:** day headers, an all-day strip, and a scrolling 24-hour grid (48pt per hour, opens at 7 AM) with events as tinted blocks laid out in lanes when they overlap, plus a now line in today's column. Double-click an hour to add an event there.
  - **Editor** (`CalendarEditorCard`, 470pt overlay): title, All day, Starts/Ends (date and time, or days), 30 m / 1 h / 1½ h shortcuts, Repeat, Until, Alert, Colour (the theme's 8 tints), Location and Notes. Delete asks for a second click and removes every repeat of the event.
- **Theme:** everything draws with the shared `Board` tokens and `BoardBackdrop`, observes `BoardThemeStore.shared`, and the AppKit hosts follow `$theme`. Calendar has no theme picker of its own.

## Files

| File | Symbols |
| --- | --- |
| `CalendarModel.swift` | `CalendarEvent`, `CalendarBook`, `CalendarRepeat`, `CalendarOccurrence`, `CalendarDays` (date helpers, uses `Calendar.current`), `CalendarAlertChoice`, `CalendarPersistence` and `CalendarVaultPersistence`, `CalendarStore`, `CalendarAlerts` |
| `CalendarApp.swift` | `CalendarDropdownState`, `ScrollMonthStepper`, `CalendarDropdown`, `CalendarAgendaRow`, `CalendarApp` |
| `CalendarBoard.swift` | `CalendarBoardRequest` (`browse`, `create`, `edit`), `CalendarBoardMode`, `CalendarDraft`, `CalendarBoardState`, `CalendarBoardWindow`, shared bits (`CalendarSectionTitle`, `CalendarHairline`, `CalendarGlass`, `CalendarCircleChip`, `CalendarAccentButton`), sidebar, month and week views, `CalendarBoardView` |
| `CalendarEditor.swift` | `CalendarEditorCard` |

## Data
- `$ROOT/calendar.json`, vault name `calendar`, noun "event", `{"events": [...]}` with ISO 8601 dates. Fields are listed in `CLAUDE.md` → Calendar app. Decoding tolerates missing fields.
- Loading: the file, else quarantine it and recover from the newest readable snapshot, else start empty. Every save writes atomically and snapshots through `DataVault`.
- `CalendarStore` only talks to `CalendarPersistence` (`load`, `save`, `onIncoming`, `keepAside`). Swap the implementation to change where events live; the views never touch files.
- Merge (from "Bring them in", or any other incoming copy): keep aside, then union by id where the newer `updated` wins. Deletions don't travel through a merge, so a deleted event can come back if the other copy still has it.
- Repeats are expanded on read (`CalendarStore.expand`), stepping from the original start so monthly events on the 31st land on the last day of shorter months. Edits and deletes apply to the whole series.
- UserDefaults: `calendar.board.mode` (`month` or `week`), `calendar.board.sidebar`, `calendar.alert.default` (minutes, -1 for none, default 10), and `size.calendar` is unused because the panel isn't resizable.

## Alerts
- `CalendarAlerts.schedule` removes every pending request whose id starts with `pocket.calendar.` and adds one `UNCalendarNotificationTrigger` per occurrence whose fire time falls in the next 14 days, earliest first, at most 48.
- Timed events fire `alert` minutes before the start; all-day events at 9 AM on the day (`0`) or 9 AM the day before (`1440`).
- Rebuilt at app start, after every add/update/delete/merge, when the day changes, and when the 60-second clock finds the last rebuild over 6 hours old. Clicking a notification opens the dropdown (`userInfo["app"] = "calendar"`).
- `stop()` clears them only when Calendar has been disabled (it is no longer in `Layout.enabled`), so quitting Pocket leaves them to fire.
- Without a bundle id (a bare `.build` binary) scheduling is skipped and logged.

## Logging
- `calendar loaded|recovered|started empty|load failed|save failed ... path=`
- `calendar event added|updated|deleted id= start= allDay= repeats= alert= events=`
- `calendar merged added= newer= events=` and `calendar incoming unreadable`
- `calendar alerts scheduled trigger= count= removed= failed= next=`, `calendar alert failed id=`, `calendar alerts cleared`, `calendar alerts skipped reason=no bundle`
- `calendar board requested|opened|refocused|closed`, `calendar board view mode=`, `calendar editor opened new=`, `calendar editor rejected`, `calendar default alert minutes=`, `calendar day changed`

## How to change it safely
- **Add an event field:** add it to `CalendarEvent` with a default and a `decodeIfPresent` line, then show it in `CalendarEditorCard`. Old files keep loading.
- **New repeat rule:** add a `CalendarRepeat` case with `label`, `short` and `step`; filter in `expand` if it skips days (as `weekdays` does).
- **Another backend:** implement `CalendarPersistence` and build the store with it (`CalendarStore(persistence:)`). Keep `DataVault` snapshots if the data stays on disk.
- **Screenshots:** construct `CalendarStore` with an in-memory persistence and render `CalendarDropdown` / `CalendarBoardView` offscreen as described in [operations.md](../operations.md); nothing touches real data.

## Open questions
- No "this occurrence only" edit or delete for repeating events.
- No drag to move or resize events in the week view.
- No import from the Mac's Calendar or from `.ics` files.
