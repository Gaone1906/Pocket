# Web apps (WhatsApp, Slack, Spotify, Gmail, Outlook) and link apps (Preparo)

Two thin `PocketApp` subclasses cover six catalog entries:

- **`WebApp`** (`Sources/Pocket/WebApp.swift`) hosts a site in a `WKWebView` inside the app's dropdown panel. It serves WhatsApp, Slack, Spotify, Gmail and Outlook. Matinee subclasses it too; for that, see [matinee.md](matinee.md).
- **`LinkApp`** (`Sources/Pocket/LinkApp.swift`) has no panel. Clicking it opens a URL in a named browser. Preparo is the only one.

`makeApp(_:)` in `Sources/Pocket/Factory.swift` routes each spec:

- `spec.web != nil` gives a `WebApp`, or a `MatineeApp` for `id == "matinee"`.
- `spec.link != nil` gives a `LinkApp`.

So a new web or link app needs only a catalog entry. For the shared panel, status-bar and layout machinery, see [../architecture.md](../architecture.md).

## What it is

| id | Name | URL | Shortcut | Realtime | Unload after | Zoom | UA | Store UUID suffix |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `whatsapp` | WhatsApp | `https://web.whatsapp.com/` | ⌥W | yes | never | 0.8 | Safari | `…7A01` |
| `slack` | Slack | `https://app.slack.com/client` | ⌥S | yes | never | 0.85 | Chrome + `chromeDisguise` | `…7A02` |
| `spotify` | Spotify | `https://open.spotify.com/` | ⌥M | yes | 1800 s | 0.85 | Safari | `…7A03` |
| `gmail` | Gmail | `https://mail.google.com/mail/` | ⌥G | no | never | 0.85 | Safari | `…7A04` |
| `outlook` | Outlook | `https://outlook.office.com/mail/` | none | no | never | 0.85 | Safari | `…7A05` |
| `preparo` | Preparo | `http://localhost:8960/` | none | n/a (LinkApp) | n/a | n/a | n/a | n/a |

- **Store UUIDs.** Each is the full `6B1F2C1E-0A57-4C3B-9E4B-0E5C4A0F7A0N`; Matinee uses `…7A06`.
- **Shortcuts.** The `hotKey` values are option + key, assigned once per app by `Layout.init` (see [../architecture.md](../architecture.md)).
- **Panel.** It uses the `PocketApp` defaults: 460×680, resizable, minimum 360×420. A resized size is remembered in UserDefaults `size.<id>`.
- **Menu-bar icon.** WhatsApp, Slack, Spotify, Gmail and Preparo use SVG glyphs from `Glyphs.swift`. Outlook has no glyph and uses the SF Symbol `tray.full.fill`.
- **Unread badge.** `WebApp.barImage()` overrides `AppIcon.render(spec, unread:)`:
  - a positive count draws a red pill with the number, capped at `99+`;
  - `-1` draws a 7 pt red dot.
- **Badges show only in the menu bar.** The dropdown grid (`TrayView.icon`) draws plain templated glyphs, so an app placed in the dropdown shows no unread state.
- **Right-click menu** (`WebApp.menuItems`): "Reload <Name>", "Restart <Name> (if frozen)" and "Open <Name> in browser". The common items from `AppDelegate.appendCommonItems` follow.
- **Preparo** opens `http://localhost:8960/` in Ardia (bundle id `com.ardia.browser`), or in the default browser when Ardia isn't installed. It never shows a panel.

## Playback watch (Spotify)

`WebSpec.watch` is an optional main-frame script; Spotify uses `playbackWatch` (`WebApp.swift`). It reports to the
`pocketWatch` message handler, logged as `pocket web watch app=spotify kind=<kind> shown=<bool> detail=<...>`:

- `http <status>` / `fetch failed` for player, Connect, licence and spclient requests;
- `socket open|closed|error` for every WebSocket (the Connect dealer), with close code;
- `drm granted|refused` from `requestMediaKeySystemAccess`;
- `media error|stalled|abort|emptied` from audio and video elements;
- `rejection`, `script error` and `console` (console.error) messages.

