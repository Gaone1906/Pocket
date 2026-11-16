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

    override var defaultSize: NSSize { NSSize(width: 340, height: 428) }
    override var minSize: NSSize { NSSize(width: 340, height: 428) }
    override var resizable: Bool { false }

    override func makeContent() -> NSView {
        let view = PomodoroView(
            model: model,
            toggle: { [weak self] in self?.toggle() },
            reset: { [weak self] in self?.reset(reason: "reset") },
            skip: { [weak self] in self?.skip() }
        )
        let hosting = NSHostingView(rootView: view)
        hosting.appearance = NSAppearance(named: .darkAqua)
        return hosting
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

private enum Forest {
    static let sky = [Color(red: 0.05, green: 0.11, blue: 0.10), Color(red: 0.08, green: 0.19, blue: 0.15), Color(red: 0.11, green: 0.25, blue: 0.18)]
    static let far = Color(red: 0.13, green: 0.30, blue: 0.21)
    static let mid = Color(red: 0.08, green: 0.21, blue: 0.15)
    static let near = Color(red: 0.04, green: 0.12, blue: 0.09)
    static let moss = Color(red: 0.55, green: 0.70, blue: 0.47)
    static let mist = Color(red: 0.84, green: 0.90, blue: 0.82)
}

private struct Seeded {
    var state: UInt64
    mutating func next() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double(state >> 33) / Double(1 << 31)
    }
}

private struct PineRidge: Shape {
    let seed: UInt64
    let count: Int
    let heights: ClosedRange<Double>

    func path(in rect: CGRect) -> Path {
        var random = Seeded(state: seed)
        var path = Path()
        path.addRect(CGRect(x: rect.minX, y: rect.maxY - 6, width: rect.width, height: 6))
        let step = rect.width / Double(count)
        for index in 0...count {
            let x = rect.minX + Double(index) * step + (random.next() - 0.5) * step * 0.7
            let height = heights.lowerBound + random.next() * (heights.upperBound - heights.lowerBound)
            let width = height * (0.42 + random.next() * 0.12)
            let base = rect.maxY - 4
            for tier in 0..<3 {
                let top = base - height + Double(tier) * height * 0.24
                let bottom = base - Double(2 - tier) * height * 0.2
                let half = width / 2 * (0.62 + Double(tier) * 0.19)
                path.move(to: CGPoint(x: x, y: top))
                path.addLine(to: CGPoint(x: x + half, y: bottom))
                path.addLine(to: CGPoint(x: x - half, y: bottom))
                path.closeSubpath()
            }
            path.addRect(CGRect(x: x - 1.5, y: base - height * 0.2, width: 3, height: height * 0.2 + 4))
        }
        return path
    }
}

private struct ForestBackdrop: View {
    let glow: Color
    let progress: Double
    let running: Bool
    let resting: Bool
    let tick: Date

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack(alignment: .topLeading) {
                LinearGradient(colors: Forest.sky, startPoint: .top, endPoint: .bottom)
                RadialGradient(colors: [glow.opacity(0.22), .clear], center: UnitPoint(x: 0.5, y: 0.36), startRadius: 10, endRadius: 210)
                stars(size)
                Image(systemName: "moon.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Forest.mist.opacity(0.75))
                    .position(x: size.width - 34, y: 30)
                birds(size)
                PineRidge(seed: 7, count: 9, heights: 46...70).fill(Forest.far).frame(height: 96).offset(y: size.height - 96)
                PineRidge(seed: 19, count: 7, heights: 40...62).fill(Forest.mid).frame(height: 76).offset(y: size.height - 76)
                fireflies(size)
                critter(size)
                PineRidge(seed: 41, count: 4, heights: 30...48).fill(Forest.near).frame(height: 50).offset(y: size.height - 50)
            }
        }
    }

    func stars(_ size: CGSize) -> some View {
        var random = Seeded(state: 3)
        let points = (0..<16).map { _ in (CGPoint(x: random.next() * size.width, y: random.next() * size.height * 0.28), 0.8 + random.next() * 1.4, random.next()) }
        return ForEach(points.indices, id: \.self) { index in
            let point = points[index]
            Circle()
                .fill(Forest.mist.opacity(0.25 + point.2 * 0.35))
                .frame(width: point.1, height: point.1)
                .position(point.0)
        }
    }

    func birds(_ size: CGSize) -> some View {
        ForEach(0..<3, id: \.self) { index in
            Image(systemName: "bird.fill")
                .font(.system(size: [9, 7, 6][index]))
                .foregroundStyle(Forest.mist.opacity(0.28))
                .position(x: 30 + Double(index) * 16, y: 26 + Double(index % 2) * 9)
        }
    }

    func fireflies(_ size: CGSize) -> some View {
        var random = Seeded(state: 11)
        let spots = (0..<9).map { _ in CGPoint(x: 16 + random.next() * (size.width - 32), y: size.height - 30 - random.next() * 70) }
        let beat = Int(tick.timeIntervalSince1970)
        return ForEach(spots.indices, id: \.self) { index in
            let lit = running && (beat + index * 2) % 3 != 0
            Circle()
                .fill(Color(red: 0.93, green: 0.92, blue: 0.55))
                .frame(width: 3, height: 3)
                .shadow(color: Color(red: 0.95, green: 0.9, blue: 0.4), radius: lit ? 4 : 0)
                .opacity(lit ? 0.9 : 0.18)
                .position(spots[index])
                .animation(.easeInOut(duration: 0.9), value: lit)
        }
    }

    func critter(_ size: CGSize) -> some View {
        let x = 22 + progress * (size.width - 44)
        return Image(systemName: resting ? "tortoise.fill" : "hare.fill")
            .font(.system(size: 15))
            .foregroundStyle(Forest.mist.opacity(0.85))
            .position(x: x, y: size.height - 46)
            .animation(.linear(duration: 0.9), value: progress)
            .help(resting ? "The tortoise strolls through your break" : "The hare crosses the forest as you focus")
    }
}

