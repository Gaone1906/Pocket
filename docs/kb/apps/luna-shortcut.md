# The Luna Sync Shortcut

Built by hand in the Shortcuts app on the iPhone, once (Pranav found the first, 17-step version too fiddly, so the parsing moved into the database on 2026-11-21). `KEY` is the anon key from the setup link (never commit it).

Related: [luna.md](luna.md), `cloud/schema.sql` (`luna_ingest`).

## Shortcut "Luna Sync" (4 actions)

1. **Find Health Samples**: Type Sleep Analysis, Start Date is in the last 14 days, no limit.
2. **Repeat with Each**, holding one **Text**: `[Value]|[Start Date]|[End Date]|[Source]` from the Repeat Item, both dates formatted ISO 8601 with time.
3. **Combine Text**: Repeat Results with New Lines.
4. **Get Contents of URL**: `POST https://<project>.supabase.co/rest/v1/rpc/luna_ingest`, header `apikey: KEY`, JSON body `{"lines": <Combined Text>}`.

`public.luna_ingest(lines, type)` splits the lines on `|` and upserts one `sleep.sample` per line (id `<v>|<s>|<source>`, data `{s, e, v}`), skipping blank or short lines, and returns the count. With `type` set (for example `"type": "HRV"` or `"HR"` in the body), every line's `v` is that type and `q` is the first number in its first field, so a second loop over Heart Rate Variability samples can post the same line format. Every run re-sends 14 days; unchanged rows are not rewritten.

## Automation

Shortcuts → Automation → **Alarm** → Is Stopped → Run Immediately → Luna Sync (or **Sleep → Waking Up**). Health is readable only once the phone is unlocked, which these triggers guarantee.

## From the web app

The sync button opens `shortcuts://x-callback-url/run-shortcut?name=Luna%20Sync&x-success=<Luna url>#synced`; Shortcuts returns to Luna when it finishes, and Luna pulls and shows how many nights are new. In the Home Screen app (standalone), x-success would reopen the page in Safari instead, so there it runs `shortcuts://run-shortcut?name=Luna%20Sync` without a callback and pulls when the app becomes visible again.
