# System Stats

## What it is
A glanceable system monitor.

- **Catalog:** `id: "stats"`, name "System Stats", symbol `gauge.with.dots.needle.33percent`, **no default shortcut** (`hotKey: nil`; the user can assign one in setup).
- **Panel:** fixed 340×420 (`resizable = false`). It shows rows for:
  - **CPU:** % and a meter;
  - **Memory:** "used GB / total GB", a meter, and "Pressure N%";
  - **Disk:** "X GB free", a meter of the used fraction, and "of Y GB";
  - **Network:** "↓ rate ↑ rate";
  - **Battery:** %, a meter, and "Charging", "On power" or "On battery". It's hidden on Macs without an internal battery.

  Below a divider are a **"Show CPU in menu bar"** switch and a footer with "Uptime Xd Yh Zm" and "Thermal Nominal/Fair/Serious/Critical".
- **Menu bar:** the normal glyph. With "Show CPU in menu bar" on, `barTitle()` adds `" NN%"` in the monospaced-digit menu-bar font. It only appears if the app is placed in the **menu bar**; in the dropdown it isn't visible anywhere.
- **Meter colours** (`meterColor`): green below 70%, orange from 70%, red at 90% and above.

## Files
All in `Sources/Pocket/StatsApp.swift`.

| Symbol | Role |
| --- | --- |
| `BatteryReading` | `percent`, `charging`, `onAC` |
| `DiskReading` | `free`, `total`, `usedFraction` |
| `StatsSampler` | Stateless readers, plus the deltas needed for rates: `cpuPercent()`, `resetCPU()`, `memory()`, `memoryPressurePercent()`, `disk()`, `network()`, `resetNetwork()`, `battery()`, `bootDate()`, and `report(_:code:)`, which logs each failure kind once |
| `StatsModel` (`ObservableObject`) | Published readings, plus `cpuInBar`, which persists to UserDefaults and calls `onToggle` |
| `StatsApp` | `PocketApp` subclass. Has `panelTimer` (2 s) and `barTimer` (5 s), plus `start`, `stop`, `didShow`, `didHide`, `barTitle`, `barToggled`, `startBarTimer`, `sampleBar` and `sampleAll` |
| `formatBytes`, `formatRate`, `formatUptime`, `thermalLabel`, `meterColor`, `Meter`, `MeterRow`, `StatsView` | Private formatting and views. Bytes are shown in GiB (labelled "GB"): 1 decimal below 100, none from 100. Rates are in KiB/s ("KB/s"), switching to MiB/s ("MB/s") at 1024 KiB/s |

## Data
- **UserDefaults `stats.cpuInBar`** (Bool, default false). That's the only persisted state.
- Nothing goes through `DataVault`, and there are no files.

## Sources and sampling

| Metric | Source | Computation |
| --- | --- | --- |
| CPU | `host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO)` | Ticks (user, system, idle, nice) since the previous sample. `(user+system+nice)/total*100`, clamped 0–100. It uses wrapping `&-` on the UInt32 ticks. It needs a previous sample, so the first call returns `nil` |
| Memory used | `host_statistics64(HOST_VM_INFO64)` | `(internal_page_count − purgeable_count + wire_count + compressor_page_count) × vm_kernel_page_size`. That's app memory + wired + compressed, which approximates Activity Monitor's "Memory Used" |
| Memory total | `ProcessInfo.physicalMemory` | |
| Pressure | `sysctlbyname("kern.memorystatus_level")` | `100 − level`, clamped. The level is the percentage of memory available, so this is a "pressure %", not Activity Monitor's green, yellow and red graph |
| Disk | `URL("/").resourceValues([.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey])` | "Free" includes purgeable space, like Finder's "Available", for the boot volume only |
| Network | `getifaddrs`, `AF_LINK` entries named `en*` | Sums `if_data.ifi_ibytes`/`ifi_obytes` deltas across `en*` interfaces, divided by the elapsed seconds. The UInt32 counters wrap at 4 GiB; `delta()` handles one wrap. It excludes `utun*` (VPN), `bridge*`, `awdl*` and `lo0`, so VPN traffic is counted once, on the physical `en` interface |
| Battery | `IOPSCopyPowerSourcesInfo` / `IOPSCopyPowerSourcesList` / `IOPSGetPowerSourceDescription` | The first source with `kIOPSTypeKey == InternalBattery`. `percent = current*100/max`. `charging` = `kIOPSIsChargingKey`. `onAC` = the power-source state is `AC Power`. `nil` on desktops |
| Uptime | `sysctlbyname("kern.boottime")` | now − boot |
| Thermal | `ProcessInfo.thermalState` | |

