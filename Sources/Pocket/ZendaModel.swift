import AppKit
import Combine
import Foundation

struct ZendaProject: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var goal: String
    var start: String
    var end: String
    var routine: String
    var days: [Int]
    var updated: String

    init(id: String = UUID().uuidString, name: String, goal: String, start: String, end: String, routine: String, days: [Int], updated: String = "") {
        self.id = id
        self.name = name
        self.goal = goal
        self.start = start
        self.end = end
        self.routine = routine
        self.days = days
        self.updated = updated
    }

    private enum Keys: String, CodingKey { case id, name, goal, start, end, routine, days, updated }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        goal = try c.decodeIfPresent(String.self, forKey: .goal) ?? ""
        start = try c.decodeIfPresent(String.self, forKey: .start) ?? ""
        end = try c.decodeIfPresent(String.self, forKey: .end) ?? ""
        routine = try c.decodeIfPresent(String.self, forKey: .routine) ?? ""
        days = (try? c.decodeIfPresent([Int].self, forKey: .days)) ?? []
        updated = try c.decodeIfPresent(String.self, forKey: .updated) ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(goal, forKey: .goal)
        try c.encode(start, forKey: .start)
        try c.encode(end, forKey: .end)
        try c.encode(routine, forKey: .routine)
        try c.encode(days, forKey: .days)
        try c.encode(updated, forKey: .updated)
    }

    static func iso(_ day: String) -> Int { (ScheduleDays.weekday(day) + 5) % 7 + 1 }

    func covers(_ day: String) -> Bool { !start.isEmpty && start <= day && (end.isEmpty || day <= end) }

    func applies(_ day: String) -> Bool { covers(day) && days.contains(Self.iso(day)) }

    func dayNumber(_ day: String) -> Int { ZendaDates.span(start, day) + 1 }

    var total: Int { max(1, ZendaDates.span(start, end) + 1) }

    var routineRecord: ScheduleRoutine? { UUID(uuidString: routine).flatMap { ScheduleStore.shared.routine($0) } }
}

struct ZendaFile: Codable, Equatable {
    var projects: [ZendaProject]
}

enum ZendaDates {
    static func span(_ from: String, _ to: String) -> Int {
        guard let a = ScheduleDays.date(from), let b = ScheduleDays.date(to) else { return 0 }
        return ScheduleDays.calendar.dateComponents([.day], from: a, to: b).day ?? 0
    }

    static func monday(_ day: String) -> String { ScheduleDays.shift(day, by: 1 - ZendaProject.iso(day)) }

    static func format(_ day: String, _ pattern: String) -> String {
        guard let date = ScheduleDays.date(day) else { return day }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.calendar = ScheduleDays.calendar
        f.dateFormat = pattern
        return f.string(from: date)
    }
}

final class ZendaStore: ObservableObject {
    static let shared = ZendaStore()
    static let name = "zenda"

    @Published private(set) var projects: [ZendaProject] = []
    private let file = PocketData.zenda

    private init() {
        let vault = DataVault.shared
        vault.register(Self.name) { [weak self] data in self?.merge(data) }
        CloudSync.shared.register(Self.name) { [weak self] data in self?.adopt(data) }
        if FileManager.default.fileExists(atPath: file.path) {
            do {
                projects = try Self.decode(Data(contentsOf: file)).projects
                note("zenda projects loaded count=\(projects.count) path=\(file.path)")
                return
            } catch {
                note("zenda projects load failed path=\(file.path) error=\(error.localizedDescription)")
                vault.quarantine(file, name: Self.name)
            }
        }
        if let (saved, snap) = vault.recover(Self.name, decode: Self.decode) {
            projects = saved.projects
            note("zenda projects recovered from=\(snap.url.path) count=\(projects.count)")
            save()
            return
        }
        note("zenda projects empty path=\(file.path)")
    }

    static func decode(_ data: Data) throws -> ZendaFile { try JSONDecoder().decode(ZendaFile.self, from: data) }

