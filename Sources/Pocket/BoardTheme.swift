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
            backdrop: base(34, 11), sidebar: base(36, 8.5), card: base(28, 15.5), line: base(22, 23),
            ink: lit(40, 93), muted: base(18, 70), faint: base(14, 48),
            accent: lit(62, 76), accentInk: lit(70, 81), shadow: Color.black.opacity(0.45),
            pill: base(26, 20),
            swatch: base(34, 14), swatchEdge: lit(50, 62), swatchRing: lit(70, 81),
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
        dusk("moonlit-sage", "Moonlit Sage", ground: 160, glow: 140),
        dusk("harbour", "Harbour", ground: 218, glow: 24),
        dusk("aurora", "Aurora", ground: 268, glow: 158),
        dusk("nocturne", "Nocturne", ground: 242, glow: 268),
        dusk("candlelight", "Candlelight", ground: 345, glow: 44),
        dusk("mint-cocoa", "Mint Cocoa", ground: 22, glow: 156, depth: 0.9),
        dusk("coral-reef", "Coral Reef", ground: 192, glow: 12),
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

struct BoardBackdrop: View {
    let theme: BoardTheme

    var body: some View {
        theme.backdrop
    }
}

extension View {
    func boardEdge(_ radius: CGFloat, color: Color = Board.line, width: CGFloat = 1) -> some View {
        overlay(RoundedRectangle(cornerRadius: radius).stroke(color, lineWidth: width))
    }
}

final class ThemedHostingView<Content: View>: NSHostingView<Content> {
    private var themeWatch: AnyCancellable?

    required init(rootView: Content) {
        super.init(rootView: rootView)
        appearance = BoardThemeStore.shared.theme.appearance
        themeWatch = BoardThemeStore.shared.$theme.sink { [weak self] theme in self?.appearance = theme.appearance }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }
}
