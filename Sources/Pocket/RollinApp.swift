import AppKit
import QuartzCore
import SwiftUI

struct RollinFeed: Identifiable {
    let id: String
    let name: String
    let detail: String
    let app: String?
    let symbol: String
    let tint: NSColor

    static let all = [
        RollinFeed(id: "whatsapp", name: "WhatsApp", detail: "New messages from WhatsApp in Pocket", app: "whatsapp", symbol: "message.fill",
                   tint: NSColor(srgbRed: 0.36, green: 0.80, blue: 0.53, alpha: 1)),
        RollinFeed(id: "otp", name: "One-time codes", detail: "Codes from Messages and Gmail", app: nil, symbol: "key.fill",
                   tint: NSColor(srgbRed: 0.97, green: 0.73, blue: 0.33, alpha: 1)),
    ]

    static func find(_ id: String) -> RollinFeed? { all.first { $0.id == id } }
}

struct RollinItem {
    let feed: RollinFeed
    let title: String
    let body: String
    var passes: Int
}

final class RollinStore: ObservableObject {
    static let shared = RollinStore()
    let defaults = UserDefaults.standard
    let ticker = RollinTicker()
    var recent: [String: Date] = [:]

    @Published private(set) var present = false
    @Published var on: Bool {
        didSet {
            guard on != oldValue else { return }
            defaults.set(on, forKey: "rollin.on")
            note("rollin switched on=\(on)")
            if !on { ticker.clear(reason: "switched off") }
            AppDelegate.shared.syncOtp()
        }
    }
    @Published private(set) var feeds: [String: Bool]

    init() {
        let store = UserDefaults.standard
        on = store.object(forKey: "rollin.on") as? Bool ?? true
        feeds = Dictionary(uniqueKeysWithValues: RollinFeed.all.map { ($0.id, store.object(forKey: "rollin.feed.\($0.id)") as? Bool ?? true) })
    }

    func isOn(_ feed: String) -> Bool { feeds[feed] ?? false }

    func set(_ feed: String, on value: Bool) {
        guard feeds[feed] != value else { return }
        feeds[feed] = value
        defaults.set(value, forKey: "rollin.feed.\(feed)")
        note("rollin feed switched feed=\(feed) on=\(value)")
        if !value { ticker.clear(feed: feed) }
        AppDelegate.shared.syncOtp()
    }

    func wants(_ feed: String) -> Bool { present && on && isOn(feed) }

    func attach() {
        guard !present else { return }
        present = true
        note("rollin attached on=\(on) feeds=\(feeds.filter(\.value).keys.sorted().joined(separator: ","))")
    }

    func detach() {
        guard present else { return }
        present = false
        ticker.clear(reason: "app disabled")
        note("rollin detached")
    }

    func push(_ feed: String, title: String, body: String) {
        guard wants(feed), let source = RollinFeed.find(feed) else { return }
        let title = RollinStore.flatten(title, limit: 60)
        let body = RollinStore.flatten(body, limit: 160)
        guard !title.isEmpty || !body.isEmpty else { return }
        let key = "\(feed)|\(title)|\(body)"
        let now = Date()
        recent = recent.filter { now.timeIntervalSince($0.value) < 10 }
        if recent[key] != nil { return note("rollin skipped feed=\(feed) cause=repeat within 10s") }
        recent[key] = now
        ticker.add(RollinItem(feed: source, title: title, body: body, passes: 2))
    }

    func sample() {
        guard present && on else { return }
        ticker.add(RollinItem(feed: RollinFeed.all[0], title: "Rollin", body: "This is how a new WhatsApp message rolls by", passes: 1))
        ticker.add(RollinItem(feed: RollinFeed.all[1], title: "Code", body: "482913", passes: 1))
        note("rollin sample rolled")
    }

    static func flatten(_ text: String, limit: Int) -> String {
        let single = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
        return single.count > limit ? String(single.prefix(limit - 1)) + "…" : single
    }
}

