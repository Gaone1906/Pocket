import Foundation
import SwiftUI

enum ScheduleSlot: String, Codable, CaseIterable, Identifiable {
    case morning
    case night

    var id: String { rawValue }
    var label: String { self == .morning ? "Morning" : "Night" }
    var symbol: String { self == .morning ? "sun.max" : "moon" }
}

struct ScheduleStep: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var tip: String = ""
}

struct ScheduleRoutine: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var hue: Int
    var starts: String
    var plan: [String: [ScheduleStep]] = [:]
    var notes: String = ""

    static func key(_ weekday: Int, _ slot: ScheduleSlot) -> String { "\(weekday)-\(slot.rawValue)" }

    func steps(_ weekday: Int, _ slot: ScheduleSlot) -> [ScheduleStep] { plan[Self.key(weekday, slot)] ?? [] }
}

struct ScheduleCheck: Codable, Identifiable, Equatable {
    let id: String
    let routine: UUID
    let day: String
    let slot: ScheduleSlot
    let step: UUID
    let done: Date

    static func id(routine: UUID, day: String, slot: ScheduleSlot, step: UUID) -> String {
        "\(routine.uuidString)|\(day)|\(slot.rawValue)|\(step.uuidString)"
    }
}

struct ScheduleItem: Identifiable, Equatable {
    let routine: ScheduleRoutine
    let step: ScheduleStep
    let slot: ScheduleSlot
    let day: String
    let done: Bool

    var id: String { ScheduleCheck.id(routine: routine.id, day: day, slot: slot, step: step.id) }
}

enum ScheduleDayStatus: Equatable {
    case before
    case rest
    case upcoming
    case open(done: Int, total: Int)
    case done
    case partial(done: Int, total: Int)
    case missed
}

struct ScheduleBook: Codable, Equatable {
    var routines: [ScheduleRoutine]
    var checks: [ScheduleCheck]
    var nightFrom: Int = 16
    var dayFrom: Int = 4
}

enum ScheduleDays {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        calendar.firstWeekday = 2
        return calendar
    }()

    static let format: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static let weekOrder = [2, 3, 4, 5, 6, 7, 1]

    static func key(_ date: Date) -> String { format.string(from: date) }
    static func date(_ key: String) -> Date? { format.date(from: key) }
    static func weekday(_ key: String) -> Int { date(key).map { calendar.component(.weekday, from: $0) } ?? 1 }
    static func shift(_ key: String, by days: Int) -> String {
        guard let date = date(key), let moved = calendar.date(byAdding: .day, value: days, to: date) else { return key }
        return Self.key(moved)
    }

    static func name(_ weekday: Int) -> String { calendar.weekdaySymbols[(weekday - 1 + 7) % 7] }
    static func short(_ weekday: Int) -> String { calendar.shortWeekdaySymbols[(weekday - 1 + 7) % 7] }
}

final class ScheduleStore: ObservableObject {
    static let shared = ScheduleStore()
    static let startDay = "2026-11-19"

    @Published private(set) var book: ScheduleBook
    @Published var filter: UUID? {
        didSet {
            UserDefaults.standard.set(filter?.uuidString, forKey: "schedule.filter")
            note("schedule filter changed routine=\(filter.flatMap { id in book.routines.first { $0.id == id }?.name } ?? "all")")
        }
    }
    @Published private(set) var now = Date()
    private let file = PocketData.schedule
    private var clock: Timer?

