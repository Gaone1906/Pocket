# Theme

One theme covers every native Pocket app: Pomodoro (dropdown timer and board window), Schedule (dropdown, board window, editor), To-do, Scratchpad, System Stats, Calculator and the Pocket Settings window. The `DeclareSession` sheet also uses the tokens. Web apps (Gmail, WhatsApp, Slack, Spotify, Outlook, Matinee) and link apps (Preparo) are not themed. The theme is picked only in Pocket Settings → Appearance (`SettingsWindow.swift`, `PocketSettings.shared.show(section:)`, also "Pocket Settings…" in every status item's right-click menu); the Pomodoro and Schedule settings panels show a `ThemeLinkRow` that opens it. The code is in `Sources/Pocket/BoardTheme.swift` (palette, store, helpers) and `Sources/Pocket/Embroidery.swift` (the three embroidered themes, their backdrop and `.boardEdge`). The `Board` token enum lives in `Sources/Pocket/PomodoroBoard.swift`.

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
- **Panels.** The settings panel is 280pt wide, on `Board.theme.panel`. The stats sidebar is 220pt, on `Board.sidebar`. Dividers are 1pt `Board.line` rectangles; embroidered themes dim them to 0.2–0.35 opacity.
- **Motion.** `Board.glide = .smooth(duration: 0.3)`. Theme switches animate with `.easeInOut(duration: 0.15)`.
- **Out of scope.** Web apps and link apps. Calculator keeps its CAT-exam layout; only its colours come from the theme (`CatStyle` proxies the tokens).

## `BoardTheme` (`BoardTheme.swift`)

`struct BoardTheme: Identifiable, Equatable`. Equality compares `id` only.

| Field | Role |
| --- | --- |
| `id`, `name`, `isDark` | Persisted id, display name (swatch tooltip and the THEME label), and light or dark |
| `backdrop` | Window and board background |
| `sidebar` | Stats sidebar (embroidered: fully transparent `fabric.opacity(0)`) |
| `card` | Card fill, exposed as `Board.column` |
| `line` | Hairlines and card edges |
| `ink`, `muted`, `faint` | Text, from primary down to tertiary |
| `accent`, `accentInk` | Accent fill, and accent used as text |
| `shadow` | Shadow color |
| `pill` | Pill and chip fill |
| `swatch`, `swatchEdge`, `swatchRing` | Theme-picker circle fill, its edge, and the selected ring |
| `projectTints: [Color]` | Per-project colors (8 in every theme); indexed through `projectTint(_:)` with a wrapping modulo |
| `metal: [Color]?` | Bronze only. Turns the accents into gradients |
| `embroidery: Embroidery?` | Embroidered themes only |

Derived members:
- `colorScheme` and `appearance` (`.darkAqua` / `.aqua`).
- `accentStyle` and `accentInkStyle`: a solid color, or a `LinearGradient(metal)` when `metal` is set.
- `panel`: `sidebar`, or `#111113 @ 0.96` for embroidered themes.
- `swatchStyle`: an `AngularGradient` of tiger thread, gold and dragon thread for embroidered themes; swatch plus metal for Bronze; otherwise solid.
- `sheen(tint)`: a banded metallic gradient over a project tint, Bronze only.

`Color(hue:saturation:lightness:alpha:)`, which takes HSL with saturation and lightness 0–100, and `Color(hex:alpha:)` are defined here and used app-wide.

`BrushedGrain` is a deterministic `Canvas` of faint horizontal streaks. It is overlaid on the dropdown's focus button (`FlapButton(brushed:)` in `PomodoroApp.swift`) when the theme has `metal`.

## Theme list (`BoardTheme.all`, in picker order; 5 per row)

| # | id | Name | Kind | Recipe |
| --- | --- | --- | --- | --- |
| 0 | `sage` | Sage | pastel, light | hue 145, saturation × 1 (**default**) |
| 1 | `rose` | Rose | pastel | hue 356, × 1 |
| 2 | `butter` | Butter | pastel | hue 46, × 1.15 |
| 3 | `apricot` | Apricot | pastel | hue 24, × 1.05 |
| 4 | `sky` | Sky | pastel | hue 205, × 1 |
| 5 | `lavender` | Lavender | pastel | hue 262, × 0.95 |
| 6 | `blush` | Blush | pastel | hue 328, × 0.9 |
| 7 | `stone` | Stone | pastel | hue 32, × 0.28 |
| 8 | `bronze` | Bronze | dark, metallic | Fixed hex: charcoal `#2B2C30`, accent `#C8925A`, 10-stop `metal` gradient, 8 metallic project tints |
| 9 | `saffron-azure` | Saffron tiger, azure dragon | embroidered, dark | accent `#E0943A`, dragon thread `#4F7FC4` |
| 10 | `gold-vermilion` | Gold tiger, vermilion dragon | embroidered, dark | accent `#E1B23E`, dragon thread `#C8402F` |
| 11 | `white-jade` | White tiger, jade dragon | embroidered, dark | accent `#7FB89A`, tiger thread `#ECE6D8`, dragon thread `#5F9E80` |

`pastel(id, name, hue:, saturation:)` derives every token from one hue through `tone(saturation, lightness)`, with saturation scaled by the factor and capped at 100. For example: backdrop is tone 45/92.5, card 55/96, ink 34/16, accent 48/54. Project tints rotate the hue by `projectOffsets = [0, -32, 34, -64, 66, -98, 100, 180]`; `Board.hueCount` is 8.

`embroidered(id, name, accent:, accentInk:, border:, threads:, embroidery:)`:
- backdrop `BoardTheme.fabric` = `#0C0C0D`;
- card `#141416 @ 0.8`;
- ink `#EFE6D6`;
- `line` = `border`;
- `projectTints` = `threads` (8 hex values).

## `BoardThemeStore`

`final class BoardThemeStore: ObservableObject`, `static let shared`.
- `@Published var theme` persists `theme.id` to UserDefaults **`pomodoro.board.theme`** on change, and logs `pomodoro board theme=<id> previous=<id>`.
- At init, it loads the saved id. An unknown or missing id falls back to `BoardTheme.all[0]` (Sage).
- There is one theme for the whole app, written only by the Appearance gallery in Pocket Settings (`ThemeGallery`, grouped by `BoardTheme.family`: Pastel, Metal, Embroidered).

Who reacts to a change:
- **SwiftUI views** observe `BoardThemeStore.shared` and set `.environment(\.colorScheme, theme.colorScheme)`. `PomodoroView` also uses `.id(theme.id)` to rebuild on a switch.
- **AppKit hosts** subscribe to `$theme`:
  - the Pomodoro and Schedule dropdown `NSHostingView.appearance`;
  - the board windows' `appearance` and `backgroundColor` (`NSColor(theme.backdrop)`).

## `Board` tokens (`PomodoroBoard.swift`, `enum Board`)

These are static computed proxies to `BoardThemeStore.shared.theme`. Use them in views rather than reading the theme directly:
- colors: `theme`, `backdrop`, `sidebar`, `column` (= `card`), `line`, `muted`, `ink`, `faint`, `accent`, `accentInk`, `shadow`;
- styles: `accentStyle`, `accentInkStyle`;
- project colors: `hue(i)` (= `projectTint(i)`) and `hueCount`;
- animation: `glide`.

The same enum also carries Pomodoro formatting helpers (`sessionLabel`, `units`, `duration`, `days`, `dayDate`, `dayTag`); those are documented in [apps/pomodoro.md](apps/pomodoro.md). `Flap` (private, `PomodoroApp.swift`) is the dropdown timer's own token set, derived from the same theme. Embroidered themes override its backdrop gradient and card top with near-black values.

Because the tokens are computed, a view only updates on a theme change if it observes `BoardThemeStore.shared` (or an ancestor rebuilds it).

## `BoardBackdrop` and the embroidered fabric (`Embroidery.swift`)

`BoardBackdrop(theme:)` is the background for the Pomodoro board, the Schedule board and the Schedule dropdown. It renders `theme.backdrop` for plain themes, and `EmbroideredFabric(embroidery:)` for embroidered ones.

`struct Embroidery` (in this worktree) has these fields:
- `tiger`, `dragon`: image names;
- `tigerThread`, `dragonThread`, `gold`: thread colors;
- `waves: [Color]`: 5 rows;
- `tigerFade`, `dragonFade`: image opacity, 0.46–0.58.

`EmbroideredFabric` builds a `ZStack`, back to front, inside a `GeometryReader`. It is clipped, and hit testing is off:
1. `BoardTheme.fabric` flat black.
2. `FabricWeave`: a deterministic `Canvas` of warp and weft threads every 1.7pt, plus random slubs.
3. `EmbroideredMotifs` at 0.42 opacity: a deterministic `Canvas` with a 5-row zig-zag wave band and crests along the bottom, 6 cloud spirals, and 36 French knots. Each stroke goes through `thread(...)`, which draws a drop shadow, a shaded base, a color core, a highlight and stitch dashes.
4. The dragon image, `size = beast`, offset to the upper right (`x: width − beast·0.817, y: −beast·0.067`), focus (0.59, 0.32).
5. The tiger image, offset to the lower left (`x: −beast·0.183, y: height − beast·1.037`), focus (0.42, 0.66).
6. A radial vignette to 50% black.

`beast = min(600, max(360, height · 0.82))`. Each creature is masked by an `EllipticalGradient`, opaque to 0.66 and clear at 1, with end radius 0.58 around its focus. It gets `.saturation(1.05).contrast(1.05)`, then `.opacity(fade)` and `.blendMode(.lighten)`. The lighten blend makes the jpg's black fabric disappear, leaving the stitched animal.

### Fabric images (`Resources/Embroidery`)

The worktree has six 1024×1024 jpgs: `tiger-saffron`, `tiger-gold`, `tiger-white`, `dragon-azure`, `dragon-vermilion` and `dragon-jade`.
- `EmbroideryArt.image(name)` loads `Bundle.main.url(forResource: name, withExtension: "jpg", subdirectory: "Embroidery")` and caches the `NSImage` in a static dictionary.
- A missing image logs `board embroidery art missing name= bundle=` and is skipped; the procedural layers still draw.
- `scripts/install.sh` copies `Resources/Embroidery` into `Pocket.app/Contents/Resources/Embroidery`. It isn't in `Package.swift` resources, so `swift run` never has the art.

### `.boardEdge(_ radius:, color: = Board.line, width: = 1)`

This is a `View` extension in `Embroidery.swift`. Use it as the outline of every card.
- **Plain themes:** a `RoundedRectangle(radius)` stroke of `width`.
- **Embroidered themes ("stitched"):** the outline is inset 5pt. It is a dashed stroke `[6, 4.5]` with round caps, width `width + 0.8`, plus a hard black shadow (0.7, offset 0.5/0.9), so it reads as a running stitch.

Callers pass an accent color for "today" or "now" highlights, and `width: 1.5` for targeted or today states.

## Pending, uncommitted work in the main checkout

`/Users/pranav.yarasi/Desktop/workspace/personal/pocket` (branch `add-matinee`) has uncommitted work that this worktree (`add-schedule`) doesn't have. `BoardTheme.swift` is identical in both.

| Path | State | What it does |
| --- | --- | --- |
| `Sources/Pocket/Embroidery.swift` | modified (+43 / −155 lines overall with the docs) | Replaces the procedural background with a painted fabric image per theme |
| `Resources/Embroidery/fabric-saffron-azure.jpg` | untracked, 2688×1520, ~1.6 MB | Fabric for `saffron-azure` |
| `Resources/Embroidery/fabric-gold-vermilion.jpg` | untracked, 2688×1520, ~1.36 MB | Fabric for `gold-vermilion` |
| `Resources/Embroidery/fabric-white-jade.jpg` | untracked, 2688×1520, ~1.28 MB | Fabric for `white-jade` |
| `CLAUDE.md`, `README.md` | modified | Docs for the above |

Code changes in the pending `Embroidery.swift`:
- `Embroidery` gains `fabric: String` (`"fabric-<theme-id>"`) and **drops `waves`**. Each theme entry is updated to match.
- `FabricWeave` and `EmbroideredMotifs` (waves, clouds, knots, `thread`, `spiral`, `shade`) are **deleted**.
- `EmbroideredFabric` gets new members:
  - `static let dragonFocus` / `tigerFocus`;
  - `fabric(size:)`, which draws the fabric jpg `.aspectRatio(contentMode: .fill)` across the whole view, clipped. Without the image, only flat black shows; there is no procedural fallback any more;
  - `clearing(size:focus:)`, a `BoardTheme.fabric`-coloured square masked by the same halo at 0.92 opacity, placed under each creature so the busy fabric art doesn't show through the lightened animal;
  - `halo(_:)`, the shared `EllipticalGradient` mask.
- New layer order: flat fabric, fabric image, dragon clearing, tiger clearing, dragon, tiger, vignette.

The pending CLAUDE.md edit adds a requirement for new colourways: a 16:9 fabric (stars, starburst, comet, clouds and a wave band on black, with the centre and the tiger and dragon corners left empty), generated on Higgsfield with the saffron fabric as reference. The pending README edit describes "a night sky of stars, a starburst, a comet, clouds and waves".

None of this is committed or pushed. When it lands, update this page: drop the `FabricWeave` / `EmbroideredMotifs` sections and `waves`, and add `fabric`. The art bundle grows by about 4.2 MB.

## How to change it safely

- **Add a pastel theme.** Add one `pastel("<id>", "<Name>", hue:, saturation:)` line to `BoardTheme.all`, and update the README theme list. Ids are persisted, so never rename an existing id: a user on it would silently fall back to Sage.
- **Add an embroidered colourway.**
  - Art: a tiger and a dragon jpg (1024², on flat black; tiger lower left facing right, dragon upper right facing left) in `Resources/Embroidery`. With the pending work, also a 16:9 fabric.
  - Code: a `static let` built with `embroidered(...)` in `Embroidery.swift`, with 8 thread colors, and an entry in `BoardTheme.all`.
  - Run `scripts/install.sh` to see the art. The owner runs that; agents must not.
- **Add a token.** Add the field to `BoardTheme`. Fill it in `pastel`, `bronze` and `embroidered`. Add a `Board.<name>` proxy.
- **Theme a new surface.**
  - Observe `BoardThemeStore.shared`.
  - Set `.environment(\.colorScheme, …)`.
  - Use `BoardBackdrop` for full-window backgrounds.
  - For a panel, return `ThemedHostingView(rootView:)` from `makeContent()`; it keeps `appearance` in step with the theme. For a window, set `appearance` and `backgroundColor` and subscribe to `$theme`, as `PocketSettings`, `ScheduleBoardWindow` and the Pomodoro board do.
- **Gate macOS 26 APIs** (`glassEffect`) with `#available(macOS 26, *)`, and keep the `.ultraThinMaterial` fallback.

## Logging

- `pocket theme changed theme=<id> previous=<id>`, from `BoardThemeStore`.
- `pocket settings opened|refocused|closed …` and `pocket settings section=<id> previous=<id>`, from `PocketSettings`.
- `board embroidery art missing name=<image> bundle=<path>`, from `EmbroideryArt`. It is logged on every miss, because misses aren't cached.

## Gotchas

- **Under `swift run`, embroidered themes show no animals,** and the missing-art line is logged on every render. With the pending change, the whole fabric goes flat black as well.
- **The theme key is called `pomodoro.board.theme`** even though Schedule shares it. Keep the name for compatibility.
- **The embroidered `sidebar` is transparent.** Anything filled with `Board.sidebar` shows the fabric through it; use `theme.panel` for opaque panels.
- **`EmbroideryArt.cache` is unbounded and never evicted.** That is fine for six (or nine) images.
- **The canvases are deterministic.** They use fixed LCG seeds, so the pattern is stable across redraws; keep the seeds when editing.

## Open questions

- Whether the main-checkout fabric work will merge before or after `add-schedule` hasn't been decided (see [handoff.md](handoff.md)).
- The two section-title and Backup-section duplicates (Pomodoro and Schedule) could be shared views. This hasn't been done.
