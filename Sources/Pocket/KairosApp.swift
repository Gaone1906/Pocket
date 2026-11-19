import AppKit
import Combine
import SwiftUI

final class KairosApp: PocketApp {
    private var watch: AnyCancellable?

    override var defaultSize: NSSize { NSSize(width: 380, height: 520) }
    override var minSize: NSSize { NSSize(width: 380, height: 520) }
    override var resizable: Bool { false }

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

    override func makeContent() -> NSView {
        let view = KairosGlance(runner: KairosRunner.shared, store: ScheduleStore.shared) { [weak self] in self?.openWindow(source: "dropdown") }
        return ThemedHostingView(rootView: view, app: "runner")
    }

    override func didShow() {
        ScheduleStore.shared.tick()
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
            .foregroundColor: AppThemeStore.shared.iconTint(for: spec.id) ?? NSColor.labelColor
        ]
        return NSAttributedString(string: text, attributes: attributes)
    }

    func openWindow(source: String) {
        hide(reason: "switched")
        KairosWindow.shared.present(source: source)
    }

    override func menuItems() -> [NSMenuItem] {
        let open = NSMenuItem(title: "Open Kairos", action: #selector(openFromMenu), keyEquivalent: "")
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

    static func hour(_ hour: Int) -> String {
        let suffix = hour < 12 ? "AM" : "PM"
        let shown = hour % 12 == 0 ? 12 : hour % 12
        return "\(shown) \(suffix)"
    }

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
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(KairosLook.onAccent)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(Capsule().fill(tint.map { AnyShapeStyle($0) } ?? KairosBoard.accentStyle))
            .opacity(configuration.isPressed ? 0.8 : 1)
            .contentShape(Capsule())
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
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(KairosBoard.ink)
            .frame(width: 40, height: 40)
            .overlay(Circle().stroke(KairosBoard.line, lineWidth: 1))
            .background(Circle().fill(KairosBoard.column.opacity(configuration.isPressed ? 1 : 0.4)))
            .contentShape(Circle())
    }
}

private enum KairosPage {
    case today
    case journal
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
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 980, height: 680),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = "Kairos"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.appearance = KairosBoard.theme.appearance
        window.backgroundColor = NSColor(KairosBoard.backdrop)
        themeWatch = AppThemeStore.shared.publisher(for: "runner").sink { [weak window] theme in
            window?.appearance = theme.appearance
            window?.backgroundColor = NSColor(theme.backdrop)
        }
        window.minSize = NSSize(width: 780, height: 540)
        window.contentView = NSHostingView(rootView: KairosBoardView(runner: KairosRunner.shared, store: ScheduleStore.shared, journal: KairosJournal.shared))
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

private struct KairosGlance: View {
    @ObservedObject var runner: KairosRunner
    @ObservedObject var store: ScheduleStore
    @ObservedObject var themes = AppThemeStore.shared
    let open: () -> Void

    var body: some View {
        let day = store.today
        let sessions = KairosSession.all(on: day)
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Kairos")
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(KairosBoard.ink)
                    Text(KairosLook.title(day))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(KairosBoard.muted)
                }
                Spacer()
                Button(action: open) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(KairosBoard.muted)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(KairosBoard.line.opacity(0.55)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Open Kairos in its own window")
            }
            .padding(.horizontal, 18)
            .padding(.top, 20)
            .padding(.bottom, 14)
            Rectangle().fill(KairosBoard.line).frame(height: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if runner.running, let live = runner.live, let beat = live.beat, let state = runner.state {
                        now(live, beat, state)
                    }
                    if sessions.isEmpty {
                        Text("Nothing to run today.")
                            .font(.system(size: 13))
                            .foregroundStyle(KairosBoard.muted)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 30)
                    }
                    ForEach(ScheduleSlot.allCases) { slot in
                        let list = sessions.filter { $0.slot == slot }
                        if !list.isEmpty {
                            KairosLook.kicker(slot == .morning ? "Morning" : "Tonight · from \(KairosLook.hour(store.book.nightFrom))")
                                .padding(.top, 6)
                            ForEach(list) { session in
                                Button(action: open) {
                                    KairosSessionRow(session: session, running: runner.isRunning(session), action: nil)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(16)
            }
            .scrollIndicators(.never)
            Button("Open Kairos", action: open)
                .buttonStyle(KairosPrimary(height: 38))
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
        }
        .id(KairosBoard.theme.id)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BoardBackdrop(theme: KairosBoard.theme))
        .ignoresSafeArea()
        .appTheme(KairosBoard.theme)
    }

