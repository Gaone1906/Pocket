# Calendar

## What it is
A read-only month view of the events in the Mac's Calendar (EventKit). It covers every calendar the user has (iCloud, Google, Exchange and so on), as configured in Calendar.app.

- **Catalog:** `id: "calendar"`, symbol `calendar`, shortcut ⌥D (`kVK_ANSI_D`). It has no glyph and no badge.
- **Panel:** fixed 560×620, not resizable (`CalendarApp.resizable = false`).
- **Layout:**
  - a header with the month title, ‹, "Today" and ›;
  - a weekday row that respects `Calendar.current.firstWeekday`;
  - a 6×7 grid in which each cell shows the day number (today is a filled accent circle), up to 2 event titles with colour dots, and "+N" for the rest;
  - a divider, then the selected day's list ("All day" or "start – end", with a calendar-colour bar).
- **Navigation:** clicking a day selects it, and clicking a spill-over day jumps to its month. A trackpad or mouse scroll over the panel changes month: scrolling down goes forward, scrolling up goes back.
- **Not to be confused with** Schedule's Calendar view (`ScheduleBoard.swift`). That one is unrelated and doesn't use EventKit.

## Files
All in `Sources/Pocket/CalendarApp.swift`.

| Symbol | Role |
| --- | --- |
| `CalendarEntry` | A view model: `title`, `start`, `end`, `allDay`, and `color` from `EKCalendar.cgColor`. Its `id` is a fresh `UUID()` on every fetch |
| `CalendarAccess` | `.granted`, `.undetermined` or `.denied`. `CalendarModel.currentAccess()` maps `.fullAccess`/`.authorized` to granted, `.notDetermined` to undetermined, and everything else (including `.writeOnly`) to denied |
| `CalendarModel` (`ObservableObject`) | Holds `visibleMonth`, `selectedDay`, `eventsByDay: [Date: [CalendarEntry]]` (keyed by start of day) and `access`. Grid maths: `gridStart`, `gridDays` (42 days), `weekdaySymbols`. Navigation: `shiftMonth(by:)`, `goToToday()`, `select(_:)`, `showMonth(of:preferredDay:)`. Loading: `fetch()`, `bucket(...)`, `activate()`, `startObserving()`/`stopObserving()`. Access: `requestAccess()`, `openPrivacySettings()` |
| `ScrollMonthStepper` | Turns scroll events into ±1 month steps. It sums the deltas (non-precise wheels are multiplied by 10) up to a threshold of 30. Then it locks until the gesture or momentum ends, so one swipe moves exactly one month; a classic wheel can step repeatedly |
| `CalendarRoot`, `DayCell`, `EntryRow` | SwiftUI views. `CalendarRoot` switches on `access`: the grid, an "Allow Calendar access" button, or "Open Privacy Settings" |
| `CalendarApp` | The `PocketApp` subclass. It has a `static let store = EKEventStore()` and a static `requestAccess(done:)`, plus `start`, `didShow`, `didHide`, `stop` and the scroll monitor |

Related: `Sources/Pocket/Setup.swift` (`SetupModel.requestCalendar()`) has its own `EKEventStore` and asks for access during setup step 2. `Resources/Info.plist` carries `NSCalendarsFullAccessUsageDescription` and `NSCalendarsUsageDescription`.

## Data
- **Nothing is persisted, and nothing goes through `DataVault`.** Events are read live from EventKit, and the model is in memory only.
- The visible month and selected day reset to today at each launch, because `CalendarModel.init` runs then.
- It doesn't use `POCKET_DATA_DIR`; it has no files.

## Flows
- **Start** (`CalendarApp.start`): `model.startObserving()` subscribes to `.EKEventStoreChanged` on `CalendarApp.store`. When the store changes:
  - if the panel is shown, it calls `fetch()`;
  - otherwise it sets `isDirty = true`.
- **Open** (`didShow`):
  1. It installs a local `scrollWheel` monitor, which only acts when the event's window is this panel and access is granted.
  2. `model.activate()` re-reads the authorisation status. If granted, it fetches when this is the first open (`!hasLoaded`) or when the store changed while hidden (`isDirty`). Otherwise it reuses the cached `eventsByDay`.
