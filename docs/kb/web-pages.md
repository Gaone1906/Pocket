# The four web pages on GitHub Pages

Pocket's data reaches phones, iPads and other laptops through four small installable web apps, all served from this repo by GitHub Pages and all reading the same Supabase table. They are separate apps on purpose (Pranav, 2026-11-19): one is shared with his parents, one is his own Orario, one is a view of his focus sessions, and Kairos runs his timed routines step by step. Each has its own folder, its own local copy of the data, its own service worker and its own Home Screen entry, so changing one never touches the others.

Not to be confused with [apps/web-apps.md](apps/web-apps.md), which covers the websites (WhatsApp, Slack and so on) wrapped inside the Mac menu bar.

Related: [cloud-sync.md](cloud-sync.md) (the table, sync rules, setup link, dev server), [apps/schedule.md](apps/schedule.md) (Orario on the Mac), [apps/pomodoro.md](apps/pomodoro.md) (Aurelius on the Mac), [apps/kairos.md](apps/kairos.md) (Kairos on both).

## At a glance

| | Routine | Orario | Aurelius | Kairos |
| --- | --- | --- | --- | --- |
| URL | `https://gaone1906.github.io/Pocket/` | `https://gaone1906.github.io/Pocket/orario/` | `https://gaone1906.github.io/Pocket/aurelius/` | `https://gaone1906.github.io/Pocket/kairos/` |
| Folder | `web/` (top-level files only) | `web/orario/` | `web/aurelius/` | `web/kairos/` |
| Who uses it | Pranav's parents | Pranav | Pranav | Pranav |
| Shows | The Hair routine only | Every Orario routine | Aurelius focus sessions | Today's timed routines, one step at a time, and the journal |
| Writes | Never | Step check-offs, night start hour, its theme | Never | Step check-offs and `runner.entry` journal entries |
| Default theme | Sage, from the synced `settings.prefs`/`prefs` record | Butter, synced as `settings.prefs`/`orario` | Rose, kept per device in `localStorage` (`aurelius.web.theme`) | Apricot, fixed |
| Icon | Shared Pocket icon | Sun on the horizon, in Butter | Tomato, in Rose | Balanced stones, in Apricot |
| Title and Home Screen name | Routine | Orario | Aurelius | Kairos |
| Local state key | `pocket.cloud.v1` | `orario.cloud.v1` | `aurelius.cloud.v1` | `runner.cloud.v1` |
| Cache prefix (`sw.js`) | `pocket-` (`pocket-v10`) | `orario-master-` (`orario-master-v4`) | `aurelius-web-` (`aurelius-web-v1`) | `runner-` (`runner-v1`) |

`web/pomodoro/index.html` is only a redirect to `../aurelius/` that keeps the query and hash, so old bookmarks and setup links still work.

## Routine (`web/`)

The original web app, now cut down to what Pranav's parents need (PRs #8, #13).
- Shows only routines whose name matches `/hair/i` (`web/orario.js`), in Day, Week and Month views with tips.
- Read only: no ticking, no Mark all done, no schedule editor, no settings screen and no bottom bar. The only control is a sync button at the top, which runs `store.syncNow()`.
- No app or routine name appears anywhere; the page title and Home Screen name are "Routine".
- Theme and night start hour come from synced data (`settings.prefs`/`prefs`, `schedule.settings`/`book`), so they change only when someone changes them elsewhere.
- Before connecting it shows a setup screen asking for the setup link.

Files: `index.html`, `app.js` (shell, sync button, setup screen), `orario.js` (the views), `store.js`, `util.js`, `themes.js`, `style.css`, `sw.js`, `manifest.webmanifest`, icons.

## Orario (`web/orario/`)

The all-routines Orario, Pranav's own (PRs #12, #15, #17, #21).
- Every routine in Day, Week and Month views, with a routine filter.
- Ticking steps and Mark all done write `schedule.check` records; this is where check-offs happen away from the Mac.
- No schedule editing: routines are added and changed in Orario on the Mac (Pranav, 2026-11-19).
- No bottom bar or sidebar. A gear at the top right opens Settings: theme (light and dark rows), night start hour (writes `schedule.settings`/`book`), device name, sync status, Download a copy, disconnect.
- Theme defaults to Butter and syncs across devices as its own `settings.prefs` record with id `orario`, separate from the Routine app's `prefs`.
- If the browser already holds the Routine app's link (`pocket.cloud.v1`), it connects without asking.

