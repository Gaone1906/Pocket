# Ignis (formerly Pomodoro)

Renamed from Pomodoro on 2026-11-19. Only the names people see changed; the code, app id `pomodoro`, routes, data folder and keys did not.

A focus, break and long-break timer with a split-flap dropdown and a live countdown in the menu bar. It also has a
separate **board** window: finished focus sessions are filed there as glowing dots and tally marks under projects. The
board is the visual reference other Pocket apps copy (Schedule's board and dropdown use the same `Board.*` tokens,
`boardEdge`, `BoardBackdrop` and theme store). Local programs can drive the timer over HTTP (`PocketServer`, documented
in `CLAUDE.md`).

Related: [architecture](../architecture.md), [theme](../theme.md) (`BoardTheme`, `BoardThemeStore`, embroidery),
[data and backups](../data-and-backups.md) (`DataVault`), [schedule](schedule.md) (the board's closest copy),
[todo](todo.md).

## What it is

| Thing | Value |
| --- | --- |
| Catalog entry | `Catalog.swift`: `AppSpec(id: "pomodoro", name: "Ignis", symbol: "timer", glyph: Glyphs.ignis, hotKey: kVK_ANSI_P)`. Built by `Factory.swift` `case "pomodoro": PomodoroApp(spec:)` |
| Default shortcut | ⌥P |
| Dropdown | 340 × 330, fixed (`defaultSize` = `minSize`, `resizable = false`) |
| Menu-bar item | Idle: the lion face (`Glyphs.ignis`) in the app colour. Active (running or paused): the face tinted, followed by ` MM:SS` in semibold monospaced digits. The tint is **gold** in focus and **silver** in rest/long (`PomodoroPalette`, with light and dark variants). A paused phase shows a frozen countdown in the same colour |
| Right-click menu item | **Open Ignis board** (`menuItems()`) |
| Board window | 980 × 620 to start (min 640 × 420), resizable, frame autosaved as `pomodoro.board` |

What the user does:
- **Dropdown (`PomodoroView`).** It shows:
  - a heading: `READY` when held, `PAUSED`, the project name during focus, or the phase label;
  - two `FlapCard`s, minutes and seconds, that flip on change;
  - a row of `longEvery` dots showing progress to the long break;
  - three buttons: Reset (↺), **Start / Pause / Resume** (Space), and Skip (⏭).

  The ⤢ button at the top right opens the board.
- **Board.** It has three parts:
  - a left stats sidebar;
  - a header with a **Sessions | Calendar** toggle and a settings button;
  - a right settings panel with timer lengths, 12 themes and the backup section.

  In Sessions mode there is one column per project, plus "Unassigned". Finished sessions land as glowing dots in
  Unassigned. Drag them (or click → menu) onto a project, and they become tally sticks (one stick per 25 min, struck
  every 5). Right-click a column (or use its ⋯ menu) → **Declare a session…** to log time away from the laptop.

## Files

| File | Key types and functions |
| --- | --- |
| `Sources/Pocket/PomodoroApp.swift` | `PomodoroPhase` (`focus`, `rest`, `long`; `label`). `PomodoroState` (`idle`, `running(phase, endsAt)`, `paused(phase, remaining)`). `PomodoroPalette` (gold, silver, `color(for:)`). `PomodoroPlan` (optional `focus`, `rest`, `long`; `isEmpty`). `PomodoroModel` (all timer state and settings; `minutes(for:)`, `seconds(for:)`, `phase`, `isRunning`, `isIdle`, `isActive`, `remaining(at:)`, `progress(at:)`, `format(_:)`). `PomodoroApp` (`makeContent`, `barImage`, `barTitle`, `menuItems`, `openBoard`, `remoteState`, `remoteStart`, `remotePause`, `remoteResume`, `remoteStop`, `stop`, and the private `toggle`, `reset(reason:)`, `skip`, `advance(from:reason:running:)`, `onTick`, `refresh`, `startTimer`, `stopTimer`, `requestAuthorizationOnce`, `notify`). The private `Flap` theme tokens, `FlapCard` and `FlapButton`. `PomodoroView` |
| `Sources/Pocket/PomodoroBoard.swift` | `PomodoroProject`, `PomodoroSession`, `PomodoroBoardStore` (singleton `shared`; load, merge, snapshots, restore, record, declare, assign, delete, project CRUD, `projectId(named:)`). The `Board` token and format namespace. `MenuAction` and `SessionMenu` (the NSMenu for a session). `GlowDot`, `TallyStick` (`sticks(for:)`, `groups(for:)`), `TallyGroup`, `SessionMarks`, `BoardCalendar`, `BoardColumn`, `SettingRow`, `BoardSectionTitle`, `BoardStats`, `BoardSettingsPanel`, `BoardBackupSection`, `PomodoroBoardView`, `DeclareTarget`, `BoardSettingsButton`, `BoardModeToggle` and `PomodoroBoardWindow` |
| `Sources/Pocket/DeclareSession.swift` | `DeclareSessionCard`, the overlay for logging a session by hand. It offers presets of 25/40/60/90/120 min, a maximum of 720, an optional start/end time, and today or an earlier day. It calls `store.declare(...)` |
| `Sources/Pocket/BoardTheme.swift` | `BoardTheme` (12 themes in `BoardTheme.all`), `BoardThemeStore.shared` (key `pomodoro.board.theme`) and `BrushedGrain`. See [theme](../theme.md) |
| `Sources/Pocket/Embroidery.swift` | `BoardBackdrop` (flat colour, or embroidered fabric) and the `View.boardEdge(_:color:width:)` modifier (a plain stroke, or a dashed "stitch" on embroidered themes) |
| `Sources/Pocket/PocketServer.swift` | `route(_:)` handles the `/pomodoro*` routes and calls `PomodoroApp.remote*` and `PomodoroBoardStore.shared` |

## Timer: phases and state machine

Model state is `PomodoroModel.state: PomodoroState`, plus these fields:

| Field | Meaning |
| --- | --- |
| `cycle` | +1 each time a focus phase begins (idle→focus, and every break→focus, whether finished, skipped or held). Not persisted; it is 0 at every launch |
| `streak` | Focus phases **finished** (not skipped) since the last long break. Persisted (`pomodoro.streak`). It is **not** reset by Reset or Stop, so it carries across runs and days |
| `project` | A free-text project label for the current run (set only by the API; `nil` from the UI) |
| `plan` | Custom durations from an API start; `nil` means use the settings |
| `hold`, `waiting` | Hold-after-break (see below) |
| `tick` | Bumped on every refresh to re-render the countdown |

Transitions (all in `PomodoroApp`):

| From | Trigger | To | Side effects |
| --- | --- | --- | --- |
| `idle` | `toggle()` (Start, Space, `/start`) | `running(.focus, now+focus)` | `cycle += 1`; asks for notification permission once; starts the 1 s timer |
| `running(p, end)` | `toggle()` (Pause, `/pause`) | `paused(p, end-now)` | stops the timer |
| `paused(p, left)` | `toggle()` (Resume/Start, `/resume`, `/start`) | `running(p, now+left)` | `waiting = false`; starts the timer |
| any active | `reset(reason:)` (↺, `/stop`) | `idle` | clears `project`, `plan`, `hold` and `waiting`. **The focus in progress is discarded**: nothing is recorded |
| `running/paused(.focus)` | `skip()` | `rest` or `long`, keeping running vs paused | no session is recorded; `streak` is unchanged |
| `running/paused(rest/long)` | `skip()` | `.focus`, keeping running vs paused | `cycle += 1` |
| `running(.focus)` reaches 0 | `onTick()` | `running(rest/long)` | records the session, `streak += 1`, sound, notification |
| `running(rest/long)` reaches 0, `hold == false` | `onTick()` | `running(.focus)` | `cycle += 1`, sound, notification |
| `running(rest/long)` reaches 0, `hold == true` | `onTick()` | `paused(.focus, full length)` with `waiting = true` | `cycle += 1`, timer stopped, sound, notification "Break over — press Start when you're back" |

`skip()` always clears `waiting` first. Skipping while `waiting` (a paused, held focus) therefore advances to a
**paused break**.

**Durations.** `minutes(for:)` works like this:
- focus = `plan.focus ?? focusMinutes`;
- rest = `plan.rest ?? breakMinutes`;
- long = `plan.long ?? plan.rest ?? longBreakMinutes`.

So an API start that sets only `rest` also uses it for long breaks.

**Streak and the long break (`advance`).**
1. Leaving focus: if `reason == "finished"`, `streak += 1`.
2. Next is `.long` if `streak >= longEvery`, otherwise `.rest`.
3. Entering `.long` sets `streak = 0`.

Default `longEvery` is 4. Skipped focuses don't count but still lead to a break (a long one, if the streak is already at
or past `longEvery`, for example after `longEvery` was lowered). The dot row fills `streak` dots, or all of them during
a long break.

