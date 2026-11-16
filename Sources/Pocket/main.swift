import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
app.delegate = AppDelegate.shared
app.run()
