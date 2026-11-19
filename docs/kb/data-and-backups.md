# Data and backups

All of this is `Sources/Pocket/DataVault.swift` unless stated otherwise. It owns where Pocket's durable data lives, daily snapshots, recovery from unreadable files, the optional mirror folder, and the optional git sync to a private repo. The rest of this page lists every persisted file and every UserDefaults key across all apps.

Related: [architecture.md](architecture.md), [operations.md](operations.md), [apps/pomodoro.md](apps/pomodoro.md), [apps/todo.md](apps/todo.md), [apps/schedule.md](apps/schedule.md), [apps/scratchpad.md](apps/scratchpad.md).

## Paths: `enum PocketData`

`PocketData.root` is `$POCKET_DATA_DIR` when that variable is set and non-empty. Otherwise it is `~/Library/Application Support/Pocket`. The value is resolved once, in a static `let`, so it must be set before anything touches `PocketData`.

| Member | Path under root | Notes |
| --- | --- | --- |
| `board` | `Pomodoro/board.json` | Pomodoro projects and sessions (`PomodoroBoardStore`) |
| `todos` | `todos.json` | To-do list (`TodoStore`) |
| `schedule` | `schedule.json` | Schedule routines and check-offs (`ScheduleStore`) |
| `calendar` | `calendar.json` | Calendar events (`CalendarStore`, through `CalendarVaultPersistence`) |
| `backups` | `Backups/` | Daily snapshots and keep-aside copies, one subfolder per vault name |
| `repo` | `DataRepo/` | Local clone of the sync repo |
| `syncState` | `sync-state.json` | Ids this Mac has pushed, per vault name: `{"board": [...], ...}` |

## `VaultFile.all`: the backed-up files

`private struct VaultFile` has three fields: `name` (the vault key, used for the backup folder and repo file name), `source` (the live file) and `noun` (the word used in "GitHub has N …").

| name | source | noun | Ids that count as "seen" (`DataVault.ids(in:name:)`) |
| --- | --- | --- | --- |
| `board` | `PocketData.board` | session | `sessions[].id` (projects are not counted) |
| `todos` | `PocketData.todos` | to-do | top-level array `[].id` |
| `schedule` | `PocketData.schedule` | check-off | `checks[].id` and `routines[].id` |

The repo holds these files as `<name>.json` at its root. `VaultFile.noun(_:)` falls back to `"item"`.