**Ticking.** `startTimer()` puts one repeating 1 s `Timer` (tolerance 0.2) in `.common` mode. `onTick()`:
- compares the **wall-clock** `endsAt` with now, then calls `refresh()` (`tick = Date()` + `changed()` → `StatusBar.refresh("pomodoro")`), so the menu bar repaints every second;
- stops itself if the state isn't `running`.

**Recording.** When a focus ends naturally, `onTick` calls
`PomodoroBoardStore.shared.record(minutes: minutes(for: .focus), ended: endsAt, project: project.map(store.projectId(named:)))`.
- `ended` is the scheduled end, not the tick time.
- `projectId(named:)` matches case-insensitively, or creates a project via `addProject()` + `rename`.

**Notifications.** `notify(title: "Ignis", body:)` posts a `UNNotificationRequest` straight away and plays
`NSSound "Glass"`. The bodies are:
- "Focus done — take a N min break" or "… long break";
- "Break over — back to focus";
- the hold variant, "Break over — press Start when you're back".

`requestAuthorizationOnce()` (alert and sound) runs on the first Start. `AppDelegate` also requests notification
permission at launch. Both are skipped when there's no bundle id (`swift run`), which logs
`pomodoro notification skipped reason=no bundle`.

### Hold focus after a break (commit `271e7e5`, 2026-11-17)

