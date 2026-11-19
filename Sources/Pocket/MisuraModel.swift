import AppKit
import Combine
import Foundation
import SwiftUI
import UserNotifications

enum MisuraBoard: BoardScope {
    static var theme: BoardTheme { AppThemeStore.shared.theme(for: "calorie") }
    static let over = Color(hue: 8, saturation: 62, lightness: 50)
    static let overInk = Color(hue: 8, saturation: 60, lightness: 42)
    static let under = Color(hue: 145, saturation: 45, lightness: 32)
    static let food = Color(hue: 28, saturation: 80, lightness: 40)
    static let burn = Color(hue: 145, saturation: 38, lightness: 64)
}

struct MisuraPlan: Codable, Equatable {
    var born: String
    var sex: String
    var heightCm: Double
    var activity: Double
    var startDay: String
    var startKg: Double
    var goalKg: Double
    var goalDay: String
    var pace: String = "fastest"
    var floor: Double = 1500
    var watchShare: Double = 0.75
    var eatBack: Bool = false
    var menuLeft: Bool = true
    var weighAt: String? = "07:00"

    init(born: String, sex: String, heightCm: Double, activity: Double, startDay: String, startKg: Double, goalKg: Double, goalDay: String) {
        self.born = born
        self.sex = sex
        self.heightCm = heightCm
        self.activity = activity
        self.startDay = startDay
        self.startKg = startKg
        self.goalKg = goalKg
        self.goalDay = goalDay
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        born = try c.decodeIfPresent(String.self, forKey: .born) ?? "2000-01-01"
        sex = try c.decodeIfPresent(String.self, forKey: .sex) ?? "male"
        heightCm = try c.decodeIfPresent(Double.self, forKey: .heightCm) ?? 170
        activity = try c.decodeIfPresent(Double.self, forKey: .activity) ?? 1.2
        startDay = try c.decodeIfPresent(String.self, forKey: .startDay) ?? MisuraDays.today()
        startKg = try c.decodeIfPresent(Double.self, forKey: .startKg) ?? 80
        goalKg = try c.decodeIfPresent(Double.self, forKey: .goalKg) ?? startKg
        goalDay = try c.decodeIfPresent(String.self, forKey: .goalDay) ?? MisuraDays.shift(startDay, by: 180)
        pace = try c.decodeIfPresent(String.self, forKey: .pace) ?? "fastest"
        floor = try c.decodeIfPresent(Double.self, forKey: .floor) ?? 1500
        watchShare = try c.decodeIfPresent(Double.self, forKey: .watchShare) ?? 0.75
        eatBack = try c.decodeIfPresent(Bool.self, forKey: .eatBack) ?? false
        menuLeft = try c.decodeIfPresent(Bool.self, forKey: .menuLeft) ?? true
        weighAt = try c.decodeIfPresent(String.self, forKey: .weighAt)
    }
}

struct MisuraEntry: Codable, Equatable, Identifiable {
    var id: String
    var day: String
    var kind: String
    var slot: String?
    var title: String
    var kcal: Double
    var at: String?
    var updated: String?

    var isWorkout: Bool { kind == "workout" }
}

struct MisuraWeight: Codable, Equatable, Identifiable {
    var id: String
    var day: String
    var kg: Double
    var updated: String?
}

struct MisuraBook: Codable, Equatable {
    var plan: MisuraPlan?
    var entries: [MisuraEntry] = []
    var weights: [MisuraWeight] = []

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        plan = try c.decodeIfPresent(MisuraPlan.self, forKey: .plan)
        entries = try c.decodeIfPresent([MisuraEntry].self, forKey: .entries) ?? []
        weights = try c.decodeIfPresent([MisuraWeight].self, forKey: .weights) ?? []
    }
}

enum MisuraSlot: String, CaseIterable, Identifiable {
    case breakfast
    case lunch
    case snack
    case dinner

    var id: String { rawValue }
    var label: String { rawValue.capitalized }

    static func now(_ date: Date = Date()) -> MisuraSlot {
        let hour = Calendar.current.component(.hour, from: date)
        if hour >= 4 && hour < 11 { return .breakfast }
        if hour < 16 && hour >= 11 { return .lunch }
        if hour < 19 && hour >= 16 { return .snack }
        return .dinner
    }
}

