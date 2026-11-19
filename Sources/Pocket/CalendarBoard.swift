import AppKit
import Combine
import SwiftUI

enum CalendarBoardRequest {
    case browse(Date)
    case create(Date)
    case edit(UUID)

    var label: String {
        switch self {
        case .browse(let day): return "browse day=\(day.ISO8601Format())"
        case .create(let day): return "create day=\(day.ISO8601Format())"
        case .edit(let id): return "edit id=\(id.uuidString)"
        }
    }
}

enum CalendarBoardMode: String {
    case month
    case week

    static let key = "calendar.board.mode"
}

struct CalendarDraft: Identifiable {
    let id = UUID()
    var event: CalendarEvent
    let isNew: Bool

    static let alertKey = "calendar.alert.default"

    static var defaultAlert: Int? {
        let stored = UserDefaults.standard.object(forKey: alertKey) as? Int ?? 10
        return stored < 0 ? nil : stored
    }

    static func new(on day: Date, hour: Int? = nil, store: CalendarStore) -> CalendarDraft {
        let calendar = CalendarDays.calendar
        let base = CalendarDays.day(day)
        let start: Date
        if let hour {
            start = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: base) ?? base
        } else if base == store.today {
            let next = calendar.component(.hour, from: store.now) + 1
            start = next < 24 ? calendar.date(bySettingHour: next, minute: 0, second: 0, of: base) ?? base
                : calendar.date(bySettingHour: 9, minute: 0, second: 0, of: CalendarDays.shift(base, days: 1)) ?? base
        } else {
            start = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: base) ?? base
        }
        let event = CalendarEvent(title: "", start: start, end: start.addingTimeInterval(3600), hue: store.events.count % Board.hueCount, alert: defaultAlert)
        return CalendarDraft(event: event, isNew: true)
    }
}

final class CalendarBoardState: ObservableObject {
    @Published var anchor: Date
    @Published var mode: CalendarBoardMode {
        didSet {
            UserDefaults.standard.set(mode.rawValue, forKey: CalendarBoardMode.key)
            note("calendar board view mode=\(mode.rawValue)")
        }
    }
    @Published var draft: CalendarDraft?

    init() {
        anchor = CalendarDays.day(Date())
        mode = UserDefaults.standard.string(forKey: CalendarBoardMode.key).flatMap(CalendarBoardMode.init(rawValue:)) ?? .month
    }

    var title: String {
        switch mode {
        case .month:
            return anchor.formatted(.dateTime.month(.wide).year())
        case .week:
            let days = CalendarDays.week(anchor)
            let first = days[0]
            let last = days[6]
            if CalendarDays.calendar.isDate(first, equalTo: last, toGranularity: .month) {
                return "\(first.formatted(.dateTime.day())) – \(last.formatted(.dateTime.day().month(.abbreviated).year()))"
            }
            return "\(first.formatted(.dateTime.day().month(.abbreviated))) – \(last.formatted(.dateTime.day().month(.abbreviated).year()))"
        }
    }

    func step(_ direction: Int) {
        let calendar = CalendarDays.calendar
        switch mode {
        case .month:
            let moved = calendar.date(byAdding: .month, value: direction, to: CalendarDays.monthStart(anchor)) ?? anchor
            anchor = CalendarDays.monthStart(moved)
        case .week:
            anchor = CalendarDays.shift(anchor, days: 7 * direction)
        }
    }

    func create(on day: Date, hour: Int? = nil, store: CalendarStore) {
        draft = CalendarDraft.new(on: day, hour: hour, store: store)
        note("calendar editor opened new=true day=\(day.ISO8601Format()) hour=\(hour.map(String.init) ?? "auto")")
    }

    func edit(_ event: CalendarEvent) {
        draft = CalendarDraft(event: event, isNew: false)
        note("calendar editor opened new=false id=\(event.id.uuidString)")
    }
}

final class CalendarBoardWindow: NSObject, NSWindowDelegate {
    static let shared = CalendarBoardWindow()

    let state = CalendarBoardState()
    private var window: NSWindow?
    private var themeWatch: AnyCancellable?