The script also counts open Connect dealer sockets and exposes `window.__pocketConnected()` (null until one has
opened). `WebApp.checkPlayer(reason:)` runs it when the panel opens and on every `checkHealth()` (every 300 s and on
wake); if the dealer is down and nothing is playing it reloads the page and logs
`pocket player disconnected app=spotify reason=<opened|health> playing=<bool> action=<reload|kept>`.

Each kind is capped per page load (30, sockets 100, DRM 5/10). When song picks stop working, read
`grep "app=spotify" ~/Library/Logs/pocket.log | tail -80` around that time.

## Files

| File | Key symbols |
| --- | --- |
| `Sources/Pocket/Catalog.swift` | `WebSpec` (`url`, `store`, `hosts`, `zoom`, `agent`, `disguise`, `realtime`, `unloadAfter`), `AppSpec` (`link`, `browser`), `safariAgent`, `chromeAgent`, `chromeDisguise`, `signInHosts`, `catalog` |
| `Sources/Pocket/WebApp.swift` | `notificationShim`, `mediaScript`, `playingProbe` (JS strings); `class WebApp` (non-final since Matinee subclasses it): `load(reason:)`, `unload(reason:)`, `checkHealth()`, `restart(reason:)`, `unreadCount(_:)`, `inCall`, `shouldStayOpen()`, `scheduleUnload()`, `ownsHost(_:)`, `staysInside(_:)`, the navigation, UI and download delegate methods, `openPopup`, `closePopup`, `retry(after:stage:)`, `userContentController(_:didReceive:)` |
| `Sources/Pocket/LinkApp.swift` | `final class LinkApp`: `toggle(anchor:source:)` override |
| `Sources/Pocket/AppDelegate.swift` | `syncAwake()` (App Nap), the wake observer calling `checkHealth()`, `remoteRestart(_:)`, and the notification-centre delegate (click opens the app) |
| `Sources/Pocket/PocketApp.swift` | `AppIcon.render(_:unread:tint:)` (badge drawing), panel lifecycle (`show`, `hide`, `windowDidResignKey`, which consults `shouldStayOpen`) |
| `Sources/Pocket/Setup.swift` | `SetupModel.signIn(_:)` opens a web app's panel unanchored, so the user can log in during setup. `SignInStep` lists enabled apps with `web != nil` |
| `Resources/Info.plist` | `NSMicrophoneUsageDescription` and `NSCameraUsageDescription` (needed for calls) |

## Data

No Pocket-owned files. Everything lives in WebKit's persistent stores.

- **Website data.** `config.websiteDataStore = WKWebsiteDataStore(forIdentifier: site.store)` is a per-app persistent store holding cookies, localStorage, IndexedDB and service workers. On disk it is `~/Library/WebKit/com.pranav.pocket/WebsiteDataStore/<lowercase uuid>/`; this was verified on the owner's Mac, which has `…7a01` to `…7a04` and `…7a06` (no Outlook).
  - The stores are isolated per app. Signing out of one never touches another.
  - **Never change a `store` UUID.** That silently logs the user out of the site, and the old directory is orphaned.
- **Not covered by `POCKET_DATA_DIR`.** The stores aren't backed up by `DataVault`, and they aren't redirected by `POCKET_DATA_DIR`, so a test harness that loads a `WebApp` uses the real logins.
- **Popups share the store.** Popup web views reuse the `WKWebViewConfiguration` WebKit hands to `createWebViewWith` (WebKit requires this), so they share the parent's store and cookies.
- **UserDefaults:**
  - `size.<id>` (the panel size);
  - the layout and shortcut keys owned by `Layout`.
- **Not persisted.** In memory only: `unread`, `popups`, `choosingFile` and the timers.

## User agents and page scripts

- **`safariAgent`** is a Safari 26 / macOS UA. WhatsApp, Spotify, Gmail, Outlook and Matinee use it. It's set as `customUserAgent` on the main view and on every popup.
- **`chromeAgent`** is a Chrome 146 UA, combined with `chromeDisguise`, which is injected at document start into **all frames** (`forMainFrameOnly: false`). The disguise:
  - defines `navigator.userAgentData` (brands "Google Chrome"/"Chromium" 146, platform macOS, plus `getHighEntropyValues`);
  - sets `navigator.vendor = "Google Inc."`;
  - stubs `window.chrome`.

  Slack uses it so huddles and its feature gates treat WebKit as Chrome. If Slack starts blocking or degrading, first bump the version numbers in both `chromeAgent` and `chromeDisguise` together.
