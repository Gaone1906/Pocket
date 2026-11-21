import AppKit
import Combine
import SwiftUI

final class KairosApp: PocketApp {
    private var watch: AnyCancellable?

    override func start() {
        let journal = KairosJournal.shared
        let runner = KairosRunner.shared
        runner.onChange = { [weak self] in self?.changed() }
        watch = ScheduleStore.shared.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.changed() }
        note("kairos app started day=\(ScheduleStore.shared.today) sessions=\(KairosSession.all(on: ScheduleStore.shared.today).count) entries=\(journal.entries.count) running=\(runner.running)")
    }

    override func stop() {
        KairosRunner.shared.onChange = nil
        watch = nil
        super.stop()
    }

    override func toggle(anchor: NSStatusItem?, source: String) {
        openWindow(source: source)
    }

    override func show(anchor: NSStatusItem?, source: String) {
        openWindow(source: source)
    }

    override func barTitle() -> NSAttributedString? {
        let runner = KairosRunner.shared
        guard runner.running, let live = runner.live, let beat = live.beat, let state = runner.state else { return nil }
        let name = beat.name.count > 18 ? String(beat.name.prefix(17)) + "…" : beat.name
        let text: String
        if state.waiting {
            text = " Ready · \(name)"
        } else if beat.counted {
            text = " \(KairosPlan.clock(runner.remaining)) \(name)\(state.paused ? " ⏸" : "")"
        } else {
            text = " \(name)"
        }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .semibold),
            .foregroundColor: NSColor.labelColor
        ]
        return NSAttributedString(string: text, attributes: attributes)
    }

    func openWindow(source: String) {
        AppDelegate.shared.hideOthers(except: self)
        ScheduleStore.shared.tick()
        KairosWindow.shared.present(source: source)
    }

    override func menuItems() -> [NSMenuItem] {
        let open = NSMenuItem(title: "Open Ventus", action: #selector(openFromMenu), keyEquivalent: "")
        open.target = self
        guard KairosRunner.shared.running else { return [open] }
        let pause = NSMenuItem(title: KairosRunner.shared.state?.paused == true ? "Resume" : "Pause", action: #selector(pauseFromMenu), keyEquivalent: "")
        pause.target = self
        let end = NSMenuItem(title: "End session", action: #selector(endFromMenu), keyEquivalent: "")
        end.target = self
        return [open, pause, end]
    }

    @objc private func openFromMenu() { openWindow(source: "menu") }

    @objc private func pauseFromMenu() { KairosRunner.shared.togglePause() }

    @objc private func endFromMenu() { KairosRunner.shared.end(reason: "menu") }
}

private enum KairosLook {
    static let rest = Color(red: 0.435, green: 0.592, blue: 0.702)
    static var onAccent: Color { KairosBoard.theme.isDark ? KairosBoard.backdrop : .white }

    static let dateFormat: DateFormatter = {
        let format = DateFormatter()
        format.calendar = ScheduleDays.calendar
        format.locale = .current
        format.setLocalizedDateFormatFromTemplate("EEEEdMMM")
        return format
    }()

    static let timeFormat: DateFormatter = {
        let format = DateFormatter()
        format.locale = .current
        format.timeStyle = .short
        format.dateStyle = .none
        return format
    }()

    static func title(_ day: String) -> String { ScheduleDays.date(day).map(dateFormat.string(from:)) ?? day }

    static let shortFormat: DateFormatter = {
        let format = DateFormatter()
        format.calendar = ScheduleDays.calendar
        format.locale = .current
        format.setLocalizedDateFormatFromTemplate("dMMM")
        return format
    }()

    static func short(_ day: String) -> String { ScheduleDays.date(day).map(shortFormat.string(from:)) ?? day }

    static func kicker(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(1.2)
            .foregroundStyle(KairosBoard.muted)
    }
}

private struct KairosPrimary: ButtonStyle {
    var tint: Color? = nil
    var height: CGFloat = 40

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Ventus.font(15))
            .foregroundStyle(tint == nil ? Ventus.onInk : KairosLook.onAccent)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(Capsule().fill(tint ?? Ventus.ink))
            .opacity(configuration.isPressed ? 0.8 : 1)
            .contentShape(Capsule())
    }
}

enum VentusTab: String, CaseIterable, Identifiable {
    case today
    case scheduled
    case start
    case review

    var id: String { rawValue }
    var label: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }

    var glyph: VentusGlyph {
        switch self {
        case .today: return .today
        case .scheduled: return .scheduled
        case .start: return .start
        case .review: return .review
        }
    }

    var key: KeyEquivalent {
        switch self {
        case .today: return "1"
        case .scheduled: return "2"
        case .start: return "3"
        case .review: return "4"
        }
    }
}

private struct KairosBoardView: View {
    @ObservedObject var runner: KairosRunner
    @ObservedObject var store: ScheduleStore
    @ObservedObject var journal: KairosJournal
    @ObservedObject var themes = AppThemeStore.shared
    @State private var tab = VentusTab.today
    @State private var picked: UUID?
    @State private var preview: KairosSession?
    @State private var previewStep = 0
    @State private var hidden = false
    @State private var logging: VentusLogRequest?
    @State private var editing = false

