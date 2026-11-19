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
    static let rest = Color(red: 0.396, green: 0.643, blue: 0.522)
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

    static func chip(_ day: String, today: String) -> String {
        if day == today { return "Today" }
        if day == ScheduleDays.shift(today, by: 1) { return "Tomorrow" }
        let number = ScheduleDays.date(day).map { ScheduleDays.calendar.component(.day, from: $0) } ?? 0
        return "\(ScheduleDays.short(ScheduleDays.weekday(day))) \(number)"
    }

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
        let host = NSHostingView(rootView: KairosBoardView(runner: KairosRunner.shared, store: ScheduleStore.shared, journal: KairosJournal.shared))
        host.sizingOptions = []
        window.contentView = host
        window.contentMinSize = NSSize(width: 880, height: 620)
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
    @State private var settings = false
    @State private var day = ""
    @State private var preview: KairosSession?
    @State private var previewStep = 0

    var body: some View {
        HStack(spacing: 0) {
            KairosSidebar(runner: runner, store: store, page: page) { next in
                preview = nil
                page = next
                if next == .today { day = "" }
            }
                .frame(width: 280)
                .background(KairosBoard.sidebar)
            Rectangle().fill(KairosBoard.line).frame(width: 1)
            stage
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if settings {
                Rectangle().fill(KairosBoard.line).frame(width: 1)
                KairosSettings()
                    .frame(width: 260)
                    .background(KairosBoard.sidebar)
                    .transition(.move(edge: .trailing))
            }
        }
        .overlay(alignment: .topTrailing) {
            Button {
                withAnimation(.easeOut(duration: 0.2)) { settings.toggle() }
                note("kairos settings \(settings ? "opened" : "closed")")
            } label: {
                Image(systemName: settings ? "xmark" : "gearshape")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(settings ? KairosBoard.ink : KairosBoard.muted)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(settings ? KairosBoard.column : Color.clear))
                    .overlay(Circle().stroke(KairosBoard.line, lineWidth: 1))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(",", modifiers: .command)
            .help(settings ? "Close settings" : "Settings")
            .padding(.top, 8)
            .padding(.trailing, 12)
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
        } else if let preview {
            KairosPreview(session: preview, step: $previewStep) { self.preview = nil }
                .frame(maxWidth: 640)
                .padding(.horizontal, 24)
                .padding(.top, 28)
                .padding(.bottom, 20)
        } else if page == .journal {
            KairosJournalPage(journal: journal, today: store.today)
                .frame(maxWidth: 900)
                .padding(.horizontal, 28)
                .padding(.top, 40)
                .padding(.bottom, 22)
                .frame(maxWidth: .infinity)
        } else {
            KairosToday(runner: runner, store: store, day: $day) { session in
                previewStep = 0
                preview = session
                note("kairos preview opened routine=\(session.routine.name) day=\(session.day) slot=\(session.slot.rawValue)")
            }
            .frame(maxWidth: 680)
            .padding(.horizontal, 24)
            .padding(.top, 40)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity)
            .kairosFill()
        }
    }
}

