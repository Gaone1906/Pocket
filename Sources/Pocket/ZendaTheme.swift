import AppKit
import SwiftUI

enum Zen {
    static let ink = Color(hex: 0x2B2926)
    static let paper = Color(hex: 0xF3EEE3)
    static let card = Color(hex: 0xF9F5EC)
    static let line = Color(hex: 0xE2DDD2)
    static let rule = Color(hex: 0xE6E1D6)
    static let muted = Color(hex: 0x5E5A53)
    static let pale = Color(hex: 0xEAE3D5)
    static let stone = Color(hex: 0xD3CEC3)
    static let edge = Color(hex: 0xD9D4C8)
    static let mid = Color(hex: 0x8C877E)
    static let empty = Color(hex: 0xDDD8CD)
    static let leaf = Color(hex: 0xFFFDF8)
    static let umber = Color(hex: 0x5A544D)
    static let vermilion = Color(hex: 0xB5452F)

    static func serif(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font { .system(size: size, weight: weight, design: .serif) }
    static func round(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font { .system(size: size, weight: weight, design: .rounded) }

    static let logo: NSImage? = Data(base64Encoded: ZendaLogo.jpeg, options: .ignoreUnknownCharacters).flatMap(NSImage.init(data:))
}

struct ZendaBackdrop: View {
    var body: some View {
        ZStack {
            Zen.paper
            RadialGradient(colors: [Color.white.opacity(0.6), .clear], center: UnitPoint(x: 0.15, y: 0), startRadius: 0, endRadius: 520)
            RadialGradient(colors: [Zen.vermilion.opacity(0.05), .clear], center: UnitPoint(x: 1, y: 1), startRadius: 0, endRadius: 560)
        }
    }
}

struct ZendaEnso: View {
    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            ZStack {
                Circle()
                    .trim(from: 0.02, to: 0.9)
                    .stroke(Zen.ink, style: StrokeStyle(lineWidth: side * 0.085, lineCap: .round))
                    .padding(side * 0.06)
                Circle()
                    .trim(from: 0.12, to: 0.74)
                    .stroke(Zen.ink.opacity(0.7), style: StrokeStyle(lineWidth: side * 0.03, lineCap: .round))
                    .padding(side * 0.02)
                Circle()
                    .trim(from: 0.55, to: 0.97)
                    .stroke(Zen.ink.opacity(0.55), style: StrokeStyle(lineWidth: side * 0.022, lineCap: .round))
                    .padding(side * 0.105)
            }
            .rotationEffect(.degrees(-62))
            .frame(width: side, height: side)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .allowsHitTesting(false)
    }
}

struct ZendaLogoMark: View {
    var side: CGFloat = 52

    var body: some View {
        Group {
            if let logo = Zen.logo {
                Image(nsImage: logo).resizable().interpolation(.high).aspectRatio(contentMode: .fill)
            } else {
                Zen.pale
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: side * 0.27, style: .continuous))
    }
}

struct ZendaFilled: ButtonStyle {
    var height: CGFloat = 52
    var fill: Color = Zen.vermilion
    var size: CGFloat = 17

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Zen.round(size, .bold))
            .foregroundStyle(Zen.paper)
            .padding(.horizontal, 30)
            .frame(height: height)
            .background(Capsule().fill(fill))
            .opacity(configuration.isPressed ? 0.85 : 1)
            .contentShape(Capsule())
    }
}

struct ZendaCircleButton: ButtonStyle {
    var side: CGFloat = 52
    var filled = false
    var stroke: Color = Zen.stone

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(filled ? Zen.paper : Zen.ink)
            .frame(width: side, height: side)
            .background(Circle().fill(filled ? Zen.ink : Color.clear))
            .overlay(Circle().strokeBorder(filled ? Color.clear : stroke, lineWidth: 1.5))
            .opacity(configuration.isPressed ? 0.75 : 1)
            .contentShape(Circle())
    }
}

struct ZendaChip: ButtonStyle {
    var on: Bool
    var height: CGFloat = 32
    var minWidth: CGFloat = 44
    var bordered = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Zen.round(13))
            .lineLimit(1)
            .foregroundStyle(on ? Zen.paper : Zen.ink)
            .padding(.horizontal, 12)
            .frame(minWidth: minWidth)
            .frame(height: height)
            .background(Capsule().fill(on ? Zen.ink : Color.clear))
            .overlay(Capsule().strokeBorder(on ? Zen.ink : bordered ? Zen.stone : Color.clear, lineWidth: 1.5))
            .opacity(configuration.isPressed ? 0.75 : 1)
            .contentShape(Capsule())
    }
}

struct ZendaPill: View {
    let text: String
    var symbol: String? = nil
    var height: CGFloat = 40

    var body: some View {
        HStack(spacing: 8) {
            if let symbol { Image(systemName: symbol).font(.system(size: 15, weight: .medium)) }
            Text(text).lineLimit(1).truncationMode(.tail)
        }
        .font(Zen.round(14))
        .foregroundStyle(Zen.ink)
        .padding(.horizontal, 16)
        .frame(height: height)
        .background(Capsule().fill(Zen.pale))
    }
}

struct ZendaCard: ViewModifier {
    var radius: CGFloat = 22
    var stroke: Color = Zen.line
    var width: CGFloat = 1

    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Zen.card))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(stroke, lineWidth: width))
    }
}

extension View {
    func zendaCard(_ radius: CGFloat = 22, stroke: Color = Zen.line, width: CGFloat = 1) -> some View {
        modifier(ZendaCard(radius: radius, stroke: stroke, width: width))
    }
}

struct ZendaProjectMenu: View {
    let title: String
    let options: [(id: String?, name: String)]
    let pick: (String?) -> Void

    var body: some View {
        Menu {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                Button(option.name) { pick(option.id) }
            }
        } label: {
            HStack(spacing: 10) {
                Text(title).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 13, weight: .bold))
            }
            .font(Zen.round(16, .bold))
            .foregroundStyle(Zen.paper)
            .padding(.leading, 18)
            .padding(.trailing, 16)
            .frame(height: 44)
            .background(Capsule().fill(Zen.ink))
            .contentShape(Capsule())
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .fixedSize()
    }
}
