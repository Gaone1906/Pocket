# Cloud sync and the web app

Pocket's data lives on every device, not only one Mac. A hosted Postgres database (Supabase, free tier) holds one row per item, the Mac app syncs its vault files to it, and an installable web app (`web/`) works on the phone, iPad and any other laptop. Each device keeps a full local copy, so it keeps working offline and a lost device loses nothing.

Related: [data-and-backups.md](data-and-backups.md) (the vault files this syncs), [architecture.md](architecture.md) (local HTTP server).

## Pieces

| Piece | Where | Does |
| --- | --- | --- |
| Schema | `cloud/schema.sql` | One table, `public.records`, private per user through row-level security |
| Mac sync | `Sources/Pocket/CloudSync.swift` | Two-way sync of `board`, `todos`, `schedule` and `calendar` with the table |
| Web app | `web/` (`index.html`, `app.js`, `store.js`, `themes.js`, `style.css`, `sw.js`) | Focus timer and board, To-do, Schedule check-offs, Calendar with alerts, Settings and themes |
| Hosting | `.github/workflows/pages.yml` | Publishes `web/` (without `web/dev`) to GitHub Pages on pushes to `main` |
| Dev backend | `web/dev/server.mjs` | A local stand-in for Supabase auth and REST, code always `123456`, for testing without a cloud project |
| Setup link | `web/dev/link.mjs` | Prints a link that fills in the database URL and key on a new device |

## Data model

`records(user_id, kind, id, data jsonb, deleted, device, updated_at)`, primary key `(user_id, kind, id)`. `updated_at` is set by a trigger on every write. Deletes are tombstones (`deleted = true`) so other devices learn about them.

| kind | id | data | From |
| --- | --- | --- | --- |
| `board.project` | project UUID | `{id, name, hue, _pos}` | `board.json` `projects` |
| `board.session` | session UUID | `{id, ended, minutes, project?, started?, declared?}`; `ended` is seconds since 2001 | `board.json` `sessions` |
| `todo` | UUID | `{id, title, done, created, _pos}` | `todos.json` |
| `schedule.routine` | UUID | the routine, with `plan`, plus `_pos` | `schedule.json` `routines` |
| `schedule.check` | `routine\|day\|slot\|step` | the check | `schedule.json` `checks` |
| `schedule.settings` | `book` | `{nightFrom, dayFrom}` | `schedule.json` top-level scalars |
| `calendar.event` | UUID | `{id, title, start, end, allDay, notes, alert?, hue, location, repeats, until?, created, updated}` | `calendar.json` `events` |
| `pomodoro.timer` | `current` | the web timer: `{runId, phase, running, endsAt, remaining, focusMinutes, breakMinutes, longMinutes, cycle, project, device}` | web only |
| `settings.prefs` | `prefs` | `{theme, focusMinutes, breakMinutes, longMinutes, longEvery}` | web only |

`_pos` keeps list order (projects, to-dos, routines). It exists only in the cloud; the Mac strips it when it writes a file and puts its own index back when it reads one. `CloudDocument.all` in `CloudSync.swift` is the mapping; a new vault file gets one row there.

## Sync rules

Same on both sides:
- **Pull** `GET /rest/v1/records?updated_at=gt.<cursor − 2 min>&order=updated_at.asc`, paged by 1000. The 2-minute overlap covers writes that commit late; re-applying a row is harmless.
- **Push** `POST /rest/v1/records?on_conflict=user_id,kind,id` with `Prefer: resolution=merge-duplicates`, in chunks of 500.
- **Conflicts** are per item. A change made here and not yet pushed wins over the incoming copy, and the other device then pulls it. Two devices editing different items never conflict.

Mac (`CloudSync.sync()`, on the `pocket.cloud` queue):
1. Read each vault file and turn it into records. A record whose JSON differs from what was last synced (`$ROOT/cloud-state.json`, `seen`) is a local change.
2. Pull. Rows that aren't local changes and differ from `seen` are applied on main: the file is re-read, patched and handed to the store's `adopt(_:)` (board, to-dos, schedule), which replaces its state and saves. Stores that aren't loaded yet (or Calendar on this branch) get the file written directly plus a snapshot.
3. Push every local record that still differs from `seen`, and a tombstone for every `seen` item missing locally.
4. **Delete guard.** If a file is missing or unreadable it is skipped. If it is empty, or more than half of a large set (over 20) vanished at once, deletes are held and logged as `pocket cloud delete held`, never pushed.

It runs 5 s after launch, 4 s after any vault save, and every 60 s.

