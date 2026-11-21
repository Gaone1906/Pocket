# Ortus

Ortus (app id `ortus`) is the motivation app, built on 2026-11-21. It is purely passive: quotes to read, Shorts and long videos to watch, and one-page stories, all general motivation with nothing tied to a goal. Its icon is the rooster (M2, #D9542C on #FDE3D8, facing right); the menu bar shows a sunrise glyph. Mac shortcut ⌥7.

It exists twice: on the Mac (`Ortus*.swift`) and as the web app at `/Pocket/ortus/` (`web/ortus/`). Both only read the library. Mockups: the "Ortus mockups" canvas (Mac Stories, Reels, Quotes, the dropdown, and three web screens).

Related: [../cloud-sync.md](../cloud-sync.md), [../web-pages.md](../web-pages.md).

## Library

| kind | id | data |
| --- | --- | --- |
| `ortus.quote` | `q001`… | `{id, text, author, who, source?, theme, sure?}`. Ten themes: Courage, Resilience, Purpose, Mindset, Perseverance, Excellence, Discipline, Failure, Patience, Action. `sure: "moderate"` marks a doubtful attribution |
| `ortus.story` | slug | `{id, name, kind, who, title, paras, line, source}`: `kind` `real` or `fiction`, `paras` three paragraphs, `line` the closing takeaway |
| `ortus.reel` | slug | `{id, source: "youtube", url, category, views, channel, title, start, end}`: a YouTube Short. Categories: Speeches, Never give up, Discipline, Legends, Stories, Sports, Kindness & humanity, Life advice |
| `ortus.video` | slug | `{id, url, title, channel, category, start, end}`: a long YouTube video, `start`/`end` in seconds to play a clip |

Loaded on 2026-11-21: 501 quotes, 100 stories (75 real, 25 fiction) and 437 Shorts. No videos yet; both apps show an empty state until rows exist. There is no music mode (Pranav, 2026-11-21). Adding content is a db insert, never a code change.

On the Mac: `$ROOT/ortus.json` (`{"quotes", "stories", "reels", "videos"}`) through `DataVault` as `ortus` (git noun "library item"), synced by a `CloudDocument` row. `OrtusStore` writes adopted cloud data verbatim, so the canonical comparison never sees a diff and nothing is pushed back.

## Daily picks

The quote, story and reel of the day are the same on every device. `OrtusPick` (Swift) and `web/ortus/pick.js` must agree:

- Day key: local time minus 4 hours, as `yyyy-MM-dd`.
- Hash: FNV-1a 32-bit over the UTF-8 of `"<kind>|<day>"`, e.g. `hash("ortus.quote|2026-11-21") = 3628894745`.
- `daily`: sort by id, pick `hash % count`. `shuffled`: sort by `hash(seed + "|" + id)`. Browsing order is the daily item first, then the rest shuffled with seed `day|kind`.
- Reel and Short titles go through `cleanTitle` (hashtags, emoji and trailing pipes removed).

"Only quotes with a known source" (Mac UserDefaults `ortus.verifiedOnly`, web `ortus.verified`) hides `sure: "moderate"` quotes.

## Screens

Quotes (theme chips, quote of the day card, next/previous, copy or share), Reels (category chips, vertical player, next/previous), Videos (wide player and list), Stories (story of the day, search, Real/Fiction filter, reader with the closing line and source link), settings (the verified toggle, counts, sync).

- Mac dropdown (380×600): the quote of the day with Next, the story of the day, a reel pick, and a row of four mode buttons; each opens the window at that place. The expanded window (1100×720, autosave `ortus.board`) has an 88px rail with the four modes and a gear. YouTube plays in a `WKWebView` (`OrtusPlayer`) loading a `youtube-nocookie.com` iframe with the web app's URL as base, so YouTube gets a referrer; the player is blanked when the window closes. Arrow keys step quotes (←/→) and reels (↑/↓). Logo is `OrtusLogo.jpeg` (base64 in `OrtusLogo.swift`).
- Web: 520-wide column, bottom tab bar, Fraunces and Inter. Reels and Videos switch to a dark screen. Swipe left/right on quotes, up/down on reels. The page does not re-render while a player is on screen, so a background sync never interrupts playback. Local keys `ortus.mode`, `ortus.theme`, `ortus.category`, `ortus.verified`.

## Look

Accent #C2461F, bright #D9542C, deep #8F3215, ground #FDE3D8, paper #FFF8F4, ink #3A1F14, muted #6E4A3B, hairline #F0D6CA. Dark mode for Reels and Videos: night #1E100A with #3A1F14 panels.
