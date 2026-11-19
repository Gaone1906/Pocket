# Architecture: the Pocket shell

The shell is everything that is not one specific sub-app: process start, the app registry, menu-bar items, the dropdown
("tray"), global hotkeys, setup, the loopback HTTP server and logging. Per-app detail lives in `apps/*.md`; persistence
in [data-and-backups.md](data-and-backups.md); themes in [theme.md](theme.md); build/run/test in
[operations.md](operations.md).

All sources are in `Sources/Pocket/` (one executable target, `Package.swift`, swift-tools 5.10, macOS 14+, links
`sqlite3`). No tests target exists.

## Shape in one picture

```
main.swift ── NSApplication(.accessory) ── AppDelegate.shared
                                            ├─ Layout.shared        (UserDefaults: which apps, where, shortcuts)
                                            ├─ BarController (bar)  (NSStatusItems: launcher line + one per menu-bar app)
                                            ├─ HotKeys              (Carbon RegisterEventHotKey)
                                            ├─ apps: [id: PocketApp]  ← makeApp(spec) from catalog (Factory.swift)
                                            ├─ tray: TrayApp        (the dropdown panel; itself a PocketApp)
                                            ├─ OtpWatcher / MailWatcher (one-time codes, optional)
                                            ├─ DataVault.shared     (snapshots, git sync)  → data-and-backups.md
                                            └─ PocketServer.shared  (127.0.0.1:8977)
```

`AppDelegate.sync()` is the single reconciliation point: it diffs `layout.enabled` against `apps`, creates/stops apps,
rebuilds status items, re-registers hotkeys, and starts/stops OTP and the App-Nap blocker. Everything that changes
layout, shortcuts, `hotKeys` or `otp` calls `Layout.onChange`, which is wired to `sync()`.

## Files

