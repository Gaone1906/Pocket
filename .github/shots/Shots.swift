import AppKit
import SwiftUI

func render<V: View>(_ view: V, size: CGSize, appearance: NSAppearance.Name, to path: String) {
    let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
    host.frame = NSRect(origin: .zero, size: size)
    host.appearance = NSAppearance(named: appearance)
    let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = host
    host.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.4))
    host.layoutSubtreeIfNeeded()
    guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return print("no bitmap \(path)") }
    host.cacheDisplay(in: host.bounds, to: rep)
    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    print("wrote \(path)")
}

func seed(bar: [String], shelves: [Shelf], collapsed: [String] = []) {
    let d = UserDefaults.standard
    d.set(true, forKey: "setup.done")
    d.set(catalog.map(\.id), forKey: "layout.offered")
    d.set(bar, forKey: "layout.bar")
    d.set(shelves.flatMap(\.apps), forKey: "layout.tray")
    d.set(try! JSONEncoder().encode(shelves), forKey: "layout.shelves")
    d.set(collapsed, forKey: "layout.collapsed")
}

func tray(_ name: String, theme: String, editing: Bool = false, out: String) {
    BoardThemeStore.shared.theme = BoardTheme.all.first { $0.id == theme } ?? BoardTheme.all[0]
    var measured: CGFloat = 600
    let probe = TrayView(layout: Layout.shared, themes: BoardThemeStore.shared, open: { _ in }, fit: { measured = $0 }, editing: editing)
    render(probe, size: CGSize(width: TrayView.width, height: 1400), appearance: (BoardThemeStore.shared.theme.isDark ? .darkAqua : .aqua), to: "/tmp/probe.png")
    let view = TrayView(layout: Layout.shared, themes: BoardThemeStore.shared, open: { _ in }, fit: { _ in }, editing: editing)
    render(view.clipShape(RoundedRectangle(cornerRadius: 14)), size: CGSize(width: TrayView.width, height: min(measured, 1000)), appearance: (BoardThemeStore.shared.theme.isDark ? .darkAqua : .aqua), to: "\(out)/\(name).png")
}

func trayShots(to out: String) {
    try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
    seed(bar: ["pomodoro", "schedule"], shelves: [
        Shelf(id: "s-comms", name: "Communication", apps: ["gmail", "whatsapp", "slack", "outlook"]),
        Shelf(id: "s-focus", name: "Focus", apps: ["todo", "calendar", "scratchpad", "preparo"]),
        Shelf(id: Shelf.unorganizedId, name: Shelf.unorganizedName, apps: ["calculator", "stats", "spotify", "matinee"]),
    ])
    let layout = Layout.shared
    tray("1-shelves-bronze", theme: "bronze", out: out)
    tray("2-shelves-sage", theme: "sage", out: out)
    tray("3-organize-bronze", theme: "bronze", editing: true, out: out)
    tray("4-shelves-lavender", theme: "lavender", out: out)
    layout.toggleCollapsed("s-comms")
    tray("5-collapsed-bronze", theme: "bronze", out: out)
    layout.toggleCollapsed("s-comms")
    layout.apply(bar: ["pomodoro"], tray: [])
    layout.apply(bar: ["pomodoro"], tray: ["gmail", "calendar", "calculator", "stats", "slack", "spotify", "whatsapp", "todo", "schedule", "scratchpad", "preparo", "matinee"])
    layout.deleteShelf("s-comms")
    layout.deleteShelf("s-focus")
    tray("6-first-launch-bronze", theme: "bronze", out: out)
    BoardThemeStore.shared.theme = BoardTheme.all.first { $0.id == "bronze" }!
    let id = layout.addShelf(named: "Communication")
    ["gmail", "whatsapp", "slack"].forEach { layout.move($0, to: .shelf(id)) }
    layout.move("pomodoro", to: .bar)
    layout.move("schedule", to: .bar)
    render(ShelvesSettings().background(BoardBackdrop(theme: BoardThemeStore.shared.theme)), size: CGSize(width: 480, height: 760), appearance: .darkAqua, to: "\(out)/7-settings-shelves.png")
}