Only these three files are protected. Scratchpad, the Gmail client config, Keychain items, WebKit data and UserDefaults are not snapshotted or synced (see the [per-store table](#every-persisted-file-and-userdefaults-key)).

## `DataVault` at a glance

`final class DataVault: ObservableObject`, a singleton (`DataVault.shared`). All file and git work runs on a serial utility queue, `pocket.vault`. Published state is set on main.

| Member | Meaning |
| --- | --- |
| `keepDays = 30` | Snapshot retention, before the monthly rule |
| `folderKey = "pocket.backup.folder"` | Mirror-folder override |
| `repoKey = "pocket.backup.repo"` | Sync repo URL. Sync is off when it is unset or empty |
| `userKey = "pocket.backup.githubUser"` | `gh` login used for credentials |
| `@Published lastSnapshot` | Newest snapshot time. At init it is read only from `Backups/board/` mtimes; after that, any snapshot updates it |
| `@Published lastSync` | Set when a sync finishes with no problem |
| `@Published syncProblem` | Last error string, or the held message ("GitHub has 3 sessions and 1 to-do this Mac doesn't") |
| `@Published incoming` | `[name: unseenCount]` for held files; drives the **Bring them in** / **Keep this Mac's** buttons |
| `mergers` | `[name: (Data) -> Void]`, filled by `register(_:merge:)` from each store's init |
| `overridden` | Names the user chose to overwrite (`keepThisMac`); cleared once pushed |
| `held` | Queue-side copy of `incoming` |

`AppDelegate.applicationDidFinishLaunching` calls `DataVault.shared.start()` first, before any app starts.

## Load → quarantine → recover → seed

Each store implements this itself, in the same shape. `DataVault` provides the pieces.

1. **Load.** If the live file exists, decode it with the store's own `Codable` type. On success, log and return.
2. **Quarantine.** On a decode failure, log the error and call `quarantine(file, name:)`. This renames the file in place to `<name>.broken-yyyy-MM-dd-HHmmss.json`, in the same folder as the live file (for example `Pomodoro/board.broken-….json`). It logs `pocket vault quarantined name= from= to=`. A failure logs `quarantine failed`.
3. **Recover.** `recover(name, decode:)` walks `snapshots(name)` newest day first, and returns the first that decodes, plus its `VaultSnapshot`. Each unreadable snapshot logs `pocket vault snapshot unreadable name= path= error=`. The store then adopts the data and calls `save()`, which rewrites the live file and snapshots it.
4. **Seed / empty.** If nothing recovers:
   - `board` starts empty (`pomodoro board starting empty … snapshots=0`).
   - `todos` starts empty (`pocket todo load none …`).
   - `schedule` seeds `ScheduleSeed.hairCare()` and saves (`schedule seeded routines=1`). `ScheduleModel.swift` is the only store with a seed.

| Store | Load site | Decoder notes |
| --- | --- | --- |
| `PomodoroBoardStore` (`PomodoroBoard.swift`) | `private init()`, lazy singleton | Default `JSONDecoder`; `Saved {projects, sessions}`; dates use the default (Double seconds since 2001) |
| `TodoStore` (`TodoApp.swift`) | `load()`, called from `TodoApp.start()` | `.iso8601` dates, `[TodoItem]`, pretty-printed with sorted keys |
| `ScheduleStore` (`ScheduleModel.swift`) | `private init()`, lazy singleton | `ScheduleStore.decode` / `encode`: `.iso8601`, pretty-printed with sorted keys |

## Saves and daily snapshots

Every store `save()` does the same three steps: write the live file with `.atomic`, then call `DataVault.shared.snapshot(data, name:, count:)`, then log on failure.

`snapshot(_:name:count:)`:
- On the vault queue, it writes `Backups/<name>/<name>-yyyy-MM-dd.json` (a `.atomic` overwrite). So the daily file is **the last save of that day**.
- It then calls `prune` and `mirror`, and sets `lastSnapshot`.
- It calls `scheduleSync(after: 90)`.
- `count` is used only in the failure log (sessions, items or checks); `start()` passes `-1`.

`start()`:
- Logs `pocket vault started root= mirror=<path|none> repo=<url|none>`.
- Re-snapshots each `VaultFile` whose live file parses as JSON (any JSON, through `JSONSerialization`, not the store's `Codable`).
- Calls `scheduleSync(after: 20)`.

**Retention (`prune`).** Snapshots sorted oldest first. The first snapshot of each calendar month (`yyyy-MM`) is kept forever. Every other snapshot older than 30 days is deleted. The log reads `pocket vault pruned name= removed= kept=`.

**Listing (`snapshots(name)`).** Lists files in `Backups/<name>/` whose base name is `<name>-` followed by something that parses as `yyyy-MM-dd`. It returns `[VaultSnapshot(url, day)]`, newest first. Keep-aside and broken files don't parse, so they are neither listed nor pruned; they stay forever.

## Keep-aside copies

`keepAside(data, name:, reason:)` writes `Backups/<name>/<name>-<reason>-yyyy-MM-dd-HHmmss.json` and logs `pocket vault kept aside name= reason= path=`. It is synchronous, on the caller's thread. These are the callers:

| Caller | name | reason |
| --- | --- | --- |
| `PomodoroBoardStore.merge` | board | `before-merge` |
| `PomodoroBoardStore.restore` | board | `before-restore` |
| `ScheduleStore.merge` | schedule | `before-merge` |
| `ScheduleStore.restore` | schedule | `before-restore` |
| `ScheduleStore.deleteRoutine` | schedule | `before-delete` |

`TodoStore.merge` keeps nothing aside. It only adds items, so nothing is lost.

## Mirror folder

`mirrorFolder` resolves in this order:
1. The `pocket.backup.folder` default, if non-empty. `~` is expanded. Set it with `defaults write com.pranav.pocket pocket.backup.folder "<path>"`.
2. Otherwise, the first entry in `~/Library/CloudStorage/` whose name starts with `GoogleDrive-`, with `My Drive/Pocket Backups` appended. This is Google Drive for Desktop.
3. Otherwise `nil`, and mirroring is skipped.

`mirror(file, name:)` copies each **daily snapshot** (not keep-asides, not broken files) to `<mirror>/<name>/<same filename>`, replacing any existing file of that name. Failures log `pocket vault mirror failed name= target= error=`.

- **Mirror copies are never pruned.** The mirror keeps every day forever.
- The backup UI shows a "Copy" line as "Google Drive" when the folder's last component is `Pocket Backups`; otherwise it shows the folder name.

**State on the owner's Mac (checked 2026-11-19).** Google Drive for Desktop is **not installed**. `~/Library/CloudStorage` holds only an iCloud Drive entry, and `pocket.backup.folder` is unset. So the log shows `mirror=none` and nothing is mirrored. The README's "mirrored to Google Drive" claim only holds once Drive for Desktop is installed or the folder key is set.

## Git sync

The repo is configured by `pocket.backup.repo`. The owner uses `https://github.com/Gaone1906/pocket-data.git`, a **private** repo, through the `gh` account in `pocket.backup.githubUser` (`Gaone1906`). Never point it at the public code repo.

**Scheduling.** `scheduleSync(after:)` is a no-op without a repo URL. Otherwise it sets `syncPending` and fires `sync()` once after the delay. Further calls are ignored while one is pending.
- This is a throttle, not a debounce: the first save starts the 90 s clock.
- At launch, `start()` queues its per-file `snapshot` calls (each scheduling 90 s) before its own `scheduleSync(after: 20)`. So when any data file exists, the 20 s request is dropped and the first sync runs about 90 s after launch.
- `syncNow()` runs immediately. It is used after `bringIn`.

**`sync()` steps (vault queue):**
1. If `DataRepo/.git` is missing, run `git clone <remote> DataRepo` in root. The clone needs the repo to have at least one commit.
2. Run `git pull --rebase --quiet`.
3. Load `known` from `sync-state.json`.
4. For each `VaultFile`, collect the `local` ids, the `remote` ids (from `DataRepo/<name>.json`), and `unseen = remote − local − known[name]`. Then:
   - If `unseen` is non-empty and the name isn't in `overridden`, the file is **held**: `blocked[name] = unseen.count`, the log reads `pocket vault sync held name= unseen= local= remote=`, and the repo copy is left untouched.
   - Otherwise, if the live file exists, copy it over `DataRepo/<name>.json` and record `pushed[name] = local`.
   - For `board`, count `sessions` for the commit message.
5. Publish `held`/`incoming`.
6. Run `git add -A`. If `git diff --cached --quiet` reports no change, call `remember`, finish, and log `pocket vault sync unchanged repo= held=`.
7. Otherwise, commit `backup yyyy-MM-dd-HHmmss sessions=<n>`, push, call `remember`, finish, and log `pocket vault synced repo= sessions= held=`.

`remember(pushed, into:)` sets `known[name] = local ids` (a replace, not a union) for each pushed name, removes the name from `overridden`, and writes `sync-state.json` (sorted arrays, sorted keys).

**Hold rule.** "Seen" means present locally now, or pushed from this Mac before. Deleting a session locally doesn't cause a hold, because its id is in `known`. A new Mac, or a second Mac that pushed, does cause one. Held names surface as `syncProblem` = `heldMessage` (for example "GitHub has 4 sessions and 2 check-offs this Mac doesn't"), shown as a red "GitHub" line in the Backup sections. Other, non-held files keep syncing.

**Resolving a hold:**
- **Bring them in** (`bringIn()`): on the queue, read `DataRepo/<name>.json` for each held name. Then, on main, call each registered merger and `syncNow()`. Without a merger, the log reads `pocket vault bring in skipped name= reason=no-store`. Mergers union by id, keeping everything local:
  - `PomodoroBoardStore.merge`: adds unknown projects and sessions, then re-sorts sessions by `ended`.
  - `TodoStore.merge`: appends unknown items.
  - `ScheduleStore.merge`: adds unknown routines and checks.

  Board and schedule keep a copy aside first.
- **Keep this Mac's** (`keepThisMac()`, after an `NSAlert` confirm): adds the held names to `overridden` and syncs, overwriting the repo copy. The data stays in the repo history.

**Credentials (`git(_:in:step:quiet:)`).**
- Runs `/usr/bin/git -c credential.helper= -c credential.helper=<helper>`. The inline helper prints `username=<githubUser>` and `password=$(gh auth token [-u <githubUser>])`.
- `gh` is `/opt/homebrew/bin/gh`, then `/usr/local/bin/gh`, then `gh` on `PATH`.
- Environment: `GIT_TERMINAL_PROMPT=0` and `PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin`.
- It never prompts. No token is stored by Pocket.
- On failure it sets `syncProblem = "git <step> failed"` and logs `pocket vault git failed step= status= detail=<stderr, up to 300 chars>`. `quiet: true` (used for `diff --cached`) suppresses this.

## Restore flows

| What | Where in UI | Code |
| --- | --- | --- |
| Board from a daily snapshot | Pomodoro board → settings (slider icon) → BACKUP → **Restore…** menu. Each row shows the day, session count and duration | `BoardBackupSection.confirm` (`NSAlert`) → `PomodoroBoardStore.restore(snap)`: keeps aside `before-restore`, replaces projects and sessions, saves. Logs `pomodoro board restored from= sessionsBefore= sessionsAfter=` |
| Schedule from a daily snapshot | Schedule expanded window → settings sidebar → BACKUP → **Restore…**. Rows show routines and check-offs | `ScheduleBackupSection.confirm` → `ScheduleStore.restore(snap)`. Logs `schedule restored from= checksBefore= checksAfter=` |
| To-dos | No UI | Quit Pocket, copy `Backups/todos/todos-<day>.json` over `todos.json`, reopen |
| Older git version | Shell | `git -C "$ROOT/DataRepo" log --oneline -- board.json`, then `git show <sha>:board.json`. Copy it in with Pocket quit |
| New Mac | Set `pocket.backup.repo` and `githubUser`, open Pocket, press **Bring them in** | See CLAUDE.md "Moving to another Mac" |
| Undo a restore or merge | Restore… doesn't list keep-asides | Copy `Backups/<name>/<name>-before-restore-….json` over the live file by hand, with Pocket quit |

Both Backup sections also show:
- "Daily copy saved …", from `lastSnapshot`;
- the "GitHub" status;
- the mirror "Copy" line;
- **Show backups**, which runs `showInFinder()` and reveals `Backups/` in Finder.

`BoardBackupSection` is `private` in `PomodoroBoard.swift`; `ScheduleBackupSection` is `private` in `ScheduleBoard.swift`. They are near-duplicates.

## Every persisted file and UserDefaults key

The defaults domain is `com.pranav.pocket` for the installed app bundle. An unbundled `swift run` uses a different domain; this is believed to be the executable name, but it hasn't been verified.

### Files

| Store / owner | Path | Format | Vault-backed | Honors `POCKET_DATA_DIR` |
| --- | --- | --- | --- | --- |
| `PomodoroBoardStore` (`PomodoroBoard.swift`) | `$ROOT/Pomodoro/board.json` | JSON `{projects, sessions}` | yes (`board`) | yes |
| `TodoStore` (`TodoApp.swift`) | `$ROOT/todos.json` | JSON array, ISO 8601 | yes (`todos`) | yes |
| `ScheduleStore` (`ScheduleModel.swift`) | `$ROOT/schedule.json` | JSON `ScheduleBook`, ISO 8601 | yes (`schedule`) | yes |
| `CalendarStore` (`CalendarModel.swift`) | `$ROOT/calendar.json` | JSON `CalendarBook` (`{"events": [...]}`), ISO 8601 | yes (`calendar`, noun "event") | yes |
| `DataVault` | `$ROOT/Backups/<name>/…`, `$ROOT/DataRepo/`, `$ROOT/sync-state.json` | JSON / git | n/a | yes |
| `ScratchStore` (`ScratchpadApp.swift`) | `~/Library/Application Support/Pocket/Scratchpad/pages.json` plus `<page-uuid>.rtf` | JSON index plus RTF | **no** | **no** (hardcoded to `NSHomeDirectory()`) |
| `GoogleAuth.load` (`Mail.swift`) | `~/Library/Application Support/Pocket/google-client.json` | `{"id","secret"}` OAuth desktop client, user-provided | no | no (hardcoded) |
| `Keychain` (`Mail.swift`) | Keychain generic password, service `com.pranav.pocket.gmail`, account = Gmail address | Refresh token | no | n/a |
| Web apps (`WebApp.swift`, `Catalog.swift`) | `WKWebsiteDataStore(forIdentifier: site.store)`, one fixed UUID per web app (`6B1F2C1E-…7A01`…`7A06`) | WebKit-managed; exact on-disk location not verified | no | no |
| `Log.swift` | `~/Library/Logs/pocket.log`, rotated to `.1` above 5 MB at launch | text | no | no |
| `MatineeApp` | `~/Library/Logs/Matinee/engine-stdout.log` | text | no | no |
| `OtpWatcher` (`Otp.swift`) | Reads `~/Library/Messages/chat.db` (and `-wal`); never writes | SQLite | n/a | n/a |

### UserDefaults keys

| Key | Type | Owner (file) | Meaning |
| --- | --- | --- | --- |
| `pocket.backup.repo` | String | `DataVault` | Sync repo URL; unset = sync off |
| `pocket.backup.githubUser` | String | `DataVault` | `gh` login for `gh auth token -u` |
| `pocket.backup.folder` | String | `DataVault` | Mirror-folder override (`~` allowed) |
| `pomodoro.board.theme` | String | `BoardThemeStore` (`BoardTheme.swift`) | Theme id, shared by Pomodoro and Schedule; see [theme.md](theme.md) |
| `pomodoro.focus`, `pomodoro.break`, `pomodoro.long`, `pomodoro.longEvery` | Int | `PomodoroModel` (`PomodoroApp.swift`) | Timer lengths in minutes; long break every N sessions |
| `pomodoro.streak` | Int | `PomodoroModel` | Focus count toward the long break |
| `pomodoro.board.stats`, `pomodoro.board.panel` | Bool (`@AppStorage`) | `PomodoroBoardView` | Stats sidebar shown; settings panel open |
| `pomodoro.board.mode` | String (`@AppStorage`) | `PomodoroBoardView` | `sessions` or `calendar` |
| `schedule.filter` | String (UUID) | `ScheduleStore` | Routine filter; nil = all |
| `schedule.board.span` | String | `ScheduleBoardFocus` (`ScheduleBoard.swift`) | `ScheduleSpan` raw value; default `.day` |
| `schedule.board.mode` | String (`@AppStorage`, `ScheduleBoardMode.key`) | `ScheduleBoardView` | `schedule` or `calendar` |
| `schedule.board.stats`, `schedule.board.panel` | Bool (`@AppStorage`) | `ScheduleBoardView` | Stats column; settings panel |
| `stats.cpuInBar` | Bool | `StatsApp.swift` | Show CPU in the menu bar |
| `pocket.matinee.path` | String | `MatineeApp` | Matinee repo path; default `~/Files/Personal Projects/Matinee` |
| `gmailAccounts` | [String] | `MailWatcher` (`Mail.swift`) | Gmail addresses watched for OTPs |
| `keepMessages` | Bool | `OtpWatcher` | `false` stops Pocket keeping Messages open |
| `setup.done` | Bool | `Layout.swift` | Setup finished |
| `hotkeys.enabled` | Bool, default true | `Layout` | Global shortcuts on |
| `otp.enabled` | Bool | `Layout` | OTP watcher on |
| `layout.bar`, `layout.tray` | [String] | `Layout` | App ids in the menu bar and in the dropdown |
| `layout.offered` | [String] | `Layout` | Catalog ids already offered (new apps get placed once) |
| `shortcuts` | Data (JSON `[id: Shortcut]`) | `Layout` | Per-app shortcuts |
| `shortcuts.offered` | [String] | `Layout` | Ids whose default shortcut was already applied |
| `size.<appId>` | String (`NSStringFromSize`) | `PocketApp.swift` | Remembered panel size per resizable app |

**Stale keys.** On the owner's Mac (2026-11-19), `com.pranav.pocket` also holds `pomodoro.board.settings`, `scene.enabled`, `scene.freeRight` and `scene.hue.base`. No current source reads them; they look like leftovers from removed features.

## How to add a new vault-backed store

1. **Path.** Add `static var <name>: URL { root.appendingPathComponent("<name>.json") }` to `PocketData`. Never hardcode `NSHomeDirectory()`.
2. **Register.** Add `VaultFile(name: "<name>", source: PocketData.<name>, noun: "<singular>")` to `VaultFile.all`. The noun is pluralised with a plain `s`.
3. **Ids.** If the file isn't a top-level array of `{id}` objects, add a `case "<name>"` to `DataVault.ids(in:name:)` listing the arrays whose `id`s count as seen. Ids must be strings and stable across Macs (UUIDs or deterministic keys). Otherwise the hold rule misfires.
4. **Load.** In the store's init or load, follow the guard exactly: decode, then `quarantine`, then `recover(name, decode:)`, then save the recovered data, then an empty state or a seed. Log each branch with counts.
5. **Save.** Write `.atomic` to the live file, then `DataVault.shared.snapshot(data, name:, count:)`.
6. **Merge.** Call `DataVault.shared.register("<name>") { [weak self] in self?.merge($0) }` in init. `merge` must union by id, never drop local data, and `keepAside(... reason: "before-merge")` first. Register as early as possible: the store must exist for **Bring them in** to work (see gotchas).
7. **Restore (optional).** Expose `snapshots` and `restore(_:)` like `ScheduleStore`, and keep aside `before-restore`.
8. **Docs.** Update CLAUDE.md's backup table and README "Your data".
9. **Testing.** Launch with `POCKET_DATA_DIR=<scratch>`, and also make sure the defaults domain has no `pocket.backup.repo` (see gotchas).

## Logging

All lines start `pocket vault`:
- `started`, `snapshot failed`, `snapshot unreadable`;
- `quarantined`, `quarantine failed`;
- `kept aside`, `keep aside failed`;
- `pruned`, `prune failed`, `mirror failed`;
- `bring in skipped`, `brought in`, `keeping local over github`, `keep local cancelled`;
- `sync held`, `sync unchanged`, `synced`;
- `sync state write failed`, `git failed`.

They carry `name=`, `path=`, `count=`, `repo=`, `unseen=`, `local=` and `remote=` as relevant.

Store-side lines:
- Board: `pomodoro board loaded|load failed|recovered|starting empty|merged|restored|save failed`.
- To-dos: `pocket todo loaded|load failed|recovered|load none|merged|save failed`.
- Schedule: `schedule loaded|load failed|recovered|seeded|merged|restored|save failed`.

Triage: `grep "pocket vault" ~/Library/Logs/pocket.log | tail`.

## Gotchas

- **`POCKET_DATA_DIR` does not isolate sync or the mirror.** It moves every `PocketData` path, including `DataRepo`. But `pocket.backup.repo`, `githubUser` and `folder` come from UserDefaults, and the Google Drive lookup uses the real home. A scratch run in a process whose defaults domain has `pocket.backup.repo` set would clone the real private repo into the scratch root, and could push scratch data. The hold rule blocks overwriting ids it hasn't seen, but don't rely on that. CLAUDE.md says "every path … then lives there", which is true of paths only.
- **Mergers register lazily.**
  - `PomodoroBoardStore.shared` is created on the first finished focus, the first board open, or the first API call that touches it (`PocketServer`).
  - `TodoStore` exists only while the To-do app is enabled.
  - `ScheduleStore.shared` is created when the Schedule app starts.

  Pressing **Bring them in** before a store exists logs `bring in skipped … reason=no-store`, and the file stays held. In practice the board is registered by the time its own Backup section is visible. But pressing the button in Schedule's Backup section before the Pomodoro board was ever touched skips the board, and a disabled To-do app leaves `todos` held forever (use **Keep this Mac's**, or enable To-do).
- **Daily snapshot = last write of the day.** A bad save late in the day overwrites that day's good snapshot. The previous day's is still there.
- **`start()` can overwrite today's snapshot with a file that is valid JSON but not decodable**, because it checks only `JSONSerialization`. Recovery still falls back to older days, but today's earlier good copy is gone. `start()` runs asynchronously on the vault queue, so it races with store loads.
- **The mirror folder is never pruned**, and gets only daily snapshots.
- **Keep-aside and broken files are never pruned and not listed in Restore…**; they accumulate in `Backups/<name>/` and next to the live file.
- **`lastSnapshot` at launch reads only `Backups/board/`.** On a Mac with to-dos or schedule but no board, it shows "none yet" until the first snapshot.
- **The commit message's `sessions=` is 0 when the board is held or missing.**
- **Clone failure.** `clone` fails if `DataRepo` exists without `.git`, or if the remote is empty (no commits). Delete `DataRepo` and fix the remote.
- **Two Macs pushing at once** makes `pull --rebase` fail on a conflict in `<name>.json`. Pocket reports `git pull failed` until it is fixed by hand in `DataRepo` (or `DataRepo` is deleted to re-clone).
- **Scratchpad is unprotected**: no snapshot, no quarantine (a bad `pages.json` just logs and shows an empty list, then `create()` saves a fresh index over it), and no sync.

## History

From `git log -- Sources/Pocket/DataVault.swift`:

| Commit | Change |
| --- | --- |
| 7ee92cc | Vault, snapshots, recovery and GitHub sync |
| d2d5573 | Hold rule, `sync-state.json`, bring in / keep this Mac |
| 4882c90 | `PocketData.schedule` |
| f21de11 | `schedule` in `VaultFile.all` and in `ids` (checks + routines) |

## Open questions

- The exact defaults domain under `swift run` or a test harness hasn't been verified.
- Where WebKit stores `WKWebsiteDataStore(forIdentifier:)` data on disk hasn't been verified.
- There is no to-do restore UI, and Restore… doesn't offer keep-asides. Both are possible additions.
- `sync()` treats every vault file independently but commits them together. A held board still lets todos and schedule push, which is intended but worth knowing.
