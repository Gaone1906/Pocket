import Combine
import AppKit
import SwiftUI
import UserNotifications

enum PomodoroPhase {
    case focus, rest, long

    var label: String {
        switch self {
        case .focus: return "Focus"
        case .rest: return "Break"
        case .long: return "Long break"
        }
    }
}

enum PomodoroState {
    case idle
    case running(PomodoroPhase, Date)
    case paused(PomodoroPhase, TimeInterval)
}

enum PomodoroPalette {
    static let silver = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0xC9 / 255, green: 0xCC / 255, blue: 0xD1 / 255, alpha: 1)
            : NSColor(srgbRed: 0x7D / 255, green: 0x80 / 255, blue: 0x85 / 255, alpha: 1)
    }

    static func color(for phase: PomodoroPhase) -> NSColor {
        phase == .focus ? AppThemeStore.shared.iconTint(for: "pomodoro") ?? .labelColor : silver
    }
}

struct PomodoroPlan: Equatable {
    var focus: Int?
    var rest: Int?
    var long: Int?

    var isEmpty: Bool { focus == nil && rest == nil && long == nil }
}

final class PomodoroModel: ObservableObject {
    @Published var state: PomodoroState = .idle
    @Published var tick = Date()
    @Published var project: String?
    @Published var cycle = 0
    @Published var plan: PomodoroPlan?
    @Published var hold = false
    @Published var waiting = false
    @Published var focusMinutes: Int {
        didSet {
            UserDefaults.standard.set(focusMinutes, forKey: "pomodoro.focus")
            note("pomodoro setting focus=\(focusMinutes)m")
        }
    }
    @Published var breakMinutes: Int {
        didSet {
            UserDefaults.standard.set(breakMinutes, forKey: "pomodoro.break")
            note("pomodoro setting break=\(breakMinutes)m")
        }
    }

    @Published var longBreakMinutes: Int {
        didSet {
            UserDefaults.standard.set(longBreakMinutes, forKey: "pomodoro.long")
            note("pomodoro setting long=\(longBreakMinutes)m")
        }
    }
    @Published var longEvery: Int {
        didSet {
            UserDefaults.standard.set(longEvery, forKey: "pomodoro.longEvery")
            note("pomodoro setting longEvery=\(longEvery)")
        }
    }
    @Published var streak: Int {
        didSet { UserDefaults.standard.set(streak, forKey: "pomodoro.streak") }
    }

    init() {
        let defaults = UserDefaults.standard
        let focus = defaults.integer(forKey: "pomodoro.focus")
        let rest = defaults.integer(forKey: "pomodoro.break")
        let long = defaults.integer(forKey: "pomodoro.long")
        let every = defaults.integer(forKey: "pomodoro.longEvery")
        focusMinutes = (1...120).contains(focus) ? focus : 25
        breakMinutes = (1...60).contains(rest) ? rest : 5
        longBreakMinutes = (1...90).contains(long) ? long : 15
        longEvery = (2...12).contains(every) ? every : 4
        streak = max(0, defaults.integer(forKey: "pomodoro.streak"))
    }

    func minutes(for phase: PomodoroPhase) -> Int {
        switch phase {
        case .focus: return plan?.focus ?? focusMinutes
        case .rest: return plan?.rest ?? breakMinutes
        case .long: return plan?.long ?? plan?.rest ?? longBreakMinutes
        }
    }
    func seconds(for phase: PomodoroPhase) -> TimeInterval { TimeInterval(minutes(for: phase) * 60) }

    var phase: PomodoroPhase {
        switch state {
        case .idle: return .focus
        case .running(let phase, _), .paused(let phase, _): return phase
        }
    }

    var isRunning: Bool {
        if case .running = state { return true }
        return false
    }

    var isIdle: Bool {
        if case .idle = state { return true }
        return false
    }

    var isActive: Bool { !isIdle }

    func remaining(at date: Date = Date()) -> TimeInterval {
        switch state {
        case .idle: return seconds(for: .focus)
        case .running(_, let ends): return max(0, ends.timeIntervalSince(date))
        case .paused(_, let left): return left
        }
    }

    func progress(at date: Date = Date()) -> Double {
        let total = seconds(for: phase)
        guard total > 0 else { return 0 }
        return min(1, max(0, 1 - remaining(at: date) / total))
    }

