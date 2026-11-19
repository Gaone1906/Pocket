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
| To-do | A simple list; the menu bar shows one open task at a time, moving to the next every minute |
| Schedule | Your weekly routines as a checklist (⌥O). The dropdown shows today's morning or night steps, each with a tip on how to do it; tick them off as you go. The expand button opens a window with a Schedule view of the week and a Calendar view that marks every day from 19 Nov as done, partly done or missed. Settings in the sidebar include **Change the schedule**, a weekly editor with a card for each morning and night of the week where you add, reorder and describe steps. Keep several routines (hair care, fitness, diet) and pick one or all from the dropdown filter. Backed up like everything else, to Google Drive and GitHub |
| Pomodoro | Focus, break and long-break timer; the countdown shows in the menu bar, gold while focusing and silver on a break. The expand button opens a board where finished sessions glow as dots until you file them as tally marks under a project; each project counts one stick per 25 minutes focused, struck through every five, with a shorter stick for the remainder. Right-click a project (or use its ⋯ menu) and choose **Declare a session…** to log time worked away from the laptop: pick the day, the minutes and, optionally, the start and end time. The heading switches to a Calendar table with a row per day and a cell per project. The left sidebar shows sessions and time focused today and all time; the settings button at the top right holds the timer lengths and eight pastel themes (Sage, Rose, Butter, Apricot, Sky, Lavender, Blush, Stone) a dark Bronze theme with metallic accents, and three embroidered themes on jet black fabric (Saffron tiger and azure dragon, Gold tiger and vermilion dragon, White tiger and jade dragon) with a stitched tiger, dragon, clouds and waves behind the board; themes tint the whole board and the timer |
| Calculator | Type or tap a calculation and see the answer as you go |
| Scratchpad | Notes in pages, with headings, bold, italic, underline, strikethrough and bulleted or numbered lists (type `- `, `1. ` or `# ` to start one) |
| System Stats | CPU, memory, disk, network and battery at a glance |
| Preparo | Opens Preparo, the local exam practice app at http://localhost:8960, in Ardia (or the default browser if Ardia is missing) |

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
- Each app has a keyboard shortcut that opens it from anywhere. The defaults are ⌥W WhatsApp, ⌥S Slack, ⌥M Spotify, ⌥G Gmail, ⌥O Schedule, ⌥D Calendar, ⌥T To-do, ⌥P Pomodoro, ⌥C Calculator and ⌥N Scratchpad; Outlook has no default shortcut. To change one, click it next to the app in setup and press the new keys; Delete clears it.
- Esc or clicking elsewhere hides the panel.
- Local tools and pages on `localhost` can drive the Pomodoro through `http://127.0.0.1:8977`: start, pause, resume and stop it with custom focus and break lengths, log sessions under a project, and read projects, sessions and totals. `GET /` lists the routes and [CLAUDE.md](CLAUDE.md) is the integration guide. Requests from other websites are refused.

## Your data

Pomodoro sessions, to-dos and schedules live in `~/Library/Application Support/Pocket`. Pocket protects them in four ways:

- **Daily copies.** Every save also writes a dated copy to `Backups/`. The last 30 days are kept, plus the first copy of every month, forever.
- **Safe loading.** If a file can't be read, Pocket moves it aside as `*.broken-*.json` and loads the newest good copy instead of starting empty.
- **Restore.** Board settings → Backup lists every copy. Restoring first keeps the current board aside, so it can be undone.
- **Off-machine copies.** Set `defaults write com.pranav.pocket pocket.backup.repo <private git url>` (and `pocket.backup.githubUser <login>` to use that `gh` account) and Pocket pushes the data to that repo about 90 seconds after each change. Keep that repo private. If the repo has sessions, to-dos or schedule check-offs this Mac has never had (a new Mac, or a second one), Pocket won't overwrite them: Backup settings offer to bring them in or, after a confirm, replace them. With Google Drive for Desktop installed, copies are also mirrored to `My Drive/Pocket Backups`; set `pocket.backup.folder` to mirror elsewhere.

## Performance

Web apps load only when they are first opened. The exception is WhatsApp and Slack, which stay connected so messages arrive. Pages that aren't realtime are throttled while hidden, and Spotify unloads after 30 minutes idle if it isn't playing. If you don't pick any web apps, Pocket uses only a few megabytes.

## Optional: one-time codes

When this is turned on in setup, Pocket shows verification codes from Messages in the menu bar as they arrive.

- It needs **Full Disk Access** for Pocket: System Settings → Privacy & Security → Full Disk Access.
- To also catch codes from Gmail, save a Google OAuth desktop client to `~/Library/Application Support/Pocket/google-client.json` as `{"id": "…", "secret": "…"}`. Then choose "Add Gmail account for codes…" from the right-click menu.

## Signing

`install.sh` signs with your first Apple Development identity if you have one, otherwise ad hoc. To pick an identity, set `POCKET_SIGN_IDENTITY`. With an ad hoc signature, macOS may ask again for permissions after each rebuild.

Logs are written to `~/Library/Logs/pocket.log`.