- **`mediaScript`** (main frame only):
  - wraps `HTMLMediaElement.prototype.play` to remember played elements;
  - exposes `window.__pocketPlaying()`, which is true if any remembered or in-DOM `<audio>`/`<video>` is playing, or `navigator.mediaSession.playbackState == "playing"`.

  `playingProbe` evaluates it.
- **`notificationShim`** (main frame only) replaces `window.Notification` with `PocketNotification`:
  - `permission` is always `"granted"`;
  - `requestPermission` resolves `"granted"`;
  - each `new Notification(title, {body, tag})` posts `{title, body, tag}` to the `pocketNotify` message handler.

  Uncertain: notifications a site sends from a service worker (`registration.showNotification`) bypass the shim and are not shown.

## Flows

### Startup and lazy loading
1. `AppDelegate.sync()` builds the app via `makeApp` and calls `start()`.
2. `WebApp.start()` forces the panel to exist (`_ = panel`; the content is `container`, an empty `NSView`). Then:
   - with `site.unloadAfter != nil` (Spotify only), it logs `deferred … until first open` and does not load;
   - otherwise it calls `load(reason: "startup")` right away. So WhatsApp, Slack, Gmail and Outlook all load at launch (see Gotchas: the README says otherwise).
3. `load(reason:)` is a no-op if `web` exists. It builds a `WKWebViewConfiguration`:
   - the per-app store;
   - autoplay allowed (`mediaTypesRequiringUserActionForPlayback = []`);
   - JS may open windows;
   - element fullscreen;
   - `inactiveSchedulingPolicy` set to `.none` when realtime, else `.throttle`.

   It then adds the user scripts and the `pocketNotify` handler, and creates the web view (autoresizing, UA, `pageZoom = site.zoom`, `isInspectable = true`, no back/forward swipe). After that it:
   - observes `title` for unread;
   - adds the view to `container` and loads `site.url`;
   - starts `healthTimer`, every 300 s with 60 s tolerance.

### Keep-alive and background behaviour
- **Realtime (WhatsApp, Slack, Spotify):**
  - `inactiveSchedulingPolicy = .none`;
  - the private WKPreferences `pageVisibilityBasedProcessSuppressionEnabled`, `hiddenPageDOMTimerThrottlingEnabled` and `hiddenPageDOMTimerThrottlingAutoIncreases` are set false, each only if the `_set…:` selector exists;
  - the private `windowOcclusionDetectionEnabled` on the web view is set false.
- **App Nap.** `AppDelegate.syncAwake()` holds `ProcessInfo.beginActivity(.userInitiatedAllowingIdleSystemSleep)` while any enabled `WebApp` is realtime, which blocks App Nap but still lets the Mac idle-sleep. It logs `pocket app nap blocked for realtime apps` or `allowed`.
- **Non-realtime (Gmail, Outlook):** WebKit throttles them while hidden (`.throttle`). They stay loaded.
- **Why Spotify is realtime.** Its web player kept playing while hidden but, after a while, stopped starting new tracks
  even though browsing and search still worked. The likeliest cause is hidden-page throttling and process suppression
  stalling the player's Spotify Connect socket and timers, so play commands went nowhere. Spotify is realtime since
  19 Nov 2026; it still unloads after 1800 s hidden and not playing.
- **Spotify idle unload.** `didHide()` calls `scheduleUnload()`, which is a no-op unless `unloadAfter` is set. After 1800 s hidden, the work item:
  - re-arms if the panel is shown again, if `inCall`, or if `playingProbe` returns true;
  - otherwise calls `unload(reason: "idle 1800s")`.

  `didShow()` cancels the pending unload and calls `load(reason: "opened")` (a no-op if already loaded), then makes the web view first responder.
