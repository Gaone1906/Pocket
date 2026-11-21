import AppKit
import SwiftUI

enum Ventus {
    static var theme: BoardTheme { KairosBoard.theme }
    static var ink: Color { KairosBoard.ink }
    static var ground: Color { KairosBoard.backdrop }
    static var card: Color { KairosBoard.column }
    static var rail: Color { KairosBoard.sidebar }
    static var line: Color { KairosBoard.line }
    static var muted: Color { KairosBoard.muted }
    static var faint: Color { KairosBoard.faint }
    static var track: Color { KairosBoard.line.opacity(0.7) }
    static var onInk: Color { theme.isDark ? KairosBoard.backdrop : .white }
    static var onInkSoft: Color { theme.isDark ? KairosBoard.line : Color(hex: 0xE0D3C0) }
    static let hot = Color(hex: 0xC0622F)
    static let rest = Color(hex: 0x6F97B3)
    static var restText: Color { theme.isDark ? rest : Color(hex: 0x3C5568) }
    static var restSoft: Color { theme.isDark ? rest.opacity(0.22) : Color(hex: 0xE1EBF1) }
    static var restTile: Color { theme.isDark ? rest.opacity(0.18) : Color(hex: 0xE1E8ED) }
    static var warm: Color { theme.isDark ? KairosBoard.backdrop : Color(hex: 0xF6E4D6) }
    static var warmSide: Color { theme.isDark ? KairosBoard.sidebar : Color(hex: 0xEFD6C3) }
    static var warmTrack: Color { theme.isDark ? KairosBoard.line : Color(hex: 0xE4C2AA) }
    static var coolSide: Color { theme.isDark ? KairosBoard.sidebar : Color(hex: 0xD3E2EC) }

    static func font(_ size: CGFloat, _ weight: Font.Weight = .heavy) -> Font { .system(size: size, weight: weight, design: .rounded) }

    private static func format(_ template: String) -> DateFormatter {
        let format = DateFormatter()
        format.calendar = ScheduleDays.calendar
        format.locale = .current
        format.setLocalizedDateFormatFromTemplate(template)
        return format
    }

    private static let weekdayFormat = format("EEEE")
    private static let shortFormat = format("dMMM")

    static func weekday(_ day: String) -> String { ScheduleDays.date(day).map(weekdayFormat.string(from:)) ?? day }
    static func short(_ day: String) -> String { ScheduleDays.date(day).map(shortFormat.string(from:)) ?? day }
    static func dayOfMonth(_ day: String) -> Int { ScheduleDays.date(day).map { ScheduleDays.calendar.component(.day, from: $0) } ?? 0 }
    static func weekdayShort(_ day: String) -> String { ScheduleDays.short(ScheduleDays.weekday(day)) }
    static func letter(_ day: String) -> String { String(weekdayShort(day).prefix(1)) }
    static func tag(_ day: String) -> String { "\(weekdayShort(day)) \(dayOfMonth(day))" }

    static func minutes(_ seconds: Int) -> String { "\(KairosPlan.minutes(seconds))m" }

    static func hours(_ seconds: Int) -> String {
        let minutes = max(0, seconds) / 60
        return minutes >= 60 ? "\(minutes / 60)h \(String(format: "%02d", minutes % 60))" : "\(minutes)m"
    }

    static func glyph(_ step: ScheduleStep) -> VentusGlyph {
        let name = KairosFit.name(step).lowercased()
        if name.hasPrefix("warm") { return .flame }
        if name.contains("stretch") || name.contains("mobility") { return .wave }
        if name.contains("rope") { return .rope }
        if name.contains("calf") || name.contains("calves") { return .rise }
        if name.contains("walk") { return .walk }
        if name.contains("run") || name.contains("jog") { return .run }
        if name.contains("gym") { return .gym }
        switch KairosPlan.type(step) {
        case "intervals": return .pulse
        case "rounds", "moves": return .loop
        case "log": return .run
        default: return .other
        }
    }

    static func tint(_ glyph: VentusGlyph) -> Color {
        switch glyph {
        case .flame: return hot
        case .wave: return restText
        default: return ink
        }
    }

    static func glyph(_ kind: VentusKind) -> VentusGlyph {
        switch kind {
        case .run: return .run
        case .rope: return .rope
        case .walk: return .walk
        case .gym: return .gym
        case .other: return .other
        }
    }

    static func icons(_ steps: [ScheduleStep]) -> [VentusGlyph] {
        let main = steps.filter { !KairosFit.warm($0) && !KairosFit.easy($0) }
        var out: [VentusGlyph] = []
        for step in main {
            let symbol = Self.glyph(step)
            if !out.contains(symbol) { out.append(symbol) }
        }
        if out.isEmpty, !steps.isEmpty { out = [.wave] }
        return Array(out.prefix(4))
    }
}

enum VentusGlyph: Equatable {
    case today, scheduled, start, review
    case flame, run, rope, rise, wave, pulse, loop, walk, gym, other
    case check, flag, pencil, plus, back, forward, down, heart, eye, close, next, arrow
}

struct VentusGlyphShape: Shape {
    let glyph: VentusGlyph

    func path(in rect: CGRect) -> Path {
        var path = Path()
        func m(_ x: CGFloat, _ y: CGFloat) { path.move(to: CGPoint(x: x, y: y)) }
        func l(_ x: CGFloat, _ y: CGFloat) { path.addLine(to: CGPoint(x: x, y: y)) }
        func c(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat, _ x: CGFloat, _ y: CGFloat) {
            path.addCurve(to: CGPoint(x: x, y: y), control1: CGPoint(x: x1, y: y1), control2: CGPoint(x: x2, y: y2))
        }
        func dot(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) { path.addEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)) }
        switch glyph {
        case .today:
            dot(12, 12, 8.5)
            dot(12, 12, 1)
        case .scheduled:
            path.addRoundedRect(in: CGRect(x: 3.5, y: 5, width: 17, height: 15), cornerSize: CGSize(width: 3, height: 3))
            m(3.5, 10); l(20.5, 10)
            m(8, 3); l(8, 7)
            m(16, 3); l(16, 7)
        case .start:
            m(8, 5.5); l(8, 18.5); l(18.5, 12); path.closeSubpath()
        case .review:
            m(6, 20); l(6, 13)
            m(12, 20); l(12, 5)
            m(18, 20); l(18, 10)
        case .flame:
            m(12, 3)
            c(13, 7, 17, 8.5, 17, 13)
            c(17, 15.76, 14.76, 18, 12, 18)
            c(9.24, 18, 7, 15.76, 7, 13)
            c(7, 11, 8, 9.5, 9, 8.5)
            c(9, 10.5, 10, 11.5, 11, 11.5)
            c(11, 8.5, 10, 6.5, 12, 3)
            path.closeSubpath()
        case .run:
            m(4, 8); l(13, 8)
            m(2, 12); l(15, 12)
            m(5, 16); l(13, 16)
            m(15, 6); l(20, 12); l(15, 18)
        case .rope:
            m(6, 4); l(6, 9)
            m(18, 4); l(18, 9)
            m(6, 9); c(6, 18, 18, 18, 18, 9)
        case .rise:
            m(12, 20); l(12, 5)
            m(7, 10); l(12, 5); l(17, 10)
        case .wave:
            m(3, 14); c(6, 9, 9, 19, 12, 14); c(15, 9, 18, 19, 21, 14)
        case .pulse:
            m(3, 12); l(6, 12); l(8, 7); l(12, 17); l(14, 12); l(21, 12)
        case .loop:
            m(17, 4); l(20, 7); l(17, 10)
            m(20, 7); l(8, 7); c(5.79, 7, 4, 8.79, 4, 11)
            m(7, 20); l(4, 17); l(7, 14)
            m(4, 17); l(16, 17); c(18.21, 17, 20, 15.21, 20, 13)
        case .walk:
            dot(13, 4.5, 1.8)
            m(9, 21); l(11.5, 14.5); l(14, 17); l(14, 21)
            m(11.5, 14.5); l(12.5, 9); l(15.5, 12); l(18.5, 12)
            m(12.5, 9); l(8, 11); l(8, 14)
        case .gym:
            m(6.5, 7); l(6.5, 17)
            m(17.5, 7); l(17.5, 17)
            m(3.5, 10); l(3.5, 14)
            m(20.5, 10); l(20.5, 14)
            m(6.5, 12); l(17.5, 12)
        case .other:
            dot(6, 12, 1.2)
            dot(12, 12, 1.2)
            dot(18, 12, 1.2)
        case .check:
            m(5, 12.5); l(9.5, 17); l(19, 7.5)
        case .flag:
            m(5, 21); l(5, 4)
            m(5, 4); l(16, 4); l(14, 8); l(16, 12); l(5, 12)
        case .pencil:
            m(4, 20); l(8, 20); l(19, 9); l(15, 5); l(4, 16); path.closeSubpath()
        case .plus:
            m(12, 5); l(12, 19)
            m(5, 12); l(19, 12)
        case .back:
            m(15, 6); l(9, 12); l(15, 18)
        case .forward:
            m(9, 6); l(15, 12); l(9, 18)
        case .down:
            m(6, 9); l(12, 15); l(18, 9)
        case .heart:
            m(12, 20)
            c(12, 20, 5, 15.5, 5, 10)
            c(5, 6.5, 10, 5.5, 12, 7.4)
            c(14, 5.5, 19, 6.5, 19, 10)
            c(19, 15.5, 12, 20, 12, 20)
            path.closeSubpath()
        case .eye:
            m(2, 12)
            c(2, 12, 6, 5, 12, 5)
            c(18, 5, 22, 12, 22, 12)
            c(22, 12, 18, 19, 12, 19)
            c(6, 19, 2, 12, 2, 12)
            path.closeSubpath()
            dot(12, 12, 3)
        case .close:
            m(6, 6); l(18, 18)
            m(18, 6); l(6, 18)
        case .next:
            m(4, 12); l(16, 12)
            m(12, 6); l(18, 12); l(12, 18)
        case .arrow:
            m(5, 12); l(19, 12)
            m(13, 6); l(19, 12); l(13, 18)
        }
        let scale = min(rect.width, rect.height) / 24
        let dx = rect.minX + (rect.width - 24 * scale) / 2
        let dy = rect.minY + (rect.height - 24 * scale) / 2
        return path.applying(CGAffineTransform(translationX: dx, y: dy).scaledBy(x: scale, y: scale))
    }
}

