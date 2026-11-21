import AppKit
import Combine
import SwiftUI

final class LunaApp: PocketApp {
    override var defaultSize: NSSize { NSSize(width: 360, height: 560) }
    override var minSize: NSSize { NSSize(width: 360, height: 560) }
    override var resizable: Bool { false }

    override func start() {
        let store = LunaStore.shared
        store.onChange = { [weak self] in self?.changed() }
        note("luna app started day=\(store.today) samples=\(store.book.samples.count) nights=\(store.nights.count)")
    }

    override func stop() {
        LunaStore.shared.onChange = nil
        super.stop()
    }

    override func makeContent() -> NSView {
        let view = LunaGlance(store: LunaStore.shared) { [weak self] in self?.openWindow(source: "dropdown") }
        return ThemedHostingView(rootView: view, app: "sleep")
    }

    override func didShow() {
        LunaStore.shared.tick()
    }

    func openWindow(source: String) {
        hide(reason: "switched")
        LunaWindow.shared.present(source: source)
    }

    override func menuItems() -> [NSMenuItem] {
        let open = NSMenuItem(title: "Open Luna", action: #selector(openFromMenu), keyEquivalent: "")
        open.target = self
        return [open]
    }

    @objc private func openFromMenu() { openWindow(source: "menu") }
}

enum LunaLook {
    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    static func kicker(_ text: String) -> some View {
        Text(text.uppercased())
            .font(font(10.5, .semibold))
            .tracking(1.6)
            .foregroundStyle(LunaBoard.muted)
    }

    static var onTone: Color { LunaBoard.theme.isDark ? LunaBoard.backdrop : .white }
}

struct LunaTip: Equatable {
    let title: String
    var lines: [String] = []
}

struct LunaTipLabel: View {
    let tip: LunaTip

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(tip.title).font(LunaLook.font(12, .semibold)).foregroundStyle(Color.white)
            ForEach(Array(tip.lines.enumerated()), id: \.offset) { _, line in
                Text(line).font(LunaLook.font(11)).foregroundStyle(Color.white.opacity(0.72))
            }
        }
        .monospacedDigit()
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.black.opacity(0.84)))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.white.opacity(0.1), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.18), radius: 6, x: 0, y: 2)
    }
}

struct LunaTipped: ViewModifier {
    let make: (CGPoint, CGSize) -> LunaTip?
    @State private var point: CGPoint?

    static func left(_ x: CGFloat, _ width: CGFloat, _ room: CGFloat) -> CGFloat {
        let centered = x - width / 2
        guard room > width else { return centered }
        return min(max(0, centered), room - width)
    }

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let location): point = location
                case .ended: point = nil
                }
            }
            .overlay {
                GeometryReader { geo in
                    if let point, let tip = make(point, geo.size) {
                        Color.clear.overlay(alignment: .topLeading) {
                            LunaTipLabel(tip: tip)
                                .alignmentGuide(.leading) { d in -LunaTipped.left(point.x, d.width, geo.size.width) }
                                .alignmentGuide(.top) { d in -(point.y - d.height - 12) }
                        }
                    }
                }
                .allowsHitTesting(false)
            }
            .zIndex(point == nil ? 0 : 1)
    }
}

extension View {
    func lunaTip(_ make: @escaping (CGPoint, CGSize) -> LunaTip?) -> some View {
        modifier(LunaTipped(make: make))
    }
}

struct LunaCard<Content: View>: View {
    var padding: CGFloat = 14
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16).fill(LunaBoard.column))
            .boardEdge(16)
    }
}

struct LunaRing: View {
    let score: Int
    let asleep: Int
    let size: CGFloat
    let line: CGFloat

    var body: some View {
        ZStack {
            Circle().stroke(LunaBoard.track, lineWidth: line)
            Circle()
                .trim(from: 0, to: min(1, max(0, Double(score) / 100)))
                .stroke(LunaBoard.score(score), style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 2) {
                Text("\(score)").font(LunaLook.font(size * 0.27, .bold)).foregroundStyle(LunaBoard.ink)
                Text(LunaText.duration(Double(asleep))).font(LunaLook.font(max(11.5, size * 0.085))).foregroundStyle(LunaBoard.muted)
            }
            .monospacedDigit()
        }
        .frame(width: size, height: size)
        .lunaTip { _, _ in LunaTip(title: "Score \(score)", lines: ["\(LunaText.duration(Double(asleep))) asleep"]) }
    }
}

struct LunaFacts: View {
    let night: LunaNight
    var rule = true

    var body: some View {
        VStack(spacing: 0) {
            row("Bed", LunaText.clock(night.bed))
            row("Wake", LunaText.clock(night.wake))
            if rule { Rectangle().fill(LunaBoard.line).frame(height: 1).padding(.vertical, 6) }
            row("In bed", LunaText.duration(Double(night.inBed)))
            row("Awake", LunaText.duration(Double(night.awake)))
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).foregroundStyle(LunaBoard.ink)
            Spacer()
            Text(value).fontWeight(.bold).foregroundStyle(LunaBoard.ink)
        }
        .font(LunaLook.font(13.5))
        .monospacedDigit()
        .padding(.vertical, 5)
    }
}