private struct KairosSidebar: View {
    @ObservedObject var runner: KairosRunner
    @ObservedObject var store: ScheduleStore
    let page: KairosPage
    let go: (KairosPage) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: 44)
            if runner.state == nil {
                VStack(spacing: 2) {
                    nav("sun.horizon", "Routine", .today)
                    nav("book.closed", "Journal", .journal)
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 12)
                Rectangle().fill(KairosBoard.line).frame(height: 1)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if let state = runner.state, let live = runner.live {
                        steps(live, state)
                    } else {
                        stats
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
            }
            .scrollIndicators(.never)
        }
    }

    private func nav(_ symbol: String, _ title: String, _ target: KairosPage) -> some View {
        let on = page == target
        return Button { go(target) } label: {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 18)
                Text(title)
                    .font(.system(size: 13, weight: on ? .semibold : .medium))
                Spacer(minLength: 0)
            }
            .foregroundStyle(on ? KairosBoard.accentInk : KairosBoard.muted)
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(RoundedRectangle(cornerRadius: 9).fill(on ? KairosBoard.accent.opacity(0.14) : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var stats: some View {
        let list = KairosStats.all()
        return VStack(alignment: .leading, spacing: 10) {
            KairosLook.kicker("Your routines")
                .padding(.horizontal, 4)
            if list.isEmpty {
                Text("Timed routines from Orario show up here once they exist.")
                    .font(.system(size: 12))
                    .foregroundStyle(KairosBoard.muted)
                    .padding(.horizontal, 4)
            }
            ForEach(list) { item in
                VStack(alignment: .leading, spacing: 10) {
                    Text(item.routine.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(KairosBoard.ink)
                        .lineLimit(2)
                    if item.routine.starts > store.today {
                        Text("Starts \(KairosLook.title(item.routine.starts))")
                            .font(.system(size: 12))
                            .foregroundStyle(KairosBoard.muted)
                    } else {
                        HStack(alignment: .firstTextBaseline, spacing: 0) {
                            figure("\(item.done)", item.done == 1 ? "day done" : "days done", accent: true)
                            figure("\(item.streak)", "streak", accent: false)
                            figure("\(item.skipped)", "skipped", accent: false)
                        }
                        Text(footer(item))
                            .font(.system(size: 11))
                            .foregroundStyle(KairosBoard.muted)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12).fill(KairosBoard.column))
                .boardEdge(12)
            }
        }
    }

    private func footer(_ item: KairosStats) -> String {
        var parts = ["Since \(KairosLook.short(item.routine.starts))"]
        if let ends = item.routine.ends { parts.append(ends < store.today ? "ended \(KairosLook.short(ends))" : "until \(KairosLook.short(ends))") }
        if item.best > item.streak { parts.append("best streak \(item.best)") }
        return parts.joined(separator: " · ")
    }

    private func figure(_ value: String, _ caption: String, accent: Bool) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.system(size: 22, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(accent ? AnyShapeStyle(KairosBoard.accentInk) : AnyShapeStyle(KairosBoard.ink))
            Text(caption)
                .font(.system(size: 11))
                .foregroundStyle(KairosBoard.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
        .padding(.horizontal, 18)
        .padding(.top, 40)
        .padding(.bottom, 18)
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

private struct KairosToday: View {
    @ObservedObject var runner: KairosRunner
    @ObservedObject var store: ScheduleStore
    @Binding var day: String
    let preview: (KairosSession) -> Void
    @State private var calendar = false

    var body: some View {
        let today = store.today
        let shown = day.isEmpty ? today : day
        let isToday = shown == today
        let list = KairosSession.all(on: shown)
        let open = list.filter { !$0.finished }
        let next = isToday ? (open.first { $0.slot == store.slotNow } ?? open.first) : nil
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                KairosLook.kicker(isToday ? "Routine" : shown > today ? "Coming up" : "Looking back")
                Text(KairosLook.title(shown))
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(KairosBoard.ink)
                Text(summary(list, isToday: isToday))
                    .font(.system(size: 13))
                    .foregroundStyle(KairosBoard.muted)
            }
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(0..<7, id: \.self) { offset in
                        let key = ScheduleDays.shift(today, by: offset)
                        Button(KairosLook.chip(key, today: today)) { day = offset == 0 ? "" : key }
                            .buttonStyle(KairosChip(on: key == shown, fill: false))
                            .fixedSize()
                    }
                    let inStrip = shown >= today && shown <= ScheduleDays.shift(today, by: 6)
                    Button {
                        calendar = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "calendar")
                            if !inStrip { Text(KairosLook.short(shown)) }
                        }
                    }
                    .buttonStyle(KairosChip(on: !inStrip, fill: false))
                    .fixedSize()
                    .help("Pick any date")
                    .popover(isPresented: $calendar, arrowEdge: .bottom) {
                        DatePicker("", selection: Binding(
                            get: { ScheduleDays.date(shown) ?? Date() },
                            set: { picked in
                                let key = ScheduleDays.key(picked)
                                day = key == today ? "" : key
                                calendar = false
                            }), displayedComponents: .date)
                            .datePickerStyle(.graphical)
                            .labelsHidden()
                            .padding(12)
                    }
                }
            }
            .scrollIndicators(.never)
            if list.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "figure.mind.and.body")
                        .font(.system(size: 30, weight: .light))
                        .foregroundStyle(KairosBoard.faint)
                    Text(isToday ? "Nothing to run today" : "Nothing guided that day")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(KairosBoard.ink)
                    Text("Timed routines from Orario show up here on the days they run.")
                        .font(.system(size: 12))
                        .foregroundStyle(KairosBoard.muted)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
            }
            ForEach(ScheduleSlot.allCases) { slot in
                let group = list.filter { $0.slot == slot }
                if !group.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        KairosLook.kicker(slot == .morning ? "Morning" : "Tonight · from \(KairosLook.hour(store.book.nightFrom))")
                        ForEach(group) { session in
                            KairosSessionCard(session: session, canStart: isToday, expanded: session.id == next?.id,
                                              start: { runner.start(session) }, preview: { preview(session) })
                        }
                    }
                }
            }
        }
    }

    private func summary(_ list: [KairosSession], isToday: Bool) -> String {
        guard !list.isEmpty else { return isToday ? "A rest day" : "A rest day, nothing guided" }
        let minutes = KairosPlan.minutes(list.reduce(0) { $0 + $1.seconds })
        let count = "\(list.count) session\(list.count == 1 ? "" : "s") · about \(minutes) min"
        guard isToday else { return count + " · preview any of them; nothing is ticked" }
        let done = list.filter(\.finished).count
        return done == list.count ? "All done for today" : done > 0 ? "\(done) of \(list.count) done · " + count : count
    }
}