struct VentusIcon: View {
    let glyph: VentusGlyph
    var color: Color? = nil
    var size: CGFloat = 20
    var weight: CGFloat = 2

    init(_ glyph: VentusGlyph, color: Color? = nil, size: CGFloat = 20, weight: CGFloat = 2) {
        self.glyph = glyph
        self.color = color
        self.size = size
        self.weight = weight
    }

    var body: some View {
        VentusGlyphShape(glyph: glyph)
            .stroke(color ?? Ventus.ink, style: StrokeStyle(lineWidth: max(1.2, weight * size / 24), lineCap: .round, lineJoin: .round))
            .frame(width: size, height: size)
    }
}

enum VentusArt {
    static let bear: NSImage? = {
        var places: [URL] = []
        if let resources = Bundle.main.resourceURL { places.append(resources.appendingPathComponent("ventus-bear.png")) }
        if let source = Bundle.main.object(forInfoDictionaryKey: "PocketSource") as? String, !source.isEmpty {
            places.append(URL(fileURLWithPath: source).appendingPathComponent("Resources/ventus-bear.png"))
        }
        for place in places {
            if let image = NSImage(contentsOf: place) {
                note("kairos logo loaded path=\(place.path)")
                return image
            }
        }
        note("kairos logo missing searched=\(places.count)")
        return nil
    }()
}

struct VentusLogo: View {
    var size: CGFloat = 52

    var body: some View {
        Group {
            if let image = VentusArt.bear {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Ventus.card
                    Image(systemName: "pawprint.fill")
                        .font(.system(size: size * 0.42, weight: .bold))
                        .foregroundStyle(Ventus.ink)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.27, style: .continuous))
        .accessibilityLabel("Ventus")
    }
}

struct VentusCard<Content: View>: View {
    var radius: CGFloat = 24
    var padding: CGFloat = 22
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Ventus.card))
    }
}

struct VentusPill: ButtonStyle {
    var dark = false
    var fill: Color? = nil
    var size: CGFloat = 15
    var height: CGFloat = 40

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Ventus.font(size))
            .foregroundStyle(dark ? Ventus.onInk : Ventus.ink)
            .padding(.horizontal, 18)
            .frame(height: height)
            .background(Capsule().fill(dark ? Ventus.ink : (fill ?? Ventus.card)))
            .opacity(configuration.isPressed ? 0.8 : 1)
            .contentShape(Capsule())
    }
}

struct VentusRoundButton: View {
    let glyph: VentusGlyph
    let help: String
    var size: CGFloat = 40
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VentusIcon(glyph, size: size * 0.45, weight: 2.4)
                .frame(width: size, height: size)
                .background(Circle().fill(Ventus.card))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .help(help)
    }
}

struct VentusChip: View {
    let glyph: VentusGlyph
    var tint: Color? = nil
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            VentusIcon(glyph, color: tint, size: 18)
            Text(text).font(Ventus.font(14))
        }
        .foregroundStyle(Ventus.ink)
        .padding(.horizontal, 14)
        .frame(height: 36)
        .background(Capsule().fill(Ventus.card))
    }
}

struct VentusDayRing: View {
    let number: Int
    let fraction: Double
    var size: CGFloat = 64
    var inverted = false

    var body: some View {
        let width = size * 6 / 64
        ZStack {
            Circle().stroke(inverted ? Ventus.muted : Ventus.track, lineWidth: width)
            Circle()
                .trim(from: 0, to: max(0, min(1, fraction)))
                .stroke(inverted ? Ventus.onInk : Ventus.ink, style: StrokeStyle(lineWidth: width, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(number)")
                .font(Ventus.font(size * 0.28, .black))
                .monospacedDigit()
                .foregroundStyle(inverted ? Ventus.onInk : Ventus.ink)
        }
        .padding(width / 2)
        .frame(width: size, height: size)
    }
}

struct VentusBar: View {
    let fraction: Double
    var height: CGFloat = 10
    var fill: Color? = nil

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Ventus.track)
                Capsule()
                    .fill(fill ?? Ventus.ink)
                    .frame(width: fraction > 0 ? max(height, geo.size.width * max(0, min(1, fraction))) : 0)
            }
        }
        .frame(height: height)
    }
}

struct VentusProjectMenu: View {
    let projects: [VentusProject]
    let project: VentusProject?
    var size: CGFloat = 20
    let pick: (UUID) -> Void

    var body: some View {
        Menu {
            ForEach(projects) { item in
                Button(item.name) { pick(item.id) }
            }
        } label: {
            HStack(spacing: 8) {
                Text(project?.name ?? "No project")
                    .font(Ventus.font(size, .black))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: size * 0.6, weight: .heavy))
            }
            .foregroundStyle(Ventus.ink)
            .padding(.horizontal, 18)
            .frame(height: size * 2.2)
            .background(Capsule().fill(Ventus.card))
            .contentShape(Capsule())
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .fixedSize()
        .disabled(projects.isEmpty)
        .help("Switch project")
    }
}

struct VentusStepRow: View {
    let step: ScheduleStep
    var boxed = true
    var extras = false

