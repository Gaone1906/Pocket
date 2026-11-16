import AppKit
import SwiftUI

struct Embroidery {
    let tiger: String
    let dragon: String
    let tigerThread: Color
    let dragonThread: Color
    let gold: Color
    let waves: [Color]
    let tigerFade: Double
    let dragonFade: Double
}

extension BoardTheme {
    static let fabric = Color(hex: 0x0C0C0D)

    static func embroidered(_ id: String, _ name: String, accent: UInt32, accentInk: UInt32, border: UInt32, threads: [UInt32], embroidery: Embroidery) -> BoardTheme {
        BoardTheme(
            id: id, name: name, isDark: true,
            backdrop: fabric, sidebar: fabric.opacity(0), card: Color(hex: 0x141416, alpha: 0.8), line: Color(hex: border),
            ink: Color(hex: 0xEFE6D6), muted: Color(hex: 0x9C948A), faint: Color(hex: 0x5F5A55),
            accent: Color(hex: accent), accentInk: Color(hex: accentInk), shadow: Color.black.opacity(0.55),
            pill: Color(hex: 0x232326),
            swatch: fabric, swatchEdge: Color(hex: border), swatchRing: Color(hex: accentInk),
            projectTints: threads.map { Color(hex: $0) },
            metal: nil,
            embroidery: embroidery
        )
    }

    static let saffronAzure = embroidered(
        "saffron-azure", "Saffron tiger, azure dragon", accent: 0xE0943A, accentInk: 0xEBA75A, border: 0x8A7A62,
        threads: [0xE0943A, 0x5D8FD0, 0xD4A24C, 0xEFE2C4, 0xC2703A, 0x7AA4DC, 0x9C8F7A, 0xF0C27A],
        embroidery: Embroidery(
            tiger: "tiger-saffron", dragon: "dragon-azure",
            tigerThread: Color(hex: 0xE0943A), dragonThread: Color(hex: 0x4F7FC4), gold: Color(hex: 0xD4A24C),
            waves: [0x2F5C9E, 0x4F7FC4, 0xE0943A, 0xEFE2C4, 0xD4A24C].map { Color(hex: $0) },
            tigerFade: 0.58, dragonFade: 0.52
        )
    )

    static let goldVermilion = embroidered(
        "gold-vermilion", "Gold tiger, vermilion dragon", accent: 0xE1B23E, accentInk: 0xF0C55A, border: 0x8C6A48,
        threads: [0xE1B23E, 0xC8402F, 0xF1E3C0, 0xE07A3A, 0xA8322A, 0xF0CF72, 0x9C8F7A, 0xD86A5A],
        embroidery: Embroidery(
            tiger: "tiger-gold", dragon: "dragon-vermilion",
            tigerThread: Color(hex: 0xE1B23E), dragonThread: Color(hex: 0xC8402F), gold: Color(hex: 0xE1B23E),
            waves: [0x9E2A22, 0xC8402F, 0xE1B23E, 0xF1E3C0, 0xE07A3A].map { Color(hex: $0) },
            tigerFade: 0.56, dragonFade: 0.52
        )
    )

    static let whiteJade = embroidered(
        "white-jade", "White tiger, jade dragon", accent: 0x7FB89A, accentInk: 0x9CCDB2, border: 0x6F7A70,
        threads: [0x7FB89A, 0xECE6D8, 0xC9A45C, 0x9FC7B2, 0x4F8A70, 0xD8D2C4, 0x8E9A90, 0xB7D8C4],
        embroidery: Embroidery(
            tiger: "tiger-white", dragon: "dragon-jade",
            tigerThread: Color(hex: 0xECE6D8), dragonThread: Color(hex: 0x5F9E80), gold: Color(hex: 0xC9A45C),
            waves: [0x2F6B55, 0x5F9E80, 0xC9A45C, 0xECE6D8, 0x9FC7B2].map { Color(hex: $0) },
            tigerFade: 0.46, dragonFade: 0.52
        )
    )
}

enum EmbroideryArt {
    private static var cache: [String: NSImage] = [:]

    static func image(_ name: String) -> NSImage? {
        if let hit = cache[name] { return hit }
        guard let url = Bundle.main.url(forResource: name, withExtension: "jpg", subdirectory: "Embroidery"),
              let image = NSImage(contentsOf: url) else {
            note("board embroidery art missing name=\(name) bundle=\(Bundle.main.bundlePath)")
            return nil
        }
        cache[name] = image
        return image
    }
}

struct BoardBackdrop: View {
    let theme: BoardTheme

    var body: some View {
        if let embroidery = theme.embroidery {
            EmbroideredFabric(embroidery: embroidery)
        } else {
            theme.backdrop
        }
    }
}

