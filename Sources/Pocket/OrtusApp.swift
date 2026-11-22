import AppKit
import SwiftUI

enum Fab {
    static let ground = Color(hex: 0x17100D)
    static let surface = Color(hex: 0x241914)
    static let raised = Color(hex: 0x1F1511)
    static let rail = Color(hex: 0x120C09)
    static let railLine = Color(hex: 0x2A1E18)
    static let line = Color(hex: 0x3A2A22)
    static let ink = Color(hex: 0xFBEDE5)
    static let muted = Color(hex: 0xBFA294)
    static let faint = Color(hex: 0x9C8173)
    static let accent = Color(hex: 0xE8673C)
    static let hover = Color(hex: 0xF2875F)
    static let wash = Color(hex: 0x3A2118)
    static let washText = Color(hex: 0xFBD3C2)
    static let gold = Color(hex: 0xF2C14E)
    static let onGold = Color(hex: 0x2A1A05)
    static let onAccent = Color(hex: 0x1A0D07)
    static let yes = Color(hex: 0x4CC283)
    static let no = Color(hex: 0xF0785C)

    static func serif(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font { .system(size: size, weight: weight, design: .serif) }
    static func sans(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font { .system(size: size, weight: weight) }

    static let logo: NSImage? = Data(base64Encoded: OrtusLogo.jpeg, options: .ignoreUnknownCharacters).flatMap(NSImage.init(data:))

    static func ratingColor(_ value: Double?) -> Color {
        guard let value else { return muted }
        if value >= 8 { return accent }
        if value >= 7 { return muted }
        return no
    }
}

struct FabulaLogoMark: View {
    let side: CGFloat

    var body: some View {
        Group {
            if let logo = Fab.logo {
                Image(nsImage: logo).resizable().interpolation(.high)
            } else {
                Fab.surface
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: side * 0.26, style: .continuous))
    }
}

final class OrtusApp: PocketApp {
    override var defaultSize: NSSize { NSSize(width: 380, height: 600) }
    override var minSize: NSSize { NSSize(width: 380, height: 600) }
    override var resizable: Bool { false }

    override func start() {
        let store = OrtusStore.shared
        store.onChange = { [weak self] in self?.changed() }
        FabulaDeck.shared.refill(source: "start")
        note("fabula app started logs=\(store.logs.count) swipes=\(store.swipes.count) connected=\(FabulaNet.connected)")
    }

    override func stop() {
        OrtusStore.shared.onChange = nil
        super.stop()
    }

    override func didShow() {
        let deck = FabulaDeck.shared
        if deck.cards.isEmpty { deck.reload(source: "dropdown") } else { deck.refill(source: "dropdown") }
    }

    override func makeContent() -> NSView {
        let view = FabulaGlance(deck: FabulaDeck.shared, nav: FabulaNav.shared) { [weak self] tab in
            self?.openWindow(tab: tab, source: "dropdown")
        }
        let host = NSHostingView(rootView: view)
        host.appearance = NSAppearance(named: .darkAqua)
        return host
    }

    func openWindow(tab: FabulaTab?, source: String) {
        hide(reason: "switched")
        if let tab { FabulaNav.shared.tab = tab }
        OrtusWindow.shared.present(source: source)
    }

    override func menuItems() -> [NSMenuItem] {
        let open = NSMenuItem(title: "Open Fabula", action: #selector(openFromMenu), keyEquivalent: "")
        open.target = self
        return [open]
    }

    @objc private func openFromMenu() { openWindow(tab: nil, source: "menu") }
}

final class OrtusWindow: NSObject, NSWindowDelegate {
    static let shared = OrtusWindow()

    private var window: NSWindow?

    func present(source: String) {
        NSApp.setActivationPolicy(.regular)
        let deck = FabulaDeck.shared
        if deck.cards.isEmpty { deck.reload(source: "window") }
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            note("fabula window refocused source=\(source) tab=\(FabulaNav.shared.tab.rawValue)")
            return
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 720),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = "Fabula"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(Fab.ground)
        let host = NSHostingView(rootView: FabulaRoot(store: OrtusStore.shared, deck: deck, nav: FabulaNav.shared))
        host.sizingOptions = []
        window.contentView = host
        window.contentMinSize = NSSize(width: 980, height: 640)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        window.setFrameAutosaveName("ortus.board")
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        note("fabula window opened source=\(source) tab=\(FabulaNav.shared.tab.rawValue)")
    }

    func windowWillClose(_ notification: Notification) {
        let closing = window
        window?.contentView = nil
        window?.delegate = nil
        window = nil
        let others = NSApp.windows.contains { $0 !== closing && $0.isVisible && $0.styleMask.contains(.titled) && $0.canBecomeMain }
        if !others { NSApp.setActivationPolicy(.accessory) }
        note("fabula window closed otherWindows=\(others)")
    }
}

final class FabulaKeyView: NSView {
    var handle: ((NSEvent) -> Bool)?
    private var monitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            guard let self, let window = self.window, event.window === window else { return event }
            if window.firstResponder is NSText { return event }
            return self.handle?(event) == true ? nil : event
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }
}

struct FabulaKeys: NSViewRepresentable {
    let handle: (NSEvent) -> Bool

