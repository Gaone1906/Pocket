# Calculator

## What it is
A basic calculator modelled on the **CAT exam's on-screen calculator**: navy title bar, memory row, immediate execution, no operator precedence. It was a scientific calculator before; commit `21d165b` replaced that.

- **Catalog:** `id: "calculator"`, symbol `plusminus.circle`, shortcut ⌥C (`kVK_ANSI_C`). It has no glyph and no badge.
- **Panel:** fixed 280×307 (`resizable = false`), and always light appearance (`hosting.appearance = .aqua` plus `.environment(\.colorScheme, .light)`).
- **Layout:**
  - a title bar "Calculator" with a ✕ that hides the panel (`hide(reason: "close button")`);
  - a display with a small expression line (`"<acc> <op>"`, or "M" when memory ≠ 0) and the current value;
  - a 5-column key grid.

  | Row | Keys |
  | --- | --- |
  | Memory | MC MR MS M+ M- |
  | Edit | ← CE C ± √ |
  | | 7 8 9 / % |
  | | 4 5 6 * 1/x |
  | | 1 2 3 - |
  | | 0 (double width) . + |
  | Tall | = |

- The README says "Type or tap a calculation and see the answer as you go". In practice, results appear as each operator or `=` is pressed; there's no precedence (`2 + 3 * 4` gives 20).

## Files
All in `Sources/Pocket/CalculatorApp.swift`.

| Symbol | Role |
| --- | --- |
| `CatCalculator` (`ObservableObject`) | The engine. Published: `current` (display string), `accumulator: Double?`, `operation: String?`, `memory: Double`. Private: `fresh` (the next digit starts a new number). Methods: `press(_ key: String)`, `copy()`, `static format(_:)`, `applyPending()`, `expression` |
| `CatStyle` | Colour and size constants (navy `#13305A`, blue `#1F63C6`, key height 31, gap 5) |
| `CatKey` | The key button, with a hover tint. `=` is solid blue |
| `CalcView` | Layout, keyboard handling (`onKeyPress`) and focus |
| `CalculatorApp` | A `PocketApp` subclass. It only sets the size, `resizable = false` and the content. There are no `start`, `stop` or `didShow` overrides |

## Data
None. The value, accumulator and **memory** live in memory only and reset when Pocket quits. There are no UserDefaults keys beyond the shared layout and shortcut ones, and nothing goes through `DataVault`.

## Flows (engine semantics)
- **Digits:** they replace the display if `fresh` or the display is "0"; otherwise they append. `.` gives `0.` when fresh, and is ignored if a dot already exists.
- **`←`** deletes the last character, but only while typing (`!fresh`). **`CE`** clears the entry. **`C`** clears everything except memory.
- **`±`, `√`, `1/x`** act on the current value. `√` and `1/x` set `fresh`. `±` leaves `fresh` unchanged, so mid-entry typing keeps appending.
- **`%`:**
  - with a pending accumulator, `acc * x / 100`, so `200 + 10 %` shows 20, and `=` then gives 220;
  - otherwise `x / 100`.
- **`+ - * /`:**
  1. If a number was typed, or there's no accumulator, the pending operation is applied first (a chain).
  2. The operator is stored, and the display shows the accumulator.
  3. Pressing a second operator in a row just swaps the operator.
- **`=`** applies the pending operation, then clears the accumulator and operator. Repeated `=` does **not** repeat the last operation.
- **Division by 0** gives `.nan`, and `format` shows "Error" for any non-finite value.
- **`format`:**
  - it rounds to 1e-10;
  - integers below 1e15 print without a decimal point;
  - everything else uses Swift's `String(Double)`, which can give exponent notation such as `1e+20`.
- **`MS`** stores, **`M+`/`M-`** add or subtract, **`MR`** recalls (and sets fresh), **`MC`** clears.
- **Keyboard** (`CalcView.key(for:)`; the view is focusable and focused on appear):
  - digits, `. + - * / % =` map to themselves;
  - `x`/`X` gives `*`, `,` gives `.`, `c`/`C` gives C, `r`/`R` gives 1/x, `@` gives √;
  - Return gives `=`, Delete gives `←`, Forward-delete gives CE;
  - ⌘C copies `current` to the pasteboard, then returns `.ignored`, so the Edit menu's Copy may also fire;
  - Esc isn't handled here, so it falls through to `Panel.cancelOperation`, which hides the panel.
- Right-clicking the display offers "Copy".

## Integrations
None (only `NSPasteboard`).

## Logging
None. The calculator has no `note(...)` lines; it has no failure modes or boundaries worth logging. Panel shown and hidden lines come from `PocketApp` (`pocket shown app=calculator …`).

## Gotchas
- **No precedence**, by design, to match the CAT calculator. Don't "fix" it.
- **Large results** can show exponent notation; `minimumScaleFactor(0.5)` shrinks long values.
- **Reopening keeps the state.** The panel is created once and the content persists, so the last value is still there.
- **History** (`git log -- Sources/Pocket/CalculatorApp.swift`):
  - `ac9ebb5` added the calculator;
  - `9801d9f` added roots, powers, logs, trig and Ans;
  - `09abdd0` added an LCD and shift keys;
  - `21d165b` rewrote it to the CAT layout (−430 lines).

  The scientific features no longer exist.

## How to change it safely
- **Add a key:** add its label to `topRows` (or to the bottom block), and add a `case` in `CatCalculator.press`. Optionally map a keyboard character in `key(for:)`. The panel height (307) is tuned to the current rows, so adding a row means changing `defaultSize`.
- **Persist memory:** write `memory` to a UserDefaults key, e.g. `calculator.memory`, in `didSet`, and read it in `init`. It's small and not worth `DataVault`.
- `CatCalculator` is UI-free, so it can be unit-tested by calling `press` with key strings.

## Open questions / known gaps
- There's no repeat-equals and no history tape.
- The README wording ("see the answer as you go") oversells it slightly; the answer appears per operator, not as you type.
