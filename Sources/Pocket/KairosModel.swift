import AppKit
import Combine
import Foundation
import SwiftUI

enum KairosBoard: BoardScope {
    static var theme: BoardTheme { AppThemeStore.shared.theme(for: "runner") }
}

enum KairosBeatKind: String {
    case count
    case rest
    case reps
    case say
    case write
    case log
}

struct KairosCue: Equatable {
    let at: Int
    let text: String
}

struct KairosBreath: Equatable {
    let index: Int
    let label: String
    let fraction: Double
    let left: Int
}

struct KairosBeat: Equatable {
    var step: Int
    var kind: KairosBeatKind
    var name: String
    var detail: String
    var tip: String
    var type: String
    var guide: Int
    var quiet: Bool
    var seconds = 0
    var reps = 0
    var label = ""
    var cues: [KairosCue] = []
    var moves: [String] = []
    var at = -1
    var round = 0
    var rounds = 0
    var hot = false
    var then: String?
    var nextName: String?
    var lines: [String] = []
    var times = 1
    var fields = 0
    var prompt = ""
    var tag = "note"
    var plan = ""
    var box: [Int] = []
    var reads: [String] = []
    var every = 20

    var counted: Bool { kind == .count || kind == .rest }
}

enum KairosPlan {
    static let guidedTypes: Set<String> = ["timed", "box", "moves", "intervals", "rounds", "log", "say", "write"]
    static let breathLabels = ["Breathe in", "Hold", "Breathe out", "Hold"]
    static let repSeconds = 3
    private static let minutePattern = try? NSRegularExpression(pattern: #"(\d+)\s*min\b"#)
    private static let trailingMinutes = try? NSRegularExpression(pattern: #",?\s*\d+\s*min\b.*$"#)

    static func split(_ title: String) -> (name: String, detail: String) { ScheduleStepText.parts(title) }

    static func run(_ step: ScheduleStep) -> Loose {
        if let run = step.run, let type = run["type"]?.string, !type.isEmpty { return run }
        let detail = split(step.title).detail
        let range = NSRange(detail.startIndex..., in: detail)
        if let match = minutePattern?.firstMatch(in: detail, range: range),
           let found = Range(match.range(at: 1), in: detail), let minutes = Int(detail[found]) {
            return .object(["type": .string("timed"), "seconds": .number(Double(minutes * 60))])
        }
        return .object(["type": .string("tap")])
    }

    static func num(_ value: Loose?, _ fallback: Int = 0) -> Int {
        guard let number = value?.number, number.isFinite, number > 0 else { return fallback }
        return Int(number.rounded())
    }

    static func text(_ value: Loose?, _ fallback: String = "") -> String {
        let found = value?.string ?? ""
        return found.isEmpty ? fallback : found
    }

    static func type(_ step: ScheduleStep) -> String { text(run(step)["type"]) }

    static func isGuided(_ step: ScheduleStep) -> Bool { guidedTypes.contains(type(step)) }

    static func capital(_ word: String) -> String { word.prefix(1).uppercased() + word.dropFirst() }

    static func beats(for steps: [ScheduleStep], day: String = "") -> [KairosBeat] {
        steps.enumerated().flatMap { index, step in beats(step, index: index, day: day) }
    }

    static func dayNumber(_ day: String) -> Int {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return 0 }
        let year = parts[1] <= 2 ? parts[0] - 1 : parts[0]
        let era = (year >= 0 ? year : year - 399) / 400
        let yearOfEra = year - era * 400
        let dayOfYear = (153 * ((parts[1] + 9) % 12) + 2) / 5 + parts[2] - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146097 + dayOfEra - 719468
    }

    static func pick(_ pool: Loose?, _ count: Loose?, day: String) -> [String] {
        let lines = (pool?.list ?? []).compactMap(\.string).filter { !$0.isEmpty }
        let take = min(num(count), lines.count)
        guard take > 0 else { return lines }
        let start = ((dayNumber(day) * take) % lines.count + lines.count) % lines.count
        return (0..<take).map { lines[(start + $0) % lines.count] }
    }

    static func pattern(_ run: Loose) -> [Int] {
        let values = (run["pattern"]?.list ?? []).map { max(0, Int(($0.number ?? 0).rounded())) }
        return values.count == 4 && values.contains(where: { $0 > 0 }) ? values : [4, 4, 4, 4]
    }

    static func breath(_ box: [Int], _ elapsed: Double) -> KairosBreath {
        let pattern = box.count == 4 ? box : [4, 4, 4, 4]
        let cycle = Double(max(1, pattern.reduce(0, +)))
        var time = elapsed.truncatingRemainder(dividingBy: cycle)
        if time < 0 { time += cycle }
        for index in 0..<4 where pattern[index] > 0 {
            let length = Double(pattern[index])
            if time < length {
                return KairosBreath(index: index, label: breathLabels[index], fraction: time / length, left: Int((length - time).rounded(.up)))
            }
            time -= length
        }
        return KairosBreath(index: 0, label: breathLabels[0], fraction: 0, left: pattern[0])
    }

    static func beats(_ step: ScheduleStep, index: Int, day: String = "") -> [KairosBeat] {
        let run = self.run(step)
        let kind = text(run["type"])
        let (name, detail) = split(step.title)
        let base = KairosBeat(step: index, kind: .reps, name: name, detail: detail, tip: step.tip, type: kind, guide: num(run["seconds"]), quiet: run["quiet"]?.flag ?? false)
        let moves = (run["moves"]?.list ?? []).filter { !text($0["name"]).isEmpty }
        let names = moves.map { text($0["name"]) }

        func move(_ item: Loose, _ at: Int) -> KairosBeat {
            var beat = base
            let seconds = num(item["seconds"])
            beat.kind = seconds > 0 ? .count : .reps
            beat.seconds = seconds
            beat.name = text(item["name"], name)
            beat.reps = num(item["reps"])
            beat.detail = text(item["detail"])
            beat.moves = names
            beat.at = at
            return beat
        }

        switch kind {
        case "timed", "box":
            var beat = base
            beat.kind = .count
            beat.seconds = num(run["seconds"], kind == "box" ? 240 : 60)
            if kind == "box" { beat.box = pattern(run) }
            beat.reads = pick(run["reads"], run["pick"], day: day)
            beat.every = num(run["every"], 20)
            beat.cues = (run["cues"]?.list ?? []).compactMap { cue in
                let words = text(cue["text"])
                return words.isEmpty ? nil : KairosCue(at: num(cue["at"]), text: words)
            }
            .sorted { $0.at < $1.at }
            return [beat]
        case "moves":
            guard !moves.isEmpty else { return [base] }
            return moves.enumerated().map { at, item in
                var beat = move(item, at)
                beat.label = "\(name) · move \(at + 1) of \(moves.count)"
                return beat
            }
        case "intervals":
            let rounds = num(run["rounds"], 1)
            let rotate = (run["names"]?.list ?? []).compactMap(\.string)
            let on = num(run["on"], 30)
            let off = num(run["off"])
            let unit = text(run["unit"], "interval")
            let onLabel = text(run["onLabel"], "Go")
            let offName = text(run["offName"], "Rest")
            let single = text(run["onName"], name)
            var out: [KairosBeat] = []
            for round in 0..<rounds {
                let label = rotate.isEmpty ? single : rotate[round % rotate.count]
                let following = rotate.isEmpty ? label : rotate[(round + 1) % rotate.count]
                let resting = round < rounds - 1 && off > 0
                var go = base
                go.kind = .count
                go.seconds = on
                go.name = label
                go.label = "\(onLabel) · \(unit) \(round + 1) of \(rounds)"
                go.round = round
                go.rounds = rounds
                go.hot = true
                go.then = resting ? "Then \(offName.lowercased()) \(clock(off)), then \(following)" : nil
                out.append(go)
                if resting {
                    var pause = base
                    pause.kind = .rest
                    pause.seconds = off
                    pause.name = offName
                    pause.label = "\(capital(unit)) \(round + 1) of \(rounds) done"
                    pause.round = round
                    pause.rounds = rounds
                    pause.nextName = following
                    out.append(pause)
                }
            }
            return out
        case "rounds":
            guard !moves.isEmpty else { return [base] }
            let rounds = num(run["rounds"], 1)
            let unit = text(run["unit"], "round")
            let rest = num(run["rest"])
            var out: [KairosBeat] = []
            for round in 0..<rounds {
                for (at, item) in moves.enumerated() {
                    var beat = move(item, at)
                    beat.round = round
                    beat.rounds = rounds
                    beat.label = "\(name) · \(unit) \(round + 1) of \(rounds)"
                    out.append(beat)
                }
                if round < rounds - 1 && rest > 0 {
                    var pause = base
                    pause.kind = .rest
                    pause.seconds = rest
                    pause.name = "Rest"
                    pause.label = "\(capital(unit)) \(round + 1) of \(name) done"
                    pause.round = round
                    pause.rounds = rounds
                    pause.nextName = names[0]
                    pause.reps = num(moves[0]["reps"])
                    pause.moves = names
                    out.append(pause)
                }
            }
            return out
        case "log":
            var beat = base
            beat.kind = .log
            beat.plan = text(run["plan"], detail.isEmpty ? name : detail)
            beat.tag = "run"
            return [beat]
        case "say":
            var beat = base
            beat.kind = .say
            beat.lines = (run["lines"]?.list ?? []).compactMap(\.string) + ((run["pool"]?.list ?? []).isEmpty ? [] : pick(run["pool"], run["pick"], day: day))
            beat.times = num(run["times"], 1)
            return [beat]
        case "write":
            var beat = base
            beat.kind = .write
            beat.fields = num(run["fields"])
            beat.prompt = text(run["prompt"])
            beat.tag = text(run["tag"], "note")
            return [beat]
        default:
            var beat = base
            beat.detail = text(run["detail"], detail)
            return [beat]
        }
    }

    static func estimate(_ step: ScheduleStep) -> Int {
        let run = self.run(step)
        if text(run["type"]) == "log" { return num(run["seconds"], 15 * 60) }
        let counted = beats(step, index: 0).reduce(0) { sum, beat in
            sum + beat.seconds + (beat.kind == .reps ? max(20, (beat.reps > 0 ? beat.reps : 10) * repSeconds) : 0)
        }
        return max(counted, num(run["seconds"]))
    }

    static func howLabel(_ step: ScheduleStep) -> String {
        let run = self.run(step)
        let moves = run["moves"]?.list ?? []
        switch text(run["type"]) {
        case "timed": return (run["reads"]?.list ?? []).isEmpty ? "Timer" : "Timer · lines to read if it's hard to picture"
        case "box": return "Box breathing \(pattern(run).map(String.init).joined(separator: "-")) · follow the ball"
        case "moves": return moves.isEmpty ? "Tap Done when finished" : "\(moves.count) moves, each named"
        case "intervals":
            let off = num(run["off"])
            let rest = off > 0 ? ", \(off)s \(text(run["offName"], "rest").lowercased())" : ""
            let rotate = (run["names"]?.list.count ?? 0) > 1 ? " · moves rotate" : ""
            return "\(num(run["rounds"], 1)) × \(num(run["on"], 30))s on\(rest)\(rotate)"
        case "rounds":
            let rest = num(run["rest"])
            return "\(num(run["rounds"], 1)) \(text(run["unit"], "round"))s of \(moves.count) move\(moves.count == 1 ? "" : "s")\(rest > 0 ? " · \(rest)s rest" : "")"
        case "log": return "Do it, then enter time and distance"
        case "say":
            let pool = run["pool"]?.list.count ?? 0
            let count = (run["lines"]?.list.count ?? 0) + (pool > 0 ? min(num(run["pick"], pool), pool) : 0)
            return "Out loud · \(count) lines\(pool > 0 ? " (fresh daily)" : ""), \(num(run["times"], 1)) times each"
        case "write": return num(run["fields"]) > 1 ? "Write \(num(run["fields"])) lines" : "Write it down"
        default: return "Tap Done when finished"
        }
    }

    static func plainDetail(_ detail: String) -> String {
        guard let pattern = trailingMinutes else { return detail }
        let range = NSRange(detail.startIndex..., in: detail)
        return pattern.stringByReplacingMatches(in: detail, range: range, withTemplate: "").trimmingCharacters(in: .whitespaces)
    }

    static func clock(_ seconds: Double) -> String {
        let whole = max(0, Int(seconds.rounded()))
        return "\(whole / 60):" + String(format: "%02d", whole % 60)
    }

    static func clock(_ seconds: Int) -> String { clock(Double(seconds)) }

    static func minutes(_ seconds: Int) -> Int { max(1, Int((Double(seconds) / 60).rounded())) }
}

struct KairosEntry: Codable, Identifiable, Equatable {
    var id: String
    var routine: String
    var routineName: String?
    var day: String
    var slot: String
    var step: String
    var title: String?
    var tag: String?
    var lines: [String]?
    var text: String?
    var seconds: Double?
    var km: Double?
    var notes: String?
    var feel: String?
    var prompts: [String]?
    var updated: String?