enum MisuraDays {
    static let rollover = 4
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        calendar.firstWeekday = 2
        return calendar
    }

    private static let keyFormat: DateFormatter = {
        let format = DateFormatter()
        format.calendar = Calendar(identifier: .gregorian)
        format.locale = Locale(identifier: "en_US_POSIX")
        format.timeZone = .current
        format.dateFormat = "yyyy-MM-dd"
        return format
    }()

    static func key(_ date: Date) -> String { keyFormat.string(from: date) }
    static func date(_ key: String) -> Date? { keyFormat.date(from: key) }

    static func today(_ now: Date = Date()) -> String {
        key(now.addingTimeInterval(-Double(rollover) * 3600))
    }

    static func shift(_ key: String, by days: Int) -> String {
        guard let date = date(key), let moved = calendar.date(byAdding: .day, value: days, to: date) else { return key }
        return self.key(moved)
    }

    static func between(_ from: String, _ to: String) -> Int {
        guard let a = date(from), let b = date(to) else { return 0 }
        return calendar.dateComponents([.day], from: a, to: b).day ?? 0
    }

    static func weekStart(_ key: String) -> String {
        guard let d = date(key) else { return key }
        let weekday = calendar.component(.weekday, from: d)
        return shift(key, by: -((weekday + 5) % 7))
    }

    static func week(_ key: String) -> [String] {
        let start = weekStart(key)
        return (0..<7).map { shift(start, by: $0) }
    }

    static func monthStart(_ key: String) -> String { String(key.prefix(8)) + "01" }

    static func monthDays(_ key: String) -> [String] {
        let start = monthStart(key)
        guard let d = date(start), let range = calendar.range(of: .day, in: .month, for: d) else { return [start] }
        return range.map { shift(start, by: $0 - 1) }
    }

    static func monthShift(_ key: String, by months: Int) -> String {
        guard let d = date(monthStart(key)), let moved = calendar.date(byAdding: .month, value: months, to: d) else { return key }
        return self.key(moved)
    }

    static func weekday(_ key: String) -> Int { date(key).map { calendar.component(.weekday, from: $0) } ?? 1 }
    static func dayNumber(_ key: String) -> Int { Int(key.suffix(2)) ?? 0 }

    static func format(_ key: String, _ template: String) -> String {
        guard let d = date(key) else { return key }
        let format = DateFormatter()
        format.locale = .current
        format.setLocalizedDateFormatFromTemplate(template)
        return format.string(from: d)
    }

    static func long(_ key: String) -> String { format(key, "EEEEdMMMM") }
    static func short(_ key: String) -> String { format(key, "dMMM") }
    static func weekdayShort(_ key: String) -> String { format(key, "EEE") }
    static func month(_ key: String) -> String { format(key, "MMMMyyyy") }
}

struct MisuraDay: Equatable {
    let day: String
    let eaten: Double
    let workoutRaw: Double
    let workout: Double
    let base: Double
    let budget: Double
    let logged: Bool

    var allowance: Double { budget }
    var left: Double { budget - eaten }
    var deficit: Double { logged ? base + workout - eaten : 0 }
    var over: Bool { logged && eaten > budget }
}

struct MisuraSpan: Equatable {
    let days: [MisuraDay]
    let goal: Double
    let due: Double

    var deficit: Double { days.reduce(0) { $0 + $1.deficit } }
    var logged: [MisuraDay] { days.filter(\.logged) }
    var avgEaten: Double { logged.isEmpty ? 0 : logged.reduce(0) { $0 + $1.eaten } / Double(logged.count) }
    var workouts: Double { days.reduce(0) { $0 + $1.workout } }
    var underLimit: Bool { deficit >= due }
}

enum MisuraMath {
    static let kcalPerKg = 7700.0

    static func age(_ born: String, on day: String) -> Double {
        Double(MisuraDays.between(born, day)) / 365.2425
    }

    static func bmr(_ plan: MisuraPlan, kg: Double, on day: String) -> Double {
        let years = age(plan.born, on: day).rounded(.down)
        return 10 * kg + 6.25 * plan.heightCm - 5 * years + (plan.sex == "female" ? -161 : 5)
    }

