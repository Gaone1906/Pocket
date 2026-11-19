import Foundation
import SwiftUI
import UserNotifications

enum CalendarRepeat: String, Codable, CaseIterable, Identifiable {
    case never
    case daily
    case weekdays
    case weekly
    case monthly
    case yearly

    var id: String { rawValue }

    var label: String {
        switch self {
        case .never: return "Never"
        case .daily: return "Every day"
        case .weekdays: return "Weekdays"
        case .weekly: return "Every week"
        case .monthly: return "Every month"
        case .yearly: return "Every year"
        }
    }

    var short: String {
        switch self {
        case .never: return ""
        case .daily: return "Daily"
        case .weekdays: return "Weekdays"
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        case .yearly: return "Yearly"
        }
    }

    fileprivate var step: (Calendar.Component, Int) {
        switch self {
        case .never, .daily, .weekdays: return (.day, 1)
        case .weekly: return (.day, 7)
        case .monthly: return (.month, 1)
        case .yearly: return (.year, 1)
        }
    }
}

struct CalendarEvent: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var start: Date
    var end: Date
    var allDay = false
    var hue = 0
    var location = ""
    var notes = ""
    var alert: Int? = 10
    var repeats: CalendarRepeat = .never
    var until: Date?
    var created = Date()
    var updated = Date()

    init(title: String, start: Date, end: Date, allDay: Bool = false, hue: Int = 0, alert: Int? = 10) {
        self.title = title
        self.start = start
        self.end = end
        self.allDay = allDay
        self.hue = hue
        self.alert = alert
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        start = try c.decode(Date.self, forKey: .start)
        end = try c.decodeIfPresent(Date.self, forKey: .end) ?? start
        allDay = try c.decodeIfPresent(Bool.self, forKey: .allDay) ?? false
        hue = try c.decodeIfPresent(Int.self, forKey: .hue) ?? 0
        location = try c.decodeIfPresent(String.self, forKey: .location) ?? ""
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        alert = try c.decodeIfPresent(Int.self, forKey: .alert)
        repeats = (try? c.decodeIfPresent(CalendarRepeat.self, forKey: .repeats)) ?? .never
        until = try c.decodeIfPresent(Date.self, forKey: .until)
        created = try c.decodeIfPresent(Date.self, forKey: .created) ?? start
        updated = try c.decodeIfPresent(Date.self, forKey: .updated) ?? created
    }

    var length: TimeInterval { max(0, end.timeIntervalSince(start)) }
    var displayTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled" : title }
}

struct CalendarBook: Codable, Equatable {
    var events: [CalendarEvent] = []

    init(events: [CalendarEvent] = []) {
        self.events = events
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        events = try c.decodeIfPresent([CalendarEvent].self, forKey: .events) ?? []
    }
}

struct CalendarOccurrence: Identifiable, Equatable {
    let event: CalendarEvent
    let start: Date
    let end: Date

    var id: String { "\(event.id.uuidString)|\(Int(start.timeIntervalSince1970))" }
    var tint: Color { Board.hue(event.hue) }
}

enum CalendarDays {
    static var calendar: Calendar { Calendar.current }

    static func day(_ date: Date) -> Date { calendar.startOfDay(for: date) }

    static func shift(_ date: Date, days: Int) -> Date {
        calendar.date(byAdding: .day, value: days, to: date) ?? date
    }

    static func monthStart(_ date: Date) -> Date {
        calendar.dateInterval(of: .month, for: date)?.start ?? day(date)
    }

    static func weekStart(_ date: Date) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? day(date)
    }

    static func monthGrid(_ month: Date) -> [Date] {
        let first = monthStart(month)
        let weekday = calendar.component(.weekday, from: first)
        let lead = (weekday - calendar.firstWeekday + 7) % 7
        let start = shift(first, days: -lead)
        return (0..<42).map { shift(start, days: $0) }
    }

    static func week(_ date: Date) -> [Date] {
        let start = weekStart(date)
        return (0..<7).map { shift(start, days: $0) }
    }

    static var weekdaySymbols: [String] {
        let symbols = calendar.shortWeekdaySymbols
        return (0..<7).map { symbols[(calendar.firstWeekday - 1 + $0) % 7] }
    }

    static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    static func span(_ occurrence: CalendarOccurrence) -> String {
        if occurrence.event.allDay { return "All day" }
        guard occurrence.end > occurrence.start else { return time(occurrence.start) }
        return "\(time(occurrence.start)) – \(time(occurrence.end))"
    }

    static func label(_ date: Date) -> String {
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInTomorrow(date) { return "Tomorrow" }
        return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }
}

