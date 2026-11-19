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
    var run: Loose? = nil
}

indirect enum Loose: Codable, Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([Loose])
    case object([String: Loose])

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if value.decodeNil() { self = .null }
        else if let flag = try? value.decode(Bool.self) { self = .bool(flag) }
        else if let number = try? value.decode(Double.self) { self = .number(number) }
        else if let text = try? value.decode(String.self) { self = .string(text) }
        else if let list = try? value.decode([Loose].self) { self = .array(list) }
        else { self = .object(try value.decode([String: Loose].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var value = encoder.singleValueContainer()
        switch self {
        case .null: try value.encodeNil()
        case .bool(let flag): try value.encode(flag)
        case .number(let number):
            if number.rounded() == number, abs(number) < 1e15 { try value.encode(Int64(number)) } else { try value.encode(number) }
        case .string(let text): try value.encode(text)
        case .array(let list): try value.encode(list)
        case .object(let map): try value.encode(map)
        }
    }

    subscript(key: String) -> Loose? {
        if case .object(let map) = self { return map[key] }
        return nil
    }

    var string: String? {
        switch self {
        case .string(let text): return text
        case .number(let number): return number.rounded() == number ? String(Int64(number)) : String(number)
        default: return nil
        }
    }

    var number: Double? {
        switch self {
        case .number(let number): return number
        case .string(let text): return Double(text)
        default: return nil
        }
    }

    var flag: Bool {
        switch self {
        case .bool(let flag): return flag
        case .number(let number): return number != 0
        default: return false
        }
    }

    var list: [Loose] {
        if case .array(let list) = self { return list }
        return []
    }
}

enum ScheduleStepText {
    static func parts(_ title: String) -> (name: String, detail: String) {
        guard let bar = title.firstIndex(of: "|") else { return (title.trimmingCharacters(in: .whitespaces), "") }
        let name = title[..<bar].trimmingCharacters(in: .whitespaces)
        let detail = title[title.index(after: bar)...].trimmingCharacters(in: .whitespaces)
        return (name, detail)
    }

    static func make(_ title: String) -> Text {
        let split = parts(title)
        guard !split.detail.isEmpty else { return Text(split.name) }
        return Text(split.name).fontWeight(.semibold) + Text(" " + split.detail).fontWeight(.regular).foregroundStyle(OrarioBoard.muted)
    }

    static func plain(_ title: String) -> String {
        let split = parts(title)
        return split.detail.isEmpty ? split.name : "\(split.name) \(split.detail)"
    }
}

struct ScheduleRoutine: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var hue: Int
    var starts: String
    var plan: [String: [ScheduleStep]] = [:]
    var notes: String = ""
    var ends: String?
    var dated: [String: [ScheduleStep]]?

    static func key(_ weekday: Int, _ slot: ScheduleSlot) -> String { "\(weekday)-\(slot.rawValue)" }
    static func key(_ day: String, _ slot: ScheduleSlot) -> String { "\(day)-\(slot.rawValue)" }

    func steps(_ weekday: Int, _ slot: ScheduleSlot) -> [ScheduleStep] { plan[Self.key(weekday, slot)] ?? [] }

    func runs(on day: String) -> Bool { starts <= day && ends.map { day <= $0 } ?? true }

    func steps(on day: String, _ slot: ScheduleSlot) -> [ScheduleStep] {
        dated?[Self.key(day, slot)] ?? steps(ScheduleDays.weekday(day), slot)
    }
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
            addFitnessIfDue()
            if let id = filter, !book.routines.contains(where: { $0.id == id }) { filter = nil }
            let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in self?.tick() }
            RunLoop.main.add(timer, forMode: .common)
            clock = timer
            addMindfulnessIfDue()
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
        let done = Set(book.checks.lazy.filter { $0.day == day && $0.slot == slot }.map(\.id))
        return (routines ?? shown).filter { $0.runs(on: day) }.flatMap { routine in
            routine.steps(on: day, slot).map { step in
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

    private func addFitnessIfDue() {
        let flag = "schedule.seeded.fitness-2026-11"
        guard !UserDefaults.standard.bool(forKey: flag) else { return }
        UserDefaults.standard.set(true, forKey: flag)
        var routine = ScheduleSeed.fitness()
        guard today <= routine.ends ?? today, !book.routines.contains(where: { $0.name == routine.name }) else { return }
        routine.hue = (book.routines.map(\.hue).max() ?? -1) + 1
        book.routines.append(routine)
        note("schedule routine seeded name=\(routine.name) starts=\(routine.starts) ends=\(routine.ends ?? "never") days=\(routine.dated?.count ?? 0)")
        save()
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

    private func addMindfulnessIfDue() {
        let flag = "schedule.seeded.mindfulness-2026-11"
        guard !UserDefaults.standard.bool(forKey: flag) else { return }
        UserDefaults.standard.set(true, forKey: flag)
        var routine = ScheduleSeed.mindfulness()
        guard !book.routines.contains(where: { $0.name == routine.name }) else { return }
        routine.hue = (book.routines.map(\.hue).max() ?? -1) + 1
        book.routines.append(routine)
        note("schedule routine seeded name=\(routine.name) starts=\(routine.starts) hue=\(routine.hue)")
        save()
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
    static func mindfulness() -> ScheduleRoutine {
        enum Goal { case job, abs, hair, all }
        let wakeTip = "Before you touch your phone: sit up in bed, drink a glass of water, and take 3 slow breaths, in through the nose for 4, out through the mouth for 6. The phone stays away until this session is done."
        let breathTip = "Sit upright, eyes closed. Breathe naturally and count each out-breath from 1 to 10, then start again. When your mind wanders (it will, often), notice it without judging and go back to 1. Coming back is the practice, not a failure."
        let kindnessTip = "Sit upright, eyes closed, hand on your chest. Repeat slowly to yourself: \"May I be confident. May I be healthy and strong. May I be at ease.\" After 4 minutes, picture your family and wish them the same, then everyone you'll meet today. Self-kindness is the root of real confidence."
        let awareTip = "Sit upright, eyes closed. Don't hold onto anything: notice sounds, body sensations and thoughts as they come and go, like clouds passing. Label them lightly (\"hearing\", \"thinking\", \"planning\") and let them go. This trains you to watch doubts without believing them."
        let affirmTip = """
        Stand tall, shoulders back, chin up, ideally at a mirror. Say each line out loud, slowly, 3 times, and feel it as true now:
        "I am confident, calm and worthy of good things."
        "I am selected for a secure, respected government job."
        "I am disciplined, and my body is lean, strong and defined."
        "My hair grows back thicker and healthier every week."
        "Good things flow into my life easily."
        """
        let gratitudeTip = "Write 3 specific good things from today and why each happened, e.g. \"Finished 2 focus sessions because I put my phone in another room.\" Specific beats general: it trains your mind to notice what's working."
        let winsTip = "Write one thing you did well or bravely today, toward any goal, however small: a study block, a workout, the hair routine on time, speaking up. Confidence is built from this evidence, so reread the list when you doubt yourself."
        let reviewTip = "Reread this week's wins and scripts. Note what moved each goal forward and what got in the way. Rewrite your affirmations if a line no longer feels right, and pick one focus per goal for next week."
        let scanTip = "Lie down, lights off. Move your attention slowly from your toes to the top of your head, relaxing each part as you breathe out. If you're still awake at the end, rest on your breath and let sleep come."
        func visualTip(_ goal: Goal) -> String {
            switch goal {
            case .job: return "Eyes closed. See it as already real, in detail: the result page with your name on it, the call home to tell your family, your first morning walking into the office. Feel the relief and pride in your body. End by seeing yourself sitting down to study today, calm and focused."
            case .abs: return "Eyes closed. See it as already real: you in the mirror with a lean, defined stomach, how your T-shirt fits, how light and strong you feel moving. Feel the pride. End by seeing yourself doing today's workout and choosing good food."
            case .hair: return "Eyes closed. See it as already real: running your hand through thick hair, a photo of yourself you love, the barber saying it's grown back well. Feel how good it is. End by seeing yourself doing the Hair care routine on time today."
            case .all: return "Eyes closed. Spend about 4 minutes on each goal as already real: the government job (your name on the result, your first day), the six pack (you in the mirror, lean and strong), your hair (thick under your hand). Feel each fully, then see yourself taking this week's steps calmly."
            }
        }
        func actionTip(_ goal: Goal) -> String {
            switch goal {
            case .job: return "Attraction works with action. Choose one concrete step for the job today and decide when you'll do it, e.g. \"2 focus sessions in Ignis before lunch\" or \"one full mock test tonight\"."
            case .abs: return "Attraction works with action. Choose one concrete step for your six pack today, e.g. \"finish this morning's Fitness session\", \"protein at every meal\" or \"no sugar today\"."
            case .hair: return "Attraction works with action. Choose one concrete step for your hair today, e.g. \"every Hair care step on time\", \"8 hours of sleep\" or \"cap on outdoors\"."
            case .all: return "Choose one concrete step for each goal this week and put it where you'll see it."
            }
        }
        func scriptTip(_ goal: Goal) -> String {
            switch goal {
            case .job: return "Write 5 to 10 lines in the present tense, as if it already happened, and include feelings. e.g. \"I'm so grateful. I saw my name on the final list today. I called my family and we celebrated together. I start my government job next month and I feel secure and proud.\""
            case .abs: return "Write 5 to 10 lines in the present tense, as if it already happened, and include feelings. e.g. \"I'm so grateful for my body. I can see my abs clearly in the mirror. My clothes fit perfectly and I feel light, strong and confident everywhere I go.\""
            case .hair: return "Write 5 to 10 lines in the present tense, as if it already happened, and include feelings. e.g. \"I'm so grateful. My hair is thick and full again. My crown is covered, I love how I look in photos, and I don't think about my hair anymore.\""
            case .all: return ""
            }
        }
        func label(_ goal: Goal) -> String {
            switch goal {
            case .job: return "government job"
            case .abs: return "six pack"
            case .hair: return "hair"
            case .all: return "all three goals"
            }
        }
        let wake = ScheduleStep(title: "Wake up | water, 3 slow breaths, no phone", tip: wakeTip)
        let affirm = ScheduleStep(title: "Affirmations | out loud, standing tall, 3 min", tip: affirmTip)
        let gratitude = ScheduleStep(title: "Gratitude | 3 good things, 4 min", tip: gratitudeTip)
        let wins = ScheduleStep(title: "Wins log | 1 win toward a goal, 3 min", tip: winsTip)
        let scan = ScheduleStep(title: "Body scan | lying down, 8 min, then sleep", tip: scanTip)
        let days: [Int: (meditation: ScheduleStep?, goal: Goal)] = [
            2: (ScheduleStep(title: "Breath meditation | 8 min", tip: breathTip), .job),
            3: (ScheduleStep(title: "Loving-kindness | 8 min", tip: kindnessTip), .abs),
            4: (ScheduleStep(title: "Open awareness | 8 min", tip: awareTip), .hair),
            5: (ScheduleStep(title: "Breath meditation | 8 min", tip: breathTip), .job),
            6: (ScheduleStep(title: "Loving-kindness | 8 min", tip: kindnessTip), .abs),
            7: (ScheduleStep(title: "Open awareness | 8 min", tip: awareTip), .hair),
            1: (nil, .all)
        ]
        var routine = ScheduleRoutine(name: "Mindfulness", hue: 2, starts: "2026-11-20")
        for (weekday, day) in days {
            var morning = [wake]
            if let meditation = day.meditation { morning.append(meditation) }
            morning.append(ScheduleStep(title: "Visualize | \(label(day.goal)), \(day.goal == .all ? 13 : 5) min", tip: visualTip(day.goal)))
            morning.append(affirm)
            morning.append(ScheduleStep(title: "One action | for \(day.goal == .all ? "each goal this week" : "your " + label(day.goal) + " today"), 2 min", tip: actionTip(day.goal)))
            let middle = day.goal == .all
                ? ScheduleStep(title: "Weekly review | wins, affirmations, next week, 5 min", tip: reviewTip)
                : ScheduleStep(title: "Scripting | \(label(day.goal)), as if it's done, 5 min", tip: scriptTip(day.goal))
            routine.plan[ScheduleRoutine.key(weekday, .morning)] = morning
            routine.plan[ScheduleRoutine.key(weekday, .night)] = [gratitude, wins, middle, scan]
        }
        routine.notes = """
        About 20 minutes first thing after waking and 20 minutes last thing before sleep. The phone stays away until the morning session is done.
        Goal focus rotates: Monday and Thursday the government job, Tuesday and Friday the six pack, Wednesday and Saturday your hair, Sunday all three with a weekly review.
        Keep one notebook for gratitude, wins and scripting, so you can reread your progress.
        Attraction works best paired with action: study in Ignis, the Fitness mornings, and the Hair care routine are how the goals arrive.
        Missing a step or a day is fine; just pick up at the next session. Consistency matters more than perfection.
        """
        return routine
    }

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

    static func fitness() -> ScheduleRoutine {
        let warmTip = "March in place for 2 minutes, then 10 leg swings each way on each leg, 10 ankle circles each way, 10 arm circles and 10 slow squats."
        let cardioTip = "Rotate jumping jacks, high knees, butt kicks and skater steps, one per interval. Work at a pace where talking is hard but possible; rest fully in the gaps. Land softly on the balls of your feet. On a mat or rug if you have one."
        let calfTip = "Calf raises on a step edge: up for 1 second, down slowly for 3. Then toe raises with your back against a wall, lifting your toes toward your shins. This gets your shins and calves ready for running and rope."
        let runTip = "Jog slow enough to talk in short sentences. Take short, quick steps and land under your hips, not on your heels. Walk briskly in the gaps. Sharp pain in the shins or knees means walk the rest today; tired legs are fine."
        let ropeTip = "Tiny hops, about an inch off the ground, on the balls of your feet with soft knees. Turn the rope with your wrists and keep your elbows by your sides. Rest 30–60 seconds between sets. A trip doesn't reset the set; keep counting."
        let stretchTip = "Hold each for 30 seconds without bouncing: calves against a wall, hamstrings, quads, hip flexors in a low lunge, chest in a doorway."
        let mobilityTip = "Slow and easy: 10 cat-cows, 10 hip circles each way, 10 world's greatest stretches a side, 10 shoulder rolls, 1 minute in a deep squat holding onto something, 1 minute of child's pose. Then the full stretch twice."
        let circuitTips = [
            "A": "Per round: 10 squats, 5 incline push-ups with your hands on a bed or table, 10 glute bridges, a 20-second plank, 10 bird dogs a side. Rest 60 seconds between rounds.",
            "B": "Per round: 12 squats, 8 knee push-ups, 8 reverse lunges a leg, a 30-second plank, 10 mountain climbers a leg. Rest 60 seconds between rounds.",
            "C": "Per round: 15 squats, 10 push-ups (on your knees if needed), 10 lunges a leg, a 40-second plank, 8 step-back burpees. Rest 60–90 seconds between rounds."
        ]
        func warm() -> ScheduleStep { ScheduleStep(title: "Warm-up | 5 min", tip: warmTip) }
        func stretch() -> ScheduleStep { ScheduleStep(title: "Stretch | 5 min", tip: stretchTip) }
        func cardio(_ detail: String) -> ScheduleStep { ScheduleStep(title: "Cardio | \(detail)", tip: cardioTip) }
        func calves(_ detail: String) -> ScheduleStep { ScheduleStep(title: "Calves and shins | \(detail)", tip: calfTip) }
        func run(_ detail: String) -> ScheduleStep { ScheduleStep(title: "Run | \(detail)", tip: runTip) }
        func rope(_ detail: String) -> ScheduleStep { ScheduleStep(title: "Jump rope | \(detail)", tip: ropeTip) }
        func circuit(_ name: String, _ rounds: Int) -> ScheduleStep {
            ScheduleStep(title: "Circuit \(name) | \(rounds) rounds", tip: circuitTips[name] ?? "")
        }
        func recovery() -> [ScheduleStep] {
            [ScheduleStep(title: "Mobility | 20 min easy", tip: mobilityTip + " No hard work today; this is when your body catches up.")]
        }
        let days: [[ScheduleStep]] = [
            [warm(), cardio("6 × (30s on, 30s rest)"), circuit("A", 2), calves("2 × 12 each"), stretch()],
            [warm(), cardio("8 × (30s on, 30s rest)"), circuit("A", 3), stretch()],
            [warm(), cardio("8 × (40s on, 20s rest)"), circuit("A", 3), calves("2 × 15 each"), stretch()],
            [warm(), cardio("10 × (40s on, 20s rest)"), circuit("B", 2), stretch()],
            recovery(),
            [warm(), cardio("12 × (40s on, 20s rest)"), circuit("B", 3), calves("3 × 15 each"), stretch()],
            [warm(), cardio("12 × (45s on, 15s rest)"), circuit("B", 3), stretch()],
            [warm(), cardio("15 × (45s on, 15s rest)"), circuit("C", 2), calves("3 × 20 each"), stretch()],
            [warm(), cardio("18 × (45s on, 15s rest)"), circuit("C", 3), stretch()],
            recovery(),
            [warm(), run("6 × (1 min jog, 1 min walk)"), rope("300, 6 × 50"), calves("2 × 20 each"), stretch()],
            [warm(), circuit("C", 3), rope("300, 6 × 50"), stretch()],
            [warm(), run("5 × (2 min jog, 1 min walk)"), rope("400, 8 × 50"), stretch()],
            [warm(), circuit("C", 3), rope("500, 10 × 50"), calves("3 × 20 each"), stretch()],
            recovery(),
            [warm(), run("3 × (4 min jog, 1 min walk)"), rope("600, 6 × 100"), stretch()],
            [warm(), circuit("C", 3), rope("700, 7 × 100"), stretch()],
            [warm(), run("2 × (6 min jog, 1 min walk)"), rope("800, 8 × 100"), stretch()],
            [warm(), circuit("C", 2), rope("900, 9 × 100"), calves("3 × 20 each"), stretch()],
            [warm(), ScheduleStep(title: "Walk | 15 min easy", tip: "An easy day before the test. Brisk enough to warm up, nothing more."), rope("500 easy, 5 × 100"), stretch()],
            [warm(), ScheduleStep(title: "Run | 1 km", tip: "The test. Start slower than feels right; about 7–8 minutes at an easy jog. If you need it, take one 30-second walk break and carry on; finishing matters, speed doesn't."),
             ScheduleStep(title: "Jump rope | 1000, 10 × 100", tip: ropeTip + " This is the daily target from here on."), stretch()]
        ]
        let starts = "2026-11-20"
        var routine = ScheduleRoutine(name: "Fitness", hue: 1, starts: starts)
        var dated: [String: [ScheduleStep]] = [:]
        for (offset, steps) in days.enumerated() {
            dated[ScheduleRoutine.key(ScheduleDays.shift(starts, by: offset), .morning)] = steps
        }
        routine.dated = dated
        routine.ends = ScheduleDays.shift(starts, by: days.count - 1)
        routine.notes = """
        21 mornings to build endurance before the gym starts on 11 Dec. Days 1 to 10 (20 to 29 Nov) are home exercises only, building stamina and strong calves and shins.
        Running and jump rope start on 30 Nov, on alternate days with strength circuits. By day 21: run 1 km and jump rope 1000 times. Recovery days are 24 Nov, 29 Nov and 4 Dec.
        If a session feels too hard, repeat it the next day instead of moving on. Sharp pain (not tiredness) means stop and walk.
        Wear cushioned running shoes, and jump rope on a mat, wood or packed earth rather than bare concrete.
        For fat loss, food does most of the work: a small calorie deficit, protein at every meal, plenty of water and 7–8 hours of sleep.
        """
        return routine
    }
}
