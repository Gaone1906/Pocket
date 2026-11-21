# Zenda

Zenda (app id `zenda`) is the mindfulness app, built on 2026-11-21 by splitting the mindfulness side out of Ventus; Ventus keeps fitness. Its icon is the ink-swirl panda (yin-yang spots, tail curling into ink); the menu bar shows glyph G1, an ensō with an S-curve and two dots. Mac shortcut ⌥6.

It exists twice: on the Mac (`Zenda*.swift`) and as the web app at `/Pocket/zenda/` (`web/zenda/`). Both read and write the same records. Mockups: the "Zenda mockups" Design canvas (Desktop and Web pages).

Related: [kairos.md](kairos.md) (the engine and the `run` types), [schedule.md](schedule.md) (Aqua, where routines live), [../cloud-sync.md](../cloud-sync.md), [../web-pages.md](../web-pages.md).

## Which routines are Zenda's

A routine belongs to Zenda when its steps (weekly `plan` and `dated`) include a mindfulness step (`box`, `say`, `write`, or `timed` with `reads` or `quiet`) and no fitness step (`moves`, `intervals`, `rounds`, `log`). `ZendaRoutines.owns` on the Mac and `isMindful` in `web/ventus/plan.js` implement the rule; `KairosSession.all`, `KairosStats.all` and `web/ventus/routines.js` skip those routines, so Ventus lists only fitness. No routine name is hard-coded.

## Engine

- Sessions are the Aqua routine's morning and night steps, run through the Ventus engine: `KairosPlan` beats and a second runner, `KairosRunner.zenda` (UserDefaults `zenda.run`), so a Zenda session never shows in Ventus's window or menu bar. The web imports `../ventus/plan.js` (listed in Zenda's `sw.js` shell) and keeps run state in `zenda.run.v1`.
- Finishing a step ticks Aqua exactly like Ventus (`ScheduleStore.shared.set`, `schedule.check`).
- Start launches one-off sessions of a single step (`KairosRunState.adhoc`); they journal but never tick Aqua. Web one-off journal ids are `zenda|day|adhoc|<stepId>`.

## Projects

| kind | id | data |
| --- | --- | --- |
| `zenda.project` | UUID | `{id, name, goal, start, end, routine, days, updated}`: dates `yyyy-MM-dd`, `routine` a `schedule.routine` id, `days` ISO weekdays (1 = Mon) |

On the Mac: `$ROOT/zenda.json` (`{"projects": [...]}`) through `DataVault` as `zenda` (git noun "project"), synced by a `CloudDocument` row. Merge is a union by id, newer `updated` wins. Added and edited in Scheduled on both the Mac and the web (the web can also delete). Several projects may share one routine. A project applies on a day inside start…end whose weekday is in `days`; day n = days since start + 1. Pranav's three projects (RBI, Fit, Crown, all on the Mindfulness routine from Mon 23 Nov 2026) were added as data, never in code.

## Journal

`runner.entry`, the same records as Ventus. Books: Gratitude, Wins, Scripts, Actions, Reviews, Notes (tags `gratitude`, `win`, `script`, `action`, `review`, `note`). Ventus's `project`, `workout` and `run` entries and template entries are ignored.

## Screens

Today (morning and night cards, Start, week dot strip, project chips with day n), Scheduled (project pill, goal, date range with progress, week stepper, day strip, the day's steps), Start (Box breathing 2/4/8/12, Visualize and Affirm with project and minute chips, Body scan 5/10/20, journal books), sessions (box breathing square with the ball, visualize read-along over the ensō, affirm with Said it and repeat dots, journal page with Save ⌘↩), Review (W/M/All, streak, sessions done/planned, hours present, entries, heatmap, adherence bars, minutes per day, book shelf) and the Book view (two-page spread on the Mac, one page on the web).

- Mac: no dropdown; the menu-bar item or ⌥6 opens a 1100×720 window with a left rail (logo, Today, Scheduled, Start, Review, gear). Serif design for headings and read-along text, SF Rounded elsewhere. Logo is `ZendaLogo.jpeg` (base64 in `ZendaLogo.swift`). Logs start with `zenda`.
- Web: 390-wide column with a bottom tab bar, Shippori Mincho and Zen Maru Gothic. Local key `zenda.cloud.v1`; borrows the setup link from any other Pocket web app. Cache prefix `zenda-web-` (`zenda-web-v1`).

## Look

Ink #2B2926, rice paper #F3EEE3, card #F9F5EC, hairline #E2DDD2, muted #5E5A53, pale fill #EAE3D5. Vermilion #B5452F is the only colour: the primary button, the active-tab dot, the breathing ball and the 禅 seal on Today. A faint ensō watermark on Today and Visualize.

## Not done yet

- One-off sessions from Start don't tick Aqua (by design for now).
- The Mac has no project delete.
- Scheduled counts body-scan steps under Visualize.