private struct MinutePill: View {
    let title: String
    let icon: String
    @Binding var value: Int
    let range: ClosedRange<Int>

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 10)).foregroundStyle(Forest.moss)
            Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(Forest.mist.opacity(0.7))
            nudge("minus", by: -1)
            Text("\(value)")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Forest.mist)
                .frame(minWidth: 20)
            nudge("plus", by: 1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color.black.opacity(0.28)))
        .overlay(Capsule().stroke(Forest.moss.opacity(0.25), lineWidth: 1))
    }

    func nudge(_ symbol: String, by delta: Int) -> some View {
        Button {
            value = min(range.upperBound, max(range.lowerBound, value + delta))
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Forest.mist.opacity(0.8))
                .frame(width: 18, height: 18)
                .background(Circle().fill(Forest.moss.opacity(0.18)))
        }
        .buttonStyle(.plain)
    }
}

private struct ForestButton: ButtonStyle {
    let fill: Color
    let ink: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(ink)
            .padding(.horizontal, 16)
            .frame(height: 32)
            .background(Capsule().fill(fill))
            .overlay(Capsule().stroke(Forest.mist.opacity(0.12), lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

struct PomodoroView: View {
    @ObservedObject var model: PomodoroModel
    let toggle: () -> Void
    let reset: () -> Void
    let skip: () -> Void

    private var tint: Color { Color(nsColor: PomodoroPalette.color(for: model.phase)) }

    private var heading: String {
        if model.isIdle { return "Into the woods" }
        if case .paused = model.state { return "Resting in the clearing" }
        return model.phase == .focus ? "Focus" : "Break by the stream"
    }

    private var toggleTitle: String {
        switch model.state {
        case .idle: return "Start"
        case .running: return "Pause"
        case .paused: return "Resume"
        }
    }

    private var toggleIcon: String { model.isRunning ? "pause.fill" : "play.fill" }

    var body: some View {
        let now = model.tick
        let progress = model.isIdle ? 0 : model.progress(at: now)
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: model.phase == .focus ? "leaf.fill" : "drop.fill").font(.system(size: 10))
                Text(heading.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(1.6)
            }
            .foregroundStyle(Forest.moss)
            .padding(.top, 26)
            ZStack {
                Circle().fill(Color.black.opacity(0.22))
                Circle().stroke(Forest.moss.opacity(0.16), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(tint, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: tint.opacity(0.5), radius: 6)
                    .animation(.linear(duration: 0.4), value: progress)
                VStack(spacing: 2) {
                    Text(PomodoroModel.format(model.remaining(at: now)))
                        .font(.system(size: 46, weight: .light, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(tint)
                    Text(model.phase == .focus ? "\(model.focusMinutes) min focus" : "\(model.breakMinutes) min break")
                        .font(.system(size: 11))
                        .foregroundStyle(Forest.mist.opacity(0.5))
                }
            }
            .frame(width: 176, height: 176)
            .padding(.top, 16)
            HStack(spacing: 8) {
                MinutePill(title: "Focus", icon: "leaf.fill", value: $model.focusMinutes, range: 1...120)
                MinutePill(title: "Break", icon: "drop.fill", value: $model.breakMinutes, range: 1...60)
            }
            .disabled(model.isRunning)
            .opacity(model.isRunning ? 0.45 : 1)
            .padding(.top, 20)
            HStack(spacing: 8) {
                Button(action: reset) { Image(systemName: "arrow.counterclockwise") }
                    .buttonStyle(ForestButton(fill: Color.black.opacity(0.3), ink: Forest.mist))
                    .disabled(model.isIdle)
                    .opacity(model.isIdle ? 0.4 : 1)
                    .help("Reset")
                Button(action: toggle) { Label(toggleTitle, systemImage: toggleIcon) }
                    .buttonStyle(ForestButton(fill: tint, ink: Forest.near))
                    .keyboardShortcut(.space, modifiers: [])
                Button(action: skip) { Image(systemName: "forward.end.fill") }
                    .buttonStyle(ForestButton(fill: Color.black.opacity(0.3), ink: Forest.mist))
                    .disabled(model.isIdle)
                    .opacity(model.isIdle ? 0.4 : 1)
                    .help("Skip to the next phase")
            }
            .padding(.top, 16)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ForestBackdrop(glow: tint, progress: progress, running: model.isRunning, resting: model.phase == .rest, tick: now))
        .ignoresSafeArea()
        .environment(\.colorScheme, .dark)
    }
}