    static func format(_ seconds: TimeInterval) -> String {
        let whole = Int(seconds.rounded(.up))
        return String(format: "%02d:%02d", whole / 60, whole % 60)
    }
}

final class PomodoroApp: PocketApp {
    private let model = PomodoroModel()
    private lazy var board = PomodoroBoardWindow(model: model)
    private var timer: Timer?
    private var authorizationRequested = false

    override init(spec: AppSpec) {
        super.init(spec: spec)
    }

    override var defaultSize: NSSize { NSSize(width: 340, height: 330) }
    override var minSize: NSSize { NSSize(width: 340, height: 330) }
    override var resizable: Bool { false }

    override func makeContent() -> NSView {
        let view = PomodoroView(
            model: model,
            toggle: { [weak self] in self?.toggle() },
            reset: { [weak self] in self?.reset(reason: "reset") },
            skip: { [weak self] in self?.skip() },
            openBoard: { [weak self] in self?.openBoard() }
        )
        return ThemedHostingView(rootView: view, app: "pomodoro")
    }

    override func barImage() -> NSImage? {
        guard model.isActive else { return AppIcon.render(spec) }
        return AppIcon.render(spec, tint: PomodoroPalette.color(for: model.phase))
    }

    override func barTitle() -> NSAttributedString? {
        guard model.isActive else { return nil }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .semibold),
            .foregroundColor: PomodoroPalette.color(for: model.phase)
        ]
        return NSAttributedString(string: " " + PomodoroModel.format(model.remaining()), attributes: attributes)
    }

    override func menuItems() -> [NSMenuItem] {
        let item = NSMenuItem(title: "Open Ignis board", action: #selector(openBoard), keyEquivalent: "")
        item.target = self
        return [item]
    }

    @objc private func openBoard() {
        hide(reason: "switched")
        board.present()
    }

    func remoteState() -> [String: Any] {
        var state: [String: Any] = [
            "phase": model.isIdle ? "idle" : model.phase == .focus ? "focus" : model.phase == .long ? "long" : "rest",
            "running": model.isRunning,
            "remaining": Int(model.remaining().rounded(.up)),
            "focusMinutes": model.minutes(for: .focus),
            "breakMinutes": model.minutes(for: .rest),
            "longMinutes": model.minutes(for: .long),
            "customPlan": model.plan != nil,
            "hold": model.hold,
            "waiting": model.waiting,
            "cycle": model.cycle,
            "project": model.project ?? NSNull(),
        ]
        if case .running(_, let ends) = model.state { state["endsAt"] = Int(ends.timeIntervalSince1970 * 1000) }
        return state
    }

    func remoteStart(project: String?, plan: PomodoroPlan?, hold: Bool?, source: String) {
        model.project = project
        if model.isIdle {
            model.plan = plan?.isEmpty == false ? plan : nil
            model.hold = hold ?? false
        }
        note("pomodoro remote start source=\(source) project=\(project ?? "none") focus=\(model.minutes(for: .focus))m rest=\(model.minutes(for: .rest))m custom=\(model.plan != nil) hold=\(model.hold) waiting=\(model.waiting) state=\(model.isIdle ? "idle" : model.isRunning ? "running" : "paused") phase=\(model.phase.label)")
        if !model.isRunning { toggle() }
        changed()
    }

    func remotePause(source: String) {
        note("pomodoro remote pause source=\(source) project=\(model.project ?? "none") phase=\(model.phase.label) running=\(model.isRunning)")
        if model.isRunning { toggle() }
    }

    func remoteResume(source: String) {
        note("pomodoro remote resume source=\(source) project=\(model.project ?? "none") phase=\(model.phase.label) paused=\(!model.isRunning && !model.isIdle) waiting=\(model.waiting)")
        if !model.isRunning && !model.isIdle { toggle() }
    }

    func remoteStop(source: String) {
        note("pomodoro remote stop source=\(source) project=\(model.project ?? "none") phase=\(model.phase.label)")
        reset(reason: "stopped from \(source)")
        model.project = nil
    }

    override func stop() {
        stopTimer()
        super.stop()
    }

    private func toggle() {
        switch model.state {
        case .idle:
            let phase = PomodoroPhase.focus
            model.cycle += 1
            model.state = .running(phase, Date().addingTimeInterval(model.seconds(for: phase)))
            note("pomodoro start phase=\(phase.label) planned=\(model.minutes(for: phase))m")
            requestAuthorizationOnce()
            startTimer()
        case .running(let phase, let ends):
            let left = max(0, ends.timeIntervalSinceNow)
            model.state = .paused(phase, left)
            note("pomodoro pause phase=\(phase.label) remaining=\(Int(left))s")
            stopTimer()
        case .paused(let phase, let left):
            model.state = .running(phase, Date().addingTimeInterval(left))
            note("pomodoro resume phase=\(phase.label) remaining=\(Int(left))s waited=\(model.waiting) cycle=\(model.cycle)")
            model.waiting = false
            startTimer()
        }
        refresh()
    }

    private func reset(reason: String) {
        guard model.isActive else { return }
        let phase = model.phase
        note("pomodoro phase end phase=\(phase.label) planned=\(model.minutes(for: phase))m reason=\(reason)")
        model.state = .idle
        model.project = nil
        model.plan = nil
        model.hold = false
        model.waiting = false
        stopTimer()
        refresh()
    }

    private func skip() {
        model.waiting = false
        switch model.state {
        case .idle:
            return
        case .running(let phase, _):
            advance(from: phase, reason: "skipped", running: true)
        case .paused(let phase, _):
            advance(from: phase, reason: "skipped", running: false)
        }
        refresh()
    }

    private func advance(from phase: PomodoroPhase, reason: String, running: Bool) {
        let next: PomodoroPhase
        if phase == .focus {
            if reason == "finished" { model.streak += 1 }
            next = model.streak >= model.longEvery ? .long : .rest
            if next == .long { model.streak = 0 }
        } else {
            next = .focus
            model.cycle += 1
        }
        note("pomodoro phase end phase=\(phase.label) planned=\(model.minutes(for: phase))m reason=\(reason) next=\(next.label) nextPlanned=\(model.minutes(for: next))m")
        if running {
            model.state = .running(next, Date().addingTimeInterval(model.seconds(for: next)))
        } else {
            model.state = .paused(next, model.seconds(for: next))
        }
    }

    private func onTick() {
        guard case .running(let phase, let ends) = model.state else {
            stopTimer()
            return
        }
        if ends.timeIntervalSinceNow <= 0 {
            if phase == .focus {
                let store = PomodoroBoardStore.shared
                store.record(minutes: model.minutes(for: .focus), ended: ends, project: model.project.map(store.projectId(named:)))
            }
            let holding = phase != .focus && model.hold
            advance(from: phase, reason: "finished", running: !holding)
            if holding {
                model.waiting = true
                stopTimer()
                note("pomodoro waiting for start project=\(model.project ?? "none") cycle=\(model.cycle)")
            }
            NSSound(named: "Glass")?.play()
            let message = phase == .focus
                ? "Focus done — take a \(model.minutes(for: model.phase)) min \(model.phase == .long ? "long break" : "break")"
                : holding ? "Break over — press Start when you're back" : "Break over — back to focus"
            notify(title: spec.name, body: message)
        }
        refresh()
    }

    private func refresh() {
        model.tick = Date()
        changed()
    }

    private func startTimer() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.onTick() }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func requestAuthorizationOnce() {
        guard !authorizationRequested, Bundle.main.bundleIdentifier != nil else { return }
        authorizationRequested = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            note("pomodoro notification authorization granted=\(granted) error=\(error?.localizedDescription ?? "none")")
        }
    }

    private func notify(title: String, body: String) {
        guard Bundle.main.bundleIdentifier != nil else {
            note("pomodoro notification skipped reason=no bundle body=\(body)")
            return
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                note("pomodoro notification failed body=\(body) error=\(error.localizedDescription)")
            }
        }
    }
}