Web (`store.js`): edits go to a local outbox in `localStorage` and are pushed within half a second; it pulls every 4 s while the page is visible, on focus, and when the network comes back.

## Timer across devices

The web timer is a single `pomodoro.timer` record with `endsAt` in epoch ms, so every device counts down from the same moment and shows "Running from <device>". Whichever device first sees a focus end logs the session under a UUID derived from `runId:cycle`, so several devices finishing it at once write the same session once. If nobody had the app open when a break ended, the timer goes idle instead of logging sessions nobody worked. The Mac menu-bar timer is not tied to this record yet; sessions from either side reach both boards.

## Notifications

The web app asks for permission in Settings. While it is open (or installed and recently opened), it checks every 20 s and notifies for calendar alerts and focus/break changes. All-day alerts follow the Mac rule: `0` means 9 AM on the day, `1440` means 9 AM the day before. On iPhone and iPad this needs the app added to the Home Screen (iOS 16.4+). Alerts while every device is closed need web push, which is not built yet.

## Setting it up (owner, once)

1. Create a free project at supabase.com. In **SQL Editor**, run `cloud/schema.sql`.
2. **Authentication → Sign In / Providers → Email**: keep Email on. **Authentication → Emails → Magic Link**: make the body include `{{ .Token }}` so the email carries a 6-digit code (the web app and Mac sign in with the code, which works inside a Home Screen app where links don't).
3. **Project Settings → API**: copy the Project URL and the anon public key. The anon key is safe to publish; row-level security keeps rows private.
4. Turn on GitHub Pages for this repo with **Source: GitHub Actions**. After the branch is merged, the app is at `https://gaone1906.github.io/Pocket/`.
5. Make a setup link: `node web/dev/link.mjs <url> <anon key>`. Open it on each device, sign in with the emailed code, and on iPhone/iPad use Share → Add to Home Screen.
6. On the Mac:
   ```bash
   defaults write com.pranav.pocket pocket.cloud.url https://<project>.supabase.co
   defaults write com.pranav.pocket pocket.cloud.key <anon key>
   curl -X POST 127.0.0.1:8977/cloud/signin -H 'X-Pocket-Source: setup' -d '{"email":"<you>"}'
   curl -X POST 127.0.0.1:8977/cloud/verify -H 'X-Pocket-Source: setup' -d '{"code":"<code>"}'
   ```
   The first sync uploads everything on the Mac. `grep "pocket cloud" ~/Library/Logs/pocket.log | tail` shows progress.
7. Once every device is signed in, turn off **Allow new users to sign up** in Authentication settings.

Supabase's built-in email sender allows only a few emails per hour, which is plenty for signing in a handful of devices. A free project pauses after a week without any requests; daily use keeps it awake, and a paused project resumes from the dashboard with nothing lost.

## Safety

- Every device holds a full copy. Settings → **Download a copy** in the web app saves all data as JSON in the Mac's file shapes.
- The Mac still writes daily snapshots and pushes to the private `pocket-data` repo, independent of Supabase.
- Signing in needs only the email inbox, so losing any device (or all of them) doesn't lock you out.

## Testing without a cloud project

```bash
POCKET_DEV_DB=/tmp/pocket-dev.json node web/dev/server.mjs
```
It serves the web app at `http://127.0.0.1:8790` and fakes auth and REST; every sign-in code is `123456`. Point a scratch Mac run at it with `pocket.cloud.url = http://127.0.0.1:8790` and any key, and follow the scratch-run rules in [operations.md](operations.md) (those defaults are shared with the real app).

## Not built yet

- A sign-in pane in the Mac app (today it's the two `curl` calls above); it belongs in the new Pocket settings window.
- Tying the Mac menu-bar timer to `pomodoro.timer`, and syncing the Mac theme (`pomodoro.board.theme` in UserDefaults) with `settings.prefs`.
- Editing routines on the web (it shows and checks them off; edit them on the Mac).
- Web push for alerts while every device is closed.
- Calendar's `CalendarStore.adopt(_:)` lives on `claude/project-thread-tvh5lw`. Whichever of the two branches merges second adds `CloudSync.shared.register("calendar") { [weak self] data in self?.adopt(data) }` to `CalendarStore.init`, next to `persistence.onIncoming`. Adopt's own save doesn't bounce back: applied rows are recorded in `seen` first, so only fields the store normalises differently are pushed, once.
- `CloudSync.swift` has not been compiled yet; it was written on Linux. Build it on the Mac before merging.