    static func id(routine: UUID, day: String, slot: ScheduleSlot, step: String) -> String {
        "\(routine.uuidString)|\(day)|\(slot.rawValue)|\(step)"
    }

    var body: String {
        if let lines, lines.contains(where: { !$0.isEmpty }) {
            let kept = lines.filter { !$0.isEmpty }
            return kept.count == 1 ? kept[0] : kept.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        }
        if let text, !text.isEmpty { return text }
        if tag == "run" {
            var parts: [String] = []
            if let km { parts.append("\(KairosEntry.number(km)) km") }
            if let seconds { parts.append("in \(KairosPlan.clock(seconds))") }
            if let seconds, let km, km > 0 { parts.append("· \(KairosPlan.clock(seconds / km)) /km") }
            if let notes, !notes.isEmpty { parts.append("\n" + notes) }
            return parts.joined(separator: " ")
        }
        if let feel { return "Felt \(feel.replacingOccurrences(of: "-", with: " "))" }
        return ""
    }

    static func number(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%g", value)
    }
}

struct KairosJournalFile: Codable, Equatable {
    var entries: [KairosEntry]
}

final class KairosJournal: ObservableObject {
    static let shared = KairosJournal()
    static let name = "runner"

    @Published private(set) var entries: [KairosEntry] = []
    private let file = PocketData.runner
    private static let stamp: ISO8601DateFormatter = {
        let format = ISO8601DateFormatter()
        format.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return format
    }()