    func makeNSView(context: Context) -> FabulaKeyView {
        let view = FabulaKeyView()
        view.handle = handle
        return view
    }

    func updateNSView(_ view: FabulaKeyView, context: Context) {
        view.handle = handle
    }
}

struct FabulaShake: GeometryEffect {
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        let damp = 1 - progress
        let wave = sin(progress * .pi * 7)
        let shift = wave * 6 * damp
        let angle = wave * 2.5 * damp * .pi / 180
        var transform = CGAffineTransform(translationX: size.width / 2 + shift, y: size.height / 2)
        transform = transform.rotated(by: angle)
        transform = transform.translatedBy(x: -size.width / 2, y: -size.height / 2)
        return ProjectionTransform(transform)
    }
}

final class FabulaMotion: ObservableObject {
    @Published var offset: CGSize = .zero
    @Published var shake: CGFloat = 0
    @Published var gold = false

    var locked = false
    var pressing = false
    var commit: ((FabulaVerdict) -> Void)?
    private var hold: DispatchWorkItem?

    func beginHold() {
        guard !locked, hold == nil else { return }
        let item = DispatchWorkItem { [weak self] in
            self?.hold = nil
            self?.superlike()
        }
        hold = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: item)
    }

    func cancelHold() {
        hold?.cancel()
        hold = nil
    }

    func drag(_ translation: CGSize) {
        if abs(translation.width) > 8 || abs(translation.height) > 8 { cancelHold() }
        guard !locked else { return }
        offset = translation
    }

    func release(_ translation: CGSize) {
        cancelHold()
        guard !locked else { return }
        if translation.height < -110 && abs(translation.height) > abs(translation.width) {
            fling(.seen)
        } else if translation.width > 110 {
            fling(.yes)
        } else if translation.width < -110 {
            fling(.no)
        } else {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.68)) { offset = .zero }
        }
    }

    func fling(_ verdict: FabulaVerdict) {
        guard !locked else { return }
        cancelHold()
        locked = true
        let target: CGSize
        switch verdict {
        case .yes: target = CGSize(width: 900, height: offset.height + 40)
        case .no: target = CGSize(width: -900, height: offset.height + 40)
        default: target = CGSize(width: offset.width, height: -1100)
        }
        withAnimation(.easeIn(duration: 0.22)) { offset = target }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.23) { [weak self] in self?.finish(verdict) }
    }

    func superlike() {
        guard !locked else { return }
        locked = true
        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) { offset = .zero }
        withAnimation(.linear(duration: 0.5)) { shake = 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }
            self.still { self.shake = 0 }
            withAnimation(.easeOut(duration: 0.15)) { self.gold = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.finish(.superlike) }
        }
    }

    private func finish(_ verdict: FabulaVerdict) {
        commit?(verdict)
        still {
            offset = .zero
            gold = false
            shake = 0
        }
        locked = false
    }

    private func still(_ change: () -> Void) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction, change)
    }
}

struct FabulaPoster: View {
    let url: URL?
    var radius: CGFloat = 8

    var body: some View {
        LinearGradient(colors: [Fab.wash, Fab.surface], startPoint: .top, endPoint: .bottom)
            .overlay {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        Color.clear
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

struct FabulaStamp: View {
    let text: String
    let color: Color
    let angle: Double
    let size: CGFloat

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .heavy))
            .tracking(size * 0.06)
            .foregroundStyle(color)
            .padding(.horizontal, size * 0.35)
            .padding(.vertical, size * 0.06)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(color, lineWidth: 4))
            .rotationEffect(.degrees(angle))
    }
}

struct FabulaPill: View {
    let word: String
    let options: [String]
    let chosen: [String]
    let apply: ([String]) -> Void

    private var label: String {
        if chosen.isEmpty { return word }
        if chosen.count == 1 { return chosen[0] }
        return "\(word) · \(chosen.count)"
    }

