# Operations: build, run, test, ship

How to build Pocket, run it without touching real data, check UI visually, read logs, and land changes the way the
owner expects. Code structure is in [architecture.md](architecture.md); persistence and backups in
[data-and-backups.md](data-and-backups.md); current branches in [handoff.md](handoff.md).

## Toolchain

- Swift package, `swift-tools-version:5.10`, one `executableTarget` `Pocket` at `Sources/Pocket`, links `sqlite3`,
  platform macOS 14+. No Xcode project, no tests target, no third-party dependencies.
- Needs the Xcode command line tools. The owner's machine has Apple Swift 6.3.3 targeting `arm64-apple-macosx26.0`
  (language mode stays 5 because of the 5.10 tools version).
- Frameworks used: AppKit, SwiftUI, Combine, Carbon (hotkeys), EventKit, UserNotifications, ServiceManagement,
  WebKit, Network, Security (Keychain), CryptoKit, IOKit.ps, SQLite3.

## Build

```bash
swift build                    # debug → .build/debug/Pocket
swift build -c release         # what install.sh uses → .build/release/Pocket
```

A plain build only proves it compiles. The binary is not a bundle: it has no `Info.plist`, no bundle id, no
`Contents/Resources`, so running it directly crashes in `AppDelegate` (see below). When several agents share a
worktree, build in your own rsync'd copy so you don't clobber the shared `.build`:

```bash
S=/path/to/your/scratchpad
rsync -a --delete --exclude .build --exclude .git /Users/pranav.yarasi/Desktop/workspace/personal/pocket-schedule/ "$S/pocket/"
cd "$S/pocket" && swift build
```

## Install: `scripts/install.sh`

zsh, `set -euo pipefail`. Steps:
1. `root` = repo root; `app` = `${POCKET_APP_DIR:-$HOME/Applications}/Pocket.app`.
2. Identity = `POCKET_SIGN_IDENTITY`, else the first `Apple Development` identity from
   `security find-identity -v -p codesigning`, else `-` (ad hoc).
3. `swift build -c release`; binary from `--show-bin-path`.
4. `pkill -x Pocket` then `sleep 1` (**kills any running Pocket, whichever copy**; SIGTERM, which Pocket handles by
   terminating cleanly and calling `stop()` on every app).
5. `rm -rf "$app"`, recreate `Contents/MacOS/Pocket`, copy `Resources/Info.plist`, copy `Resources/Embroidery` to
   `Contents/Resources/Embroidery`.
6. `codesign --force --sign "$identity" "$app"` (no entitlements file, no hardened runtime, not sandboxed).
7. `open "$app"` unless `POCKET_NO_OPEN=1`.

Env knobs: `POCKET_APP_DIR`, `POCKET_SIGN_IDENTITY`, `POCKET_NO_OPEN`. Only run it when the user asks to install; it
replaces and relaunches the real app, which then runs against real data.

`Info.plist` (`Resources/Info.plist`): `CFBundleIdentifier com.pranav.pocket`, version `2.0` (build `2`),
`LSMinimumSystemVersion 14.0`, `LSUIElement true`, and usage strings for microphone and camera (the calendar usage strings were removed with EventKit).

## Testing safely with `POCKET_DATA_DIR`

`PocketData.root` (`DataVault.swift`) is `$POCKET_DATA_DIR` when set and non-empty, else
`~/Library/Application Support/Pocket`. It is read once (static `let`), so set it in the environment before launch (or
`setenv` before anything touches `PocketData`). Under it: `Pomodoro/board.json`, `todos.json`, `schedule.json`,
`Backups/`, `DataRepo/`, `sync-state.json`.

**What it does NOT isolate** (verified in source; this contradicts the "every path ... then lives there" line in
`CLAUDE.md`):