    private init() {
        let vault = DataVault.shared
        vault.register(Self.name) { [weak self] data in self?.merge(data) }
        CloudSync.shared.register(Self.name) { [weak self] data in self?.adopt(data) }
        if FileManager.default.fileExists(atPath: file.path) {
            do {
                entries = try Self.decode(Data(contentsOf: file)).entries
                note("kairos journal loaded entries=\(entries.count) path=\(file.path)")
                return
            } catch {
                note("kairos journal load failed path=\(file.path) error=\(error.localizedDescription)")
                vault.quarantine(file, name: Self.name)
            }
        }
        if let (saved, snap) = vault.recover(Self.name, decode: Self.decode) {
            entries = saved.entries
            note("kairos journal recovered from=\(snap.url.path) entries=\(entries.count)")
            save()
            return
        }
        note("kairos journal empty path=\(file.path)")
    }

    static func decode(_ data: Data) throws -> KairosJournalFile {
        try JSONDecoder().decode(KairosJournalFile.self, from: data)
    }

    static func encode(_ journal: KairosJournalFile) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(journal)
    }

    static func now() -> String { stamp.string(from: Date()) }

    var sorted: [KairosEntry] {
        entries.sorted { a, b in
            if a.day != b.day { return a.day > b.day }
            if a.slot != b.slot { return a.slot == "night" }
            return (a.updated ?? "") > (b.updated ?? "")
        }
    }

    func entry(_ id: String) -> KairosEntry? { entries.first { $0.id == id } }

    static let notWriting: Set<String> = ["feel", "manual", "template", "project", "workout", "run"]

    static func isDaily(_ entry: KairosEntry) -> Bool { !notWriting.contains(entry.tag ?? "") }

    var templates: [KairosEntry] {
        entries.filter { $0.tag == "template" }.sorted { ($0.title ?? "").localizedCaseInsensitiveCompare($1.title ?? "") == .orderedAscending }
    }

    var manual: [KairosEntry] {
        entries.filter { $0.tag == "manual" }.sorted { a, b in
            a.day != b.day ? a.day > b.day : (a.updated ?? "") > (b.updated ?? "")
        }
    }

    static let blankBook = "Blank page"

    func book(_ entry: KairosEntry) -> String {
        let name = (entry.routineName ?? "").trimmingCharacters(in: .whitespaces)
        if !name.isEmpty { return name }
        let shelf = templates
        if let prompts = entry.prompts, !prompts.isEmpty, let match = shelf.first(where: { ($0.lines ?? []) == prompts }), let title = match.title {
            return title
        }
        let title = (entry.title ?? "").trimmingCharacters(in: .whitespaces)
        if let match = shelf.first(where: { ($0.title ?? "").caseInsensitiveCompare(title) == .orderedSame }), let found = match.title {
            return found
        }
        return Self.blankBook
    }

    static func fresh(_ kind: String, title: String, prompts: [String], day: String) -> KairosEntry {
        let step = UUID().uuidString
        return KairosEntry(id: "\(kind)|\(step)", routine: kind, day: day, slot: "", step: step, title: title, tag: kind,
                           lines: kind == "template" ? prompts : nil, prompts: kind == "manual" && !prompts.isEmpty ? prompts : nil)
    }