private struct EmbroideredFabric: View {
    let embroidery: Embroidery

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let beast = min(600, max(360, size.height * 0.82))
            ZStack(alignment: .topLeading) {
                BoardTheme.fabric
                FabricWeave()
                EmbroideredMotifs(embroidery: embroidery)
                    .opacity(0.42)
                creature(embroidery.dragon, size: beast, focus: UnitPoint(x: 0.59, y: 0.32), fade: embroidery.dragonFade)
                    .offset(x: size.width - beast * 0.817, y: -beast * 0.067)
                creature(embroidery.tiger, size: beast, focus: UnitPoint(x: 0.42, y: 0.66), fade: embroidery.tigerFade)
                    .offset(x: -beast * 0.183, y: size.height - beast * 1.037)
                RadialGradient(colors: [.clear, .black.opacity(0.5)], center: .center,
                               startRadius: min(size.width, size.height) * 0.35,
                               endRadius: max(size.width, size.height) * 0.8)
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .clipped()
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func creature(_ name: String, size: CGFloat, focus: UnitPoint, fade: Double) -> some View {
        if let image = EmbroideryArt.image(name) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
                .saturation(1.05)
                .contrast(1.05)
                .mask(EllipticalGradient(stops: [.init(color: .black, location: 0.66), .init(color: .clear, location: 1)],
                                         center: focus, startRadiusFraction: 0, endRadiusFraction: 0.58))
                .opacity(fade)
                .blendMode(.lighten)
        }
    }
}

private struct FabricWeave: View {
    var body: some View {
        Canvas { context, size in
            var seed: UInt64 = 0x2545F4914F6CDD1D
            func next() -> Double {
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                return Double(seed >> 33) / Double(UInt64(1) << 31)
            }
            var y: CGFloat = 0
            while y < size.height {
                context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 0.7)), with: .color(.white.opacity(0.012 + next() * 0.022)))
                y += 1.7
            }
            var x: CGFloat = 0
            while x < size.width {
                context.fill(Path(CGRect(x: x, y: 0, width: 0.7, height: size.height)), with: .color(.white.opacity(0.008 + next() * 0.018)))
                x += 1.7
            }
            for _ in 0..<Int(size.width * size.height / 900) {
                let slub = CGRect(x: next() * size.width, y: next() * size.height, width: 3 + next() * 9, height: 0.8)
                context.fill(Path(slub), with: .color(.white.opacity(0.02 + next() * 0.03)))
            }
        }
    }
}

private struct EmbroideredMotifs: View {
    let embroidery: Embroidery