enum CalendarAlertChoice {
    static let timed: [Int?] = [nil, 0, 5, 10, 15, 30, 60, 120, 1440]
    static let allDay: [Int?] = [nil, 0, 1440]
    static let morningHour = 9

    static func label(_ minutes: Int?, allDay: Bool) -> String {
        guard let minutes else { return "None" }
        if allDay { return minutes == 0 ? "On the day, 9 AM" : "Day before, 9 AM" }
        switch minutes {
        case 0: return "At start"
        case 60: return "1 hour before"
        case 120: return "2 hours before"
        case 1440: return "1 day before"
        default: return "\(minutes) min before"
        }
    }

    static func fireDate(_ occurrence: CalendarOccurrence) -> Date? {
        guard let minutes = occurrence.event.alert else { return nil }
        if occurrence.event.allDay {
            let morning = CalendarDays.calendar.date(bySettingHour: morningHour, minute: 0, second: 0, of: occurrence.start) ?? occurrence.start
            return morning.addingTimeInterval(-Double(minutes) * 60)
        }
        return occurrence.start.addingTimeInterval(-Double(minutes) * 60)
    }
}

protocol CalendarPersistence {
    var location: String { get }
    func load() -> CalendarBook
    func save(_ book: CalendarBook)
    func onIncoming(_ handler: @escaping (CalendarBook) -> Void)
    func keepAside(_ book: CalendarBook, reason: String)
}

struct CalendarVaultPersistence: CalendarPersistence {
    static let name = "calendar"
    let file = PocketData.calendar

    var location: String { file.path }

    static func decode(_ data: Data) throws -> CalendarBook {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(CalendarBook.self, from: data)
    }

    static func encode(_ book: CalendarBook) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(book)
    }

    func load() -> CalendarBook {
        let vault = DataVault.shared
        if FileManager.default.fileExists(atPath: file.path) {
            do {
                let book = try Self.decode(Data(contentsOf: file))
                note("calendar loaded events=\(book.events.count) path=\(file.path)")
                return book
            } catch {
                note("calendar load failed path=\(file.path) error=\(error.localizedDescription)")
                vault.quarantine(file, name: Self.name)
            }
        }
        if let (saved, snap) = vault.recover(Self.name, decode: Self.decode) {
            note("calendar recovered from=\(snap.url.path) events=\(saved.events.count)")
            save(saved)
            return saved
        }
        note("calendar started empty path=\(file.path)")
        return CalendarBook()
    }

    func save(_ book: CalendarBook) {
        do {
            let data = try Self.encode(book)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: file, options: .atomic)
            DataVault.shared.snapshot(data, name: Self.name, count: book.events.count)
        } catch {
            note("calendar save failed events=\(book.events.count) path=\(file.path) error=\(error.localizedDescription)")
        }
    }

    func onIncoming(_ handler: @escaping (CalendarBook) -> Void) {
        DataVault.shared.register(Self.name) { data in
            do {
                handler(try Self.decode(data))
            } catch {
                note("calendar incoming unreadable bytes=\(data.count) error=\(error.localizedDescription)")
            }
        }
    }

    func keepAside(_ book: CalendarBook, reason: String) {
        guard let data = try? Self.encode(book) else { return }
        DataVault.shared.keepAside(data, name: Self.name, reason: reason)
    }
}

final class CalendarStore: ObservableObject {
    static let shared = CalendarStore(persistence: CalendarVaultPersistence())

    @Published private(set) var book: CalendarBook
    @Published private(set) var now = Date()
    private let persistence: CalendarPersistence
    private var clock: Timer?
    private var lastAlerts = Date.distantPast

    init(persistence: CalendarPersistence) {
        self.persistence = persistence
        book = persistence.load()
        persistence.onIncoming { [weak self] incoming in self?.merge(incoming) }
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        clock = timer
    }

    var events: [CalendarEvent] { book.events }
    var today: Date { CalendarDays.day(now) }

    func event(_ id: UUID) -> CalendarEvent? { book.events.first { $0.id == id } }

    func tick() {
        let before = today
        now = Date()
        if today != before {
            note("calendar day changed day=\(today.ISO8601Format())")
            refreshAlerts(reason: "day")
        } else if now.timeIntervalSince(lastAlerts) > 6 * 3600 {
            refreshAlerts(reason: "clock")
        }
    }

