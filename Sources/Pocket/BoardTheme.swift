import AppKit
import Combine
import SwiftUI

extension Color {
    init(hue: Double, saturation: Double, lightness: Double, alpha: Double = 1) {
        let s = saturation / 100
        let l = lightness / 100
        let chroma = (1 - abs(2 * l - 1)) * s
        let sector = (hue.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) / 60
        let x = chroma * (1 - abs(sector.truncatingRemainder(dividingBy: 2) - 1))
        let (r, g, b): (Double, Double, Double)
        switch sector {
        case ..<1: (r, g, b) = (chroma, x, 0)
        case ..<2: (r, g, b) = (x, chroma, 0)
        case ..<3: (r, g, b) = (0, chroma, x)
        case ..<4: (r, g, b) = (0, x, chroma)
        case ..<5: (r, g, b) = (x, 0, chroma)
        default: (r, g, b) = (chroma, 0, x)
        }
        let m = l - chroma / 2
        self.init(.sRGB, red: r + m, green: g + m, blue: b + m, opacity: alpha)
    }

    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: alpha)
    }
}

struct BoardTheme: Identifiable, Equatable {
    let id: String
    let name: String
    let isDark: Bool
    let backdrop: Color
    let sidebar: Color
    let card: Color
    let line: Color
    let ink: Color
    let muted: Color
    let faint: Color
    let accent: Color
    let accentInk: Color
    let shadow: Color
    let pill: Color
    let swatch: Color
    let swatchEdge: Color
    let swatchRing: Color
    let projectTints: [Color]

    static func == (lhs: BoardTheme, rhs: BoardTheme) -> Bool { lhs.id == rhs.id }

    static let projectOffsets: [Double] = [0, -32, 34, -64, 66, -98, 100, 180]

    static func pastel(_ id: String, _ name: String, hue: Double, saturation factor: Double) -> BoardTheme {
        func tone(_ saturation: Double, _ lightness: Double, _ alpha: Double = 1) -> Color {
            Color(hue: hue, saturation: min(100, saturation * factor), lightness: lightness, alpha: alpha)
        }
        return BoardTheme(
            id: id, name: name, isDark: false,
            backdrop: tone(45, 92.5), sidebar: tone(42, 89), card: tone(55, 96), line: tone(30, 81.5),
            ink: tone(34, 16), muted: tone(18, 35), faint: tone(16, 62),
            accent: tone(48, 54), accentInk: tone(52, 32), shadow: tone(34, 26, 0.1),
            pill: Color.white.opacity(0.85),
            swatch: tone(46, 84), swatchEdge: tone(46, 72), swatchRing: tone(46, 46),
            projectTints: projectOffsets.map { offset in
                Color(hue: hue + offset, saturation: max(18, min(100, 34 * factor)), lightness: offset == 0 ? 50 : 56)
            }
        )
    }

    static func dusk(_ id: String, _ name: String, ground: Double, glow: Double, depth factor: Double = 1) -> BoardTheme {
        func base(_ saturation: Double, _ lightness: Double) -> Color {
            Color(hue: ground, saturation: min(100, saturation * factor), lightness: lightness)
        }
        func lit(_ saturation: Double, _ lightness: Double) -> Color {
            Color(hue: glow, saturation: saturation, lightness: lightness)
        }
        return BoardTheme(
            id: id, name: name, isDark: true,
            backdrop: base(46, 11), sidebar: base(48, 8.5), card: base(36, 15.5), line: base(28, 23),
            ink: lit(40, 93), muted: base(18, 70), faint: base(14, 48),
            accent: lit(62, 76), accentInk: lit(70, 81), shadow: Color.black.opacity(0.45),
            pill: base(32, 20),
            swatch: base(46, 14), swatchEdge: lit(50, 62), swatchRing: lit(70, 81),
            projectTints: projectOffsets.map { Color(hue: glow + $0, saturation: 55, lightness: 74) }
        )
    }

