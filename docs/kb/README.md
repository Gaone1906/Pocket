# Pocket knowledge base

This knowledge base is the full context for agents working on Pocket, a macOS menu-bar app built as a Swift package (macOS 14+, AppKit + SwiftUI). Start with **[handoff.md](handoff.md)**, which covers the current branches, unmerged work, and how this user wants work done. Then open the file for the area you're touching.

## Core

| File | Covers |
| --- | --- |
| [handoff.md](handoff.md) | Current state, branches, uncommitted work, open items, working agreements |
| [architecture.md](architecture.md) | App shell: lifecycle, `PocketApp`, catalog and factory, menu bar and dropdown layout, hotkeys, setup window, local HTTP server, logging, checklist for adding a new app |
| [operations.md](operations.md) | Build, install, signing, safe testing with `POCKET_DATA_DIR`, rendering views to PNG, logs, git and code conventions |
| [data-and-backups.md](data-and-backups.md) | `DataVault`: every persisted file and UserDefaults key, snapshots, recovery, Drive mirror, git sync to `pocket-data`, restore |
| [cloud-sync.md](cloud-sync.md) | Supabase records table, Mac `CloudSync`, the `web/` app on phone/iPad/laptops, setup and safety |
| [web-pages.md](web-pages.md) | The five GitHub Pages web apps (Routine for the parents, Orario, Aurelius, Kairos, Misura): what each shows and writes, themes, icons, storage keys, cache prefixes, setup link |
| [theme.md](theme.md) | `Board` design tokens, themes, embroidery backdrops, design language |

## Apps

| App | Shortcut | File |
| --- | --- | --- |
| WhatsApp, Slack, Spotify, Gmail, Outlook, Preparo | ⌥W ⌥S ⌥M ⌥G, none, none | [apps/web-apps.md](apps/web-apps.md) |
| Calendar | ⌥D | [apps/calendar.md](apps/calendar.md) |
| To-do | ⌥T | [apps/todo.md](apps/todo.md) |
| Aurelius (and its board, the visual reference for every other board) | ⌥P | [apps/pomodoro.md](apps/pomodoro.md) |
| Orario (weekly routines, built 2026-11-19) | ⌥O | [apps/schedule.md](apps/schedule.md) |
| Kairos (runs today's routines step by step, journal) | ⌥K | [apps/kairos.md](apps/kairos.md) |
| Misura (calories against daily, weekly and monthly goals) | ⌥E | [apps/misura.md](apps/misura.md) |
| Calculator | ⌥C | [apps/calculator.md](apps/calculator.md) |
| Scratchpad | ⌥N | [apps/scratchpad.md](apps/scratchpad.md) |
| System Stats | none | [apps/stats.md](apps/stats.md) |
| Matinee (District ticket hunter) | none | [apps/matinee.md](apps/matinee.md) |

Shortcuts are the defaults from `Catalog.swift`. The user can rebind them, or add more per app, in Pocket Settings → Shortcuts (or in setup).

## Elsewhere in the repo

- [../../README.md](../../README.md): user-facing overview and install.
- [../../CLAUDE.md](../../CLAUDE.md): the Aurelius HTTP API integration guide and rules to keep true.

## Keeping this current

The knowledge base is a read-through cache. Check it before reading code. When you change behaviour, update the matching file in the same commit series, and update [handoff.md](handoff.md) when branches or open items change.