    var body: some View {
        let today = store.today
        let projects = VentusProject.all(journal)
        let project = projects.first { $0.id == picked } ?? VentusProject.current(projects, today: today)
        Group {
            if let state = runner.state, let live = runner.live, !hidden {
                KairosStage(runner: runner, store: store, journal: journal, live: live, state: state, project: project) {
                    hidden = true
                    note("kairos run stage hidden routine=\(live.routine.name) running=\(runner.running)")
                }
            } else {
                HStack(spacing: 0) {
                    VentusRail(tab: tab) { next in
                        preview = nil
                        tab = next
                        note("kairos tab \(next.rawValue)")
                    }
                    page(projects: projects, project: project, today: today)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .id(KairosBoard.theme.id)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BoardBackdrop(theme: KairosBoard.theme))
        .ignoresSafeArea()
        .appTheme(KairosBoard.theme)
        .onChange(of: runner.state?.started) { _, _ in hidden = false }
        .sheet(item: $logging) { request in
            VentusLogSheet(journal: journal, projects: projects, project: project, first: request.kind, today: today) { logging = nil }
        }
        .sheet(isPresented: $editing) {
            if let project {
                VentusProjectEditor(journal: journal, project: project) { editing = false }
            }
        }
    }

    @ViewBuilder private func page(projects: [VentusProject], project: VentusProject?, today: String) -> some View {
        if let preview {
            KairosPreview(session: preview, step: $previewStep) { self.preview = nil }
                .frame(maxWidth: 680)
                .padding(.horizontal, 24)
                .padding(.top, 32)
                .padding(.bottom, 20)
                .frame(maxWidth: .infinity)
        } else {
            Group {
                switch tab {
                case .today:
                    VentusTodayPage(store: store, journal: journal, runner: runner, projects: projects, project: project,
                                    resumable: runner.state != nil && hidden, start: { begin($0, adhoc: false) }, resume: resume)
                case .scheduled:
                    VentusScheduledPage(store: store, journal: journal, projects: projects, project: project, pick: pick,
                                        edit: { editing = true }, preview: peek, start: { session, adhoc in begin(session, adhoc: adhoc) })
                case .start:
                    VentusStartPage(store: store, project: project, startToday: { begin($0, adhoc: false) }, startStep: { step, day, slot in
                        guard let project else { return }
                        hidden = false
                        runner.start(step: step, of: project.routine, day: day, slot: slot)
                    }, anyDay: { tab = .scheduled }, log: { logging = VentusLogRequest(kind: $0) })
                case .review:
                    VentusReviewPage(store: store, journal: journal, projects: projects, project: project, pick: pick)
                }
            }
            .padding(.horizontal, 36)
            .padding(.top, 30)
            .padding(.bottom, 24)
            .kairosFill()
        }
    }

    private func pick(_ id: UUID) {
        picked = id
        note("kairos project picked routine=\(id.uuidString)")
    }

    private func peek(_ session: KairosSession) {
        previewStep = 0
        preview = session
        note("kairos preview opened routine=\(session.routine.name) day=\(session.day) slot=\(session.slot.rawValue)")
    }

    private func begin(_ session: KairosSession, adhoc: Bool) {
        hidden = false
        if !adhoc, runner.isRunning(session) { return }
        runner.start(session, adhoc: adhoc)
    }

    private func resume() {
        hidden = false
        note("kairos run stage shown running=\(runner.running)")
    }
}

private struct VentusRail: View {
    let tab: VentusTab
    let go: (VentusTab) -> Void
    @State private var settings = false

    var body: some View {
        VStack(spacing: 6) {
            Color.clear.frame(height: 18)
            VentusLogo(size: 52)
                .padding(.bottom, 14)
            ForEach(VentusTab.allCases) { item in
                let on = item == tab
                Button {
                    go(item)
                } label: {
                    VStack(spacing: 4) {
                        VentusIcon(item.glyph, color: on ? Ventus.ink : Ventus.muted, size: 22)
                        Text(item.label)
                            .font(Ventus.font(11, .bold))
                    }
                    .foregroundStyle(on ? Ventus.ink : Ventus.muted)
                    .frame(width: 64)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(on ? Ventus.card : Color.clear))
                    .contentShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(item.key, modifiers: .command)
                .help(item.label)
            }
            Spacer(minLength: 12)
            Button {
                settings.toggle()
                note("kairos settings \(settings ? "opened" : "closed")")
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Ventus.muted)
                    .frame(width: 40, height: 40)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(",", modifiers: .command)
            .help("Settings")
            .popover(isPresented: $settings, arrowEdge: .trailing) {
                KairosSettings()
                    .frame(width: 280, height: 220)
                    .background(Ventus.card)
                    .appTheme(KairosBoard.theme)
            }
        }
        .padding(.top, 22)
        .padding(.bottom, 18)
        .frame(width: 88)
        .frame(maxHeight: .infinity)
        .background(Ventus.rail)
    }
}

private struct KairosStage: View {
    @ObservedObject var runner: KairosRunner
    @ObservedObject var store: ScheduleStore
    @ObservedObject var journal: KairosJournal
    let live: KairosLive
    let state: KairosRunState
    let project: VentusProject?
    let back: () -> Void

    private var resting: Bool {
        guard state.finished == nil, !state.waiting, let beat = live.beat else { return false }
        return beat.kind == .rest
    }

    var body: some View {
        HStack(spacing: 0) {
            side
                .frame(width: 260)
                .background(resting ? Ventus.coolSide : Ventus.warmSide)
            Group {
                if state.finished != nil {
                    KairosDone(runner: runner, journal: journal, live: live, state: state)
                        .frame(maxWidth: 560)
                        .padding(.horizontal, 24)
                        .padding(.top, 36)
                        .padding(.bottom, 20)
                } else {
                    KairosRun(runner: runner, journal: journal, live: live, state: state)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(resting ? Ventus.restSoft : Ventus.warm)
        .animation(.easeInOut(duration: 0.35), value: resting)
    }

    private var title: String {
        if state.isAdhoc, live.steps.count == 1 { return KairosFit.name(live.steps[0]) }
        if let project, state.day >= project.start, state.day <= project.end { return "Day \(project.dayNumber(state.day))" }
        return KairosSession.title(live.routine, on: state.day)
    }

    private var side: some View {
        let items = store.items(on: state.day, slot: state.slot, in: [live.routine])
        let current = live.beat?.step ?? 0
        let total = max(1, live.steps.reduce(0) { $0 + KairosPlan.estimate($1) })
        let elapsed = (state.finished ?? runner.now).timeIntervalSince(state.started)
        return VStack(alignment: .leading, spacing: 4) {
            Button(action: back) {
                HStack(spacing: 8) {
                    VentusIcon(.back, size: 18, weight: 2.4)
                    Text(title)
                        .font(Ventus.font(15, .black))
                        .lineLimit(1)
                }
                .foregroundStyle(Ventus.ink)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Back to Ventus; the session keeps running")
            .padding(.leading, 6)
            .padding(.bottom, 18)
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(live.steps.enumerated()), id: \.offset) { index, step in
                        row(index: index, step: step, current: current, items: items)
                    }
                }
            }
            .scrollIndicators(.never)
            Spacer(minLength: 8)
            Text(KairosPlan.clock(max(0, elapsed)))
                .font(Ventus.font(28, .black))
                .monospacedDigit()
                .foregroundStyle(Ventus.ink)
                .padding(.horizontal, 14)
            VentusBar(fraction: min(1, elapsed / Double(total)), height: 8, fill: Ventus.ink)
                .padding(.horizontal, 14)
                .padding(.top, 8)
        }
        .padding(.horizontal, 16)
        .padding(.top, 44)
        .padding(.bottom, 24)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func row(index: Int, step: ScheduleStep, current: Int, items: [ScheduleItem]) -> some View {
        let done = state.isAdhoc ? (index < current || state.finished != nil) : (items.first { $0.step.id == step.id }?.done ?? false)
        let here = index == current && state.finished == nil
        let glyph = Ventus.glyph(step)
        let beat = live.beat
        let trailing: String
        if here, let beat, beat.rounds > 1 {
            trailing = "\(beat.round + 1)/\(beat.rounds)"
        } else if done, let spent = state.spent[String(index)], spent > 0 {
            trailing = KairosPlan.clock(spent)
        } else {
            trailing = Ventus.minutes(KairosPlan.estimate(step))
        }
        return Button {
            if state.finished == nil { runner.jump(to: index) }
        } label: {
            HStack(spacing: 12) {
                if done && !here {
                    VentusIcon(.check, size: 20, weight: 2.6)
                } else {
                    VentusIcon(glyph, color: here ? Ventus.hot : Ventus.tint(glyph), size: 20)
                }
                Text(KairosFit.name(step))
                    .font(Ventus.font(15))
                    .foregroundStyle(Ventus.ink)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(trailing)
                    .font(Ventus.font(14, .bold))
                    .monospacedDigit()
                    .foregroundStyle(Ventus.ink.opacity(here || done ? 1 : 0.7))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(here ? Ventus.card : Color.clear))
            .opacity(done && !here ? 0.55 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(state.finished == nil ? "Jump to this step" : "")
    }
}

private struct KairosGhost: ButtonStyle {
    var height: CGFloat = 40

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(KairosBoard.ink)
            .padding(.horizontal, 16)
            .frame(height: height)
            .background(Capsule().fill(KairosBoard.column.opacity(configuration.isPressed ? 1 : 0.6)))
            .overlay(Capsule().stroke(KairosBoard.line, lineWidth: 1))
            .contentShape(Capsule())
    }
}

private struct KairosRound: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 20, weight: .bold))
            .foregroundStyle(Ventus.ink)
            .frame(width: 56, height: 56)
            .background(Circle().fill(Ventus.card.opacity(configuration.isPressed ? 0.7 : 1)))
            .contentShape(Circle())
    }
}

final class KairosWindow: NSObject, NSWindowDelegate {
    static let shared = KairosWindow()