    var body: some View {
        let glyph = Ventus.glyph(step)
        let detail = KairosFit.detail(step)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 14) {
                if boxed {
                    VentusIcon(glyph, color: Ventus.tint(glyph), size: 20)
                        .frame(width: 36, height: 36)
                        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Ventus.ground))
                } else {
                    VentusIcon(glyph, color: Ventus.tint(glyph), size: 20)
                }
                Text(KairosFit.name(step))
                    .font(Ventus.font(boxed ? 16 : 15))
                    .foregroundStyle(Ventus.ink)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if !detail.isEmpty && !extras {
                    Text(detail)
                        .font(Ventus.font(14, .bold))
                        .foregroundStyle(Ventus.muted)
                        .lineLimit(1)
                        .layoutPriority(-1)
                }
                Text(extras ? (KairosFit.setsLabel(step) ?? Ventus.minutes(KairosPlan.estimate(step))) : Ventus.minutes(KairosPlan.estimate(step)))
                    .font(Ventus.font(14, .bold))
                    .monospacedDigit()
                    .foregroundStyle(Ventus.muted)
                    .frame(minWidth: 36, alignment: .trailing)
            }
            if extras { more(detail) }
        }
        .padding(.vertical, boxed ? 12 : 11)
        .overlay(alignment: .top) { Rectangle().fill(Ventus.rail).frame(height: 1) }
    }

    @ViewBuilder private func more(_ detail: String) -> some View {
        let parts = KairosFit.intervals(step)
        let chips = KairosFit.sets(step)
        Group {
            if !parts.isEmpty {
                GeometryReader { geo in
                    let total = CGFloat(max(1, parts.reduce(0) { $0 + $1.seconds }))
                    let gaps = CGFloat(parts.count - 1) * 3
                    HStack(spacing: 3) {
                        ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                            Capsule()
                                .fill(part.hot ? Ventus.hot : Ventus.rest)
                                .frame(width: max(2, (geo.size.width - gaps) * CGFloat(part.seconds) / total))
                        }
                    }
                }
                .frame(height: 8)
            } else if !chips.isEmpty {
                HStack(spacing: 6) {
                    ForEach(Array(chips.prefix(12).enumerated()), id: \.offset) { _, reps in
                        Text("\(reps)")
                            .font(Ventus.font(12, .bold))
                            .foregroundStyle(Ventus.ink)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Ventus.ground))
                    }
                }
            } else if !detail.isEmpty {
                Text(detail)
                    .font(Ventus.font(13, .bold))
                    .foregroundStyle(Ventus.muted)
            }
        }
        .padding(.leading, 34)
    }
}

struct VentusTodayPage: View {
    @ObservedObject var store: ScheduleStore
    @ObservedObject var journal: KairosJournal
    @ObservedObject var runner: KairosRunner
    let projects: [VentusProject]
    let project: VentusProject?
    let resumable: Bool
    let start: (KairosSession) -> Void
    let resume: () -> Void

    var body: some View {
        let today = store.today
        let sessions = KairosSession.all(on: today)
        VStack(alignment: .leading, spacing: 22) {
            header(today)
            HStack(alignment: .top, spacing: 22) {
                VStack(spacing: 22) {
                    if sessions.isEmpty {
                        quiet(today)
                    }
                    ForEach(sessions) { session in
                        VentusHero(session: session, project: projects.first { $0.id == session.routine.id },
                                   running: runner.isRunning(session), start: { start(session) }, resume: resume)
                    }
                }
                .frame(maxWidth: .infinity)
                side(today)
                    .frame(width: 320)
            }
        }
    }

    private func header(_ today: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            (Text(Ventus.weekday(today) + " ").foregroundColor(Ventus.ink) + Text(Ventus.short(today)).font(Ventus.font(34, .bold)).foregroundColor(Ventus.muted))
                .font(Ventus.font(34, .black))
            Spacer()
            HStack(spacing: 10) {
                if resumable {
                    Button(action: resume) {
                        HStack(spacing: 8) {
                            VentusIcon(.start, color: Ventus.onInk, size: 16)
                            Text("Resume")
                        }
                    }
                    .buttonStyle(VentusPill(dark: true, size: 14, height: 36))
                }
                if let project {
                    if let milestone = project.nextMilestone(after: today) {
                        VentusChip(glyph: .gym, text: "\(max(0, KairosFit.days(today, milestone.day)))")
                            .help("\(milestone.label) · \(Ventus.short(milestone.day))")
                    }
                    VentusChip(glyph: .flame, tint: Ventus.hot, text: "\(project.streak(today))")
                        .help("Streak")
                }
            }
        }
    }

    private func quiet(_ today: String) -> some View {
        let resting = projects.contains { $0.routine.runs(on: today) && today >= $0.start && today <= $0.end }
        return VentusCard {
            Text(resting ? "Rest day" : "Nothing today")
                .font(Ventus.font(24, .black))
                .foregroundStyle(Ventus.muted)
                .frame(maxWidth: .infinity, minHeight: 120)
        }
    }

    @ViewBuilder private func side(_ today: String) -> some View {
        VStack(spacing: 22) {
            week(today)
            if let project, !project.targets.isEmpty {
                VentusCard {
                    VStack(spacing: 18) {
                        ForEach(Array(project.targets.enumerated()), id: \.offset) { index, target in
                            VStack(spacing: 8) {
                                HStack {
                                    Text(target)
                                    Spacer()
                                    Text(Ventus.short(project.end)).foregroundStyle(Ventus.muted)
                                }
                                .font(Ventus.font(15))
                                .foregroundStyle(Ventus.ink)
                                VentusBar(fraction: project.progress(index, journal))
                            }
                        }
                    }
                }
            }
            if let project, let next = project.nextSession(after: today) {
                HStack(spacing: 14) {
                    VentusIcon(.next, color: Ventus.muted, size: 20)
                        .frame(width: 36, height: 36)
                        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Ventus.rail))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Ventus.tag(next.day))
                            .font(Ventus.font(12))
                            .foregroundStyle(Ventus.muted)
                        Text(KairosFit.title(next.steps, fallback: project.name))
                            .font(Ventus.font(16))
                            .foregroundStyle(Ventus.ink)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    Text(Ventus.minutes(KairosFit.seconds(next.steps)))
                        .font(Ventus.font(14, .bold))
                        .foregroundStyle(Ventus.muted)
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 18)
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Ventus.line, style: StrokeStyle(lineWidth: 2, dash: [6, 5])))
            }
        }
    }

    private func week(_ today: String) -> some View {
        let monday = KairosFit.monday(today)
        return VentusCard {
            HStack(spacing: 6) {
                ForEach(0..<7, id: \.self) { offset in
                    let day = ScheduleDays.shift(monday, by: offset)
                    let state = project?.state(day, today: today) ?? KairosDayState.off
                    VStack(spacing: 6) {
                        Text(Ventus.letter(day))
                            .font(Ventus.font(12))
                            .foregroundStyle(day == today ? Ventus.ink : Ventus.muted)
                        dot(day, state: state, today: today)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func dot(_ day: String, state: KairosDayState, today: String) -> some View {
        let fill: Color
        let text: Color
        switch state {
        case .done:
            fill = Ventus.ink
            text = Ventus.onInk
        case .rest:
            fill = day > today ? Ventus.rest.opacity(0.35) : Ventus.rest
            text = Ventus.onInk
        case .part, .missed:
            fill = Ventus.track
            text = Ventus.ink
        default:
            fill = .clear
            text = day == today ? Ventus.ink : Ventus.muted
        }
        return Text("\(Ventus.dayOfMonth(day))")
            .font(Ventus.font(12))
            .monospacedDigit()
            .foregroundStyle(text)
            .frame(width: 30, height: 30)
            .background(Circle().fill(fill))
            .overlay(Circle().strokeBorder(day == today ? Ventus.ink : Color.clear, lineWidth: 2.5))
    }
}

struct VentusHero: View {
    let session: KairosSession
    let project: VentusProject?
    let running: Bool
    let start: () -> Void
    let resume: () -> Void

    var body: some View {
        let number = project?.dayNumber(session.day) ?? 1
        let total = project?.total ?? 1
        VentusCard(padding: 26) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 18) {
                    VentusDayRing(number: number, fraction: Double(number) / Double(max(1, total)))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(project?.name ?? session.routine.name) · \(number)/\(total)")
                            .font(Ventus.font(13))
                            .foregroundStyle(Ventus.muted)
                            .lineLimit(1)
                        Text(KairosFit.title(session.steps, fallback: session.routine.name))
                            .font(Ventus.font(28, .black))
                            .foregroundStyle(Ventus.ink)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 8)
                    action
                }
                .padding(.bottom, 12)
                ForEach(session.steps) { step in
                    VentusStepRow(step: step)
                }
            }
        }
    }

    @ViewBuilder private var action: some View {
        if running {
            Button(action: resume) {
                HStack(spacing: 10) {
                    VentusIcon(.start, color: Ventus.onInk, size: 18)
                    Text("Resume")
                }
            }
            .buttonStyle(VentusPill(dark: true, size: 17, height: 50))
            .keyboardShortcut(.return, modifiers: [])
        } else if session.finished {
            HStack(spacing: 8) {
                VentusIcon(.check, size: 18, weight: 2.6)
                Text("Done")
            }
            .font(Ventus.font(17))
            .foregroundStyle(Ventus.ink)
            .padding(.horizontal, 22)
            .frame(height: 50)
            .background(Capsule().fill(Ventus.ground))
        } else {
            Button(action: start) {
                HStack(spacing: 10) {
                    VentusIcon(.start, color: Ventus.onInk, size: 18)
                    Text("\(session.done > 0 ? "Continue" : "Start") · \(Ventus.minutes(session.seconds))")
                }
            }
            .buttonStyle(VentusPill(dark: true, size: 17, height: 50))
            .keyboardShortcut(.return, modifiers: [])
        }
    }
}

