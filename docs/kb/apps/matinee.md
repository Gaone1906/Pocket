# Matinee

Matinee hunts for movie tickets on district.in. When a matching show opens, it holds the best seats in a visible Chromium window and stops at checkout so the user can pay.

It is **two codebases**:

| Part | Where | Language |
| --- | --- | --- |
| Pocket host: `MatineeApp`, a `WebApp` subclass that supervises the engine | this repo, `Sources/Pocket/MatineeApp.swift` | Swift |
| Matinee itself: the engine (HTTP API, scheduler, District scraping, Playwright booking, alerts) and the panel UI | `~/Files/Personal Projects/Matinee` (separate git repo, **no remote**, local only) | Node 26 (CommonJS) and React with Vite |

Everything that touches District lives in the Matinee repo. Pocket only hosts the panel and keeps the engine process alive. The Matinee repo has its own `README.md` and `docs/CONTRACT.md`, which is the authoritative build spec; read it before changing the engine.

Related: [../architecture.md](../architecture.md) (WebApp, Factory, AppDelegate lifecycle), [web-apps.md](web-apps.md) (the `WebApp` base class this subclasses), [../operations.md](../operations.md) (logs, install), [../handoff.md](../handoff.md) (branch state).

## What it is

- **Catalog entry** (`Catalog.swift`, `catalog`): `id: "matinee"`, name "Matinee", summary "Hunts District movie tickets and holds seats for you", SF symbol `ticket.fill`, glyph `Glyphs.matinee` (a ticket SVG), **`hotKey: nil` (no default shortcut)**, not pinned by default.
- **WebSpec**: url `http://127.0.0.1:47811/`, store UUID `6B1F2C1E-0A57-4C3B-9E4B-0E5C4A0F7A06` (its own `WKWebsiteDataStore`), hosts `["127.0.0.1", "localhost"]`, zoom 1.0, `safariAgent`, no disguise, `realtime: false`, `unloadAfter: nil`. So the page loads at Pocket startup and is never unloaded for idleness.
- **Dropdown size**: the `PocketApp` default of 460×680, resizable, minimum 360×420, with the size saved in UserDefaults `size.matinee`.
- **Badge**: comes from `document.title` via `WebApp.unreadCount`. The UI sets `Matinee (1)` while any hunt is holding, which shows a "1" badge. It sets `Matinee (!)` while any hunt needs attention, but that **does not badge** (see Gotchas).
- **Right-click menu** (`MatineeApp.menuItems`, which replaces WebApp's three items): "Reload Matinee", "Restart engine", "Open Matinee logs". WebApp's "Open in browser" and "Restart (if frozen)" are not offered.
- **The user's view**: the panel (React) has a hunt list. "New hunt" is a four-step wizard: Movie, Preferences, Cinemas, Review. Hunt detail offers pause/resume, check now, edit, delete, **Go to payment** and **I've paid**. There is a **Sign in** button for District, and `⌘N` starts a new hunt.

## Files

### Pocket repo

| File | Matinee role | Key symbols |
| --- | --- | --- |
| `Sources/Pocket/MatineeApp.swift` | All Pocket-side Matinee logic | `MatineeApp` (`final class`, subclass of `WebApp`). Statics: `pathKey`, `defaultPath`, `healthURL`, `shutdownURL`, `logFolder`. Functions: `start()`, `load(reason:)`, `supervise(reason:)`, `probe(_:)`, `record(up:version:reason:)`, `warmUp()`, `respawnIfDue(reason:)`, `findNode()`, `spawn(reason:)`, `fail(_:log:)`, `showPlaceholder()`, `requestShutdown(wait:)`, `stop()`, `restartEngine()`, `openLogs()`, `menuItems()` |
| `Sources/Pocket/Catalog.swift` | The `AppSpec`/`WebSpec` entry above | `catalog`, `safariAgent` |
| `Sources/Pocket/Glyphs.swift` | `Glyphs.matinee` ticket SVG | |
| `Sources/Pocket/Factory.swift` | `makeApp`: `if spec.id == "matinee" { return MatineeApp(...) }`, before the generic `WebApp` | |
| `Sources/Pocket/WebApp.swift` | Base class, changed from `final class` to `class` so Matinee can subclass it | `load`, `reload`, `unreadCount`, the `notificationShim`, `retry(after:stage:)`, `checkHealth` |
| `Sources/Pocket/AppDelegate.swift` | `applicationWillTerminate` calls `stop()` on every app, and a SIGTERM handler calls `NSApp.terminate`. Both were added for Matinee, so the engine is shut down when Pocket quits | `termSource`, `applicationWillTerminate`, `sync()` (calls `stop()` when the app is disabled) |

**Not Matinee** (checked; the brief guessed otherwise):

- `Mail.swift` (`Keychain`, `GoogleAuth`, `MailAccount`, `MailWatcher`) and `Otp.swift` (`OtpWatcher`) are Pocket's **general OTP-in-menu-bar feature**. They read SMS codes from `~/Library/Messages/chat.db`, and Gmail codes over Gmail IMAP IDLE (`imap.gmail.com:993`, XOAUTH2) plus the Gmail REST API. Each code is shown as a green menu-bar item for 30 s. Nothing in Matinee calls them, and the Matinee engine never reads mail or SMS.
  - **Indirect help:** when District texts a login OTP while the user signs in to the Matinee Chromium window, Pocket's OTP watcher may show that code to copy. That only happens if the OTP feature is on (`layout.otp`).
  - **Credentials:** Keychain service `com.pranav.pocket.gmail`, with the account set to the Gmail address and the value being the OAuth refresh token. The Google OAuth client is read from `~/Library/Application Support/Pocket/google-client.json` (`id`, `secret`). UserDefaults keys: `gmailAccounts`, `keepMessages`.
  - Documented with the architecture.
- `PocketServer.swift`: the loopback HTTP API on port **8977**, Ignis routes only. It has no Matinee routes. Don't confuse it with Matinee's port **47811**.
- `DeclareSession.swift`: `DeclareSessionCard`, the Ignis "declare a session" SwiftUI card. Unrelated.

### Matinee repo (`~/Files/Personal Projects/Matinee`)

| Path | What |
| --- | --- |
| `engine/server.js` | `createApp`: the HTTP API, static serving of `dist/`, a 10-min login-status refresh, and `shutdown`. `main()` wires everything together and exits 0 if an engine already answers `/health`. `healthAnswers` |
| `engine/paths.js` | `resolvePaths`: data dir, log dir, port and `distDir` (`<repo>/dist`). `ensureDirs` |
| `engine/logger.js` | `createLogger`. Line format `ISO LEVEL event k=v`. Rotates at 5 MB and keeps 3. Redacts keys matching cookie, token, password, secret or authorization. Also writes to stdout |
| `engine/hunts/engine.js` | `createEngine`: scheduler, arming, check, booking loop and status machine |
| `engine/hunts/gather.js` | `gatherShows`: which District pages to fetch for a hunt (full or light) |
| `engine/hunts/match.js` | `matchesHunt`, `selectMatches`, `rankShows`, IST helpers (`todayIST`, `istLocal`) |
| `engine/hunts/validate.js` | `validateNewHunt`, `validatePatch`, the `EDITABLE` fields and their defaults |
| `engine/hunts/store.js` | `createStore`: in-memory map, written atomically to `hunts.json` (via tmp file and rename) |
| `engine/district/catalog.js` | `createCatalog`: plain `fetch` of district.in HTML, then `__NEXT_DATA__` parsing (`listMovies`, `movieDetail`, `showings`, `listCinemas`). `CatalogError` |
| `engine/booking/booker.js` | `createBooker`: a Playwright persistent Chromium context (`loginStatus`, `login`, `hold`, `focus`, `release`) |
| `engine/booking/district.js` | DOM automation of District's seat pages (`openSeatLayout`, `readSeatMap`, `selectSeat`, `selectedCount`, `proceedToCheckout`) |
| `engine/booking/seats.js` | `rankCandidates`: picks the seat block |
| `engine/booking/layout.js` | `inferGrid`: geometry fallback when seat columns are unreadable |
| `engine/booking/outcome.js` | `watchOutcome`: detects BOOKED, EXPIRED or CLOSED after holding |
| `engine/booking/timer.js` | `readExpiresAt`: parses District's checkout countdown |
| `engine/booking/session.js` | `hasSessionCookie`, `loginVerdict`, `readLoginUi` |
| `engine/alerts/alert.js`, `alarm.swift`, `sounds/*.wav` | `osascript` notifications, plus a full-screen alarm binary compiled with `swiftc` |
| `src/**` | React panel. `src/hooks/useEngine.ts` (polling), `src/lib/summary.ts` (`documentTitle`) |

## Data

The Pocket side persists only one thing, the UserDefaults key **`pocket.matinee.path`** in domain `com.pranav.pocket`. It is the repo folder; when unset, the default is `~/Files/Personal Projects/Matinee`. It is unset on this machine. Nothing Matinee-related goes through `DataVault` (see [../data-and-backups.md](../data-and-backups.md)), so **hunts are not backed up**.

The engine side:

| What | Path |
| --- | --- |
| Hunts | `~/Library/Application Support/Matinee/hunts.json` (a JSON array of Hunt) |
| District login session (cookies) | `~/Library/Application Support/Matinee/profile/` (Playwright persistent Chromium profile) |
| Screenshots | `.../Matinee/shots/<runId>-<name>.png` |
| Compiled alarm | `.../Matinee/bin/alarm` |
| Engine log (rotated) | `~/Library/Logs/Matinee/engine.log` |
| Engine stdout and stderr (from Pocket's spawn; **never rotated**) | `~/Library/Logs/Matinee/engine-stdout.log` |
| Overrides | `MATINEE_HOME` (moves data, and logs to `$MATINEE_HOME/logs`), `MATINEE_PORT`, `MATINEE_DRY_RUN=1`, `MATINEE_LOG_LEVEL` |

The Hunt shape is in `docs/CONTRACT.md` § Hunt. Key fields:

- `movie {id, name, path, releaseDate?}`;
- `languages[]`, `formats[]`, ranked `cinemas[]`;
- `dates {from, to}`, `weekdays[]`, `time {from, to}` (it may cross midnight);
- `seats` (1–10, default 2), `rowWeight` (0–10, default 1.5), `priority` (`cinema` | `date` | `time`), `leadDays` (1–7, default 3);
- `armAt`, `status`, `statusDetail`, `checks`, `matches[]`;
- `booking {show, runId, chosen, holdingSince, expiresAt, orderId, screenshot}`;
- `events[]` (newest first, capped at 60).

`city` defaults to `chennai` and is a slug.

Statuses: `scheduled` → `watching` → `booking` → `holding` → `booked`, plus `paused` and `attention`. On load, a hunt found in `booking` or `holding` is turned into `paused`, with the detail "Matinee restarted" (`store.load`).

## Flows

### Pocket: supervising the engine (`MatineeApp`)

1. **On start:** `start()` calls `super.start()`, which loads the web view immediately because `unloadAfter` is nil. Because `engineUp` is still nil, `load(reason:)` replaces the page with `showPlaceholder()` ("Starting the Matinee engine"). Then `supervise(reason:"start")` runs, plus a **30 s repeating timer** (tolerance 5 s) calling `supervise(reason:"interval")`.
2. **`supervise`:** `probe` does a `GET http://127.0.0.1:47811/health` (2 s timeout, no cache). The engine is "up" only on HTTP 200 with `ok: true`; `version` is read from the body. Then `record(...)` runs, and if the engine is down, `respawnIfDue`.
3. **`record`:** acts only on a change of `engineUp`.
   - Up after down or unknown: it resets `failures` and `problem`, then reloads `site.url` in the web view.
   - Down: it shows the placeholder.
4. **`respawnIfDue`:**
   - If our process is running and was spawned less than **45 s** ago, it waits.
   - If our process is running but silent for longer than that, it calls `terminate()`. The next tick, or the termination handler, takes over.
   - If `now < nextSpawnAllowed`, it logs the backoff and waits.
   - Otherwise it calls `spawn`.
5. **`spawn`:**
   - Requires `<repo>/engine/server.js`, else it calls `fail` with a `defaults write com.pranav.pocket pocket.matinee.path ...` hint.
   - `findNode()` tries `/opt/homebrew/bin/node`, then `/usr/local/bin/node`, then `zsh -lc 'command -v node'`, else it calls `fail` with "brew install node".
   - It runs `node <repo>/engine/server.js` with `cwd` set to the repo, stdin set to `/dev/null`, and stdout and stderr appended to `~/Library/Logs/Matinee/engine-stdout.log`.
   - On success: `spawnedByUs = true`, `failures += 1`, and `nextSpawnAllowed = now + min(600, 30·2^(failures−1))` seconds (30 s, 60 s, 120 s … capped at 10 min). Then `warmUp()` runs.
6. **`warmUp`:** up to **20 probes, 1 s apart**, until the engine answers. This gives a fast page reload instead of waiting for the 30 s tick.
7. **Termination handler:** logs the exit (status, and whether it was a signal or an exit, plus `expected`). If the process is still `engine`, it clears it, sets `spawnedByUs = false` and re-probes.
8. **`fail`:** sets `problem` (shown in the placeholder), bumps `failures` and the backoff.
9. **Restart engine** (menu, `restartEngine`): resets the failures, problem and backoff. Off the main thread, it `POST /shutdown`s (2 s wait). After 2 s if that was accepted (0 s otherwise), it terminates our process if it is still running, sets `engineUp = nil` and calls `supervise(reason:"restart")`. It sends the shutdown even to an engine Pocket didn't spawn.
10. **Open Matinee logs:** opens `~/Library/Logs/Matinee` in Finder.
11. **`stop()`** (Pocket quit via `applicationWillTerminate`, SIGTERM, or the app being disabled in Setup via `sync()`):
    - Sets `stopping` and kills the timer.
    - If `spawnedByUs`: `requestShutdown(wait: 2)`, a **synchronous** POST on the main thread using a semaphore. It then polls up to **6 s** for exit, and calls `terminate()` (SIGTERM) after that grace.
    - An engine Pocket did not spawn is left running and logged as `ours=false`.
    - Then `super.stop()` unloads the web view.
12. **On wake:** nothing Matinee-specific. The 30 s timer catches a dead engine. WebApp's 5-min `checkHealth` and the 15 s `retry(after:)` on load failures also apply.

### Engine: a hunt's life (`engine/hunts/engine.js`)

1. **Create** (`POST /hunts`): `validateNewHunt`, then status `watching`. `backfillReleaseDate` fetches `movieDetail` if `releaseDate` is missing. Then `applyArming`.
2. **Arming:** the opening day is the later of `releaseDate` and `dates.from`. `armAt` is 00:00 IST, `leadDays` days earlier.
   - If `armAt` is in the future, the status is `scheduled`, with a detail like "Starts checking Sat 20 Dec, 3 days before release".
   - Scheduled hunts get a **light check every 6 h ± 15 min**: the first matching language group only, and its first listed date. They are capped so that a check falls exactly at `armAt`.
   - At `armAt`, or on any light-check match (`early_match`), the hunt arms: it becomes `watching`, logs `hunt.armed`, and its first check runs after 1 s.
3. **Full check:** every **45 s ± 10 s** per `watching` hunt.
   - For each matching language group, it fetches the movie page at the first in-window date (today IST or `dates.from`), reads `sessionDates`, then fetches every other listed date in the window that also passes the weekday filter.
   - `selectMatches` filters by date window, not-yet-started (IST), weekday, time window (which may wrap midnight), language, format chip (equal, or a prefix followed by a space), `available >= seats`, and cinema in the ranked list.
   - It then ranks by `priority`: cinema rank, date or closeness to the window midpoint.
   - New matches after none push the `opened` event and alert.
4. **Booking:** on the first match, and **only if no other hunt is booking** (`bookingHuntId === null`), the hunt goes to `booking`. `bookLoop` tries the matches in rank order with `booker.hold`.

   | `result.code` | Engine response |
   | --- | --- |
   | `HOLDING` | `holding`, `notify('holding')`, then await the outcome |
   | `PLANNED` (dry run) | `paused`, "Dry run: would hold row …" |
   | `NOT_LOGGED_IN` | `attention`, "Sign in to District in the Matinee window, then resume", plus an alert |
   | `BUSY` | Event only. The hunt goes back to `watching` |
   | `NO_SEATS`, `SHOW_GONE` | Per-`(hunt, sid)` cooldown of **5 min**, then the next match |
   | `SELECTION_FAILED`, `CHECKOUT_TIMEOUT`, `UNEXPECTED` | Cooldown of **2 min**, then the next match |
   | All candidates exhausted | `watching`, "No seats at the current matches" |

5. **Outcome while holding:** `BOOKED` (an order URL was seen) leads to `booked` with `orderId` and an alert. `EXPIRED` or `CLOSED` leads to `paused` ("Seat hold expired before payment" or "Checkout window was closed before payment"). `bookingHuntId` stays set for the whole hold, so other hunts cannot book meanwhile.
6. **Failures:** a catalog `NOT_FOUND` counts as zero matches, not a failure. Any other catalog error counts toward a consecutive-failure tally. At **5 in a row**, a `watching` hunt goes to `attention` ("Checks are failing: CODE, n in a row") plus an alert. Checks continue, and the first success returns it to `watching`.
7. **User actions** (`PATCH /hunts/:id`):
   - `pause` releases the browser if the hunt was holding.
   - `resume` works from `paused` or `attention`, and re-arms.
   - `markBooked` releases the browser.
   - Edits are refused while `booking`, `holding` or `booked`. An edit clears the matches, bumps `editVersions` (so a stale in-flight check is discarded) and re-arms.
   - `POST /hunts/:id/check` runs a full check whatever the status (409 when booking, holding or booked).
   - `POST /hunts/:id/focus` brings Chromium to the front.
   - `DELETE` releases the browser if the hunt was holding or booking.

### Engine: seat holding (`engine/booking/booker.js`, `district.js`, `seats.js`)

1. `hold()` refuses when the booker is `busy` (it returns `BUSY`). Otherwise it closes any open context and launches a **headed** persistent Chromium (window 1280×900, `--disable-blink-features=AutomationControlled`, locale en-IN) on the profile dir.
2. **`openSeatLayout`** tries, in order:
   - the "cinemas" seat-layout URL from the catalog (`/movies/seat-layout/{fmtGrpId}?encsessionid={cinemaId}-{sid}-{mid}-{fmtGrpId}&fromdate=…&type=CINEMAS&contentid=…`), waiting up to 15 s for `span[aria-label*="seat, class"]`;
   - the "movies" form (`encsessionid=…-{cinemaId}&type=MOVIES`), waiting up to 8 s;
   - the fallback: open the cinema page (`{cinemaPath}?fromdate=`), find the movie's block, pick the timeblock by 12 h time, language and format (`pickTimeblock`), click it, and verify that the URL is a seat layout for the same `fmtGrpId`.

   A failure there is `SHOW_GONE`.
3. **`readSeatMap`** parses every seat's `aria-label` ("available seat, class X, row R, column N"), along with its geometry. It splits repeated row labels into `R~1` and so on, and detects which side the screen is on to get the back-to-front row order. `resolveGrid` uses the site's columns when they are all numeric, else the geometry-inferred grid (`layout.js`).
4. **`rankCandidates`:**
   - Rows are split into zone 1 (the front two-thirds) and zone 2 (the back third, only when there are 4 or more rows).
   - The ideal row is one-third of the way back.
   - Each candidate is a run of `seats` adjacent free seats. Its cost is `|mean col − centre| + rowWeight · |row − ideal|`.
   - Zone 1 always ranks before zone 2.
   - The top 12 are kept as `result.plan`. In dry run it returns `PLANNED` here.
5. **`holdSeats`:** up to `maxAttempts` (6). It clicks each seat of the best block, dismissing any "Continue booking" tip, then reads "Selected N Seats".
   - If N equals `seats`, the selection is done.
   - If N is greater, the row sells in larger units, so the row is excluded.
   - Otherwise the block is excluded, the seat layout is reloaded, the map is re-read and ranking starts again.

   Running out of blocks is `NO_SEATS`; running out of attempts is `SELECTION_FAILED`.
6. **`proceedToCheckout`:** clicks "Proceed", then for up to **90 s**:
   - "Enter your mobile number" visible means `NOT_LOGGED_IN` (with a screenshot);
   - a "Skip" button (snacks upsell) is clicked;
   - the page is considered at checkout after 3 consecutive polls, 700 ms apart, off `/seat-layout/`.

   Otherwise the result is `CHECKOUT_TIMEOUT`. The engine never fills in payment details.
7. **Holding:** the result is `HOLDING`, and the window is kept open. `readExpiresAt` (6 tries, 500 ms apart) parses "Complete your booking in MM:SS", or any clock near words like expire, session, hold or hurry, into `expiresAt`, which the panel counts down. `frontmost` brings the window forward with `page.bringToFront()` plus `osascript 'tell application "<Chromium app>" to activate'`.
8. **`watchOutcome`** polls every 1 s:
   - a URL on `district.in/movies/order/{orderId}` means `BOOKED`;
   - landing back on a seat layout, or "session expired" style text, for **2 polls in a row** means `EXPIRED`;
   - the context closing or no pages left means `CLOSED`.

   On `EXPIRED` or `CLOSED` the context is closed. On `BOOKED` it is left open, and `busy` is cleared in both cases.

### How it talks to District (`engine/district/catalog.js`)

- **No District API and no auth for reads.** The engine does plain `fetch` of public HTML pages with a Chrome 130 UA and `Accept-Language: en-IN`, then parses the embedded `<script id="__NEXT_DATA__">` JSON (`props.pageProps.data.serverState`).
- **Requests are serialized**, with at least **1.5 s between them**, a 20 s timeout and 1 retry on network errors or 5xx.
- **Blocking:** the first 20 KB is scanned for captcha, "access denied", "just a moment" or "unusual traffic". Those, or an HTTP 403/429, raise `BLOCKED`. A 404 is `NOT_FOUND`, any other non-200 is `HTTP`, and a missing or invalid `__NEXT_DATA__` is `PARSE`.

| Call | URL | Parsed from |
| --- | --- | --- |
| `listMovies(city)` | `/movies/{city}-movie-tickets`, plus `/movies/upcoming-movies-in-{city}` | `EDSResponse.rails[]` (`movies_listing_grid` first) → `ItemDetails.MovieData`. `release_date` is unix seconds and is converted to an IST date |
| `movieDetail(city, id)` | The movie's city path, `/movies/{slug}-movie-tickets-in-{city}-MV{id}` | `mdpV2MovieData[id]` or `movieData[id]`, plus `movieContents[id].languageFormatGroups` → `{language, fmtGrpId}` |
| `showings(city, movie, {fmtGrpId, date})` | `{moviePath}?frmtid={fmtGrpId}&fromdate={date}` (when the date key is missing, it re-fetches without `fromdate` to get `sessionDates`) | `movieSessions["{fmtGrpId lower}{date}"].arrangedSessions[].sessions[]`. `showTime` is UTC and becomes IST `startsAt`. Each session also gives `sid`, `mid`, `scrnFmt`, `avail`, `total` and `areas[].price` |
| `listCinemas(city)` | `/movies/cinemas-in-{city}` | `theatre_listing_v1` rail → `CinemaData` |

**Auth for booking** is the user's own District login inside the Playwright Chromium profile.

- **Sign-in** (`POST /login`) opens a headed window on `https://www.district.in/movies`. The user logs in there; District's login is mobile number plus SMS OTP, typed by the user. Matinee does not read the OTP. Login is detected when cookie `x-access-token` or `x-refresh-token` is present and unexpired. The engine waits 2 s more, then closes the window.
- **Login status** (`booker.loginStatus`) opens a **headless** Chromium on the same profile. It looks in the header for an `/account` link or a "Login" button, and falls back to the cookie. It runs at engine start, then whenever `/state` is polled and the last check is over 10 min old, but never while the booker is busy.
- Cookie and token values are never logged, because the logger redacts those keys. There are no Keychain items for Matinee.

### Engine HTTP API (127.0.0.1:47811, CORS `*`)

| Route | Returns |
| --- | --- |
| `GET /health` | `{ok, version, pid, startedAt}` |
| `GET /state` | `{login, booker{busy, huntId}, hunts}` |
| `GET /movies?city=` | Movie list, cached 10 min |
| `GET /movies/:id?city=` | Movie detail, cached 10 min |
| `GET /movies/:id/shows?city=&languages=&from=&to=` | Shows, cached 60 s |
| `GET /cinemas?city=` | Cinema list, cached 1 day |
| `POST /hunts` | The new hunt (201) |
| `PATCH /hunts/:id` | The updated hunt |
| `DELETE /hunts/:id` | 204 |
| `POST /hunts/:id/check` | The hunt, after a full check |
| `POST /hunts/:id/focus` | `{focused}` |
| `POST /login` | 202 |
| `POST /alerts/test {kind}` | 202 |
| `POST /shutdown` | 202 |

`/shutdown` stops the scheduler, calls `booker.release()` (closing Chromium) and exits, with a 5 s forced-exit guard. Errors come back as `{error:{code, message}}`. Every other GET serves `<repo>/dist` with an SPA fallback. When `dist/index.html` is missing, it returns a 503 page saying "run `npm run build`".

The panel polls `/state` every **2 s while visible and 10 s while hidden**.

### Notifications and alarms (`engine/alerts/alert.js`)

| Kind | When | macOS notification | Full-screen alarm |
| --- | --- | --- | --- |
| `opened` | Matches first appear | yes | no |
| `holding` | Seats held | yes | yes, `siren.wav` |
| `attention` | Not logged in, or 5 failed checks | yes | yes, `klaxon.wav` |
| `booked` | Order page seen | yes | no |

- **Notifications** come from `osascript display notification` (title and detail passed as argv), not from Pocket's `notificationShim`.
- **The alarm** is `alarm.swift`, compiled by `swiftc` to `bin/alarm` on first use, and rebuilt when the source is newer. It is spawned detached, and only one runs at a time.
  - It covers every screen with flashing red windows at shielding level.
  - It loops the sound and forces the system output volume to 100 % every 3 s.
  - It has a large acknowledge button. Clicks on it in the first 2 s are ignored; after that, a click dismisses the alarm.

### Ardia, browsers, Messages

- **Ardia:** no involvement. Ardia is Preparo's browser (`AppSpec` "preparo"); Matinee uses only Playwright's bundled Chromium.
- **Pocket's WKWebView:** shows only the local panel.
- **District pages:** opened only in the Playwright window.

## Logging

**Pocket** writes `note(...)` lines to `~/Library/Logs/pocket.log`. All are prefixed `pocket matinee`:

- `supervising path=`;
- `engine answering|silent reason= version= ours= pid=`;
- `reloading page after engine answered`;
- `engine running but silent pid= for=Ns; terminating`;
- `respawn backing off wait= failures=`;
- `node lookup failed cause=`;
- `spawn blocked cause=engine script missing path=` and `spawn blocked cause=node missing`;
- `spawn failed node= path= cause=`;
- `spawned pid= reason= node= script= attempt= log=`;
- `engine exited pid= status= reason=exit|signal expected=`;
- `placeholder shown problem= text=`;
- `shutdown requested status= cause=`;
- `engine still running after grace; terminating pid=` and `engine stopped pid= status=`;
- `leaving engine running ours=false`;
- `restart requested source=menu ours=`;
- `logs opened ok= path=`.

The generic WebApp lines (`pocket loading app=matinee …`, `pocket unread app=matinee count=`) also apply. Quick look: `grep "pocket matinee" ~/Library/Logs/pocket.log | tail`.

**The engine** writes `~/Library/Logs/Matinee/engine.log`, in the form `2026-…Z LEVEL event k=v`, where `mod` is one of catalog, booker, alerts, store, engine or http. Identifiers: `huntId`, `runId` (per booker run), `sid`, `cinemaId`, `movieId`, `date`, `fmtGrpId`. Useful events:

- **Hunts:** `hunt.status`, `hunt.checked`, `hunt.check_failed`, `hunt.armed`, `hunt.scheduled`;
- **Booking:** `booking.attempt`, `booking.result`, `booking.outcome`, `booker.open-direct-result`, `booker.seat-candidate`, `booker.selection-mismatch`, `booker.holding`, `booker.hold-failed`;
- **Catalog:** `catalog.fetch`, `catalog.blocked`, `catalog.show.date.mismatch`;
- **Login and alerts:** `login.status`, `alerts.alarm.*`;
- **Lifecycle:** `engine.starting`, `engine.shutdown`, `engine.exit`.

## Gotchas

- **Quitting Pocket drops a held seat.** `stop()` → `/shutdown` → `booker.release()` closes Chromium mid-checkout. On the next start, `store.load` turns `holding` into `paused` ("Matinee restarted"). The same happens when Matinee is disabled in Setup. Don't quit Pocket while a hunt is holding.
- **The `(!)` attention badge never shows.** `WebApp.unreadCount` only matches `\((\d[\d,]*)\)`, or a title starting with `*` or `!`. `Matinee (!)` returns 0, so the CONTRACT's attention badge doesn't render. Fix one side: either have the UI emit `!Matinee`, or teach `unreadCount` about `(!)`. The second option affects every web app, so check [web-apps.md](web-apps.md).
- **An engine Pocket didn't spawn is never stopped by Pocket**, for example one started by hand with `MATINEE_DRY_RUN=1`. **Restart engine still POSTs `/shutdown` to it**, though.
- **The engine refuses to double-start:** `main()` exits 0 if `/health` already answers, and also exits 0 on `EADDRINUSE`. To run a dry-run engine, quit Pocket, start yours, then reopen Pocket. Pocket will treat yours as foreign (`ours=false`).
- **`engine-stdout.log` grows without bound.** The engine logs every line to stdout as well as to the rotated `engine.log`, and Pocket appends stdout to `engine-stdout.log`, which nothing rotates.
- **`stop()` blocks Pocket's main thread** for up to about 8.5 s: a 2.5 s semaphore wait plus a 6 s poll. That is acceptable at quit, but noticeable when the app is disabled from Setup.
- **The spawn backoff grows even on successful spawns.** `failures += 1` on every spawn and is reset only when `/health` answers. A slow-booting engine (for example a Playwright first-run download) can reach the 10-min cap; use "Restart engine" to reset it.
- **The silent-engine kill happens after 45 s**, so a wedged-but-alive engine is SIGTERMed by the 30 s supervisor tick. A long synchronous step in the engine would trip it.
- **Headless login checks run about every 10 min while the panel is loaded**, because the panel always polls `/state` (every 10 s even when hidden) and stays loaded (`unloadAfter: nil`). Each check launches and closes a headless Chromium. On 18–19 Nov there were 168 `login.status` lines.
- **After `BOOKED` the Chromium window stays open, but `busy` is cleared.** The next `hold` or `loginStatus` closes it.
- **The cinema-page fallback uses Playwright's default 30 s `page.goto` timeout.** A timeout there surfaces as `UNEXPECTED` (2 min cooldown), not `SHOW_GONE`. It was seen in the log on 18 Nov at a Cinepolis cinema.
- **District's composite sids** (`35347__…`) are unverified for the direct seat-layout URL, which is why the cinema-page fallback exists. `catalog.show.date.mismatch` warnings, where `showTime` falls on a different IST date than the requested `fromdate`, are common (25 so far) and harmless: the date filter uses the converted `startsAt`.
- **Only one booking at a time, engine-wide.** A hunt matching while another holds just keeps its matches and re-checks.
- **Nothing in Pocket's `CLAUDE.md` or `README.md` mentions Matinee**, its port or `pocket.matinee.path`.

## How to change it safely

- **Point Pocket at another checkout:**

  ```
  defaults write com.pranav.pocket pocket.matinee.path "/path/to/Matinee"
  ```

  Then use "Restart engine".
- **Rehearse without holding seats:** quit Pocket, then run `MATINEE_DRY_RUN=1 MATINEE_HOME=/tmp/matinee-scratch node engine/server.js` from the Matinee repo, and reopen Pocket.
  - `MATINEE_HOME` keeps hunts, the profile and logs off real data.
  - A scratch home has no District login, so you must sign in there.
  - **Never run anything that clicks Proceed against live District.** The CONTRACT allows read-only probing only, at no more than 1 request per 1.5 s.
- **Engine tests:**

  ```
  node --test $(find engine -path engine/node_modules -prune -o -name '*.test.js' -print)
  ```

  They use the fixtures in `engine/fixtures/` and touch neither the network nor real data.
- **UI changes:** `npm run build` in the Matinee repo, because the engine serves `dist/`. `npm run dev` gives Vite on port 5174, proxying the API.
- **Changing the port** means changing three places together: `MatineeApp.healthURL` and `shutdownURL`, `WebSpec.url` in `Catalog.swift`, and `MATINEE_PORT` (or `paths.js` `DEFAULT_PORT`).
- **Adding a menu item:** add it to `MatineeApp.menuItems()`, with an `@objc` target of `self`, and log it with `note("pocket matinee …")`.
- **Matinee-specific behaviour in the base class:** keep it in `MatineeApp` by overriding `start`, `load`, `stop` or `menuItems`. `WebApp` is non-final only for this subclass.
- **House rules** in both repos: no code comments, and identifiers in every log line.

## Git history (Pocket repo)

The 3 commits on `add-matinee` that are not on `main` are all dated 2026-11-18 19:48 +0530. They are included in `add-schedule`, the KB worktree. Their contents:

| Commit | Change |
| --- | --- |
| `21caa1a` add matinee ticket glyph and catalog entry | `Catalog.swift` gets the `matinee` AppSpec and WebSpec; `Glyphs.swift` gets `Glyphs.matinee` |
| `41f3f44` supervise the matinee engine from pocket | New `MatineeApp.swift` (279 lines); the `Factory.swift` special case; `WebApp` changed from `final class` to `class` |
| `e5a6cee` stop apps when pocket quits | `AppDelegate`: `applicationWillTerminate` stops every app, and a SIGTERM `DispatchSource` calls `NSApp.terminate` |

`Mail.swift` and `Otp.swift` predate these commits; they were last touched in `894f825`, the Swift package port. The Matinee repo's own history (45 commits, latest `16e8194`, which added scheduled status and arming) is separate. Its commits `2a7bbe5`, `dcd54ca` and `763b044` replaced a Tauri shell with Pocket hosting; `~/Library/Logs/Matinee/shell.log` is a leftover from the Tauri era.

## Open questions / known gaps

- The Matinee repo has no git remote, so it is not backed up anywhere, and neither is `hunts.json`.
- Whether District's login always produces `x-access-token` or `x-refresh-token` was inferred from the code; it is not re-verified here. On 19 Nov the last `login.status` line said `loggedIn=false`.
- `alarm.swift` forces the volume to 100 %, and there is no "mute while in a call" logic. The `--mute` and `--auto-exit` flags exist, but `alert.js` never passes them.
- City support is effectively Chennai only: it is the default slug, and the fixtures are Chennai pages.
- If the engine dies while holding, Pocket respawns it, but the hold is lost: `store.load` pauses the hunt. Whether an orphaned Playwright Chromium survives a hard engine kill (SIGKILL, with no `shutdown`) is unverified.
