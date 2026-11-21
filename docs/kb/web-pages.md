# The four web pages on GitHub Pages

Pocket's data reaches phones, iPads and other laptops through five small installable web apps, all served from this repo by GitHub Pages and all reading the same Supabase table. They are separate apps on purpose (Pranav, 2026-11-19): one is shared with his parents, one is his own Aqua, one is a view of his focus sessions, Ventus runs his timed routines step by step, and Terra tracks his calories. Each has its own folder, its own local copy of the data, its own service worker and its own Home Screen entry, so changing one never touches the others.

Not to be confused with [apps/web-apps.md](apps/web-apps.md), which covers the websites (WhatsApp, Slack and so on) wrapped inside the Mac menu bar.

Luna (`web/luna/`, https://gaone1906.github.io/Pocket/luna/), the sleep app, is a sixth, with its Mac half in [apps/luna.md](apps/luna.md).

Sol's formula cards (`web/sol/`, https://gaone1906.github.io/Pocket/sol/) are a seventh web app with no Mac counterpart yet; see [apps/sol.md](apps/sol.md).

Zenda (`web/zenda/`, https://gaone1906.github.io/Pocket/zenda/), the mindfulness app split out of Ventus, is an eighth, with its Mac half and records in [apps/zenda.md](apps/zenda.md). It reads `schedule.routine`, `schedule.check`, `schedule.settings`, `runner.entry` and `zenda.project`; writes `schedule.check`, `runner.entry` and `zenda.project`. Local key `zenda.cloud.v1`, cache prefix `zenda-web-` (`zenda-web-v2`), ink-swirl panda icon, rice-paper theme. It imports `../ventus/plan.js`, so a change to that file must keep Zenda working too. Ventus hides Zenda's routines (`isMindful`).

Related: [cloud-sync.md](cloud-sync.md) (the table, sync rules, setup link, dev server), [apps/schedule.md](apps/schedule.md) (Aqua on the Mac), [apps/pomodoro.md](apps/pomodoro.md) (Ignis on the Mac), [apps/kairos.md](apps/kairos.md) (Ventus on both), [apps/misura.md](apps/misura.md) (Terra on both).

## At a glance

| | Routine | Aqua | Ignis | Ventus | Terra | Luna |
| --- | --- | --- | --- | --- | --- | --- |
| URL | `https://gaone1906.github.io/Pocket/` | `https://gaone1906.github.io/Pocket/aqua/` | `https://gaone1906.github.io/Pocket/ignis/` | `https://gaone1906.github.io/Pocket/ventus/` | `https://gaone1906.github.io/Pocket/terra/` | `https://gaone1906.github.io/Pocket/luna/` |
| Folder | `web/` (top-level files only) | `web/aqua/` | `web/ignis/` | `web/ventus/` | `web/terra/` | `web/luna/` |
| Who uses it | Pranav's parents | Pranav | Pranav | Pranav | Pranav | Pranav |
| Shows | The Hair routine only | Every Aqua routine | Ignis focus sessions | Fitness projects: today's session, the schedule, guided and logged workouts, and a review | Calories eaten and burned against the day, week and month goals | Each night's sleep from Apple Health (score, hypnogram, comments), the week and the month |
| Writes | Never | Step check-offs, night start hour, its theme | Never | Step check-offs and `runner.entry` records (run logs, feel, project details, workouts) | `calorie.entry`, `calorie.weight` and the plan (`calorie.settings`) | Only the targets (`sleep.settings`); samples come from the Luna Sync Shortcut |
| Default theme | Sage, from the synced `settings.prefs`/`prefs` record | Sky, synced as `settings.prefs`/`orario` (field `aquaTheme`; the old `theme` field, Butter by default, is ignored) | Ember, kept per device in `localStorage` (`ignis.web.theme`) | Browns and beiges, fixed | Sage, fixed | Lavender, fixed |
| Icon | Shared Pocket icon | Koi whose fins flow into ripples, blue on pale blue | Lion whose mane turns to flame, facing right, red on pale red | Brown bear whose back turns into wind, on beige (R2) | Stag whose antlers grow into leafy branches, green on pale green | Wolf howling at the moon, lavender on pale lavender |
| Title and Home Screen name | Routine | Aqua | Ignis | Ventus | Terra | Luna |
| Local state key | `pocket.cloud.v1` | `orario.cloud.v1` | `aurelius.cloud.v1` | `runner.cloud.v1` | `misura.cloud.v1` | `luna.cloud.v1` |
| Cache prefix (`sw.js`) | `pocket-` (`pocket-v10`) | `aqua-web-` (`aqua-web-v2`, also clears `orario-master-`) | `ignis-web-` (`ignis-web-v3`, also clears `aurelius-web-`) | `runner-` (`runner-v7`) | `terra-web-` (`terra-web-v3`, also clears `misura-`) | `luna-web-` (`luna-web-v1`) |

`web/pomodoro/`, `web/aurelius/`, `web/orario/`, `web/kairos/` and `web/misura/` hold only an `index.html` that redirects to `../ignis/`, `../ignis/`, `../aqua/`, `../ventus/` and `../terra/`, keeping the query and hash, so old bookmarks, Home Screen icons and setup links still work. The folders were renamed on 2026-11-19 with the apps (Aurelius → Ignis, Kairos → Ventus, Orario → Aqua, Misura → Terra).

## Routine (`web/`)

The original web app, now cut down to what Pranav's parents need (PRs #8, #13).
- Shows only routines whose name matches `/hair/i` (`web/orario.js`), in Day, Week and Month views with tips.
- Read only: no ticking, no Mark all done, no schedule editor, no settings screen and no bottom bar. The only control is a sync button at the top, which runs `store.syncNow()`.
- No app or routine name appears anywhere; the page title and Home Screen name are "Routine".
- Theme and night start hour come from synced data (`settings.prefs`/`prefs`, `schedule.settings`/`book`), so they change only when someone changes them elsewhere.
- Before connecting it shows a setup screen asking for the setup link.

Files: `index.html`, `app.js` (shell, sync button, setup screen), `orario.js` (the views), `store.js`, `util.js`, `themes.js`, `style.css`, `sw.js`, `manifest.webmanifest`, icons.

## Aqua (`web/aqua/`)

The all-routines Aqua, Pranav's own (PRs #12, #15, #17, #21).
- Every routine in Day, Week and Month views, with a routine filter.
- Ticking steps and Mark all done write `schedule.check` records; this is where check-offs happen away from the Mac.
- No schedule editing: routines are added and changed in Aqua on the Mac (Pranav, 2026-11-19).
- No bottom bar or sidebar. A gear at the top right opens Settings: theme (light and dark rows), night start hour (writes `schedule.settings`/`book`), device name, sync status, Download a copy, disconnect.
- Theme defaults to Sky and syncs across devices as its own `settings.prefs` record with id `orario`, separate from the Routine app's `prefs`.
- If the browser already holds the Routine app's link (`pocket.cloud.v1`), it connects without asking.

Files: self-contained copies of `app.js`, `orario.js`, `store.js`, `util.js`, `themes.js`, `style.css`, plus its own `sw.js`, `manifest.webmanifest` and icons. It deliberately shares no files with `web/`, so the Routine app can be trimmed freely.

## Ignis (`web/ignis/`)

The Pomodoro app, renamed Aurelius (PR #20) and then Ignis on 2026-11-19 (first built as `web/pomodoro/` in PR #16, icon and Rose in PR #19).
- View only and no timer: it reads `board.project` and `board.session` and never writes a record. The timer runs on the Mac.
- A project picker, then Daily, Weekly and Monthly tabs: a card comparing this day, week or month with the average, project totals, a stacked day-by-day bar chart (Weekly), a 6am to 10pm timeline (Daily, Weekly) or a daily line graph (Monthly), with arrows and swipe for earlier periods.
- Settings has the theme and sync. The theme is per device only (`aurelius.web.theme`), not a synced record.
- Connects without asking in a browser that already holds a link under `pomodoro.cloud.v1`, `pocket.cloud.v1` or `orario.cloud.v1`.
- Internal names still say pomodoro: the record kinds (`board.*`), the Mac routes and data paths. Its `localStorage` reads fall back from `aurelius.*` to the old `pomodoro.*` keys so earlier installs keep their settings.

## Ventus (`web/ventus/`)

The fitness runner, the web half of [apps/kairos.md](apps/kairos.md). Rebuilt on 2026-11-21 around projects (one project per fitness routine) with four tabs in a bottom bar: Today, Scheduled, Start, Review. Phone-first at 390 pt; on a desktop browser the same column is centred at 560 px.
- Only fitness routines show: a routine counts when any step (weekly `plan` or `dated`) has `run.type` `moves`, `intervals`, `rounds` or `log`. Mindfulness routines (box, say, write, quiet timers) belong to Zenda; Hair never shows.
- **Today**: weekday and date, a dumbbell chip with days to the next milestone and a flame chip with the streak, this week's seven dots (done ink, rest blue, today ringed, part half, missed outlined), a hero card per session today (day ring, project name, session title, steps with icon and compact detail) with Start · minutes (Continue, Resume or Done as fits), the project's goal bars and the next session as a dashed card. Nothing today shows one quiet line.
- **Scheduled**: project pill (picker sheet; the choice is kept per device in `localStorage` `runner.project` and drives Scheduled and Review), a pencil that opens the project editor sheet (name, goal, start, goal date, targets, milestones; saves the project record), a card with the targets and a timeline (today dot, dumbbell per milestone, flag at the end), a Monday-based week stepper opening on the current week, and seven day rows (step-type icons, minutes or a tick, faded when past, blue tint on rest days, today inverted). A row opens the **Day** screen: each step as a card (intervals as a work/rest segment bar with a legend, single-move rounds as set chips), Preview (a sheet listing every move, rest and tip) and Start. Start on today runs the scheduled session and ticks Aqua; on any other day it is an ad-hoc run.
- **Start**: Guided tiles (today's session, one tile per distinct step name in the project, the most recent version on or before today, else the first, each starting an ad-hoc run of that step, and Any day, which opens Scheduled) and Log tiles (Run, Rope, Walk, Gym, Other) that open the Log sheet: date chip, project, kind, fields by kind (min and km with pace for Run and Walk; skips, sets and min for Rope; min otherwise), feel 1–5, notes.
- **Review**: project pill, gear (Settings: chime, wait before each step, device name, last sync, Sync now, Download, Disconnect), Week / Project / All, stat tiles (days done of elapsed, streak, hours moving, goals), a heatmap of the project's days with a legend, minutes per session day (missed days hollow, rest days blue), goal bars (tap to mark a target achieved), the feel trend (last seven) and the runs list (km, time, pace).
- **Guided session**: the same engine and run screens as before (`plan.js`), warm ground while working, a blue chip for what comes next, blue mood on rests, round dots, back / pause / skip, the step list behind the title, elapsed time top right. Ad-hoc runs keep their own steps in the run state (`adhoc: true`), never tick Aqua and save a `workout` entry on finish; scheduled runs tick `schedule.check` as each step finishes.
- Records it writes: `schedule.check`, and `runner.entry` with these shapes (all carry `updated`):
  - project `project|<routineId>`: `routine`, `routineName`, `tag` and `step` `project`, `slot` "", `title` (name), `text` (goal), `day` (start), `notes` (goal date), `lines` (targets), `feel` (achieved target indexes as "0,1", absent for none), `prompts` (milestones `yyyy-MM-dd|Label`). Without one, the routine's name, `starts` and `ends` stand in.
  - workout `workout|<uuid>`: `routine`, `routineName`, `tag` `workout`, `step` (`run`, `rope`, `walk`, `gym`, `other`, or `guided` for an ad-hoc run), `title`, `day`, `slot` "", `seconds`, `km` (run and walk), `text` (rope skips), `lines` (`[sets]`), `feel` "1".."5", `notes`.
  - run logs (`tag` `run`, id `routine|day|slot|step`) and "How did it feel?" (`tag` `feel`, step `feel`, easy/right/hard, read as 2/3/4) as before.
- Templates live in `plan.js`; every number comes from the `run` object on each step in the database, never from code. Wake lock while running, a WebAudio chime with vibration, and a run that resumes after a reload (`runner.run.v1`). Per device: `runner.sound`, `runner.hold`, `runner.project`.
- Connects without asking in a browser that already holds a link under `orario.cloud.v1` or `pocket.cloud.v1`.

Files: `index.html`, `app.js` (tabs, sheets, runner and run screens), `projects.js` (fitness filter, projects, day status, streaks, review data), `plan.js` (templates to beats), `routines.js` (schedule and entry access), `store.js`, `util.js`, `style.css` (browns and beiges, Nunito), `sw.js`, `manifest.webmanifest`, `icon.svg` (the 256 px bear embedded), `icon-192.png`, `icon-512.png`.

## Terra (`web/terra/`)

The calorie tracker (built 2026-11-19), the web half of [apps/misura.md](apps/misura.md).
- First run asks for the setup link, then the plan (born, sex, height, activity, weight, start day, goal weight and day, pace, lowest budget).
- Day: week strip with a dot per logged day (red when over), a ring of kcal left, the day's entries and weight, and a + button at the bottom right (on Day, Week and Month) that fades the page and fans out Meal, Workout and Weight, each opening its sheet. Tap an entry to edit or delete it. "Poha 380" in the name field fills the kcal too.
- Week: deficit against what is due with the "Under the limit" or "Over the limit" badge, a bar per day (eaten, and workout beside it) on one baseline with a dashed budget line, and a table of Day, kg, Eaten and Deficit / goal.
- Month: a calendar coloured green or red per logged day, weight lost against the month's target with the trend, and the month's deficit.
- Settings: the plan, Watch share, Eat back, Show kcal left, export and sync.
- Connects without asking in a browser that already holds a link under `orario.cloud.v1`, `runner.cloud.v1` or `pocket.cloud.v1`.

Files: `index.html`, `app.js` (views and sheets), `plan.js` (the math, mirroring `MisuraMath`), `store.js`, `util.js`, `style.css` (Sage tokens, Nunito), `sw.js`, `manifest.webmanifest`, `icon.svg`, `icon-192.png`, `icon-512.png`.

## Luna (`web/luna/`)

The sleep app (built 2026-11-21), the web half of [apps/luna.md](apps/luna.md), which holds the records, the night math and every comment rule.
- Night: week strip with a dot per night coloured by score (arrows page by week), the score ring with time asleep, Bed and Wake, then In bed and Awake (heart rate and HRV are never shown, even when samples carry them), the hypnogram with its stage legend and up to three comments. A night with no data shows a dashed moon and a Sync button.
- Week: the range with arrows, the average with the change against last week, the sleep-window chart (a capsule per night, dashed lines at the target times, dashed outlines for nights to come), the stage bar and comments. Month: the calendar coloured by score, average, bedtime spread and score, hours asleep as a line against the target band, and two comments. Tapping a capsule or a day opens that night.
- Every chart item shows its amount in one shared dark tooltip (`.tip`, driven by `data-tip`/`data-tid` attributes and delegated pointer events): hover on desktop, tap on a phone (tap elsewhere or scroll to dismiss). Hypnogram blocks show `1h 30m · Core` and the clock range (each block has a full-height transparent hit column, at least 6 px wide); stage bar and legend items `1h 26m · Deep · 18%` (Deep, Core and REM as a share of time asleep, Awake of time in bed); week capsules the day, bed–wake range, time asleep and score; strip days and month cells time asleep and score; month line points the day and time asleep; the ring the score. On touch, the first tap on a capsule, month cell or line point shows its tooltip and a second tap opens the night.
- Sync (the round button or the empty night's button) remembers the nights it has in `sessionStorage` (`luna.before`), opens `shortcuts://x-callback-url/run-shortcut?name=Luna%20Sync` with `x-success` back to the page plus `#synced`, then pulls and shows `✓ N nights` or `✓ Up to date`. Outside iPhone and iPad it just pulls.
- Settings: Bed, Wake, Sleep, Deep and REM write `sleep.settings`/`book` with `updated`; Luna Sync opens the Shortcut; Synced, Download a copy, Disconnect.
- Pulls only `sleep.sample` and `sleep.settings` (`kind=in.(…)`) and keeps nothing else locally. Never writes samples.
- Connects without asking in a browser that already holds a link under `pocket.cloud.v1`, `orario.cloud.v1`, `runner.cloud.v1`, `misura.cloud.v1` or `aurelius.cloud.v1`.

Files: `index.html`, `app.js` (views, charts, sync flow), `sleep.js` (the shared math, mirroring `LunaMath`: value normalising, nights, score, comments, week and month), `store.js`, `util.js`, `style.css` (lavender tokens, Nunito), `sw.js`, `manifest.webmanifest`, `icon-192.png`, `icon-512.png`, `apple-touch-icon.png`.

## Shared rules

- **One backend.** All five use the same Supabase table, `public.records`, with the same record kinds and the same sync code shape (`store.js`: local outbox, push within half a second, pull every 4 s while visible). See [cloud-sync.md](cloud-sync.md).
- **No sign-in.** The table is open to the anon key. A device connects with a setup link ending in `#connect=…` (made by `node web/dev/link.mjs <url> <key>`); each app reads the hash, saves the URL and key, and clears the hash from the address bar. The link is the only key, so never commit it or the anon key, and never paste it into an issue or PR.
- **Home Screen apps have their own storage** on iPhone and iPad, so each installed app asks for the setup link once.
- **Service worker caches are scoped.** Each `sw.js` deletes only old caches with its own prefix (see the table), because all five share one origin and would otherwise wipe each other's offline copy. When you change a file an app caches, bump that app's `CACHE` version and list any new file in its `SHELL`.
- **Deploy.** `.github/workflows/pages.yml` copies `web/` (minus `web/dev`) to Pages on every push to `main` that touches `web/**`. A new web app is just a new folder under `web/` with its own manifest, `id`/`scope` of `./`, and a cache prefix no other app uses.
- **Testing.** Run `web/dev/server.mjs` and open `/`, `/orario/`, `/aurelius/`, `/kairos/`, `/misura/` or `/luna/` on it; never test against the real project.
