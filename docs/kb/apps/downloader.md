# Downloader

## What it is
Paste a link and aria2 downloads it to `~/Downloads`, resuming and retrying on its own. While anything downloads, the
menu-bar icon is replaced by the overall percentage; it returns to the glyph when nothing is running.

- **Catalog:** `id: "downloader"`, symbol `arrow.down.circle`, shortcut ⌥- (`kVK_ANSI_Minus`), `pinnedByDefault` so
  existing setups get it in the menu bar (the percentage needs a status item).
- **Needs** `aria2c` from Homebrew (`/opt/homebrew/bin`, `/usr/local/bin` or `/usr/bin`). Without it the panel says
  `brew install aria2` and logs `downloader aria2 missing`.
- **Panel:** a link field (pre-filled from the clipboard on open when it holds a single http, https, ftp or magnet link,
  and empty), a download button, and one card per download with progress, size, speed and time left. Pause/resume,
  reveal in Finder (done) and remove (✕) per card; "Clear finished" at the bottom.

## How it runs aria2
`DownloaderModel.start()` launches one `aria2c` child per Pocket process with JSON-RPC on `127.0.0.1:6809`, a random
`--rpc-secret` per launch (aria2 masks it in `ps`), and `--stop-with-process=<pocket pid>` so it never outlives Pocket.
Options: 4 connections per server and 4 splits (8 trips 429 rate limits on some hosts), `--max-tries=0`,
`--retry-wait=5`, `--continue`, `--auto-file-renaming=false`, `--file-allocation=none`, 3 concurrent downloads.
Unfinished downloads persist in `PocketData.root/Downloader/aria2.session` (saved every 15 s and on stop) and are
reloaded with `--input-file` on the next launch.

- Polls `system.multicall` (tellActive, tellWaiting, tellStopped) once a second.
- Holds `ProcessInfo.beginActivity(.idleSystemSleepDisabled)` while any download is active.
- Notifies on complete and on error (`userInfo["app"] = "downloader"`, so tapping opens the panel).
- **Adopting a browser download:** when the link's last path component matches `~/Downloads/<name>.crdownload` and
  `<name>` doesn't exist yet, the partial file is copied to `<name>` (APFS clone) and aria2 continues from its end.
  Cancel the browser's copy afterwards.

## Local API
`GET /downloader` lists downloads (`id, name, status, total, done, speed, error, path`), `percent` (or null) and
`problem`. `POST /downloader` with `{"url": "..."}` starts one and answers `202`; a bad body is `400`, a disabled app
`409`.

## Files
| Symbol | File | Role |
| --- | --- | --- |
| `DownloadItem`, `DownloaderModel` | `DownloaderModel.swift` | aria2 process, RPC client, polling, notifications, sleep hold |
| `DownloaderView`, `DownloadRow`, `DownloaderDraft`, `DownloaderApp` | `DownloaderApp.swift` | panel, clipboard pre-fill, bar title, API hooks |

## Logs
`downloader aria2 started|exited|stopped|launch failed|missing`, `downloader added|add failed|add rejected`,
`downloader status gid= name= from= to= bytes=`, `downloader prefilled|prefill skipped reason=`,
`downloader adopted browser partial`, `downloader keeping mac awake|released sleep hold`, `downloader remote add source=`.
