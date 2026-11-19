import AppKit
import SwiftUI

struct ShelvesSettings: View {
    @ObservedObject var layout = Layout.shared
    @ObservedObject var themes = BoardThemeStore.shared

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("SHELVES")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(1.6)
                        .foregroundStyle(Board.muted)
                    Text("Menu bar apps sit in the menu bar; every other shelf is a group in the Pocket dropdown. Drag apps between shelves, drag a shelf by its handle to reorder, or right-click an app to move it.")
                        .font(.system(size: 12))
                        .foregroundStyle(Board.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ShelfList(layout: layout, editing: true) { id in
                    AppDelegate.shared.open(id, source: "settings")
                }
            }
            .padding(20)
        }
        .environment(\.colorScheme, themes.theme.colorScheme)
        .animation(Board.glide, value: layout.shelves)
        .animation(Board.glide, value: layout.bar)
    }
}

final class ShelvesWindow: NSObject, NSWindowDelegate {
    static let shared = ShelvesWindow()
    var window: NSWindow?

    func show() {
        let window = self.window ?? make()
        self.window = window
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        note("pocket shelves window shown shelves=\(Layout.shared.shelves.count)")
    }

    func make() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 620), styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "Shelves"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 440, height: 420)
        let hosting = NSHostingView(rootView: ShelvesSettings().background(BoardBackdrop(theme: BoardThemeStore.shared.theme).ignoresSafeArea()))
        hosting.appearance = BoardThemeStore.shared.theme.appearance
        window.contentView = hosting
        window.center()
        window.delegate = self
        return window
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        NSApp.setActivationPolicy(.accessory)
        note("pocket shelves window closed")
    }
}
