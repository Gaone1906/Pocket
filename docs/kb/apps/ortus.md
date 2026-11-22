# Ortus → Fabula (Mac notes)

Ortus, the motivation app, was replaced by Fabula, the movie recommender, on 2026-11-22. The spec, data contract, deck RPC and
look are in [fabula.md](fabula.md); this page only covers how the Mac half is built. The app id `ortus`, ⌥7, `$ROOT/ortus.json`,
the `DataVault` name `ortus` and the window autosave name `ortus.board` stayed; everything people see says Fabula.

## Files

- `OrtusModel.swift`: `FabulaFilm` (a deck card, also built from a log or swipe row or a `fabula-tmdb` `add` answer),
  `FabulaEntry` (one `ortus.log` or `ortus.swipe` row kept as loose JSON so it round-trips untouched), `OrtusStore` (the only
  writer of `ortus.json`), `FabulaDeck` (cards, undo history, Language and Genre filters), `FabulaNav` (window tab, Tonight's
  pick, the rating sheet), `FabulaSearch` (debounced TMDB search for "+ Add film"), `FabulaNet` (POSTs to
  `{url}/rest/v1/rpc/fabula_deck`, `rpc/fabula_refine`, `{url}/functions/v1/fabula-tmdb` and `fabula-ai` with the url and anon
  key `CloudSync` holds; `function` takes a `timeout`, 60 s for mood rounds and 90 s for taste), `FabulaTaste` (the `taste`
  answer: summary, more, less), `FabulaRefiner` (pick, list and done stages, the session's shown ids, ratings and unseen
  counts) and `FabulaAI` (mood, notes, shown ids, rounds, the chosen film).
- `OrtusApp.swift`: the dropdown (`FabulaGlance`, 380×600), the window (`FabulaRoot`: 84px rail with Recommend, Watchlist,
  Log, Refiner and AI Mode; 1100×720, min 980×640), the swipe card (`FabulaStack`, `FabulaMotion`), keys (`FabulaKeys`, a local key monitor scoped
  to its own window and silent while a text field has focus), Tonight's pick, the rating sheet, Watchlist and Log.
- `OrtusModes.swift`: Refiner (`FabulaRefinerPick` with `FabulaFlow` chip rows, `FabulaRefinerList` with a 720 pt column and
  `FabulaScoreBar`, a 1 to 10 drag bar that stays grey until touched, `FabulaRefinerDone`) and AI Mode (`FabulaAIMood`,
  `FabulaAIResults`: bubbles of the last two turns, a 2×2 grid of cards, the gold "Watch … tonight" bar, the fine-tune field
  that sends on Return). Loading states are pulsing placeholder cards (`FabulaPulse`).
- `OrtusLogo.swift`: the rooster logo as base64 JPEG. The menu-bar glyph is a film reel (`Glyphs.ortus`).

## Data on the Mac

`$ROOT/ortus.json` is `{"logs": [...], "swipes": [...], "unseen": [...]}`, git noun "film", synced by the `ortus`
`CloudDocument` with `ortus.log` (`logs`), `ortus.swipe` (`swipes`) and `ortus.unseen` (`unseen`, `{tmdb, title, year, at,
updated}`, written only by Refiner). A file without `unseen` loads as an empty list and gains the key on the next save. All three
collections use `detachedId`: the row id (the TMDB id as a string) is
kept as `id` locally and left out of `data` in the cloud, so rows written by the web or by `fabula-tmdb` `import` without an
`id` field still merge. Undo and Remove delete the local item and sync pushes `deleted: true`; a "Bring them in" merge is a
union by id where the newer `updated` wins. An old library-shaped file is kept aside (`ortus-before-fabula-*`) and replaced
with the new shape on first load. `CloudSync` now remembers the record kinds it knows (`kinds` in `cloud-state.json`), does
one full pull when a kind is new, and forgets `seen` keys of retired kinds such as `ortus.quote`.

## Behaviour

- The deck asks for 20 films with `p_exclude` = cards on screen plus every logged or swiped id, and again when 5 are left.
  Without a cloud link, or offline with no cards, the card shows the logo and a single Retry.
- Drag rotates the card by `dx / 18`°, fades YES / NOPE / SEEN IT in over 90 pt and commits past 110 pt; otherwise it springs
  back. ← no, → yes, ↑ seen it, ⌘Z undo. Holding Space or pressing the card 0.6 s shakes it for 0.5 s, turns the border
  gold and records a superlike, which opens Tonight's pick ("Watch this tonight" opens the film's TMDB watch page for India).
- Seen it writes the `seen` swipe at once; the rating sheet then adds the log (Save to Log) or nothing (Skip rating). From
  the Watchlist or "+ Add film", the swipe is written only when the sheet is answered. Logged films open the same sheet to
  edit, with Delete in place of Skip.
- Refiner: Start refining calls `fabula_refine` (null for Any, `p_limit` 10, `p_exclude` = every id shown this session).
  Continue and Stop save the batch first: a touched bar is `saveLog(..., origin: "refiner")` (data `source: "refiner"`), the
  rest go to `markUnseen`. Then `CloudSync.syncNow(then:)` runs a full sync and only its callback calls the server, so the
  rows are in the cloud first. Stop marks the deck stale (`FabulaDeck.markStale`), so the next `refill` from Recommend or the
  dropdown reloads from scratch, and calls `fabula-ai` `taste` with the ids rated this session (skipped when none).
- AI Mode: each round posts `fabula-ai` `mood` with the mood text, all notes and every id shown so far; a failed round keeps
  the previous cards and shows the error under them. "Watch … tonight" goes through `FabulaDeck.superlike` (a `super` swipe,
  the tonight strip and Tonight's pick).
- Filters persist in UserDefaults `fabula.langs` and `fabula.genres` (English language names, TMDB genre names with
  "Sci-fi"); the window tab in `fabula.tab`, the Log sort in `fabula.sort`.