    static let all = [
        pastel("sage", "Sage", hue: 145, saturation: 1),
        pastel("rose", "Rose", hue: 356, saturation: 1),
        pastel("butter", "Butter", hue: 46, saturation: 1.15),
        pastel("apricot", "Apricot", hue: 24, saturation: 1.05),
        pastel("sky", "Sky", hue: 205, saturation: 1),
        pastel("lavender", "Lavender", hue: 262, saturation: 0.95),
        pastel("blush", "Blush", hue: 328, saturation: 0.9),
        pastel("stone", "Stone", hue: 32, saturation: 0.28),
        pastel("ember", "Ember", hue: 354, saturation: 1.55),
        pastel("flint", "Flint", hue: 212, saturation: 0.15),
        dusk("moonlit-sage", "Moonlit Sage", ground: 160, glow: 140),
        dusk("harbour", "Harbour", ground: 218, glow: 24),
        dusk("aurora", "Aurora", ground: 268, glow: 158),
        dusk("nocturne", "Nocturne", ground: 256, glow: 272),
        dusk("candlelight", "Candlelight", ground: 336, glow: 44),
        dusk("mint-cocoa", "Mint Cocoa", ground: 28, glow: 156, depth: 0.7),
        dusk("coral-reef", "Coral Reef", ground: 178, glow: 12),
        dusk("plum-blossom", "Plum Blossom", ground: 302, glow: 334),
    ]

    var family: String { isDark ? "Dark" : "Light" }
    var colorScheme: ColorScheme { isDark ? .dark : .light }
    var appearance: NSAppearance? { NSAppearance(named: isDark ? .darkAqua : .aqua) }
    var accentStyle: AnyShapeStyle { AnyShapeStyle(accent) }
    var accentInkStyle: AnyShapeStyle { AnyShapeStyle(accentInk) }
    var panel: Color { sidebar }

    var swatchStyle: AnyShapeStyle {
        guard isDark else { return AnyShapeStyle(swatch) }
        return AnyShapeStyle(LinearGradient(colors: [swatch, swatch, accent], startPoint: .topLeading, endPoint: .bottomTrailing))
    }

    func projectTint(_ index: Int) -> Color {
        projectTints[((index % projectTints.count) + projectTints.count) % projectTints.count]
    }
}

final class BoardThemeStore: ObservableObject {
    static let shared = BoardThemeStore()
    private static let key = "pomodoro.board.theme"

    @Published var theme: BoardTheme {
        didSet {
            guard theme != oldValue else { return }
            UserDefaults.standard.set(theme.id, forKey: Self.key)
            note("pocket theme changed theme=\(theme.id) previous=\(oldValue.id)")
        }
    }

    private init() {
        let saved = UserDefaults.standard.string(forKey: Self.key)
        theme = BoardTheme.all.first { $0.id == saved } ?? BoardTheme.all[0]
    }
}

struct ThemedApp: Identifiable {
    let id: String
    let name: String
    let fallback: String
}

final class AppThemeStore: ObservableObject {
    static let shared = AppThemeStore()
    private static let prefix = "app.theme."

    static let apps = [
        ThemedApp(id: "schedule", name: "Aqua", fallback: "sky"),
        ThemedApp(id: "pomodoro", name: "Ignis", fallback: "ember"),
        ThemedApp(id: "runner", name: "Ventus", fallback: "flint"),
        ThemedApp(id: "calorie", name: "Terra", fallback: "sage"),
        ThemedApp(id: "sleep", name: "Luna", fallback: "lavender"),
    ]

    @Published private(set) var picks: [String: String]

    private init() {
        var picks: [String: String] = [:]
        for app in Self.apps {
            if let saved = UserDefaults.standard.string(forKey: Self.prefix + app.id), BoardTheme.all.contains(where: { $0.id == saved }) {
                picks[app.id] = saved
            }
        }
        self.picks = picks
    }

    static func isThemed(_ app: String) -> Bool { apps.contains { $0.id == app } }

    func theme(for app: String) -> BoardTheme { Self.resolve(app, in: picks) }

    private static func resolve(_ app: String, in picks: [String: String]) -> BoardTheme {
        guard let entry = apps.first(where: { $0.id == app }) else { return BoardThemeStore.shared.theme }
        let id = picks[app] ?? entry.fallback
        return BoardTheme.all.first { $0.id == id } ?? BoardThemeStore.shared.theme
    }

    func isDefault(_ app: String) -> Bool { picks[app] == nil }