    private var window: NSWindow?
    private var themeWatch: AnyCancellable?

    func present(source: String) {
        NSApp.setActivationPolicy(.regular)
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            note("kairos window refocused source=\(source)")
            return
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1160, height: 740),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = "Ventus"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.appearance = KairosBoard.theme.appearance
        window.backgroundColor = NSColor(KairosBoard.backdrop)
        themeWatch = AppThemeStore.shared.publisher(for: "runner").sink { [weak window] theme in
            window?.appearance = theme.appearance
            window?.backgroundColor = NSColor(theme.backdrop)
        }
        let host = NSHostingView(rootView: KairosBoardView(runner: KairosRunner.shared, store: ScheduleStore.shared, journal: KairosJournal.shared))
        host.sizingOptions = []
        window.contentView = host
        window.contentMinSize = NSSize(width: 940, height: 640)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        window.setFrameAutosaveName("runner.board")
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        note("kairos window opened source=\(source) running=\(KairosRunner.shared.running)")
    }

    func windowWillClose(_ notification: Notification) {
        let closing = window
        window?.delegate = nil
        window = nil
        themeWatch = nil
        let others = NSApp.windows.contains { $0 !== closing && $0.isVisible && $0.styleMask.contains(.titled) && $0.canBecomeMain }
        if !others { NSApp.setActivationPolicy(.accessory) }
        note("kairos window closed running=\(KairosRunner.shared.running) otherWindows=\(others)")
    }
}

private struct KairosSettings: View {
    @State private var sound = KairosRunner.sound
    @State private var hold = KairosRunner.hold

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Settings")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(KairosBoard.ink)
            setting("Chime at each change", "A soft chime when a step, move or rest changes, and another at the end.", $sound)
            setting("Wait for a click before each step", "Each step waits on an Up next screen until you press Start.", $hold)
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: sound) { _, on in
            KairosRunner.sound = on
            note("kairos setting changed sound=\(on)")
        }
        .onChange(of: hold) { _, on in
            KairosRunner.hold = on
            note("kairos setting changed hold=\(on)")
        }
    }

    private func setting(_ title: String, _ detail: String, _ value: Binding<Bool>) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(KairosBoard.ink)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(KairosBoard.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Toggle("", isOn: value)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }
}

private struct KairosPreview: View {
    let session: KairosSession
    @Binding var step: Int
    let close: () -> Void

