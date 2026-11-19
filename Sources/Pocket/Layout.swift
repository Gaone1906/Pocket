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
        var barIds = (defaults.stringArray(forKey: "layout.bar") ?? []).filter(known.contains)
        var trayIds = (defaults.stringArray(forKey: "layout.tray") ?? []).filter(known.contains)
        let done = defaults.bool(forKey: "setup.done")
        let store = UserDefaults.standard
        let listed = Set(store.stringArray(forKey: "layout.offered") ?? catalog.filter { $0.link == nil }.map(\.id))
        let fresh = catalog.map(\.id).filter { !listed.contains($0) && !barIds.contains($0) && !trayIds.contains($0) }
        if done && !fresh.isEmpty {
            let pinned = fresh.filter { id in catalog.contains { $0.id == id && $0.pinnedByDefault } }
            let dropped = fresh.filter { !pinned.contains($0) }
            if !pinned.isEmpty {
                barIds += pinned
                store.set(barIds, forKey: "layout.bar")
                note("pocket new apps added to menu bar apps=\(pinned.joined(separator: ","))")
            }
            if !dropped.isEmpty {
                trayIds += dropped
                store.set(trayIds, forKey: "layout.tray")
                note("pocket new apps added to dropdown apps=\(dropped.joined(separator: ","))")
            }
        }
        store.set(catalog.map(\.id), forKey: "layout.offered")
        bar = barIds
        tray = trayIds
        setupDone = done
        hotKeys = defaults.object(forKey: "hotkeys.enabled") as? Bool ?? true
        otp = defaults.bool(forKey: "otp.enabled")
        let stored = defaults.data(forKey: "shortcuts").flatMap { try? JSONDecoder().decode([String: Shortcut].self, from: $0) }
        var map = stored ?? [:]
        var offered = Set(defaults.stringArray(forKey: "shortcuts.offered") ?? Array(map.keys))
        var added: [String] = []
        for app in catalog where !offered.contains(app.id) {
            offered.insert(app.id)
            guard let key = app.hotKey else { continue }
            let holders = map.filter { $0.value == .option(key) }.map(\.key).sorted()
            if !holders.isEmpty {
                guard app.claimsHotKey else { continue }
                holders.forEach { map[$0] = nil }
                note("pocket shortcut claimed app=\(app.id) from=\(holders.joined(separator: ",")) keys=\(Shortcut.option(key).display)")
            }
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