    private func now(_ live: KairosLive, _ beat: KairosBeat, _ state: KairosRunState) -> some View {
        Button(action: open) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    KairosLook.kicker("Now · \(KairosSession.title(live.routine, on: state.day))")
                    Text(beat.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(KairosBoard.ink)
                    Text("Step \(beat.step + 1) of \(live.steps.count)\(state.paused ? " · paused" : "")")
                        .font(.system(size: 11))
                        .foregroundStyle(KairosBoard.muted)
                }
                Spacer()
                if beat.counted {
                    Text(KairosPlan.clock(runner.remaining))
                        .font(.system(size: 24, weight: .light))
                        .monospacedDigit()
                        .foregroundStyle(KairosBoard.ink)
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 14).fill(KairosBoard.accent.opacity(0.12)))
            .boardEdge(14)
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}

private struct KairosBoardView: View {
    @ObservedObject var runner: KairosRunner
    @ObservedObject var store: ScheduleStore
    @ObservedObject var journal: KairosJournal
    @ObservedObject var themes = AppThemeStore.shared
    @State private var page = KairosPage.today

    var body: some View {
        HStack(spacing: 0) {
            KairosSidebar(runner: runner, store: store, page: $page)
                .frame(width: 280)
                .background(KairosBoard.sidebar)
            Rectangle().fill(KairosBoard.line).frame(width: 1)
            stage
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .id(KairosBoard.theme.id)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BoardBackdrop(theme: KairosBoard.theme))
        .ignoresSafeArea()
        .appTheme(KairosBoard.theme)
    }

    @ViewBuilder private var stage: some View {
        if let state = runner.state, let live = runner.live {
            Group {
                if state.finished != nil {
                    KairosDone(runner: runner, journal: journal, live: live, state: state)
                } else {
                    KairosRun(runner: runner, journal: journal, live: live, state: state)
                }
            }
            .frame(maxWidth: 640)
            .padding(.horizontal, 24)
            .padding(.top, 28)
            .padding(.bottom, 20)
        } else if page == .journal {
            KairosJournalView(journal: journal) { page = .today }
                .frame(maxWidth: 720)
                .padding(.top, 14)
        } else {
            KairosUpNext(runner: runner, store: store)
                .frame(maxWidth: 620)
                .padding(.horizontal, 24)
                .padding(.top, 40)
                .padding(.bottom, 24)
        }
    }
}