This was added for API clients such as Preparo, which want the user to come back before the next focus starts.

- It is set only by `POST /pomodoro/start` with `"hold": true` (validated by `PocketServer.flag`; a non-bool gets `400`).
  It is applied only when the timer is **idle**, like `plan`. A start on a running or paused timer keeps the existing
  `hold`.
- When a break ends with `hold == true`, `onTick` calls `advance(..., running: false)`. That makes the state
  `paused(.focus, full focus length)`, and `cycle` has already gone up. It then sets `waiting = true`, stops the timer,
  and logs `pomodoro waiting for start`.
- The UI shows the heading `READY` and the toggle title `Start` (instead of `Resume`). The menu bar shows the full focus
  length, frozen, in gold.
- Any of these begins the focus and clears `waiting`: `POST /pomodoro/resume`, `POST /pomodoro/start`, the dropdown
  Start or Space.
- `hold` lasts until `reset` (↺ or `/stop`). It never applies to focus→break; breaks always start on their own.
- `remoteState()` exposes `hold` and `waiting`. (`CLAUDE.md`'s sample JSON omits them, but its "Hold after break"
  paragraph covers them.)

### Remote control (`PomodoroApp.remote*`, called from `PocketServer.route`)

| Function | Behaviour |
| --- | --- |
| `remoteState()` | Returns `phase` (`idle`/`focus`/`rest`/`long`), `running`, `remaining` (seconds, rounded up), `focusMinutes`, `breakMinutes`, `longMinutes`, `customPlan`, `hold`, `waiting`, `cycle`, `project` (or null), and `endsAt` (epoch ms, only while running) |
| `remoteStart(project:plan:hold:source:)` | **Always** sets `model.project = project`, even when that is nil, which clears the label on a running run. If idle, it sets `plan` (nil when empty) and `hold`. If not running, it calls `toggle()` |
| `remotePause` | Calls `toggle()` only if running |
| `remoteResume` | Calls `toggle()` only if paused |
| `remoteStop` | `reset(reason: "stopped from <source>")`; `project = nil` |

API ranges (`PocketServer.minutes`) are focus 1–240, rest 1–90 and long 1–120. These are wider than the settings UI
(see below), and a plan never touches the settings. If Ignis isn't enabled, every route answers `409`. The full API
contract is in `CLAUDE.md`.

## Board window

`PomodoroBoardWindow.present()`:
1. switches the app to `.regular` activation (a Dock icon and Cmd-Tab);
2. reuses the existing window if there is one (logs `refocused`);
3. otherwise builds an `NSWindow` (titled, closable, miniaturizable, resizable, `fullSizeContentView`, with a transparent titlebar and the title hidden) hosting `PomodoroBoardView(model:store: .shared)`;
4. tracks `BoardThemeStore.$theme` to update `appearance` and `backgroundColor`.

