import AppKit
import SwiftUI
import WebKit

enum Ort {
    static let ground = Color(red: 0.992, green: 0.890, blue: 0.847)
    static let paper = Color(red: 1.0, green: 0.973, blue: 0.957)
    static let card = Color.white
    static let ink = Color(red: 0.227, green: 0.122, blue: 0.078)
    static let muted = Color(red: 0.431, green: 0.290, blue: 0.231)
    static let line = Color(red: 0.941, green: 0.839, blue: 0.792)
    static let edge = Color(red: 0.922, green: 0.788, blue: 0.725)
    static let accent = Color(red: 0.761, green: 0.275, blue: 0.122)
    static let bright = Color(red: 0.851, green: 0.329, blue: 0.173)
    static let deep = Color(red: 0.561, green: 0.196, blue: 0.082)
    static let night = Color(red: 0.165, green: 0.086, blue: 0.055)
    static let nightCard = Color(red: 0.290, green: 0.149, blue: 0.094)
    static let nightText = Color(red: 0.965, green: 0.804, blue: 0.733)

    static func serif(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font { .system(size: size, weight: weight, design: .serif) }
    static func sans(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font { .system(size: size, weight: weight) }

    static let logo: NSImage? = Data(base64Encoded: OrtusLogo.jpeg, options: .ignoreUnknownCharacters).flatMap(NSImage.init(data:))

    static func kicker(_ text: String, color: Color = Ort.deep) -> some View {
        Text(text.uppercased()).font(sans(10.5, .semibold)).tracking(1.2).foregroundStyle(color)
    }
}

enum OrtusMode: String, CaseIterable, Identifiable {
    case quotes, reels, videos, stories

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .quotes: return "quote.opening"
        case .reels: return "rectangle.portrait.on.rectangle.portrait"
        case .videos: return "play.rectangle"
        case .stories: return "book"
        }
    }
}

final class OrtusNav: ObservableObject {
    static let shared = OrtusNav()

    @Published var mode: OrtusMode = OrtusMode(rawValue: UserDefaults.standard.string(forKey: "ortus.mode") ?? "") ?? .quotes {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: "ortus.mode") }
    }
    @Published var story: String?
    @Published var reel: String?
    @Published var settings = false
}

struct OrtusLogoMark: View {
    let side: CGFloat

    var body: some View {
        Group {
            if let logo = Ort.logo {
                Image(nsImage: logo).resizable().interpolation(.high)
            } else {
                Ort.ground
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: side * 0.27, style: .continuous))
    }
}

final class OrtusApp: PocketApp {
    override var defaultSize: NSSize { NSSize(width: 380, height: 600) }
    override var minSize: NSSize { NSSize(width: 380, height: 600) }
    override var resizable: Bool { false }

    override func start() {
        let store = OrtusStore.shared
        store.onChange = { [weak self] in self?.changed() }
        note("ortus app started quotes=\(store.allQuotes.count) stories=\(store.stories.count) reels=\(store.reels.count) videos=\(store.videos.count)")
    }

    override func stop() {
        OrtusStore.shared.onChange = nil
        super.stop()
    }

    override func makeContent() -> NSView {
        let view = OrtusGlance(store: OrtusStore.shared) { [weak self] mode, story, reel in
            self?.openWindow(mode: mode, story: story, reel: reel, source: "dropdown")
        }
        return NSHostingView(rootView: view)
    }

    func openWindow(mode: OrtusMode?, story: String? = nil, reel: String? = nil, source: String) {
        hide(reason: "switched")
        let nav = OrtusNav.shared
        if let mode { nav.mode = mode }
        if let story { nav.story = story }
        if let reel { nav.reel = reel }
        nav.settings = false
        OrtusWindow.shared.present(source: source)
    }

    override func menuItems() -> [NSMenuItem] {
        let open = NSMenuItem(title: "Open Ortus", action: #selector(openFromMenu), keyEquivalent: "")
        open.target = self
        return [open]
    }

    @objc private func openFromMenu() { openWindow(mode: nil, source: "menu") }
}

final class OrtusWindow: NSObject, NSWindowDelegate {
    static let shared = OrtusWindow()

