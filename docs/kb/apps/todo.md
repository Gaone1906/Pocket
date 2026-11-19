# To-do

A plain to-do list in a dropdown panel. The menu bar shows one open task at a time, moving to the next every minute.
Everything lives in one file: `Sources/Pocket/TodoApp.swift`. It persists to `todos.json` and is protected by
`DataVault` (snapshots, quarantine/recovery, mirror folder, and git sync), but it has no restore UI.

Related: [architecture](../architecture.md) (the `PocketApp` base class, the status bar, layout),
[data and backups](../data-and-backups.md) (`DataVault` in full), [pomodoro](pomodoro.md) (the other store-backed app).

## What it is

| Thing | Value |
| --- | --- |
| Catalog entry | `Catalog.swift`: `AppSpec(id: "todo", name: "To-do", symbol: "checklist", hotKey: kVK_ANSI_T)`. No glyph, no web view. Built by `Factory.swift` `case "todo": TodoApp(spec:)` |
| Default shortcut | ⌥T (the user can change it in setup; stored in UserDefaults `shortcuts`, see [architecture](../architecture.md)) |
| Dropdown | 380 × 480, fixed size (`defaultSize`, `resizable = false`) |
| Menu-bar item | The SF Symbol `checklist` (default `PocketApp.barImage()`), plus a title showing one open task's text in the menu-bar font. With no open tasks, there is no title, just the icon. Titles over 28 characters are cut to 27 characters plus `…`. Newlines become spaces |
| Right-click menu items | None of its own (`menuItems()` is not overridden) |

What the user does:
- Type in **Add a task** and press Return. The field keeps focus so the next task can be typed straight away.
- Click the circle to toggle done. Double-click an open task's text to rename it (Return or losing focus commits, Esc cancels). Done tasks can't be renamed.
- Hover a row to reveal the ✕ delete button. Drag open tasks to reorder them; done tasks can't be dragged.
- Under the open tasks there is a **Done (n)** header with a chevron that collapses or expands the done list, and **Clear done**, which deletes every done task at once with no confirmation.
- With an empty list, the panel shows "Nothing to do. Add a task above."

## Files

`Sources/Pocket/TodoApp.swift`:

| Type | Role |
| --- | --- |
| `TodoItem` | `Codable, Identifiable, Equatable` struct with fields `id: UUID`, `title: String`, `done: Bool`, `created: Date` |
| `TodoStore` | `ObservableObject` that owns the list and the file. Its properties are `items` (`private(set)`), `focusTick`, `showDone`, `onNextChange`, `fileURL`, and the computed `open`, `finished` and `next`. Its functions are `load()`, `merge(_:)`, `add`, `toggle`, `rename`, `remove`, `moveOpen(from:to:)`, `clearDone()`, and the private `ordered`, `mutate` and `save` |
| `TodoRow` | One row: toggle button, inline edit (`@FocusState editFocused`), and a delete button shown on hover |
| `TodoView` | The panel: add field (`@FocusState addFocused`), a `List` of open rows with `.onMove`, `doneHeader`, and the done rows |
| `TodoApp` | `PocketApp` subclass. Owns one `TodoStore` and the 60 s rotation timer (`rotateEvery`, `rotation`, `rotator`). Overrides `start()`, `makeContent()`, `didShow()` and `barTitle()`, and has a private `rotate()` |

## Data

**Model.** A JSON array of `TodoItem`, with dates as ISO 8601 (`.iso8601` on both encoder and decoder). The file is
pretty-printed with sorted keys:

```json
[{"created": "2026-11-16T08:41:00Z", "done": false, "id": "…UUID…", "title": "Call the bank"}]
```