    static func encode(_ file: ZendaFile) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(file)
    }

    var sorted: [ZendaProject] {
        projects.sorted { $0.start != $1.start ? $0.start < $1.start : $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func project(_ id: String?) -> ZendaProject? { projects.first { $0.id == id } }

    func applying(on day: String) -> [ZendaProject] { sorted.filter { $0.applies(day) } }

    func put(_ project: ZendaProject) {
        var project = project
        project.updated = KairosJournal.now()
        let isNew: Bool
        if let index = projects.firstIndex(where: { $0.id == project.id }) {
            projects[index] = project
            isNew = false
        } else {
            projects.append(project)
            isNew = true
        }
        note("zenda project saved id=\(project.id) name=\(project.name) new=\(isNew) routine=\(project.routine) start=\(project.start) end=\(project.end) days=\(project.days.map(String.init).joined(separator: ","))")
        save()
    }

    func merge(_ data: Data) {
        do {
            let incoming = try Self.decode(data).projects
            if let current = try? Self.encode(ZendaFile(projects: projects)) { DataVault.shared.keepAside(current, name: Self.name, reason: "before-merge") }
            var added = 0, replaced = 0
            for project in incoming {
                if let index = projects.firstIndex(where: { $0.id == project.id }) {
                    if project.updated > projects[index].updated {
                        projects[index] = project
                        replaced += 1
                    }
                } else {
                    projects.append(project)
                    added += 1
                }
            }
            save()
            note("zenda projects merged added=\(added) replaced=\(replaced) count=\(projects.count)")
        } catch {
            note("zenda projects merge failed bytes=\(data.count) error=\(error.localizedDescription)")
        }
    }

    func adopt(_ data: Data) {
        do {
            let incoming = try Self.decode(data).projects
            guard incoming != projects else { return }
            let before = projects.count
            projects = incoming
            save()
            note("zenda projects adopted cloud before=\(before) after=\(projects.count)")
        } catch {
            note("zenda projects adopt failed bytes=\(data.count) error=\(error.localizedDescription)")
        }
    }

    private func save() {
        do {
            let data = try Self.encode(ZendaFile(projects: projects))
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: file, options: .atomic)
            DataVault.shared.snapshot(data, name: Self.name, count: projects.count)
        } catch {
            note("zenda projects save failed count=\(projects.count) error=\(error.localizedDescription)")
        }
    }
}

enum ZendaStepKind: String, CaseIterable {
    case breathe
    case visualize
    case scan
    case say
    case write
    case review
    case other

    var symbol: String {
        switch self {
        case .breathe: return "wind"
        case .visualize: return "eye"
        case .scan: return "figure.mind.and.body"
        case .say: return "quote.bubble"
        case .write: return "pencil.line"
        case .review: return "book.closed"
        case .other: return "circle"
        }
    }

    var label: String {
        switch self {
        case .breathe: return "Breathe"
        case .visualize: return "Visualize"
        case .scan: return "Body scan"
        case .say: return "Affirm"
        case .write, .review: return "Write"
        case .other: return "Other"
        }
    }
}

enum ZendaRoutines {
    static let fitnessTypes: Set<String> = ["moves", "intervals", "rounds", "log"]

    static func mindful(_ step: ScheduleStep) -> Bool {
        let run = KairosPlan.run(step)
        switch KairosPlan.text(run["type"]) {
        case "box", "say", "write": return true
        case "timed": return !(run["reads"]?.list ?? []).isEmpty || (run["quiet"]?.flag ?? false)
        default: return false
        }
    }

    static func steps(_ routine: ScheduleRoutine) -> [ScheduleStep] {
        (Array(routine.plan.values) + Array((routine.dated ?? [:]).values)).flatMap { $0 }
    }

    static func owns(_ routine: ScheduleRoutine) -> Bool {
        let all = steps(routine)
        return !all.contains { fitnessTypes.contains(KairosPlan.type($0)) } && all.contains(where: mindful)
    }

    static func all(_ store: ScheduleStore = .shared) -> [ScheduleRoutine] { store.routines.filter(owns) }

    static func kind(_ step: ScheduleStep) -> ZendaStepKind {
        let run = KairosPlan.run(step)
        switch KairosPlan.text(run["type"]) {
        case "box": return .breathe
        case "say": return .say
        case "write": return KairosPlan.text(run["tag"]) == "review" ? .review : .write
        case "timed":
            if !(run["reads"]?.list ?? []).isEmpty { return .visualize }
            return (run["quiet"]?.flag ?? false) ? .scan : .other
        default: return .other
        }
    }

    static func name(_ step: ScheduleStep) -> String { KairosPlan.split(step.title).name }

    static func minutes(_ step: ScheduleStep) -> Int { KairosPlan.minutes(KairosPlan.estimate(step)) }
}

struct ZendaLedger {
    let store: ScheduleStore
    let routines: [ScheduleRoutine]
    private let done: Set<String>

    init(_ store: ScheduleStore = .shared) {
        self.store = store
        routines = ZendaRoutines.all(store)
        done = Set(store.book.checks.map(\.id))
    }

    func scope(_ project: ZendaProject?) -> [ScheduleRoutine] {
        guard let project else { return routines }
        return routines.filter { $0.id.uuidString == project.routine }
    }

    func sessions(on day: String, in pool: [ScheduleRoutine]? = nil) -> [KairosSession] {
        ScheduleSlot.allCases.flatMap { slot in
            (pool ?? routines).compactMap { routine -> KairosSession? in
                guard routine.runs(on: day) else { return nil }
                let steps = routine.steps(on: day, slot)
                guard steps.contains(where: KairosPlan.isGuided) else { return nil }
                let count = steps.filter { done.contains(ScheduleCheck.id(routine: routine.id, day: day, slot: slot, step: $0.id)) }.count
                return KairosSession(routine: routine, slot: slot, day: day, steps: steps, done: count)
            }
        }
    }

    func fill(on day: String, in pool: [ScheduleRoutine]? = nil) -> (done: Int, total: Int) {
        let list = sessions(on: day, in: pool)
        let slots = Set(list.map(\.slot))
        let finished = slots.filter { slot in list.filter { $0.slot == slot }.allSatisfy(\.finished) }
        return (finished.count, slots.count)
    }