    func add(_ event: CalendarEvent) {
        var event = event
        event.created = Date()
        event.updated = event.created
        book.events.append(event)
        commit("added", event)
    }

    func update(_ event: CalendarEvent) {
        guard let index = book.events.firstIndex(where: { $0.id == event.id }) else {
            add(event)
            return
        }
        var event = event
        event.updated = Date()
        book.events[index] = event
        commit("updated", event)
    }

    func delete(_ id: UUID) {
        guard let index = book.events.firstIndex(where: { $0.id == id }) else {
            note("calendar delete missed id=\(id.uuidString)")
            return
        }
        let event = book.events.remove(at: index)
        commit("deleted", event)
    }

    func merge(_ incoming: CalendarBook) {
        persistence.keepAside(book, reason: "before-merge")
        var added = 0
        var newer = 0
        for event in incoming.events {
            if let index = book.events.firstIndex(where: { $0.id == event.id }) {
                if event.updated > book.events[index].updated {
                    book.events[index] = event
                    newer += 1
                }
            } else {
                book.events.append(event)
                added += 1
            }
        }
        persistence.save(book)
        refreshAlerts(reason: "merge")
        note("calendar merged added=\(added) newer=\(newer) events=\(book.events.count)")
    }

    private func commit(_ action: String, _ event: CalendarEvent) {
        persistence.save(book)
        refreshAlerts(reason: action)
        note("calendar event \(action) id=\(event.id.uuidString) start=\(event.start.ISO8601Format()) allDay=\(event.allDay) repeats=\(event.repeats.rawValue) alert=\(event.alert.map(String.init) ?? "none") events=\(book.events.count)")
    }

    func refreshAlerts(reason: String) {
        lastAlerts = Date()
        let horizon = CalendarDays.shift(today, days: CalendarAlerts.horizonDays + 2)
        CalendarAlerts.shared.schedule(occurrences(from: CalendarDays.shift(now, days: -2), to: horizon), reason: reason)
    }

    func occurrences(from start: Date, to end: Date) -> [CalendarOccurrence] {
        book.events
            .flatMap { Self.expand($0, from: start, to: end) }
            .sorted { lhs, rhs in
                if lhs.start != rhs.start { return lhs.start < rhs.start }
                if lhs.event.allDay != rhs.event.allDay { return lhs.event.allDay }
                return lhs.event.displayTitle < rhs.event.displayTitle
            }
    }

    func byDay(from start: Date, to end: Date) -> [Date: [CalendarOccurrence]] {
        var buckets: [Date: [CalendarOccurrence]] = [:]
        for occurrence in occurrences(from: start, to: end) {
            let last = occurrence.end > occurrence.start ? occurrence.end.addingTimeInterval(-1) : occurrence.start
            var day = max(CalendarDays.day(occurrence.start), CalendarDays.day(start))
            let lastDay = CalendarDays.day(last)
            while day <= lastDay && day < end {
                buckets[day, default: []].append(occurrence)
                day = CalendarDays.shift(day, days: 1)
            }
        }
        for key in buckets.keys {
            buckets[key]?.sort { lhs, rhs in
                if lhs.event.allDay != rhs.event.allDay { return lhs.event.allDay }
                return lhs.start < rhs.start
            }
        }
        return buckets
    }

    func on(_ day: Date) -> [CalendarOccurrence] {
        let start = CalendarDays.day(day)
        return byDay(from: start, to: CalendarDays.shift(start, days: 1))[start] ?? []
    }

    func upcoming(limit: Int) -> [CalendarOccurrence] {
        let horizon = CalendarDays.shift(today, days: 60)
        return Array(occurrences(from: now, to: horizon).filter { $0.end > now || $0.start >= today }.prefix(limit))
    }

    static func expand(_ event: CalendarEvent, from start: Date, to end: Date) -> [CalendarOccurrence] {
        let length = event.length
        func overlaps(_ s: Date) -> Bool {
            let e = s.addingTimeInterval(length)
            return s < end && (e > start || (length == 0 && s >= start))
        }
        guard event.repeats != .never else {
            return overlaps(event.start) ? [CalendarOccurrence(event: event, start: event.start, end: event.end)] : []
        }
        let calendar = CalendarDays.calendar
        let (unit, size) = event.repeats.step
        let lastDay = event.until.map { CalendarDays.shift(CalendarDays.day($0), days: 1) }
        var index = 0
        if start > event.start {
            let gap = calendar.dateComponents([unit], from: event.start, to: start.addingTimeInterval(-length)).value(for: unit) ?? 0
            index = max(0, gap / size - 1)
        }
        var results: [CalendarOccurrence] = []
        var guardCount = 0
        while guardCount < 800 {
            guardCount += 1
            guard let s = calendar.date(byAdding: unit, value: index * size, to: event.start) else { break }
            index += 1
            if s >= end { break }
            if let lastDay, s >= lastDay { break }
            if event.repeats == .weekdays, [1, 7].contains(calendar.component(.weekday, from: s)) { continue }
            if overlaps(s) { results.append(CalendarOccurrence(event: event, start: s, end: s.addingTimeInterval(length))) }
        }
        return results
    }
}

