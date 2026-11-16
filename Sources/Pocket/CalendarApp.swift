import AppKit
import EventKit
import SwiftUI

struct CalendarEntry: Identifiable {
    let id = UUID()
    let title: String
    let start: Date
    let end: Date
    let allDay: Bool
    let color: Color
}

enum CalendarAccess {
    case granted
    case undetermined
    case denied
}

final class CalendarModel: ObservableObject {
    @Published var visibleMonth: Date
    @Published var selectedDay: Date
    @Published var eventsByDay: [Date: [CalendarEntry]] = [:]
    @Published var access: CalendarAccess = CalendarModel.currentAccess()

    var isPanelShown: () -> Bool = { false }

    private let calendar = Calendar.current
    private let fetchQueue = DispatchQueue(label: "pocket.calendar.fetch", qos: .userInitiated)
    private var generation = 0
    private var hasLoaded = false
    private var isDirty = false
    private var storeObserver: NSObjectProtocol?

    init() {
        let today = Calendar.current.startOfDay(for: Date())
        selectedDay = today
        visibleMonth = Calendar.current.dateInterval(of: .month, for: today)?.start ?? today
    }

    static func currentAccess() -> CalendarAccess {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess, .authorized: return .granted
        case .notDetermined: return .undetermined
        default: return .denied
        }
    }

    var gridStart: Date {
        let weekday = calendar.component(.weekday, from: visibleMonth)
        let offset = (weekday - calendar.firstWeekday + 7) % 7
        return calendar.date(byAdding: .day, value: -offset, to: visibleMonth) ?? visibleMonth
    }

    var gridDays: [Date] {
        let start = gridStart
        return (0..<42).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    var weekdaySymbols: [String] {
        let symbols = calendar.shortWeekdaySymbols
        return (0..<7).map { symbols[(calendar.firstWeekday - 1 + $0) % 7] }
    }

    var monthTitle: String {
        visibleMonth.formatted(.dateTime.month(.wide).year())
    }

    var selectedEntries: [CalendarEntry] {
        eventsByDay[calendar.startOfDay(for: selectedDay)] ?? []
    }

    func entries(on day: Date) -> [CalendarEntry] {
        eventsByDay[calendar.startOfDay(for: day)] ?? []
    }

    func isInVisibleMonth(_ day: Date) -> Bool {
        calendar.isDate(day, equalTo: visibleMonth, toGranularity: .month)
    }

    func startObserving() {
        guard storeObserver == nil else { return }
        storeObserver = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: CalendarApp.store, queue: .main) { [weak self] _ in
            guard let self else { return }
            if self.isPanelShown() { self.fetch() } else { self.isDirty = true }
        }
    }

    func stopObserving() {
        if let storeObserver { NotificationCenter.default.removeObserver(storeObserver) }
        storeObserver = nil
    }

    func activate() {
        access = Self.currentAccess()
        guard access == .granted else { return }
        if !hasLoaded || isDirty { fetch() }
    }

    func requestAccess() {
        CalendarApp.requestAccess { [weak self] granted in
            guard let self else { return }
            self.access = Self.currentAccess()
            if granted { self.fetch() }
        }
    }

    func openPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") else { return }
        NSWorkspace.shared.open(url)
    }

    func shiftMonth(by months: Int) {
        guard let moved = calendar.date(byAdding: .month, value: months, to: visibleMonth) else { return }
        showMonth(of: moved, preferredDay: nil)
    }

    func goToToday() {
        showMonth(of: Date(), preferredDay: calendar.startOfDay(for: Date()))
    }

    func select(_ day: Date) {
        selectedDay = calendar.startOfDay(for: day)
        if !isInVisibleMonth(day) { showMonth(of: day, preferredDay: selectedDay) }
    }

    private func showMonth(of date: Date, preferredDay: Date?) {
        let month = calendar.dateInterval(of: .month, for: date)?.start ?? date
        visibleMonth = month
        if let preferredDay {
            selectedDay = preferredDay
        } else if !isInVisibleMonth(selectedDay) {
            let today = calendar.startOfDay(for: Date())
            selectedDay = isInVisibleMonth(today) ? today : month
        }
        fetch()
    }

    private func monthLabel() -> String {
        let parts = calendar.dateComponents([.year, .month], from: visibleMonth)
        return String(format: "%04d-%02d", parts.year ?? 0, parts.month ?? 0)
    }

    func fetch() {
        let label = monthLabel()
        guard CalendarModel.currentAccess() == .granted else {
            note("pocket calendar fetch skipped month=\(label) reason=no access")
            return
        }
        generation += 1
        let ticket = generation
        hasLoaded = true
        isDirty = false
        let rangeStart = gridStart
        let rangeEnd = calendar.date(byAdding: .day, value: 42, to: rangeStart) ?? rangeStart
        let calendar = self.calendar
        fetchQueue.async { [weak self] in
            let store = CalendarApp.store
            let predicate = store.predicateForEvents(withStart: rangeStart, end: rangeEnd, calendars: nil)
            let events = store.events(matching: predicate)
            let buckets = Self.bucket(events, calendar: calendar, rangeStart: rangeStart, rangeEnd: rangeEnd)
            DispatchQueue.main.async {
                guard let self, ticket == self.generation else { return }
                self.eventsByDay = buckets
                note("pocket calendar fetched month=\(label) events=\(events.count)")
            }
        }
    }

    private static func bucket(_ events: [EKEvent], calendar: Calendar, rangeStart: Date, rangeEnd: Date) -> [Date: [CalendarEntry]] {
        var buckets: [Date: [CalendarEntry]] = [:]
        for event in events {
            guard let start = event.startDate, let end = event.endDate else { continue }
            let cgColor: CGColor? = event.calendar?.cgColor
            let entry = CalendarEntry(
                title: event.title ?? "Untitled",
                start: start,
                end: end,
                allDay: event.isAllDay,
                color: cgColor.map { Color(cgColor: $0) } ?? .accentColor
            )
            let lastMoment = end > start ? end.addingTimeInterval(-1) : start
            var day = max(calendar.startOfDay(for: start), rangeStart)
            let lastDay = calendar.startOfDay(for: lastMoment)
            while day <= lastDay && day < rangeEnd {
                buckets[day, default: []].append(entry)
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
            }
        }
        for key in buckets.keys {
            buckets[key]?.sort { lhs, rhs in
                if lhs.allDay != rhs.allDay { return lhs.allDay }
                return lhs.start < rhs.start
            }
        }
        return buckets
    }
}

