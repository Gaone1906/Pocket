# Orario

Orario (named Schedule until 2026-11-19; code, ids and files still say `schedule`) is a weekly-routine tracker. It shows today's morning or night checklist in a dropdown and has a board window with Schedule and Calendar views. It was built on branch `add-schedule` on 2026-11-19 (`git log main..add-schedule`, commits `4882c90`…`f4892b9`).

The app comes from a claude.ai artifact, "Weekly Hair Routine" (https://claude.ai/artifact/NNyccJSEfqq9La5mhfb39i). `ScheduleSeed.hairCare()` is that routine translated into code.

Related files: [../architecture.md](../architecture.md) (PocketApp, catalog, hotkeys), [../data-and-backups.md](../data-and-backups.md) (DataVault), [../theme.md](../theme.md) (`Board` tokens), [pomodoro.md](pomodoro.md) (the board this one copies), [../operations.md](../operations.md) (render harness, `POCKET_DATA_DIR`).

## What it is

| | |
| --- | --- |
| Catalog entry | `AppSpec(id: "schedule", name: "Orario", symbol: "sun.horizon", hotKey: kVK_ANSI_O, claimsHotKey: true, pinnedByDefault: true)` in `Catalog.swift` |
| Default shortcut | **⌥O**, taken from Outlook. Outlook now has `hotKey: nil`. See [Shortcut migration](#shortcut-migration). |
| Menu-bar icon | SF Symbol `sun.horizon`, with a red badge counting the **unchecked steps in the current slot** of today, for the routines the filter shows (`ScheduleApp.remaining`). There is no badge at 0. |
| Placement | The app is pinned to the menu bar, not the dropdown tray, on existing installs too (`pinnedByDefault`). |
| Dropdown | 380×560, fixed (`defaultSize` = `minSize`, `resizable` false). |
| Right-click menu | "Open schedule", which opens the board window. |
| Board window | 1000×660 to start, min 720×480, resizable. Frame autosave name `schedule.board`. |

**Dropdown** (`ScheduleDropdown`), from top to bottom:
- **Header:** the date ("Thursday 19 Nov"), a slot capsule (☀ Morning / ☾ Night), the routine filter menu, and an expand button (`arrow.up.left.and.arrow.down.right`) that opens the board.
- **The current slot's card** (`ScheduleSlotCard`): a "THIS MORNING" / "TONIGHT" heading, "N of M done", a progress bar, and the checklist.
  - Each row has a round checkbox. Tapping the title also toggles it.
  - A chevron reveals the step's tip. Tips are open per item, held in `@State tips`, so they are not persisted.
  - The footer reads "Mark all done", or "All done" once everything is checked.
- **The other slot**, collapsed (`ScheduleFold`). It sits above the card when it is morning and below it when it is night. Its summary reads "· 3 steps" or "· 1 of 3 done", and it expands in place.
- **Routine tags:** when the filter is "All routines" and there is more than one routine, each row carries a coloured routine-name tag.
- **Footer** (`ScheduleTallyLine`): "N days done · M missed since 19 Nov". M is missed + partial.
- **Empty state:** with no routines, `ScheduleNoRoutines` shows an "Open the board" button.

**Board window** (`ScheduleBoardView`):
- **Top bar:** a sidebar toggle, the **Schedule | Calendar** toggle (`ScheduleModeToggle`, liquid-glass on macOS 26 with a material fallback), the routine picker (`ScheduleRoutinePicker`), and a preferences button on the right.
- **Sidebar** (`ScheduleSidebar`, 220 wide), from top to bottom:
  - **TODAY card:** the current slot plus "N of M steps done", or "All done for now!", or "Rest / nothing planned".
  - **SINCE <FIRST DAY> card:** days done and days missed. Partial days count as missed.
  - **SETTINGS:** "Change the schedule" opens the editor overlay. "Preferences" toggles the right panel.
- **Schedule view** (`ScheduleDayView`): a title row (day or week-range title, then the **Today | This week** toggle `ScheduleSpanToggle`), then:
  - **Day span:** the week strip (`ScheduleWeekStrip`: 7 chips Mon–Sun with a status dot each, plus week arrows), the title, then Morning and Night cards (`ScheduleSlotCard`, the board's private one).
    - The cards sit side by side when the view is ≥680 wide and stack when it is narrower.
    - Rows show the tip inline and can be toggled for past days and today. Future days are disabled.
    - Each card has a "Mark all done" / "Undo all" button.
  - **Week span:** the strip is hidden, the week arrows (`ScheduleWeekNav`) move next to the toggle, and `ScheduleWeekGrid` shows every step.
    - It has 7 columns when the view is ≥700 wide, and one row per day otherwise.
    - Done steps get a pastel green tint (`ScheduleTint.done`).
    - Unchecked steps in a slot whose status is `.missed` or `.partial` get a pastel red tint (`ScheduleTint.missed`).
    - Clicking a day header jumps to that day in Day span.
  - **NOTES card** (`ScheduleNotesCard`) under both spans: the notes of each shown routine.
- **Calendar view** (`ScheduleCalendarView`): a month title, "This month" when you are elsewhere, arrows, a "N done · M missed" line for the month, then a Mon-first grid.
  - The grid is built from **fixed `HStack` rows of 7**, not a `LazyVGrid`.
  - Each day is a 68pt cell showing a split mark (`ScheduleSplitMark`: left half morning, right half night), **only up to today**.
  - Clicking a day opens it in the Schedule view, Day span.
  - Months range from the month of `firstDay` to next month.
- **Preferences panel** (`SchedulePrefsPanel`, 280 wide, on the right):
  - **DAY:** a "Night routine from" hour stepper, plus an explanation of the 4 AM day boundary.
  - **THEME:** swatches from `BoardTheme.all`.
  - **BACKUP** (`ScheduleBackupSection`):
    - the times of the last daily copy and the last GitHub sync, and the Drive mirror name;
    - "Bring them in" / "Keep this Mac's" when GitHub holds unseen data;
    - "Restore…", a menu of daily snapshots labelled "19 Nov 2026 · 1 routine · 12 check-offs";
    - "Show backups".
- **Editor overlay** (`ScheduleEditorOverlay`): 88% of the window over a dimmed scrim. See [Editor](#editor-scheduleeditorswift).

## Files

| File | Key types / functions |
| --- | --- |
| `Sources/Pocket/ScheduleModel.swift` | `ScheduleSlot` (`morning`/`night`, `label`, `symbol`); `ScheduleStep` (`id`, `title`, `tip`); `ScheduleRoutine` (`id`, `name`, `hue`, `starts`, `plan`, `notes`, `key(_:_:)`, `steps(_:_:)`); `ScheduleCheck` (`id(routine:day:slot:step:)`); `ScheduleItem` (view model: routine+step+slot+day+done); `ScheduleDayStatus`; `ScheduleBook` (the file root); `ScheduleDays` (calendar with `firstWeekday = 2`, `yyyy-MM-dd` POSIX formatter, `weekOrder = [2,3,4,5,6,7,1]`, `key`, `date`, `weekday`, `shift`, `name`, `short`); `ScheduleStore` (singleton, see below); `ScheduleSeed.hairCare()` |
| `Sources/Pocket/ScheduleApp.swift` | `ScheduleApp: PocketApp` (`start` subscribes to `store.objectWillChange` to refresh the badge; `makeContent`; `didShow` → `store.tick()`; `barImage`; `menuItems`; `openBoard(source:)`). Private views: `ScheduleLook`, `ScheduleDropdown`, `ScheduleHeader`, `ScheduleFilterMenu`, `ScheduleSlotCard`, `ScheduleFold`, `ScheduleChecklist`, `ScheduleRow`, `ScheduleProgress`, `ScheduleMarkAll`, `ScheduleQuietSlot`, `ScheduleNoRoutines`, `ScheduleTallyLine` |
| `Sources/Pocket/ScheduleBoard.swift` | `ScheduleBoardWindow` (singleton NSWindow owner, `present(day:)`, `windowWillClose`); `ScheduleSpan` (`day`/`week`); `ScheduleBoardFocus` (`selected` day, `span`); `ScheduleBoardMode` (UserDefaults key + `schedule`/`calendar`); `ScheduleBoardDates` (`weekStart`, `monthStart`, `monthShift`, `monthLength`, `weekRange`, `hour`, title formatters); `ScheduleHalf` (half-disc shape); `ScheduleStatusDot`; `ScheduleSplitMark`; `ScheduleGlass`; `ScheduleModeToggle`; `ScheduleRoutinePicker`; `ScheduleCircleButton`; `ScheduleSidebarRow`; `ScheduleSidebar`; `ScheduleWeekStrip`; `ScheduleWeekNav`; `ScheduleSlotCard` (board version, private, same name as the dropdown's); `ScheduleNotesCard`; `ScheduleSpanToggle`; `ScheduleTint`; `ScheduleWeekGrid`; `ScheduleDayView`; `ScheduleCalendarView`; `ScheduleHourRow`; `ScheduleBackupSection`; `SchedulePrefsPanel`; `ScheduleBoardView` |
| `Sources/Pocket/ScheduleEditor.swift` | `ScheduleEditorOverlay` (the only non-private type); `ScheduleEditorNameField`; `ScheduleEditorPillField`; `ScheduleEditorGrid`; `ScheduleEditorCell`; `ScheduleEditorStepRow`; `ScheduleStepEditor` (popover); `ScheduleEditorNotes` |
| `Sources/Pocket/DataVault.swift` | `PocketData.schedule`; `VaultFile.all` (board/todos/schedule with nouns session/to-do/check-off); `DataVault.ids(in:name:)` handles `"schedule"` |
| `Sources/Pocket/Catalog.swift` | `AppSpec.claimsHotKey`, `AppSpec.pinnedByDefault` (both added for Schedule); the schedule entry; Outlook `hotKey: nil` |
| `Sources/Pocket/Layout.swift` | `Layout.init`: the `pinnedByDefault` new-app placement and the `claimsHotKey` shortcut claim |
| `Sources/Pocket/Factory.swift` | `case "schedule": return ScheduleApp(spec: spec)` |

Two private structs share the name `ScheduleSlotCard`, one in `ScheduleApp.swift` and one in `ScheduleBoard.swift`. That is legal because each is file-private, but grep carefully.

## Data

### Model (`schedule.json`)

`ScheduleBook` is JSON, written pretty-printed with sorted keys and ISO-8601 dates (`ScheduleStore.encode`/`decode`):

```
{ "routines": [ScheduleRoutine], "checks": [ScheduleCheck], "nightFrom": 16, "dayFrom": 4 }
```

**`ScheduleRoutine`**

| Field | Meaning |
| --- | --- |
| `id` | UUID |
| `name` | The routine's name |
| `hue` | Int index into `Board.hue` (`theme.projectTint`). New routines get max+1. |
| `starts` | `yyyy-MM-dd` day. Days before it don't count for this routine. The seed uses `2026-11-19`. New routines start on `today`. |
| `plan` | `[String: [ScheduleStep]]`, keyed `"<weekday>-<slot>"`, e.g. `"5-morning"`. Weekday is a Calendar weekday, **1 = Sun … 7 = Sat**. That gives 7×2 ordered lists. |
| `notes` | Free text |

**`ScheduleStep`**: `id` (UUID), `title`, `tip`. Editing a step keeps its id, so its check-offs survive.

**`ScheduleCheck`**: `id`, `routine`, `day`, `slot`, `step`, and `done` (Date).
- The id is deterministic: `"<routineUUID>|<yyyy-MM-dd>|<slot>|<stepUUID>"` (`ScheduleCheck.id`). The same id is `ScheduleItem.id`.
- A checked step is the presence of a check. Unchecking removes the check.

**Book settings**
- **Repeats are weekly only, by design.** There is no biweekly and no every-N-days. A repeat is entered on each weekday separately; the editor footer says "Weeks repeat; put a step on each day you want it."
- **`nightFrom`** (default 16): the hour the night slot begins. It is set in Preferences, clamped to `dayFrom+1 … 23` (`setNightFrom`).
- **`dayFrom`** (default 4): the day rolls over at 4 AM. **No UI changes it.**

### Time rules (`ScheduleStore`)
- `today` is the current time minus `dayFrom` hours, formatted as a key. At 1 AM it is still yesterday.
- `slotNow` is `.night` if `hour >= nightFrom || hour < dayFrom`, and `.morning` otherwise.
- `now` is refreshed by a 30 s `Timer` on the main run loop in `.common` mode, and by `tick()` whenever the dropdown is shown (`didShow`). `tick` logs only when the day or slot changes.
- There is no wake observer. After sleep, `now` is up to 30 s stale until the timer fires or the dropdown opens.

### Status and counting

`status(on:slot:in:)` returns a `ScheduleDayStatus`:

| Status | When |
| --- | --- |
| `.before` | No routine in the pool has started by that day |
| `.rest` | Nothing is planned for that day or slot |
| `.done` | Everything is checked (future days included) |
| `.upcoming` | A future day that isn't done |
| `.open(done,total)` | Today, still in progress. Today's **morning** becomes lapsed once `slotNow == .night`, and is then reported as missed or partial. |
| `.missed` | A past day (or today's lapsed morning) with 0 done |
| `.partial` | A past day (or today's lapsed morning) with some done |

- **`tally(from:through:)`** walks from `max(start, firstDay)` to `min(end, today)` and counts `.done`, `.partial` and `.missed`.
  - Every UI shows **missed = missed + partial**: partial counts as missed.
  - Today counts only once it is `.done`, because a whole-day status for today is `.open`.
- **The pool is the filter.** `status` and `items` default to `shown`, the routines the filter selects. Badge, tally, sidebar, calendar and week tints therefore all change with the routine filter.
- **`firstDay`** is the earliest `starts` across *all* routines, regardless of the filter.

### Persistence, UserDefaults and backups

| What | Where |
| --- | --- |
| Data | `PocketData.schedule` = `$ROOT/schedule.json`. `$ROOT` is `~/Library/Application Support/Pocket`, or `POCKET_DATA_DIR`. |
| Daily snapshot | `$ROOT/Backups/schedule/schedule-YYYY-MM-DD.json`. Rewritten on **every** `save()` via `DataVault.snapshot(_, name: "schedule", count: checks.count)`. Pruning keeps 30 days plus the first snapshot of each month. Each snapshot is mirrored to the Drive folder `…/Pocket Backups/schedule/`. |
| Kept-aside | `$ROOT/Backups/schedule/schedule-<reason>-<stamp>.json`, where reason is `before-delete` (deleting a routine), `before-merge` (Bring them in) or `before-restore` (Restore). |
| Quarantine | `$ROOT/schedule.broken-<stamp>.json`, used when `schedule.json` fails to decode at launch |
| Git sync | `schedule.json` at the root of the private `pocket-data` repo, the same as `board.json` and `todos.json` (`VaultFile.all`). "Seen" ids are **check ids plus routine ids** (`DataVault.ids(in:name:"schedule")`). The held message noun is "check-off", so routines are also counted as "check-offs" in "GitHub has N check-offs this Mac doesn't". |
| `schedule.filter` | UUID string of the routine filter. Absent means all. It is reset if the routine no longer exists. |
| `schedule.board.span` | `day` or `week` |
| `schedule.board.mode` | `schedule` or `calendar` |
| `schedule.board.stats` | Bool, whether the sidebar is shown (default true) |
| `schedule.board.panel` | Bool, whether the preferences panel is open (default false) |
| `NSWindow Frame schedule.board` | The window frame autosave |
| `pomodoro.board.theme` | The theme is **shared with the Aurelius board** (`BoardThemeStore.shared`). Changing it here changes Aurelius too, and logs as `pomodoro board theme=…`. |

**Load order** (`ScheduleStore.init`):
1. Register the vault merger `"schedule"`.
2. If the file exists, decode it.
3. If decoding fails, quarantine the file, then `vault.recover` from the newest readable snapshot and save it.
4. If there is no file and no snapshot, seed `hairCare()` and save.
5. Once per Mac (UserDefaults `schedule.seeded.mindfulness-2026-11`), add `ScheduleSeed.mindfulness()` unless a routine named Mindfulness exists, with the next free hue. It is a weekly plan from 20 Nov 2026: morning meditation, visualization, affirmations and one action; night gratitude, wins, scripting and a body scan. Goal focus rotates: Mon/Thu government job, Tue/Fri six pack, Wed/Sat hair, Sun all three plus a weekly review. Its name has no "hair", so the parents' web app never shows it.

## Flows

**Launch / first ⌥O**
1. `makeApp` builds a `ScheduleApp`.
2. `start()` touches `ScheduleStore.shared`, which is lazy, so the store loads here. It subscribes to `objectWillChange` to recompute the badge, then calls `changed()` only when the count changes.
3. The hotkey toggles the dropdown, which is handled by PocketApp and the shell.
4. `didShow` calls `tick()`, so the date and slot are fresh.

**Check a step**
1. `store.toggle(item)` calls `set(item, done:)`, which appends or removes the `ScheduleCheck`.
2. It logs, then `save()`: an atomic write, then the snapshot, then a sync about 90 s later.
3. `objectWillChange` updates the badge.

**Mark all:** `setAll(on:slot:done:)` covers the items of that slot in the **filtered** pool only.

**Open the board:** the expand button or the menu item calls `openBoard(source:)`, which hides the dropdown (`hide(reason: "switched")`) and calls `ScheduleBoardWindow.shared.present()`.
- `present` switches the app to the `.regular` activation policy so the window gets a Dock icon and focus.
- If the window already exists, it refocuses it. Otherwise it builds the `NSHostingView` and sets `focus.selected = today`.
- On close, `windowWillClose` drops back to `.accessory` unless another titled window is visible.
- The window follows the theme through `themeWatch`.

**Calendar → day:** `openDay` sets `focus.selected`, sets span to `.day`, and switches mode to schedule.

**Span toggle:** clicking either option sets the span **and resets `selected` to today**. A chip or week-grid header click selects that day and forces `.day`.

**Week paging:** `ScheduleWeekNav` moves ±7 days. It stops at the week of `firstDay`, and at the week holding the last day of next month.

**Preferences:** "Night routine from" calls `setNightFrom`. Theme swatches set `BoardThemeStore.shared.theme`.

**Restore:**
1. Pick a snapshot; an `NSAlert` confirms.
2. `store.restore(snap)` keeps the current book aside as `before-restore`, replaces the whole book, and saves.

**Bring them in:**
1. `DataVault.bringIn` calls the registered `merge(data)`, which keeps the current book aside (`before-merge`).
2. It appends incoming **routines whose id is unknown** and **checks whose id is unknown**, then saves.
3. Existing routines are **not** updated: plan, notes or name edits made on the other Mac are not merged.

**Delete a routine**
1. The editor's ⋯ menu offers "Delete…", and an `NSAlert` states the check-off count.
2. `deleteRoutine` keeps the book aside (`before-delete`), removes the routine and **its checks**, clears the filter if it pointed there, and saves.

**Quit:** nothing schedule-specific. Every mutation has already been saved synchronously, and `ScheduleApp` does not override `stop()`.

### Editor (`ScheduleEditor.swift`)
- **Routine pills.**
  - The selected pill is the filter's routine, or else the first routine.
  - Click a pill to select it. Double-click it, or use ⋯ → Rename, to rename inline (`ScheduleEditorPillField`); the edit commits on Enter or blur and is cancelled by Esc.
  - ⋯ → Delete… deletes after a confirmation. **+** adds a routine inline; it starts today and gets the next hue.
- **The 7×2 grid** (`ScheduleEditorGrid`): Mon-first columns, with today's column highlighted, and Morning/Night rows.
  - Each cell (`ScheduleEditorCell`) lists its steps. "+ Add" opens a text field.
    - Enter adds the step and keeps the field focused for the next one.
    - Blur adds any non-empty draft and closes the field. Esc cancels.
  - Hovering a step shows ✕ to remove it. A tip shows as a `text.bubble` icon.
- **Step popover** (`ScheduleStepEditor`, 320 wide): edits title and "HOW TO DO IT" (the tip), with ↑/↓ reorder within the cell, 🗑 delete, and Done.
  - It saves on Done, on Enter in the title, before a move, and in `onDisappear`, but only if something changed.
  - A step cannot be moved to another day or slot. To do that, delete it and re-add it, which gives it a new id; past check-offs for the old id become orphans.
- **Notes footer** (`ScheduleEditorNotes`): a "NOTES AND GENERAL TIPS" `TextEditor`, debounced 0.8 s, and flushed on blur and on disappear.
- **Esc** (`onExitCommand`) closes the overlay.

## Integrations

- **DataVault only:** snapshots, Drive mirror, and git sync to `pocket-data` through the `gh` account configured in `pocket.backup.githubUser`. See [../data-and-backups.md](../data-and-backups.md).
- No network, EventKit or notifications. Nothing needs any permission.

### Shortcut migration
`Layout.init` runs over apps not yet in `shortcuts.offered`. If the app's default `⌥key` is already held by another app and `spec.claimsHotKey` is true, it removes it from the holders and gives it to the new app. It logs:

```
pocket shortcut claimed app=schedule from=outlook keys=⌥O
```

This runs **once**, the first time `schedule` is offered. A user who rebinds afterwards keeps their choice.

At the same point, `pinnedByDefault` puts a newly offered app into `layout.bar`, the menu bar, rather than `layout.tray`, and logs `pocket new apps added to menu bar apps=schedule`.

## Logging

Every line is written with `note(...)`.

| Where | Line (identifiers) |
| --- | --- |
| Store load | `schedule loaded routines= checks= path=` · `schedule load failed path= error=` · `schedule recovered from= routines= checks=` · `schedule seeded routines= path=` · `schedule routine seeded name= starts= hue=` |
| Clock | `schedule moved day= slot=` (only when the day or slot changes) |
| Filter | `schedule filter changed routine=<name or all>` |
| Checks | `schedule step checked\|unchecked routine=<name> day= slot= step=<title>` · `schedule slot completed\|cleared day= slot= steps= filter=` |
| Routines | `schedule routine added id= name= starts=` · `schedule routine deleted id= name= checksRemoved=` · `schedule routine changed name=<routine> <reason>`, where reason is one of `renamed to=`, `notes chars=`, `step added weekday= slot= title=`, `step edited weekday= slot= title=`, `step removed weekday= slot= step=<uuid>`, or `step moved weekday= slot= by=` · `schedule routine missing id= action=` · `schedule routine delete cancelled id= name=` |
| Settings | `schedule night starts hour=` |
| Merge / restore | `schedule merged routinesAdded= checksAdded= checks=` · `schedule merge failed bytes= error=` · `schedule restored from= checksBefore= checksAfter=` · `schedule restore failed from= error=` · `schedule restore cancelled from=` |
| Save | `schedule save failed routines= checks= error=` |
| App | `schedule app started routines= day= slot= left=` · `schedule board requested source=dropdown\|menu day= filter=` |
| Board | `schedule board opened day= routines= filter=` · `schedule board refocused day=` · `schedule board closed otherWindows=` · `schedule board bad day requested day=` · `schedule board view mode=` · `schedule board span=<day\|week> day= from=` · `schedule board calendar opened day= status=` · `schedule board preferences open=` · `pocket vault keep local cancelled from=schedule` |
| Editor | `schedule editor opened routines=` (board) **and** `schedule editor opened routine= routines=` (overlay `onAppear`); `schedule editor closed routines=` (board) **and** `schedule editor closed routine=` (overlay `dismiss`) |
| Vault | `pocket vault kept aside name=schedule reason=…` · `pocket vault quarantined name=schedule …` · `pocket vault sync held name=schedule unseen=` · `pocket vault brought in name=schedule bytes=` |

Step titles, which may be health-related user content, appear in the log.

## Gotchas

- **History is computed from the current plan; it is not frozen.**
  - Adding a step to Monday turns every past Monday since `starts` from done into partial, which counts as missed.
  - Removing a step can turn past partial days into done.
  - `removeStep` leaves that step's checks in `book.checks` as orphans. They still count in snapshot and sync totals.
- **Deleting a routine** removes its checks too; they survive only in the `before-delete` kept-aside file. Deleting and re-adding a step gives it a new id.
- **Seeding on a new Mac:** `hairCare()` mints fresh UUIDs on every call.
  - If Pocket starts on a new Mac with no `schedule.json` and no snapshot, it seeds a *different* "Hair care" routine.
  - A later "Bring them in" then adds the GitHub copy as a **second** "Hair care" routine with its own id.
  - To avoid this, put `schedule.json` in place before the first launch, following the CLAUDE.md "Moving to another Mac" steps.
- **Merge is a union by id only.** Edits made on another Mac to an existing routine's plan, notes or name never come across. A routine deleted here and still present on GitHub comes back on "Bring them in".
- **The merger is registered lazily.** `DataVault.register("schedule")` runs in `ScheduleStore.init`, which first runs when the Schedule app starts. If Schedule is not enabled, "Bring them in" logs `pocket vault bring in skipped name=schedule reason=no-store`. Sync still pushes the file.
- **Filter-dependent numbers:** the badge, both tallies, the TODAY card, the calendar marks and the week tints all follow `store.filter`. "Mark all" only touches the filtered routines.
- **`present(day:)`** has a `day` parameter that no caller passes. The calendar uses `openDay` inside the view. The parameter is a ready-made entry point for deep links, but it is untested.
- **Calendar layout:** it used to be a `LazyVGrid`, which overlapped the legend below it. It was replaced by fixed `HStack` rows, and the legend was dropped at the user's request (`12644dd`). Don't reintroduce a `LazyVGrid` there.
- **`store.streak()` was deleted** (`3c7fbe5`) and replaced by days done and missed. Don't bring it back.
- **Duplicate editor logs:** opening or closing the editor logs twice, once from `ScheduleBoardView.openEditor`/`closeEditor` and once from the overlay. This contradicts the "don't log the same event twice" rule. The fix is to drop one pair.
- **Hosting appearance:** both the dropdown and the board set `.id(themes.theme.id)` and `.environment(\.colorScheme, …)`, so a theme change rebuilds the view tree. Transient `@State` (open tips, the fold, an editor draft) resets.
- **Clock after sleep:** there is no wake hook (see [Time rules](#time-rules-schedulestore)). The dropdown's `didShow` tick covers the common case.
- **Tally cost:** `tally()` walks every day since `firstDay` and builds items for each, on every render of the footer and sidebar. That is fine for months of data but grows linearly over time.
- **Verification:** the board and editor were checked only from offscreen renders (see [../operations.md](../operations.md)), never clicked live. Popover, focus and NSAlert behaviour is unverified in the running app.

## How to change it safely

- **Test against scratch data.** Set `POCKET_DATA_DIR` to a scratch folder and write a `schedule.json` there with past done, partial and missed days. Render through the harness in [../operations.md](../operations.md). Never point it at the real `~/Library/Application Support/Pocket`, and never run `scripts/install.sh`.
- **Add a field to the book, a routine or a step.** Old files and snapshots must keep decoding. Synthesized `Codable` **ignores property default values**: a missing non-optional key throws even though `nightFrom = 16` or `tip = ""` have defaults. Make the new field Optional, or write a custom `init(from:)` using `decodeIfPresent`. Today every file is written with every key, so the existing fields have never hit this.
  - A decode failure quarantines the file and falls back to a snapshot that would *also* fail. The app would then seed a fresh book, losing data from view. It is not deleted: it stays in `schedule.broken-*`.
  - Check the change by decoding the newest real snapshot *copy* in a scratch dir.
- **Add a setting:**
  1. Add the field to `ScheduleBook`, decodable when absent (see above).
  2. Add a `set…` method on `ScheduleStore` that clamps, logs `schedule <thing> …` and `save()`s.
  3. Add a row in `SchedulePrefsPanel`.

  View-only preferences go in UserDefaults under `schedule.board.*`.
- **Add a mutation.** Route it through `updateRoutine(_:reason:_:)` so it logs and saves, and so no-op changes are skipped. Views never write `book` directly; it is `private(set)`.
- **Change the check id format.** Don't. Ids are what sync and merge match on, and existing checks in `pocket-data` use the current format.
- **Change slot or day boundaries:** `today` and `slotNow` are the only definitions. Everything else derives from them.
- **Add another repeat rule:** this goes against an explicit user decision (weekly only). Ask first.
- **Shortcut defaults:** to move a default key from an existing app to a new one, set `claimsHotKey: true` on the new spec and `hotKey: nil` on the old. The claim only fires the first time the new id is offered.

## User preferences learned (explicit design calls)

- **Minimal.** No extra chrome or decorative stats; the cards carry the information.
- **No legend** on the calendar. It was removed on request.
- **No streak.** It was replaced by "days done · missed since <first day>".
- **Pastel, not vibrant.** The week-view tints are soft green and red at low opacity (`ScheduleTint`). Keep any new status colours in that register.
- **Weekly only.** No biweekly or every-N-days rules; a repeat is entered per weekday.
- **Partial counts as missed** in every count shown to the user.
- **The dropdown opens on the current slot**, with the other slot collapsed, and the board is one click away.
- **Steps carry tips** ("how to do it"). Keep them one tap away in the dropdown and inline on the board.

## Open questions / known gaps

- The toggle still reads "This week" after you page to another week, and "Today" for any selected day. A relative label or a "back to today" affordance may be wanted.
- A partial past day shows a **half-filled accent dot** in the day strip (`ScheduleStatusDot`) rather than red. That is inconsistent with "partial counts as missed" and with the calendar mark, which is accent at 45% opacity, also not red. Only `.missed` is red.
- Long step titles wrap to 3–4 lines in the 7-column week grid at about 700pt wide.
- `dayFrom` has no UI.
- There is no way to move a step to another day while keeping its history.
- There is no per-day override or skip, so a deliberate rest day counts as missed.
- Merge ignores edits to existing routines (see Gotchas).
- The duplicate editor open/close logs (see Gotchas).
- `ScheduleBoardWindow.present(day:)` is unused.
