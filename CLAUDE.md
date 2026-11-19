# Pocket

Pocket is a macOS menu-bar app (Swift package, macOS 14+, AppKit + SwiftUI). Its Pomodoro timer can be driven by other
programs through a local HTTP API. This file tells an agent how to integrate something with it, and what to keep true when
changing it.

Full context for every app, the shell, data, theming and the current branch state lives in the knowledge base:
start at [docs/kb/README.md](docs/kb/README.md) and [docs/kb/handoff.md](docs/kb/handoff.md).

## Integrating with the Pomodoro API

Base URL `http://127.0.0.1:8977`, loopback only, JSON in and out. Pocket must be running with the Pomodoro app enabled;
otherwise every Pomodoro route answers `409`. `GET /` lists the routes.

Who may call:
- Command-line tools, scripts and native apps (no `Origin` header) are allowed.
- Browser pages are allowed only from `http://localhost:*` or `http://127.0.0.1:*`. Any other origin gets `403`, by design;
  do not widen this, since any website could otherwise start or stop the user's timer.
- Send `X-Pocket-Source: <your-tool>` on every request so Pocket's logs name you.

| Route | Does |
| --- | --- |
| `GET /pomodoro` | Current state (below) |
| `POST /pomodoro/start` | Starts focus from idle, or resumes a paused phase. Body, all optional: `{"project": "Name", "focus": 40, "rest": 8, "long": 15, "hold": true}` |
| `POST /pomodoro/pause` | Pauses a running phase; no-op otherwise |
| `POST /pomodoro/resume` | Resumes a paused phase; no-op otherwise |
| `POST /pomodoro/stop` | Back to idle. The focus in progress is discarded, not logged |
| `GET /pomodoro/projects` | `{"projects": [{id, name, minutes, sessions}]}` |
| `GET /pomodoro/sessions?since=<ISO 8601>&project=<name>` | Finished focus sessions, newest first: `{id, ended, minutes, project}` |
| `GET /pomodoro/stats` | `{"today": {minutes, sessions}, "allTime": {minutes, sessions}, "sessionMinutes": 25}` |

State from `GET /pomodoro` (every POST returns it too):

```json
{"phase": "focus", "running": true, "remaining": 2400, "endsAt": 1794813008945,
 "focusMinutes": 40, "breakMinutes": 8, "longMinutes": 8, "customPlan": true,
 "cycle": 3, "project": "Quant Question Bank"}
```

- `phase` is `idle`, `focus`, `rest` or `long`. `remaining` is in seconds; `endsAt` is epoch milliseconds and exists only while running.
- `cycle` goes up by one each time a focus phase begins. Watch it to tell "a new focus started" apart from "still the same one".

Rules that matter:
- **Durations.** `focus` 1–240, `rest` 1–90, `long` 1–120, all whole minutes. Anything else gets `400` with a message.
  Durations you leave out fall back to the user's settings, except that `long` falls back to `rest` when `rest` is given.
- **Custom durations apply only when starting from idle.** They hold until the run is stopped and are then forgotten, so they
  never touch the user's own settings. If the timer is already running, `start` keeps the current plan; check `customPlan`
  and the minutes in the response.
- **Projects.** `project` is matched to a board project by name, case-insensitively, and created when its first session is logged. A finished focus
  is logged under it; without one it lands in Unassigned. Setting `project` on a running timer re-labels the current run.
- **Declared sessions.** Sessions the user logs by hand (time worked away from the laptop) carry `"declared": true` and an
  optional `started` in `board.json`; they count like any other session.
- **Session units.** A "session" is 25 focused minutes, so a 40-minute focus counts as 1.6. Report counts the way
  `/pomodoro/stats` does, rounded to one decimal.
- **Breaks.** Pocket moves to the break and back to focus on its own; you cannot skip phases through the API. Show your own
  break screen while `phase` is `rest` or `long`.
- **Hold after break.** With `"hold": true` on a start from idle, each break ends with focus paused at full length and
  `waiting: true` instead of starting on its own; `cycle` has already gone up. `POST /pomodoro/resume` (or Start in the
  menu bar) begins it. Like custom durations, `hold` lasts until the run is stopped.