- **Hide** (`didHide`) removes the scroll monitor.
- **Stop** (when disabled, or on quit) removes the monitor, stops observing and tears down the panel.
- **Fetch** (`fetch()`):
  1. It skips with a log line if access isn't granted.
  2. It increments `generation` (a ticket), so stale results are dropped when the user flips months quickly.
  3. The range is `gridStart` to `gridStart + 42 days`, the whole visible grid including spill-over days.
  4. On the serial `pocket.calendar.fetch` queue (`.userInitiated`) it runs `predicateForEvents(withStart:end:calendars: nil)` (every calendar) and `events(matching:)`, then buckets the results.
  5. Back on main it publishes them if the ticket is still current.
- **Bucketing:**
  - a multi-day event is added to every day from `max(startOfDay(start), rangeStart)` to `startOfDay(end - 1s)`, so an event ending exactly at midnight doesn't spill into the next day;
  - each day is sorted with all-day events first, then by start time.
- **Month navigation.** Each of `shiftMonth`, `goToToday` and `select` (for an out-of-month day) calls `showMonth`, which always fetches. If the selected day isn't in the new month, selection moves to today when today is in that month, else to the 1st.
- **Permissions:**
  - **Setup** calls `SetupModel.requestCalendar()` (`requestFullAccessToEvents` on the setup store) and logs `pocket setup calendar access …`.
  - **The panel**, in the `.undetermined` state, calls `CalendarApp.requestAccess`, which calls `requestFullAccessToEvents` on the shared store. When granted it calls `store.reset()`, so the shared store sees calendars that it created before access was granted, and the panel then fetches.
  - **Denied** opens `x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars`.
  - A grant made in System Settings while the panel is closed is picked up on the next `activate()`.
- **Wake and timers.** There are none. Freshness depends on `EKEventStoreChanged` and on opening the panel.

## Integrations
EventKit, read-only (`requestFullAccessToEvents`, macOS 14 API). The user must grant **Full Access**: write-only access maps to `.denied`, which shows "Calendar access is turned off". Pocket never writes events.

## Logging
- `pocket calendar fetch skipped month=YYYY-MM reason=no access`
- `pocket calendar fetched month=YYYY-MM events=<n>`. `n` is the raw EventKit count for the 42-day range, before bucketing.
- `pocket calendar access requested granted= error=`
- `pocket setup calendar access granted= status= error=` (from `Setup.swift`)

## Gotchas
- **Stale "today" across midnight.** If the panel stays open past midnight (or across days without a store change), the cached data is fine, because it's keyed by date. However, `selectedDay` and `visibleMonth` keep their old values until the user presses Today; they're only set in `init` and by navigation.
- **Cache staleness.** `activate()` refetches only when `isDirty`. Events that move into range purely through time passing are unaffected, because the range is fixed per month, so this is fine in practice.
- **Two `EKEventStore`s.** `SetupModel.store` and `CalendarApp.store` are separate. Only `CalendarApp.requestAccess` resets the shared store after a grant. A grant made from Setup relies on `EKEventStore` noticing on its own; if events are missing after a fresh grant in Setup, that is the suspect (unverified).
- **Entry ids.** `CalendarEntry.id` is regenerated on every fetch, so SwiftUI re-creates the rows. That's harmless at this scale.
- **The scroll monitor is app-local.** It only receives scroll events while Pocket is active, and it passes every event through (`return event`), so the day list's `ScrollView` also scrolls when the pointer is over it. Scrolling a long day list can therefore flip months too.

## How to change it safely
- **Add a field** (location, notes): extend `CalendarEntry`, fill it in `bucket`, and render it in `EntryRow`. Keep the work in `bucket` off main.
- **Filter calendars:** pass a `[EKCalendar]` instead of `nil` to `predicateForEvents`, and persist the choice in a new UserDefaults key, e.g. `calendar.hidden`. Add a log field for the count of calendars used.
- **Change the grid size:** `gridDays` (42), the `ForEach(0..<6)` in `monthGrid`, and `rangeEnd` in `fetch` must agree.
- **Testing:** there's no data dir to redirect. Test against a throwaway calendar in Calendar.app; the code is read-only, so it can't damage data.

## Open questions / known gaps
- There's no event creation, no detail view, and no click-through to Calendar.app.
- No refresh at midnight or on wake.
- Write-only access isn't distinguished from denied in the UI.
