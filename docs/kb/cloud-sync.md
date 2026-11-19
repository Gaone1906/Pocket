# Cloud sync and the web app

Pomodoro and Orario (the Schedule app) live on every device, not only one Mac. A hosted Postgres database (Supabase, free tier) holds one row per item, the Mac app syncs those two vault files to it, and an installable web app (`web/`) works on the phone, iPad and any other laptop. To-do, Calendar and Matinee stay Mac-only by choice (Pranav, 2026-11-19). Each device keeps a full local copy, so it keeps working offline and a lost device loses nothing.

Related: [data-and-backups.md](data-and-backups.md) (the vault files this syncs), [architecture.md](architecture.md) (local HTTP server).

## Pieces

| Piece | Where | Does |
| --- | --- | --- |
| Schema | `cloud/schema.sql` | One table, `public.records`, open to the app's anon key |
| Mac sync | `Sources/Pocket/CloudSync.swift` | Two-way sync of `board` and `schedule` with the table |
| Web app | `web/` (`index.html`, `app.js`, `store.js`, `orario.js`, `util.js`, `themes.js`, `style.css`, `sw.js`) | Orario's Hair routine only, Settings and themes |
| Orario (all routines) | `web/orario/` | A separate, self-contained web app with every routine: Day, Week and Month, the routine filter, Change the schedule, and Settings. Same table and setup link; its own local copy (`orario.cloud.v1`), service worker and Home Screen entry. In a browser that already holds the main app's link, it connects without asking |
| Hosting | `.github/workflows/pages.yml` | Publishes `web/` (without `web/dev`) to GitHub Pages on pushes to `main`; `web/orario/` lands at `https://gaone1906.github.io/Pocket/orario/` |
| Dev backend | `web/dev/server.mjs` | A local stand-in for the Supabase REST API, for testing without a cloud project |
| Setup link | `web/dev/link.mjs` | Prints a link that fills in the database URL and key on a new device |

## Data model

`records(user_id, kind, id, data jsonb, deleted, device, updated_at)`, primary key `(user_id, kind, id)`; `user_id` is always the shared zero UUID. `updated_at` is set by a trigger on every write. Deletes are tombstones (`deleted = true`) so other devices learn about them.

| kind | id | data | From |
| --- | --- | --- | --- |
| `board.project` | project UUID | `{id, name, hue, _pos}` | `board.json` `projects` |
| `board.session` | session UUID | `{id, ended, minutes, project?, started?, declared?}`; `ended` is seconds since 2001 | `board.json` `sessions` |
| `schedule.routine` | UUID | the routine, with `plan`, plus `_pos` | `schedule.json` `routines` |
| `schedule.check` | `routine\|day\|slot\|step` | the check | `schedule.json` `checks` |
| `schedule.settings` | `book` | `{nightFrom, dayFrom}` | `schedule.json` top-level scalars |
| `settings.prefs` | `prefs` | `{theme}` | web only |

`_pos` keeps list order (projects, routines). It exists only in the cloud; the Mac strips it when it writes a file and puts its own index back when it reads one. `CloudDocument.all` in `CloudSync.swift` is the mapping; a new vault file gets one row there.

## Sync rules

Same on both sides:
- **Pull** `GET /rest/v1/records?updated_at=gt.<cursor − 2 min>&order=updated_at.asc`, paged by 1000. The 2-minute overlap covers writes that commit late; re-applying a row is harmless.
- **Push** `POST /rest/v1/records?on_conflict=user_id,kind,id` with `Prefer: resolution=merge-duplicates`, in chunks of 500.
- **Conflicts** are per item. A change made here and not yet pushed wins over the incoming copy, and the other device then pulls it. Two devices editing different items never conflict.

Mac (`CloudSync.sync()`, on the `pocket.cloud` queue):
1. Read each vault file and turn it into records. A record whose JSON differs from what was last synced (`$ROOT/cloud-state.json`, `seen`) is a local change.
2. Pull. Rows that aren't local changes and differ from `seen` are applied on main: the file is re-read, patched and handed to the store's `adopt(_:)` (board, schedule), which replaces its state and saves. A store that isn't loaded yet gets the file written directly plus a snapshot.
3. Push every local record that still differs from `seen`, and a tombstone for every `seen` item missing locally.
4. **Delete guard.** If a file is missing or unreadable it is skipped. If it is empty, or more than half of a large set (over 20) vanished at once, deletes are held and logged as `pocket cloud delete held`, never pushed.

