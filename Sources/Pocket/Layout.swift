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
    var onChange: (() -> Void)?

    init() {
        let known = Set(catalog.map(\.id))
        bar = (defaults.stringArray(forKey: "layout.bar") ?? []).filter(known.contains)
        tray = (defaults.stringArray(forKey: "layout.tray") ?? []).filter(known.contains)
        setupDone = defaults.bool(forKey: "setup.done")
        hotKeys = defaults.object(forKey: "hotkeys.enabled") as? Bool ?? true
        otp = defaults.bool(forKey: "otp.enabled")
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
}