    func put(_ entry: KairosEntry) {
        var entry = entry
        entry.updated = Self.now()
        if let index = entries.firstIndex(where: { $0.id == entry.id }) {
            guard Self.differs(entries[index], entry) else { return }
            entries[index] = entry
        } else {
            entries.append(entry)
        }
        note("kairos journal saved id=\(entry.id) tag=\(entry.tag ?? "note") routine=\(entry.routineName ?? entry.routine) day=\(entry.day) slot=\(entry.slot) chars=\(entry.body.count)")
        save()
    }

    private static func differs(_ a: KairosEntry, _ b: KairosEntry) -> Bool {
        var a = a, b = b
        a.updated = nil
        b.updated = nil
        return a != b
    }

    func merge(_ data: Data) {
        do {
            let incoming = try Self.decode(data).entries
            if let current = try? Self.encode(KairosJournalFile(entries: entries)) { DataVault.shared.keepAside(current, name: Self.name, reason: "before-merge") }
            var added = 0, replaced = 0
            for entry in incoming {
                if let index = entries.firstIndex(where: { $0.id == entry.id }) {
                    if (entry.updated ?? "") > (entries[index].updated ?? "") {
                        entries[index] = entry
                        replaced += 1
                    }
                } else {
                    entries.append(entry)
                    added += 1
                }
            }
            save()
            note("kairos journal merged added=\(added) replaced=\(replaced) entries=\(entries.count)")
        } catch {
            note("kairos journal merge failed bytes=\(data.count) error=\(error.localizedDescription)")
        }
    }

    func adopt(_ data: Data) {
        do {
            let incoming = try Self.decode(data).entries
            guard incoming != entries else { return }
            let before = entries.count
            entries = incoming
            save()
            note("kairos journal adopted cloud before=\(before) after=\(entries.count)")
        } catch {
            note("kairos journal adopt failed bytes=\(data.count) error=\(error.localizedDescription)")
        }
    }

    private func save() {
        do {
            let data = try Self.encode(KairosJournalFile(entries: entries))
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: file, options: .atomic)
            DataVault.shared.snapshot(data, name: Self.name, count: entries.count)
        } catch {
            note("kairos journal save failed entries=\(entries.count) error=\(error.localizedDescription)")
        }
    }
}

struct KairosSession: Identifiable {
    let routine: ScheduleRoutine
    let slot: ScheduleSlot
    let day: String
    let steps: [ScheduleStep]
    let done: Int

    var id: String { "\(routine.id.uuidString)|\(slot.rawValue)" }
    var total: Int { steps.count }
    var finished: Bool { done == total }
    var seconds: Int { steps.reduce(0) { $0 + KairosPlan.estimate($1) } }
    var writing: Int { steps.filter { KairosPlan.type($0) == "write" }.count }

    static func all(on day: String) -> [KairosSession] {
        let routines = KairosFit.routines
        return ScheduleSlot.allCases.flatMap { slot in
            routines.flatMap { of($0, on: day).filter { $0.slot == slot } }
        }
    }

    static func of(_ routine: ScheduleRoutine, on day: String) -> [KairosSession] {
        guard routine.runs(on: day) else { return [] }
        let store = ScheduleStore.shared
        return ScheduleSlot.allCases.compactMap { slot -> KairosSession? in
            let steps = routine.steps(on: day, slot)
            guard steps.contains(where: KairosPlan.isGuided) else { return nil }
            let done = store.items(on: day, slot: slot, in: [routine]).filter(\.done).count
            return KairosSession(routine: routine, slot: slot, day: day, steps: steps, done: done)
        }
    }

    static func dayNumber(_ routine: ScheduleRoutine, on day: String) -> (n: Int, of: Int)? {
        guard let ends = routine.ends, let start = ScheduleDays.date(routine.starts), let today = ScheduleDays.date(day), let last = ScheduleDays.date(ends) else { return nil }
        let span = { (a: Date, b: Date) in ScheduleDays.calendar.dateComponents([.day], from: a, to: b).day ?? 0 }
        return (span(start, today) + 1, span(start, last) + 1)
    }

    static func title(_ routine: ScheduleRoutine, on day: String) -> String {
        dayNumber(routine, on: day).map { "\(routine.name) · Day \($0.n)" } ?? routine.name
    }
}

struct KairosRunState: Codable, Equatable {
    var routine: UUID
    var day: String
    var slot: ScheduleSlot
    var index: Int
    var started: Date
    var stepStarted: Date
    var paused = false
    var waiting = false
    var left: Double?
    var endsAt: Date?
    var sayLine = 0
    var said = 0
    var finished: Date?
    var spent: [String: Int] = [:]
    var adhoc: [ScheduleStep]?
    var adhocName: String?
    var only: [UUID]?
    var workout: String?

    var isAdhoc: Bool { adhoc != nil }
}

struct KairosLive {
    let routine: ScheduleRoutine
    let steps: [ScheduleStep]
    let beats: [KairosBeat]
    let index: Int

    var beat: KairosBeat? { beats.indices.contains(index) ? beats[index] : nil }
    var next: KairosBeat? { beats.indices.contains(index + 1) ? beats[index + 1] : nil }
}

final class KairosRunner: ObservableObject {
    static let shared = KairosRunner()
    static let stateKey = "runner.run"
    static let soundKey = "runner.sound"
    static let holdKey = "runner.hold"

    @Published private(set) var state: KairosRunState?
    @Published private(set) var now = Date()
    var onChange: (() -> Void)?
    let key: String
    private var clock: Timer?
    private var shownSecond = -1