    static func base(_ plan: MisuraPlan, kg: Double, on day: String) -> Double {
        bmr(plan, kg: kg, on: day) * plan.activity
    }

    static func totalDays(_ plan: MisuraPlan) -> Int { max(1, MisuraDays.between(plan.startDay, plan.goalDay)) }

    static func dailyGoal(_ plan: MisuraPlan) -> Double {
        max(0, (plan.startKg - plan.goalKg) * kcalPerKg / Double(totalDays(plan))).rounded()
    }

    static func budget(_ plan: MisuraPlan, base: Double) -> Double {
        if plan.pace == "ontime" { return max(plan.floor, (base - dailyGoal(plan)).rounded()) }
        return plan.floor
    }

    static func lostByGoal(_ plan: MisuraPlan) -> Double { plan.startKg - plan.goalKg }
}

final class MisuraStore: ObservableObject {
    static let shared = MisuraStore()
    static let name = "calorie"

    @Published private(set) var book = MisuraBook()
    @Published private(set) var today = MisuraDays.today()
    var onChange: (() -> Void)?
    private let file = PocketData.calorie
    private var clock: Timer?

    private static let stamp: ISO8601DateFormatter = {
        let format = ISO8601DateFormatter()
        format.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return format
    }()

    private init() {
        let vault = DataVault.shared
        vault.register(Self.name) { [weak self] data in self?.merge(data) }
        CloudSync.shared.register(Self.name) { [weak self] data in self?.adopt(data) }
        book = load()
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        clock = timer
        MisuraReminder.refresh(self, reason: "launch")
    }

    private func load() -> MisuraBook {
        let vault = DataVault.shared
        if FileManager.default.fileExists(atPath: file.path) {
            do {
                let loaded = try Self.decode(Data(contentsOf: file))
                note("misura loaded entries=\(loaded.entries.count) weights=\(loaded.weights.count) plan=\(loaded.plan != nil) path=\(file.path)")
                return loaded
            } catch {
                note("misura load failed path=\(file.path) error=\(error.localizedDescription)")
                vault.quarantine(file, name: Self.name)
            }
        }
        if let (saved, snap) = vault.recover(Self.name, decode: Self.decode) {
            note("misura recovered from=\(snap.url.path) entries=\(saved.entries.count) weights=\(saved.weights.count)")
            write(saved)
            return saved
        }
        note("misura started empty path=\(file.path)")
        return MisuraBook()
    }

    static func decode(_ data: Data) throws -> MisuraBook {
        try JSONDecoder().decode(MisuraBook.self, from: data)
    }

