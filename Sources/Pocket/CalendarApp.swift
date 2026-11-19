import AppKit
import Combine
import SwiftUI

final class CalendarDropdownState: ObservableObject {
    @Published var month: Date
    @Published var selected: Date
    private var shownToday: Date

    init() {
        let today = CalendarDays.day(Date())
        shownToday = today
        selected = today
        month = CalendarDays.monthStart(today)
    }

    func catchUp(today: Date) {
        guard today != shownToday else { return }
        shownToday = today
        selected = today
        month = CalendarDays.monthStart(today)
    }

    func shift(_ months: Int) {
        guard let moved = CalendarDays.calendar.date(byAdding: .month, value: months, to: month) else { return }
        month = CalendarDays.monthStart(moved)
        guard !CalendarDays.calendar.isDate(selected, equalTo: month, toGranularity: .month) else { return }
        let today = CalendarDays.day(Date())
        selected = CalendarDays.calendar.isDate(today, equalTo: month, toGranularity: .month) ? today : month
    }

    func goToday() {
        selected = CalendarDays.day(Date())
        month = CalendarDays.monthStart(selected)
    }

    func select(_ day: Date) {
        selected = CalendarDays.day(day)
        if !CalendarDays.calendar.isDate(day, equalTo: month, toGranularity: .month) { month = CalendarDays.monthStart(day) }
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

struct CalendarDropdown: View {
    @ObservedObject var store: CalendarStore
    @ObservedObject var state: CalendarDropdownState
    @ObservedObject var themes = BoardThemeStore.shared
    let open: (CalendarBoardRequest) -> Void

    var body: some View {
        let days = CalendarDays.monthGrid(state.month)
        let buckets = store.byDay(from: days[0], to: CalendarDays.shift(days[41], days: 1))
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 18)
                .padding(.top, 20)
                .padding(.bottom, 14)
            VStack(spacing: 6) {
                HStack(spacing: 4) {
                    ForEach(Array(CalendarDays.weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                        Text(symbol.uppercased())
                            .font(.system(size: 9, weight: .semibold))
                            .tracking(1.2)
                            .foregroundStyle(Board.muted)
                            .frame(maxWidth: .infinity)
                    }
                }
                ForEach(0..<6, id: \.self) { row in
                    HStack(spacing: 4) {
                        ForEach(0..<7, id: \.self) { column in
                            let day = days[row * 7 + column]
                            CalendarMiniCell(day: day,
                                             occurrences: buckets[day] ?? [],
                                             inMonth: CalendarDays.calendar.isDate(day, equalTo: state.month, toGranularity: .month),
                                             selected: day == state.selected,
                                             today: day == store.today)
                                .onTapGesture(count: 2) { open(.create(day)) }
                                .onTapGesture { withAnimation(Board.glide) { state.select(day) } }
                        }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
            CalendarHairline()
            CalendarAgenda(day: state.selected, today: store.today, occurrences: buckets[state.selected] ?? store.on(state.selected), open: open)
        }
        .id(themes.theme.id)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BoardBackdrop(theme: themes.theme))
        .ignoresSafeArea()
        .environment(\.colorScheme, themes.theme.colorScheme)
    }

    private var header: some View {
        HStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(state.month.formatted(.dateTime.month(.wide)))
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(Board.ink)
                Text(state.month.formatted(.dateTime.year()))
                    .font(.system(size: 19, weight: .regular))
                    .foregroundStyle(Board.muted)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            Spacer(minLength: 6)
            if !CalendarDays.calendar.isDate(state.month, equalTo: store.today, toGranularity: .month) {
                Button("Today") { withAnimation(Board.glide) { state.goToday() } }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Board.accentInkStyle)
            }
            HStack(spacing: 6) {
                CalendarCircleChip(symbol: "chevron.left", help: "Previous month") { withAnimation(Board.glide) { state.shift(-1) } }
                CalendarCircleChip(symbol: "chevron.right", help: "Next month") { withAnimation(Board.glide) { state.shift(1) } }
                CalendarCircleChip(symbol: "plus", help: "New event") { open(.create(state.selected)) }
                CalendarCircleChip(symbol: "arrow.up.left.and.arrow.down.right", help: "Open the calendar in its own window") { open(.browse(state.selected)) }
            }
        }
    }
}

private struct CalendarMiniCell: View {
    let day: Date
    let occurrences: [CalendarOccurrence]
    let inMonth: Bool
    let selected: Bool
    let today: Bool

    var body: some View {
        VStack(spacing: 5) {
            Text("\(CalendarDays.calendar.component(.day, from: day))")
                .font(.system(size: 12, weight: today || selected ? .bold : .medium))
                .monospacedDigit()
                .foregroundStyle(today ? Board.accentInkStyle : AnyShapeStyle(Board.ink))
            HStack(spacing: 3) {
                ForEach(occurrences.prefix(3)) { occurrence in
                    Circle().fill(occurrence.tint).frame(width: 5, height: 5)
                }
            }
            .frame(height: 5)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 42)
        .background(RoundedRectangle(cornerRadius: 12).fill(selected ? Board.accent.opacity(0.16) : Board.column))
        .boardEdge(12, color: today ? Board.accent : Board.line, width: today ? 1.5 : 1)
        .opacity(inMonth ? 1 : 0.4)
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .help(occurrences.isEmpty ? CalendarDays.label(day) : occurrences.map(\.event.displayTitle).joined(separator: ", "))
    }
}

private struct CalendarAgenda: View {
    let day: Date
    let today: Date
    let occurrences: [CalendarOccurrence]
    let open: (CalendarBoardRequest) -> Void