private struct KairosSessionCard: View {
    let session: KairosSession
    let canStart: Bool
    let expanded: Bool
    let start: () -> Void
    let preview: () -> Void
    @State private var hover = false

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
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 14) {
                ZStack {
                    Circle().strokeBorder(session.finished ? Color.clear : KairosBoard.faint, lineWidth: 1.5)
                    if session.finished {
                        Circle().fill(KairosBoard.accentStyle)
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundStyle(KairosLook.onAccent)
                    }
                }
                .frame(width: 24, height: 24)
                VStack(alignment: .leading, spacing: 3) {
                    Text(KairosSession.dayNumber(session.routine, on: session.day).map { "\(session.routine.name) · Day \($0.n) of \($0.of)" } ?? session.routine.name)
                        .font(.system(size: expanded ? 20 : 16, weight: .semibold))
                        .strikethrough(session.finished)
                        .foregroundStyle(KairosBoard.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(summary)
                        .font(.system(size: 12))
                        .foregroundStyle(KairosBoard.muted)
                }
                Spacer(minLength: 8)
                Button(session.finished ? "Look back" : "Preview", action: preview)
                    .buttonStyle(KairosGhost(height: 32))
                    .fixedSize()
                    .help("Walk through the steps without a timer; nothing is ticked")
                if canStart && !session.finished {
                    Button(session.done > 0 ? "Continue" : "Start now", action: start)
                        .buttonStyle(KairosPrimary(height: 32))
                        .fixedSize()
                        .keyboardShortcut(expanded ? KeyboardShortcut(.return, modifiers: []) : nil)
                }
            }
            if expanded {
                KairosStepList(steps: session.steps)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(KairosBoard.column))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(expanded ? KairosBoard.accent.opacity(0.5) : hover ? KairosBoard.faint : Color.clear, lineWidth: 1))
        .boardEdge(16)
        .opacity(session.finished ? 0.55 : 1)
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .onTapGesture(perform: preview)
        .onHover { hover = $0 }
    }
}

private struct KairosStepList: View {
    let steps: [ScheduleStep]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("\(index + 1)")
                        .font(.system(size: 12, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(KairosBoard.faint)
                        .frame(width: 16, alignment: .trailing)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ScheduleStepText.plain(step.title))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(KairosBoard.ink)
                        Text(KairosPlan.howLabel(step))
                            .font(.system(size: 12))
                            .foregroundStyle(KairosBoard.muted)
                    }
                    Spacer()
                }
                .padding(.vertical, 7)
                .overlay(alignment: .top) { Rectangle().fill(KairosBoard.line).frame(height: 1) }
            }
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

private struct KairosFill: ViewModifier {
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
    fileprivate func kairosFill() -> some View { modifier(KairosFill()) }
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

