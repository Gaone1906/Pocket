# Luna

Luna (internal id `sleep`) is the sleep app, built on 2026-11-21. It shows each night's sleep from Apple Health and comments on the night, the week and the month: what went well and what to fix. It is lavender (hue 258, theme `lavender`) with rounded type: SF Rounded on the Mac, Nunito on the web. Its icon is a flat wolf howling beside a crescent moon and three stars (picked 2026-11-21, replacing the busier wolf on a rock); the menu bar shows the howling head (`Glyphs.luna`). Mac shortcut ⌥5.

It exists twice: on the Mac (`LunaModel.swift`, `LunaApp.swift`) and as the web app at `/Pocket/luna/` (`web/luna/`). Both read the same records. `LunaMath` (Swift) and `web/luna/sleep.js` must give the same nights, scores and comments.

Mockups: `/mnt/project-files/luna/mockups/` in the project files (`luna.html` is the source; `w1`–`w7` web, `m1`–`m6` Mac).

Related: [../cloud-sync.md](../cloud-sync.md), [../web-pages.md](../web-pages.md), [misura.md](misura.md) (Terra, the closest sibling).

## Where the data comes from

Health data exists only on the iPhone. An iOS Shortcut, **Luna Sync**, runs each morning on an automation (alarm stopped, or first unlock), because Health is locked while the phone is locked:

1. Finds the Sleep Analysis samples that start in the last 14 days.
2. Sends them as `Value|Start|End|Source` lines to `POST /rest/v1/rpc/luna_ingest` (`cloud/schema.sql`), which upserts one `sleep.sample` per line. Rows are idempotent, so re-sending 14 days each morning is harmless and fills missed mornings.

The Shortcut's build steps are in [luna-shortcut.md](luna-shortcut.md).

The web app's sync button opens `shortcuts://x-callback-url/run-shortcut?name=Luna%20Sync&x-success=<this page>#synced`, then pulls when the page comes back. The Mac cannot read Health; its button only runs a cloud sync.

## Records

| kind | id | data |
| --- | --- | --- |
| `sleep.sample` | `<v>\|<s>\|<source>` (opaque) | `{s, e, v, q?}`: start and end as ISO 8601 with offset; `v` is the Health value; `q` is the number for `HR` (bpm) and `HRV` (ms) |
| `sleep.settings` | `book` | `{bed: "23:00", wake: "06:30", hours: 8, deep: 15, rem: 20, tolerance: 20, updated}` |

**Normalising `v`.** The Shortcut writes Health's own labels (`In Bed`, `Asleep Unspecified`, `Asleep Core`, `Asleep Deep`, `Asleep REM`, `Awake`), and `q` may be a number or a string such as `54 count/min`. Readers map `v`, case-insensitively and in this order: contains `deep` → Deep, `rem` → REM, `core` → Core, `awake` → Awake, `bed` → InBed, `hrv` or `variability` → HRV, `hr` or `heart` → HR, anything else → Asleep. `q` is the first number in the value.

The settings record is seeded in the database. Every target lives there, never in code; when a field is missing, the apps fall back to the values above. Settings can be changed on both the Mac and the web. Samples are written only by the Shortcut.

On the Mac they are kept in `$ROOT/sleep.json` through `DataVault` as `sleep`, `{"samples": [...], "settings": {...}}`, synced by a `CloudDocument` row (kinds `sleep.sample` and `sleep.settings`), with "GitHub has N samples …". Merge is a union by id; for settings the newer `updated` wins.

## Nights (the shared math)

All times are in the device's local time zone.

1. **Stage samples** are those with `v` in `InBed`, `Asleep`, `Core`, `Deep`, `REM` and `Awake`. Sort them by start. A sample joins the current cluster when it starts no later than 90 minutes after the cluster's latest end; otherwise it starts a new cluster.
2. **Minutes.** For every whole minute from the cluster's first start to its last end, the stage is the highest-priority sample covering it: `Deep` > `REM` > `Core` = `Asleep` > `Awake` > `InBed`. `Asleep` counts as Core, and a minute covered only by `InBed` (or nothing) counts as Awake. Consecutive minutes of the same stage merge into segments, giving the hypnogram.
3. **Night** values: `bed` is the cluster's first start, `wake` is its last end, and `deep`, `core`, `rem` and `awake` are minute counts. `asleep = deep + core + rem` and `inBed = wake − bed` in minutes.
4. A cluster with `asleep` under 60 is dropped. A night's **key** is the local date of `wake` (`yyyy-MM-dd`), so last night is today's date. When two clusters share a key, the one with more `asleep` wins.
5. `hr` is the mean `q` of `HR` samples that start inside `[bed, wake]`, rounded; `hrv` is the same for `HRV`. Either is null when there are no samples.

**Clock deltas.** `bedDelta` is the minutes from the target bed time to `bed`, wrapped into −720…720, so 11:18 pm against 23:00 is +18 and 10:40 pm is −20. `wakeDelta` is the same for `wake` against the target wake.

**Score** (0–100, rounded):
- 40 × min(asleep / (hours × 60), 1)
- 20 × min(deepPct / deep, 1), where deepPct = deep / asleep × 100
- 20 × min(remPct / rem, 1)
- 10 × max(0, 1 − |bedDelta| / 90)
- 10 × asleep / inBed

**Score colour**: 80 and above is good (accent), 70 to 79 is fair (REM lavender), under 70 is poor (peach).