### `main.swift`
Four lines: `NSApplication.shared`, `setActivationPolicy(.accessory)` (no Dock icon; `Info.plist` also sets
`LSUIElement`), `app.delegate = AppDelegate.shared`, `app.run()`. This is the hook point for a temporary screenshot
harness (see [operations.md](operations.md#rendering-swiftui-views-to-png)): branch on an env var *before*
`app.delegate` is set.

### `AppDelegate.swift` — `final class AppDelegate: NSApplicationDelegate, UNUserNotificationCenterDelegate`
Singleton `AppDelegate.shared`. Stored: `layout`, `bar`, `hotKeys`, `otp: OtpWatcher`, lazy `mail: MailWatcher`,
`apps: [String: PocketApp]`, lazy `tray: TrayApp`, `otpRunning`, `awake` (activity token), `termSource`,
`recordingShortcut` (didSet → `sync()`).

- `applicationDidFinishLaunching`: `installEditMenu()` (hidden main menu so ⌘Z/X/C/V/A and ⌥⇧⌘V work in text
  fields of an accessory app) → `DataVault.shared.start()` → `UNUserNotificationCenter.current()` delegate + request
  `.alert/.sound/.badge` → `layout.onChange = sync` → `sync()` → observe `NSWorkspace.didWakeNotification` (calls
  `checkHealth()` on every `WebApp`) → observe distributed notifications `com.pranav.pocket.toggle` and
  `com.pranav.pocket.restart` (object = app id) → `PocketServer.shared.start()` → SIGTERM is ignored at the C level and
  re-handled by a `DispatchSourceSignal` on main that calls `NSApp.terminate` (so `pkill`/`install.sh` still run
  `applicationWillTerminate`) → if `!layout.setupDone` present setup → log `pocket started apps=...`.
- `applicationWillTerminate`: logs and calls `stop()` on every app (added in `e5a6cee` so Matinee's engine is shut
  down on quit).
- `sync()`: stop+remove apps no longer enabled; for each newly enabled id, `spec(id)` + `makeApp(spec)` (log
  `pocket app unavailable app=` if either is nil), set `onDisplayChange` → `bar.refresh(id)`, store, `start()`. Then
  `bar.sync(layout.bar ∩ apps)`, `hotKeys.register(...)` (empty list while `recordingShortcut` or `!layout.hotKeys`),
  `syncOtp()`, `syncAwake()`.
- `syncAwake()`: while any enabled `WebApp` has `site.realtime` (WhatsApp, Slack), holds a
  `ProcessInfo.beginActivity(.userInitiatedAllowingIdleSystemSleep)` to stop App Nap.
- `syncOtp()`: starts/stops `otp` and `mail` when `layout.otp` flips.
- `open(id, source:)`: toggles the app anchored to its status item (or the launcher if it lives in the dropdown).
  Sources seen in logs: `click`, `hotkey`, `dropdown`, `remote`, `notification`, `setup`, `launcher`, `escape`.
- `hideOthers(except:)`: hides every app and the tray with reason `switched` (only one panel visible at a time).
- `appendCommonItems(to:for:)`: right-click menu tail: "Move to menu bar/dropdown", "Set up Pocket…", "Add Gmail
  account for codes…" (only if `layout.otp && mail.available`), "Quit Pocket".
- `userNotificationCenter(didReceive:)`: a notification whose `userInfo["app"]` is an enabled id opens that app
  (source `notification`). `willPresent` always shows banner + sound.

Remote control from a shell (no HTTP; snippet not verified, the mechanism is):
```bash
osascript -l JavaScript -e 'ObjC.import("Foundation"); $.NSDistributedNotificationCenter.defaultCenter.postNotificationNameObjectUserInfoDeliverImmediately("com.pranav.pocket.toggle", "todo", $(), true)'
```
`com.pranav.pocket.restart` only acts on `WebApp`s (`web.restart(reason: "remote")`).

### `PocketApp.swift` — base class, `Panel`, `AppIcon`
- `final class Panel: NSPanel`: `canBecomeKey/Main = true`; `cancelOperation` (Esc) → `onEscape`.
- `class PocketApp: NSObject, NSWindowDelegate`: `spec`, `onDisplayChange`, `panelIfLoaded`.
  - Overridable: `defaultSize` (460×680), `minSize` (360×420), `resizable` (true), `makeContent() -> NSView`,
    `start()`, `didShow()`, `didHide()`, `shouldStayOpen() -> Bool` (false), `menuItems() -> [NSMenuItem]`,
    `barImage() -> NSImage?` (default `AppIcon.render(spec)`), `barTitle() -> NSAttributedString?` (nil), `stop()`,
    and `toggle/show/hide` (only `LinkApp` overrides `toggle`).
  - `changed()` → `onDisplayChange?(self)` → `BarController.refresh(id)`. Call it whenever the bar image/title should
    change.
  - `panel` (lazy): non-activating, titled, full-size-content, transparent hidden titlebar, not movable, `.floating`,
    `hidesOnDeactivate = false`, `canJoinAllSpaces + fullScreenAuxiliary + transient`, traffic lights hidden, content =
    `makeContent()` (called once, on first access).
  - Size: if resizable, restored from UserDefaults `size.<id>` (`NSStringFromSize`) when ≥ `minSize`, saved in
    `windowDidEndLiveResize`.
  - `show(anchor:source:)`: `hideOthers` → position centred under the status item's button window, clamped 8 pt
    inside the screen's `visibleFrame`, 6 pt below; with no anchor, centred on the main screen → `NSApp.activate` →
    `makeKeyAndOrderFront` → log `pocket shown app= source= anchored=` → `didShow()`.
  - `hide(reason:)`: no-op if not visible; `orderOut`; `NSApp.hide(nil)` unless reason is `focus lost` or `switched`
    (returns focus to the previous app) → log `pocket hidden app= reason=` → `didHide()`.
  - `windowDidResignKey`: hides with `focus lost` unless `shouldStayOpen()` (WebApp keeps open while e.g. a popup or
    file dialog is up).
- `enum AppIcon`: `side = 18`. `glyph(spec)`: SVG string from `spec.glyph` via `NSImage(data:)`, else SF Symbol
  `spec.symbol`. `render(spec, unread:, tint:)`: 21×18 non-template image, glyph tinted with `tint`
  (`.labelColor`); `unread > 0` draws a red pill with the number (`99+` cap), `unread < 0` a 7 pt red dot. Logs
  `pocket menu glyph missing` if neither source works.

### `Catalog.swift` — `WebSpec`, `AppSpec`, `catalog`, `spec(_:)`
`WebSpec` (web apps only): `url`, `store` (UUID for `WKWebsiteDataStore(forIdentifier:)`, i.e. the cookie jar; never
change one or the user is signed out), `hosts` (domains kept in-panel; others open in the browser), `zoom`, `agent`
(user-agent string: `safariAgent` or `chromeAgent`), `disguise` (JS injected at document start; `chromeDisguise`
fakes `navigator.userAgentData`/`vendor`/`window.chrome` for Slack), `realtime` (never throttled, blocks App Nap),
`unloadAfter` (seconds idle-hidden before the web view is dropped; non-nil also means "load on first open").
`signInHosts` lists identity providers allowed in popups (used by `WebApp`).

`AppSpec` fields:

| Field | Meaning |
| --- | --- |
| `id` | Stable key used everywhere: layout arrays, `shortcuts`, `size.<id>`, notification `userInfo["app"]`, distributed notification object, logs. Never rename. |
| `name` | Display name (setup, tray tile, tooltips, accessibility). |
| `summary` | One line in setup and the tray tile tooltip. |
| `symbol` | SF Symbol used when `glyph` is nil (and in setup's badge fallback). |
| `glyph` | Optional SVG source (from `Glyphs`); drawn tinted. |
| `hotKey` | Optional default key code (`kVK_ANSI_*`); always offered as ⌥+key. |
| `web` | `WebSpec` → app becomes a `WebApp` (or `MatineeApp` for `matinee`). |
| `link` | URL → app becomes a `LinkApp` (opens in a browser; no panel). |
| `browser` | Bundle id for `link` (falls back to default browser if missing). |
| `claimsHotKey` | When first offered, takes its default key away from any app already holding it (else it gets none). |
| `pinnedByDefault` | When first offered to an existing setup, lands in the menu bar instead of the dropdown. |

The catalog (order = setup order):

| id | name | symbol | glyph | default key | kind | pinnedByDefault | claimsHotKey |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `whatsapp` | WhatsApp | `message.fill` | `Glyphs.whatsapp` | ⌥W | web, realtime, zoom 0.8, Safari UA | no | no |
| `slack` | Slack | `number` | `Glyphs.slack` | ⌥S | web, realtime, Chrome UA + disguise | no | no |
| `spotify` | Spotify | `music.note` | `Glyphs.spotify` | ⌥M | web, unload after 1800 s | no | no |
| `gmail` | Gmail | `envelope.fill` | `Glyphs.gmail` | ⌥G | web | no | no |
| `outlook` | Outlook | `tray.full.fill` | – | none | web | no | no |
| `calendar` | Calendar | `calendar` | – | ⌥D | native | no | no |
| `todo` | To-do | `checklist` | – | ⌥T | native | no | no |
| `pomodoro` | Pomodoro | `timer` | – | ⌥P | native | no | no |
| `schedule` | Schedule | `sun.horizon` | – | ⌥O | native | **yes** | **yes** |
| `calculator` | Calculator | `plusminus.circle` | – | ⌥C | native | no | no |
| `scratchpad` | Scratchpad | `note.text` | – | ⌥N | native | no | no |
| `stats` | System Stats | `gauge.with.dots.needle.33percent` | – | none | native | no | no |
| `preparo` | Preparo | `graduationcap.fill` | `Glyphs.preparo` | none | link `http://localhost:8960/` in `com.ardia.browser` | no | no |
| `matinee` | Matinee | `ticket.fill` | `Glyphs.matinee` | none | web `http://127.0.0.1:47811/` (`MatineeApp`) | no | no |

Web store UUIDs are `6B1F2C1E-0A57-4C3B-9E4B-0E5C4A0F7A0n`, n = 1..6 in the order whatsapp, slack, spotify, gmail,
outlook, matinee. The tray uses a separate `traySpec` (id `pocket`, `square.grid.2x2`) that is not in the catalog.

### `Factory.swift` — `makeApp(_ spec:) -> PocketApp?`
`web != nil` → `MatineeApp` if id is `matinee`, else `WebApp`; `link != nil` → `LinkApp`; else a `switch` on id:
`calendar`→`CalendarApp`, `todo`→`TodoApp`, `pomodoro`→`PomodoroApp`, `schedule`→`ScheduleApp`,
`calculator`→`CalculatorApp`, `stats`→`StatsApp`, `scratchpad`→`ScratchpadApp`; unknown → nil (logged by `sync` as
`pocket app unavailable`).

### `LinkApp.swift` (shell-level, tiny)
Overrides `toggle` only: hides others, opens `url` in `spec.browser` via `NSWorkspace.open(_:withApplicationAt:)`, or
the default browser if the bundle id isn't installed. Never creates a panel. Logs `pocket link opened|open failed|browser missing`.

### `Layout.swift` — `final class Layout: ObservableObject` (`Layout.shared`)
Owns all placement/shortcut state, in `UserDefaults.standard` (domain `com.pranav.pocket` for the installed bundle; see
the gotcha on unbundled runs below).

| Key | Type | Meaning |
| --- | --- | --- |
| `layout.bar` | `[String]` | ids shown as their own status items, in order |
| `layout.tray` | `[String]` | ids in the dropdown, in order |
| `layout.offered` | `[String]` | every catalog id this install has already seen (migration bookkeeping) |
| `setup.done` | Bool | setup finished at least once |
| `hotkeys.enabled` | Bool | global shortcuts on (default true when absent) |
| `otp.enabled` | Bool | one-time-code watching on |
| `shortcuts` | Data (JSON `[id: Shortcut]`) | per-app shortcut |
| `shortcuts.offered` | `[String]` | ids whose default shortcut has already been offered |
| `size.<id>` | String (`NSStringFromSize`) | saved panel size (written by `PocketApp`) |

Published: `bar`, `tray` (private set), `setupDone`, `hotKeys`, `otp`, `shortcuts` (private set). `enabled = bar +
tray`. Stale ids not in the catalog are dropped on load.

Migrations in `init()` (run every launch, idempotent):
1. **New apps for existing setups.** `listed = layout.offered` (fallback when absent: every non-link catalog id).
   `fresh` = catalog ids not listed and not already placed. Only if `setup.done`: `pinnedByDefault` ones append to
   `layout.bar` (log `pocket new apps added to menu bar`), the rest to `layout.tray` (`... to dropdown`). Then
   `layout.offered` = all catalog ids. On a first run (`setup.done` false) nothing is placed; setup decides.
2. **Default shortcuts.** `offered = shortcuts.offered` (fallback: keys of the stored map). For each catalog app not
   yet offered with a `hotKey`: if some app already holds ⌥+key, skip unless `claimsHotKey`, in which case the holders
   lose it (log `pocket shortcut claimed app= from= keys=`); then assign ⌥+key. Persist `shortcuts` if it was absent or
   anything was added (log `pocket shortcut defaults given apps=`). A user who cleared a shortcut keeps it cleared
   because the id is in `shortcuts.offered`.

Mutators: `apply(bar:tray:)` (dedupes, bar wins over tray, persists, logs `pocket layout changed`, `onChange`),
`move(id, toBar:, before:)`, `setShortcut(id, Shortcut?)` (steals the combo from any other app with log `pocket shortcut
taken over`, persists, logs `pocket shortcut set`, `onChange`). Setting `hotKeys`/`otp` also fires `onChange`;
`setupDone` does not.

### `Shortcuts.swift` — `struct Shortcut: Codable, Equatable { code, mods, label }`
Carbon key code + Carbon modifier mask (`cmdKey`, `optionKey`, `controlKey`, `shiftKey`) + display label.
`Shortcut.option(code)` builds ⌥+letter. `Shortcut.from(NSEvent)` requires at least one of ⌘⌥⌃ (else nil → beep),
labels letters A–Z, Space/↩/⇥/arrows/F1–F12, else the typed character, else `#<code>`. `display` renders `⌃⌥⇧⌘` +
label. Equality includes `label`.

### `HotKeys.swift` — `final class HotKeys`
`register(_ wanted: [(id, Shortcut)])`: skips if the signature string is unchanged; otherwise unregisters all, installs
a single Carbon `kEventHotKeyPressed` handler once, and registers each with `EventHotKeyID(signature: 'PKET',
id: index)`. The handler maps the index back through `ids` and calls `AppDelegate.shared.open(id, source: "hotkey")` on
main. Failures log `pocket hotkey failed app= keys= status=` (e.g. combo already taken by another process); success logs
`pocket hotkeys registered id=keys,...`. Carbon hotkeys need no Accessibility permission.

### `StatusBar.swift` — `final class BarController`
- `launcher`: always present; a 9×18 template image of a thin vertical line (`divider()`), tooltip "Pocket: more apps
  and layout". Left click toggles the tray (source `launcher`); right click shows `appendCommonItems(for: nil)`.
- `sync(ids)`: if the order changed, removes and recreates all app status items (created in reverse so they appear
  left-to-right in `ids` order; log `pocket menu bar rebuilt items=`), then `refresh` each.
- `refresh(id)`: `button.image = app.barImage()`, `attributedTitle = app.barTitle() ?? ""`.
- `anchor(for:)`: the app's item or, for dropdown apps, the launcher (so their panel opens under the line).
- Click → `AppDelegate.open(id, "click")`; right click → `app.menuItems()` + common items. Menus are attached
  temporarily and `performClick` is used to pop them.

### `Tray.swift` — `TrayApp` (the dropdown) and `TrayView`
`TrayApp: PocketApp` with `traySpec`, fixed 392×404, content `NSHostingView(TrayView)`. `TrayView` shows two sections
("Menu bar" = `layout.bar`, "Dropdown" = `layout.tray`) as 5-column grids of 64×56 tiles (template-tinted glyph + name,
tooltip = summary). Tap → hide tray and `open(id, source: "dropdown")`. Drag-and-drop uses the id `String` as payload;
dropping on a tile inserts before it, on the section appends (`layout.move`). "Set up…" button →
`AppDelegate.presentSetup()`.

### `Setup.swift` — first-run and "Set up Pocket…" window
`SetupController.shared.present()` creates (or refocuses) a 720×640 titled, closable `NSWindow` hosting `SetupView`.
Shown automatically at launch while `setup.done` is false, and from the right-click menu and the tray button.

- Step 1 "Choose your apps" (`ChooseStep`): one `AppRow` per catalog app: badge, name, summary, on/off switch, and when
  on a Menu bar/Dropdown segmented picker and a `ShortcutField`. On a first run (`layout.enabled` empty) these start in
  the dropdown: `calendar, todo, pomodoro, calculator, stats` (`firstRunTray`). Extras: global shortcuts toggle
  (`layout.hotKeys`), OTP toggle (`layout.otp`), "Open Pocket at login" via `SMAppService.mainApp.register/unregister`
  with status text. **Continue** → `SetupModel.apply()`: keeps existing order for already placed apps, appends new
  ones in catalog order, `layout.apply`, step 2.
- Step 2 "Sign in & permissions" (`SignInStep`): a **Sign in** button per enabled web app (`app.show(anchor: nil,
  source: "setup")`, a centred panel); Calendar access row (`EKEventStore.requestFullAccessToEvents`, or deep link
  `x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars` when denied); Full Disk Access row when
  OTP is on (`...?Privacy_AllFiles`). **Done** → `setup.done = true`, close.
- `ShortcutField`: click to record; a local `keyDown` monitor captures the next combo (Esc cancels, Delete/Forward
  Delete clears). While recording, `AppDelegate.recordingShortcut = true`, which unregisters all global hotkeys so the
  combo reaches the field. Only one field records at a time (`ShortcutField.active`).
- Logs: `pocket setup opened|refocused|applied|done|closed`, `login item`, `calendar access`, `opened settings`,
  `sign in`.

### `PocketServer.swift` — loopback HTTP API
`PocketServer.shared.start()`: `NWListener` on TCP 8977 with `requiredInterfaceType = .loopback`, queue main.
Hand-rolled HTTP/1.1: reads until `\r\n\r\n` + `Content-Length` (max 256 KiB, then drops), one request per
connection, always `Connection: close`, JSON bodies via `JSONSerialization`.

- Origin policy: no `Origin` header → allowed; `Origin` host `localhost`/`127.0.0.1` → allowed with CORS headers
  (incl. `Access-Control-Allow-Private-Network: true`); anything else → `403` (log `pocket server refused`). `OPTIONS` →
  `204`.
- Caller identity for logs: `X-Pocket-Source` → `Origin` → `User-Agent` → `local`.
- Routes: `GET /` (route table), and the `/pomodoro*` routes, which return `409` if Pomodoro isn't enabled. Input
  validation throws `Invalid` → `400` with a message; other errors → `500`. Full route contract and integration rules:
  `CLAUDE.md` and [apps/pomodoro.md](apps/pomodoro.md).
- To add a route: add it to the `routes` dictionary (served by `GET /`), a `case` in `route(_:)`, validate with the
  `object/text/flag/minutes` helpers, log the action with `source`, and add it to `CLAUDE.md`'s table.

### `DeclareSession.swift` — `DeclareSessionCard` (Pomodoro UI)
Despite sitting beside the shell files, this is a Pomodoro board view: the "Declare a session…" sheet (day chips,
minutes with presets 25/40/60/90/120, optional from–to time, max 720 min, cannot be in the future). Commits via
`PomodoroBoardStore.declare(minutes:ended:started:project:)`; without a time it ends now (today) or at 18:00 (past
day). Logs `pomodoro declare rejected` on a blocked commit. Styling via `Board.*` tokens. See
[apps/pomodoro.md](apps/pomodoro.md).

### `Log.swift` — `note(_:)`
`note(message)` appends `"<ISO 8601 UTC timestamp> <message>\n"` to `~/Library/Logs/pocket.log` (stderr if the file
can't be opened). Rotation happens once, at first use per launch: if the file is > 5,000,000 bytes it becomes
`pocket.log.1` (the previous `.1` is deleted). Not affected by `POCKET_DATA_DIR`. Not thread-synchronised beyond
`FileHandle.write`; called from main and background queues alike. Conventions: lower-case, prefix with the area
(`pocket ...`, `pomodoro ...`, `schedule ...`, `board ...`), then `key=value` pairs carrying ids (`app=`, `source=`,
`reason=`, `project=`) and the values that decided the outcome. How to read: [operations.md](operations.md#reading-logs).

### `Glyphs.swift` — `enum Glyphs`
Static SVG strings: `preparo`, `whatsapp`, `slack`, `spotify`, `gmail`, `matinee`. Drawn by `AppIcon` as tinted
images, so only the shape matters (fill/stroke colour is replaced). Use a square `viewBox`; raw strings use `#"…"#`
or `##"…"##` when the SVG contains `"#`.

## Sub-app lifecycle

| Event | Who triggers | What runs |
| --- | --- | --- |
| Create | `AppDelegate.sync()` when the id enters `layout.enabled` (launch, setup, drag into a section) | `makeApp(spec)` → `init(spec:)`; `onDisplayChange` wired; `start()` |
| Start | right after create | `start()`: timers, store observers, first `changed()`. `WebApp.start()` builds the panel and loads unless `unloadAfter` is set (deferred to first open). The panel/`makeContent()` is otherwise lazy, built on first `show`. |
| Bar refresh | app calls `changed()` | `barImage()` / `barTitle()` read again |
| Show | click, hotkey, tray tile, notification tap, distributed `toggle`, setup sign-in | `toggle` → `show`: others hidden (`switched`), panel positioned, activated, `didShow()` |
| Hide | Esc (`escape`), focus loss (`focus lost`, unless `shouldStayOpen()`), toggle again (same source string), another app shown (`switched`) | `orderOut`, `NSApp.hide` unless focus lost/switched, `didHide()` |
| Remove | id leaves `layout.enabled` | `stop()` (base: detach delegate, `orderOut`, drop panel), removed from `apps` |
| Quit | "Quit Pocket", SIGTERM (`pkill`, `install.sh`) | `applicationWillTerminate` → `stop()` on every app |

Rules: `didShow` is where you refresh "now"-dependent state (Schedule `tick()`, Calendar reload, Stats fast polling).
`didHide` is where you slow down or schedule unloads (`WebApp.scheduleUnload`). Always call `super.stop()` from an
override. Per-app overrides are listed in each `apps/*.md`.

## Adding a new sub-app (checklist)

1. **View + class.** New `Sources/Pocket/<Name>App.swift`: `final class <Name>App: PocketApp` overriding
   `defaultSize` (and `resizable = false` for fixed panels), `makeContent()` (usually `NSHostingView(rootView:)`), and
   whichever of `start/didShow/didHide/stop/menuItems/barImage/barTitle` it needs. Call `changed()` when the bar should
   update.
2. **Catalog.** Add an `AppSpec` to `catalog` in `Catalog.swift` at the position it should appear in setup. Pick a
   permanent `id`. Set `hotKey` (check the table above for collisions; set `claimsHotKey` only if it must win), and
   `pinnedByDefault` if existing users should get it in the menu bar.
3. **Glyph (optional).** Add an SVG to `Glyphs` and reference it; otherwise an SF Symbol in `symbol`.
4. **Factory.** Add a `case "<id>": return <Name>App(spec: spec)` to `makeApp` (web and link apps need nothing here,
   except a dedicated subclass like `MatineeApp`). Without this, `sync` logs `pocket app unavailable`.
5. **Data.** Persisted files go under `PocketData.root` (so `POCKET_DATA_DIR` isolates them), load through
   `DataVault`'s guard, snapshot on save, and get a `VaultFile.all` row if they hold user data; see
   [data-and-backups.md](data-and-backups.md). UserDefaults keys: prefix with the app id (`<id>.…`).
6. **Logging.** `note("<id> ...")` on start, every state change, every failure, with ids and deciding values.
7. **Notifications (optional).** Set `content.userInfo = ["app": spec.id]` so tapping opens the app.
8. **First-run default (optional).** Add the id to `firstRunTray` in `Setup.swift` to pre-select it for new users.
9. **Docs.** README apps table and shortcut list, `CLAUDE.md` if agents need to know it, a new `docs/kb/apps/<id>.md`,
   and the KB index.
10. **Verify.** Build in a scratch copy, render views to PNG, run against `POCKET_DATA_DIR` (see
    [operations.md](operations.md)). After install, the log should show `pocket new apps added to ...` and
    `pocket shortcut defaults given apps=<id>` once, and `pocket hotkeys registered ...<id>=⌥X`.

## Gotchas

- **Migrations run once per id.** Because `layout.offered` / `shortcuts.offered` record ids, changing an existing
  app's default `hotKey` or `pinnedByDefault` has no effect on installs that already saw it. To push a change to
  existing users you need a new migration.
- **Fallback for `layout.offered`** excludes link apps, so when that key was introduced (`3376d2d`/`6cafa8a`) link
  apps counted as fresh. The real defaults now contain `layout.offered`, so this fallback only matters for very old
  installs.
- **Unbundled runs use a different UserDefaults domain.** A bare `.build/*/Pocket` binary reads and writes the domain
  `Pocket`, not `com.pranav.pocket` (both exist on the owner's Mac). Layout/shortcuts there are a separate, mostly
  empty set.
- **`AppDelegate` needs a bundle.** `UNUserNotificationCenter.current()` in `applicationDidFinishLaunching` crashes in
  an unbundled binary; anything that only needs views must avoid setting `AppDelegate` (see operations).
- **Hotkeys are dropped while recording** a shortcut in setup; if setup is closed mid-recording, `onDisappear` → `stop()`
  restores them.
- **Same-combo collisions** inside Pocket are resolved by stealing (`setShortcut`), but a combo held by another
  process fails registration silently except for the log line.
- **Hide returns focus** via `NSApp.hide(nil)` except for `focus lost`/`switched`; a new hide reason that should not
  bounce focus must be added to that condition in `PocketApp.hide`.
- Stale UserDefaults keys from removed features exist in the real domain (`size.claude`, `scene.*`); they are inert.

## Open questions / gaps

- No unit tests; verification is by build, PNG render and log reading.
- `Log.swift`'s rotation runs only when `logFile` is first touched, so a very long-running process can exceed 5 MB.
- `ScratchpadApp` stores pages under a hard-coded `~/Library/Application Support/Pocket/Scratchpad`, not
  `PocketData.root`, so `POCKET_DATA_DIR` does not isolate it (see [apps/scratchpad.md](apps/scratchpad.md)).
- `DataVault.mirrorFolder` defaults to the real Google Drive `My Drive/Pocket Backups` regardless of
  `POCKET_DATA_DIR`; scratch runs can overwrite real Drive copies. Full list and workaround in
  [operations.md](operations.md#testing-safely-with-pocket_data_dir).