final class RollinTicker {
    let width: CGFloat = 240
    let speed: CGFloat = 46
    let gap: CGFloat = 44
    var item: NSStatusItem?
    var strip: NSView?
    var runs: [Run] = []
    var hideWork: DispatchWorkItem?

    final class Run {
        let layer: CALayer
        let item: RollinItem
        let start: CFTimeInterval
        let x: CGFloat
        let length: CGFloat
        let speed: CGFloat

        init(layer: CALayer, item: RollinItem, start: CFTimeInterval, x: CGFloat, length: CGFloat, speed: CGFloat) {
            self.layer = layer
            self.item = item
            self.start = start
            self.x = x
            self.length = length
            self.speed = speed
        }

        func trailing(at time: CFTimeInterval) -> CGFloat { x - speed * CGFloat(time - start) + length }
    }

    func add(_ entry: RollinItem) {
        guard let strip = ensureStrip(), let layer = strip.layer else { return }
        hideWork?.cancel()
        hideWork = nil
        let scale = strip.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let appearance = item?.button?.effectiveAppearance ?? NSApp.effectiveAppearance
        let span = strip.bounds.width > 0 ? strip.bounds.width : width
        let tall = strip.bounds.height > 0 ? strip.bounds.height : NSStatusBar.system.thickness
        guard let picture = RollinTicker.render(entry, height: tall, scale: scale, appearance: appearance) else {
            return note("rollin render failed feed=\(entry.feed.id)")
        }
        let now = CACurrentMediaTime()
        let tail = runs.map { $0.trailing(at: now) }.max() ?? 0
        let x = max(span, tail + gap)
        let size = picture.size
        let piece = CALayer()
        piece.contents = picture.image
        piece.contentsScale = scale
        piece.anchorPoint = .zero
        piece.bounds = CGRect(origin: .zero, size: size)
        let y = ((tall - size.height) / 2).rounded()
        let end = CGPoint(x: -size.width, y: y)
        let duration = CFTimeInterval((x + size.width) / speed)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        piece.position = end
        layer.addSublayer(piece)
        CATransaction.commit()
        let slide = CABasicAnimation(keyPath: "position.x")
        slide.fromValue = x
        slide.toValue = end.x
        slide.duration = duration
        slide.timingFunction = CAMediaTimingFunction(name: .linear)
        piece.add(slide, forKey: "roll")
        let run = Run(layer: piece, item: entry, start: now, x: x, length: size.width, speed: speed)
        runs.append(run)
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self, weak run] in
            guard let self, let run else { return }
            self.finish(run)
        }
        note("rollin rolling feed=\(entry.feed.id) chars=\(entry.title.count + entry.body.count) passesLeft=\(entry.passes) queued=\(runs.count) wait=\(Int((x - span) / speed))s")
    }

    func finish(_ run: Run) {
        guard let index = runs.firstIndex(where: { $0 === run }) else { return }
        runs.remove(at: index)
        run.layer.removeFromSuperlayer()
        var next = run.item
        next.passes -= 1
        if next.passes > 0, runs.count < 4, RollinStore.shared.wants(next.feed.id) { return add(next) }
        if runs.isEmpty { scheduleHide() }
    }

    func scheduleHide() {
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.runs.isEmpty else { return }
            self.remove(reason: "idle")
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    func clear(reason: String) {
        guard item != nil || !runs.isEmpty else { return }
        runs.forEach { $0.layer.removeFromSuperlayer() }
        runs = []
        remove(reason: reason)
    }

    func clear(feed: String) {
        let gone = runs.filter { $0.item.feed.id == feed }
        guard !gone.isEmpty else { return }
        gone.forEach { $0.layer.removeFromSuperlayer() }
        runs.removeAll { $0.item.feed.id == feed }
        note("rollin cleared feed=\(feed) removed=\(gone.count)")
        if runs.isEmpty { scheduleHide() }
    }

    func remove(reason: String) {
        hideWork?.cancel()
        hideWork = nil
        guard let item else { return }
        NSStatusBar.system.removeStatusItem(item)
        self.item = nil
        strip = nil
        note("rollin hidden reason=\(reason)")
    }

    func ensureStrip() -> NSView? {
        if let strip { return strip }
        let item = NSStatusBar.system.statusItem(withLength: width)
        guard let button = item.button else {
            NSStatusBar.system.removeStatusItem(item)
            note("rollin unavailable cause=no status button")
            return nil
        }
        button.title = ""
        button.image = nil
        button.isEnabled = false
        button.setAccessibilityLabel("Rollin")
        let strip = RollinStrip(frame: button.bounds)
        strip.autoresizingMask = [.width, .height]
        strip.wantsLayer = true
        strip.layer?.masksToBounds = true
        let fade = CAGradientLayer()
        fade.startPoint = CGPoint(x: 0, y: 0.5)
        fade.endPoint = CGPoint(x: 1, y: 0.5)
        fade.colors = [NSColor.clear.cgColor, NSColor.black.cgColor, NSColor.black.cgColor, NSColor.clear.cgColor]
        let edge = NSNumber(value: Double(14 / width))
        fade.locations = [0, edge, NSNumber(value: 1 - edge.doubleValue), 1]
        fade.frame = strip.bounds
        strip.layer?.mask = fade
        button.addSubview(strip)
        self.item = item
        self.strip = strip
        note("rollin shown width=\(Int(width)) height=\(Int(button.bounds.height))")
        return strip
    }

    struct Picture {
        let image: CGImage
        let size: CGSize
    }

    static func render(_ entry: RollinItem, height: CGFloat, scale: CGFloat, appearance: NSAppearance) -> Picture? {
        var ink = NSColor.labelColor
        var soft = NSColor.secondaryLabelColor
        appearance.performAsCurrentDrawingAppearance {
            ink = NSColor.labelColor.usingColorSpace(.sRGB) ?? .black
            soft = NSColor.secondaryLabelColor.usingColorSpace(.sRGB) ?? .darkGray
        }
        let size = NSFont.menuBarFont(ofSize: 0).pointSize
        let code = entry.feed.id == "otp"
        let titleFont = NSFont.systemFont(ofSize: size, weight: .semibold)
        let bodyFont = code ? NSFont.monospacedDigitSystemFont(ofSize: size, weight: .bold) : NSFont.systemFont(ofSize: size, weight: .regular)
        let line = NSMutableAttributedString(string: entry.title, attributes: [.font: titleFont, .foregroundColor: ink])
        if !entry.body.isEmpty {
            if !entry.title.isEmpty { line.append(NSAttributedString(string: "  ", attributes: [.font: bodyFont])) }
            line.append(NSAttributedString(string: entry.body, attributes: [.font: bodyFont, .foregroundColor: code ? ink : soft]))
        }
        let dot: CGFloat = 6
        let lead = dot + 7
        let text = line.size()
        let box = CGSize(width: ceil(lead + text.width + 2), height: max(ceil(text.height), height > 0 ? min(height, ceil(text.height) + 4) : ceil(text.height)))
        let pixelsWide = Int(ceil(box.width * scale)), pixelsHigh = Int(ceil(box.height * scale))
        guard pixelsWide > 0, pixelsHigh > 0,
              let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixelsWide, pixelsHigh: pixelsHigh, bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        rep.size = box
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        entry.feed.tint.setFill()
        NSBezierPath(ovalIn: NSRect(x: 1, y: (box.height - dot) / 2, width: dot, height: dot)).fill()
        line.draw(at: NSPoint(x: lead, y: (box.height - text.height) / 2))
        NSGraphicsContext.restoreGraphicsState()
        guard let image = rep.cgImage else { return nil }
        return Picture(image: image, size: box)
    }
}