    var body: some View {
        Menu {
            Button {
                apply([])
            } label: {
                if chosen.isEmpty { Label("Any", systemImage: "checkmark") } else { Text("Any") }
            }
            Divider()
            ForEach(options, id: \.self) { name in
                Button {
                    apply(chosen.contains(name) ? chosen.filter { $0 != name } : chosen + [name])
                } label: {
                    if chosen.contains(name) { Label(name, systemImage: "checkmark") } else { Text(name) }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(label).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
            }
            .font(Fab.sans(12.5, .semibold))
            .foregroundStyle(chosen.isEmpty ? Fab.muted : Fab.washText)
            .padding(.horizontal, 14)
            .frame(height: 32)
            .background(Capsule().fill(chosen.isEmpty ? Fab.surface : Fab.wash))
            .overlay(Capsule().stroke(chosen.isEmpty ? Fab.line : Fab.wash, lineWidth: 1))
            .contentShape(Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

struct FabulaChoice: View {
    let word: String
    let options: [String]
    let chosen: String
    let apply: (String) -> Void

    var body: some View {
        Menu {
            ForEach(options, id: \.self) { name in
                Button {
                    apply(name)
                } label: {
                    if chosen == name { Label(name, systemImage: "checkmark") } else { Text(name) }
                }
            }
        } label: {
            let active = chosen != options.first
            HStack(spacing: 6) {
                Text(active ? chosen : word).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
            }
            .font(Fab.sans(12.5, .semibold))
            .foregroundStyle(active ? Fab.washText : Fab.muted)
            .padding(.horizontal, 14)
            .frame(height: 32)
            .background(Capsule().fill(active ? Fab.wash : Fab.surface))
            .overlay(Capsule().stroke(active ? Fab.wash : Fab.line, lineWidth: 1))
            .contentShape(Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

struct FabulaFilters: View {
    @ObservedObject var deck: FabulaDeck

    var body: some View {
        HStack(spacing: 8) {
            FabulaPill(word: "Language", options: FabulaDeck.languages, chosen: deck.langs) { deck.setLangs($0) }
            FabulaPill(word: "Genre", options: FabulaDeck.genres, chosen: deck.genres) { deck.setGenres($0) }
        }
    }
}

struct FabulaButton: View {
    let title: String
    var color: Color = Fab.accent
    var filled = false
    var height: CGFloat = 40
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Fab.sans(13.5, .semibold))
                .foregroundStyle(filled ? Fab.onAccent : color)
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(filled ? color : Color.clear))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(filled ? Color.clear : color.opacity(0.9), lineWidth: 1.5))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct FabulaCardFace: View {
    let film: FabulaFilm
    let compact: Bool
    @ObservedObject var motion: FabulaMotion
    @State private var open = false

    private var vertical: Bool { motion.offset.height < 0 && abs(motion.offset.height) > abs(motion.offset.width) }
    private var yesOpacity: Double { vertical ? 0 : Double(min(1, max(0, motion.offset.width / 90))) }
    private var noOpacity: Double { vertical ? 0 : Double(min(1, max(0, -motion.offset.width / 90))) }
    private var seenOpacity: Double { vertical ? Double(min(1, max(0, -motion.offset.height / 90))) : 0 }

    var body: some View {
        ZStack(alignment: .bottom) {
            poster
            if compact {
                Color.black.opacity(open ? 0.72 : 0).allowsHitTesting(false)
                VStack(alignment: .leading, spacing: 0) {
                    title.padding(.horizontal, 18).padding(.bottom, 12)
                    info.background(Fab.surface.opacity(open ? 0 : 1))
                }
            }
        }
        .animation(.easeOut(duration: 0.38), value: open)
        .background(Fab.surface)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(motion.gold ? Fab.gold : Fab.line, lineWidth: motion.gold ? 3 : 1))
        .shadow(color: Color.black.opacity(0.55), radius: 18, y: 14)
    }

    private var poster: some View {
        ZStack(alignment: .bottomLeading) {
            FabulaPoster(url: film.posterURL, radius: 0)
            LinearGradient(colors: [Color.clear, Color.black.opacity(0.75)], startPoint: .center, endPoint: .bottom)
            if !compact { title.padding(18) }
            stamps
            if motion.gold {
                Text("Superlike")
                    .font(Fab.sans(12, .bold))
                    .foregroundStyle(Fab.onGold)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Fab.gold))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(14)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    private var title: some View {
        Text(film.title)
            .font(Fab.serif(compact ? 26 : 32))
            .foregroundStyle(Color.white)
            .lineLimit(3)
            .shadow(color: Color.black.opacity(0.5), radius: 8, y: 2)
    }

    private var stamps: some View {
        let size: CGFloat = compact ? 28 : 34
        return ZStack {
            FabulaStamp(text: "YES", color: Fab.yes, angle: -14, size: size)
                .opacity(yesOpacity)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.top, 66)
                .padding(.leading, 20)
            FabulaStamp(text: "NOPE", color: Fab.no, angle: 14, size: size)
                .opacity(noOpacity)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(.top, 66)
                .padding(.trailing, 20)
            FabulaStamp(text: "SEEN IT", color: Fab.ink, angle: -6, size: size * 0.94)
                .opacity(seenOpacity)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .allowsHitTesting(false)
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(film.meta).font(Fab.sans(12)).foregroundStyle(Fab.muted).lineLimit(1)
            if !film.overview.isEmpty {
                Text(film.overview)
                    .font(Fab.sans(13))
                    .foregroundStyle(Fab.ink)
                    .lineLimit(open ? 14 : 2)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentShape(Rectangle())
                    .onTapGesture { open.toggle() }
                    .accessibilityAddTraits(.isButton)
            }
            if !film.why.isEmpty {
                Text(film.why).font(Fab.sans(12, .semibold)).foregroundStyle(motion.gold ? Fab.gold : Fab.accent).lineLimit(1)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct FabulaStack: View {
    @ObservedObject var deck: FabulaDeck
    @ObservedObject var motion: FabulaMotion
    let compact: Bool

    var body: some View {
        ZStack {
            if deck.cards.count > 1 {
                FabulaCardFace(film: deck.cards[1], compact: compact, motion: FabulaMotion())
                    .scaleEffect(0.94)
                    .offset(y: 10)
                    .opacity(0.6)
                    .allowsHitTesting(false)
            }
            if let film = deck.top {
                ZStack(alignment: .topLeading) {
                    FabulaCardFace(film: film, compact: compact, motion: motion)
                        .contentShape(Rectangle())
                        .gesture(drag)
                    undo
                }
                .modifier(FabulaShake(progress: motion.shake))
                .offset(motion.offset)
                .rotationEffect(.degrees(Double(motion.offset.width / 18)))
                .id(film.tmdb)
            } else {
                empty
            }
        }
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !motion.pressing {
                    motion.pressing = true
                    motion.beginHold()
                }
                motion.drag(value.translation)
            }
            .onEnded { value in
                motion.pressing = false
                motion.release(value.translation)
            }
    }

    private var undo: some View {
        Button { deck.undo(source: compact ? "dropdown" : "window") } label: {
            Image(systemName: "arrow.uturn.backward")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.white)
                .frame(width: 38, height: 38)
                .background(Circle().fill(Color.black.opacity(0.45)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!deck.canUndo)
        .opacity(deck.canUndo ? 1 : 0.45)
        .padding(12)
    }

    @ViewBuilder private var empty: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(Fab.surface)
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Fab.line, lineWidth: 1))
            .overlay {
                if deck.loading {
                    ProgressView().controlSize(.small)
                } else {
                    VStack(spacing: 16) {
                        FabulaLogoMark(side: 56).opacity(0.85)
                        Button { deck.reload(source: "retry") } label: {
                            Text("Retry")
                                .font(Fab.sans(13.5, .semibold))
                                .foregroundStyle(Fab.accent)
                                .padding(.horizontal, 22)
                                .frame(height: 36)
                                .overlay(Capsule().stroke(Fab.accent, lineWidth: 1.5))
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
    }
}

struct FabulaSwiper<Content: View>: View {
    @ObservedObject var deck: FabulaDeck
    @ObservedObject var nav: FabulaNav
    @StateObject private var motion = FabulaMotion()
    let source: String
    let content: (FabulaMotion) -> Content

    init(deck: FabulaDeck, nav: FabulaNav, source: String, @ViewBuilder content: @escaping (FabulaMotion) -> Content) {
        _deck = ObservedObject(wrappedValue: deck)
        _nav = ObservedObject(wrappedValue: nav)
        self.source = source
        self.content = content
    }

    var body: some View {
        content(motion)
            .background(FabulaKeys { event in key(event) })
            .onAppear {
                motion.commit = { verdict in deck.act(verdict, source: source) }
                deck.refill(source: source)
            }
    }

    private func key(_ event: NSEvent) -> Bool {
        guard nav.rating == nil, nav.pick == nil else { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.function, .numericPad, .capsLock])
        if event.type == .keyDown, event.keyCode == 6, flags == .command {
            deck.undo(source: source + " key")
            return true
        }
        guard flags.isEmpty, deck.top != nil else { return false }
        switch (event.type, event.keyCode) {
        case (.keyDown, 123):
            if !event.isARepeat { motion.fling(.no) }
            return true
        case (.keyDown, 124):
            if !event.isARepeat { motion.fling(.yes) }
            return true
        case (.keyDown, 126):
            if !event.isARepeat { motion.fling(.seen) }
            return true
        case (.keyDown, 49):
            if !event.isARepeat { motion.beginHold() }
            return true
        case (.keyUp, 49):
            motion.cancelHold()
            return true
        default:
            return false
        }
    }
}

struct FabulaActionButton: View {
    let title: String
    let color: Color
    let strong: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Fab.sans(13, .semibold))
                .foregroundStyle(color)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Fab.surface))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(strong ? color : Fab.line, lineWidth: strong ? 1.5 : 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct FabulaRecommend: View {
    @ObservedObject var deck: FabulaDeck
    @ObservedObject var nav: FabulaNav

    var body: some View {
        FabulaSwiper(deck: deck, nav: nav, source: "window") { motion in
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .center) {
                    Text("What are we watching?").font(Fab.serif(28))
                    Spacer()
                    FabulaFilters(deck: deck)
                }
                HStack(alignment: .top, spacing: 28) {
                    FabulaStack(deck: deck, motion: motion, compact: false)
                        .frame(width: 340)
                        .frame(maxHeight: .infinity)
                    details(motion)
                }
                .frame(maxHeight: .infinity)
                tonight
            }
            .padding(.horizontal, 32)
            .padding(.top, 30)
            .padding(.bottom, 22)
        }
    }

    @ViewBuilder private func details(_ motion: FabulaMotion) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if let film = deck.top {
                Text(film.meta).font(Fab.sans(14)).foregroundStyle(Fab.muted)
                if !film.overview.isEmpty {
                    Text(film.overview).font(Fab.sans(19)).lineSpacing(5).foregroundStyle(Fab.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !film.why.isEmpty {
                    Text(film.why).font(Fab.sans(14, .semibold)).foregroundStyle(Fab.accent)
                }
                if !film.people.isEmpty {
                    Text(film.people).font(Fab.sans(14)).foregroundStyle(Fab.muted)
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 10) {
                FabulaActionButton(title: "No", color: Fab.no, strong: true) { motion.fling(.no) }
                FabulaActionButton(title: "Seen it", color: Fab.muted, strong: false) { motion.fling(.seen) }
                FabulaActionButton(title: "Superlike", color: Fab.gold, strong: true) { motion.superlike() }
                FabulaActionButton(title: "Yes", color: Fab.yes, strong: true) { motion.fling(.yes) }
            }
            .disabled(deck.top == nil)
            .opacity(deck.top == nil ? 0.4 : 1)
        }
        .padding(.top, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder private var tonight: some View {
        if !deck.tonight.isEmpty {
            HStack(spacing: 10) {
                Text("Your yeses tonight").font(Fab.sans(12)).foregroundStyle(Fab.faint).frame(width: 120, alignment: .leading)
                ForEach(deck.tonight.prefix(10)) { film in
                    FabulaPoster(url: film.thumbURL, radius: 6)
                        .frame(width: 46, height: 68)
                        .help(film.title)
                }
                Spacer(minLength: 0)
            }
        }
    }
}

struct FabulaPick: View {
    let film: FabulaFilm
    let others: [FabulaFilm]
    let compact: Bool
    let watch: () -> Void
    let keep: () -> Void

    var body: some View {
        Group {
            if compact {
                VStack(alignment: .leading, spacing: 14) {
                    kicker
                    FabulaPoster(url: film.posterURL, radius: 18)
                        .frame(maxWidth: .infinity)
                        .frame(height: 260)
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Fab.gold, lineWidth: 3))
                    text
                    Spacer(minLength: 0)
                    buttons
                }
                .padding(18)
            } else {
                HStack(alignment: .top, spacing: 36) {
                    FabulaPoster(url: film.posterURL, radius: 22)
                        .aspectRatio(2.0 / 3.0, contentMode: .fit)
                        .frame(maxWidth: 360)
                        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Fab.gold, lineWidth: 3))
                    VStack(alignment: .leading, spacing: 18) {
                        kicker
                        text
                        if !others.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Your other yeses tonight").font(Fab.sans(12)).foregroundStyle(Fab.faint)
                                HStack(spacing: 10) {
                                    ForEach(others.prefix(6)) { other in
                                        FabulaPoster(url: other.thumbURL, radius: 6).frame(width: 52, height: 78).help(other.title)
                                    }
                                }
                            }
                            .padding(.top, 8)
                        }
                        Spacer(minLength: 0)
                        buttons.frame(maxWidth: 420)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(40)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Fab.ground)
    }

    private var kicker: some View {
        Text("TONIGHT'S PICK").font(Fab.sans(11, .bold)).tracking(1.4).foregroundStyle(Fab.gold)
    }

    private var text: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(film.title).font(Fab.serif(compact ? 26 : 38)).foregroundStyle(Fab.ink).fixedSize(horizontal: false, vertical: true)
            Text(film.credits).font(Fab.sans(compact ? 12.5 : 15)).foregroundStyle(Fab.muted)
            if let streaming = film.streaming {
                Text(streaming).font(Fab.serif(compact ? 15 : 19, .semibold)).foregroundStyle(Fab.yes).padding(.top, 4)
            }
        }
    }

    private var buttons: some View {
        HStack(spacing: 10) {
            FabulaButton(title: "Watch this tonight", filled: true, height: 44, action: watch)
            FabulaButton(title: "Keep swiping", color: Fab.muted, height: 44, action: keep)
        }
    }
}

struct FabulaRateSheet: View {
    let sheet: FabulaRating
    let compact: Bool
    @State private var rating: Double?
    @State private var comment: String

    init(sheet: FabulaRating, compact: Bool) {
        self.sheet = sheet
        self.compact = compact
        _rating = State(initialValue: sheet.rating)
        _comment = State(initialValue: sheet.comment)
    }

    private var source: String { compact ? "dropdown" : "window" }

    var body: some View {
        ZStack(alignment: compact ? Alignment.bottom : Alignment.center) {
            Color.black.opacity(0.55)
                .contentShape(Rectangle())
                .onTapGesture {
                    note("fabula rating dismissed tmdb=\(sheet.film.tmdb) source=\(source)")
                    FabulaNav.shared.rating = nil
                }
            panel
                .frame(maxWidth: compact ? CGFloat.infinity : 440)
                .background(
                    UnevenRoundedRectangle(topLeadingRadius: 24, bottomLeadingRadius: compact ? 0 : 24,
                                           bottomTrailingRadius: compact ? 0 : 24, topTrailingRadius: 24, style: .continuous)
                        .fill(Fab.surface)
                )
                .overlay(
                    UnevenRoundedRectangle(topLeadingRadius: 24, bottomLeadingRadius: compact ? 0 : 24,
                                           bottomTrailingRadius: compact ? 0 : 24, topTrailingRadius: 24, style: .continuous)
                        .stroke(Fab.line, lineWidth: 1)
                )
        }
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                FabulaPoster(url: sheet.film.thumbURL, radius: 6).frame(width: 40, height: 60)
                VStack(alignment: .leading, spacing: 4) {
                    Text("How was \(sheet.film.title)?").font(Fab.serif(20)).foregroundStyle(Fab.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(sheet.film.credits).font(Fab.sans(12.5)).foregroundStyle(Fab.muted)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
                ForEach(1...10, id: \.self) { value in
                    let on = rating.map { Int($0.rounded(.down)) == value } ?? false
                    Button { rating = Double(value) } label: {
                        Text("\(value)")
                            .font(Fab.sans(16, .semibold))
                            .foregroundStyle(on ? Fab.onAccent : Fab.ink)
                            .frame(maxWidth: .infinity)
                            .frame(height: 42)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(on ? Fab.accent : Fab.ground))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(on ? Fab.accent : Fab.line, lineWidth: 1))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            TextField("Tell us about the movie!", text: $comment, axis: .vertical)
                .textFieldStyle(.plain)
                .font(Fab.sans(13.5))
                .foregroundStyle(Fab.ink)
                .lineLimit(2...4)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Fab.ground))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Fab.line, lineWidth: 1))
            HStack(spacing: 10) {
                if sheet.mode == .edit {
                    FabulaButton(title: "Delete", color: Fab.no, height: 42) { close(save: false) }
                } else {
                    FabulaButton(title: "Skip rating", color: Fab.muted, height: 42) { close(save: false) }
                }
                FabulaButton(title: "Save to Log", filled: true, height: 42) { close(save: true) }
                    .disabled(rating == nil)
                    .opacity(rating == nil ? 0.5 : 1)
            }
        }
        .padding(20)
    }

    private func close(save: Bool) {
        FabulaNav.shared.finish(sheet, rating: rating, comment: comment, save: save && rating != nil, source: source)
    }
}

struct FabulaOverlays: View {
    @ObservedObject var deck: FabulaDeck
    @ObservedObject var nav: FabulaNav
    let compact: Bool

    var body: some View {
        ZStack {
            if let film = nav.pick {
                FabulaPick(film: film, others: deck.tonight.filter { $0.tmdb != film.tmdb }, compact: compact,
                           watch: { nav.watch(film, source: compact ? "dropdown" : "window") },
                           keep: { nav.pick = nil })
            }
            if let sheet = nav.rating {
                FabulaRateSheet(sheet: sheet, compact: compact).id(sheet.id)
            }
        }
    }
}

struct FabulaRoot: View {
    @ObservedObject var store: OrtusStore
    @ObservedObject var deck: FabulaDeck
    @ObservedObject var nav: FabulaNav

    var body: some View {
        HStack(spacing: 0) {
            rail
            Rectangle().fill(Fab.railLine).frame(width: 1)
            ZStack {
                switch nav.tab {
                case .recommend: FabulaRecommend(deck: deck, nav: nav)
                case .watchlist: FabulaWatchlist(store: store, nav: nav)
                case .log: FabulaLog(store: store, nav: nav)
                case .refiner: FabulaRefinerView(refiner: FabulaRefiner.shared, nav: nav)
                case .ai: FabulaAIView(ai: FabulaAI.shared)
                }
                FabulaOverlays(deck: deck, nav: nav, compact: false)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Fab.ground)
        .foregroundStyle(Fab.ink)
        .environment(\.colorScheme, .dark)
        .ignoresSafeArea()
    }

    private var rail: some View {
        VStack(spacing: 10) {
            Spacer().frame(height: 40)
            FabulaLogoMark(side: 44).padding(.bottom, 8)
            ForEach(FabulaTab.allCases) { tab in
                let on = nav.tab == tab
                Button {
                    nav.tab = tab
                    note("fabula tab changed tab=\(tab.rawValue)")
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.symbol).font(.system(size: 17, weight: .semibold)).frame(height: 22)
                        Text(tab.title).font(Fab.sans(11, .semibold))
                    }
                    .foregroundStyle(on ? Fab.accent : Fab.muted)
                    .frame(width: 68, height: 58)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(on ? Fab.wash : Color.clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .frame(width: 84)
        .frame(maxHeight: .infinity)
        .background(Fab.rail)
    }
}

struct FabulaRow<Trailing: View>: View {
    let thumb: URL?
    let title: String
    let detail: String
    var caption: String = ""
    var gold = false
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 14) {
            FabulaPoster(url: thumb, radius: 6).frame(width: 46, height: 68)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(Fab.sans(14.5, .semibold)).foregroundStyle(Fab.ink).lineLimit(1)
                if !detail.isEmpty { Text(detail).font(Fab.sans(12.5)).foregroundStyle(Fab.muted).lineLimit(2) }
                if !caption.isEmpty { Text(caption).font(Fab.sans(11.5)).foregroundStyle(gold ? Fab.gold : Fab.faint).lineLimit(1) }
            }
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Fab.surface))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(gold ? Fab.gold.opacity(0.8) : Fab.line, lineWidth: gold ? 1.5 : 1))
    }
}