struct LunaHypnogram: View {
    let night: LunaNight
    var labels = false
    var ticks = false
    var height: CGFloat = 64

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if labels {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach([LunaStage.awake, .rem, .core, .deep]) { stage in
                        Text(stage.label)
                            .font(LunaLook.font(12))
                            .foregroundStyle(LunaBoard.muted)
                            .frame(height: height / 4, alignment: .leading)
                    }
                }
                .frame(width: 46, alignment: .leading)
            }
            VStack(spacing: 6) {
                chart.frame(height: height)
                if ticks { tickRow.frame(height: 14) }
            }
        }
    }

    static func tip(_ night: LunaNight, at point: CGPoint, in size: CGSize) -> LunaTip? {
        guard size.width > 0, point.x >= 0, point.x <= size.width else { return nil }
        let total = Double(max(1, night.wake - night.bed))
        let at = night.bed + Int64(Double(point.x / size.width) * total)
        guard let segment = night.segments.first(where: { at >= $0.start && at < $0.end }) ?? night.segments.last(where: { at >= $0.start }) else { return nil }
        let minutes = Double(segment.end - segment.start) / Double(LunaMath.minute)
        return LunaTip(title: "\(LunaText.duration(minutes)) · \(segment.stage.label)", lines: [LunaText.span(segment.start, segment.end)])
    }

    private var chart: some View {
        let night = self.night
        let lineColor = LunaBoard.line
        let colors = Dictionary(uniqueKeysWithValues: LunaStage.allCases.map { ($0, LunaBoard.stage($0)) })
        return Canvas { context, size in
            let total = Double(max(1, night.wake - night.bed))
            let lh = size.height / 4
            var previous: LunaStage?
            for segment in night.segments {
                let x = CGFloat(Double(segment.start - night.bed) / total) * size.width
                let w = max(2, CGFloat(Double(segment.end - segment.start) / total) * size.width)
                let y = CGFloat(segment.stage.lane) * lh
                if let previous {
                    let py = CGFloat(previous.lane) * lh
                    let top = min(py, y) + lh / 2
                    let bottom = max(py, y) + lh / 2
                    context.fill(Path(CGRect(x: x - 0.75, y: top, width: 1.5, height: bottom - top)), with: .color(lineColor))
                }
                let rect = CGRect(x: x, y: y + lh * 0.18, width: w, height: lh * 0.64)
                context.fill(Path(roundedRect: rect, cornerRadius: min(4, lh * 0.2, w / 2)), with: .color(colors[segment.stage] ?? lineColor))
                previous = segment.stage
            }
        }
        .lunaTip { point, size in LunaHypnogram.tip(night, at: point, in: size) }
    }

    private var marks: [(at: Int64, text: String)] {
        let calendar = LunaDays.calendar
        let bedDate = LunaMath.date(night.bed)
        guard let start = calendar.dateInterval(of: .hour, for: bedDate)?.start else { return [] }
        var hour = start < bedDate ? start.addingTimeInterval(3600) : start
        var list: [Int64] = []
        while Int64(hour.timeIntervalSince1970 * 1000) <= night.wake && list.count < 30 {
            list.append(Int64(hour.timeIntervalSince1970 * 1000))
            hour = hour.addingTimeInterval(3600)
        }
        let step = list.count > 10 ? 2 : 1
        let kept = stride(from: 0, to: list.count, by: step).map { list[$0] }
        return kept.enumerated().map { index, at in
            (at: at, text: LunaText.hourTick(at, suffix: index == 0 || index == kept.count - 1))
        }
    }

    private var tickRow: some View {
        let total = Double(max(1, night.wake - night.bed))
        let list = marks
        return GeometryReader { geo in
            ForEach(Array(list.enumerated()), id: \.offset) { _, mark in
                let x = CGFloat(Double(mark.at - night.bed) / total) * geo.size.width
                Text(mark.text)
                    .font(LunaLook.font(11.5))
                    .foregroundStyle(LunaBoard.faint)
                    .fixedSize()
                    .position(x: min(max(x, 16), geo.size.width - 16), y: 7)
            }
        }
    }
}

struct LunaStageBar: View {
    let stages: LunaStages
    var height: CGFloat = 12
    @State private var hovered: LunaStage?

    var body: some View {
        GeometryReader { geo in
            let total = max(1, stages.total)
            let gaps = CGFloat(LunaStage.allCases.filter { stages.value($0) > 0 }.count - 1) * 2
            let width = max(0, geo.size.width - max(0, gaps))
            HStack(spacing: 2) {
                ForEach(LunaStage.allCases) { stage in
                    if stages.value(stage) > 0 {
                        Rectangle()
                            .fill(LunaBoard.stage(stage))
                            .frame(width: width * CGFloat(stages.value(stage) / total))
                            .contentShape(Rectangle())
                            .onHover { inside in
                                if inside { hovered = stage } else if hovered == stage { hovered = nil }
                            }
                    }
                }
            }
            .clipShape(Capsule())
        }
        .frame(height: height)
        .lunaTip { _, _ in hovered.map { LunaTip(title: stages.tip($0)) } }
    }
}

struct LunaLegend: View {
    let stages: LunaStages
    @State private var hovered: LunaStage?

    var body: some View {
        HStack(alignment: .top) {
            ForEach(Array(LunaStage.allCases.enumerated()), id: \.element.id) { index, stage in
                if index > 0 { Spacer(minLength: 4) }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 3).fill(LunaBoard.stage(stage)).frame(width: 9, height: 9)
                        Text(stage.label).font(LunaLook.font(11.5)).foregroundStyle(LunaBoard.muted)
                    }
                    Text(LunaText.duration(stages.value(stage))).font(LunaLook.font(14, .bold)).foregroundStyle(LunaBoard.ink).monospacedDigit()
                }
                .contentShape(Rectangle())
                .onHover { inside in
                    if inside { hovered = stage } else if hovered == stage { hovered = nil }
                }
            }
        }
        .padding(.top, 10)
        .lunaTip { _, _ in hovered.map { LunaTip(title: stages.tip($0)) } }
    }
}

extension LunaStages {
    init(_ night: LunaNight) {
        self.init(deep: Double(night.deep), core: Double(night.core), rem: Double(night.rem), awake: Double(night.awake))
    }

    func share(_ stage: LunaStage) -> Double {
        let base = stage == .awake ? total : deep + core + rem
        return base > 0 ? value(stage) / base * 100 : 0
    }

    func tip(_ stage: LunaStage) -> String {
        "\(LunaText.duration(value(stage))) · \(stage.label) · \(LunaMath.jsRound(share(stage)))%"
    }
}