    private var read: String? {
        guard !beat.reads.isEmpty else { return nil }
        let elapsed = max(0, Double(beat.seconds) - runner.remaining)
        return beat.reads[(Int(elapsed) / max(1, beat.every)) % beat.reads.count]
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
            if let read {
                VStack(alignment: .leading, spacing: 6) {
                    KairosLook.kicker("Hard to picture? Read this, then close your eyes")
                    Text(read)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(KairosBoard.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 12).fill(KairosBoard.column))
                .boardEdge(12)
            }
            if beat.box.isEmpty {
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
            } else {
                KairosBox(beat: beat, state: state)
                    .frame(width: 240, height: 240)
                    .frame(maxWidth: .infinity)
                Text(state.paused ? "\(KairosPlan.clock(left)) left · paused" : "\(KairosPlan.clock(left)) left")
                    .font(.system(size: 13))
                    .monospacedDigit()
                    .foregroundStyle(KairosBoard.muted)
                    .frame(maxWidth: .infinity)
            }
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

private enum KairosShelf {
    struct Kind {
        let tag: String
        let name: String
        let line: String
        let cover: Color
    }

    static let ink = Color(red: 0.23, green: 0.16, blue: 0.13)

    static let kinds: [Kind] = [
        Kind(tag: "gratitude", name: "Gratitude", line: "good things", cover: Color(red: 0.957, green: 0.788, blue: 0.659)),
        Kind(tag: "win", name: "Wins", line: "what went right", cover: Color(red: 0.949, green: 0.863, blue: 0.604)),
        Kind(tag: "script", name: "Scripts", line: "as if it's done", cover: Color(red: 0.839, green: 0.784, blue: 0.925)),
        Kind(tag: "action", name: "Actions", line: "one step for today", cover: Color(red: 0.769, green: 0.863, blue: 0.769)),
        Kind(tag: "review", name: "Reviews", line: "looking back", cover: Color(red: 0.737, green: 0.839, blue: 0.902)),
        Kind(tag: "run", name: "Runs", line: "time, distance, pace", cover: Color(red: 0.925, green: 0.753, blue: 0.784)),
        Kind(tag: "note", name: "Notes", line: "everything else", cover: Color(red: 0.890, green: 0.835, blue: 0.784))
    ]

    static let covers: [Color] = [
        Color(red: 0.910, green: 0.706, blue: 0.561), Color(red: 0.851, green: 0.761, blue: 0.682),
        Color(red: 0.788, green: 0.824, blue: 0.722), Color(red: 0.776, green: 0.784, blue: 0.890)
    ]

    static func kind(_ tag: String?) -> Kind {
        kinds.first { $0.tag == (tag ?? "note") } ?? kinds[kinds.count - 1]
    }

    static func pages(_ count: Int) -> String { "\(count) page\(count == 1 ? "" : "s")" }
}

private struct KairosLeaf {
    let day: String
    let kicker: String
    let title: String?
    let blocks: [(label: String?, text: String)]
    let entry: KairosEntry?
}

private struct KairosBookCover: View {
    let title: String
    let line: String
    let meta: String
    let cover: Color
    var width: CGFloat = 150
    var height: CGFloat = 200
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold, design: .serif))
                Text(line)
                    .font(.system(size: 11))
                    .opacity(0.8)
                Spacer(minLength: 0)
                Text(meta)
                    .font(.system(size: 11))
                    .opacity(0.8)
            }
            .foregroundStyle(KairosShelf.ink)
            .padding(.leading, 24)
            .padding(.trailing, 14)
            .padding(.vertical, 16)
            .frame(width: width, height: height, alignment: .topLeading)
            .background(
                UnevenRoundedRectangle(topLeadingRadius: 5, bottomLeadingRadius: 5, bottomTrailingRadius: 12, topTrailingRadius: 12)
                    .fill(cover)
                    .overlay(alignment: .leading) { Rectangle().fill(Color.black.opacity(0.08)).frame(width: 9) }
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 5, bottomLeadingRadius: 5, bottomTrailingRadius: 12, topTrailingRadius: 12))
                    .shadow(color: Color.black.opacity(0.16), radius: 7, y: 5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Open \(title)")
    }
}

private struct KairosShelfPlank: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(KairosBoard.line)
            .frame(height: 12)
            .shadow(color: Color.black.opacity(0.1), radius: 3, y: 3)
    }
}

private struct KairosToggle: View {
    @Binding var manual: Bool

    var body: some View {
        HStack(spacing: 2) {
            option("Dailies", on: !manual) { manual = false }
            option("Manual", on: manual) { manual = true }
        }
        .padding(3)
        .background(Capsule().fill(KairosBoard.line.opacity(0.6)))
    }