    var body: some View {
        let steps = session.steps
        let index = max(0, min(step, steps.count - 1))
        let item = steps[index]
        let beats = KairosPlan.beats(item, index: index, day: session.day)
        let parts = KairosPlan.split(item.title)
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Preview · \(KairosSession.title(session.routine, on: session.day)) · \(session.slot.label)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(KairosBoard.ink)
                    Text("\(KairosLook.title(session.day)) · step \(index + 1) of \(steps.count) · no timer, nothing is ticked")
                        .font(.system(size: 11))
                        .foregroundStyle(KairosBoard.muted)
                }
                Spacer()
                Button("Close", action: close)
                    .buttonStyle(KairosGhost(height: 28))
                    .keyboardShortcut(.cancelAction)
            }
            HStack(spacing: 4) {
                ForEach(0..<steps.count, id: \.self) { position in
                    Capsule()
                        .fill(position <= index ? AnyShapeStyle(KairosBoard.accentStyle) : AnyShapeStyle(KairosBoard.line))
                        .frame(height: 4)
                        .contentShape(Rectangle().inset(by: -6))
                        .onTapGesture { step = position }
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                KairosLook.kicker(KairosPlan.howLabel(item))
                Text(parts.name)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(KairosBoard.ink)
                    .fixedSize(horizontal: false, vertical: true)
                let detail = KairosPlan.plainDetail(parts.detail)
                if !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 13))
                        .foregroundStyle(KairosBoard.muted)
                }
                if !item.tip.isEmpty {
                    Text(item.tip)
                        .font(.system(size: 12))
                        .foregroundStyle(KairosBoard.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 12).fill(KairosBoard.column))
                        .boardEdge(12)
                }
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(beats.enumerated()), id: \.offset) { _, beat in
                        row(beat)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 14).fill(KairosBoard.column))
                .boardEdge(14)
                Spacer(minLength: 0)
            }
            .kairosFill()
            HStack(spacing: 10) {
                Button("Back") { step = index - 1 }
                    .buttonStyle(KairosGhost(height: 40))
                    .disabled(index == 0)
                    .opacity(index == 0 ? 0.4 : 1)
                Button(index == steps.count - 1 ? "Finish preview" : "Next step") {
                    if index == steps.count - 1 { close() } else { step = index + 1 }
                }
                .buttonStyle(KairosPrimary(height: 40))
                .keyboardShortcut(.return, modifiers: [])
            }
        }
    }

    private func row(_ beat: KairosBeat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: icon(beat))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(beat.kind == .rest ? KairosLook.rest : KairosBoard.accent)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 3) {
                Text(beat.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(KairosBoard.ink)
                ForEach(Array(notes(beat).enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.system(size: 12))
                        .foregroundStyle(KairosBoard.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            Text(value(beat))
                .font(.system(size: 12, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(KairosBoard.muted)
        }
        .padding(.vertical, 9)
        .overlay(alignment: .bottom) { Rectangle().fill(KairosBoard.line).frame(height: 1).opacity(0.6) }
    }

    private func icon(_ beat: KairosBeat) -> String {
        switch beat.kind {
        case .count: return "timer"
        case .rest: return "pause.circle"
        case .reps: return "repeat"
        case .say: return "quote.bubble"
        case .write: return "pencil"
        case .log: return "figure.run"
        }
    }

    private func value(_ beat: KairosBeat) -> String {
        switch beat.kind {
        case .count, .rest: return KairosPlan.clock(Double(beat.seconds))
        case .reps: return beat.reps > 0 ? "\(beat.reps) reps" : "until Done"
        case .say: return "\(beat.times)× each"
        case .write: return beat.fields > 1 ? "\(beat.fields) lines" : "a paragraph"
        case .log: return "time and distance"
        }
    }

    private func notes(_ beat: KairosBeat) -> [String] {
        var lines: [String] = []
        if !beat.label.isEmpty, beat.kind != .say { lines.append(beat.label) }
        switch beat.kind {
        case .count:
            if !beat.box.isEmpty { lines.append("Box \(beat.box.map(String.init).joined(separator: "-")): breathe in, hold, breathe out, hold") }
            lines += beat.cues.map { "\(KairosPlan.clock(Double($0.at))) · \($0.text)" }
            lines += beat.reads.map { "Read · \($0)" }
        case .rest: if let next = beat.nextName { lines.append("Then \(next)") }
        case .reps: if !beat.detail.isEmpty { lines.append(KairosPlan.plainDetail(beat.detail)) }
        case .say: lines += beat.lines
        case .write: if !beat.prompt.isEmpty { lines.append(beat.prompt) }
        case .log: if !beat.plan.isEmpty { lines.append(beat.plan) }
        }
        return lines
    }
}

private struct KairosRun: View {
    @ObservedObject var runner: KairosRunner
    @ObservedObject var journal: KairosJournal
    let live: KairosLive
    let state: KairosRunState

    private var beat: KairosBeat { live.beat ?? live.beats[0] }

    var body: some View {
        VStack(spacing: 16) {
            dots
            Group {
                if state.waiting {
                    waiting.kairosFill()
                } else {
                    switch beat.kind {
                    case .count: KairosCount(runner: runner, live: live, beat: beat, state: state).kairosFill()
                    case .rest: KairosRest(runner: runner, beat: beat).kairosFill()
                    case .reps: KairosReps(runner: runner, live: live, beat: beat).kairosFill()
                    case .say: KairosSay(runner: runner, beat: beat, state: state)
                    case .write: KairosWrite(runner: runner, journal: journal, live: live, beat: beat, state: state).id(entryId)
                    case .log: KairosLog(runner: runner, journal: journal, live: live, beat: beat, state: state).id(entryId).kairosFill()
                    }
                }
            }
            .frame(maxWidth: 720)
        }
        .padding(.horizontal, 40)
        .padding(.top, 60)
        .padding(.bottom, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .overlay(alignment: .topTrailing) {
            Button {
                runner.end(reason: "button")
            } label: {
                VentusIcon(.close, size: 20, weight: 2.4)
                    .frame(width: 36, height: 36)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("End this session; finished steps stay ticked in Aqua")
            .padding(.top, 20)
            .padding(.trailing, 24)
        }
    }

    private var entryId: String {
        kairosBase(live, beat, state).id
    }

    @ViewBuilder private var dots: some View {
        if !state.waiting, beat.rounds > 1 {
            HStack(spacing: 8) {
                ForEach(0..<min(beat.rounds, 24), id: \.self) { index in
                    Capsule()
                        .fill(index < beat.round ? Ventus.ink : index == beat.round ? (beat.kind == .rest ? Ventus.rest : Ventus.hot) : Ventus.warmTrack)
                        .frame(width: beat.rounds > 12 ? 22 : 44, height: 8)
                }
            }
        } else {
            Color.clear.frame(height: 8)
        }
    }

    private var waiting: some View {
        VStack(spacing: 14) {
            Spacer()
            Text("Up next".uppercased())
                .font(Ventus.font(13, .black))
                .tracking(1.4)
                .foregroundStyle(Ventus.muted)
            Text(beat.name)
                .font(Ventus.font(56, .black))
                .foregroundStyle(Ventus.ink)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.5)
            Text(KairosPlan.howLabel(live.steps[beat.step]))
                .font(Ventus.font(15, .bold))
                .foregroundStyle(Ventus.muted)
            Spacer()
            Button("Start this step") { runner.togglePause() }
                .buttonStyle(KairosPrimary(height: 52))
                .frame(maxWidth: 360)
                .keyboardShortcut(.return, modifiers: [])
        }
        .frame(maxWidth: .infinity)
    }
}

private func kairosUpNext(_ live: KairosLive) -> String? {
    guard let next = live.next, let beat = live.beat else { return nil }
    if next.step != beat.step { return live.steps.indices.contains(next.step) ? KairosFit.name(live.steps[next.step]) : nil }
    if next.counted { return "\(next.name) \(KairosPlan.clock(next.seconds))" }
    return next.reps > 0 ? "\(next.reps) \(next.name)" : next.name
}

private struct KairosNextChip: View {
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            VentusIcon(.arrow, color: Ventus.restText, size: 20, weight: 2.2)
            Text(text).lineLimit(1)
        }
        .font(Ventus.font(20))
        .foregroundStyle(Ventus.restText)
        .padding(.horizontal, 20)
        .frame(height: 44)
        .background(Capsule().fill(Ventus.restSoft))
    }
}

struct KairosFill: ViewModifier {
    func body(content: Content) -> some View {
        GeometryReader { geo in
            ScrollView(.vertical) {
                content
                    .frame(maxWidth: .infinity, minHeight: geo.size.height, alignment: .top)
            }
            .scrollIndicators(.automatic)
        }
    }
}

extension View {
    func kairosFill() -> some View { modifier(KairosFill()) }
}

private struct KairosControls: View {
    @ObservedObject var runner: KairosRunner
    let paused: Bool

    var body: some View {
        HStack(spacing: 18) {
            Spacer()
            Button { runner.back() } label: { Image(systemName: "backward.end.fill") }
                .buttonStyle(KairosRound())
                .help("Back one")
            Button { runner.togglePause() } label: {
                Image(systemName: paused ? "play.fill" : "pause.fill")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(Ventus.onInk)
                    .frame(width: 76, height: 76)
                    .background(Circle().fill(Ventus.ink))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.space, modifiers: [])
            .help(paused ? "Resume" : "Pause")
            Button { runner.advance() } label: { Image(systemName: "forward.end.fill") }
                .buttonStyle(KairosRound())
                .help("Skip ahead")
            Spacer()
        }
    }
}

private struct KairosMoves: View {
    let beat: KairosBeat

    var body: some View {
        if beat.moves.count > 1 {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(beat.moves.enumerated()), id: \.offset) { index, name in
                    HStack(spacing: 10) {
                        Text(index < beat.at ? "✓" : index == beat.at ? "●" : "○")
                            .foregroundStyle(index <= beat.at ? KairosBoard.accent : KairosBoard.faint)
                            .frame(width: 14)
                        Text(name)
                            .fontWeight(index == beat.at ? .semibold : .regular)
                            .foregroundStyle(index < beat.at ? KairosBoard.muted : KairosBoard.ink)
                        Spacer()
                    }
                    .font(.system(size: 13))
                    .padding(.vertical, 5)
                }
            }
            .padding(.top, 6)
            .overlay(alignment: .top) { Rectangle().fill(KairosBoard.line).frame(height: 1) }
        }
    }
}