Don't confuse this with `board.json`, which uses Foundation's default date encoding (see [pomodoro](pomodoro.md#data)).

**Order invariant.** `ordered()` always keeps open items first and done items after, each group in its existing order.
Every mutation goes through `mutate(_:)`, which:
1. copies `items`;
2. applies the change;
3. re-orders the result;
4. returns early if nothing changed (so nothing is saved);
5. otherwise saves, and calls `onNextChange` if `next` (the first open item) changed.

`toggle` removes the item and appends it to the end. The result:
- a newly done task lands at the bottom of the done list;
- a task re-opened from done lands at the bottom of the open list, not at its old place.

**Where it lives.**

| What | Where |
| --- | --- |
| Live file | `PocketData.todos` = `$ROOT/todos.json`, where `$ROOT` is `~/Library/Application Support/Pocket` or `$POCKET_DATA_DIR` |
| Daily snapshots | `$ROOT/Backups/todos/todos-YYYY-MM-DD.json` (30 days, plus the first of each month kept forever) |
| Unreadable original | `$ROOT/todos.broken-YYYY-MM-DD-HHmmss.json` |
| Git repo copy | `todos.json` at the root of `$ROOT/DataRepo` (only if `pocket.backup.repo` is set) |
| Mirror | `<mirror>/todos/todos-YYYY-MM-DD.json` |

**UserDefaults.** To-do has no keys of its own. `showDone` is an in-memory `@Published` that resets to `true` on every
launch. The shortcut and the bar/dropdown placement belong to `Layout` (`shortcuts`, `layout.bar`, `layout.tray`).

**Vault wiring.**
- `VaultFile.all` has the row `VaultFile(name: "todos", source: PocketData.todos, noun: "to-do")`.
- `DataVault.ids(in:name:)` treats `todos` as the default case: a top-level array of objects whose `id` values count as "seen".
- `TodoStore.init` calls `DataVault.shared.register("todos") { merge($0) }`, so **Bring them in** can feed it.

## Flows

**Launch (`TodoApp.start()`).** Called by `AppDelegate.sync()` when `todo` is enabled.
1. `store.load()`:
   - If the file exists and decodes, `items` = `ordered(decoded)`, and it logs `loaded`.
   - If it exists but fails to decode, it logs `load failed` and calls `DataVault.quarantine(fileURL, name: "todos")`, which moves it to `todos.broken-*.json`.
   - If there is no file, or after a quarantine, it calls `DataVault.recover("todos", …)`, which walks the snapshots newest first. The first one that decodes is loaded and immediately saved back, and it logs `recovered`. If none decodes, it logs `load none` and starts empty.
2. `changed()` paints the menu bar.
3. It schedules a repeating 60 s `Timer` in `.common` run-loop mode and logs `todo bar rotation started`.

**Open the panel.** `didShow()` bumps `store.focusTick`, which `TodoView` watches to refocus the add field. `onAppear`
does the same the first time.

**Any edit.** `mutate` → `save()`:
1. creates the folder;
2. does an atomic write;
3. calls `DataVault.snapshot(data, name: "todos", count:)`.

The snapshot overwrites today's dated copy, mirrors it, and schedules a git sync about 90 s later. If `next` changed,
`onNextChange` → `TodoApp.changed()` → `StatusBar.refresh("todo")`.

**Menu-bar rotation.** Every 60 s, `rotate()` advances `rotation = (rotation + 1) % open.count` and repaints, but only
when there are 2 or more open tasks. `barTitle()` shows `open[rotation % open.count]`.

**Bring in from GitHub.** `DataVault.bringIn()` → `TodoStore.merge(data)`:
- It decodes the repo's `todos.json` and appends items whose `id` isn't already local. It never changes or removes local items.
- It goes through `mutate`, so it saves, snapshots and re-orders. It logs `merged added=<n>`.
- Unlike the board, **it does not keep the current list aside before merging**.

**Quit.** Nothing special. Every edit is already on disk. `TodoApp` doesn't override `stop()` (see Gotchas).

**Wake.** Nothing. The rotation timer simply resumes.

## Integrations

None. It has no network, no permissions and no HTTP routes. Off-machine copies go only through `DataVault` (git via
`gh auth token -u <pocket.backup.githubUser>`, and the mirror folder); see [data and backups](../data-and-backups.md).

## Logging

All lines go to `~/Library/Logs/pocket.log` through `note(...)`.

| Line | When | Carries |
| --- | --- | --- |
| `pocket todo loaded path= count= open=` | Successful load | file path, totals |
| `pocket todo load failed path= cause=` | Decode/read error | path, error |
| `pocket todo load none path= count=0 snapshots=0` | No file and no usable snapshot | path |
| `pocket todo recovered from= count=` | Loaded from a snapshot | snapshot path, count |
| `pocket todo save failed path= count= cause=` | Write error | path, count, error |
| `pocket todo clear done count=` | Clear done | number removed |
| `pocket todo merged added= count=` / `merge failed bytes= error=` | Bring in | added, new total / payload size, error |
| `todo bar rotation started every=60s open=` | `start()` | open count |

Vault lines (`pocket vault snapshot failed name=todos …`, `quarantined name=todos`, `sync held name=todos unseen=`) come
from `DataVault`. Add, toggle, rename and delete are **not** logged individually.

## Gotchas

- **The bar doesn't always repaint on edits.** `onNextChange` fires only when the *first* open item changes. These edits stay invisible until the next 60 s tick:
  - renaming the task currently shown, if it isn't the first;
  - deleting a non-first task;
  - reordering below the top.

  `rotation` is also never reset, so after edits the shown task can jump to a different index.
- **The rotation timer is never invalidated.** `TodoApp` has no `stop()` override. When the user disables To-do, the
  `Timer` stays on the run loop. Its closure captures `self` weakly, so it becomes a no-op once the app is freed, but it
  is never removed.
- **Merge is add-only.** If a to-do was marked done or renamed on another Mac, bringing in won't apply that change; only
  unseen ids are added. The repo copy is replaced on the next push (after the held state clears).
- **The store exists only while the app is enabled.** `register("todos")` runs in `TodoStore.init`, inside `TodoApp`.
  With To-do disabled, **Bring them in** logs `pocket vault bring in skipped name=todos reason=no-store`. The held
  to-dos then stay held until the user enables To-do or presses **Keep this Mac's**.
- **There's no restore UI.** Restore by hand: quit Pocket, copy `Backups/todos/todos-<day>.json` over `todos.json`, and
  reopen. (`CLAUDE.md` documents this.)
- **Re-opening a done task moves it to the end of the open list.** That's because `toggle` appends.
- **Typing `List` + `.onMove`.** The done header uses `.moveDisabled(true)`, and only the open `ForEach` has `.onMove`;
  `moveOpen` rebuilds `open + done`.
- History: `83678d2` added the app; `1a593f5` replaced "always show `next`" with the 60 s rotation; `15bdbf6` added
  guarded loads (quarantine and recover) and a snapshot on every save.

## How to change it safely

- **Scratch data.** Run with `POCKET_DATA_DIR=/tmp/pocket-scratch swift run`. Every path, `Backups/` and `DataRepo`
  included, then moves there. Under `swift run` there's no bundle id, so notifications are skipped (To-do doesn't use any
  anyway). Never point it at `~/Library/Application Support/Pocket`.
- **Adding a field to `TodoItem`.** Give it a default, or make it optional, so old files still decode. `TodoItem` uses
  synthesized `Codable`: a new non-optional property without a default value breaks decoding. That would quarantine the
  live file and fall back to an (equally undecodable) snapshot, so the user would start empty. Example:
  `var due: Date? = nil`. Keep `Equatable` intact, because `mutate` relies on it to skip no-op saves.
- **Adding a persisted setting** (for example, remembering `showDone`): add a `didSet` that writes a namespaced key such
  as `todo.showDone`, read it in `init`, and log the change with `note("pocket todo setting …")`.
- **Changing what the bar shows.** Edit `barTitle()`. Call `changed()` from any place whose change should repaint
  immediately. Consider calling it from `mutate` unconditionally, which would fix the stale-title gotcha.
- **Changing the order rules.** Keep the logic inside `ordered()` and `mutate`. `next`, `open` and `finished` all assume
  open items come first.
- **Adding a restore menu.** Copy `PomodoroBoardStore.snapshots` and `restore(_:)`, plus `BoardBackupSection.confirm`:
  `DataVault.snapshots("todos")`, then `keepAside(current, name: "todos", reason: "before-restore")` before replacing
  `items`.

## Open questions / known gaps

- Nothing keeps the current list aside before `merge`, unlike `PomodoroBoardStore.merge`. That's probably an oversight,
  but it is harmless because the merge is add-only.
- There are no tests. Behaviour was verified only by reading the code.