struct VentusScheduledPage: View {
    @ObservedObject var store: ScheduleStore
    @ObservedObject var journal: KairosJournal
    let projects: [VentusProject]
    let project: VentusProject?
    let pick: (UUID) -> Void
    let edit: () -> Void
    let preview: (KairosSession) -> Void
    let start: (KairosSession, Bool) -> Void
    @State private var week: Int?
    @State private var selected = ""

    var body: some View {
        let today = store.today
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                VentusProjectMenu(projects: projects, project: project, pick: pick)
                Spacer()
                VentusRoundButton(glyph: .pencil, help: "Edit project", enabled: project != nil, action: edit)
            }
            if let project {
                timeline(project, today: today)
                board(project, today: today)
            } else {
                VentusCard {
                    Text("No fitness routine")
                        .font(Ventus.font(22, .black))
                        .foregroundStyle(Ventus.muted)
                        .frame(maxWidth: .infinity, minHeight: 120)
                }
            }
        }
        .onChange(of: project?.id) { _, _ in
            week = nil
            selected = ""
        }
    }

    private func timeline(_ project: VentusProject, today: String) -> some View {
        let span = Double(max(1, KairosFit.days(project.start, project.end)))
        let at = max(0, min(1, Double(KairosFit.days(project.start, today)) / span))
        return HStack(spacing: 28) {
            HStack(spacing: 10) {
                VentusIcon(.flag, size: 20)
                Text(project.targets.isEmpty ? project.name : project.targets.joined(separator: " · "))
                    .font(Ventus.font(16))
                    .foregroundStyle(Ventus.ink)
                    .lineLimit(1)
            }
            .layoutPriority(1)
            GeometryReader { geo in
                let width = geo.size.width
                ZStack(alignment: .topLeading) {
                    Capsule().fill(Ventus.track).frame(width: width, height: 6).offset(y: 20)
                    Capsule().fill(Ventus.ink).frame(width: width * at, height: 6).offset(y: 20)
                    Text(Ventus.short(project.start)).font(Ventus.font(12)).foregroundStyle(Ventus.muted)
                    Text(Ventus.short(project.end)).font(Ventus.font(12)).foregroundStyle(Ventus.muted)
                        .frame(width: width, alignment: .trailing)
                    ForEach(project.milestones, id: \.self) { milestone in
                        let x = width * max(0, min(1, Double(KairosFit.days(project.start, milestone.day)) / span))
                        let last = milestone.day >= project.end
                        VentusIcon(last ? .flag : .gym, size: 12, weight: 3)
                            .frame(width: 18, height: 18)
                            .background(RoundedRectangle(cornerRadius: 5).fill(Ventus.card))
                            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(last ? Ventus.hot : Ventus.ink, lineWidth: 2))
                            .offset(x: x - 9, y: 14)
                            .help("\(milestone.label) · \(Ventus.short(milestone.day))")
                        if !last {
                            Text(Ventus.short(milestone.day))
                                .font(Ventus.font(11))
                                .foregroundStyle(Ventus.muted)
                                .fixedSize()
                                .offset(x: x - 18, y: 34)
                        }
                    }
                    if today >= project.start && today <= project.end {
                        Circle()
                            .fill(Ventus.ink)
                            .frame(width: 16, height: 16)
                            .background(Circle().fill(Ventus.card).padding(-4))
                            .offset(x: width * at - 8, y: 15)
                    }
                }
            }
            .frame(height: 50)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Ventus.card))
    }

    private func board(_ project: VentusProject, today: String) -> some View {
        let first = KairosFit.monday(project.start)
        let weeks = max(1, KairosFit.days(first, project.end) / 7 + 1)
        let current = max(0, min(weeks - 1, KairosFit.days(first, today) / 7))
        let shown = max(0, min(weeks - 1, week ?? current))
        let monday = ScheduleDays.shift(first, by: shown * 7)
        let fallback = today >= monday && today <= ScheduleDays.shift(monday, by: 6) ? today : max(monday, project.start)
        let chosen = selected.isEmpty ? fallback : selected
        return HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    VentusRoundButton(glyph: .back, help: "Previous week", enabled: shown > 0) {
                        week = shown - 1
                        selected = ""
                    }
                    Text("Week \(shown + 1)")
                        .font(Ventus.font(18, .black))
                        .foregroundStyle(Ventus.ink)
                    HStack(spacing: 5) {
                        ForEach(0..<min(weeks, 12), id: \.self) { index in
                            Capsule()
                                .fill(index == shown ? Ventus.ink : index < current ? Ventus.muted : Ventus.line)
                                .frame(width: 22, height: 6)
                        }
                    }
                    .padding(.leading, 4)
                    VentusRoundButton(glyph: .forward, help: "Next week", enabled: shown < weeks - 1) {
                        week = shown + 1
                        selected = ""
                    }
                }
                HStack(spacing: 10) {
                    ForEach(0..<7, id: \.self) { offset in
                        let day = ScheduleDays.shift(monday, by: offset)
                        tile(project, day: day, today: today, on: day == chosen)
                    }
                }
                .frame(minHeight: 190)
            }
            .frame(maxWidth: .infinity)
            detail(project, day: chosen, today: today)
                .frame(width: 340)
        }
    }

    private func tile(_ project: VentusProject, day: String, today: String, on: Bool) -> some View {
        let inside = day >= project.start && day <= project.end
        let steps = inside ? KairosFit.steps(project.routine, on: day).map(\.step) : []
        let state = project.state(day, today: today)
        let ink = on ? Ventus.onInk : Ventus.ink
        let sub = on ? Ventus.onInkSoft : Ventus.muted
        let fill: Color = on ? Ventus.ink : state == .rest ? Ventus.restTile : Ventus.card
        return Button {
            selected = day
        } label: {
            VStack(spacing: 10) {
                Text(Ventus.weekdayShort(day)).font(Ventus.font(12)).foregroundStyle(sub)
                Text("\(Ventus.dayOfMonth(day))").font(Ventus.font(22, .black)).foregroundStyle(ink)
                VStack(spacing: 6) {
                    ForEach(Array(Ventus.icons(steps).enumerated()), id: \.offset) { _, glyph in
                        VentusIcon(glyph, color: on ? Ventus.onInk : glyph == .wave ? Ventus.restText : Ventus.ink, size: 22)
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
                if project.status(day, today: today) == .done {
                    VentusIcon(.check, color: ink, size: 20, weight: 2.6)
                } else if !steps.isEmpty && (day >= today || state == .part) {
                    Text(Ventus.minutes(KairosFit.seconds(steps))).font(Ventus.font(12)).foregroundStyle(sub)
                }
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(fill))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(day == today && !on ? Ventus.ink : Color.clear, lineWidth: 2))
            .opacity(!inside ? 0.35 : day < today && !on ? 0.55 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
    }

    private func detail(_ project: VentusProject, day: String, today: String) -> some View {
        let inside = day >= project.start && day <= project.end
        let sessions = inside ? KairosSession.of(project.routine, on: day) : []
        let steps = inside ? KairosFit.steps(project.routine, on: day).map(\.step) : []
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(Ventus.tag(day)).font(Ventus.font(22, .black)).foregroundStyle(Ventus.ink)
                Spacer()
                if inside {
                    Text("Day \(project.dayNumber(day))").font(Ventus.font(15)).foregroundStyle(Ventus.muted)
                }
            }
            .padding(.bottom, 8)
            if steps.isEmpty {
                Text(inside ? "Rest day" : "Outside the project")
                    .font(Ventus.font(15))
                    .foregroundStyle(Ventus.muted)
                    .padding(.vertical, 12)
            }
            ForEach(steps) { step in
                VentusStepRow(step: step, boxed: false, extras: true)
            }
            Spacer(minLength: 18)
            if let session = sessions.first {
                HStack(spacing: 10) {
                    Button {
                        preview(session)
                    } label: {
                        HStack(spacing: 8) {
                            VentusIcon(.eye, size: 18)
                            Text("Preview")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(VentusPill(fill: Ventus.ground))
                    if !session.finished || day != today {
                        Button {
                            start(session, day != today)
                        } label: {
                            HStack(spacing: 8) {
                                VentusIcon(.start, color: Ventus.onInk, size: 16)
                                Text("Start")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(VentusPill(dark: true))
                    }
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity, minHeight: 300, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Ventus.card))
    }
}

struct VentusStartPage: View {
    @ObservedObject var store: ScheduleStore
    let project: VentusProject?
    let startToday: (KairosSession) -> Void
    let startStep: (ScheduleStep, String, ScheduleSlot) -> Void
    let anyDay: () -> Void
    let log: (VentusKind) -> Void

    private struct Pick {
        let step: ScheduleStep
        let day: String
        let slot: ScheduleSlot
    }

    var body: some View {
        let today = store.today
        let picks = project.map { distinct($0, today: today) } ?? []
        let session = project.flatMap { KairosSession.of($0.routine, on: today).first }
        let tiles: [AnyView] = picks.map { pick in AnyView(stepTile(pick)) } + [AnyView(anyDayTile)]
        VStack(alignment: .leading, spacing: 18) {
            caption(.start, "Guided")
            HStack(alignment: .top, spacing: 14) {
                todayTile(session, today: today)
                    .frame(maxWidth: .infinity)
                ForEach(0..<3, id: \.self) { column in
                    VStack(spacing: 14) {
                        ForEach(Array(stride(from: column, to: tiles.count, by: 3)), id: \.self) { index in
                            tiles[index]
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                }
            }
            caption(.plus, "Log")
                .padding(.top, 10)
            HStack(spacing: 14) {
                ForEach(VentusKind.allCases) { kind in
                    Button { log(kind) } label: {
                        tileBody(glyph: Ventus.glyph(kind), title: kind.label, sub: nil, height: 96)
                            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Ventus.line, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func caption(_ glyph: VentusGlyph, _ text: String) -> some View {
        HStack(spacing: 8) {
            VentusIcon(glyph, color: Ventus.muted, size: 16, weight: 2.4)
            Text(text.uppercased())
                .font(Ventus.font(13, .black))
                .tracking(1.2)
                .foregroundStyle(Ventus.muted)
        }
    }

    private func distinct(_ project: VentusProject, today: String) -> [Pick] {
        var order: [String] = []
        var found: [String: Pick] = [:]
        for day in project.days {
            for item in KairosFit.steps(project.routine, on: day) where KairosPlan.isGuided(item.step) {
                let name = KairosFit.name(item.step)
                if found[name] == nil {
                    order.append(name)
                    found[name] = Pick(step: item.step, day: day, slot: item.slot)
                } else if day <= today {
                    found[name] = Pick(step: item.step, day: day, slot: item.slot)
                }
            }
        }
        return order.compactMap { found[$0] }
    }

    private func sub(_ step: ScheduleStep) -> String {
        let run = KairosPlan.run(step)
        switch KairosPlan.text(run["type"]) {
        case "intervals": return "\(KairosPlan.num(run["on"], 30)) / \(KairosPlan.num(run["off"]))"
        default:
            if let reps = KairosFit.sets(step).first { return "× \(reps)" }
            return Ventus.minutes(KairosPlan.estimate(step))
        }
    }

    private func stepTile(_ pick: Pick) -> some View {
        let glyph = Ventus.glyph(pick.step)
        return Button { startStep(pick.step, pick.day, pick.slot) } label: {
            tileBody(glyph: glyph, tint: Ventus.tint(glyph), title: KairosFit.name(pick.step), sub: sub(pick.step), height: 120)
        }
        .buttonStyle(.plain)
        .help("Guided \(KairosFit.name(pick.step))")
    }

    private var anyDayTile: some View {
        Button(action: anyDay) {
            tileBody(glyph: .scheduled, title: "Any day", sub: project.map { "Day 1–\($0.total)" }, height: 120)
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Ventus.line, lineWidth: 2))
        }
        .buttonStyle(.plain)
    }

    private func tileBody(glyph: VentusGlyph, tint: Color? = nil, title: String, sub: String?, height: CGFloat, dark: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VentusIcon(glyph, color: tint, size: 30)
            Spacer(minLength: 12)
            Text(title)
                .font(Ventus.font(18, .black))
                .foregroundStyle(Ventus.ink)
                .lineLimit(2)
            if let sub {
                Text(sub)
                    .font(Ventus.font(13))
                    .foregroundStyle(Ventus.muted)
                    .lineLimit(1)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Ventus.card))
        .contentShape(RoundedRectangle(cornerRadius: 22))
    }

    @ViewBuilder private func todayTile(_ session: KairosSession?, today: String) -> some View {
        if let session, let project {
            let number = project.dayNumber(today)
            Button { startToday(session) } label: {
                VStack(alignment: .leading, spacing: 0) {
                    VentusDayRing(number: number, fraction: Double(number) / Double(project.total), size: 56, inverted: true)
                    Spacer(minLength: 12)
                    Text(KairosFit.title(session.steps, fallback: project.name))
                        .font(Ventus.font(26, .black))
                        .foregroundStyle(Ventus.onInk)
                        .lineLimit(3)
                    Text(session.finished ? "Done" : Ventus.minutes(session.seconds))
                        .font(Ventus.font(13))
                        .foregroundStyle(Ventus.onInkSoft)
                }
                .padding(20)
                .frame(maxWidth: .infinity, minHeight: 254, maxHeight: 254, alignment: .topLeading)
                .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Ventus.ink))
                .contentShape(RoundedRectangle(cornerRadius: 22))
            }
            .buttonStyle(.plain)
            .disabled(session.finished)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                VentusIcon(.wave, color: Ventus.restText, size: 30)
                Spacer(minLength: 12)
                Text("Rest day")
                    .font(Ventus.font(22, .black))
                    .foregroundStyle(Ventus.muted)
            }
            .padding(20)
            .frame(maxWidth: .infinity, minHeight: 254, maxHeight: 254, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Ventus.card))
        }
    }
}

enum VentusScope: String, CaseIterable, Identifiable {
    case week = "Week"
    case project = "Project"
    case all = "All"

    var id: String { rawValue }
}

struct VentusReviewPage: View {
    @ObservedObject var store: ScheduleStore
    @ObservedObject var journal: KairosJournal
    let projects: [VentusProject]
    let project: VentusProject?
    let pick: (UUID) -> Void
    @State private var scope = VentusScope.project

    private struct Point {
        let day: String
        let minutes: Double
        let state: KairosDayState
    }

    var body: some View {
        let today = store.today
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                VentusProjectMenu(projects: projects, project: project, pick: pick)
                Spacer()
                HStack(spacing: 0) {
                    ForEach(VentusScope.allCases) { item in
                        Button {
                            scope = item
                            note("kairos review scope=\(item.rawValue.lowercased())")
                        } label: {
                            Text(item.rawValue)
                                .font(Ventus.font(14))
                                .foregroundStyle(scope == item ? Ventus.ink : Ventus.muted)
                                .padding(.horizontal, 14)
                                .frame(height: 32)
                                .background(Capsule().fill(scope == item ? Ventus.card : Color.clear))
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(4)
                .background(Capsule().fill(Ventus.rail))
            }
            if let project {
                content(project, today: today)
            } else {
                VentusCard {
                    Text("No fitness routine")
                        .font(Ventus.font(22, .black))
                        .foregroundStyle(Ventus.muted)
                        .frame(maxWidth: .infinity, minHeight: 120)
                }
            }
        }
    }

    private func pool(_ project: VentusProject, today: String) -> [(project: VentusProject, day: String)] {
        switch scope {
        case .week:
            let monday = KairosFit.monday(today)
            return KairosFit.range(monday, ScheduleDays.shift(monday, by: 6))
                .filter { $0 >= project.start && $0 <= project.end }
                .map { (project: project, day: $0) }
        case .project:
            return project.days.map { (project: project, day: $0) }
        case .all:
            return projects.flatMap { item in item.days.map { (project: item, day: $0) } }
        }
    }

    @ViewBuilder private func content(_ project: VentusProject, today: String) -> some View {
        let pairs = pool(project, today: today)
        let states = pairs.map { (pair: $0, state: $0.project.status($0.day, today: today)) }.filter { $0.state != .off }
        let elapsed = states.filter { $0.pair.day < today || ($0.pair.day == today && $0.state == .done) }
        let done = elapsed.filter { $0.state == .done }.count
        let ticked = pairs.filter { $0.day <= today }.reduce(0) { $0 + $1.project.doneSeconds($1.day) }
        let days = Set(pairs.map { "\($0.project.id.uuidString)|\($0.day)" })
        let scoped = scope == .all ? projects : [project]
        let logged = scoped.flatMap { $0.workouts(journal) }.filter { days.contains("\($0.routine.uppercased())|\($0.day)") || scope == .all }
        let seconds = ticked + Int(logged.reduce(0) { $0 + ($1.seconds ?? 0) })
        let goals = scoped.reduce(0) { $0 + $1.achieved.count }
        let targets = scoped.reduce(0) { $0 + $1.targets.count }
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                stat("\(done)", of: "\(elapsed.count)", caption: "days", glyph: nil)
                stat("\(project.streak(today))", of: nil, caption: "streak", glyph: .flame)
                stat(Ventus.hours(seconds), of: nil, caption: "moving", glyph: nil)
                stat("\(goals)", of: "\(targets)", caption: "goals", glyph: .flag)
            }
            HStack(alignment: .top, spacing: 14) {
                heatmap(project, today: today)
                    .frame(width: 300)
                chart(project, today: today)
                    .frame(maxWidth: .infinity)
                VStack(spacing: 14) {
                    ForEach(Array(project.targets.enumerated()), id: \.offset) { index, target in
                        goal(project, index: index, target: target)
                    }
                    feel(project)
                }
                .frame(width: 270)
            }
            runs(project)
        }
    }

    private func stat(_ value: String, of: String?, caption: String, glyph: VentusGlyph?) -> some View {
        VentusCard(radius: 22, padding: 20) {
            VStack(alignment: .leading, spacing: 2) {
                (Text(value).font(Ventus.font(38, .black)).foregroundColor(Ventus.ink)
                    + Text(of.map { "/\($0)" } ?? "").font(Ventus.font(20, .black)).foregroundColor(Ventus.muted))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                HStack(spacing: 6) {
                    if let glyph { VentusIcon(glyph, color: glyph == .flame ? Ventus.hot : Ventus.muted, size: 15, weight: 2.4) }
                    Text(caption).font(Ventus.font(13)).foregroundStyle(Ventus.muted)
                }
            }
        }
    }

    private func heatmap(_ project: VentusProject, today: String) -> some View {
        let first = KairosFit.monday(project.start)
        let cells = KairosFit.range(first, project.end)
        let rows = Int((Double(cells.count) / 7).rounded(.up))
        let marks = Dictionary(project.milestones.map { ($0.day, $0) }, uniquingKeysWith: { a, _ in a })
        let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 7)
        return VentusCard(radius: 22, padding: 20) {
            VStack(alignment: .leading, spacing: 10) {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(0..<7, id: \.self) { offset in
                        Text(Ventus.letter(ScheduleDays.shift(first, by: offset)))
                            .font(Ventus.font(12))
                            .foregroundStyle(Ventus.muted)
                    }
                    ForEach(0..<(rows * 7), id: \.self) { index in
                        let day = ScheduleDays.shift(first, by: index)
                        cell(project, day: day, today: today, mark: marks[day])
                            .help(Ventus.tag(day))
                    }
                }
                Spacer(minLength: 8)
                HStack(spacing: 14) {
                    legend(Ventus.ink, outline: nil, "done")
                    legend(Ventus.rest, outline: nil, "rest")
                    legend(.clear, outline: Ventus.ink, project.milestones.first?.label.lowercased() ?? "goal")
                    legend(.clear, outline: Ventus.hot, "end")
                }
                .font(Ventus.font(12))
                .foregroundStyle(Ventus.muted)
            }
        }
    }

    private func legend(_ fill: Color, outline: Color?, _ label: String) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 4)
                .fill(fill)
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(outline ?? .clear, lineWidth: 2))
                .frame(width: 12, height: 12)
            Text(label).lineLimit(1)
        }
    }

    private func cell(_ project: VentusProject, day: String, today: String, mark: VentusMilestone?) -> some View {
        let inside = day >= project.start && day <= project.end
        let state = inside ? project.state(day, today: today) : KairosDayState.off
        let fill: Color
        switch state {
        case .done: fill = Ventus.ink
        case .part: fill = Ventus.ink.opacity(0.45)
        case .rest: fill = day > today ? Ventus.rest.opacity(0.35) : Ventus.rest
        case .missed: fill = .clear
        case .future, .open: fill = Ventus.rail
        case .off: fill = inside ? Ventus.rail : .clear
        }
        let outline: Color = day == project.end ? Ventus.hot : mark != nil ? Ventus.ink : state == .missed ? Ventus.line : day == today ? Ventus.ink : .clear
        let width: CGFloat = day == today ? 3 : 2
        return RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(fill)
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(outline, lineWidth: width))
            .aspectRatio(1, contentMode: .fit)
    }

    private func points(_ project: VentusProject, today: String) -> [Point] {
        project.days.filter { $0 <= today }.map { day in
            Point(day: day, minutes: Double(project.doneSeconds(day)) / 60, state: project.state(day, today: today))
        }
        .filter { $0.state != .off }
    }

    private func chart(_ project: VentusProject, today: String) -> some View {
        let list = points(project, today: today)
        let top = max(15, (list.map(\.minutes).max() ?? 0).rounded(.up))
        let step = max(5, (top / 3).rounded(.up))
        let ceiling = step * 3
        return VentusCard(radius: 22, padding: 20) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Work per session").font(Ventus.font(16, .black)).foregroundStyle(Ventus.ink)
                    Spacer()
                    Text("min").font(Ventus.font(14)).foregroundStyle(Ventus.muted)
                }
                GeometryReader { geo in
                    let left: CGFloat = 26
                    let width = max(1, geo.size.width - left - 10)
                    let height = max(1, geo.size.height - 12)
                    let gap = list.count > 1 ? width / CGFloat(list.count - 1) : 0
                    let x = { (index: Int) -> CGFloat in left + (list.count > 1 ? gap * CGFloat(index) : width / 2) }
                    let y = { (value: Double) -> CGFloat in 6 + height * CGFloat(1 - min(1, value / ceiling)) }
                    ZStack(alignment: .topLeading) {
                        ForEach(0..<4, id: \.self) { mark in
                            let value = step * Double(mark)
                            Path { path in
                                path.move(to: CGPoint(x: left, y: y(value)))
                                path.addLine(to: CGPoint(x: geo.size.width, y: y(value)))
                            }
                            .stroke(Ventus.rail, lineWidth: 1)
                            Text("\(Int(value))")
                                .font(Ventus.font(11, .bold))
                                .foregroundStyle(Ventus.muted)
                                .position(x: 8, y: y(value))
                        }
                        Path { path in
                            var open = false
                            for (index, point) in list.enumerated() {
                                guard point.state != .rest, point.state != .missed, point.minutes > 0 else {
                                    open = false
                                    continue
                                }
                                let spot = CGPoint(x: x(index), y: y(point.minutes))
                                if open { path.addLine(to: spot) } else { path.move(to: spot) }
                                open = true
                            }
                        }
                        .stroke(Ventus.ink, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                        ForEach(Array(list.enumerated()), id: \.offset) { index, point in
                            marker(point)
                                .position(x: x(index), y: y(point.state == .rest || point.state == .missed ? 0 : point.minutes))
                                .help("\(Ventus.tag(point.day)) · \(Int(point.minutes.rounded())) min")
                        }
                    }
                }
                .frame(minHeight: 200)
            }
        }
    }

    @ViewBuilder private func marker(_ point: Point) -> some View {
        switch point.state {
        case .rest:
            Circle().fill(Ventus.rest).frame(width: 10, height: 10)
        case .missed:
            Circle().fill(Ventus.card).overlay(Circle().strokeBorder(Ventus.line, lineWidth: 2)).frame(width: 10, height: 10)
        default:
            if point.minutes > 0 {
                Circle().fill(Ventus.ink).frame(width: 9, height: 9)
            } else {
                Circle().fill(Ventus.card).overlay(Circle().strokeBorder(Ventus.line, lineWidth: 2)).frame(width: 10, height: 10)
            }
        }
    }

    private func goal(_ project: VentusProject, index: Int, target: String) -> some View {
        let reached = project.achieved.contains(index)
        let best = project.best(index, journal)
        let lower = target.lowercased()
        let shown = best.map { value -> String in
            lower.contains("km") || lower.contains("run") ? "\(KairosEntry.number((value * 100).rounded() / 100)) km" : "\(Int(value))"
        }
        return Button {
            var changed = project
            if reached { changed.achieved.remove(index) } else { changed.achieved.insert(index) }
            changed.save(journal, reason: reached ? "goal unmarked index=\(index)" : "goal achieved index=\(index)")
        } label: {
            VentusCard(radius: 22, padding: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(target).font(Ventus.font(15, .black)).foregroundStyle(Ventus.ink).lineLimit(1)
                        Spacer(minLength: 6)
                        if reached { VentusIcon(.check, size: 18, weight: 2.6) }
                    }
                    VentusBar(fraction: project.progress(index, journal), height: 12, fill: reached ? Ventus.ink : Ventus.hot)
                    Text("best · \(shown ?? "—")")
                        .font(Ventus.font(12))
                        .foregroundStyle(Ventus.muted)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 22))
        }
        .buttonStyle(.plain)
        .help(reached ? "Mark as not reached" : "Mark as reached")
    }

    private func feel(_ project: VentusProject) -> some View {
        let values = project.feels(journal)
        let average = values.isEmpty ? nil : Double(values.reduce(0, +)) / Double(values.count)
        return VentusCard(radius: 22, padding: 20) {
            HStack(spacing: 10) {
                VentusIcon(.heart, color: Ventus.muted, size: 22)
                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(index == values.count - 1 ? Ventus.ink : Ventus.line)
                            .frame(height: max(4, 34 * CGFloat(value) / 5))
                            .frame(maxWidth: .infinity)
                    }
                    if values.isEmpty { Spacer() }
                }
                .frame(height: 34, alignment: .bottom)
                .frame(maxWidth: .infinity)
                Text(average.map { String(format: "%.1f", $0) } ?? "—")
                    .font(Ventus.font(22, .black))
                    .foregroundStyle(Ventus.ink)
            }
        }
    }

    @ViewBuilder private func runs(_ project: VentusProject) -> some View {
        let list = (scope == .all ? projects.flatMap { $0.runs(journal) } : project.runs(journal)).prefix(12)
        if !list.isEmpty {
            VentusCard(radius: 22, padding: 20) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 8) {
                        VentusIcon(.run, size: 18)
                        Text("Runs").font(Ventus.font(16, .black)).foregroundStyle(Ventus.ink)
                    }
                    .padding(.bottom, 8)
                    ForEach(Array(list.enumerated()), id: \.offset) { _, entry in
                        HStack(spacing: 14) {
                            Text(Ventus.tag(entry.day)).font(Ventus.font(14)).foregroundStyle(Ventus.muted).frame(width: 70, alignment: .leading)
                            Text(entry.km.map { "\(KairosEntry.number($0)) km" } ?? "—").font(Ventus.font(15)).frame(width: 80, alignment: .leading)
                            Text(entry.seconds.map { KairosPlan.clock($0) } ?? "—").font(Ventus.font(15)).monospacedDigit().frame(width: 70, alignment: .leading)
                            if let km = entry.km, km > 0, let seconds = entry.seconds {
                                Text("\(KairosPlan.clock(seconds / km)) /km").font(Ventus.font(14, .bold)).foregroundStyle(Ventus.muted)
                            }
                            Spacer()
                        }
                        .foregroundStyle(Ventus.ink)
                        .padding(.vertical, 8)
                        .overlay(alignment: .top) { Rectangle().fill(Ventus.rail).frame(height: 1) }
                    }
                }
            }
        }
    }
}

