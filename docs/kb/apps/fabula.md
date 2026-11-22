# Fabula

Fabula (app id `ortus`, Mac shortcut ⌥7) is the movie recommender that replaced the Ortus motivation app on 2026-11-22. Only the
names people see say Fabula; the app id, data file, `DataVault` name and record kinds still say `ortus`. Logo: the rooster with a
film-reel tail and a popcorn bucket (F2 without music notes). Web app at `/Pocket/fabula/` (`web/fabula/`); `/Pocket/ortus/`
redirects there. Mockups: the "Fabula mockups" canvas.

Related: [../cloud-sync.md](../cloud-sync.md), [../web-pages.md](../web-pages.md).

## Screens

- **Recommend**: one card at a time. Drag right stamps YES (green, top left), drag left stamps NOPE (red, top right), drag up
  stamps SEEN IT; release past 110 px to commit, otherwise the card springs back. Swipe up opens the rating sheet (1 to 10 grid,
  a comments box hinted "Tell us about the movie!", Skip rating, Save to Log). Hold still 0.6 s: the card shakes (0.5 s
  side-to-side wobble) and turns gold = superlike, which opens Tonight's pick. An undo arrow sits at the top left of every card.
  The description shows three lines; tapping it opens it upward over the poster in 0.38 s while the poster dims to 72% black
  (web `toggleHook`, Mac menu-bar card `open`); tapping again folds it, and a new card starts folded. The tap never starts a drag.
  Header: logo + "Fabula" + chevron (tap opens the sidebar), then round icon buttons for Watchlist (bookmark) and Match (people).
  Under the header two dropdown pills, Language and Genre, each opening a multi-select sheet. No other chips, no bottom bar,
  no instructional text anywhere.
- **Tonight's pick** (after a superlike): poster, title, year · runtime · director, the streaming line (Fraunces, green,
  "Streaming on Prime Video in India" from `providers`), "Watch this tonight" and "Keep swiping", and the other yeses.
- **Watchlist**: superlikes first (gold border), then yeses, newest first; pills Language, Genre, Added (Any time, This week,
  This month).
- **Log**: stats (films logged, your average, best decade), search, sort, list with rating and comment. "+ Add film" searches
  all of TMDB (any language) through `fabula-tmdb` `search`, then `add`, then a rating sheet.
- **Match** (web only): host creates a room and shares the link; friends open it, see a "What's your name?" sheet, then swipe the
  same 40 films. When every member has said yes to one film: "It's a match!".
- **Refiner**: pick Language and Genre chips (Any allowed), then rate 10 films at a time with 1-10 sliders; an untouched slider means not seen. "Continue: 10 more" saves the batch and loads 10 more; Stop saves it, asks `fabula-ai` `taste` for a new taste profile and shows Taste updated (counts, what changed, the one-line summary).
- **AI Mode**: a mood box with four idea chips; `fabula-ai` `mood` returns up to 4 films with a `why` line. Fine-tune notes and "None of these, try again" start new rounds that never repeat a film; "This one" then "Watch X tonight" superlikes it and opens Tonight's pick.
- **Sidebar** (from the logo): Recommend, Log, Refiner, AI Mode. Watchlist and Match are the round header buttons.
- Mac: same Recommend card (drag with the mouse, or ← no, → yes, ↑ seen it, hold Space superlike, ⌘Z undo); the window rail
  has Recommend, Watchlist, Log, Refiner and AI Mode. No Match on the Mac.

## Data

`movies` table (read-only for anon, written only by edge functions): `tmdb` (pk), `title`, `original_title`, `year`, `released`,
`runtime`, `lang` (ISO 639-1), `language` (English name, e.g. Hindi), `genres` (TMDB names, "Science Fiction" stored as "Sci-fi"),
`keywords`, `director`, `cast` (top 6), `overview`, `poster`, `backdrop` (TMDB paths: `https://image.tmdb.org/t/p/w500` + path),
`vote`, `votes`, `popularity`, `collection`, `providers` (India flatrate names), `recs` (TMDB recommendations ids), `updated`.

Personal data lives in the shared `records` table (fixed user, one row per item):

| kind | id | data |
| --- | --- | --- |
| `ortus.log` | tmdb id | `{tmdb, title, year, rating (1-10, halves allowed), comment, poster, language, genres, director, runtime, logged, updated}` |
| `ortus.swipe` | tmdb id | `{tmdb, verdict: yes \| no \| super \| seen, at, title, year, poster, language, genres, runtime, director, updated}` |

| `ortus.unseen` | tmdb id | `{tmdb, title, year, at, updated}`: Refiner sliders left untouched, so Refiner never shows them again; Recommend ignores them |
| `ortus.taste` | `book` | `{summary, more, less, likes: {genres, directors, keywords}, dislikes: {...}, ratings, updated}`, written only by `fabula-ai` |

Refiner ratings are ordinary `ortus.log` rows with `source: "refiner"`. Undo deletes the swipe row (`deleted: true`). Seen with a rating writes both a `seen` swipe and an `ortus.log`; Skip rating writes
only the swipe. Watchlist = swipes `yes`/`super` with no log. The old `ortus.quote`, `ortus.story`, `ortus.reel` and `ortus.video`
rows were deleted on 2026-11-22.

## Recommending