It runs 5 s after launch, 4 s after any vault save, and every 60 s.

Web (`store.js`): edits go to a local outbox in `localStorage` and are pushed within half a second; it pulls every 4 s while the page is visible, on focus, and when the network comes back.

## What the web app does

Built for an iPhone 14 screen first (390 pt wide, Home Screen app), with a sidebar layout on laptops.

- **Hair only** (Pranav, 2026-11-19): this is the app shared with Pranav's parents, so it shows only the Orario routine whose name contains "hair". Day, Week and Month views, today's morning and night checklists with tips, Mark all done / Undo all, the week strip and month marks, and **Change the schedule** for that routine's steps (add, edit, reorder and delete per weekday and slot). It can't add, rename or delete routines, Pomodoro isn't shown, and no app or routine name appears (the tab, page title and Home Screen name read "Routine"). Every other record in the table, other routines and Pomodoro included, is synced and kept untouched. A separate Orario app with every routine and a separate Pomodoro web app are planned.
- **Settings**: theme (shared with every device), night start hour, sync status, Download a copy, Disconnect.

## Setting it up (owner, once)

The owner's project is **Pocket** (ref `oisplnonpwyvekcbwmhv`, Mumbai). The other project in the same Supabase org belongs to a different app; never touch it.

There is no sign-in (Pranav's choice, 2026-11-19: he doesn't need the data kept private, and Supabase now needs a custom SMTP sender before its emails can carry a code). The table is open to the anon key and every row uses the fixed `user_id` `00000000-0000-0000-0000-000000000000`. Anyone who has the setup link can read and change the data, so the link stays private; the code repo never contains the key.

1. Create a free project at supabase.com. In **SQL Editor**, run `cloud/schema.sql`.
2. **Project Settings → API**: copy the Project URL and the anon public key.
3. Turn on GitHub Pages for this repo with **Source: GitHub Actions**. The app is at `https://gaone1906.github.io/Pocket/`.
4. Make a setup link: `node web/dev/link.mjs <url> <anon key>`. Open it on each device; it starts syncing straight away. On iPhone/iPad, add the app to the Home Screen and open it from there: a Home Screen app has its own storage, so it shows the setup screen once, where you paste the same link.
5. On the Mac: `curl -X POST 127.0.0.1:8977/cloud/connect -H 'X-Pocket-Source: setup' -d '{"link":"<setup link>"}'`. It saves the URL and key in UserDefaults (`pocket.cloud.url`, `pocket.cloud.key`), and the first sync uploads everything on the Mac. `grep "pocket cloud" ~/Library/Logs/pocket.log | tail` shows progress.
6. In **Authentication → Sign In / Providers**, turn off **Allow new users to sign up**; nothing uses accounts.


## Safety

- Every device holds a full copy. Settings → **Download a copy** in the web app saves all data as JSON in the Mac's file shapes.
- The Mac still writes daily snapshots and pushes to the private `pocket-data` repo, independent of Supabase.
- There is nothing to sign in to, so losing any device (or all of them) doesn't lock you out. Keep a copy of the setup link somewhere safe.

## Testing without a cloud project

```bash
POCKET_DEV_DB=/tmp/pocket-dev.json node web/dev/server.mjs
```
It serves the web app at `http://127.0.0.1:8790` and fakes the REST API; any key works. Open `http://127.0.0.1:8790/` and enter that URL with any key. Point a scratch Mac run at it with `pocket.cloud.url = http://127.0.0.1:8790` and any key, and follow the scratch-run rules in [operations.md](operations.md) (those defaults are shared with the real app).

## Not built yet

- A pane in the Mac app to paste the setup link (today it's the `curl` call above); it belongs in the new Pocket settings window.
- Syncing the Mac theme (`pomodoro.board.theme` in UserDefaults) with `settings.prefs`.
- `CloudSync.swift` has not been compiled yet; it was written on Linux. Build it on the Mac before merging.