## Flows
- **Start** (`start`): if `cpuInBar`, `startBarTimer()`. That resets the CPU baseline, primes one sample, then calls `sampleBar` every 5 s (1 s tolerance), on `RunLoop.main` in `.common` mode, so it keeps ticking during menu tracking.
- **`sampleBar`** does nothing while the panel is shown (the panel timer covers it). Otherwise it reads only CPU, sets `hasCPU`, and calls `changed()`, which makes `BarController.refresh` redraw the bar title.
- **Open** (`didShow`):
  1. `resetNetwork()`.
  2. `sampleAll()` immediately.
  3. Start the 2 s `panelTimer` (0.5 s tolerance, `.common` mode).

  `sampleAll` reads every source, keeping the previous memory pressure and uptime values on failure. It calls `changed()` if `cpuInBar`.
- **First readings on open:**
  - network shows the previous values (0 on the first open) until the second sample, 2 s later, because the baseline was just reset;
  - CPU on the first sample uses the previous baseline. With the bar off, that's the last panel sample, which could be hours old, so the first CPU figure is a long-run average. It corrects at 2 s.
- **Hide** (`didHide`): stop the panel timer and reset the network. If `cpuInBar`, reset and prime the CPU, so the next bar sample covers a clean 5 s.
- **Toggle** (`cpuInBar` `didSet`): saves to UserDefaults, then `barToggled` starts or stops the bar timer, logs, and calls `changed()`.
- **Stop** (when disabled, or on quit): invalidates both timers.
- **Wake:** nothing special. Timers resume, and the first CPU or network delta after sleep spans the sleep (CPU ticks don't advance much while asleep; network is divided by real elapsed seconds, so it averages low).

## Integrations
Mach host APIs, sysctl, BSD `getifaddrs`, IOKit power sources (`import IOKit.ps`). None need entitlements or TCC permissions.

## Logging
- `pocket stats failure kind=<kind> code=<code>`, logged **once per kind per `StatsSampler` lifetime** (`reportedFailures`). The kinds are:
  - `host_statistics.cpu`;
  - `host_statistics64.vm`;
  - `sysctl.memorystatus_level`;
  - `disk.capacity_missing`;
  - `disk.resource_values`;
  - `getifaddrs`;
  - `iops.snapshot`;
  - `iops.list`;
  - `sysctl.boottime`.
- `pocket stats cpu in bar app=stats enabled=<bool>`.
- Samples themselves aren't logged; they're pure reads on a timer.

## Gotchas
- **The battery meter colour is inverted.** `MeterRow` always uses `meterColor(fraction)`, which is meant for "usage", so a **full battery (≥ 90%) is drawn red** and a nearly empty one green. `Meter` has an unused `tint` parameter that was presumably meant for this. A fix would pass a battery-specific tint, e.g. `1 - fraction` into `meterColor`, or a fixed green.
- **`cpuInBar` in the dropdown.** Turning it on while Stats is in the dropdown still runs the 5 s bar timer, but the title has nowhere to show (`BarController` only renders bar items).
- **The `GB`/`KB` labels are binary units** (GiB and KiB), so they read slightly low compared with Finder's decimal GB.
- **Only one sampler.** `StatsSampler` keeps the CPU baseline shared between the bar and panel paths; the resets in `didHide` and `startBarTimer` exist to keep the two from mixing intervals.
- **History:** it was added in a single commit (`ba22b4b`), with no later fixes.

## How to change it safely
- **Add a metric:**
  1. Add a reader to `StatsSampler` that returns an optional and calls `report("<kind>", code:)` on failure.
  2. Add a `@Published` field to `StatsModel`.
  3. Assign it in `sampleAll`.
  4. Render it in `StatsView`. The panel height (420) is fixed, so increase `defaultSize` if needed.
- **Add a menu-bar figure** (memory, for example): follow the `cpuInBar` pattern. Use a new UserDefaults key `stats.<x>InBar`, a toggle, `barTitle` composition and the bar timer.
- **Change the cadence:** the 2 s panel and 5 s bar intervals are literals in `didShow` and `startBarTimer`.
- **Testing:** there's no data to protect; it's read-only. You can run it under `swift run` safely, but the rest of Pocket would still touch real data unless `POCKET_DATA_DIR` is set.

## Open questions / known gaps
- No per-process list, no history graphs, no GPU, and no multiple disks.
- The network rate ignores non-`en` interfaces. Thunderbolt and USB Ethernet adapters are named `en*`, so they're counted. iPhone USB tethering may use a different interface name and be missed (unverified).
