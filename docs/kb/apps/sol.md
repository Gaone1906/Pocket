# Sol (formula cards, web only)

Sol is the swipe deck for revising exam formulas, at `https://gaone1906.github.io/Pocket/sol/` (`web/sol/`). It is the web side of Sol, the Butter-themed sun-horse rebrand of Preparo (Gaone1906/Preparo, which stays a separate repo and app on the Mac). Built 2026-11-20 at Pranav's request.

## How it works

- One card at a time. The front is a situation with named values and one question; the back is the answer and an optional quick example.
- Tap flips. Swipe left = confident, swipe right = not yet. Holding the card for 0.55 s shakes it and puts a Mastered tag with Undo on it; swiping it away after that hides the card for good. Keyboard: Enter flips, ← and → sort, M toggles the tag.
- A not-yet card comes back five cards later in the same run (once) and is due again tomorrow. Confident cards climb a ladder of 1, 3, 7, 14 and 30 days. Every deck puts due and unseen cards first, each part shuffled.
- The menu holds, in order: Shuffle all formulas, Not yet (only when there are any), sections that open one at a time into "All of <section>" and their topics, then Mastered (a sheet where any card can be brought back) and the sync line. An exam picker appears when the cards hold more than one exam.

## Data

- Cards are data, not code. They live in the shared Supabase table as `sol.card` records (id = card id, e.g. `cat-pct-02`), each `{id, exam, section, topic, situation, ask, answer, example}`. `web/sol/cards.js` is a bundled copy of the CAT Quant deck so the app works before it is connected; `sol.card` rows are merged over it by id (the table wins, and new ids or exams just appear).
- Progress is one `sol.mark` record per card: `{id, box (0-5), due (yyyy-MM-dd or null), mastered, updated}`. Box 0 with a mark means "not yet".
- The Mac's CloudSync ignores both kinds; nothing on the Mac reads them yet.
- Local state key `sol.cloud.v1`; it borrows the setup link from any other Pocket web app in the same browser. Per-device prefs: `sol.exam`, `sol.pick`, `sol.guided`. Cache prefix `sol-web-` (`sol-web-v1`).

## Card source

The CAT Quant cards (211) were rewritten from Pranav's "CAT Quant formula book" PDF, one fact per card. The Basics section (sums of series and algebraic identities) comes first in the menu, at Pranav's request. To change or add cards, edit the `sol.card` rows (and `cards.js` if the bundled copy should follow).

## Look

Butter: ground #FBF5DF, card #FFF8DC, tile #FCF0B8, gold #C99A0E, ink #2B2410, not-yet clay #A4441F. Bricolage Grotesque headings, Geist body, STIX Two Text for formulas. Icon: the S1 gold galloping sun horse.
