import AppKit

final class BarController: NSObject {
    let launcher: NSStatusItem
    var items: [String: NSStatusItem] = [:]
    var order: [String] = []

    override init() {
        launcher = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        if let button = launcher.button {
            button.image = NSImage(systemSymbolName: traySpec.symbol, accessibilityDescription: "Pocket apps")
            button.image?.isTemplate = true
            button.target = self
            button.action = #selector(launcherClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "Pocket: more apps and layout"
        }
    }

    @objc func launcherClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            AppDelegate.shared.appendCommonItems(to: menu, for: nil)
            launcher.menu = menu
            launcher.button?.performClick(nil)
            launcher.menu = nil
            return
        }
        AppDelegate.shared.tray.toggle(anchor: launcher, source: "launcher")
    }

    func sync(_ ids: [String]) {
        if ids != order {
            items.values.forEach { NSStatusBar.system.removeStatusItem($0) }
            items = [:]
            for id in ids.reversed() {
                let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
                if let button = item.button {
                    button.identifier = NSUserInterfaceItemIdentifier(id)
                    button.imagePosition = .imageLeft
                    button.target = self
                    button.action = #selector(clicked(_:))
                    button.sendAction(on: [.leftMouseUp, .rightMouseUp])
                    button.toolTip = spec(id)?.name
                }
                items[id] = item
            }
            order = ids
            note("pocket menu bar rebuilt items=\(ids.joined(separator: ","))")
        }
        ids.forEach(refresh)
    }

    func refresh(_ id: String) {
        guard let button = items[id]?.button, let app = AppDelegate.shared.app(id) else { return }
        button.image = app.barImage()
        button.attributedTitle = app.barTitle() ?? NSAttributedString(string: "")
    }

    func anchor(for id: String) -> NSStatusItem { items[id] ?? launcher }

    @objc func clicked(_ sender: NSStatusBarButton) {
        guard let id = sender.identifier?.rawValue, let item = items[id] else { return }
        if NSApp.currentEvent?.type == .rightMouseUp { return showMenu(for: id, on: item) }
        AppDelegate.shared.open(id, source: "click")
    }

    func showMenu(for id: String, on item: NSStatusItem) {
        let menu = NSMenu()
        AppDelegate.shared.app(id)?.menuItems().forEach(menu.addItem)
        AppDelegate.shared.appendCommonItems(to: menu, for: id)
        item.menu = menu
        item.button?.performClick(nil)
        item.menu = nil
    }
}
