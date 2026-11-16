# Pocket

Small apps that live in the macOS menu bar. Click an icon and the app drops down in a panel under it; click away and it tucks itself back.

| App | What it does |
| --- | --- |
| WhatsApp | WhatsApp Web, kept connected for messages and calls |
| Slack | Slack with notifications and huddles |
| Spotify | Web player that keeps playing when hidden |
| Gmail | Unread count in the menu bar, new-mail notifications |
| Outlook | Outlook mail for work or personal Microsoft accounts |
| Calendar | Month view of the events in your Mac's Calendar app |
| To-do | A simple list; the next task shows in the menu bar |
| Pomodoro | Focus, break and long-break timer; the countdown shows in the menu bar, gold while focusing and silver on a break. The expand button opens a board where finished sessions glow as dots until you file them as tally marks under a project; each project counts one stick per 25 minutes focused, struck through every five, with a shorter stick for the remainder. The heading switches to a Calendar table with a row per day and a cell per project |
| Calculator | Type or tap a calculation and see the answer as you go |
| Scratchpad | Notes in pages, with headings, bold, italic, underline, strikethrough and bulleted or numbered lists (type `- `, `1. ` or `# ` to start one) |
| System Stats | CPU, memory, disk, network and battery at a glance |

## Install

Needs macOS 14 or later and the Xcode command line tools (`xcode-select --install`).

```bash
git clone https://github.com/Gaone1906/Pocket.git
cd Pocket
./scripts/install.sh
```

This builds Pocket, puts `Pocket.app` in `~/Applications` and opens it. Run the script again to update.

The first launch opens a setup window. In it you:

1. Pick the apps you want and choose where each one goes: directly in the menu bar or in the dropdown.
2. Sign in to just the web apps you picked.

## Using it

- The thin line in the menu bar opens the dropdown. Drag icons between the **Menu bar** and **Dropdown** rows to rearrange them.
- Right-click any icon to move it, rerun setup, or quit.
- Each app has a keyboard shortcut that opens it from anywhere. The defaults are ⌥W WhatsApp, ⌥S Slack, ⌥M Spotify, ⌥G Gmail, ⌥O Outlook, ⌥D Calendar, ⌥T To-do, ⌥P Pomodoro, ⌥C Calculator and ⌥N Scratchpad. To change one, click it next to the app in setup and press the new keys; Delete clears it.
- Esc or clicking elsewhere hides the panel.
- Local tools and pages on `localhost` can drive the Pomodoro through `http://127.0.0.1:8977`: start, pause, resume and stop it with custom focus and break lengths, log sessions under a project, and read projects, sessions and totals. `GET /` lists the routes and [CLAUDE.md](CLAUDE.md) is the integration guide. Requests from other websites are refused.

## Performance

Web apps load only when they are first opened. The exception is WhatsApp and Slack, which stay connected so messages arrive. Pages that aren't realtime are throttled while hidden, and Spotify unloads after 30 minutes idle if it isn't playing. If you don't pick any web apps, Pocket uses only a few megabytes.

## Optional: one-time codes

When this is turned on in setup, Pocket shows verification codes from Messages in the menu bar as they arrive.

- It needs **Full Disk Access** for Pocket: System Settings → Privacy & Security → Full Disk Access.
- To also catch codes from Gmail, save a Google OAuth desktop client to `~/Library/Application Support/Pocket/google-client.json` as `{"id": "…", "secret": "…"}`. Then choose "Add Gmail account for codes…" from the right-click menu.

## Signing

`install.sh` signs with your first Apple Development identity if you have one, otherwise ad hoc. To pick an identity, set `POCKET_SIGN_IDENTITY`. With an ad hoc signature, macOS may ask again for permissions after each rebuild.

Logs are written to `~/Library/Logs/pocket.log`.