struct VentusProjectEditor: View {
    @ObservedObject var journal: KairosJournal
    let project: VentusProject
    let close: () -> Void
    @State private var name = ""
    @State private var goal = ""
    @State private var start = Date()
    @State private var end = Date()
    @State private var targets: [String] = []
    @State private var marks: [(day: Date, label: String)] = []
    @State private var loaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Project").font(Ventus.font(24, .black)).foregroundStyle(Ventus.ink)
                Spacer()
                VentusRoundButton(glyph: .close, help: "Close", size: 34, action: close)
                    .keyboardShortcut(.cancelAction)
            }
            field("Name", text: $name)
            field("Goal", text: $goal)
            HStack(spacing: 12) {
                dateField("Start", $start)
                dateField("Goal date", $end)
            }
            section("Targets", glyph: .flag) {
                targets.append("")
            } content: {
                ForEach(targets.indices, id: \.self) { index in
                    HStack(spacing: 8) {
                        TextField("Run 1 km", text: Binding(get: { targets.indices.contains(index) ? targets[index] : "" },
                                                            set: { if targets.indices.contains(index) { targets[index] = $0 } }))
                            .textFieldStyle(.plain)
                            .font(Ventus.font(15, .bold))
                            .padding(.horizontal, 14)
                            .frame(height: 38)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Ventus.ground))
                        remove { if targets.indices.contains(index) { targets.remove(at: index) } }
                    }
                }
            }
            section("Milestones", glyph: .gym) {
                marks.append((day: end, label: ""))
            } content: {
                ForEach(marks.indices, id: \.self) { index in
                    HStack(spacing: 8) {
                        DatePicker("", selection: Binding(get: { marks.indices.contains(index) ? marks[index].day : end },
                                                          set: { if marks.indices.contains(index) { marks[index].day = $0 } }),
                                   displayedComponents: .date)
                            .labelsHidden()
                            .datePickerStyle(.field)
                            .frame(width: 130)
                        TextField("Gym", text: Binding(get: { marks.indices.contains(index) ? marks[index].label : "" },
                                                       set: { if marks.indices.contains(index) { marks[index].label = $0 } }))
                            .textFieldStyle(.plain)
                            .font(Ventus.font(15, .bold))
                            .padding(.horizontal, 14)
                            .frame(height: 38)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Ventus.ground))
                        remove { if marks.indices.contains(index) { marks.remove(at: index) } }
                    }
                }
            }
            Button(action: save) {
                Text("Save").frame(maxWidth: .infinity)
            }
            .buttonStyle(VentusPill(dark: true, size: 17, height: 48))
            .keyboardShortcut("s", modifiers: .command)
        }
        .padding(26)
        .frame(width: 520)
        .background(Ventus.card)
        .appTheme(KairosBoard.theme)
        .onAppear(perform: load)
    }

    private func field(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(Ventus.font(12)).foregroundStyle(Ventus.muted)
            TextField(label, text: text)
                .textFieldStyle(.plain)
                .font(Ventus.font(18, .black))
                .foregroundStyle(Ventus.ink)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 16).fill(Ventus.ground))
    }

    private func dateField(_ label: String, _ value: Binding<Date>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(Ventus.font(12)).foregroundStyle(Ventus.muted)
            DatePicker("", selection: value, displayedComponents: .date)
                .labelsHidden()
                .datePickerStyle(.field)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(Ventus.ground))
    }

    private func section<Content: View>(_ title: String, glyph: VentusGlyph, add: @escaping () -> Void, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                VentusIcon(glyph, color: Ventus.muted, size: 16, weight: 2.4)
                Text(title.uppercased()).font(Ventus.font(12, .black)).tracking(1.2).foregroundStyle(Ventus.muted)
                Spacer()
                Button(action: add) { VentusIcon(.plus, size: 16, weight: 2.4).frame(width: 28, height: 28).background(Circle().fill(Ventus.ground)) }
                    .buttonStyle(.plain)
                    .help("Add")
            }
            content()
        }
    }

    private func remove(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VentusIcon(.close, color: Ventus.muted, size: 14, weight: 2.4)
                .frame(width: 30, height: 30)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("Remove")
    }

    private func load() {
        guard !loaded else { return }
        name = project.name
        goal = project.goal
        start = ScheduleDays.date(project.start) ?? Date()
        end = ScheduleDays.date(project.end) ?? start
        targets = project.targets
        marks = project.milestones.map { (day: ScheduleDays.date($0.day) ?? end, label: $0.label) }
        loaded = true
    }

    private func save() {
        var changed = project
        let reached = Set(project.achieved.compactMap { project.targets.indices.contains($0) ? project.targets[$0] : nil })
        let first = ScheduleDays.key(start)
        let last = ScheduleDays.key(end)
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        changed.name = trimmed.isEmpty ? project.routine.name : trimmed
        changed.goal = goal.trimmingCharacters(in: .whitespacesAndNewlines)
        changed.start = min(first, last)
        changed.end = max(first, last)
        changed.targets = targets.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        changed.achieved = Set(changed.targets.indices.filter { reached.contains(changed.targets[$0]) })
        changed.milestones = marks
            .map { VentusMilestone(day: ScheduleDays.key($0.day), label: $0.label.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { !$0.label.isEmpty }
            .sorted { $0.day < $1.day }
        changed.save(journal, reason: "editor")
        close()
    }
}

struct VentusLogRequest: Identifiable {
    let id = UUID()
    let kind: VentusKind
}

struct VentusLogSheet: View {
    @ObservedObject var journal: KairosJournal
    let projects: [VentusProject]
    let project: VentusProject?
    let first: VentusKind
    let today: String
    let close: () -> Void
    @State private var kind = VentusKind.run
    @State private var day = Date()
    @State private var routine: UUID?
    @State private var time = ""
    @State private var km = ""
    @State private var skips = ""
    @State private var sets = ""
    @State private var feel = 0
    @State private var notes = ""
    @State private var picking = false
    @State private var loaded = false

    private var chosen: VentusProject? { projects.first { $0.id == routine } ?? project }

    private var seconds: Double? {
        let trimmed = time.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.contains(":") {
            let parts = trimmed.split(separator: ":", omittingEmptySubsequences: false).map { Double($0.trimmingCharacters(in: .whitespaces)) }
            guard parts.count == 2, let minutes = parts[0], let rest = parts[1], minutes >= 0, rest >= 0, rest < 60 else { return nil }
            let total = minutes * 60 + rest
            return total > 0 && total < 86_400 ? total : nil
        }
        guard let minutes = Double(trimmed.replacingOccurrences(of: ",", with: ".")), minutes > 0, minutes < 1_440 else { return nil }
        return (minutes * 60).rounded()
    }

    private var distance: Double? {
        guard let value = Double(km.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")), value > 0, value < 500 else { return nil }
        return (value * 100).rounded() / 100
    }

    private var count: Int? {
        guard let value = Int(skips.trimmingCharacters(in: .whitespaces)), value > 0, value < 1_000_000 else { return nil }
        return value
    }

    private var setCount: Int? {
        guard let value = Int(sets.trimmingCharacters(in: .whitespaces)), value > 0, value < 1_000 else { return nil }
        return value
    }

    private var ready: Bool {
        guard chosen != nil else { return false }
        switch kind {
        case .run, .walk: return seconds != nil || distance != nil
        case .rope: return count != nil || seconds != nil
        case .gym, .other: return seconds != nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 8) {
                Text("Log").font(Ventus.font(24, .black)).foregroundStyle(Ventus.ink)
                Spacer()
                Button {
                    picking = true
                } label: {
                    Text(ScheduleDays.key(day) == today ? "Today" : Ventus.tag(ScheduleDays.key(day)))
                        .font(Ventus.font(14))
                        .foregroundStyle(Ventus.ink)
                        .padding(.horizontal, 14)
                        .frame(height: 32)
                        .background(Capsule().fill(Ventus.ground))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .popover(isPresented: $picking, arrowEdge: .bottom) {
                    DatePicker("", selection: Binding(get: { day }, set: { picked in
                        day = min(picked, Date())
                        picking = false
                    }), displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .labelsHidden()
                        .padding(12)
                }
                Menu {
                    ForEach(projects) { item in
                        Button(item.name) { routine = item.id }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(chosen?.name ?? "No project").lineLimit(1)
                        Image(systemName: "chevron.down").font(.system(size: 10, weight: .heavy))
                    }
                    .font(Ventus.font(14))
                    .foregroundStyle(Ventus.ink)
                    .padding(.horizontal, 14)
                    .frame(height: 32)
                    .background(Capsule().fill(Ventus.ground))
                    .contentShape(Capsule())
                }
                .menuStyle(.button)
                .menuIndicator(.hidden)
                .buttonStyle(.plain)
                .fixedSize()
                VentusRoundButton(glyph: .close, help: "Close", size: 32, action: close)
                    .keyboardShortcut(.cancelAction)
            }
            HStack(spacing: 4) {
                ForEach(VentusKind.allCases) { item in
                    Button {
                        kind = item
                    } label: {
                        VStack(spacing: 4) {
                            VentusIcon(Ventus.glyph(item), color: kind == item ? Ventus.ink : Ventus.muted, size: 22)
                            Text(item.label).font(Ventus.font(14))
                        }
                        .foregroundStyle(kind == item ? Ventus.ink : Ventus.muted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 12).fill(kind == item ? Ventus.card : Color.clear))
                        .contentShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(5)
            .background(RoundedRectangle(cornerRadius: 16).fill(Ventus.ground))
            fields
            HStack(spacing: 10) {
                VentusIcon(.heart, color: Ventus.muted, size: 22)
                ForEach(1...5, id: \.self) { value in
                    Button {
                        feel = feel == value ? 0 : value
                    } label: {
                        Text("\(value)")
                            .font(Ventus.font(16, .black))
                            .foregroundStyle(feel == value ? Ventus.onInk : Ventus.ink)
                            .frame(width: 46, height: 46)
                            .background(Circle().fill(feel == value ? Ventus.ink : Ventus.ground))
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
            TextField("Notes", text: $notes)
                .textFieldStyle(.plain)
                .font(Ventus.font(16, .bold))
                .foregroundStyle(Ventus.ink)
                .padding(.horizontal, 18)
                .frame(height: 50)
                .background(RoundedRectangle(cornerRadius: 18).fill(Ventus.ground))
            Button(action: save) {
                Text("Save").frame(maxWidth: .infinity)
            }
            .buttonStyle(VentusPill(dark: true, size: 17, height: 50))
            .disabled(!ready)
            .opacity(ready ? 1 : 0.45)
            .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(26)
        .frame(width: 560)
        .background(Ventus.card)
        .appTheme(KairosBoard.theme)
        .onAppear {
            guard !loaded else { return }
            kind = first
            routine = project?.id
            day = ScheduleDays.date(today) ?? Date()
            loaded = true
        }
    }

    @ViewBuilder private var fields: some View {
        HStack(spacing: 12) {
            switch kind {
            case .run, .walk:
                box("min", $time, hint: "18:00")
                box("km", $km, hint: "2.1")
                VStack(alignment: .leading, spacing: 2) {
                    Text("pace").font(Ventus.font(12)).foregroundStyle(Ventus.muted)
                    Text(seconds.flatMap { s in distance.map { KairosPlan.clock(s / $0) } } ?? "—")
                        .font(Ventus.font(34, .black))
                        .monospacedDigit()
                        .foregroundStyle(Ventus.muted)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
            case .rope:
                box("skips", $skips, hint: "300")
                box("sets", $sets, hint: "6")
                box("min", $time, hint: "6")
            case .gym, .other:
                box("min", $time, hint: "45")
            }
        }
    }

    private func box(_ label: String, _ value: Binding<String>, hint: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(Ventus.font(12)).foregroundStyle(Ventus.muted)
            TextField(hint, text: value)
                .textFieldStyle(.plain)
                .font(Ventus.font(34, .black))
                .monospacedDigit()
                .foregroundStyle(Ventus.ink)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18).fill(Ventus.ground))
    }

    private func save() {
        guard ready, let target = chosen else { return note("kairos log refused kind=\(kind.rawValue) cause=incomplete") }
        let id = "workout|\(UUID().uuidString)"
        let key = min(ScheduleDays.key(day), today)
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        var entry = KairosEntry(id: id, routine: target.routine.id.uuidString, routineName: target.routine.name, day: key, slot: "",
                                step: kind.rawValue, title: kind.label, tag: "workout")
        entry.seconds = seconds
        if kind.distance { entry.km = distance }
        if kind == .rope {
            entry.text = count.map(String.init)
            entry.lines = setCount.map { ["\($0)"] }
        }
        entry.feel = feel > 0 ? "\(feel)" : nil
        entry.notes = trimmed.isEmpty ? nil : trimmed
        journal.put(entry)
        note("kairos workout logged id=\(id) kind=\(kind.rawValue) routine=\(target.routine.name) day=\(key) seconds=\(Int(entry.seconds ?? 0)) km=\(entry.km.map(KairosEntry.number) ?? "-") count=\(entry.text ?? "-") feel=\(entry.feel ?? "-")")
        close()
    }
}
