import Carbon
import Combine
import Foundation

struct Shelf: Codable, Identifiable, Equatable {
    static let unorganizedId = "unorganized"
    static let unorganizedName = "Unorganized"

    var id: String
    var name: String
    var apps: [String]

    var isUnorganized: Bool { id == Shelf.unorganizedId }
}

enum ShelfSpot: Equatable {
    case bar
    case shelf(String)
}

final class Layout: ObservableObject {
    static let shared = Layout()
    let defaults = UserDefaults.standard

    @Published private(set) var bar: [String]
    @Published private(set) var shelves: [Shelf]
    @Published private(set) var collapsed: Set<String>
    @Published var setupDone: Bool { didSet { defaults.set(setupDone, forKey: "setup.done") } }
    @Published var hotKeys: Bool { didSet { defaults.set(hotKeys, forKey: "hotkeys.enabled"); onChange?() } }
    @Published var otp: Bool { didSet { defaults.set(otp, forKey: "otp.enabled"); onChange?() } }
    @Published private(set) var shortcuts: [String: Shortcut]
    @Published private(set) var extraShortcuts: [String: [Shortcut]]
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
                note("pocket new apps added to unorganized shelf apps=\(dropped.joined(separator: ","))")
            }
        }
        store.set(catalog.map(\.id), forKey: "layout.offered")
        bar = barIds
        shelves = Layout.loadShelves(defaults, known: known, bar: barIds, tray: trayIds)
        collapsed = Set(defaults.stringArray(forKey: "layout.collapsed") ?? [])
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
        var moved: [String] = []
        if !defaults.bool(forKey: "shortcuts.elements.2") {
            for (id, code) in Layout.elementKeys where known.contains(id) {
                let key = Shortcut.option(code)
                map.filter { $0.key != id && $0.value == key }.forEach { map[$0.key] = nil }
                if map[id] != key {
                    map[id] = key
                    moved.append(id)
                }
            }
            defaults.set(true, forKey: "shortcuts.elements.2")
        }
        shortcuts = map
        extraShortcuts = defaults.data(forKey: "shortcuts.extra").flatMap { try? JSONDecoder().decode([String: [Shortcut]].self, from: $0) } ?? [:]
        defaults.set(Array(offered).sorted(), forKey: "shortcuts.offered")
        if stored == nil || !added.isEmpty || !moved.isEmpty, let data = try? JSONEncoder().encode(map) {
            defaults.set(data, forKey: "shortcuts")
            note("pocket shortcut defaults given apps=\(added.joined(separator: ",")) moved=\(moved.joined(separator: ","))")
        }
        save()
    }

    static let elementKeys: [(String, UInt32)] = [
        ("pomodoro", UInt32(kVK_ANSI_1)), ("runner", UInt32(kVK_ANSI_2)),
        ("schedule", UInt32(kVK_ANSI_3)), ("calorie", UInt32(kVK_ANSI_4)), ("preparo", UInt32(kVK_ANSI_9)),
    ]

    var tray: [String] { shelves.flatMap(\.apps) }
    var enabled: [String] { bar + tray }
    var customShelves: [Shelf] { shelves.filter { !$0.isUnorganized } }
    func inBar(_ id: String) -> Bool { bar.contains(id) }

    func spot(of id: String) -> ShelfSpot? {
        if bar.contains(id) { return .bar }
        return shelves.first { $0.apps.contains(id) }.map { .shelf($0.id) }
    }

    func shelfName(_ spot: ShelfSpot) -> String {
        switch spot {
        case .bar: return "Menu bar"
        case .shelf(let id): return shelves.first { $0.id == id }?.name ?? Shelf.unorganizedName
        }
    }

    static func loadShelves(_ defaults: UserDefaults, known: Set<String>, bar: [String], tray: [String]) -> [Shelf] {
        let stored = defaults.data(forKey: "layout.shelves").flatMap { try? JSONDecoder().decode([Shelf].self, from: $0) }
        if stored == nil { note("pocket shelves migrated from dropdown apps=\(tray.joined(separator: ","))") }
        return normalized(stored ?? [], known: known, bar: bar, extra: tray)
    }

    static func normalized(_ input: [Shelf], known: Set<String>, bar: [String], extra: [String]) -> [Shelf] {
        var seen = Set(bar)
        var custom: [Shelf] = []
        var loose: [String] = []
        for shelf in input {
            let apps = shelf.apps.filter { known.contains($0) && seen.insert($0).inserted }
            if shelf.isUnorganized {
                loose += apps
            } else {
                custom.append(Shelf(id: shelf.id, name: shelf.name, apps: apps))
            }
        }
        loose += extra.filter { known.contains($0) && seen.insert($0).inserted }
        return custom + [Shelf(id: Shelf.unorganizedId, name: Shelf.unorganizedName, apps: loose)]
    }

    private func save() {
        defaults.set(bar, forKey: "layout.bar")
        defaults.set(tray, forKey: "layout.tray")
        if let data = try? JSONEncoder().encode(shelves) { defaults.set(data, forKey: "layout.shelves") }
    }

    private func commit(bar newBar: [String], shelves newShelves: [Shelf], reason: String) {
        let barIds = newBar.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        let fixed = Layout.normalized(newShelves, known: Set(catalog.map(\.id)), bar: barIds, extra: [])
        guard barIds != bar || fixed != shelves else { return }
        let membershipChanged = Set(barIds + fixed.flatMap(\.apps)) != Set(enabled) || barIds != bar
        bar = barIds
        shelves = fixed
        save()
        let summary = fixed.map { "\($0.name)[\($0.apps.joined(separator: ","))]" }.joined(separator: " ")
        note("pocket layout changed reason=\(reason) bar=\(bar.joined(separator: ",")) shelves=\(summary)")
        if membershipChanged { onChange?() }
    }

    func apply(bar newBar: [String], tray newTray: [String]) {
        let barIds = newBar.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        let wanted = newTray.filter { !barIds.contains($0) }
        var next = shelves.map { Shelf(id: $0.id, name: $0.name, apps: $0.apps.filter(wanted.contains)) }
        let placed = Set(next.flatMap(\.apps))
        let loose = wanted.filter { !placed.contains($0) }
        if let index = next.firstIndex(where: \.isUnorganized) { next[index].apps += loose }
        commit(bar: barIds, shelves: next, reason: "setup")
    }

    func move(_ id: String, to spot: ShelfSpot, before target: String? = nil) {
        guard enabled.contains(id), id != target else { return }
        var newBar = bar.filter { $0 != id }
        var next = shelves.map { Shelf(id: $0.id, name: $0.name, apps: $0.apps.filter { $0 != id }) }
        switch spot {
        case .bar:
            newBar.insert(id, at: target.flatMap { newBar.firstIndex(of: $0) } ?? newBar.endIndex)
        case .shelf(let shelfId):
            guard let index = next.firstIndex(where: { $0.id == shelfId }) else {
                return note("pocket layout move ignored app=\(id) shelf=\(shelfId) cause=no such shelf")
            }
            next[index].apps.insert(id, at: target.flatMap { next[index].apps.firstIndex(of: $0) } ?? next[index].apps.endIndex)
        }
        commit(bar: newBar, shelves: next, reason: "move app=\(id) to=\(shelfName(spot))")
    }

    func move(_ id: String, toBar: Bool, before target: String? = nil) {
        move(id, to: toBar ? .bar : .shelf(Shelf.unorganizedId), before: target)
    }

    @discardableResult
    func addShelf(named name: String = "New shelf") -> String {
        let base = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "New shelf" : name.trimmingCharacters(in: .whitespacesAndNewlines)
        let taken = Set(shelves.map { $0.name.lowercased() })
        var title = base
        var counter = 2
        while taken.contains(title.lowercased()) {
            title = "\(base) \(counter)"
            counter += 1
        }
        let shelf = Shelf(id: UUID().uuidString, name: title, apps: [])
        commit(bar: bar, shelves: customShelves + [shelf] + shelves.filter(\.isUnorganized), reason: "add shelf=\(title)")
        return shelf.id
    }

    func renameShelf(_ id: String, to name: String) {
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, let index = shelves.firstIndex(where: { $0.id == id && !$0.isUnorganized }), shelves[index].name != title else { return }
        var next = shelves
        let previous = next[index].name
        next[index].name = title
        commit(bar: bar, shelves: next, reason: "rename shelf=\(previous) to=\(title)")
    }

    func deleteShelf(_ id: String) {
        guard let shelf = shelves.first(where: { $0.id == id && !$0.isUnorganized }) else { return }
        var next = shelves.filter { $0.id != id }
        if let index = next.firstIndex(where: \.isUnorganized) { next[index].apps += shelf.apps }
        collapsed.remove(id)
        defaults.set(Array(collapsed), forKey: "layout.collapsed")
        commit(bar: bar, shelves: next, reason: "delete shelf=\(shelf.name) moved=\(shelf.apps.joined(separator: ","))")
    }

    func moveShelf(_ id: String, before target: String?) {
        var custom = customShelves
        guard id != target, let from = custom.firstIndex(where: { $0.id == id }) else { return }
        let shelf = custom.remove(at: from)
        custom.insert(shelf, at: target.flatMap { t in custom.firstIndex { $0.id == t } } ?? custom.endIndex)
        commit(bar: bar, shelves: custom + shelves.filter(\.isUnorganized), reason: "reorder shelf=\(shelf.name)")
    }

    func moveShelf(_ id: String, by offset: Int) {
        let custom = customShelves
        guard let from = custom.firstIndex(where: { $0.id == id }) else { return }
        let to = min(max(from + offset, 0), custom.count - 1)
        guard to != from else { return }
        let target = offset > 0 ? (to + 1 < custom.count ? custom[to + 1].id : nil) : custom[to].id
        moveShelf(id, before: target)
    }

    func toggleCollapsed(_ id: String) {
        if collapsed.contains(id) { collapsed.remove(id) } else { collapsed.insert(id) }
        defaults.set(Array(collapsed), forKey: "layout.collapsed")
    }

    func keys(for id: String) -> [Shortcut] {
        (shortcuts[id].map { [$0] } ?? []) + (extraShortcuts[id] ?? [])
    }

    func setShortcut(_ id: String, _ shortcut: Shortcut?) {
        replaceShortcut(id, old: shortcuts[id], with: shortcut)
    }

    func replaceShortcut(_ id: String, old: Shortcut?, with shortcut: Shortcut?) {
        var all: [String: [Shortcut]] = [:]
        for app in Set(shortcuts.keys).union(extraShortcuts.keys) { all[app] = keys(for: app) }
        var list = all[id] ?? []
        if let old, let index = list.firstIndex(of: old) {
            if let shortcut { list[index] = shortcut } else { list.remove(at: index) }
        } else if let shortcut {
            list.append(shortcut)
        }
        if let shortcut {
            for (other, taken) in all where other != id && taken.contains(shortcut) {
                all[other] = taken.filter { $0 != shortcut }
                note("pocket shortcut taken over app=\(other) by=\(id) keys=\(shortcut.display)")
            }
            var seen = false
            list = list.filter { key in
                guard key == shortcut else { return true }
                defer { seen = true }
                return !seen
            }
        }
        all[id] = list
        var primary: [String: Shortcut] = [:]
        var extra: [String: [Shortcut]] = [:]
        for (app, list) in all {
            primary[app] = list.first
            if list.count > 1 { extra[app] = Array(list.dropFirst()) }
        }
        guard primary != shortcuts || extra != extraShortcuts else { return }
        shortcuts = primary
        extraShortcuts = extra
        if let data = try? JSONEncoder().encode(primary) { defaults.set(data, forKey: "shortcuts") }
        if let data = try? JSONEncoder().encode(extra) { defaults.set(data, forKey: "shortcuts.extra") }
        note("pocket shortcut set app=\(id) old=\(old?.display ?? "none") keys=\(shortcut?.display ?? "none") now=\(list.map(\.display).joined(separator: ","))")
        onChange?()
    }
}