`windowWillClose` drops the window and switches back to `.accessory`. `PomodoroApp.openBoard()` hides the dropdown
(`reason: "switched"`) before presenting.

### Component structure (copy this layout)

```
PomodoroBoardView                                  ZStack, .id(theme.id), .background(BoardBackdrop), .ignoresSafeArea, colorScheme from theme
├─ HStack(spacing 0)
│  ├─ [showStats] BoardStats (220 wide, Board.sidebar bg, top pad 52 to clear traffic lights) + 1px Board.line divider
│  │      └─ card("TODAY"), card("ALL TIME"): BoardSectionTitle + rounded-16 Board.column card with .boardEdge(16):
│  │         units (30pt bold, accentInkStyle) "sessions" / hairline / duration (22pt bold) "focused"
│  ├─ VStack (main)
│  │  ├─ header HStack: sidebar.left toggle · BoardModeToggle(mode) · Spacer · BoardSettingsButton
│  │  │      leading pad 20, or 84 when stats are hidden (clears the window buttons); top pad 12
│  │  └─ ZStack: mode == "calendar" ? BoardCalendar : horizontal ScrollView of
│  │         BoardColumn(nil "Unassigned") + BoardColumn(project)… + dashed "New project" tile (200×110)
│  └─ [showPanel] 1px divider + BoardSettingsPanel (280 wide, theme.panel bg)
│         header "Settings" + xmark · "TIMER" 4×SettingRow · hairline · "THEME" + name · 5-per-row swatch Grid
│         · hairline · BoardBackupSection
└─ [declaring] dim scrim (tap closes) + DeclareSessionCard (.scale 0.96 + opacity transition)
```

The building blocks:

| Component | What to reuse |
| --- | --- |
| `Board` enum | Tokens read live from `BoardThemeStore.shared.theme`: `backdrop`, `sidebar`, `column` (= `theme.card`), `line`, `muted`, `ink`, `faint`, `accent`, `accentInk`, `accentStyle`, `accentInkStyle` (metal gradients on Bronze), `shadow` and `hue(i)` (project tints). `Board.glide = .smooth(duration: 0.3)` is the shared animation. Format helpers: `sessionLabel`, `units`, `unitsLabel`, `days`, `dayDate`, `dayTag`, `duration` |
| Cards | `RoundedRectangle(cornerRadius: 16).fill(Board.column)` + `.boardEdge(16)`. Always use `boardEdge`, not a raw stroke, so embroidered themes get the stitched inset edge |
| `BoardSectionTitle` | 10pt semibold, tracking 1.6, `Board.muted`, with UPPERCASE text |
| `SettingRow` | Title · ± circular steppers (24pt, `Board.column` fill, `Board.line` ring) · 18pt bold value + unit. Clamps to `range` |
| `BoardModeToggle` | A capsule segmented control. On macOS 26 it uses `.glassEffect(.regular.interactive(), in: Capsule())`, otherwise `.ultraThinMaterial` + a `Board.line` border. The selected pill is a `theme.pill` capsule with `matchedGeometryEffect(id: "pill")`, so it slides. Logs `pomodoro board view mode=` |
| `BoardSettingsButton` | A 40pt circular `slider.horizontal.3`, using the same glass/material fallback. It is accent-tinted when open |
| Sidebars | Inserted in an `HStack` with a 1px divider, `.transition(.move(edge:).combined(with: .opacity))`, and toggled inside `withAnimation(Board.glide)`. The root also has `.animation(Board.glide, value:)` on each stored flag |
| View switch | Sessions uses `.opacity + .offset(x: -36)`; calendar uses `.opacity + .offset(x: 36)` |
| Window | Use the `PomodoroBoardWindow` pattern: an activation-policy flip, a theme-tracking `appearance` and `backgroundColor`, and `setFrameAutosaveName` |