struct LunaSay: View {
    let line: LunaLine

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: line.ok ? "checkmark" : "arrow.up")
                .font(.system(size: 10.5, weight: .bold))
                .foregroundStyle(line.ok ? LunaBoard.good : LunaBoard.fix)
                .frame(width: 22, height: 22)
                .background(Circle().fill(line.ok ? LunaBoard.goodSoft : LunaBoard.fixSoft))
            Text(line.text).font(LunaLook.font(13.5)).foregroundStyle(LunaBoard.ink).lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
    }
}

struct LunaSayList: View {
    let lines: [LunaLine]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                if index > 0 { Rectangle().fill(LunaBoard.line).frame(height: 1) }
                LunaSay(line: line)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(LunaBoard.column))
        .boardEdge(16)
    }
}

struct LunaRoundButton: View {
    let symbol: String
    var on = false
    var size: CGFloat = 34
    var help = ""
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(on ? LunaLook.onTone : LunaBoard.tone)
                .frame(width: size, height: size)
                .background(Circle().fill(on ? LunaBoard.tone : LunaBoard.column.opacity(0.75)))
                .overlay(Circle().stroke(on ? LunaBoard.tone : LunaBoard.line, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

struct LunaMiniButton: View {
    let symbol: String
    var help = ""
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(LunaBoard.tone)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 8).fill(LunaBoard.column))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(LunaBoard.line, lineWidth: 1))
                .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

struct LunaEmpty: View {
    let refresh: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "moon")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(LunaBoard.faint)
                .frame(width: 100, height: 100)
                .overlay(Circle().strokeBorder(LunaBoard.line, style: StrokeStyle(lineWidth: 2, dash: [5, 4])))
            Text(CloudSync.shared.configured ? "No nights yet" : "Connect Pocket's cloud sync to see your nights")
                .font(LunaLook.font(13))
                .foregroundStyle(LunaBoard.muted)
                .multilineTextAlignment(.center)
            Button(action: refresh) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                    Text("Refresh")
                }
                .font(LunaLook.font(13, .semibold))
                .foregroundStyle(LunaLook.onTone)
                .frame(width: 150, height: 34)
                .background(RoundedRectangle(cornerRadius: 10).fill(LunaBoard.tone))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct LunaGlance: View {
    @ObservedObject var store: LunaStore
    @ObservedObject var themes = AppThemeStore.shared
    let open: () -> Void
    @State private var hoveredBar: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                AppGlyph(id: "sleep")
                    .foregroundStyle(LunaBoard.tone)
                    .padding(4)
                    .frame(width: 26, height: 26)
                    .background(RoundedRectangle(cornerRadius: 8).fill(LunaBoard.soft))
                Text("Luna").font(LunaLook.font(15, .bold)).foregroundStyle(LunaBoard.ink)
                Spacer()
                LunaMiniButton(symbol: "arrow.triangle.2.circlepath", help: "Refresh") { store.refresh(source: "dropdown") }
                LunaMiniButton(symbol: "arrow.up.left.and.arrow.down.right", help: "Open Luna", action: open)
            }
            if let night = store.latest {
                content(night)
            } else {
                LunaEmpty { store.refresh(source: "dropdown") }
            }
        }
        .padding(14)
        .id(LunaBoard.theme.id)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(BoardBackdrop(theme: LunaBoard.theme))
        .ignoresSafeArea()
        .appTheme(LunaBoard.theme)
    }

    @ViewBuilder private func content(_ night: LunaNight) -> some View {
        LunaCard {
            HStack(spacing: 16) {
                LunaRing(score: night.score, asleep: night.asleep, size: 104, line: 10)
                LunaFacts(night: night, rule: false)
            }
            if night.key != store.today {
                Text(LunaDays.long(night.key)).font(LunaLook.font(11.5)).foregroundStyle(LunaBoard.muted)
            }
        }
        LunaCard(padding: 12) {
            LunaHypnogram(night: night, height: 64)
            LunaStageBar(stages: LunaStages(night), height: 8).padding(.top, 2)
        }
        weekBars(night)
        LunaSayList(lines: two(store.comments(night)))
    }

    private func weekBars(_ night: LunaNight) -> some View {
        let keys = LunaDays.week(night.key)
        return HStack(alignment: .bottom, spacing: 0) {
            ForEach(keys, id: \.self) { key in
                let found = store.night(key)
                VStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(found == nil ? LunaBoard.line : (key == night.key ? LunaBoard.tone : LunaBoard.soft))
                        .frame(width: 16, height: found.map { CGFloat(min(600, max(60, $0.inBed))) / 600 * 56 } ?? 6)
                    Text(String(LunaDays.dayName(key).prefix(1))).font(LunaLook.font(10.5)).foregroundStyle(LunaBoard.muted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .contentShape(Rectangle())
                .onHover { inside in
                    if inside { hoveredBar = key } else if hoveredBar == key { hoveredBar = nil }
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .frame(height: 96, alignment: .bottom)
        .background(RoundedRectangle(cornerRadius: 16).fill(LunaBoard.column))
        .boardEdge(16)
        .lunaTip { _, _ in barTip }
    }

    private var barTip: LunaTip? {
        guard let hoveredBar, let found = store.night(hoveredBar) else { return nil }
        return LunaTip(title: "\(LunaText.day(hoveredBar)) · \(LunaText.duration(Double(found.asleep))) · \(found.score)")
    }

    private func two(_ lines: [LunaLine]) -> [LunaLine] {
        let fixes = Array(lines.filter { !$0.ok }.prefix(1))
        let oks = Array(lines.filter(\.ok).prefix(2 - fixes.count))
        return oks + fixes
    }
}

final class LunaWindow: NSObject, NSWindowDelegate {
    static let shared = LunaWindow()

    private var window: NSWindow?
    private var themeWatch: AnyCancellable?

    func present(source: String) {
        NSApp.setActivationPolicy(.regular)
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            note("luna window refocused source=\(source)")
            return
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1180, height: 680),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = "Luna"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.appearance = LunaBoard.theme.appearance
        window.backgroundColor = NSColor(LunaBoard.backdrop)
        themeWatch = AppThemeStore.shared.publisher(for: "sleep").sink { [weak window] theme in
            window?.appearance = theme.appearance
            window?.backgroundColor = NSColor(theme.backdrop)
        }
        let host = NSHostingView(rootView: LunaBoardView(store: LunaStore.shared))
        host.sizingOptions = []
        window.contentView = host
        window.contentMinSize = NSSize(width: 1040, height: 640)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        window.setFrameAutosaveName("sleep.board")
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        note("luna window opened source=\(source) nights=\(LunaStore.shared.nights.count)")
    }

    func windowWillClose(_ notification: Notification) {
        let closing = window
        window?.delegate = nil
        window = nil
        themeWatch = nil
        let others = NSApp.windows.contains { $0 !== closing && $0.isVisible && $0.styleMask.contains(.titled) && $0.canBecomeMain }
        if !others { NSApp.setActivationPolicy(.accessory) }
        note("luna window closed otherWindows=\(others)")
    }
}

enum LunaMode: String, CaseIterable, Identifiable {
    case night = "Night"
    case week = "Week"
    case month = "Month"

    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .night: return "moon"
        case .week: return "chart.bar"
        case .month: return "calendar"
        }
    }
}