- **`unload`** invalidates the health timer, drops the title observer, closes every popup, removes the message handler, stops loading, removes the view and sets `unread = 0`.
- **`stop()`** (when the app is disabled in setup, or at quit through `applicationWillTerminate`) cancels the unload work, unloads, then `super.stop()` tears down the panel.

### Health, wake, freeze recovery
- **`checkHealth()`** (every 300 s, and for every `WebApp` on `NSWorkspace.didWakeNotification`) evaluates `document.visibilityState`:
  - a JS error reloads `site.url`;
  - no callback within 20 s calls `restart(reason: "health timed out")`.
- **`restart(reason:)`** reads the private `_webProcessIdentifier` and sends `SIGKILL` to the WebContent process. `webViewWebContentProcessDidTerminate` then reloads `site.url`. With no pid, or if the kill fails, it falls back to `load`.
- **Triggers for `restart`:**
  - the menu item "Restart … (if frozen)";
  - a distributed notification `com.pranav.pocket.restart` whose object is the app id (`AppDelegate.remoteRestart`).

  `com.pranav.pocket.toggle` with an app id opens or closes any app.
- **Navigation failures** (`didFail`, `didFailProvisionalNavigation`) on the main view go to `retry(after:stage:)`:
  - it ignores `NSURLErrorCancelled` (-999) and 102 (WebKit "frame load interrupted", which happens when a navigation becomes a download);
  - otherwise it reloads `site.url` after 15 s if the view is not mid-load.

  Popup failures are only logged.

### Unread badges
- The `title` KVO calls `WebApp.unreadCount(title)`:
  1. The first `(digits[,digits])` anywhere in the title gives that number; commas are stripped.
  2. Otherwise, a title starting with `*` or `!` gives `-1` (a dot).
  3. Otherwise 0.
- The `unread` `didSet` logs and calls `changed()`, which makes `BarController.refresh(id)` redraw the icon.
- Per-site behaviour (not verified against live titles; these are the usual formats):
  - Gmail: `Inbox (N) - …`;
  - WhatsApp: `(N) WhatsApp`;
  - Slack: a `*`/`!` prefix or `(N)`;
  - Outlook rarely puts a count in its title.

### Notifications
1. The page calls `new Notification(...)`, and the shim posts to `pocketNotify`.
2. `userContentController(_:didReceive:)` drops it if the panel is shown **and** key, since the user is looking. Otherwise it builds a `UNNotificationRequest` that fires immediately:
   - title = page title, or the app name if empty;
   - body;
   - default sound;
   - `userInfo["app"] = spec.id`;
   - identifier `<id>-<tag>`, or `<id>-<uuid>` when there's no tag, so the same tag replaces the earlier banner.
3. Authorisation is requested once at launch in `AppDelegate.applicationDidFinishLaunching` (`.alert, .sound, .badge`). `willPresent` shows a banner and plays a sound even while Pocket is frontmost.
4. Clicking a notification goes to `AppDelegate.userNotificationCenter(_:didReceive:)`, which calls `apps[id].show(anchor:source: "notification")`.

### Links, new windows, popups (calls, huddles)
- **Hosts.** `ownsHost(h)` is true when `h == x` or `h` ends with `.x`, for each `x` in `site.hosts`. `staysInside(h)` is `ownsHost` or the same test against the global `signInHosts`: facebook, Google accounts, Apple ID, Microsoft login, Okta, JumpCloud, OneLogin and Auth0.
- **Navigation policy:**
  - `shouldPerformDownload` becomes a download;
  - a user-clicked link (`.linkActivated`) in the main frame to a host outside `staysInside` opens in the default browser and is cancelled;
  - everything else (redirects, form posts, iframes) is allowed anywhere.
- **`window.open`** (`createWebViewWith`):
  - a blank, `about:` or `blob:` URL, or an owned host, gets a **popup window** (`openPopup`);
  - a sign-in host is loaded **in the main web view**, replacing the page, and `nil` is returned;
  - any other `http(s)` URL opens in the default browser;
  - other schemes are dropped and logged.