| Still real | Where | Risk in a scratch run |
| --- | --- | --- |
| Drive mirror | `DataVault.mirrorFolder`: `pocket.backup.folder`, else `~/Library/CloudStorage/GoogleDrive-*/My Drive/Pocket Backups` (only if Drive for Desktop is installed) | Every snapshot copies to `<mirror>/<name>/<name>-YYYY-MM-DD.json`, **overwriting today's real Drive copy**. A fresh scratch `ScheduleStore` seeds and saves, so even loading it triggers this. |
| Git sync target | UserDefaults `pocket.backup.repo` / `pocket.backup.githubUser` | With the real bundle id, scratch data would sync toward the real data repo (clone lands in the scratch `DataRepo`; the unseen-data guard may hold it, but don't rely on it). |
| UserDefaults | domain of the running process | All layout, shortcuts, settings. |
| Scratchpad pages | hard-coded `~/Library/Application Support/Pocket/Scratchpad` | Real notes read and written. |
| Gmail OAuth client | hard-coded `~/Library/Application Support/Pocket/google-client.json`; tokens in Keychain service `com.pranav.pocket.gmail` | Real accounts. |
| Messages DB (OTP) | `~/Library/Messages/chat.db` | Read-only, but real. |
| Log | `~/Library/Logs/pocket.log` | Scratch lines interleave with the real app's. |
| Matinee | engine path `pocket.matinee.path` (default `~/Files/Personal Projects/Matinee`), logs `~/Library/Logs/Matinee` | Starts a real engine. |
| Web sessions | `WKWebsiteDataStore(forIdentifier:)` UUIDs from the catalog | Believed scoped per bundle id (not verified). |

Rules that follow:
- **Always neutralise the mirror** in the domain your scratch process uses, before it runs:
  `defaults write <domain> pocket.backup.folder "$S/mirror"`, and make sure `pocket.backup.repo` is absent there.
- **Bare `.build` binary** → UserDefaults domain `Pocket` (exists on the owner's Mac, separate from
  `com.pranav.pocket`). So for shot harnesses: `defaults write Pocket pocket.backup.folder "$S/mirror"`.
- **Running the full app on scratch data**: build a scratch bundle with a different bundle id so UserDefaults (and,
  probably, web data) are separate, and never use `install.sh` for it (it `pkill`s the real app):

```bash
cd "$S/pocket" && swift build
app="$S/PocketDev.app"
rm -rf "$app" && mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp .build/debug/Pocket "$app/Contents/MacOS/Pocket"
cp Resources/Info.plist "$app/Contents/Info.plist"
plutil -replace CFBundleIdentifier -string com.pranav.pocket.dev "$app/Contents/Info.plist"
cp -R Resources/Embroidery "$app/Contents/Resources/Embroidery"
codesign --force --sign - "$app"
defaults write com.pranav.pocket.dev pocket.backup.folder "$S/mirror"
mkdir -p "$S/data" && POCKET_DATA_DIR="$S/data" "$app/Contents/MacOS/Pocket" &
```

  Expect clashes if the real Pocket is running: port 8977 is taken (`pocket server failed`), ⌥-hotkeys fail to
  register (`pocket hotkey failed ... status=`), and duplicate status items appear. Setup will open (fresh domain);
  don't enable OTP, Gmail codes or Matinee in it. To seed realistic data, copy a snapshot from
  `~/Library/Application Support/Pocket/Backups/<name>/` into `$S/data` (read-only use of real data). Quit with
  `kill %1` or the menu; never `pkill -x Pocket`.

## Rendering SwiftUI views to PNG

For visual checks without launching the app or touching real data. Do it only in an rsync'd scratch copy; never commit
the harness.

Why the shape: `AppDelegate.applicationDidFinishLaunching` calls `UNUserNotificationCenter.current()`, which crashes in a
bare `.build` binary (no bundle). So the harness branches in `main.swift` **before** `app.delegate = AppDelegate.shared`,
renders, and exits. Avoid views whose body touches `AppDelegate.shared` at render time (instantiating it creates status
items); closures that reference it are fine because they never fire.

1. Copy and isolate:
   ```bash
   rsync -a --delete --exclude .build --exclude .git <worktree>/ "$S/shots-src/"
   mkdir -p "$S/data" "$S/mirror" "$S/shots"
   defaults write Pocket pocket.backup.folder "$S/mirror"
   ```
2. In the copy, `main.swift`:
   ```swift
   import AppKit

   let app = NSApplication.shared
   app.setActivationPolicy(.accessory)
   if let out = ProcessInfo.processInfo.environment["SHOTS"] {
       scheduleShots(to: out)
       exit(0)
   }
   app.delegate = AppDelegate.shared
   app.run()
   ```
3. Add `Sources/Pocket/Shots.swift` in the copy:
   ```swift
   import AppKit
   import SwiftUI

   func shoot<V: View>(_ view: V, size: CGSize, dark: Bool = false, to path: String) {
       let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
       host.frame = NSRect(origin: .zero, size: size)
       host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
       let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
       window.contentView = host
       host.layoutSubtreeIfNeeded()
       guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return note("shots no bitmap path=\(path)") }
       host.cacheDisplay(in: host.bounds, to: rep)
       do {
           try rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
           note("shots wrote path=\(path)")
       } catch {
           note("shots write failed path=\(path) error=\(error.localizedDescription)")
       }
   }

   func scheduleShots(to out: String) {
       shoot(ScheduleDropdown(store: ScheduleStore.shared) {}, size: CGSize(width: 380, height: 560), to: out + "/schedule-dropdown.png")
       shoot(ScheduleDropdown(store: ScheduleStore.shared) {}, size: CGSize(width: 380, height: 560), dark: true, to: out + "/schedule-dropdown-dark.png")
   }
   ```
   Use the real view type and panel size from the app's `makeContent()` / `defaultSize`. For state that depends on
   time, set it on the store before shooting.
4. Build and run in the copy:
   ```bash
   cd "$S/shots-src" && swift build
   SHOTS="$S/shots" POCKET_DATA_DIR="$S/data" .build/debug/Pocket
   ```
5. Look at the PNGs with the Read tool. Seed `$S/data` with a copied snapshot when you need realistic content.

Notes: `cacheDisplay` draws through AppKit, so `NSViewRepresentable`s, text fields and scroll views render, but
vibrancy/materials and some animations may not look exactly like the live panel. SwiftUI's `ImageRenderer` is an
alternative for pure-SwiftUI views but skips AppKit-backed controls. Embroidery art loads from the bundle, so it is
missing in shots (`board embroidery art missing` is logged).

## Reading logs

- File: `~/Library/Logs/pocket.log`; rotated at launch to `pocket.log.1` when > 5 MB. Format:
  `2026-11-19T04:31:02Z <message>` (UTC ISO 8601).
- Useful filters:
  ```bash
  tail -f ~/Library/Logs/pocket.log
  grep "pocket started\|pocket terminating\|received SIGTERM" ~/Library/Logs/pocket.log | tail
  grep "app=schedule" ~/Library/Logs/pocket.log | tail -50
  grep "pocket vault" ~/Library/Logs/pocket.log | tail
  grep "pocket server" ~/Library/Logs/pocket.log | tail
  grep "hotkey\|shortcut" ~/Library/Logs/pocket.log | tail
  grep -E "failed|error=|refused|rejected|unavailable" ~/Library/Logs/pocket.log | tail -50
  ```
- Prefixes: `pocket ...` (shell, vault, server, web apps), `pomodoro ...`, `schedule ...`, `board ...`, plus per-app
  ones (see each `apps/*.md`). Matinee's engine logs separately under `~/Library/Logs/Matinee`.
- Scratch and harness runs write to the same file; filter by time or by `root=` in `pocket vault started`.

## Code conventions

- **Zero comments.** No comments, section headers, doc comments or TODOs in code. Names and structure carry meaning.
  Leave existing comments alone unless their code is removed (`CLAUDE.md` and the owner's global instructions).
- **Logging** with `note(...)` (`Log.swift`), following the owner's rules:
  - Log anything that can fail or crosses a boundary: external calls (HTTP, git, `Process`), file writes, IPC/queue
    hand-offs, permission decisions, retries, caught errors, state transitions, and entry/exit of jobs/requests.
  - Every line carries the identifiers needed to trace it (`app=`, `source=`, `project=`, `name=`, `path=`, `pid=`)
    and the values that shaped the outcome, not just "failed". Errors log the cause and the input.
  - Don't log pure functions, getters, loop bodies or steps that can't fail; don't log the same event twice up a call
    stack; never log secrets, tokens or bodies containing them.
  - Bar: the log alone should locate a failure.
- Server input is validated and answered with `400` + message; never crash on input.
- New persisted files go through `DataVault` (see [data-and-backups.md](data-and-backups.md)).

## Git conventions

From the owner's global `~/.claude/CLAUDE.md`:
- **Messages**: short, entirely lower case (no capitals anywhere, identifiers included), one line, no body unless
  truly needed, no generated-with footer. History follows this, e.g. `add the schedule menu bar app on option o`.
- **No co-author trailers** of any kind; the user is the only author (commits show `Gaone1906`).
- **Atomic commits**: one per unit of work, each compiling on its own; split refactors, data model, views, wiring and
  docs (see the Schedule series: model → vault → shortcut/pinning → editor → board → app → docs).
- **Push once**, after all commits are made, one push per branch; every push triggers CI.
- Commit or push only when the user asks; branch first if on `main`.
- Never put user data in this repo (it is public); data goes to the private data repo
  ([data-and-backups.md](data-and-backups.md)).

## Worktree layout

| Path | Branch | Notes |
| --- | --- | --- |
| `/Users/pranav.yarasi/Desktop/workspace/personal/pocket` | `add-matinee` | Main checkout. Matinee commits (`21caa1a`, `41f3f44`, `e5a6cee`) on top of `main`; has uncommitted work (`Embroidery.swift`, `CLAUDE.md`, `README.md`, three `Resources/Embroidery/fabric-*.jpg`). Don't edit it from another task. |
| `/Users/pranav.yarasi/Desktop/workspace/personal/pocket-schedule` | `add-schedule` | Linked worktree: `main` + the three Matinee commits + the Schedule series; tracks `origin/add-schedule`. This KB lives here. |

`main` tracks `origin/main` (`github.com/Gaone1906/Pocket`). `add-matinee` has no upstream. `git worktree list` shows
the current state; [handoff.md](handoff.md) has the latest. `.gitignore` excludes `.build/`, `.swiftpm/`, `*.app`,
`.DS_Store`.

## Permissions and entitlements

No `.entitlements` file exists; the app is signed with no entitlements, not sandboxed, no hardened runtime. That is
why it can spawn `git`/`node`/`zsh`, read `~/Library/Messages`, and bind a port without declaring anything. All access
is through runtime TCC prompts or user settings:

| Permission | Needed by | How it's obtained |
| --- | --- | --- |
| Notifications | web app new-message banners, Aurelius phase ends, Calendar alerts | `requestAuthorization(.alert, .sound, .badge)` at every launch |
| Microphone / Camera | calls in WhatsApp/Slack | WebKit prompts; `WebApp` grants media only to the app's own `hosts`; usage strings in `Info.plist` |
| Full Disk Access | OTP from Messages (`chat.db`) | manual, System Settings → Privacy & Security → Full Disk Access; setup deep-links there |
| Login item | "Open Pocket at login" | `SMAppService.mainApp.register()`; may show "Waiting for approval in System Settings" |
| Keychain | Gmail OAuth tokens | generic passwords, service `com.pranav.pocket.gmail`, account = address |
| Global hotkeys | all shortcuts | Carbon `RegisterEventHotKey`; no Accessibility permission needed |
| Loopback server | Aurelius API on 127.0.0.1:8977 | none (loopback only) |
| `gh` auth | git data sync | `gh auth token -u <pocket.backup.githubUser>`; never prompts |

TCC grants are tied to the code signature. With an ad hoc signature (no Apple Development identity), each rebuild is
a new identity and macOS may ask again; set `POCKET_SIGN_IDENTITY` to keep grants. A scratch bundle with a different
bundle id gets its own (empty) grants.

## Open questions

- `CLAUDE.md` says a plain `swift run` works with only the embroidery art missing; per the `AppDelegate` /
  `UNUserNotificationCenter` behaviour above, an unbundled run of the full app should crash at launch. Not re-verified
  for this KB (no builds were run); treat `swift run` as unsupported.
- Whether `WKWebsiteDataStore(forIdentifier:)` is isolated per bundle id was not verified.
- As of 2026-11-19 the owner's Mac has no Google Drive for Desktop (`~/Library/CloudStorage` holds only iCloud) and no
  `pocket.backup.folder` in either domain, so the mirror is currently inert there and no past scratch run could have
  overwritten a Drive copy. The hazard applies as soon as Drive is installed or the key is set; keep neutralising it.
- The isolation gap (mirror, Scratchpad, Gmail client path) is arguably a bug: `mirrorFolder` could default to `nil`
  whenever `POCKET_DATA_DIR` is set. Not changed; decide with the owner.