These views are **`private`** to `PomodoroBoard.swift`: `BoardSectionTitle`, `SettingRow`, `BoardModeToggle`,
`BoardSettingsButton`, `BoardStats` and the others. That's why `ScheduleBoard.swift` has its own copies
(`ScheduleSectionTitle`, `ScheduleModeToggle`, `ScheduleGlass`). What *is* shared: `Board`, `BoardBackdrop`,
`boardEdge`, `BoardThemeStore`, `BrushedGrain`, `MenuAction`, `TallyStick` and `DeclareTarget`. To share more, drop
`private` rather than copying again.

### Stats, sessions view and calendar

- **`BoardStats`** has two sections. TODAY counts sessions whose `ended` falls on today's calendar day. ALL TIME counts
  every session.
- **Units.** `Board.units` = total minutes / 25, rounded to 1 decimal. A 40-minute focus is 1.6 sessions. The API uses
  the same formula.
- **`BoardColumn`** has:
  - a header: a tint dot, an editable name (`TextField`, committed on submit or blur; an empty name becomes `Untitled`), a units count, and a ⋯ menu with **Declare a session…** and **Delete project**;
  - a subtitle;
  - `SessionMarks` in a vertical scroll;
  - a drop target for `String` UUIDs, which calls `store.assign` and highlights the edge in the project tint;
  - a context menu.

  A new project (empty name) auto-focuses its name field. Deleting a project moves its sessions to Unassigned.
- **`SessionMarks`.**
  - *Unassigned* sessions are `GlowDot`s: a pulsing accent dot, 22pt hit area, draggable as its UUID string. Click
    opens `SessionMenu`.
  - *Assigned* sessions are tally groups. `TallyStick.sticks(for:)` lays the sessions end to end in minutes and cuts
    them into 25-minute sticks. A final partial stick gets `fraction < 1` and is drawn shorter at 0.75 opacity.
    `groups(for:)` packs 4 sticks per group, plus a 5th diagonal strike only when all 5 are full.
  - Clicking a stick opens `SessionMenu` for every session it spans (a submenu per session when there are several).
    Dragging a stick drags its last session.
- **`SessionMenu`.** An `NSMenu` popped up at the mouse, with: a disabled title (`Board.sessionLabel`), Unassigned and
  each project (checkmarked when current), and **Delete session**. `MenuAction` retains the closure via
  `representedObject`. Deleting has no confirmation.
- **`BoardCalendar`.** A 2-axis scroll:
  - a header row of lane cards (Unassigned plus projects, each 260 wide);
  - one row per day, newest first (`Board.days`): a 150-wide date card (date, Today/Yesterday tag, units) and one cell per lane holding `SessionMarks`, or "–".

### Settings panel and backup section

- **TIMER.** These rows write straight into `PomodoroModel`'s `@Published` settings, which persist through `didSet`:

  | Row | Range |
  | --- | --- |
  | Focus | 1–120 |
  | Short break | 1–60 |
  | Long break | 1–90 |
  | Long break after | 2–12 sessions |

  Changes take effect on the next phase that starts. A running phase keeps its end time.
- **THEME.** A grid of 5 per row over `BoardTheme.all`: 8 pastels, `bronze`, and 3 embroidered themes. Clicking sets
  `BoardThemeStore.shared.theme`. The dropdown, the board and Schedule all follow it. `.id(theme.id)` on the root views
  rebuilds them on a theme change, which **resets `@State`**, for example an open declare card or a half-typed project
  name.
- **BACKUP (`BoardBackupSection`)**, driven by `DataVault.shared`. It shows:
  - "Daily copy: saved X ago" (`lastSnapshot`; at launch this reads the newest file in `Backups/board`);
  - "GitHub: synced X ago", or the `syncProblem` text in red, when `pocket.backup.repo` is set;
  - "Copy: Google Drive", or the mirror folder name, when there is one;
  - when `vault.incoming` is non-empty, **Bring them in** (`vault.bringIn()`) and **Keep this Mac's** (an NSAlert confirm, then `vault.keepThisMac()`);
  - **Restore…**, a menu of `store.snapshots` labelled "day · N sessions · duration", which runs an NSAlert confirm and then `store.restore(snap)`;
  - **Show backups** (`vault.showInFinder()`).

## Data

**Model.** `Pomodoro/board.json`:

```json
{"projects": [{"id": "UUID", "name": "Quant Question Bank", "hue": 0}],
 "sessions": [{"id": "UUID", "ended": 785000000.0, "minutes": 40, "project": "UUID-or-absent",
               "started": 784997600.0, "declared": true}]}
```

