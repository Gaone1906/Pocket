import AppKit
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
    let metal: [Color]?

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
            },
            metal: nil
        )
    }

    static let bronze = BoardTheme(
        id: "bronze", name: "Bronze", isDark: true,
        backdrop: Color(hex: 0x1D1E21), sidebar: Color(hex: 0x17181A), card: Color(hex: 0x26272B), line: Color(hex: 0x37383D),
        ink: Color(hex: 0xEDE7DF), muted: Color(hex: 0x9C968E), faint: Color(hex: 0x5F5C58),
        accent: Color(hex: 0xC8925A), accentInk: Color(hex: 0xD9A86C), shadow: Color.black.opacity(0.45),
        pill: Color(hex: 0x34353A),
        swatch: Color(hex: 0x2A2B2F), swatchEdge: Color(hex: 0xA8743F), swatchRing: Color(hex: 0xD9A86C),
        projectTints: [0xC08A52, 0xB8704A, 0xC9A55A, 0xD8C3A0, 0x9EA3A8, 0xC98F84, 0x8A949E, 0xD4AF37].map { Color(hex: $0) },
        metal: [0x6E4421, 0xB07D45, 0xF3D2A2, 0xC8925A, 0x7A4E26, 0xA8743F].map { Color(hex: $0) }
    )

    static let all = [
        pastel("sage", "Sage", hue: 145, saturation: 1),
        pastel("rose", "Rose", hue: 356, saturation: 1),
        pastel("butter", "Butter", hue: 46, saturation: 1.15),
        pastel("apricot", "Apricot", hue: 24, saturation: 1.05),
        pastel("sky", "Sky", hue: 205, saturation: 1),
        pastel("lavender", "Lavender", hue: 262, saturation: 0.95),
        pastel("blush", "Blush", hue: 328, saturation: 0.9),
        pastel("stone", "Stone", hue: 32, saturation: 0.28),
        bronze,
    ]

    var colorScheme: ColorScheme { isDark ? .dark : .light }
    var appearance: NSAppearance? { NSAppearance(named: isDark ? .darkAqua : .aqua) }

    var accentStyle: AnyShapeStyle {
        guard let metal else { return AnyShapeStyle(accent) }
        return AnyShapeStyle(LinearGradient(colors: metal, startPoint: .topLeading, endPoint: .bottomTrailing))
    }

    var accentInkStyle: AnyShapeStyle {
        guard let metal else { return AnyShapeStyle(accentInk) }
        return AnyShapeStyle(LinearGradient(colors: metal, startPoint: .top, endPoint: .bottom))
    }

    var swatchStyle: AnyShapeStyle {
        guard let metal else { return AnyShapeStyle(swatch) }
        return AnyShapeStyle(AngularGradient(colors: [swatch, swatch] + metal + [swatch], center: .center, startAngle: .degrees(200), endAngle: .degrees(560)))
    }

    func projectTint(_ index: Int) -> Color {
        projectTints[((index % projectTints.count) + projectTints.count) % projectTints.count]
    }

    private static func blend(_ base: Color, _ other: NSColor, _ fraction: CGFloat) -> Color {
        Color(nsColor: NSColor(base).usingColorSpace(.sRGB)?.blended(withFraction: fraction, of: other) ?? NSColor(base))
    }

    func sheen(_ tint: Color) -> AnyShapeStyle {
        guard metal != nil else { return AnyShapeStyle(tint) }
        return AnyShapeStyle(LinearGradient(stops: [
            .init(color: Self.blend(tint, .black, 0.35), location: 0),
            .init(color: Self.blend(tint, .white, 0.55), location: 0.35),
            .init(color: tint, location: 0.6),
            .init(color: Self.blend(tint, .black, 0.3), location: 1),
        ], startPoint: .top, endPoint: .bottom))
    }
}

final class BoardThemeStore: ObservableObject {
    static let shared = BoardThemeStore()
    private static let key = "pomodoro.board.theme"

    @Published var theme: BoardTheme {
        didSet {
            guard theme != oldValue else { return }
            UserDefaults.standard.set(theme.id, forKey: Self.key)
            note("pomodoro board theme=\(theme.id) previous=\(oldValue.id)")
        }
    }

    private init() {
        let saved = UserDefaults.standard.string(forKey: Self.key)
        theme = BoardTheme.all.first { $0.id == saved } ?? BoardTheme.all[0]
    }
}