    private var window: NSWindow?

    func present(source: String) {
        NSApp.setActivationPolicy(.regular)
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            note("ortus window refocused source=\(source) mode=\(OrtusNav.shared.mode.rawValue)")
            return
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 720),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = "Ortus"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.appearance = NSAppearance(named: .aqua)
        window.backgroundColor = NSColor(Ort.paper)
        let host = NSHostingView(rootView: OrtusRoot(store: OrtusStore.shared, nav: OrtusNav.shared))
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
        note("ortus window opened source=\(source) mode=\(OrtusNav.shared.mode.rawValue)")
    }

    func windowWillClose(_ notification: Notification) {
        let closing = window
        window?.contentView = nil
        window?.delegate = nil
        window = nil
        let others = NSApp.windows.contains { $0 !== closing && $0.isVisible && $0.styleMask.contains(.titled) && $0.canBecomeMain }
        if !others { NSApp.setActivationPolicy(.accessory) }
        note("ortus window closed otherWindows=\(others)")
    }
}

struct OrtusPlayer: NSViewRepresentable {
    let url: URL?

    final class Coordinator {
        var loaded: URL?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = []
        config.preferences.isElementFullscreenEnabled = true
        let view = WKWebView(frame: .zero, configuration: config)
        view.setValue(false, forKey: "drawsBackground")
        load(view, context: context)
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        load(view, context: context)
    }

    static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) {
        view.loadHTMLString("", baseURL: nil)
    }

    private func load(_ view: WKWebView, context: Context) {
        guard context.coordinator.loaded != url else { return }
        context.coordinator.loaded = url
        guard let url else {
            view.loadHTMLString("", baseURL: nil)
            return
        }
        let page = """
        <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"><style>html,body{margin:0;height:100%;background:#2A160E;overflow:hidden}iframe{border:0;width:100%;height:100%;display:block}</style></head>
        <body><iframe src="\(url.absoluteString)" allow="autoplay; encrypted-media; picture-in-picture; fullscreen; clipboard-write" allowfullscreen referrerpolicy="strict-origin-when-cross-origin"></iframe></body></html>
        """
        view.loadHTMLString(page, baseURL: URL(string: "https://gaone1906.github.io/Pocket/ortus/"))
        note("ortus player load host=\(url.host ?? "") path=\(url.path)")
    }
}

struct OrtusChip: View {
    let title: String
    let on: Bool
    var dark = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Ort.sans(12, on ? .semibold : .medium))
                .padding(.horizontal, 12)
                .frame(height: 28)
                .foregroundStyle(on ? Color.white : (dark ? Ort.nightText : Ort.ink))
                .background(Capsule().fill(on ? (dark ? Ort.bright : Ort.ink) : (dark ? Color.clear : Ort.card)))
                .overlay(Capsule().stroke(on ? Color.clear : (dark ? Ort.nightCard : Ort.edge), lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct OrtusIconButton: View {
    let symbol: String
    let help: String
    var solid = false
    var size: CGFloat = 38
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: size, height: size)
                .foregroundStyle(solid ? Color.white : Ort.ink)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(solid ? Ort.accent : Ort.ground))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

struct OrtusChipRow: View {
    let items: [(String, Int)]
    let current: String
    var dark = false
    let pick: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                OrtusChip(title: "All · \(items.reduce(0) { $0 + $1.1 })", on: current.isEmpty, dark: dark) { pick("") }
                ForEach(items.filter { $0.1 > 0 }, id: \.0) { item in
                    OrtusChip(title: "\(item.0) · \(item.1)", on: current == item.0, dark: dark) { pick(item.0) }
                }
            }
        }
    }
}

struct OrtusEmpty: View {
    let title: String
    let text: String
    var dark = false