- It is encoded with a **default `JSONEncoder`**. Dates are therefore `Double` seconds since 2001-01-01 (Foundation's
  reference date), *not* ISO 8601 and not Unix time. The output is compact (not pretty-printed), and nil optionals are
  omitted.
- `started` and `declared` exist only on declared sessions. The API converts `ended` to ISO 8601.
- `hue` is an index into `BoardTheme.projectOffsets` (8 slots). `addProject` takes the first unused one, then wraps
  around.
- Sessions are kept sorted by `ended` after `merge` and `declare`. `record` appends, which is in order anyway.

**Paths and backups** (`$ROOT` = `~/Library/Application Support/Pocket`, or `$POCKET_DATA_DIR`):

| What | Where |
| --- | --- |
| Live | `$ROOT/Pomodoro/board.json` (`PocketData.board`) |
| Daily snapshot | `$ROOT/Backups/board/board-YYYY-MM-DD.json`. Written on every save (`DataVault.snapshot(data, name: "board", count: sessions.count)`) and once at launch by `DataVault.start()`. Kept for 30 days, plus the first of every month forever |
| Kept aside | `$ROOT/Backups/board/board-before-restore-<stamp>.json` and `board-before-merge-<stamp>.json` |
| Quarantined | `$ROOT/Pomodoro/board.broken-<yyyy-MM-dd-HHmmss>.json` |
| Git | `board.json` at the root of `$ROOT/DataRepo`, pushed about 90 s after a save. The commit message is `backup <stamp> sessions=<n>` |
| Mirror | `<mirror>/board/board-YYYY-MM-DD.json` |

**Vault wiring.**
- `VaultFile(name: "board", noun: "session")`.
- `DataVault.ids(in:name: "board")` treats `sessions[].id` as "seen". Projects are **not** tracked.
- `PomodoroBoardStore.init` calls `register("board") { merge }`.

**Load (`PomodoroBoardStore.init`).** It decodes the file. On failure it logs, quarantines, then calls
`DataVault.recover("board")` (newest decodable snapshot), saves it back, and logs `recovered`. With nothing at all, it
starts empty.

**Merge (bring in).**
1. Keep the current board aside (`before-merge`).
2. Add projects and sessions with unknown ids.
3. Sort sessions by `ended` and save.

**Restore.** Keep the current board aside (`before-restore`), replace both arrays, then save. The save snapshots today's
file, so the restored data becomes today's copy.

### UserDefaults keys (domain `com.pranav.pocket`)

| Key | Type / default | Owner |
| --- | --- | --- |
| `pomodoro.focus` | Int, 25 (valid 1–120) | `PomodoroModel.focusMinutes` |
| `pomodoro.break` | Int, 5 (valid 1–60) | `PomodoroModel.breakMinutes` |
| `pomodoro.long` | Int, 15 (valid 1–90) | `PomodoroModel.longBreakMinutes` |
| `pomodoro.longEvery` | Int, 4 (valid 2–12) | `PomodoroModel.longEvery` |
| `pomodoro.streak` | Int, 0 (≥0) | `PomodoroModel.streak`, written on every change |
| `pomodoro.board.theme` | String theme id, default `BoardTheme.all[0]` (`sage`) | `BoardThemeStore`, shared by every themed app |
| `pomodoro.board.stats` | Bool, true | `@AppStorage`: stats sidebar visible |
| `pomodoro.board.panel` | Bool, false | `@AppStorage`: settings panel open |
| `pomodoro.board.mode` | String, `"sessions"` (or `"calendar"`) | `@AppStorage`: board view |
| `NSWindow Frame pomodoro.board` | AppKit frame string | `setFrameAutosaveName("pomodoro.board")` |
| `pocket.backup.repo`, `pocket.backup.githubUser`, `pocket.backup.folder` | Strings | `DataVault` (read by the backup section) |

Out-of-range stored values fall back to the defaults in `PomodoroModel.init`. `size.pomodoro` is never written, because
the panel isn't resizable. The timer state itself (`state`, `cycle`, `project`, `plan`, `hold` and `waiting`) is **not
persisted**.

## Flows

- **Launch.** `AppDelegate.sync()` → `PomodoroApp(spec:)` → `start()`, which is the base no-op. The model reads
  UserDefaults. `PomodoroBoardStore.shared` is **lazy**. It loads only on first touch: a finished focus, any `/pomodoro`
  route that uses `store`, or opening the board.