- **`openPopup`** creates a floating `NSWindow` titled "<Name> call":
  - size from `windowFeatures`, defaulting to 420×320;
  - it joins all Spaces;
  - it's placed left of the panel, or at the right edge if there's no room;
  - Pocket is activated and the window made key.

  Popups are tracked in `popups`. `windowWillClose` runs `window.close()` in the page and calls `closePopup`; `webViewDidClose` and the process ending also close them.
- **Keeping the panel open.** `shouldStayOpen()` keeps the panel from hiding on focus loss while any of these hold:
  - a file chooser is open;
  - `inCall`, meaning any main or popup view has microphone or camera capture active;
  - any popup exists, or a popup window is key.
- **Camera and microphone.** `requestMediaCapturePermissionFor` grants only when `ownsHost(origin.host)`. macOS TCC prompts separately, using the Info.plist strings.

### Downloads
- They're triggered by `shouldPerformDownload`, or by a response whose MIME type the view can't show (`decidePolicyFor response`).
- `download(_:decideDestinationUsing:suggestedFilename:)` saves to `~/Downloads/<suggested>`. On a clash it de-duplicates as `name 1.ext`, `name 2.ext` and so on.
- There's no progress UI and no reveal-in-Finder. The outcome is in the log only (`download started`, `finished` or `failed`).

### Other UI delegate behaviour
- `<input type=file>` opens an `NSOpenPanel`, with multi-select and directories as the page requests. `choosingFile` keeps the panel open, and the panel is re-keyed afterwards.
- `alert()` and `confirm()` appear as sheets on the view's window, or on the panel. `prompt()` isn't implemented, so it returns null.

### LinkApp (Preparo)
`toggle(anchor:source:)` is overridden; there is no panel.

1. `AppDelegate.shared.hideOthers(except: self)`.
2. If `spec.browser` is set and `NSWorkspace.urlForApplication(withBundleIdentifier:)` finds it, it calls `NSWorkspace.open([url], withApplicationAt:configuration:)`, and the completion logs success or the error.
3. Otherwise it logs `link browser missing … fallback=default` (only when a browser was named) and calls `NSWorkspace.shared.open(url)`.

- Pocket does not check that Preparo's server on `:8960` is up; the browser shows its own error page.
- `Layout.init` defaults `layout.offered` to the non-link apps, so when that key is first written, link apps count as "fresh" and are appended to the dropdown on existing installs.
- For how Preparo drives the Aurelius timer, see `CLAUDE.md` and [pomodoro.md](pomodoro.md).

## Integrations

| System | Auth / permission |
| --- | --- |
| The sites themselves | The user signs in inside the panel, from Setup step 2 ("Sign in") or just by opening the app. Cookies live in the per-app WebKit store. Pocket never sees or stores credentials |
| Notification Center | `UNUserNotificationCenter` authorisation requested at launch |
| Camera and microphone | TCC, with the Info.plist usage strings. Page-level permission is auto-granted for owned hosts only |
| Ardia (`com.ardia.browser`) | None; it's opened through LaunchServices |
| Private WebKit SPI | `_webProcessIdentifier`, `_setWindowOcclusionDetectionEnabled:` and the hidden-page throttling prefs, all guarded by `responds(to:)`, so a WebKit change degrades silently instead of crashing |

## Logging

All lines come from `note(...)` and go to `~/Library/Logs/pocket.log`. Every `WebApp` line carries `app=<id>`.

| Line | Extra fields |
| --- | --- |
| `pocket deferred app= until first open` | |
| `pocket loading app=` | `reason` (startup or opened), `realtime`, `url` |
| `pocket loaded app=` | `host` |
| `pocket unloaded app=` | `reason` (`idle 1800s`, `app disabled`) |
| `pocket stopped app=` | |
| `pocket unread app=` | `count` |
| `pocket health failed app=` | `cause` |
| `pocket restart app=` / `restart fell back to reload` | `reason`, `pid`, `killed`, `errno` |
| `pocket reload app= source=menu` | `loaded` |
| `pocket load failed app=` | `stage` (load or connect), `code`, `cause` |
| `pocket popup load failed` / `popup connect failed` | `code` |
| `pocket web process ended app=` | |
| `pocket link opened outside app=` | `host` |
| `pocket new window kept inside` / `opened outside` / `dropped` | `host` or `scheme` |
| `pocket popup opened` / `popup closed` | `host`, `size`, `reason`, `open` (count) |
| `pocket download started` / `finished` / `failed` | `file`, `cause` |
| `pocket file chooser closed` | `picked` |
| `pocket media permission` | `host`, `type`, `granted` |
| `pocket notification posted` | `bodyChars` (never the content) |
| `pocket notification failed` | `cause` |
| `pocket link opened` / `link open failed` / `link browser missing` | `url`, `browser`, `source`, `ok`, `error` |

