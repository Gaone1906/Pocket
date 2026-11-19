# Terra

Terra (internal id `calorie`) is the calorie tracker, built on 2026-11-19. It works out Pranav's BMR and the daily deficit his weight goal needs, takes meal calories and Apple Watch workout calories, and shows how each day, week and month stands against that goal. It is pastel green (Sage, hue 145) with rounded type: SF Rounded on the Mac (`design: .rounded`), Nunito on the web. Its icon is a mantis built from leaves (`Glyphs.terra`, the mantis face, in the menu bar) and its Mac shortcut is ⌥4 (⌥E until 2026-11-19).

It exists twice: on the Mac (`MisuraModel.swift`, `MisuraApp.swift`) and as the web app at `/Pocket/terra/` (`web/terra/`). Both read and write the same records.

Related: [../cloud-sync.md](../cloud-sync.md) (record kinds), [../web-pages.md](../web-pages.md) (the web app), [../theme.md](../theme.md) (app colours; Terra defaults to Sage), [../data-and-backups.md](../data-and-backups.md) (the vault).

## Data

`$ROOT/calorie.json` through `DataVault` as `calorie` (snapshots in `$ROOT/Backups/calorie/`, git-synced as `calorie.json`, "GitHub has N log …"):

```json
{"plan": {"born": "yyyy-MM-dd", "sex": "male", "heightCm": 0, "activity": 1.2, "startDay": "yyyy-MM-dd", "startKg": 0,
          "goalKg": 0, "goalDay": "yyyy-MM-dd", "pace": "fastest", "floor": 1500, "watchShare": 0.75,
          "eatBack": false, "menuLeft": true, "weighAt": "07:00"},
 "entries": [{"id": "UUID", "day": "yyyy-MM-dd", "kind": "meal", "slot": "lunch", "title": "Dal rice", "kcal": 520, "at": "ISO", "updated": "ISO"}],
 "weights": [{"id": "yyyy-MM-dd", "day": "yyyy-MM-dd", "kg": 82.4, "updated": "ISO"}]}
```

- Every number about Pranav (birth date, height, weights, goal, dates, floor) lives only in the plan. Code has no personal values.
- `kind` is `meal` or `workout`; only meals have a `slot` (`breakfast`, `lunch`, `snack`, `dinner`, guessed from the hour when added).
- A weight's id is its day, so a second weigh-in the same day replaces the first.
- Merging another copy is a union by id where the newer `updated` wins. Sync counts entry and weight ids as "seen".
- Cloud kinds: `calorie.settings` (id `book`, `{plan}`), `calorie.entry`, `calorie.weight`.

## The math

`MisuraMath` (Swift) and `web/terra/plan.js` must give the same numbers.

- **BMR**, Mifflin–St Jeor: `10·kg + 6.25·cm − 5·age + 5` (male) or `− 161` (female). Weight is the latest weigh-in on or before the day, else `startKg`. **Base burn** is BMR × `activity` (1.2 sitting, 1.375 light, 1.55 moderate, 1.725 active); the "BMR" shown in the Week table is this base burn.
- **Daily goal** (the deficit needed): `(startKg − goalKg) × 7700 / days from startDay to goalDay`.
- **Budget** (what he may eat): pace `fastest` uses `floor`; pace `ontime` uses `max(floor, base − daily goal)`. With `eatBack` on, counted workout calories are added to the budget.
- **Workouts** count at `watchShare` (default 75%) of what the Watch says, since Watch active calories run high.
- **Deficit** for a day is `base + workout − eaten`, and only once the day has at least one meal ("logged"). A logged day is **over** when eaten > budget.
- **Week** (Monday first): the goal is daily goal × the days of the week inside the plan; "due" is daily goal × the days already elapsed. "Under the limit" when the week's deficit ≥ due. "Per day left" spreads what is still owed over the days left.
- **Month**: lost weight compares 7-day average weights, from the day before the month (or `startKg`) to the last day so far.
- **Goal ETA**: the average deficit of the logged days in the last 14 (needs 3) projects the remaining kilos; otherwise it is `goalDay`.
- The day rolls over at 4am, like Aqua.

## Design rules (Pranav, from the canvas critique)

- Anything over the daily limit is red; under is green.
- The week badge reads "Under the limit" (green) or "Over the limit" (red).
- Eaten numbers are orange; workout and BMR numbers are green, because they count against what was eaten.
- Week table columns, in order: Day, kg in a box, Eaten, Workout, BMR, Deficit / goal (green when met, red when not). The phone shows Day, kg, Eaten, Deficit / goal.
- Chart columns share one baseline; the dashed line is the budget.
- Keep text to a minimum.

Design canvas: https://claude.ai/artifact/G4JvGyFuyzKR5jwCZbdbRS

## Mac

- **Menu bar**: the mantis face, plus "260 left" (or "+120" in red when over) when "Show kcal left" is on (`menuLeft`).
- **Dropdown** (`MisuraGlance`, 380×560): kcal left against budget, a quick-add field ("Poha 380" is a meal, "Gym -300" a workout), today's entries, and week and month bars. Open Terra opens the window.
- **Window** (`MisuraWindow`, 1120×720, autosave `calorie.board`): a sidebar with Today, Week, Month and Goal cards; Day, Week and Month views; a settings panel (⌘,) with the plan, Watch share, Eat back, Show kcal left, the weigh-in reminder and Backup (Restore…, Show backups). ⌘N adds a meal, ⌘⇧N a workout. Without a plan it shows the setup form.
- **Weigh-in reminder**: `MisuraReminder` schedules a local notification at `weighAt` for the next 7 days (ids prefixed `pocket.misura.`), skipping today once weighed.

## Web

`web/terra/`: Day (week strip, ring, entries, Meal / Workout / Weight buttons), Week, Month and Settings, plus sheets to add or edit a meal or workout and to weigh in (with a 14-day trend). First run asks for the setup link, then the plan.
