import AppKit
import Combine
import SwiftUI

final class ScheduleBoardWindow: NSObject, NSWindowDelegate {
    static let shared = ScheduleBoardWindow()

    private var window: NSWindow?
    private var themeWatch: AnyCancellable?
    private let focus = ScheduleBoardFocus(day: ScheduleStore.shared.today)

    func present(day: String? = nil) {
        let store = ScheduleStore.shared
        if let day {
            if ScheduleDays.date(day) != nil {
                focus.selected = max(day, store.firstDay)
                focus.span = .day
                UserDefaults.standard.set(ScheduleBoardMode.schedule, forKey: ScheduleBoardMode.key)
            } else {
                note("schedule board bad day requested day=\(day)")
            }
        }
        NSApp.setActivationPolicy(.regular)
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            note("schedule board refocused day=\(focus.selected)")
            return
        }
        if day == nil { focus.selected = store.today }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 660),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = "Schedule"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.appearance = Board.theme.appearance
        window.backgroundColor = NSColor(Board.backdrop)
        themeWatch = BoardThemeStore.shared.$theme.sink { [weak window] theme in
            window?.appearance = theme.appearance
            window?.backgroundColor = NSColor(theme.backdrop)
        }
        window.minSize = NSSize(width: 720, height: 480)
        window.contentView = NSHostingView(rootView: ScheduleBoardView(store: store, focus: focus))
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        window.setFrameAutosaveName("schedule.board")
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        note("schedule board opened day=\(focus.selected) routines=\(store.routines.count) filter=\(store.filterName)")
    }

    func windowWillClose(_ notification: Notification) {
        let closing = window
        window?.delegate = nil
        window = nil
        themeWatch = nil
        let others = NSApp.windows.contains { $0 !== closing && $0.isVisible && $0.styleMask.contains(.titled) && $0.canBecomeMain }
        if !others { NSApp.setActivationPolicy(.accessory) }
        note("schedule board closed otherWindows=\(others)")
    }
}

private enum ScheduleSpan: String {
    case day
    case week
}

private final class ScheduleBoardFocus: ObservableObject {
    @Published var selected: String
    @Published var span: ScheduleSpan {
        didSet { UserDefaults.standard.set(span.rawValue, forKey: Self.spanKey) }
    }

    private static let spanKey = "schedule.board.span"

    init(day: String) {
        selected = day
        span = UserDefaults.standard.string(forKey: Self.spanKey).flatMap(ScheduleSpan.init) ?? .day
    }
}

private enum ScheduleBoardMode {
    static let key = "schedule.board.mode"
    static let schedule = "schedule"
    static let calendar = "calendar"
}

private enum ScheduleBoardDates {
    private static func formatter(_ pattern: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = ScheduleDays.calendar
        f.timeZone = .current
        f.dateFormat = pattern
        return f
    }

    private static let monthName = formatter("LLLL yyyy")
    private static let dayName = formatter("EEEE, d MMMM")
    private static let dayMonth = formatter("d MMM")
    private static let dayMonthYear = formatter("d MMM yyyy")
    private static let longDay = formatter("d MMMM yyyy")

    static func weekStart(_ key: String) -> String {
        ScheduleDays.shift(key, by: -((ScheduleDays.weekday(key) + 5) % 7))
    }

    static func monthStart(_ key: String) -> String { String(key.prefix(7)) + "-01" }

    static func monthShift(_ key: String, by months: Int) -> String {
        guard let date = ScheduleDays.date(monthStart(key)),
              let moved = ScheduleDays.calendar.date(byAdding: .month, value: months, to: date) else { return monthStart(key) }
        return ScheduleDays.key(moved)
    }

    static func monthLength(_ key: String) -> Int {
        guard let date = ScheduleDays.date(monthStart(key)) else { return 30 }
        return ScheduleDays.calendar.range(of: .day, in: .month, for: date)?.count ?? 30
    }

    static func monthTitle(_ key: String) -> String { ScheduleDays.date(key).map(monthName.string) ?? key }
    static func dayTitle(_ key: String) -> String { ScheduleDays.date(key).map(dayName.string) ?? key }
    static func short(_ key: String) -> String { ScheduleDays.date(key).map(dayMonth.string) ?? key }
    static func full(_ key: String) -> String { ScheduleDays.date(key).map(dayMonthYear.string) ?? key }
    static func snapshot(_ date: Date) -> String { dayMonthYear.string(from: date) }
    static func longSnapshot(_ date: Date) -> String { longDay.string(from: date) }
    static func number(_ key: String) -> String { Int(key.suffix(2)).map(String.init) ?? "" }

    static func weekRange(_ start: String) -> String {
        let end = ScheduleDays.shift(start, by: 6)
        if start.prefix(7) == end.prefix(7) { return "\(number(start)) – \(full(end))" }
        return "\(short(start)) – \(full(end))"
    }

    static func hour(_ value: Int) -> String {
        let twelve = value % 12 == 0 ? 12 : value % 12
        return "\(twelve) \(value < 12 || value == 24 ? "AM" : "PM")"
    }
}

private struct ScheduleSectionTitle: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .tracking(1.6)
            .foregroundStyle(Board.muted)
    }
}