- **Open the dropdown.** `makeContent()` builds `PomodoroView` in an `NSHostingView` whose `appearance` follows the
  theme (via the `themeWatch` sink).
- **Timers.** One 1 s timer runs only while running. Nothing ticks while idle or paused.
- **Sleep and wake.** There's no wake handler. On the first tick after waking, an overdue phase ends:
  - a focus is recorded with its scheduled `ended`;
  - the next phase starts **from now**, not from the old deadline, so at most one transition happens per wake.
- **Quit.** `AppDelegate.applicationWillTerminate` → `stop()` → `stopTimer()` + `super.stop()`. A running phase is lost
  and the focus isn't recorded. The board is already on disk. `streak` survives.
- **Disable the app.** `stop()` runs the same way. `PocketServer` then answers `409`.

## Integrations

- **The HTTP API** (`PocketServer`, `127.0.0.1:8977`, loopback only). The browser `Origin` must be
  `localhost` or `127.0.0.1`. `X-Pocket-Source` names the caller in logs (falling back to `Origin`, then `User-Agent`,
  then `local`). Reference client: Preparo. See `CLAUDE.md` and [architecture](../architecture.md).
- **UserNotifications.** Needs a bundle id, so it only works in the installed `Pocket.app`.
- **`DataVault`** for git (`gh auth token -u <githubUser>`, `GIT_TERMINAL_PROMPT=0`) and the Drive or custom mirror.

## Logging

| Line | Identifiers / values |
| --- | --- |
| `pomodoro setting focus= / break= / long= / longEvery=` | the new value |
| `pomodoro start phase= planned=` | phase, minutes |
| `pomodoro pause phase= remaining=` / `pomodoro resume phase= remaining= waited= cycle=` | |
| `pomodoro phase end phase= planned= reason=` | reason is `reset` or `stopped from <source>` |
| `pomodoro phase end phase= planned= reason= next= nextPlanned=` | reason is `finished` or `skipped` |
| `pomodoro waiting for start project= cycle=` | hold engaged |
| `pomodoro remote start source= project= focus= rest= custom= hold= waiting= state= phase=` | plus `remote pause`, `remote resume` (`waiting=`) and `remote stop`, each with `source` and `project` |
| `pomodoro notification authorization granted= error=` / `notification skipped reason=no bundle body=` / `notification failed body= error=` | |
| `pomodoro session recorded session= minutes= project= total=` | session UUID, project UUID or `unassigned` |
| `pomodoro session declared session= minutes= ended= started= project= total=` / `pomodoro declare opened project=` / `declare rejected reason= day= minutes=` | |
| `pomodoro session assigned session= from= to=` / `session deleted session= remaining=` | |
| `pomodoro project created project= total=` / `renamed project= name=` / `deleted project= sessionsUnassigned=` | |
| `pomodoro board loaded / load failed / recovered from= / starting empty / merged projectsAdded= sessionsAdded= / merge failed / restored from= sessionsBefore= sessionsAfter= / restore failed / restore cancelled / save failed` | paths and counts |
| `pomodoro board opened projects= sessions=` / `refocused` / `closed` / `settings panel open=` / `view mode=` / `theme= previous=` | |
| `pocket vault …` (`keep local cancelled`, `kept aside name=board reason=`, `sync held name=board unseen=`) | from `DataVault` / backup section |

## Gotchas

- **Stop discards the focus.** Reset, `/stop`, quitting and disabling all drop the current focus without recording it.
  Skip on focus also records nothing.
- **`/start` without `project` clears the label on a running run** (`model.project = project` is unconditional). This
  is consistent with "re-labels", but a client that omits `project` on a resume-via-start loses it.
- **The streak never resets except on a long break.** Yesterday's 3 finished focuses plus today's first one will
  trigger a long break.
- **The UI and API ranges differ** (focus 120 vs 240, and so on). A plan above the UI range is fine, because plans don't
  touch UserDefaults. But anything that writes a plan into the settings must clamp it.
- **`board.json` dates are reference-date doubles.** External tools must add 978307200 to get Unix seconds.
  `python3 -m json.tool` shows them as plain numbers.