    static func encode(_ book: MisuraBook) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(book)
    }

    static func now() -> String { stamp.string(from: Date()) }

    var plan: MisuraPlan? { book.plan }

    func tick() {
        let next = MisuraDays.today()
        guard next != today else { return }
        today = next
        note("misura day changed day=\(today)")
        MisuraReminder.refresh(self, reason: "day")
        onChange?()
    }

    func setPlan(_ plan: MisuraPlan) {
        guard plan != book.plan else { return }
        let first = book.plan == nil
        book.plan = plan
        commit()
        MisuraReminder.refresh(self, reason: "plan")
        note("misura plan \(first ? "created" : "changed") start=\(plan.startDay) startKg=\(plan.startKg) goalKg=\(plan.goalKg) goalDay=\(plan.goalDay) pace=\(plan.pace) floor=\(Int(plan.floor)) share=\(plan.watchShare) eatBack=\(plan.eatBack) goal=\(Int(MisuraMath.dailyGoal(plan)))")
    }

    func editPlan(_ change: (inout MisuraPlan) -> Void) {
        guard var plan = book.plan else { return }
        change(&plan)
        setPlan(plan)
    }

    @discardableResult
    func add(kind: String, title: String, kcal: Double, day: String? = nil, slot: MisuraSlot? = nil) -> MisuraEntry? {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard kcal > 0, kcal < 20000 else {
            note("misura add rejected kind=\(kind) kcal=\(kcal)")
            return nil
        }
        let on = day ?? today
        let entry = MisuraEntry(id: UUID().uuidString, day: on, kind: kind,
                                slot: kind == "meal" ? (slot ?? MisuraSlot.now()).rawValue : nil,
                                title: name.isEmpty ? (kind == "meal" ? "Meal" : "Workout") : name,
                                kcal: kcal.rounded(), at: Self.now(), updated: Self.now())
        book.entries.append(entry)
        commit()
        note("misura entry added kind=\(kind) day=\(on) slot=\(entry.slot ?? "-") kcal=\(Int(entry.kcal)) entries=\(book.entries.count)")
        return entry
    }

    func update(_ entry: MisuraEntry) {
        guard let index = book.entries.firstIndex(where: { $0.id == entry.id }) else { return }
        var entry = entry
        entry.title = entry.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard entry.kcal > 0, entry != book.entries[index] else { return }
        entry.updated = Self.now()
        book.entries[index] = entry
        commit()
        note("misura entry updated id=\(entry.id) kind=\(entry.kind) day=\(entry.day) kcal=\(Int(entry.kcal))")
    }

    func delete(_ id: String) {
        guard let index = book.entries.firstIndex(where: { $0.id == id }) else { return }
        let entry = book.entries.remove(at: index)
        commit()
        note("misura entry deleted id=\(id) kind=\(entry.kind) day=\(entry.day) kcal=\(Int(entry.kcal)) entries=\(book.entries.count)")
    }

    func weigh(_ kg: Double, on day: String? = nil) {
        guard kg >= 25, kg <= 400 else {
            note("misura weight rejected kg=\(kg)")
            return
        }
        let on = day ?? today
        let value = (kg * 10).rounded() / 10
        if let index = book.weights.firstIndex(where: { $0.day == on }) {
            guard book.weights[index].kg != value else { return }
            book.weights[index].kg = value
            book.weights[index].updated = Self.now()
        } else {
            book.weights.append(MisuraWeight(id: on, day: on, kg: value, updated: Self.now()))
        }
        commit()
        MisuraReminder.refresh(self, reason: "weighed")
        note("misura weighed day=\(on) kg=\(value) weights=\(book.weights.count)")
    }

    func entries(on day: String) -> [MisuraEntry] {
        book.entries.filter { $0.day == day }.sorted { ($0.at ?? "") < ($1.at ?? "") }
    }

    func meals(on day: String, slot: MisuraSlot) -> [MisuraEntry] {
        entries(on: day).filter { !$0.isWorkout && ($0.slot ?? "snack") == slot.rawValue }
    }

    func workouts(on day: String) -> [MisuraEntry] { entries(on: day).filter(\.isWorkout) }

    func weight(on day: String) -> Double? { book.weights.first { $0.day == day }?.kg }

    func weightAsOf(_ day: String) -> Double? {
        book.weights.filter { $0.day <= day }.max { $0.day < $1.day }?.kg ?? plan?.startKg
    }

    func average(_ day: String) -> Double? {
        let from = MisuraDays.shift(day, by: -6)
        let list = book.weights.filter { $0.day >= from && $0.day <= day }
        guard !list.isEmpty else { return weightAsOf(day) }
        return ((list.reduce(0) { $0 + $1.kg } / Double(list.count)) * 10).rounded() / 10
    }

    func summary(_ day: String) -> MisuraDay? {
        guard let plan else { return nil }
        let list = entries(on: day)
        let eaten = list.filter { !$0.isWorkout }.reduce(0) { $0 + $1.kcal }
        let raw = list.filter(\.isWorkout).reduce(0) { $0 + $1.kcal }
        let workout = (raw * plan.watchShare).rounded()
        let base = MisuraMath.base(plan, kg: weightAsOf(day) ?? plan.startKg, on: day).rounded()
        let budget = MisuraMath.budget(plan, base: base) + (plan.eatBack ? workout : 0)
        return MisuraDay(day: day, eaten: eaten, workoutRaw: raw, workout: workout, base: base, budget: budget,
                         logged: list.contains { !$0.isWorkout })
    }

    func span(_ days: [String]) -> MisuraSpan? {
        guard let plan else { return nil }
        let goal = MisuraMath.dailyGoal(plan)
        let summaries = days.compactMap(summary)
        let elapsed = days.filter { $0 <= today && $0 >= plan.startDay }.count
        let active = days.filter { $0 >= plan.startDay && $0 <= plan.goalDay }.count
        return MisuraSpan(days: summaries, goal: goal * Double(active), due: goal * Double(elapsed))
    }

    func week(_ day: String) -> MisuraSpan? { span(MisuraDays.week(day)) }
    func month(_ day: String) -> MisuraSpan? { span(MisuraDays.monthDays(day)) }

    func perDayLeft(_ week: MisuraSpan) -> Double {
        let rest = week.days.filter { $0.day > today }.count
        guard rest > 0 else { return 0 }
        return max(0, (week.goal - week.deficit) / Double(rest)).rounded()
    }

    func monthLoss(_ day: String) -> (lost: Double, target: Double, due: Double)? {
        guard let plan, let span = month(day) else { return nil }
        let start = MisuraDays.monthStart(day)
        let opening = start <= plan.startDay ? plan.startKg : (average(MisuraDays.shift(start, by: -1)) ?? plan.startKg)
        let end = min(today, MisuraDays.monthDays(day).last ?? today)
        let current = average(end) ?? opening
        let lost = ((opening - current) * 10).rounded() / 10
        let target = (span.goal / MisuraMath.kcalPerKg * 10).rounded() / 10
        return (lost, target, span.due / MisuraMath.kcalPerKg)
    }

    func goalProgress() -> (lost: Double, total: Double, due: Double, eta: String)? {
        guard let plan else { return nil }
        let current = average(today) ?? plan.startKg
        let lost = ((plan.startKg - current) * 10).rounded() / 10
        let total = MisuraMath.lostByGoal(plan)
        let elapsed = max(0, min(MisuraMath.totalDays(plan), MisuraDays.between(plan.startDay, today)))
        let due = MisuraMath.dailyGoal(plan) * Double(elapsed) / MisuraMath.kcalPerKg
        let recent = (0..<14).map { MisuraDays.shift(today, by: -$0) }.compactMap(summary).filter(\.logged)
        var eta = plan.goalDay
        if recent.count >= 3 {
            let rate = recent.reduce(0) { $0 + $1.deficit } / Double(recent.count)
            if rate > 50 {
                let left = max(0, total - lost) * MisuraMath.kcalPerKg
                eta = MisuraDays.shift(today, by: Int((left / rate).rounded(.up)))
            }
        }
        return (lost, total, due, eta)
    }

    func trend(days: Int) -> [(day: String, kg: Double, avg: Double)] {
        (0..<days).reversed().compactMap { back in
            let day = MisuraDays.shift(today, by: -back)
            guard let kg = weight(on: day), let avg = average(day) else { return nil }
            return (day, kg, avg)
        }
    }

    func snapshots() -> [(snapshot: VaultSnapshot, entries: Int)] {
        DataVault.shared.snapshots(Self.name).map { snap in
            let count = (try? Self.decode(Data(contentsOf: snap.url)))?.entries.count ?? 0
            return (snap, count)
        }
    }

    func restore(_ snap: VaultSnapshot) {
        do {
            let saved = try Self.decode(Data(contentsOf: snap.url))
            if let current = try? Self.encode(book) { DataVault.shared.keepAside(current, name: Self.name, reason: "before-restore") }
            book = saved
            commit()
            note("misura restored from=\(snap.url.path) entries=\(saved.entries.count) weights=\(saved.weights.count)")
        } catch {
            note("misura restore failed from=\(snap.url.path) error=\(error.localizedDescription)")
        }
    }

    func merge(_ data: Data) {
        do {
            let incoming = try Self.decode(data)
            if let current = try? Self.encode(book) { DataVault.shared.keepAside(current, name: Self.name, reason: "before-merge") }
            var added = 0
            for entry in incoming.entries {
                if let index = book.entries.firstIndex(where: { $0.id == entry.id }) {
                    if (entry.updated ?? "") > (book.entries[index].updated ?? "") { book.entries[index] = entry }
                } else {
                    book.entries.append(entry)
                    added += 1
                }
            }
            for weight in incoming.weights {
                if let index = book.weights.firstIndex(where: { $0.id == weight.id }) {
                    if (weight.updated ?? "") > (book.weights[index].updated ?? "") { book.weights[index] = weight }
                } else {
                    book.weights.append(weight)
                    added += 1
                }
            }
            if book.plan == nil { book.plan = incoming.plan }
            commit()
            note("misura merged added=\(added) entries=\(book.entries.count) weights=\(book.weights.count)")
        } catch {
            note("misura merge failed bytes=\(data.count) error=\(error.localizedDescription)")
        }
    }

    func adopt(_ data: Data) {
        do {
            let incoming = try Self.decode(data)
            guard incoming != book else { return }
            let before = book.entries.count
            book = incoming
            write(book)
            MisuraReminder.refresh(self, reason: "adopt")
            onChange?()
            note("misura adopted cloud entries=\(before)->\(book.entries.count) weights=\(book.weights.count)")
        } catch {
            note("misura adopt failed bytes=\(data.count) error=\(error.localizedDescription)")
        }
    }

    private func commit() {
        write(book)
        onChange?()
    }

    private func write(_ book: MisuraBook) {
        do {
            let data = try Self.encode(book)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: file, options: .atomic)
            DataVault.shared.snapshot(data, name: Self.name, count: book.entries.count)
        } catch {
            note("misura save failed entries=\(book.entries.count) error=\(error.localizedDescription)")
        }
    }
}