    var body: some View {
        VStack(spacing: 8) {
            Text(title).font(Ort.serif(22))
            Text(text).font(Ort.sans(13)).multilineTextAlignment(.center)
        }
        .foregroundStyle(dark ? Ort.nightText : Ort.muted)
        .frame(maxWidth: 360)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct OrtusRoot: View {
    @ObservedObject var store: OrtusStore
    @ObservedObject var nav: OrtusNav

    var body: some View {
        HStack(spacing: 0) {
            rail
            Rectangle().fill(Ort.line).frame(width: 1)
            Group {
                if nav.settings {
                    OrtusSettings(store: store)
                } else {
                    switch nav.mode {
                    case .quotes: OrtusQuotesView(store: store)
                    case .reels: OrtusReelsView(store: store, nav: nav)
                    case .videos: OrtusVideosView(store: store)
                    case .stories: OrtusStoriesView(store: store, nav: nav)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Ort.paper)
        .foregroundStyle(Ort.ink)
        .environment(\.colorScheme, .light)
        .ignoresSafeArea()
    }

    private var rail: some View {
        VStack(spacing: 6) {
            Spacer().frame(height: 40)
            OrtusLogoMark(side: 44).padding(.bottom, 14)
            ForEach(OrtusMode.allCases) { mode in
                let on = nav.mode == mode && !nav.settings
                Button {
                    nav.settings = false
                    nav.mode = mode
                    note("ortus mode changed mode=\(mode.rawValue)")
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: mode.symbol).font(.system(size: 18, weight: .regular)).frame(height: 22)
                        Text(mode.title).font(Ort.sans(11, on ? .semibold : .medium))
                    }
                    .foregroundStyle(on ? Color.white : Ort.muted)
                    .frame(width: 68, height: 58)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(on ? Ort.accent : Color.clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Button { nav.settings.toggle() } label: {
                Image(systemName: "gearshape").font(.system(size: 18))
                    .foregroundStyle(nav.settings ? Ort.deep : Ort.muted)
                    .frame(width: 44, height: 44)
                    .background(RoundedRectangle(cornerRadius: 12).fill(nav.settings ? Ort.paper : Color.clear))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(",", modifiers: .command)
            .help("Settings")
            .padding(.bottom, 18)
        }
        .frame(width: 88)
        .frame(maxHeight: .infinity)
        .background(Ort.ground)
    }
}

struct OrtusHeading: View {
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(Ort.serif(28))
            Spacer()
            Text(detail).font(Ort.sans(12)).foregroundStyle(Ort.muted)
        }
    }
}

struct OrtusQuotesView: View {
    @ObservedObject var store: OrtusStore
    @State private var theme = UserDefaults.standard.string(forKey: "ortus.theme") ?? ""
    @State private var index = 0
    @State private var copied = false

    private var list: [OrtusQuote] {
        let pool = theme.isEmpty ? store.quotes : store.quotes.filter { $0.theme == theme }
        return OrtusPick.ordered(pool, kind: "ortus.quote")
    }

    var body: some View {
        let items = list
        VStack(alignment: .leading, spacing: 16) {
            OrtusHeading(title: "Quotes", detail: "\(store.quotes.count) quotes · \(Set(store.quotes.map(\.author)).count) voices")
            OrtusChipRow(items: OrtusPick.quoteThemes.map { name in (name, store.quotes.filter { $0.theme == name }.count) }, current: theme) { picked in
                theme = picked
                index = 0
                UserDefaults.standard.set(picked, forKey: "ortus.theme")
            }
            if items.isEmpty {
                OrtusEmpty(title: "No quotes yet", text: "They arrive with the next cloud sync.")
            } else {
                let at = ((index % items.count) + items.count) % items.count
                featured(items[at], today: at == 0 && theme.isEmpty, count: items.count, at: at)
                HStack(alignment: .top, spacing: 14) {
                    ForEach(1...3, id: \.self) { step in
                        let quote = items[(at + step) % items.count]
                        Button { index = at + step } label: { small(quote) }.buttonStyle(.plain)
                    }
                }
                .frame(maxHeight: 150)
            }
        }
        .padding(.horizontal, 32)
        .padding(.top, 34)
        .padding(.bottom, 26)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(keys)
    }

    private var keys: some View {
        Group {
            Button("") { index += 1 }.keyboardShortcut(.rightArrow, modifiers: [])
            Button("") { index -= 1 }.keyboardShortcut(.leftArrow, modifiers: [])
        }
        .opacity(0)
    }

    private func featured(_ quote: OrtusQuote, today: Bool, count: Int, at: Int) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Ort.kicker(today ? "Today · \(quote.theme)" : quote.theme, color: Ort.ground)
            Text("“\(quote.text)”")
                .font(Ort.serif(quote.text.count > 180 ? 25 : 32, .medium))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 780, alignment: .leading)
            Spacer(minLength: 0)
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(quote.author).font(Ort.sans(15, .semibold))
                    if !quote.credit.isEmpty { Text(quote.credit).font(Ort.sans(13)).foregroundStyle(Ort.ground) }
                }
                Spacer()
                Text("\(at + 1) of \(count)").font(Ort.sans(12)).foregroundStyle(Ort.ground)
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString("“\(quote.text)” — \(quote.author)", forType: .string)
                    copied = true
                    note("ortus quote copied id=\(quote.id)")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { copied = false }
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc").font(.system(size: 14, weight: .semibold))
                        .frame(width: 40, height: 40)
                        .overlay(RoundedRectangle(cornerRadius: 11).stroke(Color.white.opacity(0.45), lineWidth: 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Copy quote")
                Button { index -= 1 } label: { roundLabel("chevron.left", fill: false) }.buttonStyle(.plain).help("Previous")
                Button { index += 1 } label: { roundLabel("chevron.right", fill: true) }.buttonStyle(.plain).help("Next quote")
            }
        }
        .foregroundStyle(Color.white)
        .padding(.horizontal, 44)
        .padding(.vertical, 34)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Ort.accent))
    }