struct FabulaSmallButton: View {
    let title: String
    var color: Color = Fab.accent
    var outlined = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Fab.sans(12, .semibold))
                .foregroundStyle(color)
                .padding(.horizontal, 12)
                .frame(height: 30)
                .overlay(Capsule().stroke(outlined ? color : Color.clear, lineWidth: 1.2))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct FabulaWatchlist: View {
    @ObservedObject var store: OrtusStore
    @ObservedObject var nav: FabulaNav
    @State private var langs: [String] = []
    @State private var genres: [String] = []
    @State private var added = "Any time"

    private static let spans = ["Any time", "This week", "This month"]

    private var all: [FabulaEntry] { store.watchlist }

    private var list: [FabulaEntry] {
        let days: Double = added == "This week" ? 7 : added == "This month" ? 31 : 0
        let since: Date? = days > 0 ? Date().addingTimeInterval(-days * 86400) : nil
        return all.filter { (entry: FabulaEntry) -> Bool in matches(entry, since: since) }
    }

    private func matches(_ entry: FabulaEntry, since: Date?) -> Bool {
        if !langs.isEmpty && !langs.contains(entry.language) { return false }
        if !genres.isEmpty && Set(genres).isDisjoint(with: entry.genres) { return false }
        if let since {
            let when = FabulaClock.date(entry.at) ?? Date.distantPast
            if when < since { return false }
        }
        return true
    }

    private func ranked(_ values: [String]) -> [String] {
        var counts: [String: Int] = [:]
        for value in values where !value.isEmpty { counts[value, default: 0] += 1 }
        return counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.map(\.key)
    }

    var body: some View {
        let items = list
        let supers = items.filter { $0.verdict == .superlike }
        let yeses = items.filter { $0.verdict != .superlike }
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("Watchlist").font(Fab.serif(28))
                Text("\(items.count) films").font(Fab.sans(13)).foregroundStyle(Fab.muted)
                Spacer()
            }
            HStack(spacing: 8) {
                FabulaPill(word: "Language", options: ranked(all.map(\.language)), chosen: langs) { langs = $0 }
                FabulaPill(word: "Genre", options: ranked(all.flatMap(\.genres)), chosen: genres) { genres = $0 }
                FabulaChoice(word: "Added", options: Self.spans, chosen: added) { added = $0 }
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if !supers.isEmpty {
                        section("Superlikes · \(supers.count)", color: Fab.gold)
                        ForEach(supers) { entry in row(entry) }
                    }
                    if !yeses.isEmpty {
                        section("Yeses · \(yeses.count)", color: Fab.muted).padding(.top, supers.isEmpty ? 0 : 10)
                        ForEach(yeses) { entry in row(entry) }
                    }
                }
                .padding(.bottom, 20)
            }
            .scrollIndicators(.never)
        }
        .padding(.horizontal, 32)
        .padding(.top, 30)
        .frame(maxWidth: 820, maxHeight: .infinity, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func section(_ text: String, color: Color) -> some View {
        Text(text.uppercased()).font(Fab.sans(11, .bold)).tracking(1.2).foregroundStyle(color)
    }

    private func row(_ entry: FabulaEntry) -> some View {
        FabulaRow(thumb: entry.thumbURL, title: entry.title, detail: entry.meta, caption: FabulaFormat.added(entry.at),
                  gold: entry.verdict == .superlike) {
            HStack(spacing: 8) {
                FabulaSmallButton(title: "Seen it") {
                    if let film = entry.film { nav.rate(film, mode: .seen) }
                }
                FabulaSmallButton(title: "Remove", color: Fab.faint, outlined: false) {
                    store.unswipe(entry.id, source: "watchlist")
                }
            }
        }
    }
}