    private func option(_ title: String, on: Bool, _ pick: @escaping () -> Void) -> some View {
        Button(action: pick) {
            Text(title)
                .font(.system(size: 12, weight: on ? .semibold : .medium))
                .foregroundStyle(on ? KairosBoard.ink : KairosBoard.muted)
                .padding(.horizontal, 16)
                .frame(height: 28)
                .background(Capsule().fill(on ? KairosBoard.column : Color.clear))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct KairosJournalPage: View {
    @ObservedObject var journal: KairosJournal
    let today: String
    @State private var manual = false
    @State private var dailyBook: String?
    @State private var book: String?
    @State private var editing: KairosEntry?
    @State private var template: KairosEntry?
    @State private var composing = false

    var body: some View {
        if let editing {
            KairosEntryEditor(journal: journal, entry: editing) { self.editing = nil }
                .id(editing.id)
        } else if let template {
            KairosTemplateEditor(journal: journal, entry: template) { self.template = nil }
                .id(template.id)
        } else if composing {
            KairosNewEntry(journal: journal, today: today) { saved in
                composing = false
                if let saved { book = journal.book(saved) }
            }
        } else if !manual, let tag = dailyBook {
            let kind = KairosShelf.kind(tag)
            KairosBookView(title: kind.name, leaves: dailyLeaves(tag), empty: "No pages yet.", back: { dailyBook = nil }, write: nil, edit: nil)
                .id("daily-\(tag)")
        } else if manual, let name = book {
            KairosBookView(title: name, leaves: manualLeaves(name), empty: "No entries in this book yet.",
                           back: { book = nil }, write: { composing = true }, edit: { editing = $0 })
                .id("book-\(name)-\(journal.manual.count)")
        } else {
            shelf.kairosFill()
        }
    }

    private var daily: [KairosEntry] {
        journal.entries.filter { KairosJournal.isDaily($0) && !$0.body.isEmpty }
    }

    private func dailyLeaves(_ tag: String) -> [KairosLeaf] {
        let mine = daily.filter { KairosShelf.kind($0.tag).tag == tag }
        let days = Array(Set(mine.map(\.day))).sorted()
        return days.map { day in
            let found = mine.filter { $0.day == day }.sorted { $0.slot == "morning" && $1.slot != "morning" }
            let blocks = found.map { entry -> (label: String?, text: String) in
                (found.count > 1 ? (entry.slot == "night" ? "Night" : "Morning") : nil, entry.body)
            }
            let slot = found.count == 1 ? (found[0].slot == "night" ? " · night" : found[0].slot == "morning" ? " · morning" : "") : ""
            return KairosLeaf(day: day, kicker: KairosLook.title(day) + slot, title: nil, blocks: blocks, entry: nil)
        }
    }

    private func manualLeaves(_ name: String) -> [KairosLeaf] {
        journal.manual.filter { journal.book($0) == name }.reversed().map { entry in
            var blocks: [(label: String?, text: String)] = []
            if let prompts = entry.prompts, !prompts.isEmpty {
                let lines = entry.lines ?? []
                for (index, prompt) in prompts.enumerated() {
                    let answer = index < lines.count ? lines[index].trimmingCharacters(in: .whitespacesAndNewlines) : ""
                    if !answer.isEmpty { blocks.append((label: prompt, text: answer)) }
                }
            } else if let text = entry.text, !text.isEmpty {
                blocks.append((label: nil, text: text))
            }
            let title = entry.title == name ? nil : entry.title
            return KairosLeaf(day: entry.day, kicker: KairosLook.title(entry.day), title: title, blocks: blocks, entry: entry)
        }
    }

    private var shelf: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    KairosLook.kicker("Journal")
                    Text(manual ? "Manual" : "Dailies")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(KairosBoard.ink)
                    Text(manual ? "Entries you write whenever you like, one book for each template" : "What your routines wrote, one book for each kind, one page for each day")
                        .font(.system(size: 13))
                        .foregroundStyle(KairosBoard.muted)
                }
                Spacer()
                if manual {
                    Button("New entry") { composing = true }
                        .buttonStyle(KairosPrimary(height: 34))
                        .fixedSize()
                        .keyboardShortcut("n", modifiers: .command)
                }
                KairosToggle(manual: $manual)
            }
            .padding(.trailing, 34)
            if manual { months } else { dailies }
        }
    }

    private var dailies: some View {
        let entries = daily
        let present = KairosShelf.kinds.filter { kind in entries.contains { KairosShelf.kind($0.tag).tag == kind.tag } }
        return VStack(alignment: .leading, spacing: 0) {
            if present.isEmpty {
                Text("Nothing written yet. Writing steps in a session land here, one book for each kind.")
                    .font(.system(size: 12))
                    .foregroundStyle(KairosBoard.muted)
                    .padding(.vertical, 30)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 150), spacing: 24, alignment: .leading)], alignment: .leading, spacing: 30) {
                    ForEach(present, id: \.tag) { kind in
                        let mine = entries.filter { KairosShelf.kind($0.tag).tag == kind.tag }
                        let days = Set(mine.map(\.day))
                        let last = days.max().map { " · last \(KairosLook.short($0))" } ?? ""
                        KairosBookCover(title: kind.name, line: kind.line, meta: KairosShelf.pages(days.count) + last, cover: kind.cover) {
                            dailyBook = kind.tag
                            note("kairos journal book opened kind=\(kind.tag) pages=\(days.count)")
                        }
                    }
                }
                .padding(.top, 6)
                KairosShelfPlank()
                    .padding(.top, 6)
                Text("Click a book to open it. A book shows up once it has a page.")
                    .font(.system(size: 12))
                    .foregroundStyle(KairosBoard.muted)
                    .padding(.top, 14)
            }
        }
    }

    private var months: some View {
        let newest = Dictionary(journal.manual.map { (journal.book($0), $0.day) }, uniquingKeysWith: { max($0, $1) })
        let list = newest.keys.sorted { a, b in newest[a]! != newest[b]! ? newest[a]! > newest[b]! : a < b }
        return VStack(alignment: .leading, spacing: 0) {
            if list.isEmpty {
                Text("No entries yet. Each template gets its own book once you write in it.")
                    .font(.system(size: 12))
                    .foregroundStyle(KairosBoard.muted)
                    .padding(.vertical, 30)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 170, maximum: 170), spacing: 24, alignment: .leading)], alignment: .leading, spacing: 30) {
                    ForEach(Array(list.enumerated()), id: \.element) { index, name in
                        let count = journal.manual.filter { journal.book($0) == name }.count
                        KairosBookCover(title: name, line: "\(count) entr\(count == 1 ? "y" : "ies")", meta: "last \(KairosLook.short(newest[name] ?? today))",
                                        cover: KairosShelf.covers[index % KairosShelf.covers.count], width: 170, height: 220) {
                            book = name
                            note("kairos journal book opened template=\(name) entries=\(count)")
                        }
                    }
                }
                .padding(.top, 6)
                KairosShelfPlank()
                    .padding(.top, 6)
            }
            HStack {
                KairosLook.kicker("Templates")
                Spacer()
                Button("New template") { template = KairosJournal.fresh("template", title: "", prompts: [], day: today) }
                    .buttonStyle(KairosGhost(height: 28))
            }
            .padding(.top, 26)
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    if journal.templates.isEmpty {
                        Text("No templates yet. A template is a name and a few prompts.")
                            .font(.system(size: 12))
                            .foregroundStyle(KairosBoard.muted)
                    }
                    ForEach(journal.templates) { item in
                        let count = item.lines?.count ?? 0
                        Button("\(item.title ?? "Untitled") · \(count == 0 ? "blank page" : "\(count) prompt\(count == 1 ? "" : "s")")") { template = item }
                            .buttonStyle(KairosChip(on: false, fill: false))
                            .fixedSize()
                            .help("Edit this template")
                    }
                }
            }
            .scrollIndicators(.never)
            .padding(.top, 10)
        }
    }
}