private enum Flap {
    static var theme: BoardTheme { AureliusBoard.theme }
    static var backdrop: [Color] { [theme.card, theme.sidebar] }
    static var cardTop: Color { theme.card }
    static var cardBottom: Color { theme.backdrop }
    static var seam: Color { theme.line }
    static var muted: Color { theme.muted }
    static var colon: Color { theme.faint }
    static var chip: Color { theme.line.opacity(0.55) }
    static var ink: Color { theme.ink }
    static var shadow: Color { theme.shadow }

    static func tint(for phase: PomodoroPhase) -> AnyShapeStyle { phase == .focus ? theme.accentInkStyle : AnyShapeStyle(theme.muted) }
    static func glow(for phase: PomodoroPhase) -> Color { phase == .focus ? theme.accent : theme.muted }
}

private struct FlapCard: View {
    let text: String
    let tint: AnyShapeStyle
    @State private var angle: Double = 0

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                Flap.cardTop
                Flap.cardBottom
            }
            Text(text)
                .font(.system(size: 92, weight: .bold).width(.condensed))
                .monospacedDigit()
                .foregroundStyle(tint)
            Flap.seam.frame(height: 2)
        }
        .frame(width: 112, height: 136)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Flap.seam, lineWidth: 1))
        .shadow(color: Flap.shadow, radius: 10, y: 6)
        .rotation3DEffect(.degrees(angle), axis: (x: 1, y: 0, z: 0), perspective: 0.6)
        .onChange(of: text) { _, _ in
            angle = 70
            withAnimation(.easeOut(duration: 0.18)) { angle = 0 }
        }
    }
}