struct ScrollMonthStepper {
    private var accumulated: CGFloat = 0
    private var locked = false
    private let threshold: CGFloat = 30

    mutating func step(for event: NSEvent) -> Int {
        if event.phase == .began || event.phase == .mayBegin {
            accumulated = 0
            locked = false
        }
        let phased = !event.phase.isEmpty || !event.momentumPhase.isEmpty
        let ended = event.phase == .ended || event.phase == .cancelled || event.momentumPhase == .ended
        defer {
            if ended {
                accumulated = 0
                locked = false
            }
        }
        guard !locked else { return 0 }
        accumulated += event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * 10
        guard abs(accumulated) >= threshold else { return 0 }
        let direction = accumulated < 0 ? 1 : -1
        accumulated = 0
        locked = phased
        return direction
    }
}

struct CalendarRoot: View {
    @ObservedObject var model: CalendarModel

    var body: some View {
        VStack(spacing: 10) {
            header
            switch model.access {
            case .granted:
                weekdayRow
                monthGrid
                Divider()
                dayList
            case .undetermined:
                permissionPrompt(message: "Pocket shows the events from your Calendar app.", button: "Allow Calendar access") { model.requestAccess() }
            case .denied:
                permissionPrompt(message: "Calendar access is turned off for Pocket.", button: "Open Privacy Settings") { model.openPrivacySettings() }
            }
        }
        .padding(.top, 28)
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(model.monthTitle)
                .font(.title2.weight(.semibold))
            Spacer()
            Button { model.shiftMonth(by: -1) } label: { Image(systemName: "chevron.left") }
            Button("Today") { model.goToToday() }
            Button { model.shiftMonth(by: 1) } label: { Image(systemName: "chevron.right") }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private var weekdayRow: some View {
        HStack(spacing: 2) {
            ForEach(Array(model.weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var monthGrid: some View {
        let days = model.gridDays
        return VStack(spacing: 2) {
            ForEach(0..<6, id: \.self) { week in
                HStack(spacing: 2) {
                    ForEach(0..<7, id: \.self) { column in
                        let day = days[week * 7 + column]
                        DayCell(
                            day: day,
                            entries: model.entries(on: day),
                            inMonth: model.isInVisibleMonth(day),
                            selected: Calendar.current.isDate(day, inSameDayAs: model.selectedDay)
                        )
                        .onTapGesture { model.select(day) }
                    }
                }
            }
        }
    }

    private var dayList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(model.selectedDay.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                .font(.headline)
            let entries = model.selectedEntries
            if entries.isEmpty {
                Text("No events")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(entries) { entry in
                            EntryRow(entry: entry)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func permissionPrompt(message: String, button: String, action: @escaping () -> Void) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button(button, action: action)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct DayCell: View {
    let day: Date
    let entries: [CalendarEntry]
    let inMonth: Bool
    let selected: Bool

    private var isToday: Bool { Calendar.current.isDateInToday(day) }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("\(Calendar.current.component(.day, from: day))")
                .font(.system(size: 11, weight: isToday ? .bold : .regular))
                .foregroundStyle(isToday ? Color.white : Color.primary)
                .frame(width: 18, height: 18)
                .background(Circle().fill(isToday ? Color.accentColor : Color.clear))
            ForEach(entries.prefix(2)) { entry in
                HStack(spacing: 3) {
                    Circle().fill(entry.color).frame(width: 5, height: 5)
                    Text(entry.title)
                        .font(.system(size: 9))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            if entries.count > 2 {
                Text("+\(entries.count - 2)")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(3)
        .frame(maxWidth: .infinity, minHeight: 58, maxHeight: 58, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 6).fill(selected ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(selected ? Color.accentColor : Color.clear, lineWidth: 1.5))
        .opacity(inMonth ? 1 : 0.4)
        .contentShape(Rectangle())
    }
}

struct EntryRow: View {
    let entry: CalendarEntry

    private var timeText: String {
        if entry.allDay { return "All day" }
        let start = entry.start.formatted(date: .omitted, time: .shortened)
        let end = entry.end.formatted(date: .omitted, time: .shortened)
        return "\(start) – \(end)"
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            RoundedRectangle(cornerRadius: 2).fill(entry.color).frame(width: 4, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                Text(timeText).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }
}

final class CalendarApp: PocketApp {
    static let store = EKEventStore()

    static var hasAccess: Bool { CalendarModel.currentAccess() == .granted }

    static func requestAccess(done: @escaping (Bool) -> Void) {
        store.requestFullAccessToEvents { granted, error in
            if granted { store.reset() }
            note("pocket calendar access requested granted=\(granted) error=\(error.map { "\($0)" } ?? "none")")
            DispatchQueue.main.async { done(granted) }
        }
    }

    let model = CalendarModel()
    private var scrollMonitor: Any?
    private var stepper = ScrollMonthStepper()

    override init(spec: AppSpec) {
        super.init(spec: spec)
        model.isPanelShown = { [weak self] in self?.isShown ?? false }
    }

    override var resizable: Bool { false }
    override var defaultSize: NSSize { NSSize(width: 560, height: 620) }

    override func makeContent() -> NSView {
        NSHostingView(rootView: CalendarRoot(model: model))
    }

    override func start() {
        model.startObserving()
    }

    override func didShow() {
        installScrollMonitor()
        model.activate()
    }

    override func didHide() {
        removeScrollMonitor()
    }

    override func stop() {
        removeScrollMonitor()
        model.stopObserving()
        super.stop()
    }

    private func installScrollMonitor() {
        guard scrollMonitor == nil else { return }
        stepper = ScrollMonthStepper()
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, let panel = self.panelIfLoaded, event.window === panel, self.model.access == .granted else { return event }
            let direction = self.stepper.step(for: event)
            if direction != 0 { self.model.shiftMonth(by: direction) }
            return event
        }
    }

    private func removeScrollMonitor() {
        if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
        scrollMonitor = nil
    }
}