    init(key: String = KairosRunner.stateKey) {
        self.key = key
        if let data = UserDefaults.standard.data(forKey: key) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            state = try? decoder.decode(KairosRunState.self, from: data)
        }
        if state != nil, live == nil { state = nil }
        if state?.finished == nil, state != nil { startClock() }
    }

    static var sound: Bool {
        get { UserDefaults.standard.object(forKey: soundKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: soundKey) }
    }

    static var hold: Bool {
        get { UserDefaults.standard.bool(forKey: holdKey) }
        set { UserDefaults.standard.set(newValue, forKey: holdKey) }
    }

    var live: KairosLive? {
        guard let state, let routine = ScheduleStore.shared.routine(state.routine) ?? state.adhoc.map({ ScheduleRoutine(id: state.routine, name: state.adhocName ?? "", hue: 0, starts: state.day, dated: [ScheduleRoutine.key(state.day, state.slot): $0]) }) else { return nil }
        var steps = routine.steps(on: state.day, state.slot)
        if let only = state.only { steps = steps.filter { only.contains($0.id) } }
        let beats = KairosPlan.beats(for: steps, day: state.day)
        guard !beats.isEmpty else { return nil }
        return KairosLive(routine: routine, steps: steps, beats: beats, index: min(state.index, beats.count - 1))
    }

    var running: Bool { state != nil && state?.finished == nil }

    func isRunning(_ session: KairosSession) -> Bool {
        guard let state, state.finished == nil, !state.isAdhoc else { return false }
        return state.routine == session.routine.id && state.slot == session.slot && state.day == session.day
    }

    func start(_ session: KairosSession, adhoc: Bool = false) {
        let store = ScheduleStore.shared
        let items = store.items(on: session.day, slot: session.slot, in: [session.routine])
        let first = adhoc ? 0 : (items.firstIndex { !$0.done } ?? 0)
        let beats = KairosPlan.beats(for: session.steps, day: session.day)
        guard !beats.isEmpty else { return note("kairos run refused routine=\(session.routine.name) day=\(session.day) cause=no beats") }
        let index = max(0, beats.firstIndex { $0.step == first } ?? 0)
        state = KairosRunState(routine: session.routine.id, day: session.day, slot: session.slot, index: index, started: Date(), stepStarted: Date(),
                               adhoc: adhoc ? session.steps : nil, adhocName: adhoc ? session.routine.name : nil)
        if beats.indices.contains(index) { enter(beats[index], newStep: true) }
        startClock()
        note("kairos run started routine=\(session.routine.name) day=\(session.day) slot=\(session.slot.rawValue) step=\(first + 1) of=\(session.total) beats=\(beats.count) adhoc=\(adhoc)")
        publish()
    }

    func start(step: ScheduleStep, of routine: ScheduleRoutine, day: String, slot: ScheduleSlot) {
        guard routine.steps(on: day, slot).contains(where: { $0.id == step.id }) else {
            return note("kairos step run refused routine=\(routine.name) day=\(day) step=\(step.title) cause=missing")
        }
        var fresh = KairosRunState(routine: routine.id, day: day, slot: slot, index: 0, started: Date(), stepStarted: Date())
        fresh.only = [step.id]
        fresh.adhoc = [step]
        fresh.adhocName = routine.name
        state = fresh
        guard let live, let first = live.beat else {
            state = nil
            save()
            return note("kairos step run refused routine=\(routine.name) day=\(day) step=\(step.title) cause=no beats")
        }
        enter(first, newStep: true)
        startClock()
        note("kairos step run started routine=\(routine.name) day=\(day) slot=\(slot.rawValue) step=\(KairosPlan.split(step.title).name) beats=\(live.beats.count)")
        publish()
    }

    private func enter(_ beat: KairosBeat, newStep: Bool) {
        guard var state else { return }
        state.sayLine = 0
        state.said = 0
        if newStep { state.stepStarted = Date() }
        state.waiting = newStep && Self.hold && state.index > 0
        state.left = beat.counted ? Double(beat.seconds) : nil
        state.paused = state.waiting
        state.endsAt = beat.counted && !state.paused ? Date().addingTimeInterval(Double(beat.seconds)) : nil
        self.state = state
        save()
    }

    private func complete(_ live: KairosLive, step index: Int) {
        guard var state, live.steps.indices.contains(index) else { return }
        let step = live.steps[index]
        state.spent[String(index), default: 0] += Int(Date().timeIntervalSince(state.stepStarted).rounded())
        self.state = state
        guard !state.isAdhoc else { return }
        let store = ScheduleStore.shared
        if let item = store.items(on: state.day, slot: state.slot, in: [live.routine]).first(where: { $0.step.id == step.id }), !item.done {
            store.set(item, done: true)
        }
    }

    func advance(tick: Bool = true) {
        guard let live, let current = live.beat else { return end(reason: "missing") }
        let next = live.next
        if tick, next == nil || next?.step != current.step { complete(live, step: current.step) }
        guard let next else {
            state?.finished = Date()
            if state?.isAdhoc == true, key == Self.stateKey { logWorkout(live) }
            save()
            stopClock()
            chime(strong: true)
            note("kairos run finished routine=\(live.routine.name) day=\(state?.day ?? "") slot=\(state?.slot.rawValue ?? "") ticked=\(tick)")
            publish()
            return
        }
        state?.index = live.index + 1
        enter(next, newStep: next.step != current.step)
        if !current.quiet && tick { chime(strong: false) }
        publish()
    }

    private func logWorkout(_ live: KairosLive) {
        guard var state, state.workout == nil else { return }
        let id = "workout|\(UUID().uuidString)"
        let title = live.steps.count == 1 ? KairosPlan.split(live.steps[0].title).name : KairosFit.title(live.steps, fallback: live.routine.name)
        let seconds = max(0, ((state.finished ?? Date()).timeIntervalSince(state.started)).rounded())
        let entry = KairosEntry(id: id, routine: live.routine.id.uuidString, routineName: live.routine.name, day: ScheduleStore.shared.today,
                                slot: "", step: "guided", title: title, tag: "workout", seconds: seconds)
        KairosJournal.shared.put(entry)
        state.workout = id
        self.state = state
        note("kairos workout logged id=\(id) kind=guided routine=\(live.routine.name) title=\(title) seconds=\(Int(seconds))")
    }

    func back() {
        guard let live, live.index > 0, let current = live.beat else { return }
        let previous = live.beats[live.index - 1]
        state?.index = live.index - 1
        enter(previous, newStep: previous.step != current.step)
        publish()
    }

    func jump(to step: Int) {
        guard let live, let index = live.beats.firstIndex(where: { $0.step == step }) else { return }
        state?.index = index
        enter(live.beats[index], newStep: true)
        note("kairos run jumped routine=\(live.routine.name) step=\(step + 1)")
        publish()
    }

    func togglePause() {
        guard var state else { return }
        if state.waiting {
            state.waiting = false
            state.paused = false
            state.stepStarted = Date()
            if let left = state.left { state.endsAt = Date().addingTimeInterval(left) }
        } else if state.paused {
            state.paused = false
            if let left = state.left { state.endsAt = Date().addingTimeInterval(left) }
        } else {
            state.paused = true
            if let ends = state.endsAt { state.left = max(0, ends.timeIntervalSinceNow) }
            state.endsAt = nil
        }
        self.state = state
        save()
        publish()
    }

    func addTime(_ seconds: Double) {
        guard var state else { return }
        if let ends = state.endsAt { state.endsAt = ends.addingTimeInterval(seconds) } else if let left = state.left { state.left = left + seconds }
        self.state = state
        save()
        publish()
    }

    func said() {
        guard let live, let beat = live.beat, var state else { return }
        let lines = beat.lines.isEmpty ? [beat.name] : beat.lines
        state.said += 1
        if state.said >= beat.times {
            state.said = 0
            state.sayLine += 1
            if state.sayLine >= lines.count {
                self.state = state
                return advance()
            }
            chime(strong: false)
        }
        self.state = state
        save()
        publish()
    }

    func end(reason: String) {
        if let live, let state {
            note("kairos run ended routine=\(live.routine.name) day=\(state.day) slot=\(state.slot.rawValue) beat=\(live.index + 1) of=\(live.beats.count) reason=\(reason)")
        }
        state = nil
        save()
        stopClock()
        publish()
    }

    var remaining: Double {
        guard let state else { return 0 }
        if let ends = state.endsAt { return max(0, ends.timeIntervalSince(now)) }
        return state.left ?? 0
    }

    func softLeft(_ beat: KairosBeat) -> Double? {
        guard beat.guide > 0, let state else { return nil }
        let used = state.paused && !state.waiting ? 0 : now.timeIntervalSince(state.stepStarted)
        return max(0, Double(beat.guide) - used)
    }

    func sessionLeft(_ live: KairosLive) -> Double {
        guard let beat = live.beat else { return 0 }
        let later = live.steps.enumerated().filter { $0.offset > beat.step }.reduce(0) { $0 + KairosPlan.estimate($1.element) }
        let here = live.beats.enumerated().filter { $0.offset > live.index && $0.element.step == beat.step }.reduce(0) { $0 + $1.element.seconds + ($1.element.kind == .reps ? 30 : 0) }
        return Double(later + here) + (state?.left != nil ? remaining : 0)
    }

    private func startClock() {
        guard clock == nil else { return }
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        clock = timer
    }

    private func stopClock() {
        clock?.invalidate()
        clock = nil
    }

    private func tick() {
        now = Date()
        guard let state, state.finished == nil else { return }
        if let ends = state.endsAt, ends <= now, let beat = live?.beat, beat.counted {
            advance()
            return
        }
        let second = Int(remaining.rounded(.up))
        if second != shownSecond {
            shownSecond = second
            onChange?()
        }
    }

    private func publish() {
        now = Date()
        shownSecond = -1
        onChange?()
    }

    private func save() {
        guard let state else {
            UserDefaults.standard.removeObject(forKey: key)
            return
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(state) { UserDefaults.standard.set(data, forKey: key) }
    }

    func chime(strong: Bool) {
        guard Self.sound else { return }
        NSSound(named: strong ? "Glass" : "Tink")?.play()
    }
}