- **Lazy store and Bring them in.** If `PomodoroBoardStore.shared` hasn't been touched this launch, `register("board")`
  hasn't run. `DataVault.bringIn()` then logs `bring in skipped name=board reason=no-store` and the board stays held.
  In practice the board's own Backup section instantiates the store, but **Bring them in** pressed from Schedule's
  settings may not (inferred from code, not observed).
- **Sync "seen" tracks session ids only.** A project that exists only remotely never triggers a hold.
- **A theme change rebuilds the views** (`.id(themes.theme.id)` on `PomodoroView` and `PomodoroBoardView`), which
  resets transient `@State`.
- **The activation policy flips** to `.regular` while the board is open. Any other code that sets the activation policy
  can fight with it.
- **Embroidered themes** need `Resources/Embroidery/*.jpg` from the app bundle. `swift run` logs
  `board embroidery art missing`. `Flap.backdrop` and `cardTop` switch to opaque near-black on those themes (commit
  `392e8bd`, "keep the timer opaque").
- **History.**
  - `8ba3f86`: the first gold/silver timer.
  - `7388489` → `58c7459`: the forest design was replaced with split-flap cards.
  - `df97bf4`: long breaks and the board.
  - `55cfaa1`, `18ffd6a`, `d6bb281`: the API.
  - `c75a542`, `a9e7678`, `b6ebff6`: tally units.
  - `5f3d3a1`: calendar.
  - `0dbc9a6`, `a9a718b`, `2ccca07`: themes.
  - `40c094f`: guarded loads and restore.
  - `de68a58`: bring in / keep.
  - `9e53db9`: declare.
  - `e075277`: embroidery.
  - `271e7e5`: hold.

## How to change it safely

- **Scratch data.** Run `POCKET_DATA_DIR=/tmp/pocket-scratch swift run`, then drive it with
  `curl -X POST 127.0.0.1:8977/pomodoro/start -H 'X-Pocket-Source: test' -d '{"focus":1,"rest":1,"hold":true}'`.
  Notifications are skipped without a bundle. Never touch the real `$ROOT`.
- **Adding a timer setting.**
  1. Add a `@Published` property with a `didSet` that writes `pomodoro.<name>` and logs `pomodoro setting <name>=`.
  2. Read it in `init` with a range check and default.
  3. Add a `SettingRow` in `BoardSettingsPanel`.
  4. If the API should expose it, add it to `remoteState()` and the `CLAUDE.md` table.
- **Adding a per-run flag (like `hold`).**
  1. Add a `@Published` var to the model.
  2. Set it in `remoteStart` only when idle.
  3. Clear it in `reset`.
  4. Expose it in `remoteState`.
  5. Parse it in `PocketServer` (`flag`, `minutes`, `text` helpers that throw `Invalid`, which becomes `400`).
  6. Log it in the `remote start` line.
  7. Document it in `CLAUDE.md`.
- **Changing transitions.** Keep all of them in `toggle`, `reset`, `skip`, `advance` and `onTick`. Every path must end
  in `refresh()` (or `changed()`), or the menu bar goes stale.
- **Adding a field to `PomodoroSession` or `PomodoroProject`.** Make it optional with `= nil`, as `started` and
  `declared` are. Old `board.json` files and snapshots must keep decoding, or load quarantines the live file. Also check
  `DataVault.ids` if the new field should count as "seen".
- **Adding a board view or sidebar.** Store the flag in `@AppStorage("pomodoro.board.<name>")`. Add
  `.animation(Board.glide, value:)` at the root and a `.transition(.move(edge:).combined(with: .opacity))`. Style it with
  `Board.*` tokens plus `.boardEdge`, so all 12 themes, embroidery included, work. Check both a pastel and an
  embroidered theme.
- **Building another app's board.** Follow [the component structure above](#component-structure-copy-this-layout).
  Prefer making the needed `private` structs internal over copying them again.

## Open questions / known gaps

- The running timer isn't persisted. A crash or quit mid-focus loses it, with no recovery. It's unclear whether that is
  intended.
- No wake handling: a long sleep ends an overdue phase on the first tick but doesn't account for whole cycles missed
  (possibly fine).
- Board saves happen synchronously on the main thread (small files, so acceptable today).
- `PomodoroModel.progress(at:)` has no callers anywhere in `Sources/` (verified by grep), so it is dead code.