final class RollinStrip: NSView {
    override func setFrameSize(_ size: NSSize) {
        super.setFrameSize(size)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.mask?.frame = bounds
        CATransaction.commit()
    }
}

final class RollinApp: PocketApp {
    override var defaultSize: NSSize { NSSize(width: 340, height: 330) }
    override var resizable: Bool { false }

    override func makeContent() -> NSView {
        ThemedHostingView(rootView: RollinView(store: RollinStore.shared, layout: Layout.shared))
    }

    override func start() { RollinStore.shared.attach() }

    override func stop() {
        RollinStore.shared.detach()
        super.stop()
    }
}

private struct RollinView: View {
    @ObservedObject var store: RollinStore
    @ObservedObject var layout: Layout
    @ObservedObject var themes = BoardThemeStore.shared

    var body: some View {
        let theme = themes.theme
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Rollin")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(theme.ink)
                Text("New notifications roll across the menu bar")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.muted)
            }
            row(title: "Rollin", detail: store.on ? "On" : "Off", icon: nil, tint: nil, enabled: true,
                isOn: Binding(get: { store.on }, set: { store.on = $0 }))
                .background(RoundedRectangle(cornerRadius: 14).fill(theme.card))
                .boardEdge(14)
            VStack(alignment: .leading, spacing: 8) {
                Text("Apps")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.muted)
                    .padding(.leading, 4)
                VStack(spacing: 0) {
                    ForEach(Array(RollinFeed.all.enumerated()), id: \.element.id) { index, feed in
                        if index > 0 { Rectangle().fill(theme.line).frame(height: 1).padding(.leading, 52) }
                        row(title: feed.name, detail: detail(feed), icon: icon(feed), tint: Color(nsColor: feed.tint), enabled: store.on,
                            isOn: Binding(get: { store.isOn(feed.id) }, set: { store.set(feed.id, on: $0) }))
                    }
                }
                .background(RoundedRectangle(cornerRadius: 14).fill(theme.card))
                .boardEdge(14)
            }
            Spacer(minLength: 0)
            HStack {
                Spacer()
                Button {
                    store.sample()
                } label: {
                    Text("Roll a sample")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme.accentInkStyle)
                        .padding(.horizontal, 14)
                        .frame(height: 28)
                        .background(Capsule().fill(theme.accent.opacity(theme.isDark ? 0.2 : 0.16)))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!store.on)
                .opacity(store.on ? 1 : 0.5)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 26)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .id(theme.id)
        .background(BoardBackdrop(theme: theme).ignoresSafeArea())
        .environment(\.colorScheme, theme.colorScheme)
        .fontDesign(.rounded)
        .tint(theme.accent)
        .animation(Board.glide, value: store.on)
    }

    func detail(_ feed: RollinFeed) -> String {
        if let app = feed.app, !layout.enabled.contains(app) { return "Turn on \(feed.name) in Pocket to use this" }
        return feed.detail
    }

    func icon(_ feed: RollinFeed) -> NSImage? {
        guard let app = feed.app.flatMap(spec) else { return NSImage(systemSymbolName: feed.symbol, accessibilityDescription: feed.name) }
        return AppIcon.render(app, tint: feed.tint)
    }

    func row(title: String, detail: String, icon: NSImage?, tint: Color?, enabled: Bool, isOn: Binding<Bool>) -> some View {
        let theme = themes.theme
        return HStack(spacing: 12) {
            if let icon {
                Image(nsImage: icon)
                    .renderingMode(icon.isTemplate ? .template : .original)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(tint ?? theme.ink)
                    .frame(width: 16, height: 16)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill((tint ?? theme.accent).opacity(0.16)))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(theme.ink)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.muted)
            }
            Spacer()
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
                .tint(theme.accent)
                .disabled(!enabled)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .opacity(enabled ? 1 : 0.5)
    }
}