private struct ScheduleHairline: View {
    var body: some View {
        Rectangle().fill(Board.line.opacity(Board.theme.embroidery == nil ? 1 : 0.35)).frame(height: 1)
    }
}

private struct ScheduleHalf: Shape {
    let left: Bool

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        var path = Path()
        path.move(to: CGPoint(x: center.x, y: center.y - radius))
        path.addArc(center: center, radius: radius, startAngle: .degrees(-90), endAngle: .degrees(90), clockwise: left)
        path.closeSubpath()
        return path
    }
}

private struct ScheduleStatusDot: View {
    let status: ScheduleDayStatus
    var size: CGFloat = 7

    var body: some View {
        ZStack {
            switch status {
            case .done:
                Circle().fill(Board.accentStyle)
            case .partial:
                half
            case .open(let done, _):
                if done > 0 { half } else { Circle().stroke(Board.faint, lineWidth: 1) }
            case .missed:
                Circle().stroke(Color.red.opacity(0.55), lineWidth: 1.5)
            case .upcoming, .rest:
                Circle().fill(Board.faint.opacity(0.45))
            case .before:
                Circle().fill(Color.clear)
            }
        }
        .frame(width: size, height: size)
    }

    private var half: some View {
        ZStack {
            Circle().stroke(Board.accent, lineWidth: 1)
            ScheduleHalf(left: true).fill(Board.accentStyle)
        }
    }
}

private struct ScheduleSplitMark: View {
    let morning: ScheduleDayStatus
    let night: ScheduleDayStatus
    var size: CGFloat = 16

    var body: some View {
        ZStack {
            piece(morning, left: true).offset(x: -1.25)
            piece(night, left: false).offset(x: 1.25)
        }
        .frame(width: size + 2.5, height: size)
    }

    @ViewBuilder
    private func piece(_ status: ScheduleDayStatus, left: Bool) -> some View {
        let shape = ScheduleHalf(left: left)
        switch status {
        case .done:
            shape.fill(Board.accentStyle).frame(width: size, height: size)
        case .partial:
            shape.fill(Board.accent.opacity(0.45)).frame(width: size, height: size)
        case .missed:
            shape.fill(Color.red.opacity(0.55)).frame(width: size, height: size)
        case .open, .upcoming:
            shape.stroke(Board.faint, lineWidth: 1).frame(width: size - 1, height: size - 1)
        case .rest:
            Capsule().fill(Board.faint).frame(width: size * 0.3, height: 1.5).offset(x: left ? -size * 0.22 : size * 0.22)
                .frame(width: size, height: size)
        case .before:
            Color.clear.frame(width: size, height: size)
        }
    }
}

private struct ScheduleGlass<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        if #available(macOS 26, *) {
            content.glassEffect(.regular.interactive(), in: Capsule())
        } else {
            content
                .background(Capsule().fill(.ultraThinMaterial))
                .overlay(Capsule().strokeBorder(Board.line, lineWidth: 1))
        }
    }
}

private struct ScheduleModeToggle: View {
    @Binding var mode: String
    @Namespace private var pill

    private let options = [("Schedule", ScheduleBoardMode.schedule), ("Calendar", ScheduleBoardMode.calendar)]