### Pattern: tie your app's work to a focus session

1. `POST /pomodoro/start` with your project and durations, and keep the returned `cycle`.
2. Poll `GET /pomodoro` once a second, and again on `visibilitychange` for web pages. Show `remaining`, or count down from `endsAt`.
3. When `phase` turns to `rest` or `long`, the focus finished and has been logged; block work until it changes back.
4. When `phase` is `focus` and `cycle` is higher than the one you kept, a new session began; load the next batch of work.
5. When `phase` is `idle`, the user stopped the timer from the menu bar; leave your session mode.
6. If a request fails because Pocket isn't running, say so in your UI and keep working without the timer; don't retry in a tight loop.

Reference integration: Preparo, the exam practice app at `~/Desktop/workspace/personal/preparo/app/app.js` (search `POCKET`) starts
40/8 sessions under "Quant Question Bank" and loads 22 questions per focus.

## Backups: setting up and restoring data

Pocket's data is four JSON files under `~/Library/Application Support/Pocket` (`$ROOT` below): `Pomodoro/board.json`
(projects and sessions), `todos.json`, `schedule.json` (Schedule routines and check-offs) and `calendar.json` (Calendar
events). Everything else there can be rebuilt. Where copies live:

| Copy | Location |
| --- | --- |
| Daily snapshots | `$ROOT/Backups/board/board-YYYY-MM-DD.json`, `$ROOT/Backups/todos/todos-YYYY-MM-DD.json`, `$ROOT/Backups/schedule/schedule-YYYY-MM-DD.json`, `$ROOT/Backups/calendar/calendar-YYYY-MM-DD.json` |
| Kept-aside and broken files | `board-before-restore-*.json` in the same folder (`schedule-before-delete-*`, `-before-merge-*`, `-before-restore-*` for the schedule); `calendar-before-merge-*` for the calendar; unreadable originals as `$ROOT/Pomodoro/board.broken-*.json`, `$ROOT/schedule.broken-*.json` or `$ROOT/calendar.broken-*.json` |
| Git repo (optional) | `board.json`, `todos.json`, `schedule.json` and `calendar.json` at the root of the private repo in `pocket.backup.repo`, cloned to `$ROOT/DataRepo` |
| Mirror folder (optional) | `pocket.backup.folder`, or `My Drive/Pocket Backups/<name>/` when Google Drive for Desktop is installed |

The owner's data repo is the private `Gaone1906/pocket-data`, synced with the `gh` account `Gaone1906`. Never put data in
the Pocket code repo; it is public.

### Moving to another Mac (the owner, or anyone restoring their own data)

Sync will not overwrite the repo with less: if the repo holds sessions, to-dos or schedule check-offs/routines this Mac
has never seen, it holds that file back, and board settings → Backup says "GitHub has N sessions this Mac doesn't" with **Bring them in** (merge by id,
keeping everything local; the current board is kept aside first) and **Keep this Mac's** (overwrite, after a confirm).
"Seen" means present locally or pushed from this Mac before, tracked by id in `$ROOT/sync-state.json`, so deleting a
session here still syncs normally. So on a new Mac the shortest path is: install, run step 5, open Pocket, press
**Bring them in**. The manual steps below are for when you'd rather put the files in place yourself.

1. Install Pocket (`scripts/install.sh`), then quit it from the menu-bar icon's right-click menu.
2. Get the data: `gh auth login`, then `gh repo clone <owner>/pocket-data /tmp/pocket-data`. Without git, download the
   newest `board-*.json`, `todos-*.json` and `schedule-*.json` from the Drive folder (`board/`, `todos/`, `schedule/`).
3. Put it in place:
   ```bash
   mkdir -p ~/Library/Application\ Support/Pocket/Pomodoro
   cp /tmp/pocket-data/board.json ~/Library/Application\ Support/Pocket/Pomodoro/board.json
   cp /tmp/pocket-data/todos.json ~/Library/Application\ Support/Pocket/todos.json
   cp /tmp/pocket-data/schedule.json ~/Library/Application\ Support/Pocket/schedule.json
   cp /tmp/pocket-data/calendar.json ~/Library/Application\ Support/Pocket/calendar.json
   ```