enum MisuraReminder {
    static let prefix = "pocket.misura."

    static func refresh(_ store: MisuraStore, reason: String) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let center = UNUserNotificationCenter.current()
        let plan = store.plan
        let today = store.today
        let weighed = store.weight(on: today) != nil
        center.getPendingNotificationRequests { pending in
            let stale = pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
            center.removePendingNotificationRequests(withIdentifiers: stale)
            guard let plan, let at = plan.weighAt, let (hour, minute) = parse(at) else {
                note("misura reminders cleared trigger=\(reason) removed=\(stale.count)")
                return
            }
            var added = 0
            let now = Date()
            for offset in 0..<7 {
                let day = MisuraDays.shift(today, by: offset)
                if offset == 0 && weighed { continue }
                guard let date = MisuraDays.date(day),
                      let fire = MisuraDays.calendar.date(bySettingHour: hour, minute: minute, second: 0, of: date), fire > now else { continue }
                let content = UNMutableNotificationContent()
                content.title = "Terra"
                content.body = "Weigh-in"
                content.sound = .default
                content.userInfo = ["app": "calorie"]
                let parts = MisuraDays.calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
                center.add(UNNotificationRequest(identifier: prefix + day, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)))
                added += 1
            }
            note("misura reminders scheduled trigger=\(reason) at=\(at) count=\(added) removed=\(stale.count) weighedToday=\(weighed)")
        }
    }

    static func parse(_ text: String) -> (Int, Int)? {
        let parts = text.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2, (0..<24).contains(parts[0]), (0..<60).contains(parts[1]) else { return nil }
        return (parts[0], parts[1])
    }
}