    private var heading: String {
        let date = day.formatted(.dateTime.weekday(.wide).day().month(.abbreviated)).uppercased()
        if day == today { return "TODAY · \(date)" }
        if day == CalendarDays.shift(today, days: 1) { return "TOMORROW · \(date)" }
        return date
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                CalendarSectionTitle(text: heading)
                Spacer()
                Button {
                    open(.create(day))
                } label: {
                    Label("Add", systemImage: "plus")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Board.accentInkStyle)
                }
                .buttonStyle(.plain)
            }
            if occurrences.isEmpty {
                VStack(spacing: 6) {
                    Text("Nothing planned")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Board.muted)
                    Text("Double-click a day to add an event")
                        .font(.system(size: 11))
                        .foregroundStyle(Board.faint)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(occurrences) { occurrence in
                            Button {
                                open(.edit(occurrence.event.id))
                            } label: {
                                CalendarAgendaRow(occurrence: occurrence)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.bottom, 12)
                }
                .scrollIndicators(.never)
                .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.86), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct CalendarAgendaRow: View {
    let occurrence: CalendarOccurrence
    @State private var hover = false

    private var detail: String {
        var parts = [CalendarDays.span(occurrence)]
        let place = occurrence.event.location.trimmingCharacters(in: .whitespacesAndNewlines)
        if !place.isEmpty { parts.append(place) }
        if occurrence.event.repeats != .never { parts.append(occurrence.event.repeats.short) }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2).fill(occurrence.tint).frame(width: 4, height: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(occurrence.event.displayTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Board.ink)
                    .lineLimit(1)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(Board.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if occurrence.event.alert != nil {
                Image(systemName: "bell")
                    .font(.system(size: 10))
                    .foregroundStyle(Board.faint)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 12).fill(hover ? occurrence.tint.opacity(0.18) : Board.column))
        .boardEdge(12)
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.12), value: hover)
    }
}

final class CalendarApp: PocketApp {
    let state = CalendarDropdownState()
    private var themeWatch: AnyCancellable?
    private var scrollMonitor: Any?
    private var stepper = ScrollMonthStepper()

    override var resizable: Bool { false }
    override var defaultSize: NSSize { NSSize(width: 400, height: 600) }

    override func makeContent() -> NSView {
        let view = CalendarDropdown(store: CalendarStore.shared, state: state) { [weak self] request in
            self?.openBoard(request, source: "dropdown")
        }
        let hosting = NSHostingView(rootView: view)
        hosting.appearance = BoardThemeStore.shared.theme.appearance
        themeWatch = BoardThemeStore.shared.$theme.sink { [weak hosting] theme in hosting?.appearance = theme.appearance }
        return hosting
    }

    override func start() {
        let store = CalendarStore.shared
        store.refreshAlerts(reason: "launch")
        note("calendar app started events=\(store.events.count) path=\(PocketData.calendar.path)")
    }

    override func didShow() {
        let store = CalendarStore.shared
        store.tick()
        state.catchUp(today: store.today)
        installScrollMonitor()
    }

    override func didHide() {
        removeScrollMonitor()
    }

    override func stop() {
        removeScrollMonitor()
        if !Layout.shared.enabled.contains(spec.id) { CalendarAlerts.shared.clear(reason: "disabled") }
        super.stop()
    }

    override func menuItems() -> [NSMenuItem] {
        let open = NSMenuItem(title: "Open calendar", action: #selector(openFromMenu), keyEquivalent: "")
        open.target = self
        let add = NSMenuItem(title: "New event", action: #selector(newFromMenu), keyEquivalent: "")
        add.target = self
        return [open, add]
    }

    @objc private func openFromMenu() {
        openBoard(.browse(CalendarStore.shared.today), source: "menu")
    }

    @objc private func newFromMenu() {
        openBoard(.create(CalendarStore.shared.today), source: "menu")
    }

    private func openBoard(_ request: CalendarBoardRequest, source: String) {
        hide(reason: "switched")
        note("calendar board requested source=\(source) request=\(request.label)")
        CalendarBoardWindow.shared.present(request)
    }

    private func installScrollMonitor() {
        guard scrollMonitor == nil else { return }
        stepper = ScrollMonthStepper()
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, let panel = self.panelIfLoaded, event.window === panel else { return event }
            let point = event.locationInWindow
            guard point.y > panel.frame.height * 0.4 else { return event }
            let direction = self.stepper.step(for: event)
            if direction != 0 { withAnimation(Board.glide) { self.state.shift(direction) } }
            return event
        }
    }

    private func removeScrollMonitor() {
        if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
        scrollMonitor = nil
    }
}