struct LunaBoardView: View {
    @ObservedObject var store: LunaStore
    @ObservedObject var themes = AppThemeStore.shared
    @State private var mode = LunaMode.night
    @State private var picked = ""
    @State private var weekKey = ""
    @State private var monthKey = ""
    @State private var settings = false

    var body: some View {
        HStack(spacing: 0) {
            LunaSidebar(store: store, mode: $mode)
                .frame(width: 270)
                .background(LunaBoard.sidebar)
            Rectangle().fill(LunaBoard.line).frame(width: 1)
            main
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if settings {
                Rectangle().fill(LunaBoard.line).frame(width: 1)
                LunaSettingsPanel(store: store)
                    .frame(width: 290)
                    .background(LunaBoard.sidebar)
                    .transition(.move(edge: .trailing))
            }
        }
        .id(LunaBoard.theme.id)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BoardBackdrop(theme: LunaBoard.theme))
        .ignoresSafeArea()
        .appTheme(LunaBoard.theme)
        .font(LunaLook.font(13))
    }

    private var main: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 14) {
                switch mode {
                case .night:
                    LunaNightView(store: store, picked: $picked)
                case .week:
                    LunaWeekView(store: store, key: Binding(get: { weekKey.isEmpty ? store.today : weekKey }, set: { weekKey = $0 }))
                case .month:
                    LunaMonthView(store: store, key: Binding(get: { monthKey.isEmpty ? store.today : monthKey }, set: { monthKey = $0 })) { key in
                        picked = key
                        mode = .night
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 38)
            .padding(.horizontal, 36)
            .padding(.bottom, 24)
            HStack(spacing: 8) {
                LunaRoundButton(symbol: "arrow.triangle.2.circlepath", help: "Refresh") { store.refresh(source: "window") }
                LunaRoundButton(symbol: "gearshape", on: settings, help: settings ? "Close settings" : "Settings") {
                    withAnimation(.easeOut(duration: 0.2)) { settings.toggle() }
                    note("luna settings \(settings ? "opened" : "closed")")
                }
                .keyboardShortcut(",", modifiers: .command)
            }
            .padding(.top, 16)
            .padding(.trailing, 20)
        }
    }
}

private struct LunaSidebar: View {
    @ObservedObject var store: LunaStore
    @ObservedObject var cloud = CloudSync.shared
    @Binding var mode: LunaMode

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(spacing: 2) {
                ForEach(LunaMode.allCases) { item in
                    let on = item == mode
                    Button {
                        mode = item
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: item.symbol).font(.system(size: 13, weight: .medium)).frame(width: 18)
                            Text(item.rawValue).font(LunaLook.font(14, on ? .bold : .medium))
                            Spacer()
                        }
                        .foregroundStyle(on ? LunaBoard.tone : LunaBoard.muted)
                        .padding(.horizontal, 10)
                        .frame(height: 34)
                        .background(RoundedRectangle(cornerRadius: 9).fill(on ? LunaBoard.soft : .clear))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            Rectangle().fill(LunaBoard.line).frame(height: 1)
            thisWeek
            LunaLook.kicker("Targets").padding(.horizontal, 4)
            VStack(spacing: 0) {
                row("Bed", LunaText.clock(store.settings.bed))
                row("Wake", LunaText.clock(store.settings.wake))
                row("Sleep", "\(LunaText.hours(store.settings.hours))h")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 16).fill(LunaBoard.column))
            .boardEdge(16)
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 10.5))
                Text(syncText)
            }
            .font(LunaLook.font(11.5))
            .foregroundStyle(LunaBoard.faint)
            .padding(.horizontal, 4)
        }
        .padding(.top, 56)
        .padding(.horizontal, 14)
        .padding(.bottom, 14)
    }

    private var syncText: String {
        if !cloud.configured { return "Cloud sync is off" }
        if let problem = cloud.problem { return problem }
        if let last = cloud.lastSync { return last.formatted(date: .omitted, time: .shortened) }
        return "Not synced yet"
    }

    private var thisWeek: some View {
        let week = store.week(store.today)
        return VStack(alignment: .leading, spacing: 12) {
            LunaLook.kicker("This week").padding(.horizontal, 4)
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], spacing: 14) {
                stat(week.avgAsleep.map { LunaText.duration($0) } ?? "–", "avg")
                stat(week.avgScore.map { "\($0)" } ?? "–", "score")
                stat(week.spread.map { "±\($0)m" } ?? "–", "bedtime")
                stat("\(week.over)/\(week.count)", "over \(LunaText.hours(store.settings.hours - 1))h")
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 16).fill(LunaBoard.column))
            .boardEdge(16)
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(LunaLook.font(22, .bold)).foregroundStyle(LunaBoard.ink).monospacedDigit()
            Text(label).font(LunaLook.font(12)).foregroundStyle(LunaBoard.muted)
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(LunaBoard.ink)
            Spacer()
            Text(value).fontWeight(.bold).foregroundStyle(LunaBoard.ink)
        }
        .font(LunaLook.font(13.5))
        .monospacedDigit()
        .padding(.vertical, 5)
    }
}