Files: self-contained copies of `app.js`, `orario.js`, `store.js`, `util.js`, `themes.js`, `style.css`, plus its own `sw.js`, `manifest.webmanifest` and icons. It deliberately shares no files with `web/`, so the Routine app can be trimmed freely.

## Aurelius (`web/aurelius/`)

The Pomodoro app, renamed Aurelius on 2026-11-19 (PR #20; first built as `web/pomodoro/` in PR #16, icon and Rose in PR #19).
- View only and no timer: it reads `board.project` and `board.session` and never writes a record. The timer runs on the Mac.
- A project picker, then Daily, Weekly and Monthly tabs: a card comparing this day, week or month with the average, project totals, a stacked day-by-day bar chart (Weekly), a 6am to 10pm timeline (Daily, Weekly) or a daily line graph (Monthly), with arrows and swipe for earlier periods.
- Settings has the theme and sync. The theme is per device only (`aurelius.web.theme`), not a synced record.
- Connects without asking in a browser that already holds a link under `pomodoro.cloud.v1`, `pocket.cloud.v1` or `orario.cloud.v1`.
- Internal names still say pomodoro: the record kinds (`board.*`), the Mac routes and data paths. Its `localStorage` reads fall back from `aurelius.*` to the old `pomodoro.*` keys so earlier installs keep their settings.

## Kairos (`web/kairos/`)

The guided routine runner (built 2026-11-19), the web half of [apps/kairos.md](apps/kairos.md).
- Today lists the morning and night sessions of every routine with at least one guided step, so Hair never appears. Start shows only the current step: countdowns, named moves with reps, rest between rounds, say-it-out-loud lines, writing fields, and a data-entry screen for runs.
- Finishing a step writes the same `schedule.check` record Orario writes. Writing, run logs and "How did it feel?" are `runner.entry` records; the Journal screen lists and searches them by tag.
- Templates live in `plan.js`; every number comes from the `run` object on each step in the database, never from code.
- Wake lock while running, a WebAudio chime with vibration, and a run that resumes after a reload (`runner.run.v1`). Per device: `runner.sound` and `runner.hold`.
- Connects without asking in a browser that already holds a link under `orario.cloud.v1` or `pocket.cloud.v1`.

Files: `index.html`, `app.js` (views and runner), `plan.js` (templates to beats), `routines.js` (schedule and journal access), `store.js`, `util.js`, `style.css`, `sw.js`, `manifest.webmanifest`, `icon.svg`, `icon-192.png`, `icon-512.png`.

## Shared rules

- **One backend.** All four use the same Supabase table, `public.records`, with the same record kinds and the same sync code shape (`store.js`: local outbox, push within half a second, pull every 4 s while visible). See [cloud-sync.md](cloud-sync.md).
- **No sign-in.** The table is open to the anon key. A device connects with a setup link ending in `#connect=…` (made by `node web/dev/link.mjs <url> <key>`); each app reads the hash, saves the URL and key, and clears the hash from the address bar. The link is the only key, so never commit it or the anon key, and never paste it into an issue or PR.
- **Home Screen apps have their own storage** on iPhone and iPad, so each installed app asks for the setup link once.
- **Service worker caches are scoped.** Each `sw.js` deletes only old caches with its own prefix (see the table), because all four share one origin and would otherwise wipe each other's offline copy. When you change a file an app caches, bump that app's `CACHE` version and list any new file in its `SHELL`.
- **Deploy.** `.github/workflows/pages.yml` copies `web/` (minus `web/dev`) to Pages on every push to `main` that touches `web/**`. A new web app is just a new folder under `web/` with its own manifest, `id`/`scope` of `./`, and a cache prefix no other app uses.
- **Testing.** Run `web/dev/server.mjs` and open `/`, `/orario/`, `/aurelius/` or `/kairos/` on it; never test against the real project.