private struct KairosSidebar: View {
    @ObservedObject var runner: KairosRunner
    @ObservedObject var store: ScheduleStore
    @Binding var page: KairosPage
    @State private var sound = KairosRunner.sound
    @State private var hold = KairosRunner.hold

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Kairos")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(KairosBoard.ink)
                Text(KairosLook.title(store.today))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(KairosBoard.muted)
            }
            .padding(.horizontal, 18)
            .padding(.top, 40)
            .padding(.bottom, 14)
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if let state = runner.state, let live = runner.live {
                        steps(live, state)
                    } else {
                        sessions
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
            }
            .scrollIndicators(.never)
            Rectangle().fill(KairosBoard.line).frame(height: 1)
            VStack(alignment: .leading, spacing: 10) {
                if runner.state == nil {
                    HStack(spacing: 6) {
                        Button("Today") { page = .today }.buttonStyle(KairosChip(on: page == .today))
                        Button("Journal") { page = .journal }.buttonStyle(KairosChip(on: page == .journal))
                    }
                }
                Toggle("Chime at each change", isOn: $sound)
                Toggle("Wait for a click before each step", isOn: $hold)
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            .font(.system(size: 11))
            .foregroundStyle(KairosBoard.muted)
            .padding(14)
        }
        .onChange(of: sound) { _, on in
            KairosRunner.sound = on
            note("kairos setting changed sound=\(on)")
        }
        .onChange(of: hold) { _, on in
            KairosRunner.hold = on
            note("kairos setting changed hold=\(on)")
        }
    }

    private var sessions: some View {
        let list = KairosSession.all(on: store.today)
        return VStack(alignment: .leading, spacing: 8) {
            if list.isEmpty {
                Text("Nothing to run today. Timed routines from Orario show up here on the days they run.")
                    .font(.system(size: 12))
                    .foregroundStyle(KairosBoard.muted)
                    .padding(.horizontal, 4)
            }
            ForEach(ScheduleSlot.allCases) { slot in
                let group = list.filter { $0.slot == slot }
                if !group.isEmpty {
                    KairosLook.kicker(slot == .morning ? "Morning" : "Tonight · from \(KairosLook.hour(store.book.nightFrom))")
                        .padding(.top, 6)
                        .padding(.horizontal, 4)
                    ForEach(group) { session in
                        KairosSessionRow(session: session, running: false, action: session.finished ? nil : { runner.start(session) })
                    }
                }
            }
        }
    }

    private func steps(_ live: KairosLive, _ state: KairosRunState) -> some View {
        let items = store.items(on: state.day, slot: state.slot, in: [live.routine])
        let current = live.beat?.step ?? 0
        return VStack(alignment: .leading, spacing: 4) {
            KairosLook.kicker("\(KairosSession.title(live.routine, on: state.day)) · \(state.slot.label)")
                .padding(.horizontal, 6)
            if state.finished == nil {
                Text("\(KairosPlan.minutes(Int(runner.sessionLeft(live)))) min left")
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(KairosBoard.muted)
                    .padding(.horizontal, 6)
                    .padding(.bottom, 6)
            }
            ForEach(Array(live.steps.enumerated()), id: \.offset) { index, step in
                let done = items.first { $0.step.id == step.id }?.done ?? false
                let here = index == current && state.finished == nil
                Button {
                    if state.finished == nil { runner.jump(to: index) }
                } label: {
                    HStack(spacing: 10) {
                        ZStack {
                            if done {
                                Circle().fill(KairosBoard.accentStyle)
                                Image(systemName: "checkmark")
                                    .font(.system(size: 8, weight: .heavy))
                                    .foregroundStyle(KairosLook.onAccent)
                            } else {
                                Circle().strokeBorder(here ? KairosBoard.accent : KairosBoard.faint, lineWidth: 1.5)
                            }
                        }
                        .frame(width: 16, height: 16)
                        Text(KairosPlan.split(step.title).name)
                            .font(.system(size: 13, weight: here ? .semibold : .regular))
                            .foregroundStyle(done && !here ? KairosBoard.muted : KairosBoard.ink)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text(KairosPlan.clock(state.spent[String(index)] ?? KairosPlan.estimate(step)))
                            .font(.system(size: 11))
                            .monospacedDigit()
                            .foregroundStyle(KairosBoard.muted)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 9).fill(here ? KairosBoard.accent.opacity(0.12) : Color.clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(state.finished == nil ? "Jump to this step" : "")
            }
            Text("Each step ticks in Orario as you finish it.")
                .font(.system(size: 11))
                .foregroundStyle(KairosBoard.faint)
                .padding(.horizontal, 6)
                .padding(.top, 8)
        }
    }
}

private struct KairosUpNext: View {
    @ObservedObject var runner: KairosRunner
    @ObservedObject var store: ScheduleStore

    var body: some View {
        let list = KairosSession.all(on: store.today)
        let open = list.filter { !$0.finished }
        let next = open.first { $0.slot == store.slotNow } ?? open.first
        VStack(alignment: .leading, spacing: 16) {
            if let next {
                KairosLook.kicker(next.slot == store.slotNow ? "Up next" : "Later today")
                Text(KairosSession.dayNumber(next.routine, on: next.day).map { "\(next.routine.name) · Day \($0.n) of \($0.of)" } ?? next.routine.name)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(KairosBoard.ink)
                Text("\(next.slot.label) · \(next.total) steps · about \(KairosPlan.minutes(next.seconds)) min\(next.writing > 0 ? " · \(next.writing) to write" : "")")
                    .font(.system(size: 13))
                    .foregroundStyle(KairosBoard.muted)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(next.steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text("\(index + 1)")
                                .font(.system(size: 12, weight: .semibold))
                                .monospacedDigit()
                                .foregroundStyle(KairosBoard.faint)
                                .frame(width: 16, alignment: .trailing)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(ScheduleStepText.plain(step.title))
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(KairosBoard.ink)
                                Text(KairosPlan.howLabel(step))
                                    .font(.system(size: 12))
                                    .foregroundStyle(KairosBoard.muted)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 8)
                        .overlay(alignment: .bottom) { Rectangle().fill(KairosBoard.line).frame(height: 1) }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 16).fill(KairosBoard.column))
                .boardEdge(16)
                Spacer(minLength: 0)
                Button(next.done > 0 ? "Continue" : "Start") { runner.start(next) }
                    .buttonStyle(KairosPrimary(height: 48))
                    .keyboardShortcut(.return, modifiers: [])
            } else {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: list.isEmpty ? "figure.mind.and.body" : "checkmark.circle")
                        .font(.system(size: 34, weight: .light))
                        .foregroundStyle(KairosBoard.faint)
                    Text(list.isEmpty ? "Nothing to run today" : "All done for today")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(KairosBoard.ink)
                    Text(list.isEmpty ? "Timed routines from Orario show up here on the days they run." : "Every session is ticked in Orario.")
                        .font(.system(size: 13))
                        .foregroundStyle(KairosBoard.muted)
                }
                .frame(maxWidth: .infinity)
                Spacer()
            }
        }
    }
}