    private init() {
        book = ScheduleBook(routines: [], checks: [])
        filter = UserDefaults.standard.string(forKey: "schedule.filter").flatMap(UUID.init(uuidString:))
        let vault = DataVault.shared
        vault.register("schedule") { [weak self] data in self?.merge(data) }
        CloudSync.shared.register("schedule") { [weak self] data in self?.adopt(data) }
        defer {
            if let id = filter, !book.routines.contains(where: { $0.id == id }) { filter = nil }
            let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in self?.tick() }
            RunLoop.main.add(timer, forMode: .common)
            clock = timer
        }
        if FileManager.default.fileExists(atPath: file.path) {
            do {
                book = try Self.decode(Data(contentsOf: file))
                note("schedule loaded routines=\(book.routines.count) checks=\(book.checks.count) path=\(file.path)")
                return
            } catch {
                note("schedule load failed path=\(file.path) error=\(error.localizedDescription)")
                vault.quarantine(file, name: "schedule")
            }
        }
        if let (saved, snap) = vault.recover("schedule", decode: Self.decode) {
            book = saved
            note("schedule recovered from=\(snap.url.path) routines=\(book.routines.count) checks=\(book.checks.count)")
            save()
            return
        }
        book = ScheduleBook(routines: [ScheduleSeed.hairCare()], checks: [])
        note("schedule seeded routines=\(book.routines.count) path=\(file.path)")
        save()
    }

    func adopt(_ data: Data) {
        do {
            let incoming = try Self.decode(data)
            guard incoming != book else { return }
            let before = book.checks.count
            book = incoming
            if let id = filter, !book.routines.contains(where: { $0.id == id }) { filter = nil }
            save()
            note("schedule adopted cloud routines=\(book.routines.count) checksBefore=\(before) checksAfter=\(book.checks.count)")
        } catch {
            note("schedule adopt failed bytes=\(data.count) error=\(error.localizedDescription)")
        }
    }

    static func decode(_ data: Data) throws -> ScheduleBook {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ScheduleBook.self, from: data)
    }

    static func encode(_ book: ScheduleBook) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(book)
    }

    func tick() {
        let before = (today, slotNow)
        now = Date()
        if before != (today, slotNow) { note("schedule moved day=\(today) slot=\(slotNow.rawValue)") }
    }

    var routines: [ScheduleRoutine] { book.routines }
    var shown: [ScheduleRoutine] { filter.map { id in book.routines.filter { $0.id == id } } ?? book.routines }
    var filterName: String { filter.flatMap { id in book.routines.first { $0.id == id }?.name } ?? "All routines" }

    var today: String {
        let shifted = ScheduleDays.calendar.date(byAdding: .hour, value: -book.dayFrom, to: now) ?? now
        return ScheduleDays.key(shifted)
    }

    var slotNow: ScheduleSlot {
        let hour = ScheduleDays.calendar.component(.hour, from: now)
        return hour >= book.nightFrom || hour < book.dayFrom ? .night : .morning
    }

    var firstDay: String { book.routines.map(\.starts).min() ?? Self.startDay }

    func routine(_ id: UUID) -> ScheduleRoutine? { book.routines.first { $0.id == id } }

    func items(on day: String, slot: ScheduleSlot, in routines: [ScheduleRoutine]? = nil) -> [ScheduleItem] {
        let weekday = ScheduleDays.weekday(day)
        let done = Set(book.checks.lazy.filter { $0.day == day && $0.slot == slot }.map(\.id))
        return (routines ?? shown).filter { $0.starts <= day }.flatMap { routine in
            routine.steps(weekday, slot).map { step in
                let item = ScheduleItem(routine: routine, step: step, slot: slot, day: day, done: false)
                return ScheduleItem(routine: routine, step: step, slot: slot, day: day, done: done.contains(item.id))
            }
        }
    }

    func status(on day: String, slot: ScheduleSlot? = nil, in routines: [ScheduleRoutine]? = nil) -> ScheduleDayStatus {
        let pool = routines ?? shown
        guard pool.contains(where: { $0.starts <= day }) else { return .before }
        let slots = slot.map { [$0] } ?? ScheduleSlot.allCases
        let items = slots.flatMap { self.items(on: day, slot: $0, in: pool) }
        let done = items.filter(\.done).count
        if items.isEmpty { return .rest }
        if done == items.count { return .done }
        if day > today { return .upcoming }
        if day == today {
            let lapsed = slot == .morning && slotNow == .night
            if !lapsed { return .open(done: done, total: items.count) }
        }
        return done == 0 ? .missed : .partial(done: done, total: items.count)
    }

    func toggle(_ item: ScheduleItem) { set(item, done: !item.done) }

    func set(_ item: ScheduleItem, done: Bool) {
        guard done != item.done else { return }
        if done {
            book.checks.append(ScheduleCheck(id: item.id, routine: item.routine.id, day: item.day, slot: item.slot, step: item.step.id, done: Date()))
        } else {
            book.checks.removeAll { $0.id == item.id }
        }
        note("schedule step \(done ? "checked" : "unchecked") routine=\(item.routine.name) day=\(item.day) slot=\(item.slot.rawValue) step=\(item.step.title)")
        save()
    }

    func setAll(on day: String, slot: ScheduleSlot, done: Bool) {
        let targets = items(on: day, slot: slot).filter { $0.done != done }
        guard !targets.isEmpty else { return }
        let ids = Set(targets.map(\.id))
        if done {
            book.checks += targets.map { ScheduleCheck(id: $0.id, routine: $0.routine.id, day: day, slot: slot, step: $0.step.id, done: Date()) }
        } else {
            book.checks.removeAll { ids.contains($0.id) }
        }
        note("schedule slot \(done ? "completed" : "cleared") day=\(day) slot=\(slot.rawValue) steps=\(targets.count) filter=\(filterName)")
        save()
    }

    func tally(from start: String? = nil, through end: String? = nil) -> (done: Int, partial: Int, missed: Int) {
        var day = max(start ?? firstDay, firstDay)
        let last = min(end ?? today, today)
        var result = (done: 0, partial: 0, missed: 0)
        while day <= last {
            switch status(on: day) {
            case .done: result.done += 1
            case .partial: result.partial += 1
            case .missed: result.missed += 1
            default: break
            }
            day = ScheduleDays.shift(day, by: 1)
        }
        return result
    }

    @discardableResult
    func addRoutine(_ name: String) -> UUID {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let routine = ScheduleRoutine(name: trimmed.isEmpty ? "New routine" : trimmed, hue: (book.routines.map(\.hue).max() ?? -1) + 1, starts: today)
        book.routines.append(routine)
        note("schedule routine added id=\(routine.id) name=\(routine.name) starts=\(routine.starts)")
        save()
        return routine.id
    }

    func renameRoutine(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        updateRoutine(id, reason: "renamed to=\(trimmed)") { $0.name = trimmed }
    }

    func setNotes(_ id: UUID, _ notes: String) {
        updateRoutine(id, reason: "notes chars=\(notes.count)") { $0.notes = notes }
    }

    func deleteRoutine(_ id: UUID) {
        guard let routine = routine(id) else { return }
        if let data = try? Self.encode(book) { DataVault.shared.keepAside(data, name: "schedule", reason: "before-delete") }
        book.routines.removeAll { $0.id == id }
        let before = book.checks.count
        book.checks.removeAll { $0.routine == id }
        if filter == id { filter = nil }
        note("schedule routine deleted id=\(id) name=\(routine.name) checksRemoved=\(before - book.checks.count)")
        save()
    }

    @discardableResult
    func addStep(_ routine: UUID, weekday: Int, slot: ScheduleSlot, title: String, tip: String = "") -> UUID? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let step = ScheduleStep(title: trimmed, tip: tip.trimmingCharacters(in: .whitespacesAndNewlines))
        updateRoutine(routine, reason: "step added weekday=\(weekday) slot=\(slot.rawValue) title=\(trimmed)") {
            $0.plan[ScheduleRoutine.key(weekday, slot), default: []].append(step)
        }
        return step.id
    }

    func updateStep(_ routine: UUID, weekday: Int, slot: ScheduleSlot, step: UUID, title: String, tip: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        updateRoutine(routine, reason: "step edited weekday=\(weekday) slot=\(slot.rawValue) title=\(trimmed)") {
            let key = ScheduleRoutine.key(weekday, slot)
            guard let index = $0.plan[key]?.firstIndex(where: { $0.id == step }) else { return }
            $0.plan[key]?[index].title = trimmed
            $0.plan[key]?[index].tip = tip.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    func removeStep(_ routine: UUID, weekday: Int, slot: ScheduleSlot, step: UUID) {
        updateRoutine(routine, reason: "step removed weekday=\(weekday) slot=\(slot.rawValue) step=\(step)") {
            $0.plan[ScheduleRoutine.key(weekday, slot)]?.removeAll { $0.id == step }
        }
    }

    func moveStep(_ routine: UUID, weekday: Int, slot: ScheduleSlot, step: UUID, by offset: Int) {
        updateRoutine(routine, reason: "step moved weekday=\(weekday) slot=\(slot.rawValue) by=\(offset)") {
            let key = ScheduleRoutine.key(weekday, slot)
            guard var list = $0.plan[key], let index = list.firstIndex(where: { $0.id == step }) else { return }
            let target = min(max(index + offset, 0), list.count - 1)
            guard target != index else { return }
            list.insert(list.remove(at: index), at: target)
            $0.plan[key] = list
        }
    }

    func setNightFrom(_ hour: Int) {
        let clamped = min(max(hour, book.dayFrom + 1), 23)
        guard clamped != book.nightFrom else { return }
        book.nightFrom = clamped
        note("schedule night starts hour=\(clamped)")
        save()
    }

    private func updateRoutine(_ id: UUID, reason: String, _ change: (inout ScheduleRoutine) -> Void) {
        guard let index = book.routines.firstIndex(where: { $0.id == id }) else {
            return note("schedule routine missing id=\(id) action=\(reason)")
        }
        var routine = book.routines[index]
        change(&routine)
        guard routine != book.routines[index] else { return }
        book.routines[index] = routine
        note("schedule routine changed name=\(routine.name) \(reason)")
        save()
    }

    func merge(_ data: Data) {
        do {
            let incoming = try Self.decode(data)
            if let current = try? Self.encode(book) { DataVault.shared.keepAside(current, name: "schedule", reason: "before-merge") }
            let knownRoutines = Set(book.routines.map(\.id))
            let knownChecks = Set(book.checks.map(\.id))
            let routines = incoming.routines.filter { !knownRoutines.contains($0.id) }
            let checks = incoming.checks.filter { !knownChecks.contains($0.id) }
            book.routines += routines
            book.checks += checks
            save()
            note("schedule merged routinesAdded=\(routines.count) checksAdded=\(checks.count) checks=\(book.checks.count)")
        } catch {
            note("schedule merge failed bytes=\(data.count) error=\(error.localizedDescription)")
        }
    }

    var snapshots: [(snapshot: VaultSnapshot, routines: Int, checks: Int)] {
        DataVault.shared.snapshots("schedule").compactMap { snap in
            guard let saved = try? Self.decode(Data(contentsOf: snap.url)) else { return nil }
            return (snap, saved.routines.count, saved.checks.count)
        }
    }

    func restore(_ snap: VaultSnapshot) {
        do {
            let saved = try Self.decode(Data(contentsOf: snap.url))
            if let current = try? Self.encode(book) { DataVault.shared.keepAside(current, name: "schedule", reason: "before-restore") }
            let before = book.checks.count
            book = saved
            save()
            note("schedule restored from=\(snap.url.path) checksBefore=\(before) checksAfter=\(book.checks.count)")
        } catch {
            note("schedule restore failed from=\(snap.url.path) error=\(error.localizedDescription)")
        }
    }

    private func save() {
        do {
            let data = try Self.encode(book)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: file, options: .atomic)
            DataVault.shared.snapshot(data, name: "schedule", count: book.checks.count)
        } catch {
            note("schedule save failed routines=\(book.routines.count) checks=\(book.checks.count) error=\(error.localizedDescription)")
        }
    }
}