4. Check it parses: `python3 -m json.tool < ~/Library/Application\ Support/Pocket/Pomodoro/board.json | head`.
5. Only now turn on sync:
   ```bash
   defaults write com.pranav.pocket pocket.backup.repo https://github.com/<owner>/pocket-data.git
   defaults write com.pranav.pocket pocket.backup.githubUser <gh login>
   ```
6. Open Pocket. `~/Library/Logs/pocket.log` should show `pocket vault started ... repo=<url>` and, within about two
   minutes, `pocket vault synced ... sessions=<n>` or `sync unchanged`. Compare `n` with the session count in the repo.

### Setting up backups for a new user

1. They create their own **private** repo with one commit (e.g. a README), so it can be cloned:
   `gh repo create <login>/pocket-data --private --add-readme`.
2. They run step 5 above with their repo and login. Pocket clones it into `$ROOT/DataRepo` on its own.
3. For Drive, they install Google Drive for Desktop; no setting needed. For any other folder (iCloud, Dropbox):
   `defaults write com.pranav.pocket pocket.backup.folder "~/Library/Mobile Documents/com~apple~CloudDocs/Pocket Backups"`.
4. Snapshots need no setup and start with the first launch.

### Restoring on the same Mac

- From a daily snapshot: board settings → Backup → Restore…, pick a day. The current board is kept aside first.
- From a schedule snapshot: Schedule's expanded window → settings sidebar → Backup → Restore…; the current schedule is kept aside first.
- By hand, or for to-dos (no restore menu): quit Pocket, copy the snapshot over `board.json`, `todos.json` or
  `schedule.json` (from `$ROOT/Backups/schedule/`, or `schedule.json` in the repo), reopen.
- From an older git version: `git -C "$ROOT/DataRepo" log --oneline -- board.json`, then
  `git -C "$ROOT/DataRepo" show <sha>:board.json > /tmp/board.json`, check it, and copy it in with Pocket quit.

### Troubleshooting sync

- Settings → Backup shows the last error, and the log has the detail: `grep "pocket vault" ~/Library/Logs/pocket.log | tail`.
- `git clone failed` / `push failed`: check `gh auth status` has the login in `pocket.backup.githubUser` and that it can
  write to the repo. Sync never prompts; it uses `gh auth token -u <login>` with `GIT_TERMINAL_PROMPT=0`.
- `pull failed` usually means two Macs pushed at once. Fix it in `$ROOT/DataRepo` (`git pull --rebase`, keep the copy with
  more sessions), or delete `$ROOT/DataRepo` and Pocket will clone it again.
- "GitHub has N … this Mac doesn't": another Mac (or an older install) pushed data this one lacks. Use the buttons
  described above; the log line `pocket vault sync held name=<board|todos|schedule|calendar> unseen=<n>` gives the counts.
- To turn sync off: `defaults delete com.pranav.pocket pocket.backup.repo`.

## Schedule app

A weekly routine tracker (`⌥O`). Data model in `Sources/Pocket/ScheduleModel.swift` (`ScheduleStore.shared`, saved to
`$ROOT/schedule.json` through `DataVault` as `schedule`):
- `routines`: each has a name, a hue, a start day, notes, and a `plan` keyed `"<weekday>-<morning|night>"` (Calendar
  weekdays, 1 = Sunday), so 7 × 2 cells, each its own ordered list of steps (`title`, `tip`). Weeks repeat; there are no
  other repeat rules.
- `checks`: one per ticked step per day, with the deterministic id `routine|day|slot|step` (UUIDs and a `yyyy-MM-dd` day),
  so merging two copies is a union by id. Sync counts both check ids and routine ids as "seen".
- The day rolls over at 4am (`dayFrom`), so a 1am night routine still counts for the day before; the night slot starts at
  `nightFrom` (default 16:00, set in the Schedule settings). History starts 19 Nov 2026 (`ScheduleStore.startDay`).

Views: `ScheduleApp.swift` (the dropdown: today's morning/night checklist with tips), `ScheduleBoard.swift` (the expanded
window: Schedule and Calendar views, routine filter, settings sidebar with backups), `ScheduleEditor.swift` (the
"Change the schedule" weekly editor overlay). Views call the store's editing methods; the store does the logging.

