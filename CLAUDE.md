# Pocket

Pocket is a macOS menu-bar app (Swift package, macOS 14+, AppKit + SwiftUI). Its Pomodoro timer can be driven by other
programs through a local HTTP API. This file tells an agent how to integrate something with it, and what to keep true when
changing it.

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
| `POST /pomodoro/start` | Starts focus from idle, or resumes a paused phase. Body, all optional: `{"project": "Name", "focus": 40, "rest": 8, "long": 15}` |
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
- **Session units.** A "session" is 25 focused minutes, so a 40-minute focus counts as 1.6. Report counts the way
  `/pomodoro/stats` does, rounded to one decimal.
- **Breaks.** Pocket moves to the break and back to focus on its own; you cannot skip phases through the API. Show your own
  break screen while `phase` is `rest` or `long`.

### Pattern: tie your app's work to a focus session

1. `POST /pomodoro/start` with your project and durations, and keep the returned `cycle`.
2. Poll `GET /pomodoro` once a second, and again on `visibilitychange` for web pages. Show `remaining`, or count down from `endsAt`.
3. When `phase` turns to `rest` or `long`, the focus finished and has been logged; block work until it changes back.
4. When `phase` is `focus` and `cycle` is higher than the one you kept, a new session began; load the next batch of work.
5. When `phase` is `idle`, the user stopped the timer from the menu bar; leave your session mode.
6. If a request fails because Pocket isn't running, say so in your UI and keep working without the timer; don't retry in a tight loop.

Reference integration: the CAT question bank at `~/Desktop/workspace/personal/cat-sectionals/app.js` (search `POCKET`) starts
40/8 sessions under "Quant Question Bank" and loads 22 questions per focus.

## Changing Pocket itself

- Routes live in `Sources/Pocket/PocketServer.swift`, `route(_:)`. Add new routes to the `routes` table, which `GET /` serves,
  and to the table above.
- Timer behaviour lives in `Sources/Pocket/PomodoroApp.swift` (`remoteStart`, `remotePause`, `remoteResume`, `remoteStop`,
  `remoteState`). Sessions and projects are in `PomodoroBoardStore`, `Sources/Pocket/PomodoroBoard.swift`, saved to
  `~/Library/Application Support/Pocket/Pomodoro/board.json`.
- Never run tests against real data. Set `POCKET_DATA_DIR` to a scratch folder first (in a harness, `setenv` before
  anything touches `PocketData`); every path, backups and the data repo included, then lives there.
- `DataVault` (`Sources/Pocket/DataVault.swift`) owns safety: a dated snapshot on every save (30 days plus one per month),
  quarantine and recovery on unreadable loads, keep-aside before restore, an optional mirror folder, and git sync to
  `pocket.backup.repo`. Any new persisted file must load through the same guard and snapshot on save.
- Validate input in the server and answer `400` with a readable message; never crash on a body.
- Log every remote action with the `note(...)` helper, including the source, project and the values that shaped the outcome.
- No comments in code.
- Build with `swift build`. Install and relaunch with `scripts/install.sh`. Then check routes with `curl`.
