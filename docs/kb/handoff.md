# Handoff: where Pocket stands

This is a snapshot as of 2026-11-19. Read it first, then [README.md](README.md) for the map.

## Branches and checkouts

| Where | Branch | State |
| --- | --- | --- |
| `~/Desktop/workspace/personal/pocket` | `add-matinee` | Main checkout. It has 3 commits that are not on `main`. The branch has no upstream, but its commits are pushed as part of `add-schedule`. It also has **uncommitted** work: `Embroidery.swift`, `CLAUDE.md` and `README.md` edits, plus three new `Resources/Embroidery/fabric-*.jpg` files. See [theme.md](theme.md). |
| `~/Desktop/workspace/personal/pocket-schedule` | `add-schedule` | Worktree cut from `add-matinee`, so it contains the matinee commits plus the Schedule app. Pushed to `origin/add-schedule`. Fast-forwarded into `main` on 2026-11-19. |
| `origin/main` | `main` | Same as `add-schedule` (515ce71 and later): includes Matinee, Schedule and this KB. |

The installed app (`~/Applications/Pocket.app`) was built from `add-schedule`, with the uncommitted embroidery files copied in temporarily. If you reinstall from a clean `add-schedule`, the three new embroidered themes disappear until that work is committed.

Everything is now on `main`. The embroidery work still needs committing on its own, on top of `main`.

## Data and backups now

- **Live data:** `~/Library/Application Support/Pocket/`, which holds `Pomodoro/board.json`, `todos.json` and `schedule.json`. See [data-and-backups.md](data-and-backups.md).
- **Git backup:** the private repo `Gaone1906/pocket-data`. `schedule.json` was first pushed there on 2026-11-19.
- **Google Drive mirror:** inactive (`mirror=none`), because Google Drive for Desktop is not installed on this Mac. Install it, or set `defaults write com.pranav.pocket pocket.backup.folder <path>`.

## Schedule app

- Built on 2026-11-19 from the "Weekly Hair Routine" artifact. It starts on 19 Nov 2026 with the hair-care routine seeded. Full detail is in [apps/schedule.md](apps/schedule.md).
- ⌥O was moved from Outlook to Schedule by a one-time `claimsHotKey` migration.
- The board window and the editor were verified only from offscreen renders, never clicked live. Computer use could not reach the Pocket window.
- Open polish items the user may raise:
  - The "This week" toggle label stays the same when paging to another week.
  - A partial day shows a half dot in the day strip, not red.
  - Long steps wrap at narrow widths.
- Data-model risks, detailed in schedule.md:
  - Past days are scored against the *current* plan, so adding a step marks old days of that weekday as missed.
  - Merging only adds routines and check-offs it hasn't seen. Plan edits made on another Mac are lost.
  - A fresh Mac seeds its own "Hair care" routine, so bringing in data from GitHub duplicates it.

## Misura

- Calorie tracker built on 2026-11-19 on `claude/project-thread-ledxxq`, Mac and web (`/Pocket/misura/`). Detail in [apps/misura.md](apps/misura.md).
- The web app was tested against `web/dev/server.mjs`. The Mac code is checked by a `swift build` on Pranav's Mac before merge.
- It starts with no plan; Pranav fills in his own numbers on first open.

## Matinee

- **Where the code lives:** Pocket only supervises a Node engine, through `MatineeApp.swift` (a `WebApp` subclass, panel at `127.0.0.1:47811`). The real code is in the separate local repo `~/Files/Personal Projects/Matinee`, which has **no git remote**. Its `hunts.json` is not backed up anywhere.
- **Known bugs**, detailed in [apps/matinee.md](apps/matinee.md):
  - The `Matinee (!)` attention badge never shows.
  - Quitting Pocket drops held seats mid-checkout.
  - `engine-stdout.log` grows forever.
  - A headless Chromium login check runs about every 10 min.

## Known bugs found during the KB deep dive (not fixed)

Each one is detailed in the linked file.

| Area | Bug | File |
| --- | --- | --- |
| Backups | **Bring them in** skips any store not yet created (`reason=no-store`). The board store loads lazily, and the to-do store exists only while To-do is enabled. | [data-and-backups.md](data-and-backups.md) |
| Backups | Launch re-snapshots any valid JSON without checking it decodes, so a malformed file can replace today's snapshot. Mirror copies, keep-aside files and broken files are never pruned. | [data-and-backups.md](data-and-backups.md) |
| Scratchpad | No vault protection: it ignores `POCKET_DATA_DIR`, has no snapshots and no sync. An unreadable `pages.json` is overwritten with a fresh index. The last 0.8 s of typing can be lost on quit. | [apps/scratchpad.md](apps/scratchpad.md) |
| Stats | Battery colours are inverted: full shows red, empty shows green. | [apps/stats.md](apps/stats.md) |
| Web apps | The unread-badge regex matches any number in brackets, e.g. a Spotify title "(2019)". | [apps/web-apps.md](apps/web-apps.md) |
| Aurelius | `/pomodoro/start` without `project` clears the running label. The API sample in CLAUDE.md is missing `hold` and `waiting`. `board.json` dates are seconds since 2001, not ISO. | [apps/pomodoro.md](apps/pomodoro.md) |
| Schedule | Opening and closing the editor each log twice. | [apps/schedule.md](apps/schedule.md) |
| Matinee | See the Matinee section above. | [apps/matinee.md](apps/matinee.md) |

## Working agreements with this user

- **Zero comments in code.** Logs use `note("area event key=value …")` with identifiers.
- **Commits:** all lowercase, one line, no co-author trailer. One commit per atomic unit. Push once, at the end.
- **Agents:** split work across subagents and keep the main session orchestrating. Never let two agents edit the same file.
- **Scratch runs:** `POCKET_DATA_DIR` does **not** isolate the Drive mirror, Scratchpad, UserDefaults or the log. Before any scratch run, read operations.md for what to point elsewhere.
- **Real data:** never test against it. Use `POCKET_DATA_DIR` with scratch data, and render views to PNG for visual checks. See [operations.md](operations.md).
- **Design taste:** clean, minimal, elegant, matching the Aurelius board. No legends or explanatory chrome. Use pastel colours, not vibrant ones.