enum FabulaSort: String, CaseIterable {
    case rating = "Rating"
    case recent = "Recently logged"
    case title = "Title"
    case year = "Year"
}

struct FabulaLog: View {
    @ObservedObject var store: OrtusStore
    @ObservedObject var nav: FabulaNav
    @StateObject private var search = FabulaSearch()
    @State private var query = ""
    @State private var sort: FabulaSort = FabulaSort(rawValue: UserDefaults.standard.string(forKey: "fabula.sort") ?? "") ?? .rating
    @State private var adding = false
    @FocusState private var focused: Bool

    private var list: [FabulaEntry] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let found = store.logs.filter { (entry: FabulaEntry) -> Bool in Self.matches(entry, text) }
        let order = sort
        return found.sorted { (a: FabulaEntry, b: FabulaEntry) -> Bool in Self.before(a, b, by: order) }
    }

    private static func matches(_ entry: FabulaEntry, _ text: String) -> Bool {
        if text.isEmpty { return true }
        if entry.title.localizedCaseInsensitiveContains(text) { return true }
        if entry.comment.localizedCaseInsensitiveContains(text) { return true }
        return entry.director.localizedCaseInsensitiveContains(text)
    }

    private static func before(_ a: FabulaEntry, _ b: FabulaEntry, by sort: FabulaSort) -> Bool {
        switch sort {
        case .rating:
            let left = a.rating ?? 0
            let right = b.rating ?? 0
            if left != right { return left > right }
            return FabulaClock.newer(a.logged, than: b.logged)
        case .recent:
            return FabulaClock.newer(a.logged, than: b.logged)
        case .title:
            return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
        case .year:
            let left = a.year ?? 0
            let right = b.year ?? 0
            if left != right { return left > right }
            return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
        }
    }

    private var average: String {
        let rated = store.logs.compactMap(\.rating)
        guard !rated.isEmpty else { return "–" }
        return String(format: "%.1f", rated.reduce(0, +) / Double(rated.count))
    }

    private var decade: String {
        var groups: [Int: [Double]] = [:]
        for entry in store.logs {
            guard let year = entry.year, let rating = entry.rating else { continue }
            groups[year / 10 * 10, default: []].append(rating)
        }
        let solid = groups.filter { $0.value.count >= 3 }
        let pool = solid.isEmpty ? groups : solid
        var best: (decade: Int, mean: Double, count: Int)?
        for (decade, ratings) in pool {
            let mean = ratings.reduce(0, +) / Double(max(1, ratings.count))
            if let current = best, current.mean > mean || (current.mean == mean && current.count >= ratings.count) { continue }
            best = (decade: decade, mean: mean, count: ratings.count)
        }
        guard let best else { return "–" }
        return "\(best.decade)s"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center) {
                Text("Log").font(Fab.serif(28))
                Spacer()
                FabulaSmallButton(title: adding ? "Done" : "+ Add film", color: adding ? Fab.muted : Fab.accent) {
                    adding.toggle()
                    search.reset()
                    focused = adding
                }
            }
            if adding { finder } else { logList }
        }
        .padding(.horizontal, 32)
        .padding(.top, 30)
        .frame(maxWidth: 820, maxHeight: .infinity, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var logList: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                stat("\(store.logs.count)", "films logged")
                stat(average, "your average")
                stat(decade, "best decade")
            }
            HStack(spacing: 10) {
                field(text: $query, prompt: "Search \(store.logs.count) films")
                Menu {
                    ForEach(FabulaSort.allCases, id: \.self) { option in
                        Button {
                            sort = option
                            UserDefaults.standard.set(option.rawValue, forKey: "fabula.sort")
                        } label: {
                            if sort == option { Label(option.rawValue, systemImage: "checkmark") } else { Text(option.rawValue) }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(sort.rawValue)
                        Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
                    }
                    .font(Fab.sans(12.5, .semibold))
                    .foregroundStyle(Fab.muted)
                    .padding(.horizontal, 14)
                    .frame(height: 36)
                    .background(Capsule().fill(Fab.surface))
                    .overlay(Capsule().stroke(Fab.line, lineWidth: 1))
                    .contentShape(Capsule())
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
            }
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(list) { entry in
                        Button { edit(entry) } label: {
                            FabulaRow(thumb: entry.thumbURL, title: entry.heading, detail: entry.comment) {
                                Text(FabulaFormat.rating(entry.rating))
                                    .font(Fab.serif(20))
                                    .foregroundStyle(Fab.ratingColor(entry.rating))
                                    .frame(minWidth: 36, alignment: .trailing)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Edit") { edit(entry) }
                            Button("Delete") { store.deleteLog(entry.id, source: "log menu") }
                        }
                    }
                }
                .padding(.bottom, 20)
            }
            .scrollIndicators(.never)
        }
    }

    private var finder: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                field(text: $search.query, prompt: "Search all films")
                if search.busy { ProgressView().controlSize(.small) }
            }
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(search.hits) { hit in
                        Button { pick(hit) } label: {
                            FabulaRow(thumb: hit.thumbURL, title: hit.title, detail: hit.meta) {
                                if search.adding == hit.tmdb {
                                    ProgressView().controlSize(.small)
                                } else if store.log(String(hit.tmdb)) != nil {
                                    Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundStyle(Fab.yes)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.bottom, 20)
            }
            .scrollIndicators(.never)
        }
    }

    private func field(text: Binding<String>, prompt: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 12, weight: .semibold)).foregroundStyle(Fab.faint)
            TextField(prompt, text: text)
                .textFieldStyle(.plain)
                .font(Fab.sans(13.5))
                .foregroundStyle(Fab.ink)
                .focused($focused)
        }
        .padding(.horizontal, 14)
        .frame(height: 36)
        .background(Capsule().fill(Fab.surface))
        .overlay(Capsule().stroke(Fab.line, lineWidth: 1))
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(Fab.serif(26)).foregroundStyle(Fab.ink)
            Text(label).font(Fab.sans(12)).foregroundStyle(Fab.muted)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Fab.surface))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Fab.line, lineWidth: 1))
    }

    private func edit(_ entry: FabulaEntry) {
        guard let film = entry.film else { return }
        nav.rate(film, mode: .edit)
    }

    private func pick(_ hit: FabulaHit) {
        if let existing = store.log(String(hit.tmdb)), let film = existing.film {
            nav.rate(film, mode: .edit)
            return
        }
        search.add(hit) { film in
            adding = false
            search.reset()
            nav.rate(film, mode: .seen)
        }
    }
}