    var body: some View {
        Canvas { context, size in
            let k = max(0.6, min(1.1, size.height / 760))
            var seed: UInt64 = 21
            func next() -> Double {
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                return Double(seed >> 33) / Double(UInt64(1) << 31)
            }
            waves(context, width: size.width, top: size.height - 54 * k, k: k)
            let clouds: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
                (0.44, 0.84, 1, 1), (0.70, 0.79, 0.8, -1), (0.12, 0.11, 0.7, -1),
                (0.89, 0.62, 0.85, 1), (0.37, 0.39, 0.6, 1), (0.78, 0.47, 0.55, -1),
            ]
            for (x, y, scale, flip) in clouds {
                cloud(context, at: CGPoint(x: x * size.width, y: y * size.height), k: scale * k, flip: flip)
            }
            for i in 0..<36 {
                let point = CGPoint(x: (0.23 + (next() - 0.5) * 0.8) * size.width, y: (0.53 + (next() - 0.5) * 0.68) * size.height)
                knot(context, at: point, radius: (1.6 + next()) * k, color: i % 3 == 0 ? embroidery.dragonThread : embroidery.gold)
            }
        }
    }

    private func waves(_ context: GraphicsContext, width: CGFloat, top: CGFloat, k: CGFloat) {
        let band = 9 * k
        for (row, color) in embroidery.waves.enumerated() {
            let y = top + CGFloat(row) * band
            var path = Path()
            var x: CGFloat = -40
            while x < width + 40 {
                path.move(to: CGPoint(x: x, y: y + band))
                path.addLine(to: CGPoint(x: x + 7 * k, y: y))
                x += 2.6 * k
            }
            thread(context, path, color, width: 2.2 * k, shadow: 0.6)
        }
        var x: CGFloat = 30 * k
        while x < width {
            let cy = top - 2 * k
            var crest = Path()
            crest.move(to: CGPoint(x: x - 34 * k, y: cy))
            crest.addQuadCurve(to: CGPoint(x: x, y: cy - 32 * k), control: CGPoint(x: x - 30 * k, y: cy - 30 * k))
            crest.addQuadCurve(to: CGPoint(x: x + 22 * k, y: cy - 14 * k), control: CGPoint(x: x + 24 * k, y: cy - 32 * k))
            thread(context, crest, embroidery.waves[1], width: 5 * k)
            thread(context, crest, embroidery.gold, width: 1.8 * k)
            thread(context, spiral(CGPoint(x: x + 8 * k, y: cy - 18 * k), radius: 9 * k, turns: 1.1, flip: 1, start: -.pi * 0.2), embroidery.waves[3], width: 1.6 * k)
            x += 74 * k
        }
    }

    private func cloud(_ context: GraphicsContext, at point: CGPoint, k: CGFloat, flip: CGFloat) {
        let curls: [(CGFloat, CGFloat, CGFloat)] = [(0, 0, 15), (24, -8, 11), (-21, -5, 9)]
        for (dx, dy, r) in curls {
            let center = CGPoint(x: point.x + dx * k * flip, y: point.y + dy * k)
            thread(context, spiral(center, radius: r * k, turns: 1.35, flip: flip, start: .pi * 0.5), embroidery.gold, width: 2 * k)
            thread(context, spiral(center, radius: r * k * 0.6, turns: 1, flip: flip, start: .pi * 0.5), embroidery.dragonThread, width: 2.2 * k)
        }
        var tail = Path()
        tail.move(to: CGPoint(x: point.x + 14 * k * flip, y: point.y + 13 * k))
        tail.addQuadCurve(to: CGPoint(x: point.x + 95 * k * flip, y: point.y + 6 * k), control: CGPoint(x: point.x + 60 * k * flip, y: point.y + 26 * k))
        thread(context, tail, embroidery.gold, width: 2 * k)
        var under = Path()
        under.move(to: CGPoint(x: point.x - 32 * k * flip, y: point.y + 8 * k))
        under.addQuadCurve(to: CGPoint(x: point.x + 36 * k * flip, y: point.y + 14 * k), control: CGPoint(x: point.x, y: point.y + 22 * k))
        thread(context, under, embroidery.gold, width: 2 * k)
    }

    private func knot(_ context: GraphicsContext, at point: CGPoint, radius: CGFloat, color: Color) {
        let disc = { (r: CGFloat, dx: CGFloat, dy: CGFloat) in
            Path(ellipseIn: CGRect(x: point.x - r + dx, y: point.y - r + dy, width: r * 2, height: r * 2))
        }
        context.fill(disc(radius + 0.7, 0.6, 1.1), with: .color(.black.opacity(0.75)))
        context.fill(disc(radius, 0, 0), with: .color(Self.shade(color, 0.35)))
        context.stroke(disc(radius * 0.62, 0, 0), with: .color(color), lineWidth: radius * 0.55)
        context.fill(disc(radius * 0.28, -radius * 0.3, -radius * 0.35), with: .color(.white.opacity(0.35)))
    }

    private func spiral(_ center: CGPoint, radius: CGFloat, turns: Double, flip: CGFloat, start: Double) -> Path {
        var path = Path()
        let steps = 48
        for i in 0...steps {
            let t = Double(i) / Double(steps)
            let angle = start + Double(flip) * t * turns * 2 * .pi
            let r = radius * CGFloat(1 - t * 0.82)
            let point = CGPoint(x: center.x + CGFloat(cos(angle)) * r, y: center.y + CGFloat(sin(angle)) * r)
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }

    private func thread(_ context: GraphicsContext, _ path: Path, _ color: Color, width: CGFloat, shadow: CGFloat = 1) {
        let round = { (w: CGFloat, dash: [CGFloat]) in StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round, dash: dash) }
        var under = context
        under.translateBy(x: 0.6 * shadow, y: 1.1 * shadow)
        under.stroke(path, with: .color(.black.opacity(0.7)), style: round(width + 0.9, []))
        context.stroke(path, with: .color(Self.shade(color, 0.22)), style: round(width, []))
        context.stroke(path, with: .color(color), style: round(width * 0.74, []))
        var light = context
        light.translateBy(x: -0.25 * width, y: -0.3 * width)
        light.stroke(path, with: .color(.white.opacity(0.22)), style: round(width * 0.28, []))
        context.stroke(path, with: .color(.black.opacity(0.16)), style: round(width * 0.7, [0.45, 1.1]))
    }

    static func shade(_ color: Color, _ fraction: CGFloat) -> Color {
        Color(nsColor: NSColor(color).usingColorSpace(.sRGB)?.blended(withFraction: fraction, of: .black) ?? NSColor(color))
    }
}

extension View {
    func boardEdge(_ radius: CGFloat, color: Color = Board.line, width: CGFloat = 1) -> some View {
        let stitched = Board.theme.embroidery != nil
        return overlay(
            RoundedRectangle(cornerRadius: radius)
                .inset(by: stitched ? 5 : 0)
                .stroke(color, style: stitched
                        ? StrokeStyle(lineWidth: width + 0.8, lineCap: .round, dash: [6, 4.5])
                        : StrokeStyle(lineWidth: width))
                .shadow(color: .black.opacity(stitched ? 0.7 : 0), radius: 0, x: 0.5, y: 0.9)
        )
    }
}
