# Scratchpad

## What it is
Rich-text notes organised in pages.

- **Catalog:** `id: "scratchpad"`, symbol `note.text`, shortcut ⌥N (`kVK_ANSI_N`). It has no glyph and no badge.
- **Panel:** 560×520 by default, resizable, minimum 440×360. The size is saved in UserDefaults `size.scratchpad`.
- **Left sidebar** (150 pt):
  - a "PAGES" header with a new-page button (`square.and.pencil`);
  - pages, newest-created first. Each shows its title (or "New page") and its last-updated time. Right-click a page for "Delete page" (there's no confirmation).
- **Right pane:** a toolbar and the editor. The toolbar has Bold, Italic, Underline and Strikethrough; then Heading, Bulleted list, Numbered list and Dashed list.
- **Markdown-ish triggers:** typing a trigger at the start of a line, followed by a space, converts the line:
  - `- `, `* ` or `• ` gives a bulleted list;
  - `1. ` or `1) ` gives a numbered list;
  - `# ` gives a heading.
- **No formatting shortcuts.** Commit `169e810` removed ⌘B, ⌘I and the others; only the toolbar and the triggers remain. ⌘B and its siblings fall through to the default `NSTextView` behaviour, if any.

## Files
All in `Sources/Pocket/ScratchpadApp.swift`.

| Symbol | Role |
| --- | --- |
| `ScratchPage` (`Codable`) | `id: UUID`, `title: String`, `updated: Date` |
| `ScratchStore` (`ObservableObject`) | `pages`, `current: UUID?`, `folder`. Methods: `load()`, `saveIndex()`, `create()`, `delete(_:)`, `text(_:)` (reads RTF), `save(_:_:)` (writes RTF and updates the title and `updated`) |
| `ScratchFormat` | `bodySize` 13, `headingSize` 19. Marker formats: `bullet` = `.disc`, `numbered` = `"{decimal}."`, `check` = `.hyphen` (the "Dashed list"). `body` attributes, and `paragraph(_ list:)`, which sets `textLists`, the tab stops (18 right, 26 left) and `headIndent` 26 |
| `ScratchTextView: NSTextView` | `toggleTrait(_:)` (bold, italic), `toggleAttribute(_:)` (underline, strikethrough), `toggleHeading()`, `toggleList(_:)`, `applyShortcutAfterSpace()` |
| `ScratchEditor` (`NSViewRepresentable`) and its `Coordinator` | Builds the scroll view and text view: TextKit 1 (`usingTextLayoutManager: false`), rich text, undo, smart quotes and dashes off. The coordinator does `show(_:)` (load a page), `flush()` (save), the `textDidChange` debounce, and `shouldChangeTextIn` (the space triggers) |
| `ScratchView` | SwiftUI sidebar and toolbar. `tool(...)` focuses the editor and then applies the action |
| `ScratchpadApp` | `PocketApp` subclass. `didShow` focuses the text view; `didHide` flushes. `find(in:)` walks the view tree to reach the `ScratchTextView` |

## Data
- **Folder:** `~/Library/Application Support/Pocket/Scratchpad/`, built from `NSHomeDirectory()`, **not** from `PocketData`, so it ignores `POCKET_DATA_DIR` (see Gotchas).
  - `pages.json` holds a JSON array of `ScratchPage`, in sidebar order (newest-created first). Dates use `JSONEncoder` defaults: seconds since 2001 as a Double.
  - `<UUID>.rtf` holds one RTF file per page, written atomically. Its name is `id.uuidString` (uppercase).
- **Title:** the first non-empty line of the page's text, with any list marker prefix (`\t<marker>\t`) stripped, trimmed and cut to 60 characters. It's recomputed on every save.
- **Not in `DataVault`.** No daily snapshots, no git sync, no Drive mirror, no quarantine of unreadable files. If `pages.json` fails to decode, the error is logged, `pages` stays empty and a **new page is created and the index saved**, which overwrites the unreadable index; the RTF files stay on disk, orphaned.
- There are no UserDefaults keys beyond `size.scratchpad`.

## Flows
- **Init** (when the app is constructed in `AppDelegate.sync`):
  1. Create the folder.
  2. Load `pages.json` if present.
  3. If there are no pages, `create()` one.
  4. `current` is the first page.
- **Open** (`didShow`) makes the `ScratchTextView` first responder. When the editor is first created, the coordinator's `show(current)` loads that page's RTF, resets the typing attributes, clears undo, puts the caret at the end and focuses.
- **Typing:**
  1. `textDidChange` (re)arms a 0.8 s `DispatchWorkItem`.
  2. `flush()` cancels any pending work and saves the loaded page. `save` serialises the whole text storage to RTF and writes it atomically, then updates the title and `updated` and rewrites `pages.json`.
- **Switching page:**
  1. A sidebar click sets `store.current`.
  2. `updateNSView` sees `loaded != current` and calls `show(new)`.
  3. `show` first runs `flush()` on the old page, then loads the new one.
- **New page:** `create()` inserts at the top, makes it current and saves the index. The editor switches through the same path.
- **Delete:** `delete(id)`:
  1. removes it from `pages`;
  2. deletes its `.rtf`;
  3. creates a fresh page if none are left;
  4. moves `current` to the first page if the deleted page was current;
  5. saves the index.
- **Hide** (`didHide`, including focus loss and Esc) flushes immediately.
- **Quit:** `ScratchpadApp` has no `stop()` override. If the panel is open at quit, edits from the last 0.8 s may not be flushed. In practice, opening the menu-bar menu usually hides the panel first, which flushes, but SIGTERM from `install.sh`'s `pkill` does not.
- **Formatting details:**
  - **Bold, italic** (`toggleTrait`): with no selection, they toggle the trait in `typingAttributes`. With a selection, if every run has the trait it's removed, otherwise it's added to all runs, via `NSFontManager.convert`.
  - **Underline, strikethrough** (`toggleAttribute`): the same all-or-nothing rule, using `NSUnderlineStyle.single`.
  - **Heading:** if the paragraph's font is ≥ 19 pt, it goes back to body 13 pt regular; otherwise it becomes 19 pt bold. This is applied to the whole paragraph and to the typing attributes.
  - **Lists** (`toggleList`): for each paragraph in the selection, it strips an existing `\t<marker>\t` prefix and, unless removing, inserts `\t<marker for item n>\t` and sets the list paragraph style. If the first paragraph already has the same marker format, the list is removed instead. Numbering is baked into the text, so later edits don't renumber.
  - **Triggers** (`applyShortcutAfterSpace`): called from `shouldChangeTextIn` when a single space is typed with no selection. It deletes the prefix and toggles the list or heading. It returns true to swallow the space.

## Integrations
None. These are local files only.

## Logging
Lines are prefixed `scratchpad`, not `pocket`, so `grep "pocket "` misses them; grep `scratchpad`.

- `scratchpad loaded pages=<n>`
- `scratchpad index load failed path= error=`
- `scratchpad index save failed pages= error=`
- `scratchpad page created page=<uuid> total=`
- `scratchpad page deleted page=<uuid> remaining=`
- `scratchpad page file delete failed page= error=`
- `scratchpad page load failed page= error=`
- `scratchpad page save failed page= chars= error=`

Content and titles are never logged.

## Gotchas
- **`POCKET_DATA_DIR` is ignored.** This contradicts `CLAUDE.md` ("every path … then lives there"). A test harness with `POCKET_DATA_DIR` set still reads and writes the real `~/Library/Application Support/Pocket/Scratchpad`. Fix it by deriving `folder` from `PocketData`; see [../data-and-backups.md](../data-and-backups.md).
- **No backups.** Scratchpad isn't in `VaultFile.all`, and README "Your data" doesn't mention it. Deleting a page is permanent.
- **Deleting the open page can leave an orphan RTF** (likely, from reading the code; not reproduced):
  1. `delete` removes the file and changes `current`.
  2. `updateNSView` then calls `show(new)`, which calls `flush()`.
  3. `flush()` still has `loaded == deletedId`, so `save(deletedId, text)` rewrites `<deletedId>.rtf` before its `guard` on the index returns.

  The page stays hidden (it's not in `pages.json`), but its content remains on disk.
- **An unreadable index is overwritten** by a fresh one-page index, as described under Data. Older pages are then only recoverable by hand from the `.rtf` files.
- **Caret position.** `show` uses `view.string.count` (Characters) as an NSRange location (UTF-16). With emoji or composed characters, the caret lands before the end. It's cosmetic.
- **List numbering** is literal text, so it isn't renumbered when lines are inserted or removed.

## How to change it safely
- **Add a format:** add a method on `ScratchTextView` that follows the `shouldChangeText` → mutate → `didChangeText()` pattern, so undo and save both fire, then add a `tool(...)` button.
- **Add a trigger:** add a `case` in `applyShortcutAfterSpace`.
- **Add a page field:** extend `ScratchPage`. Give new fields defaults, or a custom `init(from:)`, so the existing `pages.json` still decodes; otherwise the load fails and the index is overwritten.
- **Move it under `DataVault`** (recommended): derive the path from `PocketData`, load through the vault guard and add a `VaultFile` row. RTF bodies are multiple files, though, so the vault's single-JSON-file model would need extending (an open design question).
- **Testing:** until the path is fixed, don't run the Scratchpad against a harness expecting isolation. Temporarily point `folder` at a scratch directory.

## Open questions / known gaps
- No search, no reordering, no export, no delete confirmation and no trash.
- It's unclear whether the sidebar order (creation, not last-updated) is intended.
