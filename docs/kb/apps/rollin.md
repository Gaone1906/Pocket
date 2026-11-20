# Rollin

## What it is
A hidden ticker. New WhatsApp messages and one-time codes roll right to left across the menu bar, like a stock ticker,
and the strip disappears once the last one has rolled off. The strip can't be clicked; it is only there to be read.

- **Catalog:** `id: "rollin"`, symbol `chart.line.uptrend.xyaxis`, no shortcut, `shelf: "Experimental"`. When an
  existing setup first sees it, `Layout.home` puts it on the user's shelf named Experimental (any case) instead of
  Unorganized; without that shelf it stays in Unorganized.
- **Dropdown:** open it from its shelf. Fixed 340×330, Pocket theme. A master **Rollin** switch, then an **Apps** card
  with one switch per feed (WhatsApp, One-time codes), and **Roll a sample**, which rolls a test message and code.
- **Ticker:** its own `NSStatusItem`, 320 pt wide, made on the first item and removed 1.5 s after the strip empties.
  Everything is upper case, in heavy condensed SF sized so capitals fill 64% of the menu bar's height: a coloured
  dot, the sender, then the text in the secondary colour (a code in heavy monospaced digits). Items move at 70 pt/s
  with a 64 pt gap, each passes twice (once for the sample), and a pass is not repeated while 4 or more are queued. The
  edges fade over 14 pt. Each item is drawn once to a bitmap the height of the menu bar in its
  appearance and moved by a Core Animation slide, so a rolling strip costs no CPU per frame.

## Feeds
| Feed | Source | Notes |
| --- | --- | --- |
| `whatsapp` | `WebApp.userContentController`, after Pocket posts the WhatsApp notification | Not rolled while the WhatsApp panel is open and focused, the same rule as notifications. Needs WhatsApp turned on in Pocket. |
| `otp` | `OtpWatcher.show` (Messages via `chat.db`, and Gmail accounts from `MailWatcher`) | `syncOtp` runs the watcher when the One-time codes setting is on **or** Rollin wants codes. With the setting off, the green click-to-copy code is not shown; the code only rolls. Messages needs Full Disk Access, as before. |

Text is flattened to one line (title 60, body 160 characters). The same feed, title and body within 10 s roll once.
To add a feed, give it a `RollinFeed.all` row and call `RollinStore.shared.push("<id>", title:, body:)` where it arrives.

## Settings
UserDefaults: `rollin.on` (master, default on) and `rollin.feed.<id>` (default on). Turning Rollin or a feed off clears
what is rolling for it. Turning the app off in setup removes the strip and stops feeding it.

## Files
All in `Sources/Pocket/RollinApp.swift`: `RollinFeed`, `RollinItem`, `RollinStore` (settings, `push`, `sample`, `wants`),
`RollinTicker` (status item, layers, `render`), `RollinStrip`, `RollinApp`, `RollinView`.

## Logs
`rollin attached|detached|switched|feed switched|shown|rolling|cleared|hidden|skipped`. Message text is never logged,
only the feed, length and queue.
