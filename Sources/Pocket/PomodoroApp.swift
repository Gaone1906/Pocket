import AppKit
import SwiftUI
import UserNotifications

enum PomodoroPhase {
    case focus, rest

    var other: PomodoroPhase { self == .focus ? .rest : .focus }
    var label: String { self == .focus ? "Focus" : "Break" }
}

enum PomodoroState {
    case idle
    case running(PomodoroPhase, Date)
    case paused(PomodoroPhase, TimeInterval)
}

enum PomodoroPalette {
    static let gold = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0xE6 / 255, green: 0xC2 / 255, blue: 0x5A / 255, alpha: 1)
            : NSColor(srgbRed: 0xB8 / 255, green: 0x86 / 255, blue: 0x0B / 255, alpha: 1)
    }

    static let silver = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0xC9 / 255, green: 0xCC / 255, blue: 0xD1 / 255, alpha: 1)
            : NSColor(srgbRed: 0x7D / 255, green: 0x80 / 255, blue: 0x85 / 255, alpha: 1)
    }

    static func color(for phase: PomodoroPhase) -> NSColor { phase == .focus ? gold : silver }
}

final class PomodoroModel: ObservableObject {
    @Published var state: PomodoroState = .idle
    @Published var tick = Date()
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

    init() {
        let defaults = UserDefaults.standard
        let focus = defaults.integer(forKey: "pomodoro.focus")
        let rest = defaults.integer(forKey: "pomodoro.break")
        focusMinutes = (1...120).contains(focus) ? focus : 25
        breakMinutes = (1...60).contains(rest) ? rest : 5
    }

    func minutes(for phase: PomodoroPhase) -> Int { phase == .focus ? focusMinutes : breakMinutes }
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
    private var timer: Timer?
    private var authorizationRequested = false

    override init(spec: AppSpec) {
        super.init(spec: spec)
    }

    override var defaultSize: NSSize { NSSize(width: 340, height: 400) }
    override var minSize: NSSize { NSSize(width: 340, height: 400) }
    override var resizable: Bool { false }

    override func makeContent() -> NSView {
        let view = PomodoroView(
            model: model,
            toggle: { [weak self] in self?.toggle() },
            reset: { [weak self] in self?.reset(reason: "reset") },
            skip: { [weak self] in self?.skip() }
        )
        return NSHostingView(rootView: view)
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

    override func stop() {
        stopTimer()
        super.stop()
    }

    private func toggle() {
        switch model.state {
        case .idle:
            let phase = PomodoroPhase.focus
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
            note("pomodoro resume phase=\(phase.label) remaining=\(Int(left))s")
            startTimer()
        }
        refresh()
    }

    private func reset(reason: String) {
        guard model.isActive else { return }
        let phase = model.phase
        note("pomodoro phase end phase=\(phase.label) planned=\(model.minutes(for: phase))m reason=\(reason)")
        model.state = .idle
        stopTimer()
        refresh()
    }

    private func skip() {
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
        let next = phase.other
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
            advance(from: phase, reason: "finished", running: true)
            NSSound(named: "Glass")?.play()
            let message = phase == .focus
                ? "Focus done — take a \(model.breakMinutes) min break"
                : "Break over — back to focus"
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

struct PomodoroView: View {
    @ObservedObject var model: PomodoroModel
    let toggle: () -> Void
    let reset: () -> Void
    let skip: () -> Void

    private var tint: Color { Color(nsColor: PomodoroPalette.color(for: model.phase)) }

    private var toggleTitle: String {
        switch model.state {
        case .idle: return "Start"
        case .running: return "Pause"
        case .paused: return "Resume"
        }
    }

    var body: some View {
        let now = model.tick
        VStack(spacing: 16) {
            Text(model.isIdle ? "Ready" : model.phase.label)
                .font(.headline)
                .foregroundStyle(.secondary)
            ZStack {
                Circle().stroke(tint.opacity(0.18), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: model.isIdle ? 0 : model.progress(at: now))
                    .stroke(tint, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.4), value: model.progress(at: now))
                Text(PomodoroModel.format(model.remaining(at: now)))
                    .font(.system(size: 44, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(tint)
            }
            .frame(width: 180, height: 180)
            VStack(spacing: 6) {
                Stepper("Focus  \(model.focusMinutes) min", value: $model.focusMinutes, in: 1...120)
                Stepper("Break  \(model.breakMinutes) min", value: $model.breakMinutes, in: 1...60)
            }
            .disabled(model.isRunning)
            HStack(spacing: 10) {
                Button(toggleTitle, action: toggle)
                    .buttonStyle(.borderedProminent)
                    .tint(tint)
                    .keyboardShortcut(.space, modifiers: [])
                Button("Reset", action: reset)
                    .disabled(model.isIdle)
                Button("Skip", action: skip)
                    .disabled(model.isIdle)
            }
            .controlSize(.large)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
        .padding(.top, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