private struct KairosBookView: View {
    let title: String
    let leaves: [KairosLeaf]
    let empty: String
    let back: () -> Void
    let write: (() -> Void)?
    let edit: ((KairosEntry) -> Void)?
    @State private var index: Int
    @State private var picking = false

    init(title: String, leaves: [KairosLeaf], empty: String, back: @escaping () -> Void, write: (() -> Void)?, edit: ((KairosEntry) -> Void)?) {
        self.title = title
        self.leaves = leaves
        self.empty = empty
        self.back = back
        self.write = write
        self.edit = edit
        let last = max(0, leaves.count - 1)
        _index = State(initialValue: last - last % 2)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Button(action: back) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Shelf")
                    }
                }
                .buttonStyle(KairosGhost(height: 30))
                .keyboardShortcut(.cancelAction)
                Text(title)
                    .font(.system(size: 24, weight: .semibold, design: .serif))
                    .foregroundStyle(KairosBoard.ink)
                Spacer()
                Button {
                    picking = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "calendar")
                        Text("Go to date")
                    }
                }
                .buttonStyle(KairosGhost(height: 30))
                .disabled(leaves.isEmpty)
                .popover(isPresented: $picking, arrowEdge: .bottom) {
                    DatePicker("", selection: Binding(get: { ScheduleDays.date(leaves.indices.contains(index) ? leaves[index].day : "") ?? Date() },
                                                      set: { go(to: ScheduleDays.key($0)) }),
                               displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .labelsHidden()
                        .padding(12)
                }
                if let write {
                    Button("New entry", action: write)
                        .buttonStyle(KairosPrimary(height: 30))
                        .fixedSize()
                }
            }
            .padding(.trailing, 34)
            if leaves.isEmpty {
                Text(empty)
                    .font(.system(size: 13))
                    .foregroundStyle(KairosBoard.muted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 14) {
                    arrow("chevron.left", enabled: index > 0, key: .leftArrow) { index = max(0, index - 2) }
                    HStack(spacing: 0) {
                        page(index, leading: true)
                        Rectangle().fill(KairosBoard.line).frame(width: 1)
                        page(index + 1, leading: false)
                    }
                    .background(RoundedRectangle(cornerRadius: 6).fill(KairosBoard.column))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(KairosBoard.line, lineWidth: 1))
                    .shadow(color: Color.black.opacity(0.14), radius: 12, y: 8)
                    arrow("chevron.right", enabled: index + 2 < leaves.count, key: .rightArrow) { index = min(index + 2, leaves.count - 1 - (leaves.count - 1) % 2) }
                }
                Text(footer)
                    .font(.system(size: 12))
                    .foregroundStyle(KairosBoard.muted)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var footer: String {
        let first = index + 1
        let second = min(index + 2, leaves.count)
        let pages = first == second ? "Page \(first) of \(leaves.count)" : "Pages \(first) and \(second) of \(leaves.count)"
        return pages + " · ← → to flip"
    }

    private func go(to day: String) {
        picking = false
        let at = leaves.lastIndex { $0.day <= day } ?? 0
        index = at - at % 2
        note("kairos journal went to date=\(day) page=\(at + 1) of=\(leaves.count)")
    }

    private func arrow(_ symbol: String, enabled: Bool, key: KeyEquivalent, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(KairosBoard.ink)
                .frame(width: 40, height: 40)
                .background(Circle().fill(KairosBoard.column))
                .overlay(Circle().stroke(KairosBoard.line, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(key, modifiers: [])
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
    }

    @ViewBuilder private func page(_ at: Int, leading: Bool) -> some View {
        if leaves.indices.contains(at) {
            let leaf = leaves[at]
            VStack(alignment: .leading, spacing: 12) {
                KairosLook.kicker(leaf.kicker)
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if let title = leaf.title {
                            Text(title)
                                .font(.system(size: 17, weight: .semibold, design: .serif))
                                .foregroundStyle(KairosBoard.ink)
                        }
                        ForEach(Array(leaf.blocks.enumerated()), id: \.offset) { _, block in
                            VStack(alignment: .leading, spacing: 4) {
                                if let label = block.label {
                                    Text(label)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(KairosBoard.ink)
                                }
                                Text(block.text)
                                    .font(.system(size: 14, design: .serif))
                                    .lineSpacing(5)
                                    .foregroundStyle(KairosBoard.ink)
                                    .textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        if leaf.blocks.isEmpty {
                            Text("Empty page")
                                .font(.system(size: 13, design: .serif))
                                .foregroundStyle(KairosBoard.muted)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.never)
                HStack {
                    if let entry = leaf.entry, let edit {
                        Button("Edit") { edit(entry) }
                            .buttonStyle(KairosGhost(height: 26))
                    }
                    Spacer()
                    Text("\(at + 1)")
                        .font(.system(size: 11))
                        .foregroundStyle(KairosBoard.muted)
                    Spacer()
                    if leaf.entry != nil && edit != nil { Color.clear.frame(width: 50, height: 1) }
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(LinearGradient(colors: [Color.black.opacity(leading ? 0 : 0.05), Color.clear, Color.black.opacity(leading ? 0.05 : 0)],
                                       startPoint: .leading, endPoint: .trailing))
        } else {
            Text("The rest of this book is blank")
                .font(.system(size: 13, design: .serif))
                .foregroundStyle(KairosBoard.faint)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct KairosNewEntry: View {
    @ObservedObject var journal: KairosJournal
    let today: String
    let done: (KairosEntry?) -> Void
    @State private var chosen: KairosEntry?
    @State private var title = ""
    @State private var answers: [String] = []
    @State private var text = ""

    private var prompts: [String] { chosen?.lines ?? [] }

    var body: some View {
        HStack(alignment: .top, spacing: 22) {
            VStack(alignment: .leading, spacing: 8) {
                KairosLook.kicker("Template")
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        option(nil)
                        ForEach(journal.templates) { option($0) }
                    }
                }
                .scrollIndicators(.never)
                Text("Edit templates from the Manual shelf.")
                    .font(.system(size: 11))
                    .foregroundStyle(KairosBoard.muted)
            }
            .frame(width: 220)
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Text("\(KairosLook.title(today)) · goes into the \(chosen?.title ?? KairosJournal.blankBook) book")
                        .font(.system(size: 12))
                        .foregroundStyle(KairosBoard.muted)
                    Spacer()
                    Button("Cancel") { done(nil) }
                        .buttonStyle(KairosGhost(height: 30))
                        .keyboardShortcut(.cancelAction)
                    Button("Save") { save() }
                        .buttonStyle(KairosPrimary(height: 30))
                        .fixedSize()
                        .keyboardShortcut("s", modifiers: .command)
                }
                .padding(.trailing, 34)
                TextField("Title", text: $title)
                    .textFieldStyle(.plain)
                    .font(.system(size: 26, weight: .semibold, design: .serif))
                    .foregroundStyle(KairosBoard.ink)
                if prompts.isEmpty {
                    editor($text)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            ForEach(Array(prompts.enumerated()), id: \.offset) { index, prompt in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(prompt)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(KairosBoard.ink)
                                    editor(answer(index))
                                        .frame(height: 100)
                                }
                            }
                        }
                    }
                    .scrollIndicators(.automatic)
                }
                Text("⌘S saves · Esc cancels")
                    .font(.system(size: 11))
                    .foregroundStyle(KairosBoard.muted)
            }
        }
    }

    private func answer(_ index: Int) -> Binding<String> {
        Binding(get: { index < answers.count ? answers[index] : "" },
                set: { value in
                    if answers.count <= index { answers += Array(repeating: "", count: index + 1 - answers.count) }
                    answers[index] = value
                })
    }

    private func option(_ item: KairosEntry?) -> some View {
        let on = chosen?.id == item?.id
        let count = item?.lines?.count ?? 0
        return Button {
            chosen = item
            title = item?.title ?? ""
            answers = Array(repeating: "", count: item?.lines?.count ?? 0)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(item?.title ?? "Blank page")
                    .font(.system(size: 13, weight: on ? .semibold : .medium))
                    .foregroundStyle(KairosBoard.ink)
                Text(count == 0 ? "blank page" : "\(count) prompt\(count == 1 ? "" : "s")")
                    .font(.system(size: 11))
                    .foregroundStyle(KairosBoard.muted)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(on ? KairosBoard.accent.opacity(0.16) : KairosBoard.column))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(on ? KairosBoard.accent.opacity(0.5) : KairosBoard.line, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private func editor(_ value: Binding<String>) -> some View {
        TextEditor(text: value)
            .font(.system(size: 14))
            .foregroundStyle(KairosBoard.ink)
            .scrollContentBackground(.hidden)
            .lineSpacing(4)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 12).fill(KairosBoard.column))
            .boardEdge(12)
    }

    private func save() {
        let blank = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && answers.allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !blank else { return done(nil) }
        let name = title.trimmingCharacters(in: .whitespaces)
        var entry = KairosJournal.fresh("manual", title: name.isEmpty ? (chosen?.title ?? "Untitled") : name, prompts: prompts, day: today)
        if prompts.isEmpty { entry.text = text } else { entry.lines = answers }
        entry.routineName = chosen?.title ?? KairosJournal.blankBook
        journal.put(entry)
        note("kairos manual entry saved id=\(entry.id) template=\(chosen?.title ?? "blank") prompts=\(prompts.count) chars=\(entry.body.count)")
        done(entry)
    }
}

private struct KairosEntryEditor: View {
    @ObservedObject var journal: KairosJournal
    let entry: KairosEntry
    let close: () -> Void
    @State private var title: String
    @State private var answers: [String]
    @State private var text: String

    init(journal: KairosJournal, entry: KairosEntry, close: @escaping () -> Void) {
        self.journal = journal
        self.entry = entry
        self.close = close
        let prompts = entry.prompts ?? []
        var lines = entry.lines ?? []
        if lines.count < prompts.count { lines += Array(repeating: "", count: prompts.count - lines.count) }
        _title = State(initialValue: entry.title ?? "")
        _answers = State(initialValue: lines)
        _text = State(initialValue: entry.text ?? "")
    }

    private var prompts: [String] { entry.prompts ?? [] }

    private var empty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && answers.allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Text(KairosLook.title(entry.day))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(KairosBoard.muted)
                Spacer()
                Button("Cancel", action: close)
                    .buttonStyle(KairosGhost(height: 30))
                    .keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .buttonStyle(KairosPrimary(height: 30))
                    .fixedSize()
                    .keyboardShortcut("s", modifiers: .command)
            }
            TextField("Title", text: $title)
                .textFieldStyle(.plain)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(KairosBoard.ink)
            if prompts.isEmpty {
                field($text)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(Array(prompts.enumerated()), id: \.offset) { index, prompt in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(prompt)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(KairosBoard.ink)
                                field($answers[index])
                                    .frame(height: 110)
                            }
                        }
                    }
                }
                .scrollIndicators(.automatic)
            }
        }
    }

    private func field(_ value: Binding<String>) -> some View {
        TextEditor(text: value)
            .font(.system(size: 14))
            .foregroundStyle(KairosBoard.ink)
            .scrollContentBackground(.hidden)
            .lineSpacing(4)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 12).fill(KairosBoard.column))
            .boardEdge(12)
    }

    private func save() {
        guard !empty || journal.entry(entry.id) != nil else { return close() }
        var next = entry
        let name = title.trimmingCharacters(in: .whitespaces)
        next.title = name.isEmpty ? "Untitled" : name
        if prompts.isEmpty { next.text = text } else { next.lines = answers }
        journal.put(next)
        note("kairos manual entry saved id=\(next.id) title=\(next.title ?? "") prompts=\(prompts.count) chars=\(next.body.count)")
        close()
    }
}