private struct KairosSessionRow: View {
    let session: KairosSession
    let running: Bool
    let action: (() -> Void)?

    private var summary: String {
        if session.finished {
            let last = ScheduleStore.shared.book.checks
                .filter { $0.routine == session.routine.id && $0.day == session.day && $0.slot == session.slot }
                .map(\.done).max()
            return last.map { "Done at \(KairosLook.timeFormat.string(from: $0))" } ?? "Done"
        }
        var parts = ["\(session.total) step\(session.total == 1 ? "" : "s")", "about \(KairosPlan.minutes(session.seconds)) min"]
        if session.done > 0 { parts[0] = "\(session.done) of \(session.total) done" }
        if session.writing > 0 { parts.append("\(session.writing) to write") }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().strokeBorder(session.finished ? Color.clear : KairosBoard.faint, lineWidth: 1.5)
                if session.finished {
                    Circle().fill(KairosBoard.accentStyle)
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(KairosLook.onAccent)
                }
            }
            .frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(KairosSession.dayNumber(session.routine, on: session.day).map { "\(session.routine.name) · Day \($0.n) of \($0.of)" } ?? session.routine.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(KairosBoard.ink)
                Text(summary)
                    .font(.system(size: 12))
                    .foregroundStyle(KairosBoard.muted)
            }
            Spacer(minLength: 8)
            if let action, !session.finished || running {
                Button(running ? "Resume" : session.done > 0 ? "Continue" : "Start", action: action)
                    .buttonStyle(KairosPrimary(height: 30))
                    .fixedSize()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 12).fill(KairosBoard.column))
        .boardEdge(12)
        .opacity(session.finished && !running ? 0.75 : 1)
    }
}

private struct KairosRun: View {
    @ObservedObject var runner: KairosRunner
    @ObservedObject var journal: KairosJournal
    let live: KairosLive
    let state: KairosRunState