private struct LunaHeading: View {
    let kicker: String
    let title: String
    var back: (() -> Void)? = nil
    var next: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            LunaLook.kicker(kicker)
            HStack(spacing: 10) {
                Text(title).font(LunaLook.font(30, .bold)).foregroundStyle(LunaBoard.ink)
                if let back {
                    Button(action: back) {
                        Image(systemName: "chevron.left").font(.system(size: 14, weight: .semibold)).foregroundStyle(LunaBoard.muted).frame(width: 26, height: 26)
                    }
                    .buttonStyle(.plain)
                }
                if let next {
                    Button(action: next) {
                        Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).foregroundStyle(LunaBoard.muted).frame(width: 26, height: 26)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct LunaNightView: View {
    @ObservedObject var store: LunaStore
    @Binding var picked: String

    var body: some View {
        if let night = (picked.isEmpty ? nil : store.night(picked)) ?? store.latest {
            content(night)
        } else {
            LunaHeading(kicker: "Last night", title: LunaDays.long(store.today))
            LunaEmpty { store.refresh(source: "night") }
        }
    }

    @ViewBuilder private func content(_ night: LunaNight) -> some View {
        LunaHeading(kicker: night.key == store.today ? "Last night" : "Night", title: LunaDays.long(night.key))
        pills(night)
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 14) {
                LunaRing(score: night.score, asleep: night.asleep, size: 150, line: 13)
                LunaFacts(night: night)
            }
            .padding(20)
            .frame(width: 300)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(RoundedRectangle(cornerRadius: 16).fill(LunaBoard.column))
            .boardEdge(16)
            VStack(alignment: .leading, spacing: 0) {
                LunaHypnogram(night: night, labels: true, ticks: true, height: 230)
                LunaStageBar(stages: LunaStages(night), height: 12).padding(.top, 18)
                LunaLegend(stages: LunaStages(night))
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(RoundedRectangle(cornerRadius: 16).fill(LunaBoard.column))
            .boardEdge(16)
        }
        .fixedSize(horizontal: false, vertical: true)
        comments(store.comments(night))
    }

    private func pills(_ night: LunaNight) -> some View {
        HStack(spacing: 8) {
            ForEach(store.recent(6)) { item in
                let on = item.key == night.key
                Button {
                    picked = item.key == store.latest?.key ? "" : item.key
                } label: {
                    Text(item.key == store.today ? "Last night" : LunaDays.pill(item.key))
                        .font(LunaLook.font(13, on ? .semibold : .medium))
                        .foregroundStyle(on ? LunaLook.onTone : LunaBoard.muted)
                        .padding(.horizontal, 14)
                        .frame(height: 30)
                        .background(Capsule().fill(on ? LunaBoard.tone : LunaBoard.column))
                        .overlay(Capsule().stroke(on ? LunaBoard.tone : LunaBoard.line, lineWidth: 1))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func comments(_ lines: [LunaLine]) -> some View {
        HStack(alignment: .center, spacing: 16) {
            ForEach(lines) { line in
                LunaSay(line: line).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(LunaBoard.column))
        .boardEdge(16)
    }
}

private struct LunaStat: View {
    let value: String
    let label: String
    var size: CGFloat = 28

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(LunaLook.font(size, .bold)).foregroundStyle(LunaBoard.ink).monospacedDigit()
            Text(label).font(LunaLook.font(12)).foregroundStyle(LunaBoard.muted)
        }
    }
}

private struct LunaStagesCard: View {
    let stages: LunaStages

    var body: some View {
        LunaCard(padding: 18) {
            LunaLook.kicker("Stages").padding(.bottom, 4)
            if stages.total > 0 {
                LunaStageBar(stages: stages, height: 14)
                LunaLegend(stages: stages)
            } else {
                Text("No nights").font(LunaLook.font(12)).foregroundStyle(LunaBoard.muted)
            }
        }
    }
}

private struct LunaWeekView: View {
    @ObservedObject var store: LunaStore
    @Binding var key: String

    var body: some View {
        let week = store.week(key)
        LunaHeading(kicker: "Week", title: LunaDays.range(week.keys),
                    back: { key = LunaDays.shift(week.keys[0], by: -7) },
                    next: { key = LunaDays.shift(week.keys[0], by: 7) })
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .bottom, spacing: 28) {
                    LunaStat(value: week.avgAsleep.map { LunaText.duration($0) } ?? "–", label: "avg")
                    LunaStat(value: week.avgScore.map { "\($0)" } ?? "–", label: "score")
                    LunaStat(value: week.spread.map { "±\($0)m" } ?? "–", label: "bedtime")
                    Spacer()
                    if let change = week.change { LunaChip(change: change) }
                }
                LunaWindowChart(week: week, settings: store.settings, today: store.today)
                    .frame(maxHeight: .infinity)
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 16).fill(LunaBoard.column))
            .boardEdge(16)
            .layoutPriority(1.4)
            VStack(spacing: 14) {
                LunaStagesCard(stages: week.stages)
                LunaCard(padding: 18) {
                    LunaLook.kicker("Each night").padding(.bottom, 2)
                    LunaNightStacks(keys: week.keys, nights: week.nights, today: store.today)
                }
                if week.comments.isEmpty {
                    Spacer(minLength: 0)
                } else {
                    LunaSayList(lines: week.comments)
                    Spacer(minLength: 0)
                }
            }
            .frame(width: 360)
        }
        .frame(maxHeight: .infinity)
    }
}

private struct LunaChip: View {
    let change: Int

    var body: some View {
        Text(change >= 0 ? "+\(change)m" : "−\(-change)m")
            .font(LunaLook.font(12, .heavy))
            .foregroundStyle(change >= 0 ? LunaBoard.good : LunaBoard.fix)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(Capsule().fill(change >= 0 ? LunaBoard.goodSoft : LunaBoard.fixSoft))
    }
}

private struct LunaPick: Equatable {
    let key: String
    let stage: LunaStage
}

private struct LunaNightStacks: View {
    let keys: [String]
    let nights: [LunaNight]
    let today: String
    @State private var hovered: LunaPick?

