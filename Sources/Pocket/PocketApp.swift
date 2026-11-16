import AppKit

final class Panel: NSPanel {
    var onEscape: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func cancelOperation(_ sender: Any?) { onEscape?() }
}

class PocketApp: NSObject, NSWindowDelegate {
    let spec: AppSpec
    var onDisplayChange: ((PocketApp) -> Void)?
    var panelIfLoaded: Panel?

    init(spec: AppSpec) {
        self.spec = spec
        super.init()
    }

    var defaultSize: NSSize { NSSize(width: 460, height: 680) }
    var minSize: NSSize { NSSize(width: 360, height: 420) }
    var resizable: Bool { true }
    var isShown: Bool { panelIfLoaded?.isVisible == true }

    func makeContent() -> NSView { NSView() }
    func start() {}
    func didShow() {}
    func didHide() {}
    func shouldStayOpen() -> Bool { false }
    func menuItems() -> [NSMenuItem] { [] }
    func barImage() -> NSImage? { AppIcon.render(spec) }
    func barTitle() -> NSAttributedString? { nil }

    func stop() {
        panelIfLoaded?.delegate = nil
        panelIfLoaded?.orderOut(nil)
        panelIfLoaded = nil
    }

    func changed() { onDisplayChange?(self) }

    var panel: Panel {
        if let panelIfLoaded { return panelIfLoaded }
        var style: NSWindow.StyleMask = [.nonactivatingPanel, .titled, .fullSizeContentView]
        if resizable { style.insert(.resizable) }
        let panel = Panel(contentRect: NSRect(origin: .zero, size: resizable ? savedSize() : defaultSize), styleMask: style, backing: .buffered, defer: true)
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovable = false
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.minSize = resizable ? minSize : defaultSize
        panel.delegate = self
        panel.onEscape = { [weak self] in self?.hide(reason: "escape") }
        for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            panel.standardWindowButton(kind)?.isHidden = true
        }
        panel.contentView = makeContent()
        panelIfLoaded = panel
        return panel
    }

    func savedSize() -> NSSize {
        let stored = UserDefaults.standard.string(forKey: "size.\(spec.id)").map(NSSizeFromString) ?? .zero
        return stored.width >= minSize.width && stored.height >= minSize.height ? stored : defaultSize
    }

    func toggle(anchor: NSStatusItem?, source: String) {
        isShown ? hide(reason: source) : show(anchor: anchor, source: source)
    }

    func show(anchor: NSStatusItem?, source: String) {
        AppDelegate.shared.hideOthers(except: self)
        let panel = self.panel
        let size = panel.frame.size
        if let window = anchor?.button?.window, let area = (window.screen ?? NSScreen.main)?.visibleFrame {
            let spot = window.frame
            let x = min(max(spot.midX - size.width / 2, area.minX + 8), area.maxX - size.width - 8)
            panel.setFrame(NSRect(x: x, y: spot.minY - size.height - 6, width: size.width, height: size.height), display: true)
        } else if let area = NSScreen.main?.visibleFrame {
            panel.setFrame(NSRect(x: area.midX - size.width / 2, y: area.midY - size.height / 2, width: size.width, height: size.height), display: true)
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        note("pocket shown app=\(spec.id) source=\(source) anchored=\(anchor != nil)")
        didShow()
    }

    func hide(reason: String) {
        guard let panel = panelIfLoaded, panel.isVisible else { return }
        panel.orderOut(nil)
        if reason != "focus lost" && reason != "switched" { NSApp.hide(nil) }
        note("pocket hidden app=\(spec.id) reason=\(reason)")
        didHide()
    }

    func windowDidResignKey(_ notification: Notification) {
        guard (notification.object as? NSWindow) === panelIfLoaded, !shouldStayOpen() else { return }
        hide(reason: "focus lost")
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        guard let panel = panelIfLoaded, (notification.object as? NSWindow) === panel else { return }
        UserDefaults.standard.set(NSStringFromSize(panel.frame.size), forKey: "size.\(spec.id)")
    }
}

enum AppIcon {
    static let side: CGFloat = 18

    static func glyph(_ spec: AppSpec) -> NSImage? {
        spec.glyph.flatMap { NSImage(data: Data($0.utf8)) }
            ?? NSImage(systemSymbolName: spec.symbol, accessibilityDescription: spec.name)
    }

    static func render(_ spec: AppSpec, unread: Int = 0, tint: NSColor = .labelColor) -> NSImage? {
        guard let glyph = glyph(spec) else {
            note("pocket menu glyph missing app=\(spec.id) symbol=\(spec.symbol)")
            return nil
        }
        let image = NSImage(size: NSSize(width: side + 3, height: side), flipped: false) { _ in
            let box = NSRect(x: 1.5, y: 1.5, width: side - 3, height: side - 3)
            let fitted = fit(glyph.size, in: box)
            glyph.draw(in: fitted)
            tint.set()
            fitted.fill(using: .sourceAtop)
            if unread != 0 {
                let text = unread < 0 ? "" : unread > 99 ? "99+" : "\(unread)"
                let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 8, weight: .bold), .foregroundColor: NSColor.white]
                let label = NSAttributedString(string: text, attributes: attrs)
                let pill = unread < 0 ? NSSize(width: 7, height: 7) : NSSize(width: max(11, label.size().width + 5), height: 11)
                let rect = NSRect(x: side - pill.width + 3, y: side - pill.height, width: pill.width, height: pill.height)
                NSColor.systemRed.setFill()
                NSBezierPath(roundedRect: rect, xRadius: pill.height / 2, yRadius: pill.height / 2).fill()
                let size = label.size()
                label.draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2))
            }
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = spec.name
        return image
    }

    static func fit(_ size: NSSize, in box: NSRect) -> NSRect {
        guard size.width > 0, size.height > 0 else { return box }
        let scale = min(box.width / size.width, box.height / size.height)
        let w = size.width * scale, h = size.height * scale
        return NSRect(x: box.midX - w / 2, y: box.midY - h / 2, width: w, height: h)
    }
}