`rpc/fabula_deck` (`p_langs text[]`, `p_genres text[]`, `p_limit int`, `p_exclude int[]`) returns a JSON array of films with a
`why` line ("Because you loved …"). Both apps call it, so the Mac and the web always agree. It centres ratings on 8.1 (7 is a
soft no), treats swipes as pseudo-ratings (super 10, yes 8.8, no 7.0 fading over 90 days) at half weight, learns shrunk
affinities for genres, keywords, director and top cast, boosts films TMDB recommends from films rated 9+, adds a quality prior,
penalises sequels whose earlier parts are unseen, excludes everything logged or swiped (a no comes back after 180 days), and
mixes about 20% exploration from ranks 40 to 400. The `ortus.taste` likes and dislikes add or take 0.25 per matching genre,
director or keyword (capped at 3 matches). It is plpgsql with custom plans and runs in about 0.6 s (the anon role times out at 3 s).
`rpc/fabula_refine` (same filters, `p_limit`, `p_exclude`) picks Refiner films: the 300 most-voted matches not logged, swiped or
unseen, sampled with a bias to more votes. Clients pass the ids already on screen as `p_exclude` and fetch more when 5
cards are left.

## Edge functions

Base `https://oisplnonpwyvekcbwmhv.supabase.co/functions/v1/`, JSON `POST`, no JWT needed.

- `fabula-tmdb`: `{action: "search", q, year?}` → `{results: [{tmdb, title, original_title, year, language, poster, votes}]}`;
  `{action: "add", tmdb}` → `{movie}` (fetches from TMDB and stores it in `movies` if missing). `ingest` and `import` need the
  admin token in `fabula_admin` and are run from the database only. The TMDB token is the `TMDB_TOKEN` function secret and is never
  stored anywhere else.
- `fabula-ai` (needs the app's `apikey` header, checked against the REST API; calls Haiku with the `ANT_KEY` secret):
  `{action: "mood", text, notes?, shown?}` → `{films: [deck-shaped film + why]}` (Haiku names films, matched to `movies` or
  added through `fabula-tmdb`, minus anything logged, swiped or shown); `{action: "taste", fresh?}` → `{taste}` and saves
  `ortus.taste`.
- `fabula-match`: `create {name, langs?, genres?}` (needs the app's own `apikey` header; the function checks it against the REST
  API), `join {code, name}`, `state {code, member}`, `start {code, member}` (host only), `swipe {code, member, tmdb, yes}`,
  `leave {code, member}`. Every answer is the room state `{code, me, started, members: [{name, host, swiped, me}], deck, swiped,
  matched, total}`. Rooms live in locked tables `match_room`, `match_member`, `match_swipe` that only the function can touch; a
  `pg_cron` job deletes rooms 2 hours after a match or 12 hours after creation. Friend links are
  `/Pocket/fabula/match.html#<projectRef>.<code>` (the Supabase subdomain from the host's setup link, so no project URL is in the repo) and never carry the anon key. Up to 8 people per room; joining closes when the host starts.

## Catalogue

Loaded by `fabula-tmdb` `ingest` on a `pg_cron` job (`fabula-ingest`, every minute, unscheduled when done): for each year 1990 to
2026, the most-voted films with at least 200 votes (90 for 2024, 40 for 2025, 15 for 2026), plus Hindi, Telugu, Tamil,
Malayalam and Kannada films with at least 20 votes (5 from 2025). Documentaries are skipped. Progress is `ingest_cursor` in
`fabula_admin`. Any film logged through search is added on the fly.

## Movies, Shows and Anime

One `movies` table holds all three, told apart by `kind` (`movie`, `show`, `anime`). Shows use id 100,000,000 + TMDB TV
id and come from TMDB TV (English, Korean and Hindi, 1990 on) with IMDb ratings; anime uses id 200,000,000 + MyAnimeList
id and comes only from the MyAnimeList API (`fabula-anime`, secret `MAL_CLIENT_ID`), with `mal_score`, `mal_members`,
`mal_scorers`, `format`, `episodes`, `season`, and the studio in `director`. Japanese animated films are left out of
Movies. `fabula_deck` and `fabula_refine` take `p_kind` first; the old four-argument versions are movie-only wrappers.
Decks hide titles under 5/10 (IMDb for shows, MAL for anime) or with under 500 votes, and anime specials. Taste from
other kinds counts at a quarter weight. Records keep the `ortus.*` kinds with a `kind` field. Cards show `IMDb: x/10` or
`MAL: x.xx/10` (MAL blue). Refills: `fabula-tmdb` actions `ingest_shows` and `imdb` (kind `show` or `movie`), and
`fabula-anime` action `ingest`, all with the ingest token.

## Local state

Web: `fabula.cloud.v1` (setup link, picked up from the other apps), `fabula.kind`, `fabula.langs`, `fabula.genres` (with `.show` and `.anime` suffixes for those types), `fabula.sort`,
`fabula.tonight`, `fabula.name`, `fabula.match`; the friend page keeps `fabula.match.<code>` in sessionStorage. Cache prefix
`fabula-web-`. Mac: UserDefaults `fabula.langs`, `fabula.genres`; `$ROOT/ortus.json` is `{"logs", "swipes"}` (git noun
"film"). Both record kinds use `detachedId`: the row id is the TMDB id and `data` has no `id`. Mac code notes are in
[ortus.md](ortus.md). Language filters send English names (the `language` column); empty filters are sent as null.

## Look

Dark cinema: ground #17100D, surface #241914, raised #1F1511, line #3A2A22, ink #FBEDE5, muted #BFA294, faint #9C8173, accent
#E8673C (hover #F2875F), accent wash #3A2118 with text #FBD3C2, gold #F2C14E (text on gold #2A1A05), yes #4CC283, no #F0785C.
Fraunces 600/700 for titles and numbers, Inter 400/500/600 for everything else.
