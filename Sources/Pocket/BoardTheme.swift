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
}

struct BoardTheme: Identifiable, Equatable {
    let id: String
    let name: String
    let hue: Double
    let saturation: Double

    static let all = [
        BoardTheme(id: "sage", name: "Sage", hue: 145, saturation: 1),
        BoardTheme(id: "rose", name: "Rose", hue: 356, saturation: 1),
        BoardTheme(id: "butter", name: "Butter", hue: 46, saturation: 1.15),
        BoardTheme(id: "apricot", name: "Apricot", hue: 24, saturation: 1.05),
        BoardTheme(id: "sky", name: "Sky", hue: 205, saturation: 1),
        BoardTheme(id: "lavender", name: "Lavender", hue: 262, saturation: 0.95),
        BoardTheme(id: "blush", name: "Blush", hue: 328, saturation: 0.9),
        BoardTheme(id: "stone", name: "Stone", hue: 32, saturation: 0.28),
    ]

    static let projectOffsets: [Double] = [0, -32, 34, -64, 66, -98, 100, 180]

    private func tone(_ saturation: Double, _ lightness: Double, _ alpha: Double = 1) -> Color {
        Color(hue: hue, saturation: min(100, saturation * self.saturation), lightness: lightness, alpha: alpha)
    }

    var backdrop: Color { tone(45, 92.5) }
    var sidebar: Color { tone(42, 89) }
    var card: Color { tone(55, 96) }
    var line: Color { tone(30, 81.5) }
    var ink: Color { tone(34, 16) }
    var muted: Color { tone(18, 35) }
    var faint: Color { tone(16, 62) }
    var accent: Color { tone(48, 54) }
    var accentInk: Color { tone(52, 32) }
    var shadow: Color { tone(34, 26, 0.1) }

    var swatch: Color { tone(46, 84) }
    var swatchEdge: Color { tone(46, 72) }
    var swatchRing: Color { tone(46, 46) }

    func projectTint(_ index: Int) -> Color {
        let offset = Self.projectOffsets[((index % Self.projectOffsets.count) + Self.projectOffsets.count) % Self.projectOffsets.count]
        return Color(hue: hue + offset, saturation: max(18, min(100, 34 * saturation)), lightness: offset == 0 ? 50 : 56)
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
