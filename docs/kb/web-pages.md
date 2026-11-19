# The four web pages on GitHub Pages

Pocket's data reaches phones, iPads and other laptops through five small installable web apps, all served from this repo by GitHub Pages and all reading the same Supabase table. They are separate apps on purpose (Pranav, 2026-11-19): one is shared with his parents, one is his own Aqua, one is a view of his focus sessions, Ventus runs his timed routines step by step, and Terra tracks his calories. Each has its own folder, its own local copy of the data, its own service worker and its own Home Screen entry, so changing one never touches the others.

Not to be confused with [apps/web-apps.md](apps/web-apps.md), which covers the websites (WhatsApp, Slack and so on) wrapped inside the Mac menu bar.

Related: [cloud-sync.md](cloud-sync.md) (the table, sync rules, setup link, dev server), [apps/schedule.md](apps/schedule.md) (Aqua on the Mac), [apps/pomodoro.md](apps/pomodoro.md) (Ignis on the Mac), [apps/kairos.md](apps/kairos.md) (Ventus on both), [apps/misura.md](apps/misura.md) (Terra on both).

## At a glance

| | Routine | Aqua | Ignis | Ventus | Terra |
| --- | --- | --- | --- | --- | --- |
| URL | `https://gaone1906.github.io/Pocket/` | `https://gaone1906.github.io/Pocket/aqua/` | `https://gaone1906.github.io/Pocket/ignis/` | `https://gaone1906.github.io/Pocket/ventus/` | `https://gaone1906.github.io/Pocket/terra/` |
| Folder | `web/` (top-level files only) | `web/aqua/` | `web/ignis/` | `web/ventus/` | `web/terra/` |
| Who uses it | Pranav's parents | Pranav | Pranav | Pranav | Pranav |
| Shows | The Hair routine only | Every Aqua routine | Ignis focus sessions | Today's timed routines, one step at a time, and the journal | Calories eaten and burned against the day, week and month goals |
| Writes | Never | Step check-offs, night start hour, its theme | Never | Step check-offs and `runner.entry` journal entries | `calorie.entry`, `calorie.weight` and the plan (`calorie.settings`) |
| Default theme | Sage, from the synced `settings.prefs`/`prefs` record | Sky, synced as `settings.prefs`/`orario` (field `aquaTheme`; the old `theme` field, Butter by default, is ignored) | Rose, kept per device in `localStorage` (`aurelius.web.theme`) | Stone, fixed | Sage, fixed |
| Icon | Shared Pocket icon | Koi whose fins flow into ripples, blue on pale blue | Lion whose mane turns to flame, rose on pale rose | Eagle dissolving into wind, stone on pale stone | Mantis built from leaves, green on pale green |
| Title and Home Screen name | Routine | Aqua | Ignis | Ventus | Terra |
| Local state key | `pocket.cloud.v1` | `orario.cloud.v1` | `aurelius.cloud.v1` | `runner.cloud.v1` | `misura.cloud.v1` |
| Cache prefix (`sw.js`) | `pocket-` (`pocket-v10`) | `aqua-web-` (`aqua-web-v1`, also clears `orario-master-`) | `ignis-web-` (`ignis-web-v1`, also clears `aurelius-web-`) | `runner-` (`runner-v3`) | `terra-web-` (`terra-web-v2`, also clears `misura-`) |

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

The guided routine runner (built 2026-11-19), the web half of [apps/kairos.md](apps/kairos.md).
- Today lists the morning and night sessions of every routine with at least one guided step, so Hair never appears. Start shows only the current step: countdowns, named moves with reps, rest between rounds, say-it-out-loud lines, writing fields, and a data-entry screen for runs.
- Finishing a step writes the same `schedule.check` record Aqua writes. Writing, run logs and "How did it feel?" are `runner.entry` records; the Journal screen lists and searches them by tag.
- Templates live in `plan.js`; every number comes from the `run` object on each step in the database, never from code.
- Wake lock while running, a WebAudio chime with vibration, and a run that resumes after a reload (`runner.run.v1`). Per device: `runner.sound` and `runner.hold`.
- Connects without asking in a browser that already holds a link under `orario.cloud.v1` or `pocket.cloud.v1`.

Files: `index.html`, `app.js` (views and runner), `plan.js` (templates to beats), `routines.js` (schedule and journal access), `store.js`, `util.js`, `style.css`, `sw.js`, `manifest.webmanifest`, `icon.svg`, `icon-192.png`, `icon-512.png`.

## Terra (`web/terra/`)

The calorie tracker (built 2026-11-19), the web half of [apps/misura.md](apps/misura.md).
- First run asks for the setup link, then the plan (born, sex, height, activity, weight, start day, goal weight and day, pace, lowest budget).
- Day: week strip with a dot per logged day (red when over), a ring of kcal left, the day's entries and weight, and Meal, Workout and Weight buttons. Tap an entry to edit or delete it. "Poha 380" in the name field fills the kcal too.
- Week: deficit against what is due with the "Under the limit" or "Over the limit" badge, a bar per day (eaten, and workout beside it) on one baseline with a dashed budget line, and a table of Day, kg, Eaten and Deficit / goal.
- Month: a calendar coloured green or red per logged day, weight lost against the month's target with the trend, and the month's deficit.
- Settings: the plan, Watch share, Eat back, Show kcal left, export and sync.
- Connects without asking in a browser that already holds a link under `orario.cloud.v1`, `runner.cloud.v1` or `pocket.cloud.v1`.

Files: `index.html`, `app.js` (views and sheets), `plan.js` (the math, mirroring `MisuraMath`), `store.js`, `util.js`, `style.css` (Sage tokens, Nunito), `sw.js`, `manifest.webmanifest`, `icon.svg`, `icon-192.png`, `icon-512.png`.

## Shared rules

- **One backend.** All five use the same Supabase table, `public.records`, with the same record kinds and the same sync code shape (`store.js`: local outbox, push within half a second, pull every 4 s while visible). See [cloud-sync.md](cloud-sync.md).
- **No sign-in.** The table is open to the anon key. A device connects with a setup link ending in `#connect=…` (made by `node web/dev/link.mjs <url> <key>`); each app reads the hash, saves the URL and key, and clears the hash from the address bar. The link is the only key, so never commit it or the anon key, and never paste it into an issue or PR.
- **Home Screen apps have their own storage** on iPhone and iPad, so each installed app asks for the setup link once.
- **Service worker caches are scoped.** Each `sw.js` deletes only old caches with its own prefix (see the table), because all five share one origin and would otherwise wipe each other's offline copy. When you change a file an app caches, bump that app's `CACHE` version and list any new file in its `SHELL`.
- **Deploy.** `.github/workflows/pages.yml` copies `web/` (minus `web/dev`) to Pages on every push to `main` that touches `web/**`. A new web app is just a new folder under `web/` with its own manifest, `id`/`scope` of `./`, and a cache prefix no other app uses.
- **Testing.** Run `web/dev/server.mjs` and open `/`, `/orario/`, `/aurelius/`, `/kairos/` or `/misura/` on it; never test against the real project.