`AppDelegate` lines that relate to web apps:

- `pocket mac woke; checking pages`;
- `pocket app nap …`;
- `pocket remote restart ignored`;
- `pocket notification permission granted=`.

## Gotchas

- **README contradiction.** The README says "Web apps load only when they are first opened. The exception is WhatsApp and Slack." In the code, only apps with `unloadAfter` (Spotify) are deferred, so Gmail and Outlook load at launch as well (throttled). To make Gmail and Outlook lazy, the deferral needs its own flag, because `unloadAfter` also drives idle unloading.
- **False badges from Spotify.** The unread regex matches any parenthesised digits in the title, so a track title like "Song (2019)" would show a 2019 → `99+` badge. This hasn't been seen in the logs, but it follows from `unreadCount`.
- **Unloading clears the badge.** An unloaded Spotify shows no badge. A deferred app has none until first opened.
- **Sign-in pages replace the main view.** An OAuth `window.open` to a `signInHosts` domain is loaded into the main view, not a popup. A site that expects a real popup (`window.opener` callback) may not complete that flow.
- **The retry can bounce the user home.** `retry` reloads `site.url` (home), not the failed URL, if the view isn't loading 15 s later.
- **Popup UA and delegates.** A popup's `customUserAgent` is set explicitly. Popups get no disguise script of their own; they inherit the parent configuration's user scripts.
- **Health kills.** A health check timing out (20 s) SIGKILLs the web process. Heavy pages after wake can trip this; look for `restart app=<id> reason=health timed out`.
- **Commit history:**
  - `4de6ccf` replaced the old tick counter and idle logging with lazy loading, `unloadAfter` and throttling of non-realtime pages, and moved the web view into a `container` view, so the panel can exist without a page;
  - `41f3f44` made `WebApp` non-final for `MatineeApp`;
  - `3376d2d` and `43f3ca1` added `LinkApp` and then the `browser` field for Ardia.

## How to change it safely

- **Add a web app.** Add an `AppSpec` with a `WebSpec` to `catalog`, with a **new, never-reused** `store` UUID. Then:
  - list every host the site needs in `hosts`; anything missing opens externally when clicked, or never gets camera or mic access;
  - choose `realtime` (only for things that must receive pushes while hidden; it costs battery and blocks App Nap);
  - choose `unloadAfter`.

  Optionally add a glyph in `Glyphs.swift` and a `hotKey`, picking one not taken in `catalog`. Existing installs get the new app appended to the dropdown (or to the bar if `pinnedByDefault`) by `Layout.init`.
- **Add a link app.** Set `web: nil`, `link: URL` and optionally `browser: <bundle id>`.
- **Change a UA.** Edit `safariAgent` or `chromeAgent`. For Chrome, keep `chromeDisguise` brand versions in step.
- **Change the unread parsing.** Edit `WebApp.unreadCount`. It is `static` and pure, so it's easy to test with sample titles.
- **Test without touching real logins.** There's no supported way; the stores are keyed by fixed UUIDs in the user's WebKit directory. Test in a separately signed build with a different bundle id, or temporarily use different UUIDs locally and don't commit them.
- Don't build into the shared `.build`, and never run `scripts/install.sh` from an agent session against the owner's install.

## Open questions / known gaps

- Service-worker notifications aren't bridged (unverified per site).
- No download UI, and `prompt()` isn't supported.
- There's no badge in the dropdown grid.
- Outlook has no glyph, no shortcut and probably no title count.
- Preparo gives no feedback when its local server is down.
- `checkHealth` on wake runs for every `WebApp`, including deferred or unloaded ones, which is a no-op because of the `guard let web`.