struct FabulaIconButton: View {
    let symbol: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Fab.ink)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Fab.surface))
                .overlay(Circle().stroke(Fab.line, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

struct FabulaGlance: View {
    @ObservedObject var deck: FabulaDeck
    @ObservedObject var nav: FabulaNav
    let open: (FabulaTab?) -> Void

    var body: some View {
        ZStack {
            FabulaSwiper(deck: deck, nav: nav, source: "dropdown") { motion in
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        FabulaLogoMark(side: 30)
                        Text("Fabula").font(Fab.serif(22))
                        Spacer()
                        FabulaIconButton(symbol: "bookmark", help: "Watchlist") { open(.watchlist) }
                        FabulaIconButton(symbol: "list.bullet", help: "Log") { open(.log) }
                        FabulaIconButton(symbol: "arrow.up.left.and.arrow.down.right", help: "Open Fabula") { open(.recommend) }
                    }
                    FabulaFilters(deck: deck)
                    FabulaStack(deck: deck, motion: motion, compact: true)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.bottom, 6)
                }
                .padding(16)
            }
            FabulaOverlays(deck: deck, nav: nav, compact: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Fab.ground)
        .foregroundStyle(Fab.ink)
        .environment(\.colorScheme, .dark)
        .ignoresSafeArea()
    }
}