    private var beat: KairosBeat { live.beat ?? live.beats[0] }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            top
            segments
            if state.waiting {
                waiting
            } else {
                switch beat.kind {
                case .count: KairosCount(runner: runner, live: live, beat: beat, state: state)
                case .rest: KairosRest(runner: runner, beat: beat)
                case .reps: KairosReps(runner: runner, live: live, beat: beat)
                case .say: KairosSay(runner: runner, beat: beat, state: state)
                case .write: KairosWrite(runner: runner, journal: journal, live: live, beat: beat, state: state).id(entryId)
                case .log: KairosLog(runner: runner, journal: journal, live: live, beat: beat, state: state).id(entryId)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(mood)
    }

    private var entryId: String {
        KairosEntry.id(routine: live.routine.id, day: state.day, slot: state.slot, step: live.steps[beat.step].id.uuidString)
    }

    @ViewBuilder private var mood: some View {
        if !state.waiting && beat.kind == .rest {
            KairosLook.rest.opacity(0.16)
        } else if !state.waiting && beat.hot {
            KairosBoard.accent.opacity(0.12)
        } else {
            Color.clear
        }
    }

    private var top: some View {
        HStack(alignment: .center, spacing: 10) {
            Menu {
                ForEach(Array(live.steps.enumerated()), id: \.offset) { index, step in
                    Button {
                        runner.jump(to: index)
                    } label: {
                        Text("\(index + 1). \(ScheduleStepText.plain(step.title))")
                    }
                }
            } label: {
                Image(systemName: "list.bullet")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(KairosBoard.muted)
                    .frame(width: 30, height: 30)
                    .overlay(Circle().stroke(KairosBoard.line, lineWidth: 1))
                    .contentShape(Circle())
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .buttonStyle(.plain)
            .fixedSize()
            .help("Jump to a step")
            VStack(alignment: .leading, spacing: 1) {
                Text("\(KairosSession.title(live.routine, on: state.day)) · \(state.slot.label)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(KairosBoard.ink)
                Text("Step \(beat.step + 1) of \(live.steps.count) · \(KairosPlan.minutes(Int(runner.sessionLeft(live)))) min left")
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(KairosBoard.muted)
            }
            Spacer()
            Button("End") { runner.end(reason: "button") }
                .buttonStyle(KairosGhost(height: 28))
                .help("End this session; finished steps stay ticked in Orario")
        }
    }

    private var segments: some View {
        let inStep = live.beats.enumerated().filter { $0.element.step == beat.step }
        let position = inStep.firstIndex { $0.offset == live.index } ?? 0
        let fraction = inStep.isEmpty ? 0 : CGFloat(position) / CGFloat(inStep.count)
        return HStack(spacing: 4) {
            ForEach(0..<live.steps.count, id: \.self) { index in
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(KairosBoard.line)
                        Capsule()
                            .fill(KairosBoard.accentStyle)
                            .frame(width: index < beat.step ? geo.size.width : index == beat.step ? geo.size.width * max(0.04, fraction) : 0)
                    }
                }
                .frame(height: 4)
            }
        }
    }

    private var waiting: some View {
        VStack(alignment: .leading, spacing: 10) {
            Spacer()
            KairosLook.kicker("Up next")
            Text(beat.name)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(KairosBoard.ink)
            Text(KairosPlan.howLabel(live.steps[beat.step]))
                .font(.system(size: 13))
                .foregroundStyle(KairosBoard.muted)
            Spacer()
            Button("Start this step") { runner.togglePause() }
                .buttonStyle(KairosPrimary(height: 44))
                .keyboardShortcut(.return, modifiers: [])
        }
    }
}

private struct KairosRing: View {
    let fraction: Double
    let tint: Color
    let width: CGFloat