private struct KairosCount: View {
    @ObservedObject var runner: KairosRunner
    let live: KairosLive
    let beat: KairosBeat
    let state: KairosRunState

    private var cue: KairosCue? {
        let elapsed = Double(beat.seconds) - runner.remaining
        return beat.cues.last { Double($0.at) <= elapsed }
    }

    private var read: String? {
        guard !beat.reads.isEmpty else { return nil }
        let elapsed = max(0, Double(beat.seconds) - runner.remaining)
        return beat.reads[(Int(elapsed) / max(1, beat.every)) % beat.reads.count]
    }

    var body: some View {
        let left = runner.remaining
        VStack(spacing: 12) {
            if !beat.label.isEmpty {
                Text(beat.label)
                    .font(Ventus.font(14, .bold))
                    .foregroundStyle(Ventus.muted)
                    .lineLimit(1)
            }
            Text(beat.name)
                .font(Ventus.font(56, .black))
                .foregroundStyle(Ventus.ink)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.5)
            if beat.type == "timed", !beat.detail.isEmpty {
                Text(KairosPlan.plainDetail(beat.detail))
                    .font(Ventus.font(15, .bold))
                    .foregroundStyle(Ventus.muted)
            }
            if let read {
                Text(read)
                    .font(Ventus.font(17, .bold))
                    .foregroundStyle(Ventus.ink)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(14)
                    .frame(maxWidth: .infinity)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Ventus.card.opacity(0.7)))
            }
            if beat.box.isEmpty {
                Text(KairosPlan.clock(left))
                    .font(.system(size: 160, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .tracking(-4)
                    .foregroundStyle(Ventus.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                    .opacity(state.paused ? 0.45 : 1)
            } else {
                KairosBox(beat: beat, state: state)
                    .frame(width: 240, height: 240)
                    .frame(maxWidth: .infinity)
                Text(KairosPlan.clock(left))
                    .font(Ventus.font(15, .bold))
                    .monospacedDigit()
                    .foregroundStyle(Ventus.muted)
            }
            if state.paused {
                Text("Paused")
                    .font(Ventus.font(13, .black))
                    .foregroundStyle(Ventus.muted)
            }
            if let next = kairosUpNext(live) {
                KairosNextChip(text: next)
            }
            if let cue {
                Text(cue.text)
                    .font(Ventus.font(14, .bold))
                    .foregroundStyle(Ventus.ink)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(12)
                    .frame(maxWidth: .infinity)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Ventus.card.opacity(0.7)))
            }
            KairosMoves(beat: beat)
            Spacer(minLength: 16)
            KairosControls(runner: runner, paused: state.paused)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct KairosBox: View {
    let beat: KairosBeat
    let state: KairosRunState

    private static let corners: [CGPoint] = [CGPoint(x: 0, y: 1), CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: 1, y: 1)]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: state.paused || state.endsAt == nil)) { context in
            let left = state.endsAt.map { max(0, $0.timeIntervalSince(context.date)) } ?? (state.left ?? 0)
            let breath = KairosPlan.breath(beat.box, max(0, Double(beat.seconds) - left))
            GeometryReader { geo in
                let side = min(geo.size.width, geo.size.height) - 28
                let inset = CGPoint(x: (geo.size.width - side) / 2, y: (geo.size.height - side) / 2)
                let from = Self.corners[breath.index]
                let to = Self.corners[(breath.index + 1) % 4]
                let ball = CGPoint(x: inset.x + (from.x + (to.x - from.x) * breath.fraction) * side,
                                   y: inset.y + (from.y + (to.y - from.y) * breath.fraction) * side)
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(KairosBoard.line, lineWidth: 4)
                        .frame(width: side, height: side)
                        .position(x: geo.size.width / 2, y: geo.size.height / 2)
                    VStack(spacing: 2) {
                        Text(breath.label)
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(KairosBoard.ink)
                        Text("\(breath.left)")
                            .font(.system(size: 44, weight: .light))
                            .monospacedDigit()
                            .foregroundStyle(KairosBoard.muted)
                    }
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
                    Circle()
                        .fill(KairosBoard.accent)
                        .frame(width: 24, height: 24)
                        .position(ball)
                }
            }
        }
    }
}