enum KairosFit {
    static let types: Set<String> = ["moves", "intervals", "rounds", "log"]
    private static let minutesOnly = try? NSRegularExpression(pattern: #"^\s*\d+\s*min\b.*$"#)
    private static let firstNumber = try? NSRegularExpression(pattern: #"\d+(?:[.,]\d+)?"#)
    private static let restName = try? NSRegularExpression(pattern: #"stretch|mobility|cool.?down|recovery|rest"#, options: .caseInsensitive)
    private static let sideName = try? NSRegularExpression(pattern: #"warm|stretch|cool|calves|shins|mobility"#, options: .caseInsensitive)
    static let kmPattern = try? NSRegularExpression(pattern: #"\bkm\b"#, options: .caseInsensitive)

    static func matches(_ pattern: NSRegularExpression?, _ text: String) -> Bool {
        pattern?.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    static func isFitness(_ routine: ScheduleRoutine) -> Bool {
        let lists = Array(routine.plan.values) + Array((routine.dated ?? [:]).values)
        return lists.contains { $0.contains { types.contains(KairosPlan.type($0)) } }
    }

    static var routines: [ScheduleRoutine] { ScheduleStore.shared.routines.filter(isFitness) }

    static func name(_ step: ScheduleStep) -> String { KairosPlan.split(step.title).name }

    static func easy(_ step: ScheduleStep) -> Bool { matches(restName, name(step)) }

    static func warm(_ step: ScheduleStep) -> Bool { name(step).lowercased().hasPrefix("warm") }

    static func days(_ from: String, _ to: String) -> Int { KairosPlan.dayNumber(to) - KairosPlan.dayNumber(from) }

    static func monday(_ day: String) -> String {
        ScheduleDays.shift(day, by: -((ScheduleDays.weekday(day) + 5) % 7))
    }

    static func range(_ from: String, _ to: String) -> [String] {
        let count = days(from, to)
        guard count >= 0, ScheduleDays.date(from) != nil else { return [] }
        return (0...min(count, 730)).map { ScheduleDays.shift(from, by: $0) }
    }

    static func steps(_ routine: ScheduleRoutine, on day: String) -> [(slot: ScheduleSlot, step: ScheduleStep)] {
        guard routine.runs(on: day) else { return [] }
        return ScheduleSlot.allCases.flatMap { slot in routine.steps(on: day, slot).map { (slot: slot, step: $0) } }
    }

    static func short(_ name: String) -> String {
        let lower = name.lowercased()
        return lower.contains("rope") || lower.contains("skip") ? "Rope" : name
    }

    static func title(_ steps: [ScheduleStep], fallback: String) -> String {
        var names: [String] = []
        for step in steps {
            let label = name(step)
            if !label.isEmpty && !names.contains(label) { names.append(label) }
        }
        let main = names.filter { !matches(sideName, $0) }
        let pick = main.isEmpty ? Array(names.prefix(2)) : Array(main.prefix(2))
        return pick.isEmpty ? fallback : pick.map(short).joined(separator: " + ")
    }

    static func seconds(_ steps: [ScheduleStep]) -> Int { steps.reduce(0) { $0 + KairosPlan.estimate($1) } }

    static func detail(_ step: ScheduleStep) -> String {
        let detail = KairosPlan.split(step.title).detail
        let range = NSRange(detail.startIndex..., in: detail)
        if minutesOnly?.firstMatch(in: detail, range: range) != nil { return "" }
        return detail.replacingOccurrences(of: ", ", with: " · ")
    }

    static func intervals(_ step: ScheduleStep) -> [(seconds: Int, hot: Bool)] {
        let run = KairosPlan.run(step)
        guard KairosPlan.text(run["type"]) == "intervals" else { return [] }
        let rounds = min(KairosPlan.num(run["rounds"], 1), 30)
        let on = KairosPlan.num(run["on"], 30)
        let off = KairosPlan.num(run["off"])
        var out: [(seconds: Int, hot: Bool)] = []
        for round in 0..<rounds {
            out.append((seconds: on, hot: true))
            if off > 0 && round < rounds - 1 { out.append((seconds: off, hot: false)) }
        }
        return out
    }

    static func sets(_ step: ScheduleStep) -> [Int] {
        let run = KairosPlan.run(step)
        guard KairosPlan.text(run["type"]) == "rounds" else { return [] }
        let moves = (run["moves"]?.list ?? []).filter { !KairosPlan.text($0["name"]).isEmpty }
        guard moves.count == 1 else { return [] }
        let reps = KairosPlan.num(moves[0]["reps"])
        guard reps > 0 else { return [] }
        return Array(repeating: reps, count: min(KairosPlan.num(run["rounds"], 1), 40))
    }

    static func setsLabel(_ step: ScheduleStep) -> String? {
        let run = KairosPlan.run(step)
        guard KairosPlan.text(run["type"]) == "rounds" else { return nil }
        let moves = run["moves"]?.list ?? []
        let chips = Self.sets(step)
        if !chips.isEmpty { return "\(chips.reduce(0, +))" }
        guard let first = moves.first, KairosPlan.num(first["reps"]) > 0 else { return nil }
        return "\(KairosPlan.num(run["rounds"], 1)) × \(KairosPlan.num(first["reps"]))"
    }

    static func number(_ text: String) -> Double? {
        let range = NSRange(text.startIndex..., in: text)
        guard let match = firstNumber?.firstMatch(in: text, range: range), let found = Range(match.range, in: text) else { return nil }
        return Double(text[found].replacingOccurrences(of: ",", with: "."))
    }

    static func same(_ entry: KairosEntry, _ routine: ScheduleRoutine) -> Bool {
        entry.routine.caseInsensitiveCompare(routine.id.uuidString) == .orderedSame
    }

    static func feelScore(_ value: String?) -> Int? {
        guard let value = value?.lowercased(), !value.isEmpty else { return nil }
        switch value {
        case "easy": return 2
        case "right": return 3
        case "hard", "too-hard": return 4
        default:
            guard let number = Int(value), (1...5).contains(number) else { return nil }
            return number
        }
    }
}

enum KairosDayState: Equatable {
    case off
    case rest
    case future
    case open
    case done
    case part
    case missed

    static func of(_ routine: ScheduleRoutine, on day: String, today: String) -> KairosDayState {
        let list = KairosFit.steps(routine, on: day)
        guard !list.isEmpty else { return .off }
        if list.allSatisfy({ KairosFit.easy($0.step) }) { return .rest }
        return status(routine, on: day, today: today)
    }

    static func status(_ routine: ScheduleRoutine, on day: String, today: String) -> KairosDayState {
        let list = KairosFit.steps(routine, on: day)
        guard !list.isEmpty else { return .off }
        let store = ScheduleStore.shared
        let done = ScheduleSlot.allCases.flatMap { store.items(on: day, slot: $0, in: [routine]) }.filter(\.done).count
        if done >= list.count { return .done }
        if done > 0 { return .part }
        if day > today { return .future }
        return day == today ? .open : .missed
    }
}

struct VentusMilestone: Hashable {
    var day: String
    var label: String
}

enum VentusKind: String, CaseIterable, Identifiable {
    case run
    case rope
    case walk
    case gym
    case other

    var id: String { rawValue }
    var label: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
    var distance: Bool { self == .run || self == .walk }
}

struct VentusProject: Identifiable, Equatable {
    let routine: ScheduleRoutine
    var entryId: String
    var name: String
    var goal: String
    var start: String
    var end: String
    var targets: [String]
    var achieved: Set<Int>
    var milestones: [VentusMilestone]

    var id: UUID { routine.id }
    var total: Int { max(1, KairosFit.days(start, end) + 1) }
    var days: [String] { KairosFit.range(start, end) }

    func dayNumber(_ day: String) -> Int { KairosFit.days(start, day) + 1 }

    static func all(_ journal: KairosJournal) -> [VentusProject] {
        KairosFit.routines.map { make($0, journal) }.sorted { $0.start < $1.start }
    }

    static func current(_ projects: [VentusProject], today: String) -> VentusProject? {
        projects.first { $0.start <= today && today <= $0.end } ?? projects.first
    }

    static func valid(_ day: String?) -> String? {
        guard let day = day?.trimmingCharacters(in: .whitespaces), day.count == 10, ScheduleDays.date(day) != nil else { return nil }
        return day
    }

    static func make(_ routine: ScheduleRoutine, _ journal: KairosJournal) -> VentusProject {
        let key = "project|\(routine.id.uuidString)"
        let entry = journal.entries.first { $0.id.caseInsensitiveCompare(key) == .orderedSame }
            ?? journal.entries.first { $0.tag == "project" && KairosFit.same($0, routine) }
        let dated = (routine.dated ?? [:]).keys.map { String($0.prefix(10)) }.filter { valid($0) != nil }.max()
        let start = valid(entry?.day) ?? routine.starts
        var end = valid(entry?.notes) ?? routine.ends ?? dated ?? ScheduleDays.shift(start, by: 27)
        if end < start { end = start }
        let targets = (entry?.lines ?? []).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let achieved = Set((entry?.feel ?? "").split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }.filter { $0 >= 0 && $0 < targets.count })
        let milestones = (entry?.prompts ?? []).compactMap { line -> VentusMilestone? in
            guard let bar = line.firstIndex(of: "|"), let day = valid(String(line[..<bar])) else { return nil }
            let label = line[line.index(after: bar)...].trimmingCharacters(in: .whitespaces)
            return VentusMilestone(day: day, label: label.isEmpty ? "Milestone" : label)
        }
        .sorted { $0.day < $1.day }
        let title = (entry?.title ?? "").trimmingCharacters(in: .whitespaces)
        return VentusProject(routine: routine, entryId: entry?.id ?? key, name: title.isEmpty ? routine.name : title,
                             goal: entry?.text ?? "", start: start, end: end, targets: targets, achieved: achieved, milestones: milestones)
    }

    func save(_ journal: KairosJournal, reason: String) {
        var entry = journal.entry(entryId) ?? KairosEntry(id: entryId, routine: routine.id.uuidString, routineName: routine.name, day: start,
                                                          slot: "", step: "project", title: name, tag: "project")
        entry.routineName = routine.name
        entry.slot = ""
        entry.step = "project"
        entry.tag = "project"
        entry.title = name
        entry.text = goal
        entry.day = start
        entry.notes = end
        entry.lines = targets
        entry.feel = achieved.isEmpty ? nil : achieved.sorted().map(String.init).joined(separator: ",")
        entry.prompts = milestones.map { "\($0.day)|\($0.label)" }
        journal.put(entry)
        note("kairos project saved routine=\(routine.name) name=\(name) start=\(start) end=\(end) targets=\(targets.count) achieved=\(achieved.count) milestones=\(milestones.count) reason=\(reason)")
    }

    func state(_ day: String, today: String) -> KairosDayState {
        guard day >= start, day <= end else { return .off }
        return KairosDayState.of(routine, on: day, today: today)
    }

    func status(_ day: String, today: String) -> KairosDayState {
        guard day >= start, day <= end else { return .off }
        return KairosDayState.status(routine, on: day, today: today)
    }

    func nextMilestone(after today: String) -> VentusMilestone? {
        milestones.first { $0.day >= today }
    }

    func streak(_ today: String) -> Int {
        var day = min(today, end)
        var count = 0
        var guardDays = 0
        while day >= start && guardDays < 800 {
            guardDays += 1
            let status = self.status(day, today: today)
            if status == .done {
                count += 1
            } else if !(day == today || status == .off || state(day, today: today) == .rest) {
                break
            }
            day = ScheduleDays.shift(day, by: -1)
        }
        return count
    }

    func workouts(_ journal: KairosJournal) -> [KairosEntry] {
        journal.entries.filter { $0.tag == "workout" && KairosFit.same($0, routine) }
    }

    func runs(_ journal: KairosJournal) -> [KairosEntry] {
        journal.entries
            .filter { KairosFit.same($0, routine) && ($0.tag == "run" || ($0.tag == "workout" && $0.step == "run")) && ($0.km != nil || $0.seconds != nil) }
            .sorted { $0.day != $1.day ? $0.day > $1.day : ($0.updated ?? "") > ($1.updated ?? "") }
    }

    func doneSeconds(_ day: String) -> Int {
        let store = ScheduleStore.shared
        return ScheduleSlot.allCases.flatMap { store.items(on: day, slot: $0, in: [routine]) }
            .filter(\.done).reduce(0) { $0 + KairosPlan.estimate($1.step) }
    }

    func best(_ index: Int, _ journal: KairosJournal) -> Double? {
        guard targets.indices.contains(index) else { return nil }
        let target = targets[index]
        let lower = target.lowercased()
        if KairosFit.matches(KairosFit.kmPattern, target) {
            return ((runs(journal).compactMap(\.km).max() ?? 0) * 100).rounded() / 100
        }
        if lower.contains("rope") || lower.contains("skip") {
            let best = workouts(journal).filter { $0.step == "rope" }.compactMap { Double(($0.text ?? "").trimmingCharacters(in: .whitespaces)) }.max() ?? 0
            return best
        }
        return nil
    }

    func progress(_ index: Int, _ journal: KairosJournal) -> Double {
        if achieved.contains(index) { return 1 }
        guard targets.indices.contains(index), let goal = KairosFit.number(targets[index]), goal > 0, let best = best(index, journal) else { return 0 }
        return max(0, min(1, best / goal))
    }

    func feels(_ journal: KairosJournal) -> [Int] {
        journal.entries
            .filter { KairosFit.same($0, routine) && ($0.tag == "feel" || $0.tag == "workout") }
            .sorted { $0.day != $1.day ? $0.day < $1.day : ($0.updated ?? "") < ($1.updated ?? "") }
            .compactMap { KairosFit.feelScore($0.feel) }
            .suffix(7)
            .map { $0 }
    }

    func nextSession(after today: String) -> (day: String, steps: [ScheduleStep])? {
        for offset in 1...21 {
            let day = ScheduleDays.shift(today, by: offset)
            guard day <= end else { return nil }
            let steps = KairosSession.of(routine, on: day).flatMap(\.steps)
            if !steps.isEmpty { return (day, steps) }
        }
        return nil
    }
}