    private static let order: [LunaStage] = [.awake, .rem, .core, .deep]
    private static let tall: CGFloat = 84

    var body: some View {
        let scale = Double(max(480, nights.map(\.inBed).max() ?? 480))
        HStack(alignment: .bottom, spacing: 0) {
            ForEach(keys, id: \.self) { key in
                VStack(spacing: 5) {
                    if let night = nights.first(where: { $0.key == key }) {
                        VStack(spacing: 1.5) {
                            ForEach(Self.order) { stage in
                                if night.minutes(stage) > 0 {
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(LunaBoard.stage(stage))
                                        .frame(width: 22, height: max(2, CGFloat(Double(night.minutes(stage)) / scale) * Self.tall))
                                        .contentShape(Rectangle())
                                        .onHover { inside in hover(LunaPick(key: key, stage: stage), inside) }
                                }
                            }
                        }
                    } else {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(key > today ? Color.clear : LunaBoard.line)
                            .frame(width: 22, height: 4)
                    }
                    Text(String(LunaDays.dayName(key).prefix(1)))
                        .font(LunaLook.font(11))
                        .foregroundStyle(key == today ? LunaBoard.tone : LunaBoard.faint)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 122, alignment: .bottom)
        .lunaTip { _, _ in tip }
    }

    private func hover(_ pick: LunaPick, _ inside: Bool) {
        if inside { hovered = pick } else if hovered == pick { hovered = nil }
    }

    private var tip: LunaTip? {
        guard let hovered, let night = nights.first(where: { $0.key == hovered.key }) else { return nil }
        return LunaTip(title: LunaStages(night).tip(hovered.stage), lines: [LunaText.day(hovered.key)])
    }
}

private struct LunaWindowChart: View {
    let week: LunaWeek
    let settings: LunaSettings
    let today: String

    private static func value(_ minutes: Int) -> Double { Double(minutes < 720 ? minutes + 1440 : minutes) }

    private var bounds: (top: Double, bottom: Double) {
        let bedT = Self.value(settings.bedMinutes)
        let wakeT = Self.value(settings.wakeMinutes)
        let beds = week.nights.map { Self.value(LunaMath.clockMinutes($0.bed)) }
        let wakes = week.nights.map { Self.value(LunaMath.clockMinutes($0.wake)) }
        let top = ((min(bedT - 60, beds.min() ?? bedT) / 60).rounded(.down)) * 60
        let bottom = ((max(wakeT + 60, wakes.max() ?? wakeT) / 60).rounded(.up)) * 60
        return (top, max(bottom, top + 120))
    }

    var body: some View {
        let range = bounds
        let span = range.bottom - range.top
        let axis = stride(from: range.top, through: range.bottom, by: span > 720 ? 240 : 120).map { $0 }
        HStack(alignment: .top, spacing: 8) {
            GeometryReader { geo in
                ForEach(Array(axis.enumerated()), id: \.offset) { index, mark in
                    Text(label(mark, index: index, axis: axis))
                        .font(LunaLook.font(11))
                        .foregroundStyle(LunaBoard.faint)
                        .fixedSize()
                        .frame(width: 44, alignment: .trailing)
                        .position(x: 22, y: CGFloat((mark - range.top) / span) * geo.size.height)
                }
            }
            .frame(width: 44)
            VStack(spacing: 8) {
                canvas(range)
                HStack(spacing: 0) {
                    ForEach(week.keys, id: \.self) { key in
                        Text(String(LunaDays.dayName(key).prefix(1)))
                            .font(LunaLook.font(12))
                            .foregroundStyle(key == today ? LunaBoard.tone : LunaBoard.muted)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .frame(minHeight: 220)
    }

    private func label(_ mark: Double, index: Int, axis: [Double]) -> String {
        let hour = (Int(mark) / 60) % 24
        let shown = hour % 12 == 0 ? 12 : hour % 12
        let firstMorning = hour < 12 && !axis.prefix(index).contains { (Int($0) / 60) % 24 < 12 }
        return index == 0 || firstMorning ? "\(shown) \(hour < 12 ? "am" : "pm")" : "\(shown)"
    }

    private func canvas(_ range: (top: Double, bottom: Double)) -> some View {
        let span = range.bottom - range.top
        let keys = week.keys
        let nights = week.nights
        let today = self.today
        let bedT = Self.value(settings.bedMinutes)
        let wakeT = Self.value(settings.wakeMinutes)
        let tone = LunaBoard.tone
        let line = LunaBoard.line
        let fills = Dictionary(uniqueKeysWithValues: nights.map { ($0.key, LunaBoard.score($0.score)) })
        return Canvas { context, size in
            let y: (Double) -> CGFloat = { CGFloat(($0 - range.top) / span) * size.height }
            for target in [bedT, wakeT] {
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y(target)))
                path.addLine(to: CGPoint(x: size.width, y: y(target)))
                context.stroke(path, with: .color(tone.opacity(0.55)), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
            }
            let column = size.width / CGFloat(max(1, keys.count))
            for (index, key) in keys.enumerated() {
                let cx = column * CGFloat(index) + column / 2
                if let night = nights.first(where: { $0.key == key }) {
                    let top = y(Self.value(LunaMath.clockMinutes(night.bed)))
                    let bottom = max(top + 8, y(Self.value(LunaMath.clockMinutes(night.wake))))
                    let rect = CGRect(x: cx - 11, y: top, width: 22, height: bottom - top)
                    context.fill(Path(roundedRect: rect, cornerRadius: 11), with: .color(fills[key] ?? tone))
                } else if key > today {
                    let rect = CGRect(x: cx - 11, y: y(bedT), width: 22, height: max(8, y(wakeT) - y(bedT)))
                    context.stroke(Path(roundedRect: rect, cornerRadius: 11), with: .color(line), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
            }
        }
        .lunaTip { point, size in
            guard !keys.isEmpty, size.width > 0, point.x >= 0 else { return nil }
            let index = Int(point.x / (size.width / CGFloat(keys.count)))
            guard index >= 0, index < keys.count, let night = nights.first(where: { $0.key == keys[index] }) else { return nil }
            return LunaTip(title: LunaText.day(night.key),
                           lines: [LunaText.span(night.bed, night.wake), "\(LunaText.duration(Double(night.asleep))) · \(night.score)"])
        }
    }
}

private struct LunaMonthView: View {
    @ObservedObject var store: LunaStore
    @Binding var key: String
    let open: (String) -> Void
    @State private var hoveredDay: String?

    var body: some View {
        let month = store.month(key)
        LunaHeading(kicker: "Month", title: LunaDays.monthTitle(key),
                    back: { key = LunaDays.monthShift(key, by: -1) },
                    next: { key = LunaDays.monthShift(key, by: 1) })
        HStack(alignment: .top, spacing: 14) {
            grid(month)
                .lunaTip { _, _ in
                    guard let hoveredDay, let night = month.nights.first(where: { $0.key == hoveredDay }) else { return nil }
                    return LunaTip(title: LunaText.day(hoveredDay), lines: ["\(LunaText.duration(Double(night.asleep))) · \(night.score)"])
                }
                .padding(18)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(RoundedRectangle(cornerRadius: 16).fill(LunaBoard.column))
                .boardEdge(16)
                .layoutPriority(1.35)
            VStack(spacing: 14) {
                LunaCard(padding: 18) {
                    HStack {
                        LunaStat(value: month.avgAsleep.map { LunaText.duration($0) } ?? "–", label: "avg")
                        Spacer()
                        LunaStat(value: month.spread.map { "±\($0)m" } ?? "–", label: "bedtime")
                        Spacer()
                        LunaStat(value: month.avgScore.map { "\($0)" } ?? "–", label: "score")
                    }
                    .padding(.bottom, 6)
                    LunaLineChart(keys: month.keys, nights: month.nights, hours: store.settings.hours)
                        .frame(height: 110)
                }
                LunaStagesCard(stages: month.stages)
                if !month.comments.isEmpty { LunaSayList(lines: month.comments) }
                Spacer(minLength: 0)
            }
            .frame(width: 380)
        }
        .frame(maxHeight: .infinity)
    }

    private func grid(_ month: LunaMonth) -> some View {
        let lead = (LunaDays.weekday(month.keys.first ?? key) + 5) % 7
        let cells: [String?] = Array(repeating: nil, count: lead) + month.keys.map { Optional($0) }
        let columns = Array(repeating: GridItem(.flexible(), spacing: 7), count: 7)
        let names = LunaDays.week(month.keys.first ?? key).map { LunaDays.format($0, "EEE") }
        return LazyVGrid(columns: columns, spacing: 7) {
            ForEach(Array(names.enumerated()), id: \.offset) { _, name in
                Text(name).font(LunaLook.font(11, .semibold)).foregroundStyle(LunaBoard.muted)
            }
            ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                if let day = cell {
                    self.cell(day, night: month.nights.first { $0.key == day })
                } else {
                    Color.clear.frame(height: 62)
                }
            }
        }
    }

    @ViewBuilder private func cell(_ day: String, night: LunaNight?) -> some View {
        if day > store.today {
            Text("\(LunaDays.dayNumber(day))")
                .font(LunaLook.font(12))
                .foregroundStyle(LunaBoard.faint)
                .padding(8)
                .frame(maxWidth: .infinity, minHeight: 62, maxHeight: 62, alignment: .topLeading)
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(LunaBoard.line, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
        } else {
            Button {
                if night != nil { open(day) }
            } label: {
                VStack(spacing: 0) {
                    HStack {
                        Text("\(LunaDays.dayNumber(day))").foregroundStyle(LunaBoard.muted)
                        Spacer()
                        if let night { Text("\(night.score)").fontWeight(.bold).foregroundStyle(LunaBoard.ink) }
                    }
                    .font(LunaLook.font(12))
                    .monospacedDigit()
                    Spacer(minLength: 0)
                    if let night {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(LunaBoard.track)
                                Capsule().fill(LunaBoard.score(night.score))
                                    .frame(width: geo.size.width * CGFloat(min(1, Double(night.asleep) / 540)))
                            }
                        }
                        .frame(height: 6)
                    } else {
                        Capsule().strokeBorder(LunaBoard.line, style: StrokeStyle(lineWidth: 1, dash: [3, 2])).frame(height: 6)
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, minHeight: 62, maxHeight: 62)
                .background(RoundedRectangle(cornerRadius: 12).fill(LunaBoard.column))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(day == store.today ? LunaBoard.tone : LunaBoard.line, lineWidth: 1))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { inside in
                if inside { hoveredDay = day } else if hoveredDay == day { hoveredDay = nil }
            }
        }
    }
}

private struct LunaLineChart: View {
    let keys: [String]
    let nights: [LunaNight]
    let hours: Double

    var body: some View {
        let values: [Double?] = keys.map { key in nights.first { $0.key == key }.map { Double($0.asleep) / 60 } }
        let known = values.compactMap { $0 }
        let low = min(hours - 1.5, (known.min() ?? hours) - 0.3)
        let high = max(hours + 1.5, (known.max() ?? hours) + 0.3)
        let soft = LunaBoard.soft
        let tone = LunaBoard.tone
        let card = LunaBoard.column
        return Canvas { context, size in
            let x: (Int) -> CGFloat = { CGFloat($0) / CGFloat(max(1, values.count - 1)) * size.width }
            let y: (Double) -> CGFloat = { size.height - CGFloat(($0 - low) / max(0.1, high - low)) * size.height }
            let band = CGRect(x: 0, y: y(hours + 1), width: size.width, height: y(hours - 0.5) - y(hours + 1))
            context.fill(Path(roundedRect: band, cornerRadius: 6), with: .color(soft.opacity(0.6)))
            var target = Path()
            target.move(to: CGPoint(x: 0, y: y(hours)))
            target.addLine(to: CGPoint(x: size.width, y: y(hours)))
            context.stroke(target, with: .color(tone.opacity(0.6)), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
            var path = Path()
            for (index, value) in values.enumerated() {
                guard let value else { continue }
                let point = CGPoint(x: x(index), y: y(value))
                if index > 0, values[index - 1] != nil { path.addLine(to: point) } else { path.move(to: point) }
            }
            context.stroke(path, with: .color(tone), style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
            for (index, value) in values.enumerated() {
                guard let value else { continue }
                let dot = Path(ellipseIn: CGRect(x: x(index) - 2.6, y: y(value) - 2.6, width: 5.2, height: 5.2))
                context.fill(dot, with: .color(card))
                context.stroke(dot, with: .color(tone), lineWidth: 1.6)
            }
        }
        .lunaTip { point, size in
            guard values.count > 0, size.width > 0 else { return nil }
            let step = size.width / CGFloat(max(1, values.count - 1))
            let index = Int((point.x / step).rounded())
            guard index >= 0, index < values.count, let value = values[index] else { return nil }
            return LunaTip(title: "\(LunaText.day(keys[index])) · \(LunaText.duration(value * 60))")
        }
    }
}

private struct LunaSettingsPanel: View {
    @ObservedObject var store: LunaStore
    @ObservedObject var cloud = CloudSync.shared
    @ObservedObject var vault = DataVault.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                LunaLook.kicker("Targets").padding(.top, 56)
                VStack(spacing: 0) {
                    row("Bed") { time("bed", store.settings.bed) }
                    divider
                    row("Wake") { time("wake", store.settings.wake) }
                    divider
                    row("Sleep") { stepper("hours", store.settings.hours, 4...12, 0.5, "\(LunaText.hours(store.settings.hours))h") }
                    divider
                    row("Deep") { stepper("deep", store.settings.deep, 5...40, 1, "\(LunaText.number(store.settings.deep))%") }
                    divider
                    row("REM") { stepper("rem", store.settings.rem, 5...40, 1, "\(LunaText.number(store.settings.rem))%") }
                    divider
                    row("Leeway") { stepper("tolerance", store.settings.tolerance, 5...90, 5, "\(LunaText.number(store.settings.tolerance)) min") }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 16).fill(LunaBoard.column))
                .boardEdge(16)
                LunaLook.kicker("Sync")
                VStack(spacing: 0) {
                    row("Last sync") { Text(lastSync).foregroundStyle(LunaBoard.muted) }
                    divider
                    row("Samples") { Text("\(store.book.samples.count)").foregroundStyle(LunaBoard.muted).monospacedDigit() }
                    divider
                    row("Nights") { Text("\(store.nights.count)").foregroundStyle(LunaBoard.muted).monospacedDigit() }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 16).fill(LunaBoard.column))
                .boardEdge(16)
                if let problem = cloud.problem {
                    Text(problem).font(LunaLook.font(11.5)).foregroundStyle(LunaBoard.fix)
                }
                soft("Refresh") { store.refresh(source: "settings") }
                LunaLook.kicker("Backup")
                HStack(spacing: 8) {
                    Menu {
                        let snaps = store.snapshots()
                        if snaps.isEmpty { Text("No daily copies yet") }
                        ForEach(snaps, id: \.snapshot.id) { entry in
                            Button("\(entry.snapshot.day.formatted(date: .abbreviated, time: .omitted)) · \(entry.samples) samples") { confirm(entry.snapshot) }
                        }
                    } label: {
                        Text("Restore…").font(LunaLook.font(12, .medium)).foregroundStyle(LunaBoard.ink)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    Spacer()
                    Button("Show backups") { vault.showInFinder() }
                        .buttonStyle(.plain)
                        .font(LunaLook.font(12, .medium))
                        .foregroundStyle(LunaBoard.muted)
                }
            }
            .font(LunaLook.font(13.5))
            .padding(.horizontal, 18)
            .padding(.bottom, 18)
        }
        .scrollIndicators(.never)
    }

    private var lastSync: String {
        if !cloud.configured { return "Off" }
        return cloud.lastSync?.formatted(date: .omitted, time: .shortened) ?? "Not yet"
    }

    private var divider: some View { Rectangle().fill(LunaBoard.line).frame(height: 1) }

    private func row<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        HStack {
            Text(title).foregroundStyle(LunaBoard.ink)
            Spacer()
            content()
        }
        .frame(minHeight: 38)
    }

    private func time(_ key: String, _ text: String) -> some View {
        let minutes = LunaSettings.minutes(text)
        let date = Calendar.current.date(bySettingHour: (minutes / 60) % 24, minute: minutes % 60, second: 0, of: Date()) ?? Date()
        return DatePicker("", selection: Binding(get: { date }, set: { store.setTime(key, $0) }), displayedComponents: .hourAndMinute)
            .labelsHidden()
            .datePickerStyle(.field)
            .fixedSize()
    }

    private func stepper(_ key: String, _ value: Double, _ range: ClosedRange<Double>, _ step: Double, _ label: String) -> some View {
        Stepper(value: Binding(get: { value }, set: { store.setNumber(key, $0) }), in: range, step: step) {
            Text(label)
                .fontWeight(.semibold)
                .foregroundStyle(LunaBoard.tone)
                .monospacedDigit()
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 7).fill(LunaBoard.soft))
        }
        .fixedSize()
    }

    private func soft(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(LunaLook.font(13, .semibold))
                .foregroundStyle(LunaBoard.tone)
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .background(RoundedRectangle(cornerRadius: 8).fill(LunaBoard.column))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(LunaBoard.line, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func confirm(_ snap: VaultSnapshot) {
        let alert = NSAlert()
        alert.messageText = "Restore Luna from \(snap.day.formatted(date: .long, time: .omitted))?"
        alert.informativeText = "Today's copy is kept as its own backup first, so this can be undone."
        alert.addButton(withTitle: "Restore")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        store.restore(snap)
    }
}