    func present(_ request: CalendarBoardRequest) {
        apply(request)
        NSApp.setActivationPolicy(.regular)
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            note("calendar board refocused \(request.label)")
            return
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1080, height: 720),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = "Calendar"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.appearance = Board.theme.appearance
        window.backgroundColor = NSColor(Board.backdrop)
        themeWatch = BoardThemeStore.shared.$theme.sink { [weak window] theme in
            window?.appearance = theme.appearance
            window?.backgroundColor = NSColor(theme.backdrop)
        }
        window.minSize = NSSize(width: 760, height: 560)
        window.contentView = NSHostingView(rootView: CalendarBoardView(store: CalendarStore.shared, state: state))
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        window.setFrameAutosaveName("calendar.board")
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        note("calendar board opened \(request.label) mode=\(state.mode.rawValue) events=\(CalendarStore.shared.events.count)")
    }

    private func apply(_ request: CalendarBoardRequest) {
        let store = CalendarStore.shared
        switch request {
        case .browse(let day):
            state.anchor = CalendarDays.day(day)
        case .create(let day):
            state.anchor = CalendarDays.day(day)
            state.create(on: day, store: store)
        case .edit(let id):
            guard let event = store.event(id) else {
                note("calendar board edit missed id=\(id.uuidString)")
                return
            }
            state.anchor = CalendarDays.day(event.start)
            state.edit(event)
        }
    }

    func windowWillClose(_ notification: Notification) {
        let closing = window
        window?.delegate = nil
        window = nil
        themeWatch = nil
        state.draft = nil
        let others = NSApp.windows.contains { $0 !== closing && $0.isVisible && $0.styleMask.contains(.titled) && $0.canBecomeMain }
        if !others { NSApp.setActivationPolicy(.accessory) }
        note("calendar board closed otherWindows=\(others)")
    }
}

struct CalendarSectionTitle: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .tracking(1.6)
            .foregroundStyle(Board.muted)
            .lineLimit(1)
    }
}

struct CalendarHairline: View {
    var body: some View {
        Rectangle().fill(Board.line.opacity(Board.theme.embroidery == nil ? 1 : 0.35)).frame(height: 1)
    }
}

struct CalendarGlass<Content: View>: View {
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

struct CalendarCircleChip: View {
    let symbol: String
    let help: String
    var enabled = true
    let action: () -> Void