    private func roundLabel(_ symbol: String, fill: Bool) -> some View {
        Image(systemName: symbol).font(.system(size: 14, weight: .bold))
            .frame(width: 40, height: 40)
            .foregroundStyle(fill ? Ort.deep : Color.white)
            .background(RoundedRectangle(cornerRadius: 11).fill(fill ? Color.white : Color.white.opacity(0.14)))
            .contentShape(Rectangle())
    }

    private func small(_ quote: OrtusQuote) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("“\(quote.text)”").font(Ort.serif(15, .medium)).lineLimit(4).multilineTextAlignment(.leading)
            Spacer(minLength: 0)
            Text("\(quote.author) · \(quote.theme)").font(Ort.sans(12)).foregroundStyle(Ort.muted).lineLimit(1)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Ort.card))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Ort.line, lineWidth: 1))
        .contentShape(Rectangle())
    }
}

struct OrtusThumb: View {
    let clip: OrtusClip
    var radius: CGFloat = 12

    var body: some View {
        ZStack {
            Ort.nightCard
            AsyncImage(url: URL(string: "https://i.ytimg.com/vi/\(clip.video)/hqdefault.jpg")) { phase in
                if let image = phase.image { image.resizable().aspectRatio(contentMode: .fill) } else { Color.clear }
            }
            Image(systemName: "play.fill").font(.system(size: 16)).foregroundStyle(Color.white.opacity(0.9))
                .padding(9).background(Circle().fill(Color.black.opacity(0.35)))
        }
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

struct OrtusReelsView: View {
    @ObservedObject var store: OrtusStore
    @ObservedObject var nav: OrtusNav
    @State private var category = UserDefaults.standard.string(forKey: "ortus.category") ?? ""
    @State private var index = 0
    @State private var played = false

    private var list: [OrtusClip] {
        let pool = category.isEmpty ? store.reels : store.reels.filter { $0.category == category }
        return OrtusPick.ordered(pool, kind: "ortus.reel")
    }

    var body: some View {
        let items = list
        VStack(alignment: .leading, spacing: 14) {
            OrtusHeading(title: "Reels", detail: "\(store.reels.count) Shorts")
            OrtusChipRow(items: OrtusPick.reelCategories.map { name in (name, store.reels.filter { $0.category == name }.count) }, current: category) { picked in
                category = picked
                index = 0
                UserDefaults.standard.set(picked, forKey: "ortus.category")
            }
            if items.isEmpty {
                OrtusEmpty(title: "No reels yet", text: "They arrive with the next cloud sync.")
            } else {
                let at = ((index % items.count) + items.count) % items.count
                let clip = items[at]
                HStack(alignment: .top, spacing: 24) {
                    VStack(alignment: .leading, spacing: 10) {
                        OrtusPlayer(url: clip.embed(autoplay: played))
                            .frame(width: 300, height: 533)
                            .background(Ort.night)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        Text(clip.title).font(Ort.sans(14, .semibold)).lineLimit(2).frame(width: 300, alignment: .leading)
                        HStack(spacing: 8) {
                            Text(clip.meta).font(Ort.sans(12)).foregroundStyle(Ort.muted).lineLimit(1)
                            Spacer()
                            OrtusIconButton(symbol: "chevron.up", help: "Previous reel", size: 32) { step(-1) }
                            OrtusIconButton(symbol: "chevron.down", help: "Next reel", solid: true, size: 32) { step(1) }
                            if let watch = clip.watchURL {
                                OrtusIconButton(symbol: "arrow.up.right", help: "Open on YouTube", size: 32) {
                                    NSWorkspace.shared.open(watch)
                                    note("ortus reel opened externally id=\(clip.id)")
                                }
                            }
                        }
                        .frame(width: 300)
                    }
                    ScrollView {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 14) {
                            ForEach(Array(items.enumerated()).filter { $0.offset != at }.prefix(60), id: \.element.id) { item in
                                Button {
                                    played = true
                                    index = item.offset
                                    note("ortus reel picked id=\(item.element.id) category=\(item.element.category)")
                                } label: {
                                    VStack(alignment: .leading, spacing: 5) {
                                        OrtusThumb(clip: item.element).aspectRatio(9 / 14, contentMode: .fit)
                                        Text(item.element.title).font(Ort.sans(11.5, .semibold)).lineLimit(2).multilineTextAlignment(.leading)
                                        Text(item.element.meta).font(Ort.sans(10.5)).foregroundStyle(Ort.muted).lineLimit(1)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.bottom, 20)
                    }
                }
                .background(keys)
                .onAppear { focus(items) }
                .onChange(of: nav.reel) { _, _ in focus(items) }
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 34)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var keys: some View {
        Group {
            Button("") { step(1) }.keyboardShortcut(.downArrow, modifiers: [])
            Button("") { step(-1) }.keyboardShortcut(.upArrow, modifiers: [])
        }
        .opacity(0)
    }

    private func step(_ by: Int) {
        played = true
        index += by
    }

    private func focus(_ items: [OrtusClip]) {
        guard let wanted = nav.reel else { return }
        nav.reel = nil
        if let found = items.firstIndex(where: { $0.id == wanted }) {
            index = found
            played = true
        } else if let found = OrtusPick.ordered(store.reels, kind: "ortus.reel").firstIndex(where: { $0.id == wanted }) {
            category = ""
            index = found
            played = true
        }
    }
}

struct OrtusVideosView: View {
    @ObservedObject var store: OrtusStore
    @State private var index = 0
    @State private var played = false

    var body: some View {
        let items = OrtusPick.ordered(store.videos, kind: "ortus.video")
        VStack(alignment: .leading, spacing: 16) {
            OrtusHeading(title: "Videos", detail: "\(store.videos.count) videos")
            if items.isEmpty {
                OrtusEmpty(title: "No videos yet", text: "Longer talks and films land here once they are added to the library as ortus.video records.")
            } else {
                let at = ((index % items.count) + items.count) % items.count
                let clip = items[at]
                HStack(alignment: .top, spacing: 24) {
                    VStack(alignment: .leading, spacing: 10) {
                        OrtusPlayer(url: clip.embed(autoplay: played))
                            .aspectRatio(16 / 9, contentMode: .fit)
                            .background(Ort.night)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(clip.title).font(Ort.sans(16, .semibold)).lineLimit(2)
                                Text(clip.meta).font(Ort.sans(12)).foregroundStyle(Ort.muted)
                            }
                            Spacer()
                            OrtusIconButton(symbol: "chevron.right", help: "Next video", solid: true) { played = true; index += 1 }
                            if let watch = clip.watchURL {
                                OrtusIconButton(symbol: "arrow.up.right", help: "Open on YouTube") { NSWorkspace.shared.open(watch) }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    ScrollView {
                        VStack(spacing: 6) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { item in
                                Button { played = true; index = item.offset } label: {
                                    HStack(spacing: 10) {
                                        OrtusThumb(clip: item.element, radius: 8).frame(width: 96, height: 54)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(item.element.title).font(Ort.sans(12.5, .semibold)).lineLimit(2).multilineTextAlignment(.leading)
                                            Text(item.element.channel).font(Ort.sans(11)).foregroundStyle(Ort.muted).lineLimit(1)
                                        }
                                        Spacer(minLength: 0)
                                    }
                                    .padding(6)
                                    .background(RoundedRectangle(cornerRadius: 10).fill(item.offset == at ? Ort.ground : Color.clear))
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .frame(width: 300)
                }
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 34)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct OrtusStoriesView: View {
    @ObservedObject var store: OrtusStore
    @ObservedObject var nav: OrtusNav
    @State private var query = ""
    @State private var kind = "all"

    private var list: [OrtusStory] {
        let text = query.trimmingCharacters(in: .whitespaces).lowercased()
        return store.stories
            .filter { kind == "all" || (kind == "fiction") == $0.fiction }
            .filter { text.isEmpty || "\($0.name) \($0.title) \($0.who)".lowercased().contains(text) }
    }

    private var current: OrtusStory? {
        store.story(nav.story) ?? OrtusPick.daily(store.stories, kind: "ortus.story")
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 300)
            Rectangle().fill(Ort.line).frame(width: 1)
            if let story = current {
                reader(story)
            } else {
                OrtusEmpty(title: "No stories yet", text: "They arrive with the next cloud sync.")
            }
        }
    }

    private var sidebar: some View {
        let fiction = store.stories.filter(\.fiction).count
        return VStack(alignment: .leading, spacing: 12) {
            OrtusHeading(title: "Stories", detail: "\(store.stories.count) stories")
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(Ort.muted)
                TextField("Search people and stories", text: $query).textFieldStyle(.plain).font(Ort.sans(13))
            }
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(RoundedRectangle(cornerRadius: 10).fill(Ort.card))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Ort.edge, lineWidth: 1))
            HStack(spacing: 6) {
                OrtusChip(title: "All", on: kind == "all") { kind = "all" }
                OrtusChip(title: "Real · \(store.stories.count - fiction)", on: kind == "real") { kind = "real" }
                OrtusChip(title: "Fiction · \(fiction)", on: kind == "fiction") { kind = "fiction" }
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(list) { story in
                        let on = story.id == current?.id
                        Button {
                            nav.story = story.id
                            note("ortus story opened id=\(story.id) source=list")
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(story.fiction ? "\(story.name) · fiction" : story.name).font(Ort.sans(11.5, on ? .semibold : .regular)).foregroundStyle(on ? Ort.deep : Ort.muted)
                                Text(story.title).font(Ort.sans(13.5, .semibold)).multilineTextAlignment(.leading)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 10).fill(on ? Ort.ground : Color.clear))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, -8)
        }
        .padding(.horizontal, 20)
        .padding(.top, 34)
        .padding(.bottom, 12)
    }

    private func reader(_ story: OrtusStory) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 10) {
                    Text(story.fiction ? "FICTION" : "REAL").font(Ort.sans(10.5, .semibold)).tracking(1)
                        .foregroundStyle(Color.white).padding(.horizontal, 9).padding(.vertical, 4)
                        .background(Capsule().fill(Ort.accent))
                    Text([story.name, story.who].filter { !$0.isEmpty }.joined(separator: " · ")).font(Ort.sans(13)).foregroundStyle(Ort.muted)
                    if story.id == OrtusPick.daily(store.stories, kind: "ortus.story")?.id {
                        Text("Story of the day").font(Ort.sans(12, .semibold)).foregroundStyle(Ort.deep)
                    }
                }
                Text(story.title).font(Ort.serif(34)).fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(story.paras.enumerated()), id: \.offset) { para in
                        Text(para.element).font(Ort.sans(15.5)).lineSpacing(6).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .textSelection(.enabled)
                Rectangle().fill(Ort.line).frame(height: 1)
                HStack(alignment: .center, spacing: 12) {
                    if !story.line.isEmpty {
                        Text(story.line).font(Ort.serif(17, .medium)).italic().foregroundStyle(Ort.deep)
                    }
                    Spacer()
                    if let link = story.sourceURL {
                        OrtusIconButton(symbol: "arrow.up.right", help: "Read more") { NSWorkspace.shared.open(link) }
                    }
                    Button {
                        let others = store.stories.filter { $0.id != story.id }
                        if let pick = others.randomElement() {
                            nav.story = pick.id
                            note("ortus story opened id=\(pick.id) source=random")
                        }
                    } label: {
                        Label("Random story", systemImage: "shuffle").font(Ort.sans(13, .semibold))
                            .padding(.horizontal, 14).frame(height: 38)
                            .foregroundStyle(Color.white)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Ort.accent))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                if !story.source.isEmpty && story.sourceURL == nil {
                    Text(story.source).font(Ort.sans(12)).foregroundStyle(Ort.muted)
                }
            }
            .frame(maxWidth: 660, alignment: .leading)
            .padding(.horizontal, 56)
            .padding(.top, 46)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .id(story.id)
    }
}

struct OrtusSettings: View {
    @ObservedObject var store: OrtusStore
    @ObservedObject var cloud = CloudSync.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Settings").font(Ort.serif(30))
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Only quotes with a known source").font(Ort.sans(14, .semibold))
                        Text("Hides the \(store.allQuotes.filter(\.moderate).count) quotes that are only widely attributed").font(Ort.sans(12)).foregroundStyle(Ort.muted)
                    }
                    Spacer()
                    Toggle("", isOn: $store.verifiedOnly).labelsHidden().toggleStyle(.switch).tint(Ort.accent)
                }
                .frame(height: 64)
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: 560)
            .background(RoundedRectangle(cornerRadius: 14).fill(Ort.card))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Ort.line, lineWidth: 1))
            VStack(alignment: .leading, spacing: 8) {
                Ort.kicker("Library")
                Text("\(store.allQuotes.count) quotes · \(store.stories.count) stories · \(store.reels.count) reels · \(store.videos.count) videos")
                    .font(Ort.sans(13))
                Text(cloud.lastSync.map { "Last cloud sync \($0.formatted(date: .abbreviated, time: .shortened))" } ?? "Cloud sync has not run yet")
                    .font(Ort.sans(12)).foregroundStyle(Ort.muted)
                if let problem = cloud.problem { Text(problem).font(Ort.sans(12)).foregroundStyle(Color.red) }
                Button("Sync now") { CloudSync.shared.syncNow() }.padding(.top, 4)
                Text("Content is added as ortus.quote, ortus.story, ortus.reel and ortus.video rows in the shared table.")
                    .font(Ort.sans(12)).foregroundStyle(Ort.muted).padding(.top, 6)
            }
            Spacer()
        }
        .padding(.horizontal, 44)
        .padding(.vertical, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct OrtusGlance: View {
    @ObservedObject var store: OrtusStore
    let open: (OrtusMode?, String?, String?) -> Void
    @State private var shift = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                OrtusLogoMark(side: 32)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Ortus").font(Ort.serif(18))
                    Text(Date().formatted(.dateTime.weekday(.wide).day().month(.wide))).font(Ort.sans(11)).foregroundStyle(Ort.muted)
                }
                Spacer()
                OrtusIconButton(symbol: "arrow.up.left.and.arrow.down.right", help: "Open Ortus", size: 34) { open(nil, nil, nil) }
            }
            if store.empty {
                OrtusEmpty(title: "Nothing here yet", text: "Connect cloud sync in Pocket Settings and the library arrives on its own.")
            } else {
                quoteCard
                storyCard
                reelCard
                Spacer(minLength: 0)
                modes
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Ort.paper)
        .foregroundStyle(Ort.ink)
        .environment(\.colorScheme, .light)
        .ignoresSafeArea()
    }

    @ViewBuilder private var quoteCard: some View {
        let quotes = OrtusPick.ordered(store.quotes, kind: "ortus.quote")
        if !quotes.isEmpty {
            let quote = quotes[shift % quotes.count]
            VStack(alignment: .leading, spacing: 10) {
                Text("“\(quote.text)”").font(Ort.serif(quote.text.count > 140 ? 15.5 : 18.5, .medium))
                    .lineLimit(7).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Text([quote.author, quote.source].filter { !$0.isEmpty }.joined(separator: " · ")).font(Ort.sans(12)).foregroundStyle(Ort.ground).lineLimit(1)
                    Spacer()
                    Button { shift += 1 } label: {
                        Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold))
                            .frame(width: 30, height: 30)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.45), lineWidth: 1))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Next quote")
                }
            }
            .foregroundStyle(Color.white)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Ort.accent))
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { open(.quotes, nil, nil) }
        }
    }

    @ViewBuilder private var storyCard: some View {
        if let story = OrtusPick.daily(store.stories, kind: "ortus.story") {
            Button { open(.stories, story.id, nil) } label: {
                VStack(alignment: .leading, spacing: 5) {
                    Ort.kicker("Story of the day")
                    Text(story.title).font(Ort.serif(16.5)).multilineTextAlignment(.leading)
                    Text(story.paras.first ?? "").font(Ort.sans(12.5)).foregroundStyle(Ort.muted).lineLimit(2).multilineTextAlignment(.leading)
                    Text("\(story.name) · \(story.minutes) min read").font(Ort.sans(11.5)).foregroundStyle(Ort.muted)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 14).fill(Ort.card))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Ort.line, lineWidth: 1))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder private var reelCard: some View {
        if let clip = OrtusPick.daily(store.reels, kind: "ortus.reel") {
            Button { open(.reels, nil, clip.id) } label: {
                HStack(spacing: 12) {
                    OrtusThumb(clip: clip, radius: 9).frame(width: 52, height: 80)
                    VStack(alignment: .leading, spacing: 4) {
                        Ort.kicker("Reel · \(clip.category)")
                        Text(clip.title).font(Ort.sans(13.5, .semibold)).lineLimit(2).multilineTextAlignment(.leading)
                        Text(clip.meta).font(Ort.sans(11.5)).foregroundStyle(Ort.muted).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 14).fill(Ort.card))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Ort.line, lineWidth: 1))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var modes: some View {
        HStack(spacing: 0) {
            ForEach(OrtusMode.allCases) { mode in
                Button { open(mode, nil, nil) } label: {
                    VStack(spacing: 4) {
                        Image(systemName: mode.symbol).font(.system(size: 16)).frame(height: 20)
                        Text(mode.title).font(Ort.sans(10.5, .medium))
                    }
                    .foregroundStyle(Ort.muted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 10)
        .overlay(Rectangle().fill(Ort.line).frame(height: 1), alignment: .top)
    }
}
