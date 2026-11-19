# Theme

Aqua, Ignis and Ventus have their own colour (see [App colours](#app-colours)); the Pocket theme covers the rest. One theme covers every other native Pocket app: Ignis (dropdown timer and board window), Schedule (dropdown, board window, editor), To-do, Scratchpad, System Stats, Calculator and the Pocket Settings window. The `DeclareSession` sheet also uses the tokens. Web apps (Gmail, WhatsApp, Slack, Spotify, Outlook, Matinee) and link apps (Preparo) are not themed. The theme is picked only in Pocket Settings → Appearance (`SettingsWindow.swift`, `PocketSettings.shared.show(section:)`, also "Pocket Settings…" in every status item's right-click menu); the Ignis and Schedule settings panels show a `ThemeLinkRow` that opens it. The code is in `Sources/Pocket/BoardTheme.swift` (palette, store, helpers, `BoardBackdrop`, `.boardEdge`). The `Board` token enum lives in `Sources/Pocket/PomodoroBoard.swift`.

Related: [apps/pomodoro.md](apps/pomodoro.md), [apps/schedule.md](apps/schedule.md), [architecture.md](architecture.md), [data-and-backups.md](data-and-backups.md), [operations.md](operations.md) (install and bundling).

## Design language

The style is clean, minimal and elegant. Keep new UI inside these rules:

- **Cards.** Use `RoundedRectangle(cornerRadius: 16).fill(Board.column)` plus `.boardEdge(16)`. Smaller radii:
  - 14 for day cells and editor cards;
  - 12 for small controls;
  - 18 for floating sheets and overlays (`DeclareSession`, the Schedule editor overlay);
  - 8 for buttons (`FlapButton`).

  Shadows use `Board.shadow`.
- **Section titles.** These are small caps by convention, not via `Font.smallCaps()`: the string literal is already uppercase ("TODAY", "ALL TIME", "TIMER", "THEME", "BACKUP"), set with `.font(.system(size: 10, weight: .semibold)).tracking(1.6).foregroundStyle(Board.muted)`. Two private copies exist: `BoardSectionTitle` (`PomodoroBoard.swift`) and `ScheduleSectionTitle` (`ScheduleBoard.swift`). Copy the pattern; don't invent a new title style.
- **Glass.** Floating controls (the settings button, the mode toggle) use `if #available(macOS 26, *) { view.glassEffect(.regular.interactive(), in: Circle()/Capsule()) } else { view.background(Shape().fill(.ultraThinMaterial)).overlay(Shape().strokeBorder(Board.line, lineWidth: 1)) }`. Examples are `PomodoroBoard.swift` (settings button, `BoardModeToggle`) and `ScheduleBoard.swift` (around lines 245 and 371). The package targets macOS 14, so the fallback is mandatory.
- **Text.** Use the system font only. Ink is `Board.ink`, secondary text `Board.muted`, tertiary `Board.faint`, and emphasis `Board.accentInkStyle`. Numbers in stats are 30pt bold.
- **Panels.** The settings panel is 280pt wide, on `Board.theme.panel`. The stats sidebar is 220pt, on `Board.sidebar`. Dividers are 1pt `Board.line` rectangles.
- **Motion.** `Board.glide = .smooth(duration: 0.3)`. Theme switches animate with `.easeInOut(duration: 0.15)`.
- **Out of scope.** Web apps and link apps. Calculator keeps its CAT-exam layout; only its colours come from the theme (`CatStyle` proxies the tokens).

## `BoardTheme` (`BoardTheme.swift`)

`struct BoardTheme: Identifiable, Equatable`. Equality compares `id` only.

| Field | Role |
| --- | --- |
| `id`, `name`, `isDark` | Persisted id, display name (swatch tooltip and the THEME label), and light or dark |
| `backdrop` | Window and board background |
| `sidebar` | Stats sidebar |
| `card` | Card fill, exposed as `Board.column` |
| `line` | Hairlines and card edges |
| `ink`, `muted`, `faint` | Text, from primary down to tertiary |
| `accent`, `accentInk` | Accent fill, and accent used as text |
| `shadow` | Shadow color |
| `pill` | Pill and chip fill |
| `swatch`, `swatchEdge`, `swatchRing` | Theme-picker circle fill, its edge, and the selected ring |
| `projectTints: [Color]` | Per-project colors (8 in every theme); indexed through `projectTint(_:)` with a wrapping modulo |

Derived members:
- `colorScheme` and `appearance` (`.darkAqua` / `.aqua`).
- `accentStyle` and `accentInkStyle`: the accent colours as shape styles.
- `panel`: `sidebar`.
- `swatchStyle`: solid for light themes; a ground-to-glow gradient for dark ones.
- `family`: "Light" or "Dark", the groups in the Appearance gallery.

`Color(hue:saturation:lightness:alpha:)`, which takes HSL with saturation and lightness 0–100, and `Color(hex:alpha:)` are defined here and used app-wide.


## Theme list (`BoardTheme.all`, in picker order)

Light, from `pastel(id, name, hue:, saturation:)`: `sage` (default), `rose`, `butter`, `apricot`, `sky`, `lavender`, `blush`, `stone`, `ember` (hue 354 × 1.55, Ignis's default), `flint` (hue 30 × 0.62, Ventus's default).

Dark, from `dusk(id, name, ground:, glow:, depth:)`: a deep background tinted with the `ground` hue and pastel text, accents and project tints from the `glow` hue.

| id | Name | ground | glow |
| --- | --- | --- | --- |
| `moonlit-sage` | Moonlit Sage | 160 | 140 |
| `harbour` | Harbour | 218 | 24 |
| `aurora` | Aurora | 268 | 158 |
| `nocturne` | Nocturne | 256 | 272 |
| `candlelight` | Candlelight | 336 | 44 |
| `mint-cocoa` | Mint Cocoa | 28 (depth 0.7) | 156 |
| `coral-reef` | Coral Reef | 178 | 12 |
| `plum-blossom` | Plum Blossom | 302 | 334 |

`dusk` tones (saturation, lightness): backdrop ground 46/11, sidebar 48/8.5, card 36/15.5, line 28/23, muted 18/70, faint 14/48; ink glow 40/93, accent 62/76, accentInk 70/81; project tints glow + `projectOffsets` at 55/74. On dark themes, text over an accent fill uses `backdrop`, not white.

Bronze and the three embroidered themes were removed on 2026-11-19 at the owner's request; a saved id from them falls back to Sage.

## App colours

Aqua (`schedule`), Ignis (`pomodoro`), Ventus (`runner`) and Terra (`calorie`) open in their web app's default theme and can each be
given any theme from `BoardTheme.all`. The Pocket theme still colours the dropdown, Settings and every other app.

| App | Default | Web counterpart |
| --- | --- | --- |
| Aqua | `sky` | `/Pocket/aqua/` |
| Ignis | `ember` | `/Pocket/ignis/` |
| Ventus | `flint` | `/Pocket/ventus/` |
| Terra | `sage` | `/Pocket/terra/` |

The Hair web app (`/Pocket/`) defaults to Sage, but it has no Mac app of its own: Hair lives inside Aqua.

- **Store.** `AppThemeStore.shared` (`BoardTheme.swift`). `AppThemeStore.apps` lists each themed app (`ThemedApp`: id,
  name, symbol, `fallback` theme id). `theme(for:)` gives the app's theme, `set(_:for:)` changes it, `publisher(for:)`
  emits on change (for AppKit hosts), `isDefault(_:)` says whether the app still uses its fallback. A pick is saved to
  UserDefaults `app.theme.<id>` and removed again when it equals the fallback, so changing a default later reaches
  everyone who never picked. Unknown saved ids fall back to the default.
- **Tokens.** `protocol BoardScope { static var theme }` gives every token (`ink`, `muted`, `column`, `line`, `accent`,
  `accentInkStyle`, `hue(_:)`, `glide`, …) through an extension. `Board` (Pocket theme), `OrarioBoard` and
  `AureliusBoard` conform; Aqua's files use `OrarioBoard.*`, Ignis's files (including `DeclareSession` and `Flap`)
  use `AureliusBoard.*`. Ventus adds `KairosBoard` reading `theme(for: "runner")`. `Board` keeps the Ignis formatting
  helpers.
- **Shared views.** `.appTheme(theme)` sets `\.boardTheme`, `\.colorScheme` and `.fontDesign(.rounded)` at an app's root, so Aqua, Ignis, Ventus and Terra all use SF Rounded like Terra (explicit `design: .serif` in Ventus's journal books stays); `.boardEdge` without a
  colour reads `\.boardTheme`, falling back to the Pocket theme. Panels use `ThemedHostingView(rootView:app:)`, and the
  board windows subscribe to `AppThemeStore.shared.publisher(for:)`.
- **Icons.** `AppIcon.render` tints a themed app's menu-bar glyph with `iconTint(for:)`, a dynamic colour: the theme's
  `swatchRing` on a light menu bar and `swatchEdge` on a dark one (for dark themes, `swatchEdge` and `accent`). Dropdown
  tiles use `iconColor(for:onDark:)` against the Pocket theme. Ignis's running timer uses the same colour in focus
  and silver on breaks. `set(_:for:)` calls the app's `changed()` so the menu bar redraws at once.
- **Settings.** Pocket Settings → Appearance → APP COLOURS has one row per app with every theme as a swatch and a "Use
  <default>" button once changed. The THEME row in the Aqua and Ignis settings panels shows the app's colour and
  opens that section.
- **Log.** `pocket app theme changed app=<id> theme=<id> previous=<id> default=<id>`.

To give another app its own colour: add a `ThemedApp` row, a `BoardScope` enum, switch its files to that enum, wrap the
root in `.appTheme(...)`, and host it with `ThemedHostingView(rootView:app:)`.

## `BoardThemeStore`

`final class BoardThemeStore: ObservableObject`, `static let shared`.
- `@Published var theme` persists `theme.id` to UserDefaults **`pomodoro.board.theme`** on change, and logs `pomodoro board theme=<id> previous=<id>`.
- At init, it loads the saved id. An unknown or missing id falls back to `BoardTheme.all[0]` (Sage).
- There is one theme for the whole app, written only by the Appearance gallery in Pocket Settings (`ThemeGallery`, grouped by `BoardTheme.family`: Light, Dark).

Who reacts to a change:
- **SwiftUI views** observe `BoardThemeStore.shared` and set `.environment(\.colorScheme, theme.colorScheme)`. `PomodoroView` also uses `.id(theme.id)` to rebuild on a switch.
- **AppKit hosts** subscribe to `$theme`:
  - the Ignis and Schedule dropdown `NSHostingView.appearance`;
  - the board windows' `appearance` and `backgroundColor` (`NSColor(theme.backdrop)`).

## `Board` tokens (`PomodoroBoard.swift`, `enum Board`)

These are static computed proxies to `BoardThemeStore.shared.theme`. Use them in views rather than reading the theme directly:
- colors: `theme`, `backdrop`, `sidebar`, `column` (= `card`), `line`, `muted`, `ink`, `faint`, `accent`, `accentInk`, `shadow`;
- styles: `accentStyle`, `accentInkStyle`;
- project colors: `hue(i)` (= `projectTint(i)`) and `hueCount`;
- animation: `glide`.

The same enum also carries Ignis formatting helpers (`sessionLabel`, `units`, `duration`, `days`, `dayDate`, `dayTag`); those are documented in [apps/pomodoro.md](apps/pomodoro.md). `Flap` (private, `PomodoroApp.swift`) is the dropdown timer's own token set, derived from the same theme.

Because the tokens are computed, a view only updates on a theme change if it observes `BoardThemeStore.shared` (or an ancestor rebuilds it).

## `BoardBackdrop` and `.boardEdge`

Both are in `BoardTheme.swift`. `BoardBackdrop(theme:)` fills with `theme.backdrop`. `.boardEdge(radius, color:, width:)` strokes a rounded rectangle, by default in `Board.line`.

## How to change it safely

- **Add a pastel theme.** Add one `pastel("<id>", "<Name>", hue:, saturation:)` line to `BoardTheme.all`, and update the README theme list. Ids are persisted, so never rename an existing id: a user on it would silently fall back to Sage.
- **Add a dark theme.** Add one `dusk("<id>", "<Name>", ground:, glow:)` line to `BoardTheme.all`. Pick a `glow` far enough from the other glows that the swatch reads differently.
- **Add a token.** Add the field to `BoardTheme`. Fill it in `pastel` and `dusk`. Add a `Board.<name>` proxy.
- **Theme a new surface.**
  - Observe `BoardThemeStore.shared`.
  - Set `.environment(\.colorScheme, …)`.
  - Use `BoardBackdrop` for full-window backgrounds.
  - For a panel, return `ThemedHostingView(rootView:)` from `makeContent()`; it keeps `appearance` in step with the theme. For a window, set `appearance` and `backgroundColor` and subscribe to `$theme`, as `PocketSettings`, `ScheduleBoardWindow` and the Ignis board do.
- **Gate macOS 26 APIs** (`glassEffect`) with `#available(macOS 26, *)`, and keep the `.ultraThinMaterial` fallback.

## Logging

- `pocket theme changed theme=<id> previous=<id>`, from `BoardThemeStore`.
- `pocket settings opened|refocused|closed …` and `pocket settings section=<id> previous=<id>`, from `PocketSettings`.

## Gotchas

- **The theme key is called `pomodoro.board.theme`** even though Schedule shares it. Keep the name for compatibility.
- **The canvases are deterministic.** They use fixed LCG seeds, so the pattern is stable across redraws; keep the seeds when editing.

## Open questions

- The two section-title and Backup-section duplicates (Ignis and Schedule) could be shared views. This hasn't been done.