enum ScheduleSeed {
    static func hairCare() -> ScheduleRoutine {
        let washTip = "Wet your hair well, work it into the scalp (not just the hair) until it lathers, leave 3–5 minutes, rinse completely. Keep it out of your eyes."
        let dryTip = "Towel off, then a cool dryer. Minokem must never go on a wet or damp scalp."
        let minoTip = "Part your hair in rows over the thinning areas, put the 1 ml on the scalp and spread it with your fingertips. Wash your hands. Don't wet your hair for 4 hours."
        let waitTip = "Give the Minokem 20–30 minutes to dry before anything else goes on."
        let serumTip = "Use the amount on the box, put it on the scalp and massage it in gently. Leave it on overnight."
        let haloTip = "A few drops in a thin layer on the dry scalp, focusing on itchy, red or flaky patches. Rub it in, wash your hands. Never more than 2 nights a week; keep it off your face."
        func wash() -> [ScheduleStep] {
            [ScheduleStep(title: "Shower: KZ Plus wash, leave 3–5 min, rinse", tip: washTip),
             ScheduleStep(title: "Dry scalp fully", tip: dryTip),
             ScheduleStep(title: "Minokem-N 1 ml on dry scalp", tip: minoTip)]
        }
        func plainMorning() -> [ScheduleStep] {
            [ScheduleStep(title: "Minokem-N 1 ml on dry scalp", tip: minoTip + " Keep your hair dry in the shower today, or shower first.")]
        }
        func night(halovate: Bool) -> [ScheduleStep] {
            var steps = [ScheduleStep(title: "Minokem-N 1 ml", tip: minoTip),
                         ScheduleStep(title: "Let it dry, about 20–30 min", tip: waitTip)]
            if halovate { steps.append(ScheduleStep(title: "Halovate, thin layer", tip: haloTip)) }
            steps.append(ScheduleStep(title: "Hair Shine serum", tip: serumTip))
            return steps
        }
        var routine = ScheduleRoutine(name: "Hair care", hue: 0, starts: ScheduleStore.startDay)
        for weekday in 1...7 {
            let washDay = [5, 7, 2].contains(weekday)
            let halovate = [6, 3].contains(weekday)
            routine.plan[ScheduleRoutine.key(weekday, .morning)] = washDay ? wash() : plainMorning()
            routine.plan[ScheduleRoutine.key(weekday, .night)] = night(halovate: halovate)
        }
        routine.notes = """
        Wash days are Thursday, Saturday and Monday: shower first, dry your scalp completely, then the morning Minokem.
        Don't wet your hair within 4 hours of Minokem. Take a night shower before the night routine, not after.
        Extra shedding in the first 4–8 weeks is normal. Wear a cap outdoors; tretinoin makes the scalp sun-sensitive.
        Use a wooden comb and a scalp massager. Get the lab tests done before the review visit.
        Ask the clinic whether Halovate is layered with the night Minokem and serum, or replaces one of them.
        """
        return routine
    }
}