private struct KairosRest: View {
    @ObservedObject var runner: KairosRunner
    let beat: KairosBeat

    var body: some View {
        let left = runner.remaining
        VStack(spacing: 14) {
            Text(beat.name)
                .font(Ventus.font(56, .black))
                .foregroundStyle(Ventus.restText)
            if !beat.label.isEmpty {
                Text(beat.label)
                    .font(Ventus.font(14, .bold))
                    .foregroundStyle(Ventus.muted)
            }
            Text(KairosPlan.clock(left))
                .font(.system(size: 150, weight: .black, design: .rounded))
                .monospacedDigit()
                .tracking(-4)
                .foregroundStyle(Ventus.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
            HStack(spacing: 10) {
                Button("+15s") { runner.addTime(15) }.buttonStyle(KairosGhost(height: 36))
                Button("Skip rest") { runner.advance() }.buttonStyle(KairosGhost(height: 36))
            }
            if let next = beat.nextName {
                HStack(spacing: 12) {
                    VentusIcon(.arrow, color: Ventus.restText, size: 20, weight: 2.2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(beat.reps > 0 ? "\(beat.reps) \(next)" : next)
                            .font(Ventus.font(20, .black))
                            .foregroundStyle(Ventus.ink)
                        if beat.moves.count > 1 {
                            Text(beat.moves.dropFirst().joined(separator: " · "))
                                .font(Ventus.font(13, .bold))
                                .foregroundStyle(Ventus.muted)
                                .lineLimit(2)
                        }
                    }
                    Spacer(minLength: 0)
                    if beat.rounds > 0 && !beat.moves.isEmpty {
                        Text("\(beat.round + 2)/\(beat.rounds)")
                            .font(Ventus.font(15, .black))
                            .monospacedDigit()
                            .foregroundStyle(Ventus.restText)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .frame(maxWidth: 520)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Ventus.card.opacity(0.8)))
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct KairosReps: View {
    @ObservedObject var runner: KairosRunner
    let live: KairosLive
    let beat: KairosBeat

    var body: some View {
        VStack(spacing: 12) {
            if !beat.label.isEmpty {
                Text(beat.label)
                    .font(Ventus.font(14, .bold))
                    .foregroundStyle(Ventus.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if beat.reps > 0 {
                Text("\(beat.reps)")
                    .font(.system(size: 150, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Ventus.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
            }
            Text(beat.name)
                .font(Ventus.font(52, .black))
                .foregroundStyle(Ventus.ink)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.5)
            let detail = beat.at >= 0 ? beat.detail : KairosPlan.plainDetail(beat.detail)
            if !detail.isEmpty {
                Text(detail)
                    .font(Ventus.font(15, .bold))
                    .foregroundStyle(Ventus.muted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if beat.at < 0, !beat.tip.isEmpty {
                Text(beat.tip)
                    .font(Ventus.font(13, .medium))
                    .foregroundStyle(Ventus.muted)
                    .multilineTextAlignment(.center)
                    .lineLimit(6)
            }
            if let next = kairosUpNext(live) {
                KairosNextChip(text: next)
            }
            Spacer(minLength: 0)
            KairosMoves(beat: beat)
            HStack(spacing: 14) {
                Button { runner.back() } label: { Image(systemName: "backward.end.fill") }
                    .buttonStyle(KairosRound())
                    .help("Back one")
                Button("Done") { runner.advance() }
                    .buttonStyle(KairosPrimary(height: 56))
                    .frame(maxWidth: 320)
                    .keyboardShortcut(.return, modifiers: [])
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct KairosSay: View {
    @ObservedObject var runner: KairosRunner
    let beat: KairosBeat
    let state: KairosRunState

    var body: some View {
        let lines = beat.lines.isEmpty ? [beat.name] : beat.lines
        let at = min(state.sayLine, lines.count - 1)
        VStack(alignment: .leading, spacing: 12) {
            KairosLook.kicker("\(beat.name) · line \(at + 1) of \(lines.count)")
            Text(lines[at])
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(KairosBoard.ink)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                ForEach(0..<beat.times, id: \.self) { index in
                    Circle()
                        .fill(index < state.said ? KairosBoard.accent : KairosBoard.line)
                        .frame(width: 9, height: 9)
                }
                Text("Said \(state.said) of \(beat.times) times")
                    .font(.system(size: 11))
                    .foregroundStyle(KairosBoard.muted)
                    .padding(.leading, 4)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                        if index != at {
                            HStack(alignment: .top, spacing: 8) {
                                Text(index < at ? "✓" : "")
                                    .foregroundStyle(KairosBoard.accent)
                                    .frame(width: 12)
                                Text(line)
                                    .foregroundStyle(index < at ? KairosBoard.muted : KairosBoard.ink)
                            }
                            .font(.system(size: 12))
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.never)
            Button("Said it") { runner.said() }
                .buttonStyle(KairosPrimary(height: 44))
                .keyboardShortcut(.return, modifiers: [])
        }
    }
}

private func kairosBase(_ live: KairosLive, _ beat: KairosBeat, _ state: KairosRunState) -> KairosEntry {
    let step = live.steps[beat.step]
    let split = KairosPlan.split(step.title)
    let title = [split.name, KairosPlan.plainDetail(split.detail)].filter { !$0.isEmpty }.joined(separator: " · ")
    let day = state.isAdhoc ? ScheduleStore.shared.today : state.day
    return KairosEntry(id: KairosEntry.id(routine: live.routine.id, day: day, slot: state.slot, step: step.id.uuidString),
                       routine: live.routine.id.uuidString, routineName: live.routine.name, day: day, slot: state.slot.rawValue,
                       step: step.id.uuidString, title: title, tag: beat.tag)
}

private struct KairosWrite: View {
    @ObservedObject var runner: KairosRunner
    @ObservedObject var journal: KairosJournal
    let live: KairosLive
    let beat: KairosBeat
    let state: KairosRunState
    @State private var lines: [String] = []
    @State private var text = ""
    @State private var loaded = false
    @State private var pending: DispatchWorkItem?

    private var base: KairosEntry { kairosBase(live, beat, state) }

    var body: some View {
        let saved = journal.entry(base.id)
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(heading)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(KairosBoard.ink)
                Spacer()
                if let soft = runner.softLeft(beat) {
                    Text(KairosPlan.clock(soft))
                        .font(.system(size: 17, weight: .light))
                        .monospacedDigit()
                        .foregroundStyle(KairosBoard.muted)
                }
            }
            Text(beat.prompt.isEmpty ? (beat.tip.isEmpty ? beat.detail : beat.tip) : beat.prompt)
                .font(.system(size: 12))
                .foregroundStyle(KairosBoard.muted)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
            if beat.fields > 1 {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(0..<beat.fields, id: \.self) { index in
                            HStack(alignment: .top, spacing: 8) {
                                Text("\(index + 1)")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(KairosBoard.muted)
                                    .frame(width: 12)
                                    .padding(.top, 9)
                                TextField(index == beat.fields - 1 ? "What else went well, and why?" : "", text: binding(index), axis: .vertical)
                                    .textFieldStyle(.plain)
                                    .lineLimit(2...4)
                                    .font(.system(size: 14))
                                    .foregroundStyle(KairosBoard.ink)
                                    .padding(10)
                                    .background(RoundedRectangle(cornerRadius: 10).fill(KairosBoard.column))
                                    .boardEdge(10)
                            }
                        }
                    }
                }
                .scrollIndicators(.never)
            } else {
                TextEditor(text: $text)
                    .font(.system(size: 14))
                    .foregroundStyle(KairosBoard.ink)
                    .scrollContentBackground(.hidden)
                    .lineSpacing(4)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 12).fill(KairosBoard.column))
                    .boardEdge(12)
                    .onChange(of: text) { _, _ in later() }
            }
            Text(Self.footer(saved))
                .font(.system(size: 11))
                .foregroundStyle(KairosBoard.muted)
            HStack(spacing: 10) {
                Button("Skip") {
                    store()
                    runner.advance(tick: false)
                }
                .buttonStyle(KairosGhost(height: 40))
                Button("Save and next") {
                    store()
                    runner.advance()
                }
                .buttonStyle(KairosPrimary(height: 40))
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .onAppear(perform: load)
        .onDisappear(perform: store)
    }

    private var heading: String {
        let extra = beat.tag == "script" || beat.tag == "action" ? KairosPlan.plainDetail(beat.detail).replacingOccurrences(of: ", as if it's done", with: "") : ""
        return [beat.name, extra].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private static let parse: ISO8601DateFormatter = {
        let format = ISO8601DateFormatter()
        format.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return format
    }()

    private static func footer(_ saved: KairosEntry?) -> String {
        guard let stamp = saved?.updated, let shown = time(stamp) else { return "The timer is a guide; it won't cut you off." }
        return "Saved \(shown) · in your journal on every device"
    }

    private static func time(_ stamp: String) -> String? {
        (parse.date(from: stamp) ?? ISO8601DateFormatter().date(from: stamp)).map(KairosLook.timeFormat.string(from:))
    }

    private func binding(_ index: Int) -> Binding<String> {
        Binding(
            get: { lines.indices.contains(index) ? lines[index] : "" },
            set: { value in
                while lines.count <= index { lines.append("") }
                lines[index] = value
                later()
            }
        )
    }

    private func load() {
        guard !loaded else { return }
        let saved = journal.entry(base.id)
        lines = (0..<max(beat.fields, 0)).map { index in
            let old = saved?.lines ?? []
            return old.indices.contains(index) ? old[index] : ""
        }
        text = saved?.text ?? ""
        loaded = true
    }

    private func later() {
        pending?.cancel()
        let work = DispatchWorkItem { store() }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7, execute: work)
    }

    private func store() {
        pending?.cancel()
        guard loaded else { return }
        var entry = journal.entry(base.id) ?? base
        if beat.fields > 1 {
            let trimmed = lines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard trimmed.contains(where: { !$0.isEmpty }) || journal.entry(base.id) != nil else { return }
            entry.lines = trimmed
        } else {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty || journal.entry(base.id) != nil else { return }
            entry.text = trimmed
        }
        entry.title = base.title
        entry.tag = base.tag
        journal.put(entry)
    }
}

private struct KairosLog: View {
    @ObservedObject var runner: KairosRunner
    @ObservedObject var journal: KairosJournal
    let live: KairosLive
    let beat: KairosBeat
    let state: KairosRunState
    @State private var time = ""
    @State private var km = ""
    @State private var notes = ""
    @State private var loaded = false

    private var base: KairosEntry { kairosBase(live, beat, state) }

    private var seconds: Double? {
        let trimmed = time.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.contains(":") {
            let parts = trimmed.split(separator: ":").map { Double($0) }
            guard parts.count == 2, let minutes = parts[0], let rest = parts[1] else { return nil }
            return minutes * 60 + rest
        }
        return Double(trimmed.replacingOccurrences(of: ",", with: ".")).map { ($0 * 60).rounded() }
    }

    private var distance: Double? {
        guard let value = Double(km.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")), value > 0 else { return nil }
        return (value * 100).rounded() / 100
    }

    private var previous: KairosEntry? {
        journal.sorted.first { $0.tag == "run" && $0.km != nil && $0.seconds != nil && $0.id != base.id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            KairosLook.kicker("Today's \(beat.name.lowercased())")
            Text(beat.plan)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(KairosBoard.ink)
                .fixedSize(horizontal: false, vertical: true)
            if !beat.tip.isEmpty {
                Text(beat.tip)
                    .font(.system(size: 12))
                    .foregroundStyle(KairosBoard.muted)
                    .lineLimit(5)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 12).fill(KairosBoard.column))
                    .boardEdge(12)
            }
            Text("Go and do it. When you're back, enter what you did.")
                .font(.system(size: 12))
                .foregroundStyle(KairosBoard.muted)
            HStack(spacing: 10) {
                metric("Time", "12:40", "min", $time)
                metric("Distance", "1.6", "km", $km)
            }
            HStack {
                if let seconds, let distance {
                    Text("Pace \(KairosPlan.clock(seconds / distance)) /km")
                }
                Spacer()
                if let previous, let pkm = previous.km, let ps = previous.seconds {
                    Text("Last: \(KairosEntry.number(pkm)) km in \(KairosPlan.clock(ps))")
                }
            }
            .font(.system(size: 11))
            .foregroundStyle(KairosBoard.muted)
            TextField("Notes: how it felt, any pain, weather", text: $notes, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(2...4)
                .font(.system(size: 13))
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(KairosBoard.column))
                .boardEdge(10)
            Spacer(minLength: 0)
            HStack(spacing: 10) {
                Button("Later") { runner.advance(tick: false) }
                    .buttonStyle(KairosGhost(height: 40))
                Button("Save and next") {
                    store()
                    runner.advance()
                }
                .buttonStyle(KairosPrimary(height: 40))
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .onAppear(perform: load)
    }

    private func metric(_ label: String, _ hint: String, _ unit: String, _ value: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(KairosBoard.muted)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                TextField(hint, text: value)
                    .textFieldStyle(.plain)
                    .font(.system(size: 22, weight: .medium))
                    .monospacedDigit()
                Text(unit)
                    .font(.system(size: 11))
                    .foregroundStyle(KairosBoard.muted)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(KairosBoard.column))
        .boardEdge(12)
    }

    private func load() {
        guard !loaded else { return }
        if let saved = journal.entry(base.id) {
            time = saved.seconds.map { KairosPlan.clock($0) } ?? ""
            km = saved.km.map(KairosEntry.number) ?? ""
            notes = saved.notes ?? ""
        }
        loaded = true
    }

    private func store() {
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard seconds != nil || distance != nil || !trimmedNotes.isEmpty else { return }
        var entry = journal.entry(base.id) ?? base
        entry.seconds = seconds
        entry.km = distance
        entry.notes = trimmedNotes
        entry.title = base.title
        entry.tag = "run"
        journal.put(entry)
    }
}

private struct KairosDone: View {
    @ObservedObject var runner: KairosRunner
    @ObservedObject var journal: KairosJournal
    let live: KairosLive
    let state: KairosRunState

    private static let feels: [(value: String, label: String, score: String)] = [("easy", "Easy", "2"), ("right", "Right", "3"), ("too-hard", "Too hard", "4")]

    private var feelId: String {
        if state.isAdhoc { return state.workout ?? "" }
        return KairosEntry.id(routine: live.routine.id, day: state.day, slot: state.slot, step: "feel")
    }

    private var rows: [(name: String, done: Bool, spent: Int)] {
        if state.isAdhoc {
            return live.steps.enumerated().map { index, step in
                let spent = state.spent[String(index)] ?? 0
                return (name: KairosFit.name(step), done: spent > 0, spent: spent)
            }
        }
        let items = ScheduleStore.shared.items(on: state.day, slot: state.slot, in: [live.routine])
        return items.enumerated().map { index, item in
            (name: KairosFit.name(item.step), done: item.done, spent: state.spent[String(index)] ?? 0)
        }
    }

    private var chosen: String? {
        guard let feel = journal.entry(feelId)?.feel else { return nil }
        if state.isAdhoc { return Self.feels.first { $0.score == feel }?.value }
        return feel
    }

    var body: some View {
        let list = rows
        let ticked = list.filter(\.done).count
        let all = ticked == list.count
        let total = Int((state.finished ?? Date()).timeIntervalSince(state.started))
        VStack(spacing: 16) {
            ZStack {
                Circle().fill(all ? Ventus.ink : Ventus.warmTrack)
                Image(systemName: all ? "checkmark" : "pause")
                    .font(.system(size: 28, weight: .heavy))
                    .foregroundStyle(all ? Ventus.onInk : Ventus.ink)
            }
            .frame(width: 72, height: 72)
            Text(all ? (state.isAdhoc ? "Done" : "\(KairosFit.title(live.steps, fallback: live.routine.name)) done") : "Stopped early")
                .font(Ventus.font(30, .black))
                .foregroundStyle(Ventus.ink)
                .multilineTextAlignment(.center)
            HStack(spacing: 14) {
                Text("\(KairosPlan.minutes(total))m")
                if !state.isAdhoc {
                    HStack(spacing: 6) {
                        VentusIcon(.check, color: Ventus.muted, size: 16, weight: 2.6)
                        Text("\(ticked)/\(list.count)")
                    }
                    .help("Ticked in Aqua")
                }
            }
            .font(Ventus.font(16, .bold))
            .foregroundStyle(Ventus.muted)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(list.enumerated()), id: \.offset) { _, row in
                        HStack(spacing: 10) {
                            VentusIcon(row.done ? .check : .other, color: row.done ? Ventus.ink : Ventus.faint, size: 16, weight: 2.4)
                            Text(row.name)
                                .foregroundStyle(row.done ? Ventus.ink : Ventus.muted)
                            Spacer()
                            if row.spent > 0 {
                                Text(KairosPlan.clock(row.spent))
                                    .monospacedDigit()
                                    .foregroundStyle(Ventus.muted)
                            }
                        }
                        .font(Ventus.font(14, .bold))
                        .padding(.vertical, 7)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Ventus.card.opacity(0.8)))
            }
            .scrollIndicators(.never)
            HStack(spacing: 10) {
                VentusIcon(.heart, color: Ventus.muted, size: 22)
                ForEach(Self.feels, id: \.value) { feel in
                    Button(feel.label) { setFeel(feel.value, score: feel.score) }
                        .buttonStyle(KairosChip(on: chosen == feel.value))
                        .disabled(feelId.isEmpty)
                }
            }
            Button(state.isAdhoc ? "Back" : "Back to today") { runner.end(reason: "finished") }
                .buttonStyle(KairosPrimary(height: 50))
                .keyboardShortcut(.return, modifiers: [])
        }
    }

    private func setFeel(_ value: String, score: String) {
        if state.isAdhoc {
            guard var entry = journal.entry(feelId) else { return }
            entry.feel = score
            journal.put(entry)
            return
        }
        var entry = journal.entry(feelId) ?? KairosEntry(id: feelId, routine: live.routine.id.uuidString, routineName: live.routine.name, day: state.day,
                                                         slot: state.slot.rawValue, step: "feel", title: live.routine.name, tag: "feel")
        entry.feel = value
        journal.put(entry)
    }
}

private struct KairosChip: ButtonStyle {
    let on: Bool
    var fill = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: on ? .semibold : .medium))
            .lineLimit(1)
            .foregroundStyle(on ? KairosLook.onAccent : KairosBoard.muted)
            .padding(.horizontal, 14)
            .frame(maxWidth: fill ? .infinity : nil)
            .frame(height: 30)
            .background(Capsule().fill(on ? KairosBoard.accentStyle : AnyShapeStyle(Color.clear)))
            .overlay(Capsule().stroke(on ? Color.clear : KairosBoard.line, lineWidth: 1))
            .contentShape(Capsule())
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}
