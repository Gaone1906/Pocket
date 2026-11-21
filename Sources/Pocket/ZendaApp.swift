import AppKit
import Combine
import SwiftUI

final class ZendaApp: PocketApp {
    private var watch: AnyCancellable?
    private var finishedAt: Date?

    override func start() {
        let runner = KairosRunner.zenda
        _ = ZendaStore.shared
        runner.onChange = { [weak self] in self?.changed() }
        finishedAt = runner.state?.finished
        watch = runner.$state.receive(on: RunLoop.main).sink { [weak self] state in self?.track(state) }
        let ledger = ZendaLedger()
        note("zenda app started day=\(ScheduleStore.shared.today) routines=\(ledger.routines.count) projects=\(ZendaStore.shared.projects.count) running=\(runner.running)")
    }

    override func stop() {
        KairosRunner.zenda.onChange = nil
        watch = nil
        super.stop()
    }

    private func track(_ state: KairosRunState?) {
        guard let finished = state?.finished, finished != finishedAt, let state else {
            if state == nil { finishedAt = nil }
            return
        }
        finishedAt = finished
        let minutes = Int(finished.timeIntervalSince(state.started) / 60)
        note("zenda session finished routine=\(state.adhocName ?? ScheduleStore.shared.routine(state.routine)?.name ?? state.routine.uuidString) adhoc=\(state.adhoc != nil) day=\(state.day) slot=\(state.slot.rawValue) minutes=\(minutes)")
    }

    override func toggle(anchor: NSStatusItem?, source: String) {
        AppDelegate.shared.hideOthers(except: self)
        ZendaWindow.shared.present(source: source)
    }

    override func barTitle() -> NSAttributedString? {
        let runner = KairosRunner.zenda
        guard runner.running, let live = runner.live, live.beat?.counted == true else { return nil }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .semibold),
            .foregroundColor: NSColor.labelColor
        ]
        return NSAttributedString(string: " " + KairosPlan.clock(runner.remaining), attributes: attributes)
    }

    override func menuItems() -> [NSMenuItem] {
        let open = NSMenuItem(title: "Open Zenda", action: #selector(openFromMenu), keyEquivalent: "")
        open.target = self
        guard KairosRunner.zenda.running else { return [open] }
        let end = NSMenuItem(title: "End session", action: #selector(endFromMenu), keyEquivalent: "")
        end.target = self
        return [open, end]
    }

    @objc private func openFromMenu() { ZendaWindow.shared.present(source: "menu") }

    @objc private func endFromMenu() { KairosRunner.zenda.end(reason: "menu") }
}

final class ZendaWindow: NSObject, NSWindowDelegate {
    static let shared = ZendaWindow()

    private var window: NSWindow?

    func present(source: String) {
        NSApp.setActivationPolicy(.regular)
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            note("zenda window refocused source=\(source)")
            return
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 720),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = "Zenda"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.appearance = NSAppearance(named: .aqua)
        window.backgroundColor = NSColor(Zen.paper)
        let host = NSHostingView(rootView: ZendaRoot())
        host.sizingOptions = []
        window.contentView = host
        window.contentMinSize = NSSize(width: 980, height: 660)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        window.setFrameAutosaveName("zenda.board")
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        note("zenda window opened source=\(source) running=\(KairosRunner.zenda.running) projects=\(ZendaStore.shared.projects.count)")
    }

    func windowWillClose(_ notification: Notification) {
        let closing = window
        window?.delegate = nil
        window = nil
        let others = NSApp.windows.contains { $0 !== closing && $0.isVisible && $0.styleMask.contains(.titled) && $0.canBecomeMain }
        if !others { NSApp.setActivationPolicy(.accessory) }
        note("zenda window closed running=\(KairosRunner.zenda.running) otherWindows=\(others)")
    }
}

enum ZendaRoute: Equatable {
    case today
    case scheduled
    case start
    case review
    case book(String)
    case settings

    var tab: ZendaRoute { if case .book = self { return .review }; return self }
}

struct ZendaRoot: View {
    @ObservedObject var runner = KairosRunner.zenda
    @ObservedObject var store = ScheduleStore.shared
    @ObservedObject var projects = ZendaStore.shared
    @ObservedObject var journal = KairosJournal.shared
    @State var route: ZendaRoute

    init(route: ZendaRoute = .today) {
        _route = State(initialValue: route)
    }

    var body: some View {
        ZStack {
            ZendaBackdrop()
            if runner.state != nil, let live = runner.live, let state = runner.state {
                ZendaSessionView(runner: runner, journal: journal, live: live, state: state)
            } else {
                HStack(spacing: 0) {
                    rail
                    Rectangle().fill(Zen.line).frame(width: 1)
                    content.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .foregroundStyle(Zen.ink)
        .environment(\.colorScheme, .light)
        .ignoresSafeArea()
    }

    @ViewBuilder private var content: some View {
        switch route {
        case .today: ZendaToday(store: store, projects: projects, runner: runner)
        case .scheduled: ZendaScheduled(store: store, projects: projects)
        case .start: ZendaStart(store: store, projects: projects)
        case .review: ZendaReview(store: store, projects: projects, journal: journal, open: { route = .book($0) })
        case .book(let tag): ZendaBookView(journal: journal, projects: projects, tag: tag, back: { route = .review })
        case .settings: ZendaSettings()
        }
    }

    private var rail: some View {
        VStack(spacing: 8) {
            Spacer().frame(height: 41)
            ZendaLogoMark(side: 52).padding(.bottom, 14)
            tab(.today, "smallcircle.filled.circle", "Today")
            tab(.scheduled, "calendar", "Scheduled")
            tab(.start, "play", "Start")
            tab(.review, "chart.bar", "Review")
            Spacer()
            Button { route = .settings } label: {
                Image(systemName: "gearshape").font(.system(size: 19, weight: .regular))
                    .frame(width: 44, height: 44)
                    .background(RoundedRectangle(cornerRadius: 12).fill(route == .settings ? Zen.pale : Color.clear))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(",", modifiers: .command)
            .padding(.bottom, 18)
        }
        .frame(width: 92)
    }

    private func tab(_ target: ZendaRoute, _ symbol: String, _ title: String) -> some View {
        let on = route.tab == target
        return Button { route = target } label: {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 19, weight: .regular)).frame(height: 22)
                Text(title).font(Zen.round(11))
                if on { Circle().fill(Zen.vermilion).frame(width: 5, height: 5) }
            }
            .frame(width: 68, height: 60)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(on ? Zen.pale : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct ZendaSettings: View {
    @State private var sound = KairosRunner.sound
    @State private var hold = KairosRunner.hold

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Settings").font(Zen.serif(40, .bold))
            VStack(spacing: 0) {
                row("Chime at each change", $sound) { KairosRunner.sound = $0 }
                Rectangle().fill(Zen.rule).frame(height: 1)
                row("Wait for a click before each step", $hold) { KairosRunner.hold = $0 }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 8)
            .frame(maxWidth: 520)
            .zendaCard()
            Spacer()
        }
        .padding(.horizontal, 44)
        .padding(.vertical, 34)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func row(_ title: String, _ value: Binding<Bool>, apply: @escaping (Bool) -> Void) -> some View {
        HStack {
            Text(title).font(Zen.round(15))
            Spacer()
            Toggle("", isOn: value).labelsHidden().toggleStyle(.switch).tint(Zen.ink)
                .onChange(of: value.wrappedValue) { _, new in
                    apply(new)
                    note("zenda setting changed name=\(title) value=\(new)")
                }
        }
        .frame(height: 52)
    }
}