    var body: some View {
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
        .help(help)
    }
}

struct CalendarAccentButton: View {
    let title: String
    var symbol: String? = nil
    var height: CGFloat = 34
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let symbol { Image(systemName: symbol).font(.system(size: 11, weight: .bold)) }
                Text(title).font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(Board.theme.isDark ? Color.black.opacity(0.85) : Color.white)
            .padding(.horizontal, 16)
            .frame(height: height)
            .background(Capsule().fill(Board.accentStyle))
            .shadow(color: Board.shadow, radius: 4, y: 1)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct CalendarModeToggle: View {
    @Binding var mode: CalendarBoardMode
    @Namespace private var pill

    private let options: [(String, CalendarBoardMode)] = [("Month", .month), ("Week", .week)]

    var body: some View {
        CalendarGlass {
            HStack(spacing: 2) {
                ForEach(options, id: \.1) { title, value in
                    Button {
                        guard mode != value else { return }
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

private struct CalendarSidebar: View {
    @ObservedObject var store: CalendarStore
    @ObservedObject var state: CalendarBoardState
    @ObservedObject var alerts = CalendarAlerts.shared
    @AppStorage(CalendarDraft.alertKey) private var defaultAlert = 10

    var body: some View {
        let today = store.on(store.today)
        let week = CalendarDays.week(store.today)
        let weekCount = store.occurrences(from: week[0], to: CalendarDays.shift(week[6], days: 1)).count
        let next = store.upcoming(limit: 6)
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 18) {
                stat("TODAY", today.count)
                stat("THIS WEEK", weekCount)
            }
            VStack(alignment: .leading, spacing: 10) {
                CalendarSectionTitle(text: "UP NEXT")
                if next.isEmpty {
                    Text("Nothing coming up")
                        .font(.system(size: 12))
                        .foregroundStyle(Board.faint)
                } else {
                    ForEach(next) { occurrence in
                        Button {
                            state.anchor = CalendarDays.day(occurrence.start)
                            state.edit(occurrence.event)
                        } label: {
                            upNext(occurrence)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 10) {
                CalendarSectionTitle(text: "ALERTS")
                Menu {
                    ForEach(CalendarAlertChoice.timed, id: \.self) { minutes in
                        Button(CalendarAlertChoice.label(minutes, allDay: false)) {
                            defaultAlert = minutes ?? -1
                            note("calendar default alert minutes=\(minutes.map(String.init) ?? "none")")
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "bell")
                        Text(CalendarAlertChoice.label(defaultAlert < 0 ? nil : defaultAlert, allDay: false))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .bold))
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Board.ink)
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Board.column))
                    .boardEdge(10)
                    .contentShape(Rectangle())
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .help("Default alert for new events")
                if alerts.permission == .denied {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Notifications are off for Pocket, so alerts won't show.")
                            .font(.system(size: 11))
                            .foregroundStyle(Board.muted)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Open Notification Settings") {
                            let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")
                            let opened = url.map { NSWorkspace.shared.open($0) } ?? false
                            note("calendar opened notification settings opened=\(opened)")
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Board.accentInkStyle)
                    }
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 56)
        .padding(.bottom, 20)
        .frame(width: 240, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Board.sidebar)
        .onAppear { alerts.checkPermission { _ in } }
    }

    private func stat(_ title: String, _ value: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            CalendarSectionTitle(text: title)
            Text("\(value)")
                .font(.system(size: 30, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(Board.ink)
            Text(value == 1 ? "event" : "events")
                .font(.system(size: 11))
                .foregroundStyle(Board.muted)
        }
    }

    private func upNext(_ occurrence: CalendarOccurrence) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Circle().fill(occurrence.tint).frame(width: 8, height: 8).padding(.top, 4)
            VStack(alignment: .leading, spacing: 2) {
                Text(occurrence.event.displayTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Board.ink)
                    .lineLimit(1)
                Text(occurrence.event.allDay ? "\(CalendarDays.label(occurrence.start)) · All day" : "\(CalendarDays.label(occurrence.start)) · \(CalendarDays.time(occurrence.start))")
                    .font(.system(size: 11))
                    .foregroundStyle(Board.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }
}

private struct CalendarEventChip: View {
    let occurrence: CalendarOccurrence
    let day: Date
    @State private var hover = false

    var body: some View {
        let event = occurrence.event
        HStack(spacing: 5) {
            if event.allDay {
                Text(event.displayTitle)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Board.ink)
                    .lineLimit(1)
                Spacer(minLength: 0)
            } else {
                Circle().fill(occurrence.tint).frame(width: 6, height: 6)
                Text(event.displayTitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Board.ink)
                    .lineLimit(1)
                Spacer(minLength: 2)
                if CalendarDays.calendar.isDate(occurrence.start, inSameDayAs: day) {
                    Text(CalendarDays.time(occurrence.start))
                        .font(.system(size: 10))
                        .monospacedDigit()
                        .foregroundStyle(Board.faint)
                        .lineLimit(1)
                        .layoutPriority(-1)
                }
            }
        }
        .padding(.horizontal, 6)
        .frame(height: 19)
        .background(RoundedRectangle(cornerRadius: 6).fill(event.allDay ? occurrence.tint.opacity(hover ? 0.5 : 0.32) : (hover ? occurrence.tint.opacity(0.2) : Color.clear)))
        .contentShape(RoundedRectangle(cornerRadius: 6))
        .onHover { hover = $0 }
        .help("\(event.displayTitle) · \(CalendarDays.span(occurrence))")
    }
}

private struct CalendarMonthView: View {
    @ObservedObject var store: CalendarStore
    @ObservedObject var state: CalendarBoardState

    var body: some View {
        let days = CalendarDays.monthGrid(state.anchor)
        let buckets = store.byDay(from: days[0], to: CalendarDays.shift(days[41], days: 1))
        GeometryReader { geo in
            let rowHeight = max(76, (geo.size.height - 26 - 6 * 8) / 6)
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    ForEach(Array(CalendarDays.weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                        Text(symbol.uppercased())
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(1.2)
                            .foregroundStyle(Board.muted)
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 18)
                ForEach(0..<6, id: \.self) { row in
                    HStack(spacing: 8) {
                        ForEach(0..<7, id: \.self) { column in
                            let day = days[row * 7 + column]
                            cell(day, occurrences: buckets[day] ?? [], height: rowHeight)
                        }
                    }
                }
            }
            .id(CalendarDays.monthStart(state.anchor))
            .transition(.opacity)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
    }

    private func cell(_ day: Date, occurrences: [CalendarOccurrence], height: CGFloat) -> some View {
        let inMonth = CalendarDays.calendar.isDate(day, equalTo: state.anchor, toGranularity: .month)
        let today = day == store.today
        let selected = day == state.anchor
        let capacity = max(1, Int((height - 34) / 21))
        let shown = occurrences.count > capacity ? capacity - 1 : capacity
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("\(CalendarDays.calendar.component(.day, from: day))")
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(today ? AnyShapeStyle(Board.theme.isDark ? Color.black.opacity(0.85) : Color.white) : AnyShapeStyle(Board.ink))
                    .frame(minWidth: 22, minHeight: 22)
                    .background(Circle().fill(today ? Board.accentStyle : AnyShapeStyle(Color.clear)))
                Spacer(minLength: 0)
            }
            .padding(.bottom, 2)
            ForEach(occurrences.prefix(shown)) { occurrence in
                Button {
                    state.edit(occurrence.event)
                } label: {
                    CalendarEventChip(occurrence: occurrence, day: day)
                }
                .buttonStyle(.plain)
            }
            if occurrences.count > capacity {
                Text("+\(occurrences.count - shown) more")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Board.muted)
                    .padding(.leading, 6)
            }
            Spacer(minLength: 0)
        }
        .padding(7)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: height)
        .background(RoundedRectangle(cornerRadius: 14).fill(selected ? Board.accent.opacity(0.1) : Board.column))
        .boardEdge(14, color: selected ? Board.accent : Board.line, width: selected ? 1.5 : 1)
        .opacity(inMonth ? 1 : 0.45)
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .onTapGesture(count: 2) { state.create(on: day, store: store) }
        .onTapGesture { withAnimation(Board.glide) { state.anchor = day } }
    }
}

private struct CalendarLanes {
    static func assign(_ occurrences: [CalendarOccurrence]) -> (lanes: [String: Int], count: Int) {
        var ends: [Date] = []
        var lanes: [String: Int] = [:]
        for occurrence in occurrences.sorted(by: { $0.start < $1.start }) {
            let end = max(occurrence.end, occurrence.start.addingTimeInterval(1800))
            if let free = ends.firstIndex(where: { $0 <= occurrence.start }) {
                lanes[occurrence.id] = free
                ends[free] = end
            } else {
                lanes[occurrence.id] = ends.count
                ends.append(end)
            }
        }
        return (lanes, max(1, ends.count))
    }
}

private struct CalendarWeekView: View {
    @ObservedObject var store: CalendarStore
    @ObservedObject var state: CalendarBoardState

    private let hourHeight: CGFloat = 48
    private let gutter: CGFloat = 56

    var body: some View {
        let days = CalendarDays.week(state.anchor)
        let buckets = store.byDay(from: days[0], to: CalendarDays.shift(days[6], days: 1))
        let allDay = days.map { day in (buckets[day] ?? []).filter(\.event.allDay) }
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Color.clear.frame(width: gutter - 6, height: 1)
                ForEach(days, id: \.self) { day in
                    header(day)
                }
            }
            .padding(.bottom, 8)
            if allDay.contains(where: { !$0.isEmpty }) {
                HStack(alignment: .top, spacing: 6) {
                    Text("all-day")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Board.faint)
                        .frame(width: gutter - 6, alignment: .trailing)
                        .padding(.top, 3)
                    ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                        VStack(spacing: 2) {
                            ForEach(allDay[index].prefix(2)) { occurrence in
                                Button {
                                    state.edit(occurrence.event)
                                } label: {
                                    CalendarEventChip(occurrence: occurrence, day: day)
                                }
                                .buttonStyle(.plain)
                            }
                            if allDay[index].count > 2 {
                                Text("+\(allDay[index].count - 2)")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(Board.muted)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .top)
                    }
                }
                .padding(.bottom, 8)
            }
            CalendarHairline()
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    ZStack(alignment: .topLeading) {
                        grid
                        HStack(spacing: 6) {
                            Color.clear.frame(width: gutter - 6)
                            ForEach(days, id: \.self) { day in
                                column(day, occurrences: (buckets[day] ?? []).filter { !$0.event.allDay })
                            }
                        }
                    }
                    .frame(height: hourHeight * 24)
                    .padding(.top, 8)
                    .padding(.bottom, 12)
                }
                .scrollIndicators(.never)
                .onAppear { proxy.scrollTo(7, anchor: .top) }
            }
        }
        .id(CalendarDays.weekStart(state.anchor))
        .transition(.opacity)
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    private func header(_ day: Date) -> some View {
        let today = day == store.today
        let selected = day == state.anchor
        return Button {
            withAnimation(Board.glide) { state.anchor = day }
        } label: {
            VStack(spacing: 3) {
                Text(day.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(today ? Board.accentInkStyle : AnyShapeStyle(Board.muted))
                Text("\(CalendarDays.calendar.component(.day, from: day))")
                    .font(.system(size: 20, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(today ? Board.accentInkStyle : AnyShapeStyle(Board.ink))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(RoundedRectangle(cornerRadius: 12).fill(selected ? Board.accent.opacity(0.1) : Color.clear))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private var grid: some View {
        VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { hour in
                HStack(alignment: .top, spacing: 6) {
                    Text(hour == 0 ? "" : hourLabel(hour))
                        .font(.system(size: 10, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(Board.faint)
                        .frame(width: gutter - 12, alignment: .trailing)
                        .offset(y: -6)
                    Rectangle().fill(Board.line.opacity(Board.theme.embroidery == nil ? 0.7 : 0.25)).frame(height: 1)
                }
                .frame(height: hourHeight, alignment: .top)
                .id(hour)
            }
        }
    }

    private func hourLabel(_ hour: Int) -> String {
        let date = CalendarDays.calendar.date(bySettingHour: hour, minute: 0, second: 0, of: store.today) ?? store.today
        return date.formatted(.dateTime.hour())
    }

    private func column(_ day: Date, occurrences: [CalendarOccurrence]) -> some View {
        let layout = CalendarLanes.assign(occurrences)
        let today = day == store.today
        return GeometryReader { geo in
            let laneWidth = geo.size.width / CGFloat(layout.count)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(today ? Board.accent.opacity(0.06) : Color.clear)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2, coordinateSpace: .local) { point in
                        let hour = min(23, max(0, Int(point.y / hourHeight)))
                        state.create(on: day, hour: hour, store: store)
                    }
                ForEach(occurrences) { occurrence in
                    let top = offset(occurrence.start, on: day)
                    let bottom = max(top + 22, offset(occurrence.end, on: day, clampEnd: true))
                    let lane = CGFloat(layout.lanes[occurrence.id] ?? 0)
                    Button {
                        state.edit(occurrence.event)
                    } label: {
                        block(occurrence, height: bottom - top - 2)
                    }
                    .buttonStyle(.plain)
                    .frame(width: max(20, laneWidth - 3), height: bottom - top - 2)
                    .offset(x: lane * laneWidth, y: top + 1)
                }
                if today {
                    let y = offset(store.now, on: day)
                    HStack(spacing: 0) {
                        Circle().fill(Board.accentStyle).frame(width: 7, height: 7)
                        Rectangle().fill(Board.accentStyle).frame(height: 1.5)
                    }
                    .offset(x: -3.5, y: y - 3.5)
                    .allowsHitTesting(false)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func offset(_ date: Date, on day: Date, clampEnd: Bool = false) -> CGFloat {
        let start = CalendarDays.day(day)
        let minutes = date.timeIntervalSince(start) / 60
        let limit = clampEnd ? 24.0 * 60 : 24.0 * 60 - 15
        return CGFloat(min(max(0, minutes), limit)) / 60 * hourHeight
    }

    private func block(_ occurrence: CalendarOccurrence, height: CGFloat) -> some View {
        HStack(spacing: 0) {
            Rectangle().fill(occurrence.tint).frame(width: 3)
            VStack(alignment: .leading, spacing: 1) {
                Text(occurrence.event.displayTitle)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Board.ink)
                    .lineLimit(height > 40 ? 2 : 1)
                if height > 34 {
                    Text(CalendarDays.span(occurrence))
                        .font(.system(size: 10))
                        .monospacedDigit()
                        .foregroundStyle(Board.muted)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(occurrence.tint.opacity(Board.theme.isDark ? 0.3 : 0.26))
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .contentShape(RoundedRectangle(cornerRadius: 7))
        .help("\(occurrence.event.displayTitle) · \(CalendarDays.span(occurrence))")
    }
}

struct CalendarBoardView: View {
    @ObservedObject var store: CalendarStore
    @ObservedObject var state: CalendarBoardState
    @ObservedObject var themes = BoardThemeStore.shared
    @AppStorage("calendar.board.sidebar") private var showSidebar = true

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                if showSidebar {
                    HStack(spacing: 0) {
                        CalendarSidebar(store: store, state: state)
                        Rectangle().fill(Board.line.opacity(Board.theme.embroidery == nil ? 1 : 0.2)).frame(width: 1)
                    }
                    .transition(.move(edge: .leading).combined(with: .opacity))
                }
                VStack(alignment: .leading, spacing: 16) {
                    topBar
                    ZStack(alignment: .topLeading) {
                        if state.mode == .month {
                            CalendarMonthView(store: store, state: state)
                                .transition(.opacity.combined(with: .offset(x: -36)))
                        } else {
                            CalendarWeekView(store: store, state: state)
                                .transition(.opacity.combined(with: .offset(x: 36)))
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .clipped()
                }
            }
            if let draft = state.draft {
                Color.black.opacity(themes.theme.isDark ? 0.4 : 0.18)
                    .ignoresSafeArea()
                    .onTapGesture { state.draft = nil }
                    .transition(.opacity)
                CalendarEditorCard(store: store, draft: draft) {
                    state.draft = nil
                }
                .id(draft.id)
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .animation(.smooth(duration: 0.15), value: state.draft?.id)
        .animation(Board.glide, value: state.mode)
        .animation(Board.glide, value: showSidebar)
        .id(themes.theme.id)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BoardBackdrop(theme: themes.theme))
        .ignoresSafeArea()
        .environment(\.colorScheme, themes.theme.colorScheme)
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button {
                withAnimation(Board.glide) { showSidebar.toggle() }
            } label: {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 13))
                    .foregroundStyle(Board.muted)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(showSidebar ? "Hide sidebar" : "Show sidebar")
            CalendarModeToggle(mode: $state.mode)
            Text(state.title)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Board.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.leading, 6)
            Spacer(minLength: 8)
            if !isCurrent {
                Button("Today") { withAnimation(Board.glide) { state.anchor = store.today } }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Board.accentInkStyle)
            }
            CalendarCircleChip(symbol: "chevron.left", help: state.mode == .month ? "Previous month" : "Previous week") {
                withAnimation(Board.glide) { state.step(-1) }
            }
            CalendarCircleChip(symbol: "chevron.right", help: state.mode == .month ? "Next month" : "Next week") {
                withAnimation(Board.glide) { state.step(1) }
            }
            CalendarAccentButton(title: "New event", symbol: "plus") {
                state.create(on: state.anchor, store: store)
            }
        }
        .padding(.leading, showSidebar ? 20 : 84)
        .padding(.trailing, 20)
        .padding(.top, 12)
    }

    private var isCurrent: Bool {
        switch state.mode {
        case .month: return CalendarDays.calendar.isDate(state.anchor, equalTo: store.today, toGranularity: .month)
        case .week: return CalendarDays.weekStart(state.anchor) == CalendarDays.weekStart(store.today)
        }
    }
}