final class CalendarAlerts: ObservableObject {
    static let shared = CalendarAlerts()
    static let prefix = "pocket.calendar."
    static let horizonDays = 14
    static let maxPending = 48

    @Published private(set) var permission: UNAuthorizationStatus = .notDetermined

    func schedule(_ occurrences: [CalendarOccurrence], reason: String) {
        guard Bundle.main.bundleIdentifier != nil else {
            note("calendar alerts skipped reason=no bundle trigger=\(reason)")
            return
        }
        let now = Date()
        let horizon = now.addingTimeInterval(Double(Self.horizonDays) * 86400)
        let due = occurrences.compactMap { occurrence -> (CalendarOccurrence, Date)? in
            guard let fire = CalendarAlertChoice.fireDate(occurrence), fire > now, fire < horizon else { return nil }
            return (occurrence, fire)
        }
        .sorted { $0.1 < $1.1 }
        .prefix(Self.maxPending)
        let requests = due.map { Self.request($0.0, fire: $0.1) }
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { pending in
            let stale = pending.map(\.identifier).filter { $0.hasPrefix(Self.prefix) }
            center.removePendingNotificationRequests(withIdentifiers: stale)
            let failures = NSLock()
            var failed = 0
            let group = DispatchGroup()
            for request in requests {
                group.enter()
                center.add(request) { error in
                    if let error {
                        failures.lock()
                        failed += 1
                        failures.unlock()
                        note("calendar alert failed id=\(request.identifier) error=\(error.localizedDescription)")
                    }
                    group.leave()
                }
            }
            let next = due.first.map { $0.1.ISO8601Format() } ?? "none"
            group.notify(queue: .main) {
                note("calendar alerts scheduled trigger=\(reason) count=\(requests.count) removed=\(stale.count) failed=\(failed) next=\(next)")
            }
        }
    }

    func clear(reason: String) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { pending in
            let stale = pending.map(\.identifier).filter { $0.hasPrefix(Self.prefix) }
            center.removePendingNotificationRequests(withIdentifiers: stale)
            note("calendar alerts cleared trigger=\(reason) removed=\(stale.count)")
        }
    }

    func checkPermission(_ done: @escaping (UNAuthorizationStatus) -> Void) {
        guard Bundle.main.bundleIdentifier != nil else { return done(.notDetermined) }
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.permission = settings.authorizationStatus
                done(settings.authorizationStatus)
            }
        }
    }

    private static func request(_ occurrence: CalendarOccurrence, fire: Date) -> UNNotificationRequest {
        let event = occurrence.event
        let content = UNMutableNotificationContent()
        content.title = event.displayTitle
        content.body = body(occurrence, fire: fire)
        content.sound = .default
        content.threadIdentifier = "calendar"
        content.userInfo = ["app": "calendar", "event": event.id.uuidString]
        let parts = CalendarDays.calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: fire)
        let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
        return UNNotificationRequest(identifier: prefix + occurrence.id, content: content, trigger: trigger)
    }

    private static func body(_ occurrence: CalendarOccurrence, fire: Date) -> String {
        let event = occurrence.event
        var parts: [String] = []
        if event.allDay {
            parts.append(CalendarDays.calendar.isDate(fire, inSameDayAs: occurrence.start) ? "Today, all day" : "Tomorrow, all day")
        } else if let minutes = event.alert, minutes > 0 {
            let lead = minutes >= 1440 ? "Tomorrow" : minutes >= 60 ? "In \(minutes / 60) hour\(minutes >= 120 ? "s" : "")" : "In \(minutes) min"
            parts.append("\(lead) · \(CalendarDays.span(occurrence))")
        } else {
            parts.append("Now · \(CalendarDays.span(occurrence))")
        }
        let place = event.location.trimmingCharacters(in: .whitespacesAndNewlines)
        if !place.isEmpty { parts.append(place) }
        return parts.joined(separator: " · ")
    }
}