    var body: some View {
        ScheduleGlass {
            HStack(spacing: 2) {
                ForEach(options, id: \.1) { title, value in
                    Button {
                        guard mode != value else { return }
                        note("schedule board view mode=\(value)")
                        withAnimation(Board.glide) { mode = value }
                    } label: {
                        Text(title)
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(mode == value ? Board.ink : Board.muted.opacity(0.7))
                            .padding(.horizontal, 16)
                            .frame(height: 34)
                            .background {
                                if mode == value {
                                    Capsule()
                                        .fill(Board.theme.pill)
                                        .shadow(color: Board.shadow, radius: 4, y: 1)
                                        .matchedGeometryEffect(id: "pill", in: pill)
                                }
                            }
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
        }
        .fixedSize()
    }
}

private struct ScheduleRoutinePicker: View {
    @ObservedObject var store: ScheduleStore

    var body: some View {
        Menu {
            Button {
                store.filter = nil
            } label: {
                if store.filter == nil { Label("All routines", systemImage: "checkmark") } else { Text("All routines") }
            }
            if !store.routines.isEmpty { Divider() }
            ForEach(store.routines) { routine in
                Button {
                    store.filter = routine.id
                } label: {
                    if store.filter == routine.id { Label(routine.name, systemImage: "checkmark") } else { Text(routine.name) }
                }
            }
        } label: {
            ViewThatFits(in: .horizontal) {
                label(named: true)
                label(named: false)
            }
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .help(store.filterName)
    }

    private func label(named: Bool) -> some View {
        ScheduleGlass {
            HStack(spacing: 8) {
                dots
                if named {
                    Text(store.filterName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Board.ink)
                        .lineLimit(1)
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Board.muted)
            }
            .padding(.horizontal, 14)
            .frame(height: 34)
            .contentShape(Capsule())
        }
        .fixedSize()
    }

    private var dots: some View {
        let tints = store.shown.prefix(3).map { Board.hue($0.hue) }
        return HStack(spacing: -3) {
            if tints.isEmpty {
                Circle().fill(Board.faint).frame(width: 8, height: 8)
            }
            ForEach(Array(tints.enumerated()), id: \.offset) { _, tint in
                Circle().fill(tint).frame(width: 8, height: 8).overlay(Circle().stroke(Board.column, lineWidth: 1))
            }
        }
    }
}

private struct ScheduleCircleButton: View {
    let symbol: String
    let on: Bool
    let help: String
    let action: () -> Void

    var body: some View {
        let icon = Image(systemName: symbol)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(on ? Board.accentInkStyle : AnyShapeStyle(Board.muted))
            .frame(width: 40, height: 40)
            .contentShape(Circle())
        Button(action: action) {
            if #available(macOS 26, *) {
                icon.glassEffect(.regular.interactive(), in: Circle())
            } else {
                icon
                    .background(Circle().fill(.ultraThinMaterial))
                    .overlay(Circle().strokeBorder(Board.line, lineWidth: 1))
            }
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

private struct ScheduleSidebarRow: View {
    let symbol: String
    let title: String
    let on: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(on ? Board.accentInkStyle : AnyShapeStyle(Board.muted))
                    .frame(width: 18)
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Board.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(height: 34)
            .background(RoundedRectangle(cornerRadius: 10).fill(on || hover ? Board.column : Color.clear))
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.12), value: hover)
    }
}

private struct ScheduleSidebar: View {
    @ObservedObject var store: ScheduleStore
    let prefsOpen: Bool
    let edit: () -> Void
    let prefs: () -> Void

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 14) {
                todayCard
                sinceCard
                ScheduleHairline().padding(.vertical, 6)
                VStack(alignment: .leading, spacing: 6) {
                    ScheduleSectionTitle(text: "SETTINGS").padding(.bottom, 4)
                    ScheduleSidebarRow(symbol: "square.and.pencil", title: "Change the schedule", on: false, action: edit)
                    ScheduleSidebarRow(symbol: "slider.horizontal.3", title: "Preferences", on: prefsOpen, action: prefs)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 52)
            .padding(.bottom, 20)
        }
        .scrollIndicators(.never)
        .frame(width: 220, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Board.sidebar)
    }

    private var todayCard: some View {
        let slot = store.slotNow
        let items = store.items(on: store.today, slot: slot)
        let done = items.filter(\.done).count
        return card("TODAY") {
            HStack(spacing: 8) {
                Image(systemName: slot.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Board.accentInkStyle)
                Text(slot.label)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Board.ink)
            }
            ScheduleHairline()
            if items.isEmpty {
                figure("Rest", "nothing planned", accent: true, size: 22)
            } else if done == items.count {
                Text("All done for now!")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Board.accentInkStyle)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            } else {
                figure("\(done) of \(items.count)", items.count == 1 ? "step done" : "steps done", accent: true)
            }
        }
    }

    private var sinceCard: some View {
        let tally = store.tally()
        let missed = tally.missed + tally.partial
        let start = ScheduleBoardDates.short(store.firstDay).uppercased()
        return card("SINCE \(start)") {
            HStack(alignment: .firstTextBaseline, spacing: 22) {
                figure("\(tally.done)", tally.done == 1 ? "day done" : "days done", accent: true)
                figure("\(missed)", missed == 1 ? "day missed" : "days missed", accent: false)
            }
        }
    }

    private func card<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ScheduleSectionTitle(text: title)
            VStack(alignment: .leading, spacing: 10, content: content)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 16).fill(Board.column))
                .boardEdge(16)
        }
        .padding(.top, 4)
    }

    private func figure(_ value: String, _ caption: String, accent: Bool, size: CGFloat = 28) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.system(size: size, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(accent ? Board.accentInkStyle : AnyShapeStyle(Board.ink))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(caption)
                .font(.system(size: 11))
                .foregroundStyle(Board.muted)
        }
    }
}

private struct ScheduleWeekStrip: View {
    @ObservedObject var store: ScheduleStore
    @ObservedObject var focus: ScheduleBoardFocus