private struct KairosTemplateEditor: View {
    @ObservedObject var journal: KairosJournal
    let entry: KairosEntry
    let close: () -> Void
    @State private var name: String
    @State private var prompts: String

    init(journal: KairosJournal, entry: KairosEntry, close: @escaping () -> Void) {
        self.journal = journal
        self.entry = entry
        self.close = close
        _name = State(initialValue: entry.title ?? "")
        _prompts = State(initialValue: (entry.lines ?? []).joined(separator: "\n"))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Text(journal.entry(entry.id) == nil ? "New template" : "Edit template")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(KairosBoard.muted)
                Spacer()
                Button("Cancel", action: close)
                    .buttonStyle(KairosGhost(height: 30))
                    .keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .buttonStyle(KairosPrimary(height: 30))
                    .fixedSize()
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            TextField("Template name", text: $name)
                .textFieldStyle(.plain)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(KairosBoard.ink)
            Text("One prompt per line. Leave it empty for a blank page.")
                .font(.system(size: 12))
                .foregroundStyle(KairosBoard.muted)
            TextEditor(text: $prompts)
                .font(.system(size: 14))
                .foregroundStyle(KairosBoard.ink)
                .scrollContentBackground(.hidden)
                .lineSpacing(6)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 12).fill(KairosBoard.column))
                .boardEdge(12)
        }
    }

    private func save() {
        var next = entry
        next.title = name.trimmingCharacters(in: .whitespaces)
        next.lines = prompts.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        journal.put(next)
        note("kairos template saved id=\(next.id) name=\(next.title ?? "") prompts=\(next.lines?.count ?? 0)")
        close()
    }
}