## Calendar app

Pocket's own calendar (`⌥D`). It no longer reads macOS Calendar (no EventKit, no Calendars permission). Data model in
`Sources/Pocket/CalendarModel.swift` (`CalendarStore.shared`, saved to `$ROOT/calendar.json` through `DataVault` as
`calendar`, shaped `{"events": [...]}`):
- Each event has `id` (UUID), `title`, `start`, `end` (ISO 8601), `allDay`, `hue` (theme tint index), `location`,
  `notes`, `alert` (minutes before start, absent for none), `repeats` (`never`, `daily`, `weekdays`, `weekly`, `monthly`,
  `yearly`), optional `until` (last day, inclusive), `created` and `updated`. All-day events start at local midnight and
  end at the midnight after their last day. Missing fields decode to defaults.
- Merging another copy is a union by id where the newer `updated` wins. Sync counts event ids as "seen".
- The store reads and writes only through the `CalendarPersistence` protocol (`CalendarVaultPersistence` today), so a
  different backend can replace the vault file without touching views.
- Alerts are local notifications scheduled by `CalendarAlerts` for the next 14 days (at most 48, ids prefixed
  `pocket.calendar.`), rebuilt on every change, at launch, when the day changes and every 6 hours. All-day alerts fire at
  9 AM on the day, or 9 AM the day before. Clicking one opens the Calendar dropdown. Disabling Calendar clears them.

Views: `CalendarApp.swift` (the dropdown: month grid with colour dots and the selected day's agenda),
`CalendarBoard.swift` (the expanded window: Month and Week views, Up next sidebar, default alert), `CalendarEditor.swift`
(the add/edit card). Double-click a day or an hour to add an event; click an event to edit it. Everything draws with the
shared `Board` theme tokens; there is no theme picker inside Calendar.

## Changing Pocket itself

- Routes live in `Sources/Pocket/PocketServer.swift`, `route(_:)`. Add new routes to the `routes` table, which `GET /` serves,
  and to the table above.
- Timer behaviour lives in `Sources/Pocket/PomodoroApp.swift` (`remoteStart`, `remotePause`, `remoteResume`, `remoteStop`,
  `remoteState`). Sessions and projects are in `PomodoroBoardStore`, `Sources/Pocket/PomodoroBoard.swift`, saved to
  `~/Library/Application Support/Pocket/Pomodoro/board.json`.
- Never run tests against real data. Set `POCKET_DATA_DIR` to a scratch folder first (in a harness, `setenv` before
  anything touches `PocketData`). That moves the vault files, snapshots and the repo clone, but not the mirror folder,
  Scratchpad, the log or UserDefaults (so not `pocket.backup.repo`); see `docs/kb/operations.md` before a scratch run.
- `DataVault` (`Sources/Pocket/DataVault.swift`) owns safety: a dated snapshot on every save (30 days plus one per month),
  quarantine and recovery on unreadable loads, keep-aside before restore, an optional mirror folder, and git sync to
  `pocket.backup.repo`. Any new persisted file must load through the same guard and snapshot on save, and gets one row in
  `VaultFile.all` (name, source path, the noun for "GitHub has N …"); `DataVault.ids(in:name:)` says which ids count as
  "seen" for it.
- Validate input in the server and answer `400` with a readable message; never crash on a body.
- Log every remote action with the `note(...)` helper, including the source, project and the values that shaped the outcome.
- No comments in code.
- Build with `swift build`. Install and relaunch with `scripts/install.sh`. Then check routes with `curl`.
- Embroidered themes (`Sources/Pocket/Embroidery.swift`) load their tiger and dragon art from
  `Resources/Embroidery/*.jpg`, which `scripts/install.sh` copies into `Contents/Resources/Embroidery`. A plain
  `swift run` has no bundle, so the art is missing there and `board embroidery art missing` is logged. A new colourway
  needs a tiger and a dragon on flat black fabric (tiger lower left facing right, dragon upper right facing left), an
  `Embroidery` entry and a place in `BoardTheme.all`.