private struct FlapButton: ButtonStyle {
    let fill: AnyShapeStyle
    let ink: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(ink)
            .padding(.horizontal, 16)
            .frame(height: 32)
            .background(RoundedRectangle(cornerRadius: 8).fill(fill))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

struct PomodoroView: View {
    @ObservedObject var model: PomodoroModel
    @ObservedObject var themes = AppThemeStore.shared
    let toggle: () -> Void
    let reset: () -> Void
    let skip: () -> Void
    let openBoard: () -> Void

    private var tint: AnyShapeStyle { Flap.tint(for: model.phase) }

    private var heading: String {
        if model.waiting { return "Ready" }
        if case .paused = model.state { return "Paused" }
        if model.phase == .focus, let project = model.project { return project }
        return model.phase.label
    }

    private var toggleTitle: String {
        switch model.state {
        case .idle: return "Start"
        case .running: return "Pause"
        case .paused: return model.waiting ? "Start" : "Resume"
        }
    }

    var body: some View {
        let parts = PomodoroModel.format(model.remaining(at: model.tick)).split(separator: ":").map(String.init)
        VStack(spacing: 0) {
            Text(heading.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(3.6)
                .foregroundStyle(Flap.muted)
            HStack(spacing: 8) {
                FlapCard(text: parts.first ?? "00", tint: tint)
                Text(":")
                    .font(.system(size: 60, weight: .bold).width(.condensed))
                    .foregroundStyle(Flap.colon)
                    .offset(y: -4)
                FlapCard(text: parts.last ?? "00", tint: tint)
            }
            .padding(.top, 16)
            HStack(spacing: 7) {
                let filled = model.phase == .long ? model.longEvery : model.streak
                ForEach(0..<model.longEvery, id: \.self) { index in
                    Circle()
                        .fill(index < filled ? tint : AnyShapeStyle(Flap.seam))
                        .frame(width: 6, height: 6)
                        .shadow(color: index < filled ? Flap.glow(for: model.phase).opacity(0.5) : .clear, radius: 3)
                }
            }
            .help("Sessions until the long break")
            .padding(.top, 20)
            HStack(spacing: 8) {
                Button(action: reset) { Image(systemName: "arrow.counterclockwise") }
                    .buttonStyle(FlapButton(fill: AnyShapeStyle(Flap.chip), ink: Flap.ink))
                    .disabled(model.isIdle)
                    .opacity(model.isIdle ? 0.4 : 1)
                    .help("Reset")
                Button(action: toggle) { Text(toggleTitle).frame(minWidth: 70) }
                    .buttonStyle(FlapButton(fill: tint, ink: Flap.cardTop))
                    .keyboardShortcut(.space, modifiers: [])
                Button(action: skip) { Image(systemName: "forward.end.fill") }
                    .buttonStyle(FlapButton(fill: AnyShapeStyle(Flap.chip), ink: Flap.ink))
                    .disabled(model.isIdle)
                    .opacity(model.isIdle ? 0.4 : 1)
                    .help("Skip to the next phase")
            }
            .padding(.top, 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .top) {
            HStack {
                Text("Ignis").font(.system(size: 17, weight: .bold)).foregroundStyle(Flap.ink)
                Spacer()
                Button(action: openBoard) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Flap.muted)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Flap.chip))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Open the Ignis board in its own window")
            }
            .padding(16)
        }
        .background(RadialGradient(colors: Flap.backdrop, center: UnitPoint(x: 0.5, y: 0.4), startRadius: 0, endRadius: 280))
        .ignoresSafeArea()
        .id(AureliusBoard.theme.id)
        .appTheme(AureliusBoard.theme)
    }
}