enum MisuraText {
    static func kcal(_ value: Double) -> String {
        let rounded = Int(value.rounded())
        let format = NumberFormatter()
        format.numberStyle = .decimal
        format.maximumFractionDigits = 0
        let text = format.string(from: NSNumber(value: abs(rounded))) ?? "\(abs(rounded))"
        return rounded < 0 ? "−" + text : text
    }

    static func kg(_ value: Double, signed: Bool = false) -> String {
        let text = String(format: "%.1f", abs(value))
        if signed { return (value < 0 ? "+" : value > 0 ? "−" : "") + text }
        return value < 0 ? "−" + text : text
    }

    static func parseQuick(_ text: String) -> (kind: String, title: String, kcal: Double)? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard let match = trimmed.range(of: #"[-−]?\s*\d+(\.\d+)?\s*(kcal|cal)?$"#, options: .regularExpression) else { return nil }
        var number = String(trimmed[match]).replacingOccurrences(of: "kcal", with: "").replacingOccurrences(of: "cal", with: "")
        let workout = number.hasPrefix("-") || number.hasPrefix("−")
        number = number.replacingOccurrences(of: "-", with: "").replacingOccurrences(of: "−", with: "").trimmingCharacters(in: .whitespaces)
        guard let kcal = Double(number), kcal > 0 else { return nil }
        let title = String(trimmed[..<match.lowerBound]).trimmingCharacters(in: .whitespaces)
        return (workout ? "workout" : "meal", title, kcal)
    }
}