**Formatting**: durations `7h 32m` (minutes zero-padded); clock times `11:18 pm`; percentages are whole numbers.

## Comments

Each rule gives either an **ok** (✓, green) or a **fix** (↑, orange) line, or nothing. Show oks first, then fixes. Night and Week show at most 3 lines; keep every fix (up to 2) and fill the rest with oks in rule order. Month shows at most 2. `T` is a target time formatted as above (`11:00`, `6:30`, dropping am/pm), and `tol` is `tolerance`.

Night, in rule order:
1. Duration: asleep ≥ hours × 60 − 30 gives ok `"{asleep} asleep"`; otherwise fix `"{asleep}, under {hours}h"`.
2. Deep: deepPct ≥ deep gives ok `"Deep {deep}, above {deep}%"`; otherwise fix `"Deep {deepPct}%, under {deep}%"`.
3. REM: remPct ≥ rem gives ok `"REM {rem}, above {rem}%"`; otherwise fix `"REM {remPct}%, under {rem}%"`.
4. Bed: |bedDelta| ≤ tol gives ok `"In bed by {bed}"`; bedDelta > tol gives fix `"Bed {bedDelta} min after {T}"`; bedDelta < −tol gives ok `"Bed {−bedDelta} min early"`.
5. Wake: |wakeDelta| ≤ tol gives ok `"Woke within {tol} min of {T}"`; wakeDelta > tol gives fix `"Woke {wakeDelta} min after {T}"`; wakeDelta < −tol gives nothing.

Week (Monday to Sunday, nights keyed by wake date):
1. `n` nights of `m` have asleep ≥ (hours − 1) × 60. With n / m ≥ 0.7 it is ok `"{n} of {m} nights over {hours−1}h"`; otherwise fix with the same text.
2. The night with the largest bedDelta, when it is over 60, gives fix `"{Wed} bed {1:36 am}"`.
3. The average asleep against the previous week's: +10 or more gives ok `"{N}m more than last week"`; −10 or less gives fix `"{N}m less than last week"`.
4. The average hr against the previous week's: down by 1 or more gives ok `"Resting heart down {n}"`; up by 2 or more gives fix `"Resting heart up {n}"`.

Month:
1. The average deep minutes against the previous month's: +5 or more gives ok `"Deep up {n} min vs {October}"`; −5 or less gives fix `"Deep down {n} min vs {October}"`.
2. The mean bedDelta of Saturday and Sunday nights (keys), against the mean bedDelta of the other nights: 30 or more later gives fix `"Weekends {n} min later"`.
3. The bedtime spread (population standard deviation of bedDelta): 30 or less gives ok `"Bedtime within ±{n}m"`; otherwise fix `"Bedtime varies ±{n}m"`.
4. The average asleep: at least hours × 60 − 30 gives ok `"{avg} average"`; otherwise fix `"{avg} average, under {hours}h"`.

## Stats

- **Week**: average asleep; average score; bedtime `±{spread}m`; `{n}/{m}` over hours − 1; a chip with the change in average asleep against the previous week (`+22m`, green when up, orange when down, hidden with no previous week); stage totals averaged per night; hr per night.
- **Month**: average asleep, bedtime spread, average score; a calendar with each night coloured by score; asleep hours per night as a line, against a band from hours − 0.5 to hours + 1 and a dashed line at hours; stage averages.

## Screens

Web (`web/luna/`, Terra's shell: icon tile, "Luna", round sync and gear buttons, a Night / Week / Month segmented control):
- **Connect**: the icon, "Luna", a setup-link field and Connect. It connects without asking when the browser already holds a link under `pocket.cloud.v1`, `orario.cloud.v1`, `runner.cloud.v1`, `misura.cloud.v1` or `aurelius.cloud.v1`.
- **Night**: a week strip with a dot coloured by score per night, a ring with the score and asleep time, Bed, Wake, Heart and HRV, the hypnogram (lanes Awake, REM, Core, Deep, and hour ticks), a stage bar with the four totals, and comments. A night with no data shows a dashed moon and a Sync button.
- **Back from the Shortcut**: a dark toast at the bottom, `✓ 2 nights` (nights that are new since the button was pressed), or `✓ Up to date`.
- **Week**: the range with arrows, the average and chip, the sleep-window chart (a capsule per night from bed to wake, coloured by score, with dashed lines at the target times, and a dashed outline for nights to come), the stage bar and comments.
- **Month**: the month with arrows, the calendar, three stats, the line and comments.
- **Settings**: Bed, Wake, Sleep, Deep and REM (written to `sleep.settings`), Luna Sync (opens the Shortcut), Synced (last pull time), Download a copy and Disconnect.

Mac:
- **Menu bar**: the wolf head (`Glyphs.luna`).
- **Dropdown**: Luna with refresh and open-window buttons, the ring card (score, asleep, Bed, Wake, Heart, HRV), the mini hypnogram with its stage bar, the week's nights as bars, and two comments.
- **Window**: a sidebar with Night, Week and Month, a This week card (avg, score, bedtime, over 7h), the targets, and the last sync time; round refresh and gear buttons at the top right. Night has pills for the last six nights, the ring card, the hypnogram with the heart-rate line, the stage bar, and comments in a row. Week and Month follow the web screens with Stages and Heart cards on the right.
- **Settings panel** (gear): Targets (editable), Sync (last sync, sample count, Refresh) and Backup.
- **Pocket Settings**: Luna has a row in App colours (default Lavender) and in Shortcuts (⌥5).