    func set(_ theme: BoardTheme, for app: String) {
        guard let entry = Self.apps.first(where: { $0.id == app }) else { return }
        let previous = self.theme(for: app).id
        let pick = theme.id == entry.fallback ? nil : theme.id
        guard picks[app] != pick else { return }
        picks[app] = pick
        if let pick {
            UserDefaults.standard.set(pick, forKey: Self.prefix + app)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.prefix + app)
        }
        note("pocket app theme changed app=\(app) theme=\(theme.id) previous=\(previous) default=\(entry.fallback)")
        AppDelegate.shared.apps[app]?.changed()
    }

    func publisher(for app: String) -> AnyPublisher<BoardTheme, Never> {
        guard Self.isThemed(app) else { return BoardThemeStore.shared.$theme.eraseToAnyPublisher() }
        return $picks.map { Self.resolve(app, in: $0) }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .eraseToAnyPublisher()
    }

    func iconColor(for app: String, onDark: Bool) -> Color? {
        guard Self.isThemed(app) else { return nil }
        let theme = self.theme(for: app)
        if onDark { return theme.isDark ? theme.accent : theme.swatchEdge }
        return theme.isDark ? theme.swatchEdge : theme.swatchRing
    }
}

protocol BoardScope {
    static var theme: BoardTheme { get }
}

extension BoardScope {
    static var backdrop: Color { theme.backdrop }
    static var sidebar: Color { theme.sidebar }
    static var column: Color { theme.card }
    static var line: Color { theme.line }
    static var muted: Color { theme.muted }
    static var ink: Color { theme.ink }
    static var faint: Color { theme.faint }
    static var accent: Color { theme.accent }
    static var accentInk: Color { theme.accentInk }
    static var accentStyle: AnyShapeStyle { theme.accentStyle }
    static var accentInkStyle: AnyShapeStyle { theme.accentInkStyle }
    static var shadow: Color { theme.shadow }
    static var hueCount: Int { BoardTheme.projectOffsets.count }
    static var glide: Animation { .smooth(duration: 0.3) }

    static func hue(_ index: Int) -> Color { theme.projectTint(index) }
}

enum OrarioBoard: BoardScope {
    static var theme: BoardTheme { AppThemeStore.shared.theme(for: "schedule") }
}

enum AureliusBoard: BoardScope {
    static var theme: BoardTheme { AppThemeStore.shared.theme(for: "pomodoro") }
}

private struct BoardThemeKey: EnvironmentKey {
    static var defaultValue: BoardTheme? { nil }
}

extension EnvironmentValues {
    var boardTheme: BoardTheme? {
        get { self[BoardThemeKey.self] }
        set { self[BoardThemeKey.self] = newValue }
    }
}

extension View {
    func appTheme(_ theme: BoardTheme) -> some View {
        environment(\.boardTheme, theme).environment(\.colorScheme, theme.colorScheme).fontDesign(.rounded)
    }
}

struct BoardBackdrop: View {
    let theme: BoardTheme

    var body: some View {
        theme.backdrop
    }
}

extension View {
    func boardEdge(_ radius: CGFloat, color: Color? = nil, width: CGFloat = 1) -> some View {
        modifier(BoardEdge(radius: radius, color: color, width: width))
    }
}

private struct BoardEdge: ViewModifier {
    let radius: CGFloat
    let color: Color?
    let width: CGFloat
    @Environment(\.boardTheme) private var scoped

    func body(content: Content) -> some View {
        content.overlay(RoundedRectangle(cornerRadius: radius).stroke(color ?? (scoped ?? Board.theme).line, lineWidth: width))
    }
}

final class ThemedHostingView<Content: View>: NSHostingView<Content> {
    private var themeWatch: AnyCancellable?

    required init(rootView: Content) {
        super.init(rootView: rootView)
        watch(app: nil)
    }

    init(rootView: Content, app: String) {
        super.init(rootView: rootView)
        watch(app: app)
    }

    private func watch(app: String?) {
        let source = app.map { AppThemeStore.shared.publisher(for: $0) } ?? BoardThemeStore.shared.$theme.eraseToAnyPublisher()
        appearance = (app.map { AppThemeStore.shared.theme(for: $0) } ?? BoardThemeStore.shared.theme).appearance
        themeWatch = source.sink { [weak self] theme in self?.appearance = theme.appearance }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }
}
