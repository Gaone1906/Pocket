import Combine
import Foundation

final class Layout: ObservableObject {
    static let shared = Layout()
    let defaults = UserDefaults.standard

    @Published private(set) var bar: [String]
    @Published private(set) var tray: [String]
    @Published var setupDone: Bool { didSet { defaults.set(setupDone, forKey: "setup.done") } }
    @Published var hotKeys: Bool { didSet { defaults.set(hotKeys, forKey: "hotkeys.enabled"); onChange?() } }
    @Published var otp: Bool { didSet { defaults.set(otp, forKey: "otp.enabled"); onChange?() } }
    @Published private(set) var shortcuts: [String: Shortcut]
    var onChange: (() -> Void)?

    init() {
        let known = Set(catalog.map(\.id))
        bar = (defaults.stringArray(forKey: "layout.bar") ?? []).filter(known.contains)
        tray = (defaults.stringArray(forKey: "layout.tray") ?? []).filter(known.contains)
        setupDone = defaults.bool(forKey: "setup.done")
        hotKeys = defaults.object(forKey: "hotkeys.enabled") as? Bool ?? true
        otp = defaults.bool(forKey: "otp.enabled")
        let stored = defaults.data(forKey: "shortcuts").flatMap { try? JSONDecoder().decode([String: Shortcut].self, from: $0) }
        var map = stored ?? [:]
        var offered = Set(defaults.stringArray(forKey: "shortcuts.offered") ?? Array(map.keys))
        var added: [String] = []
        for app in catalog where !offered.contains(app.id) {
            offered.insert(app.id)
            guard let key = app.hotKey, !map.values.contains(.option(key)) else { continue }
            map[app.id] = .option(key)
            added.append(app.id)
        }
        shortcuts = map
        defaults.set(Array(offered).sorted(), forKey: "shortcuts.offered")
        if stored == nil || !added.isEmpty, let data = try? JSONEncoder().encode(map) {
            defaults.set(data, forKey: "shortcuts")
            note("pocket shortcut defaults given apps=\(added.joined(separator: ","))")
        }
    }

    var enabled: [String] { bar + tray }
    func inBar(_ id: String) -> Bool { bar.contains(id) }

    func apply(bar newBar: [String], tray newTray: [String]) {
        let barIds = newBar.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        let trayIds = newTray.filter { !barIds.contains($0) }.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        guard barIds != bar || trayIds != tray else { return }
        bar = barIds
        tray = trayIds
        defaults.set(bar, forKey: "layout.bar")
        defaults.set(tray, forKey: "layout.tray")
        note("pocket layout changed bar=\(bar.joined(separator: ",")) tray=\(tray.joined(separator: ","))")
        onChange?()
    }

    func move(_ id: String, toBar: Bool, before target: String? = nil) {
        var newBar = bar.filter { $0 != id }
        var newTray = tray.filter { $0 != id }
        if toBar {
            newBar.insert(id, at: target.flatMap { newBar.firstIndex(of: $0) } ?? newBar.endIndex)
        } else {
            newTray.insert(id, at: target.flatMap { newTray.firstIndex(of: $0) } ?? newTray.endIndex)
        }
        apply(bar: newBar, tray: newTray)
    }

    func setShortcut(_ id: String, _ shortcut: Shortcut?) {
        var next = shortcuts
        if let shortcut {
            for (other, taken) in next where other != id && taken == shortcut {
                next[other] = nil
                note("pocket shortcut taken over app=\(other) by=\(id) keys=\(shortcut.display)")
            }
        }
        next[id] = shortcut
        guard next != shortcuts else { return }
        shortcuts = next
        if let data = try? JSONEncoder().encode(next) { defaults.set(data, forKey: "shortcuts") }
        note("pocket shortcut set app=\(id) keys=\(shortcut?.display ?? "none")")
        onChange?()
    }
}