    func doneSeconds(on day: String, in pool: [ScheduleRoutine]? = nil) -> Int {
        sessions(on: day, in: pool).reduce(0) { sum, session in
            sum + session.steps.filter { done.contains(ScheduleCheck.id(routine: session.routine.id, day: day, slot: session.slot, step: $0.id)) }
                .reduce(0) { $0 + KairosPlan.estimate($1) }
        }
    }

    func streak(today: String, in pool: [ScheduleRoutine]? = nil) -> Int {
        let first = (pool ?? routines).map(\.starts).min() ?? today
        var day = today
        var count = 0
        var guardDays = 0
        while day >= first && guardDays < 2000 {
            let fill = fill(on: day, in: pool)
            if fill.total > 0 {
                if fill.done == fill.total { count += 1 } else if day != today { break }
            }
            day = ScheduleDays.shift(day, by: -1)
            guardDays += 1
        }
        return count
    }
}

enum ZendaBooks {
    struct Book: Identifiable {
        let tag: String
        let name: String
        var id: String { tag }
    }

    static let all: [Book] = [
        Book(tag: "gratitude", name: "Gratitude"), Book(tag: "win", name: "Wins"), Book(tag: "script", name: "Scripts"),
        Book(tag: "action", name: "Actions"), Book(tag: "review", name: "Reviews"), Book(tag: "note", name: "Notes")
    ]

    static let tags = Set(all.map(\.tag))

    static func counts(_ entry: KairosEntry) -> Bool {
        guard let tag = entry.tag, tags.contains(tag), !entry.id.hasPrefix("template|"), !entry.id.hasPrefix("manual|") else { return false }
        return !entry.body.isEmpty
    }

    static func entries(_ journal: KairosJournal) -> [KairosEntry] { journal.entries.filter(counts) }

    static func name(_ tag: String?) -> String { all.first { $0.tag == tag }?.name ?? "Notes" }
}

enum ZendaAdhoc {
    enum Kind {
        case breathe
        case visualize
        case say
        case scan
        case write(String)
    }

    static func template(_ kind: Kind, in routines: [ScheduleRoutine]) -> ScheduleStep? {
        let today = ScheduleStore.shared.today
        let todays = routines.flatMap { r in ScheduleSlot.allCases.flatMap { r.steps(on: today, $0) } }
        let pool = todays + routines.flatMap(ZendaRoutines.steps)
        return pool.first { step in
            let run = KairosPlan.run(step)
            switch kind {
            case .breathe: return ZendaRoutines.kind(step) == .breathe
            case .visualize: return ZendaRoutines.kind(step) == .visualize
            case .say: return ZendaRoutines.kind(step) == .say
            case .scan: return ZendaRoutines.kind(step) == .scan
            case .write(let tag): return KairosPlan.text(run["type"]) == "write" && KairosPlan.text(run["tag"], "note") == tag
            }
        }
    }

    static func minutes(_ kind: Kind, in routines: [ScheduleRoutine]) -> Int? {
        template(kind, in: routines).map { KairosPlan.minutes(KairosPlan.num(KairosPlan.run($0)["seconds"])) }
    }

    static func step(_ kind: Kind, minutes: Int?, in routines: [ScheduleRoutine]) -> ScheduleStep {
        let found = template(kind, in: routines)
        var run: [String: Loose]
        var title: String
        if let found, case .object(let map) = KairosPlan.run(found) {
            run = map
            title = found.title
        } else {
            switch kind {
            case .breathe: run = ["type": .string("box")]; title = "Box breathing"
            case .visualize: run = ["type": .string("timed")]; title = "Visualize"
            case .say: run = ["type": .string("say")]; title = "Affirm"
            case .scan: run = ["type": .string("timed"), "quiet": .bool(true)]; title = "Body scan"
            case .write(let tag):
                run = ["type": .string("write"), "tag": .string(tag), "fields": .number(tag == "note" ? 0 : 3)]
                title = ZendaBooks.name(tag)
            }
        }
        if let minutes { run["seconds"] = .number(Double(minutes * 60)) }
        return ScheduleStep(id: UUID(), title: title, tip: found?.tip ?? "", run: .object(run))
    }

    static func start(_ step: ScheduleStep, source: String) {
        let store = ScheduleStore.shared
        let day = store.today
        let slot = store.slotNow
        let routine = ScheduleRoutine(id: UUID(), name: "Zenda", hue: 0, starts: day, dated: [ScheduleRoutine.key(day, slot): [step]])
        let session = KairosSession(routine: routine, slot: slot, day: day, steps: [step], done: 0)
        KairosRunner.zenda.start(session, adhoc: true)
        note("zenda session started adhoc=true source=\(source) step=\(ZendaRoutines.name(step)) type=\(KairosPlan.type(step)) seconds=\(KairosPlan.num(step.run?["seconds"])) day=\(day) slot=\(slot.rawValue)")
    }
}

extension KairosRunner {
    static let zenda = KairosRunner(key: "zenda.run")
}