    var body: some View {
        let start = ScheduleBoardDates.weekStart(focus.selected)
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text(ScheduleBoardDates.weekRange(start))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Board.muted)
                    .monospacedDigit()
                Spacer()
                ScheduleWeekNav(store: store, focus: focus)
            }
            HStack(spacing: 8) {
                ForEach(0..<7, id: \.self) { offset in
                    chip(ScheduleDays.shift(start, by: offset))
                }
            }
        }
    }

    private func chip(_ day: String) -> some View {
        let before = day < store.firstDay
        let selected = focus.span == .day && day == focus.selected
        let today = day == store.today
        return Button {
            if focus.span == .week { note("schedule board span=day day=\(day) from=week") }
            withAnimation(Board.glide) {
                focus.selected = day
                focus.span = .day
            }
        } label: {
            VStack(spacing: 4) {
                Text(ScheduleDays.short(ScheduleDays.weekday(day)).uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1)
                    .foregroundStyle(selected ? Board.ink : Board.muted)
                Text(ScheduleBoardDates.number(day))
                    .font(.system(size: 17, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(today ? Board.accentInkStyle : AnyShapeStyle(Board.ink))
                ScheduleStatusDot(status: store.status(on: day))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 66)
            .background {
                RoundedRectangle(cornerRadius: 14)
                    .fill(selected ? Board.theme.pill : Board.column)
                    .shadow(color: selected ? Board.shadow : .clear, radius: 5, y: 2)
            }
            .boardEdge(14, color: today ? Board.accent : Board.line, width: today ? 1.5 : 1)
            .opacity(before ? 0.4 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .disabled(before)
        .help(before ? "Before the schedule starts" : ScheduleBoardDates.dayTitle(day))
    }
}

private struct ScheduleWeekNav: View {
    @ObservedObject var store: ScheduleStore
    @ObservedObject var focus: ScheduleBoardFocus

    var body: some View {
        let start = ScheduleBoardDates.weekStart(focus.selected)
        let earliest = ScheduleBoardDates.weekStart(store.firstDay)
        let latest = ScheduleBoardDates.weekStart(ScheduleDays.shift(ScheduleBoardDates.monthShift(store.today, by: 2), by: -1))
        HStack(spacing: 10) {
            chevron("chevron.left", enabled: start > earliest) { move(to: max(ScheduleDays.shift(focus.selected, by: -7), store.firstDay)) }
            chevron("chevron.right", enabled: start < latest) { move(to: ScheduleDays.shift(focus.selected, by: 7)) }
        }
    }

    private func move(to day: String) {
        withAnimation(Board.glide) { focus.selected = day }
    }

    private func chevron(_ symbol: String, enabled: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(enabled ? Board.ink : Board.faint)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Board.column))
                .overlay(Circle().stroke(Board.line, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

private struct ScheduleSlotCard: View {
    @ObservedObject var store: ScheduleStore
    let day: String
    let slot: ScheduleSlot

    var body: some View {
        let items = store.items(on: day, slot: slot)
        let done = items.filter(\.done).count
        let now = day == store.today && slot == store.slotNow
        let future = day > store.today
        VStack(alignment: .leading, spacing: 16) {
            header(done: done, total: items.count, now: now)
            if items.isEmpty {
                Text(day < store.firstDay ? "The schedule hasn't started yet" : "Nothing planned. A rest.")
                    .font(.system(size: 12))
                    .foregroundStyle(Board.muted)
                    .padding(.vertical, 6)
            } else {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(groups(items), id: \.routine.id) { group in
                        VStack(alignment: .leading, spacing: 12) {
                            if store.filter == nil {
                                HStack(spacing: 7) {
                                    Circle().fill(Board.hue(group.routine.hue)).frame(width: 7, height: 7)
                                    Text(group.routine.name)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(Board.muted)
                                }
                            }
                            ForEach(group.items) { item in
                                row(item, future: future)
                            }
                        }
                    }
                }
                if !future {
                    let all = done == items.count
                    Button {
                        withAnimation(.smooth(duration: 0.15)) { store.setAll(on: day, slot: slot, done: !all) }
                    } label: {
                        Label(all ? "Undo all" : "Mark all done", systemImage: all ? "arrow.uturn.backward" : "checkmark.circle")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(all ? AnyShapeStyle(Board.muted) : Board.accentInkStyle)
                            .padding(.horizontal, 12)
                            .frame(height: 28)
                            .background(Capsule().fill(Board.accent.opacity(all ? 0.06 : 0.14)))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 16).fill(Board.column))
        .boardEdge(16, color: now ? Board.accent.opacity(0.7) : Board.line)
    }

    private func header(done: Int, total: Int, now: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: slot.symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Board.accentInkStyle)
            Text(slot.label)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Board.ink)
            if now {
                Text("Now")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Board.accentInkStyle)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Board.accent.opacity(0.15)))
            }
            Spacer(minLength: 4)
            if total > 0 {
                Text("\(done)/\(total)")
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(done == total ? Board.accentInkStyle : AnyShapeStyle(Board.muted))
            }
        }
    }

    private func groups(_ items: [ScheduleItem]) -> [(routine: ScheduleRoutine, items: [ScheduleItem])] {
        store.shown.compactMap { routine in
            let list = items.filter { $0.routine.id == routine.id }
            return list.isEmpty ? nil : (routine, list)
        }
    }

    private func row(_ item: ScheduleItem, future: Bool) -> some View {
        Button {
            withAnimation(.smooth(duration: 0.15)) { store.toggle(item) }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(item.done ? Board.accentInkStyle : AnyShapeStyle(Board.faint))
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.step.title)
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(item.done ? Board.muted : Board.ink)
                        .strikethrough(item.done, color: Board.faint)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if !item.step.tip.isEmpty {
                        Text(item.step.tip)
                            .font(.system(size: 12))
                            .foregroundStyle(Board.muted)
                            .multilineTextAlignment(.leading)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(future)
        .opacity(future ? 0.75 : 1)
        .help(future ? "This day hasn't come yet" : item.done ? "Mark as not done" : "Mark as done")
    }
}

private struct ScheduleNotesCard: View {
    @ObservedObject var store: ScheduleStore

    var body: some View {
        let routines = store.shown.filter { !$0.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if !routines.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                ScheduleSectionTitle(text: "NOTES")
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(routines) { routine in
                        VStack(alignment: .leading, spacing: 6) {
                            if store.filter == nil {
                                HStack(spacing: 7) {
                                    Circle().fill(Board.hue(routine.hue)).frame(width: 7, height: 7)
                                    Text(routine.name)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(Board.muted)
                                }
                            }
                            Text(routine.notes.trimmingCharacters(in: .whitespacesAndNewlines))
                                .font(.system(size: 12.5))
                                .foregroundStyle(Board.ink.opacity(0.85))
                                .lineSpacing(3)
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16).fill(Board.column.opacity(Board.theme.embroidery == nil ? 0.55 : 1)))
            .boardEdge(16)
        }
    }
}

private struct ScheduleSpanToggle: View {
    @ObservedObject var store: ScheduleStore
    @ObservedObject var focus: ScheduleBoardFocus
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 2) {
            option("Today", .day)
            option("This week", .week)
        }
        .padding(3)
        .background(Capsule().fill(Board.column))
        .overlay(Capsule().strokeBorder(Board.line, lineWidth: 1))
        .fixedSize()
    }

    private func option(_ title: String, _ span: ScheduleSpan) -> some View {
        let on = focus.span == span
        return Button {
            note("schedule board span=\(span.rawValue) day=\(store.today) from=\(focus.span.rawValue)")
            withAnimation(Board.glide) {
                focus.span = span
                focus.selected = store.today
            }
        } label: {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(on ? Board.ink : Board.muted)
                .padding(.horizontal, 12)
                .frame(height: 26)
                .background {
                    if on {
                        Capsule()
                            .fill(Board.theme.pill)
                            .shadow(color: Board.shadow, radius: 3, y: 1)
                            .matchedGeometryEffect(id: "span", in: pill)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

private enum ScheduleTint {
    static let done = Color(red: 0.42, green: 0.74, blue: 0.48).opacity(0.22)
    static let missed = Color(red: 0.92, green: 0.45, blue: 0.42).opacity(0.18)
}

private struct ScheduleWeekGrid: View {
    @ObservedObject var store: ScheduleStore
    @ObservedObject var focus: ScheduleBoardFocus
    let wide: Bool

    var body: some View {
        let start = ScheduleBoardDates.weekStart(focus.selected)
        let days = (0..<7).map { ScheduleDays.shift(start, by: $0) }
        if wide {
            HStack(alignment: .top, spacing: 6) {
                ForEach(days, id: \.self) { day in
                    VStack(alignment: .leading, spacing: 12) {
                        header(day)
                        ForEach(ScheduleSlot.allCases, id: \.self) { slot in
                            slotBlock(day, slot)
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Board.column.opacity(0.55)))
                    .boardEdge(14, color: day == store.today ? Board.accent.opacity(0.7) : Board.line)
                    .opacity(day < store.firstDay ? 0.4 : 1)
                }
            }
        } else {
            VStack(spacing: 8) {
                ForEach(days, id: \.self) { day in
                    HStack(alignment: .top, spacing: 14) {
                        header(day).frame(width: 44, alignment: .leading)
                        ForEach(ScheduleSlot.allCases, id: \.self) { slot in
                            slotBlock(day, slot).frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Board.column.opacity(0.55)))
                    .boardEdge(14, color: day == store.today ? Board.accent.opacity(0.7) : Board.line)
                    .opacity(day < store.firstDay ? 0.4 : 1)
                }
            }
        }
    }

    private func header(_ day: String) -> some View {
        let today = day == store.today
        let before = day < store.firstDay
        return Button {
            note("schedule board span=day day=\(day) from=week")
            withAnimation(Board.glide) {
                focus.selected = day
                focus.span = .day
            }
        } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text(ScheduleDays.short(ScheduleDays.weekday(day)).uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1)
                    .foregroundStyle(Board.muted)
                Text(ScheduleBoardDates.number(day))
                    .font(.system(size: 17, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(today ? Board.accentInkStyle : AnyShapeStyle(Board.ink))
            }
            .padding(.leading, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(before)
        .help(before ? "Before the schedule starts" : "Open \(ScheduleBoardDates.dayTitle(day))")
    }

    private func slotBlock(_ day: String, _ slot: ScheduleSlot) -> some View {
        let items = day < store.firstDay ? [] : store.items(on: day, slot: slot)
        let status = store.status(on: day, slot: slot)
        let lapsed: Bool = {
            switch status {
            case .missed, .partial: return true
            default: return false
            }
        }()
        return VStack(alignment: .leading, spacing: 5) {
            Image(systemName: slot.symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Board.muted)
                .help(slot.label)
            if items.isEmpty {
                Text("—")
                    .font(.system(size: 11))
                    .foregroundStyle(Board.faint)
            }
            ForEach(items) { item in
                event(item, missed: lapsed && !item.done)
            }
        }
    }

    private func event(_ item: ScheduleItem, missed: Bool) -> some View {
        let future = item.day > store.today
        return Button {
            withAnimation(.smooth(duration: 0.15)) { store.toggle(item) }
        } label: {
            HStack(alignment: .top, spacing: 5) {
                if store.filter == nil && store.shown.count > 1 {
                    Circle().fill(Board.hue(item.routine.hue)).frame(width: 5, height: 5).padding(.top, 5)
                }
                Text(item.step.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Board.ink.opacity(item.done ? 0.75 : 0.95))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(item.done ? ScheduleTint.done : missed ? ScheduleTint.missed : Board.column))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(item.done || missed ? Color.clear : Board.line, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(future)
        .help(item.step.tip.isEmpty ? item.step.title : item.step.tip)
    }
}

private struct ScheduleDayView: View {
    @ObservedObject var store: ScheduleStore
    @ObservedObject var focus: ScheduleBoardFocus

    var body: some View {
        GeometryReader { geo in
            let narrow = geo.size.width < 680
            let layout = narrow ? AnyLayout(VStackLayout(alignment: .leading, spacing: 14)) : AnyLayout(HStackLayout(alignment: .top, spacing: 14))
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 20) {
                    if focus.span == .day {
                        ScheduleWeekStrip(store: store, focus: focus)
                            .transition(.opacity)
                    }
                    title
                    if focus.span == .week {
                        ScheduleWeekGrid(store: store, focus: focus, wide: geo.size.width >= 700)
                            .transition(.opacity)
                    } else {
                        layout {
                            ScheduleSlotCard(store: store, day: focus.selected, slot: .morning)
                            ScheduleSlotCard(store: store, day: focus.selected, slot: .night)
                        }
                        .transition(.opacity)
                    }
                    ScheduleNotesCard(store: store)
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 24)
                .animation(Board.glide, value: narrow)
                .animation(Board.glide, value: focus.span)
            }
            .scrollIndicators(.automatic)
        }
    }

    private var title: some View {
        let day = focus.selected
        return HStack(alignment: .center, spacing: 12) {
            Text(focus.span == .week ? ScheduleBoardDates.weekRange(ScheduleBoardDates.weekStart(day)) : ScheduleBoardDates.dayTitle(day))
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Board.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            ScheduleSpanToggle(store: store, focus: focus)
            Spacer()
            if focus.span == .week {
                ScheduleWeekNav(store: store, focus: focus)
            }
        }
    }
}

private struct ScheduleCalendarView: View {
    @ObservedObject var store: ScheduleStore
    let open: (String) -> Void
    @State private var month: String

    init(store: ScheduleStore, selected: String, open: @escaping (String) -> Void) {
        self.store = store
        self.open = open
        let low = ScheduleBoardDates.monthStart(store.firstDay)
        let high = ScheduleBoardDates.monthShift(store.today, by: 1)
        _month = State(initialValue: min(max(ScheduleBoardDates.monthStart(selected), low), high))
    }

    var body: some View {
        let low = ScheduleBoardDates.monthStart(store.firstDay)
        let high = ScheduleBoardDates.monthShift(store.today, by: 1)
        let length = ScheduleBoardDates.monthLength(month)
        let end = ScheduleDays.shift(month, by: length - 1)
        let tally = store.tally(from: month, through: end)
        let lead = (ScheduleDays.weekday(month) + 5) % 7
        let cells: [String?] = Array(repeating: nil, count: lead) + (0..<length).map { ScheduleDays.shift(month, by: $0) }
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Text(ScheduleBoardDates.monthTitle(month))
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Board.ink)
                    Spacer()
                    if month != ScheduleBoardDates.monthStart(store.today) {
                        Button("This month") { go(ScheduleBoardDates.monthStart(store.today)) }
                            .buttonStyle(.plain)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Board.accentInkStyle)
                    }
                    chevron("chevron.left", enabled: month > low) { go(ScheduleBoardDates.monthShift(month, by: -1)) }
                    chevron("chevron.right", enabled: month < high) { go(ScheduleBoardDates.monthShift(month, by: 1)) }
                }
                Text("\(tally.done) done · \(tally.missed + tally.partial) missed")
                    .font(.system(size: 12, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Board.muted)
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        ForEach(ScheduleDays.weekOrder, id: \.self) { weekday in
                            Text(ScheduleDays.short(weekday).uppercased())
                                .font(.system(size: 10, weight: .semibold))
                                .tracking(1.2)
                                .foregroundStyle(Board.muted)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    ForEach(0..<(cells.count + 6) / 7, id: \.self) { row in
                        HStack(spacing: 8) {
                            ForEach(0..<7, id: \.self) { column in
                                let index = row * 7 + column
                                if index < cells.count, let day = cells[index] {
                                    cell(day)
                                } else {
                                    Color.clear.frame(maxWidth: .infinity).frame(height: 68)
                                }
                            }
                        }
                    }
                }
                .id(month)
                .transition(.opacity)
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
    }

    private func go(_ target: String) {
        withAnimation(Board.glide) { month = target }
    }

    private func chevron(_ symbol: String, enabled: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(enabled ? Board.ink : Board.faint)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Board.column))
                .overlay(Circle().stroke(Board.line, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func cell(_ day: String) -> some View {
        let before = day < store.firstDay
        let today = day == store.today
        return Button {
            open(day)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                Text(ScheduleBoardDates.number(day))
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(today ? Board.accentInkStyle : AnyShapeStyle(Board.ink))
                Spacer(minLength: 0)
                if day <= store.today {
                    HStack {
                        Spacer(minLength: 0)
                        ScheduleSplitMark(morning: store.status(on: day, slot: .morning), night: store.status(on: day, slot: .night))
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 68)
            .background(RoundedRectangle(cornerRadius: 14).fill(Board.column.opacity(before ? 0.5 : 1)))
            .boardEdge(14, color: today ? Board.accent : Board.line, width: today ? 1.5 : 1)
            .opacity(before ? 0.4 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .disabled(before)
        .help(before ? "Before the schedule starts" : ScheduleBoardDates.dayTitle(day))
    }
}

private struct ScheduleHourRow: View {
    let title: String
    let value: Int
    let range: ClosedRange<Int>
    let change: (Int) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(Board.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 4)
            step("minus", -1)
            Text(ScheduleBoardDates.hour(value))
                .font(.system(size: 16, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(Board.ink)
                .frame(width: 56)
            step("plus", 1)
        }
    }

    private func step(_ symbol: String, _ delta: Int) -> some View {
        let target = min(range.upperBound, max(range.lowerBound, value + delta))
        return Button {
            change(target)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(target == value ? Board.faint : Board.ink)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Board.column))
                .overlay(Circle().stroke(Board.line, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(target == value)
    }
}

private struct ScheduleBackupSection: View {
    @ObservedObject var store: ScheduleStore
    @ObservedObject var vault = DataVault.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScheduleSectionTitle(text: "BACKUP")
            line("Daily copy", vault.lastSnapshot.map { "saved \(Self.ago($0))" } ?? "none yet")
            if vault.repoURL != nil {
                line("GitHub", vault.syncProblem ?? vault.lastSync.map { "synced \(Self.ago($0))" } ?? "waiting to sync", warn: vault.syncProblem != nil)
            }
            if let folder = vault.mirrorFolder {
                line("Copy", folder.lastPathComponent == "Pocket Backups" ? "Google Drive" : folder.lastPathComponent)
            }
            if !vault.incoming.isEmpty {
                HStack(spacing: 8) {
                    Button("Bring them in") { vault.bringIn() }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Board.accentInkStyle)
                        .help("Adds what's on GitHub to this Mac, keeping everything here too")
                    Spacer()
                    Button("Keep this Mac's") { confirmKeep() }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Board.muted)
                }
            }
            HStack(spacing: 8) {
                Menu {
                    let snaps = store.snapshots
                    if snaps.isEmpty { Text("No daily copies yet") }
                    ForEach(snaps, id: \.snapshot.id) { entry in
                        Button(Self.label(entry.snapshot.day, routines: entry.routines, checks: entry.checks)) {
                            confirm(entry.snapshot, routines: entry.routines, checks: entry.checks)
                        }
                    }
                } label: {
                    Text("Restore…").font(.system(size: 12, weight: .medium)).foregroundStyle(Board.ink)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .foregroundStyle(Board.ink)
                .tint(Board.ink)
                Spacer()
                Button("Show backups") { vault.showInFinder() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Board.muted)
            }
        }
    }

    private static func label(_ day: Date, routines: Int, checks: Int) -> String {
        "\(ScheduleBoardDates.snapshot(day)) · \(routines) \(routines == 1 ? "routine" : "routines") · \(checks) \(checks == 1 ? "check-off" : "check-offs")"
    }

    private func line(_ title: String, _ value: String, warn: Bool = false) -> some View {
        HStack {
            Text(title).font(.system(size: 12)).foregroundStyle(Board.muted)
            Spacer()
            Text(value).font(.system(size: 12, weight: .medium)).foregroundStyle(warn ? Color.red.opacity(0.8) : Board.ink).lineLimit(1)
        }
    }

    private func confirm(_ snap: VaultSnapshot, routines: Int, checks: Int) {
        let alert = NSAlert()
        alert.messageText = "Restore the schedule from \(ScheduleBoardDates.longSnapshot(snap.day))?"
        alert.informativeText = "The schedule goes back to \(routines) \(routines == 1 ? "routine" : "routines") and \(checks) check-offs. Your current schedule (\(store.routines.count) routines, \(store.book.checks.count) check-offs) is kept as its own backup first, so this can be undone."
        alert.addButton(withTitle: "Restore")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else {
            note("schedule restore cancelled from=\(snap.url.path)")
            return
        }
        store.restore(snap)
    }

    private func confirmKeep() {
        let alert = NSAlert()
        alert.messageText = "Replace the GitHub copy with this Mac's data?"
        alert.informativeText = "GitHub has data this Mac doesn't have. Replacing drops it from the latest copy; it stays in the repo's history."
        alert.addButton(withTitle: "Replace")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else {
            note("pocket vault keep local cancelled from=schedule")
            return
        }
        vault.keepThisMac()
    }

    private static func ago(_ date: Date) -> String {
        date.timeIntervalSinceNow > -60 ? "just now" : date.formatted(.relative(presentation: .named))
    }
}

private struct SchedulePrefsPanel: View {
    @ObservedObject var store: ScheduleStore
    @ObservedObject var themes: BoardThemeStore
    let close: () -> Void

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Preferences")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Board.ink)
                    Spacer()
                    Button(action: close) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Board.muted)
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(Board.column))
                            .overlay(Circle().stroke(Board.line, lineWidth: 1))
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Close preferences")
                }
                ScheduleSectionTitle(text: "DAY").padding(.top, 6)
                ScheduleHourRow(title: "Night routine from", value: store.book.nightFrom, range: (store.book.dayFrom + 1)...23) { hour in
                    store.setNightFrom(hour)
                }
                Text("Morning runs from \(ScheduleBoardDates.hour(store.book.dayFrom)); a day ends at \(ScheduleBoardDates.hour(store.book.dayFrom)) the next morning.")
                    .font(.system(size: 11))
                    .foregroundStyle(Board.muted)
                    .fixedSize(horizontal: false, vertical: true)
                ScheduleHairline().padding(.vertical, 4)
                ScheduleSectionTitle(text: "THEME")
                ThemeLinkRow(source: "schedule")
                ScheduleHairline().padding(.vertical, 4)
                ScheduleBackupSection(store: store)
            }
            .padding(.horizontal, 22)
            .padding(.top, 18)
            .padding(.bottom, 20)
        }
        .scrollIndicators(.never)
        .frame(width: 280, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Board.theme.panel)
    }
}