    var body: some View {
        ZStack {
            Circle().stroke(KairosBoard.line, lineWidth: width)
            Circle()
                .trim(from: 0, to: max(0, min(1, fraction)))
                .stroke(tint, style: StrokeStyle(lineWidth: width, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

private struct KairosControls: View {
    @ObservedObject var runner: KairosRunner
    let paused: Bool

    var body: some View {
        HStack(spacing: 14) {
            Spacer()
            Button { runner.back() } label: { Image(systemName: "backward.end.fill") }
                .buttonStyle(KairosRound())
                .help("Back one")
            Button { runner.togglePause() } label: {
                Image(systemName: paused ? "play.fill" : "pause.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(KairosLook.onAccent)
                    .frame(width: 52, height: 52)
                    .background(Circle().fill(KairosBoard.accentStyle))
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

    var body: some View {
        let left = runner.remaining
        VStack(alignment: .leading, spacing: 12) {
            if !beat.label.isEmpty { KairosLook.kicker(beat.label) }
            Text(beat.name)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(KairosBoard.ink)
            if beat.type == "timed", !beat.detail.isEmpty {
                Text(KairosPlan.plainDetail(beat.detail))
                    .font(.system(size: 13))
                    .foregroundStyle(KairosBoard.muted)
            }
            ZStack {
                KairosRing(fraction: beat.seconds > 0 ? left / Double(beat.seconds) : 0, tint: KairosBoard.accent, width: 9)
                VStack(spacing: 2) {
                    Text(KairosPlan.clock(left))
                        .font(.system(size: 52, weight: .light))
                        .monospacedDigit()
                        .foregroundStyle(KairosBoard.ink)
                    if state.paused {
                        Text("Paused")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(KairosBoard.muted)
                    }
                }
            }
            .frame(width: 190, height: 190)
            .frame(maxWidth: .infinity)
            if let then = beat.then {
                Text(then)
                    .font(.system(size: 12))
                    .foregroundStyle(KairosBoard.muted)
                    .frame(maxWidth: .infinity)
            }
            if beat.rounds > 1 && beat.hot {
                HStack(spacing: 4) {
                    ForEach(0..<beat.rounds, id: \.self) { index in
                        Text("\(index + 1)")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(index < beat.round ? KairosLook.onAccent : KairosBoard.accentInk)
                            .frame(maxWidth: .infinity)
                            .frame(height: 20)
                            .background(RoundedRectangle(cornerRadius: 5).fill(index < beat.round ? KairosBoard.accent : KairosBoard.accent.opacity(index == beat.round ? 0.3 : 0.12)))
                    }
                }
            }
            if let cue {
                VStack(alignment: .leading, spacing: 4) {
                    KairosLook.kicker("Now")
                    Text(cue.text)
                        .font(.system(size: 13))
                        .foregroundStyle(KairosBoard.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(KairosBoard.column))
                .boardEdge(12)
            } else if beat.type == "timed", !beat.tip.isEmpty {
                Text(beat.tip)
                    .font(.system(size: 12))
                    .foregroundStyle(KairosBoard.muted)
                    .lineLimit(4)
            }
            KairosMoves(beat: beat)
            Spacer(minLength: 0)
            KairosControls(runner: runner, paused: state.paused)
        }
    }
}

private struct KairosRest: View {
    @ObservedObject var runner: KairosRunner
    let beat: KairosBeat

    var body: some View {
        let left = runner.remaining
        VStack(spacing: 16) {
            Spacer(minLength: 0)
            VStack(spacing: 4) {
                Text(beat.name.uppercased())
                    .font(.system(size: 12, weight: .bold))
                    .tracking(2)
                    .foregroundStyle(KairosLook.rest)
                Text(beat.label)
                    .font(.system(size: 13))
                    .foregroundStyle(KairosBoard.muted)
            }
            ZStack {
                KairosRing(fraction: beat.seconds > 0 ? left / Double(beat.seconds) : 0, tint: KairosLook.rest, width: 9)
                Text(KairosPlan.clock(left))
                    .font(.system(size: 56, weight: .light))
                    .monospacedDigit()
                    .foregroundStyle(KairosBoard.ink)
            }
            .frame(width: 200, height: 200)
            HStack(spacing: 10) {
                Button("+15s") { runner.addTime(15) }.buttonStyle(KairosGhost(height: 32))
                Button("Skip rest") { runner.advance() }.buttonStyle(KairosGhost(height: 32))
            }
            Spacer(minLength: 0)
            if let next = beat.nextName {
                VStack(alignment: .leading, spacing: 3) {
                    KairosLook.kicker(beat.rounds > 0 && beat.moves.isEmpty ? "Get ready" : "Get ready · round \(beat.round + 2) of \(beat.rounds)")
                    Text(beat.reps > 0 ? "\(beat.reps) \(next)" : next)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(KairosBoard.ink)
                    if beat.moves.count > 1 {
                        Text("then " + beat.moves.dropFirst().map { $0.lowercased() }.joined(separator: ", "))
                            .font(.system(size: 12))
                            .foregroundStyle(KairosBoard.muted)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 14).fill(KairosBoard.column))
                .boardEdge(14)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct KairosReps: View {
    @ObservedObject var runner: KairosRunner
    let live: KairosLive
    let beat: KairosBeat

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !beat.label.isEmpty { KairosLook.kicker(beat.label) }
            Spacer(minLength: 0)
            if beat.reps > 0 {
                Text("\(beat.reps)")
                    .font(.system(size: 84, weight: .light))
                    .monospacedDigit()
                    .foregroundStyle(KairosBoard.ink)
            }
            Text(beat.name)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(KairosBoard.ink)
            let detail = beat.at >= 0 ? beat.detail : KairosPlan.plainDetail(beat.detail)
            if !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 13))
                    .foregroundStyle(KairosBoard.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if beat.at < 0, !beat.tip.isEmpty {
                Text(beat.tip)
                    .font(.system(size: 12))
                    .foregroundStyle(KairosBoard.muted)
                    .lineLimit(6)
            }
            Spacer(minLength: 0)
            KairosMoves(beat: beat)
            HStack(spacing: 12) {
                Button { runner.back() } label: { Image(systemName: "backward.end.fill") }
                    .buttonStyle(KairosRound())
                    .help("Back one")
                Button("Done") { runner.advance() }
                    .buttonStyle(KairosPrimary(height: 44))
                    .keyboardShortcut(.return, modifiers: [])
            }
        }
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
    return KairosEntry(id: KairosEntry.id(routine: live.routine.id, day: state.day, slot: state.slot, step: step.id.uuidString),
                       routine: live.routine.id.uuidString, routineName: live.routine.name, day: state.day, slot: state.slot.rawValue,
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

    private var feelId: String { KairosEntry.id(routine: live.routine.id, day: state.day, slot: state.slot, step: "feel") }

    var body: some View {
        let items = ScheduleStore.shared.items(on: state.day, slot: state.slot, in: [live.routine])
        let ticked = items.filter(\.done).count
        let all = ticked == items.count
        let feel = journal.entry(feelId)?.feel
        let total = Int((state.finished ?? Date()).timeIntervalSince(state.started))
        VStack(spacing: 14) {
            ZStack {
                Circle().fill(all ? KairosBoard.accentStyle : AnyShapeStyle(KairosBoard.line))
                Image(systemName: all ? "checkmark" : "pause")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(all ? KairosLook.onAccent : KairosBoard.ink)
            }
            .frame(width: 64, height: 64)
            .padding(.top, 10)
            Text(all ? "\(live.routine.name) done" : "Stopped early")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(KairosBoard.ink)
            Text("\(KairosSession.title(live.routine, on: state.day)) · \(KairosPlan.minutes(total)) min")
                .font(.system(size: 12))
                .foregroundStyle(KairosBoard.muted)
            HStack(spacing: 10) {
                Image(systemName: "sun.horizon")
                    .foregroundStyle(KairosBoard.accent)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Ticked in Orario")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(KairosBoard.ink)
                    Text("\(ticked) of \(items.count) steps · syncs to every device")
                        .font(.system(size: 11))
                        .foregroundStyle(KairosBoard.muted)
                }
                Spacer()
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12).fill(KairosBoard.column))
            .boardEdge(12)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                        HStack {
                            Image(systemName: item.done ? "checkmark" : "circle")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(item.done ? KairosBoard.accent : KairosBoard.faint)
                                .frame(width: 16)
                            Text(KairosPlan.split(item.step.title).name)
                                .foregroundStyle(item.done ? KairosBoard.ink : KairosBoard.muted)
                            Spacer()
                            if let spent = state.spent[String(index)], spent > 0 {
                                Text(KairosPlan.clock(spent))
                                    .monospacedDigit()
                                    .foregroundStyle(KairosBoard.muted)
                            }
                        }
                        .font(.system(size: 13))
                        .padding(.vertical, 6)
                    }
                }
            }
            .scrollIndicators(.never)
            VStack(alignment: .leading, spacing: 8) {
                KairosLook.kicker("How did it feel?")
                HStack(spacing: 8) {
                    ForEach([("easy", "Easy"), ("right", "Right"), ("too-hard", "Too hard")], id: \.0) { value, label in
                        Button(label) { setFeel(value) }
                            .buttonStyle(KairosChip(on: feel == value))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button("Back to today") { runner.end(reason: "finished") }
                .buttonStyle(KairosPrimary(height: 42))
                .keyboardShortcut(.return, modifiers: [])
        }
        .padding(18)
    }

    private func setFeel(_ value: String) {
        var entry = journal.entry(feelId) ?? KairosEntry(id: feelId, routine: live.routine.id.uuidString, routineName: live.routine.name, day: state.day,
                                                         slot: state.slot.rawValue, step: "feel", title: live.routine.name, tag: "feel")
        entry.feel = value
        journal.put(entry)
    }
}

private struct KairosChip: ButtonStyle {
    let on: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(on ? KairosLook.onAccent : KairosBoard.ink)
            .frame(maxWidth: .infinity)
            .frame(height: 32)
            .background(Capsule().fill(on ? KairosBoard.accentStyle : AnyShapeStyle(KairosBoard.column)))
            .overlay(Capsule().stroke(on ? Color.clear : KairosBoard.line, lineWidth: 1))
            .contentShape(Capsule())
    }
}

private struct KairosJournalView: View {
    @ObservedObject var journal: KairosJournal
    let close: () -> Void
    @State private var query = ""
    @State private var tag = "all"

    private static let tags = [("all", "All"), ("gratitude", "Gratitude"), ("win", "Wins"), ("script", "Scripts"), ("action", "Actions"), ("review", "Reviews"), ("run", "Runs")]

    private var shown: [KairosEntry] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        return journal.sorted.filter { entry in
            guard entry.tag != "feel", !entry.body.isEmpty else { return false }
            if tag != "all" && entry.tag != tag { return false }
            if needle.isEmpty { return true }
            return entry.body.lowercased().contains(needle) || (entry.title ?? "").lowercased().contains(needle)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Button(action: close) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(KairosBoard.muted)
                        .frame(width: 26, height: 26)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                Text("Journal")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(KairosBoard.ink)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 20)
            .padding(.bottom, 10)
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(KairosBoard.muted)
                TextField("Search what you wrote", text: $query)
                    .textFieldStyle(.plain)
            }
            .font(.system(size: 13))
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(Capsule().fill(KairosBoard.column))
            .overlay(Capsule().stroke(KairosBoard.line, lineWidth: 1))
            .padding(.horizontal, 16)
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(Self.tags, id: \.0) { value, label in
                        Button(label) { tag = value }
                            .buttonStyle(KairosChip(on: tag == value))
                            .fixedSize()
                    }
                }
                .padding(.horizontal, 16)
            }
            .scrollIndicators(.never)
            .padding(.vertical, 10)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if shown.isEmpty {
                        Text(journal.entries.isEmpty ? "Nothing written yet. Writing steps in a session land here." : "Nothing matches.")
                            .font(.system(size: 12))
                            .foregroundStyle(KairosBoard.muted)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 30)
                    }
                    ForEach(Array(shown.enumerated()), id: \.element.id) { index, entry in
                        if index == 0 || shown[index - 1].day != entry.day || shown[index - 1].slot != entry.slot {
                            KairosLook.kicker("\(KairosLook.title(entry.day)) · \(entry.slot == "night" ? "Night" : "Morning")")
                                .padding(.top, index == 0 ? 0 : 6)
                        }
                        VStack(alignment: .leading, spacing: 5) {
                            Text((entry.title ?? entry.routineName ?? "").uppercased())
                                .font(.system(size: 10, weight: .semibold))
                                .tracking(0.8)
                                .foregroundStyle(KairosBoard.accentInkStyle)
                            Text(entry.body)
                                .font(.system(size: 13))
                                .foregroundStyle(KairosBoard.ink)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 12).fill(KairosBoard.column))
                        .boardEdge(12)
                    }
                }
                .padding(16)
            }
            .scrollIndicators(.never)
        }
    }
}
