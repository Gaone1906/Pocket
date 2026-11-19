import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
trayShots(to: ProcessInfo.processInfo.environment["SHOTS"] ?? "/tmp/shots")
exit(0)