private struct ScheduleBoardView: View {
    @ObservedObject var store: ScheduleStore
    @ObservedObject var focus: ScheduleBoardFocus
    @ObservedObject var themes = BoardThemeStore.shared
    @AppStorage("schedule.board.stats") private var showStats = true
    @AppStorage("schedule.board.panel") private var showPanel = false
    @AppStorage(ScheduleBoardMode.key) private var mode = ScheduleBoardMode.schedule
    @State private var editing = false

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                if showStats {
                    HStack(spacing: 0) {
                        ScheduleSidebar(store: store, prefsOpen: showPanel, edit: openEditor, prefs: togglePanel)
                        Rectangle().fill(Board.line.opacity(Board.theme.embroidery == nil ? 1 : 0.2)).frame(width: 1)
                    }
                    .transition(.move(edge: .leading).combined(with: .opacity))
                }
                VStack(alignment: .leading, spacing: 16) {
                    topBar
                    ZStack(alignment: .topLeading) {
                        if mode == ScheduleBoardMode.calendar {
                            ScheduleCalendarView(store: store, selected: focus.selected, open: openDay)
                                .transition(.opacity.combined(with: .offset(x: 36)))
                        } else {
                            ScheduleDayView(store: store, focus: focus)
                                .transition(.opacity.combined(with: .offset(x: -36)))
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .clipped()
                }
                if showPanel {
                    HStack(spacing: 0) {
                        Rectangle().fill(Board.line).frame(width: 1)
                        SchedulePrefsPanel(store: store, themes: themes) {
                            note("schedule board preferences open=false")
                            withAnimation(Board.glide) { showPanel = false }
                        }
                    }
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            if editing {
                Color.black.opacity(themes.theme.isDark ? 0.4 : 0.18)
                    .ignoresSafeArea()
                    .transition(.opacity)
                GeometryReader { geo in
                    ScheduleEditorOverlay(store: store, close: closeEditor)
                        .frame(width: geo.size.width * 0.88, height: geo.size.height * 0.88)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .background(RoundedRectangle(cornerRadius: 18).fill(Board.theme.panel).shadow(color: Board.shadow, radius: 30, y: 12))
                        .boardEdge(18)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .animation(.smooth(duration: 0.15), value: editing)
        .animation(Board.glide, value: mode)
        .animation(Board.glide, value: showStats)
        .animation(Board.glide, value: showPanel)
        .id(themes.theme.id)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BoardBackdrop(theme: themes.theme))
        .ignoresSafeArea()
        .environment(\.colorScheme, themes.theme.colorScheme)
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button {
                withAnimation(Board.glide) { showStats.toggle() }
            } label: {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 13))
                    .foregroundStyle(Board.muted)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(showStats ? "Hide sidebar" : "Show sidebar")
            ScheduleModeToggle(mode: $mode)
            ScheduleRoutinePicker(store: store)
            Spacer()
            ScheduleCircleButton(symbol: "slider.horizontal.3", on: showPanel, help: showPanel ? "Close preferences" : "Preferences", action: togglePanel)
        }
        .padding(.leading, showStats ? 20 : 84)
        .padding(.trailing, 20)
        .padding(.top, 12)
    }

    private func togglePanel() {
        note("schedule board preferences open=\(!showPanel)")
        withAnimation(Board.glide) { showPanel.toggle() }
    }

    private func openDay(_ day: String) {
        note("schedule board calendar opened day=\(day) status=\(store.status(on: day))")
        focus.selected = day
        focus.span = .day
        withAnimation(Board.glide) { mode = ScheduleBoardMode.schedule }
    }

    private func openEditor() {
        note("schedule editor opened routines=\(store.routines.count)")
        editing = true
    }

    private func closeEditor() {
        note("schedule editor closed routines=\(store.routines.count)")
        editing = false
    }
}
