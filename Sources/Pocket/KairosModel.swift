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

    var counted: Bool { kind == .count || kind == .rest }
}

enum KairosPlan {
    static let guidedTypes: Set<String> = ["timed", "moves", "intervals", "rounds", "log", "say", "write"]
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

    static func beats(for steps: [ScheduleStep]) -> [KairosBeat] {
        steps.enumerated().flatMap { index, step in beats(step, index: index) }
    }

    static func beats(_ step: ScheduleStep, index: Int) -> [KairosBeat] {
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
        case "timed":
            var beat = base
            beat.kind = .count
            beat.seconds = num(run["seconds"], 60)
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
            beat.lines = (run["lines"]?.list ?? []).compactMap(\.string)
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
        case "timed": return "Timer"
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
        case "say": return "Out loud · \(run["lines"]?.list.count ?? 0) lines, \(num(run["times"], 1)) times each"
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
        let store = ScheduleStore.shared
        return ScheduleSlot.allCases.flatMap { slot in
            store.routines.compactMap { routine -> KairosSession? in
                guard routine.runs(on: day) else { return nil }
                let steps = routine.steps(on: day, slot)
                guard steps.contains(where: KairosPlan.isGuided) else { return nil }
                let done = store.items(on: day, slot: slot, in: [routine]).filter(\.done).count
                return KairosSession(routine: routine, slot: slot, day: day, steps: steps, done: done)
            }
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
    private var clock: Timer?
    private var shownSecond = -1

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.stateKey) {
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
        guard let state, let routine = ScheduleStore.shared.routine(state.routine) else { return nil }
        let steps = routine.steps(on: state.day, state.slot)
        let beats = KairosPlan.beats(for: steps)
        guard !beats.isEmpty else { return nil }
        return KairosLive(routine: routine, steps: steps, beats: beats, index: min(state.index, beats.count - 1))
    }

    var running: Bool { state != nil && state?.finished == nil }

    func isRunning(_ session: KairosSession) -> Bool {
        guard let state, state.finished == nil else { return false }
        return state.routine == session.routine.id && state.slot == session.slot && state.day == session.day
    }

    func start(_ session: KairosSession) {
        let store = ScheduleStore.shared
        let items = store.items(on: session.day, slot: session.slot, in: [session.routine])
        let first = items.firstIndex { !$0.done } ?? 0
        let beats = KairosPlan.beats(for: session.steps)
        let index = max(0, beats.firstIndex { $0.step == first } ?? 0)
        state = KairosRunState(routine: session.routine.id, day: session.day, slot: session.slot, index: index, started: Date(), stepStarted: Date())
        if beats.indices.contains(index) { enter(beats[index], newStep: true) }
        startClock()
        note("kairos run started routine=\(session.routine.name) day=\(session.day) slot=\(session.slot.rawValue) step=\(first + 1) of=\(session.total) beats=\(beats.count)")
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
            UserDefaults.standard.removeObject(forKey: Self.stateKey)
            return
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(state) { UserDefaults.standard.set(data, forKey: Self.stateKey) }
    }

    func chime(strong: Bool) {
        guard Self.sound else { return }
        NSSound(named: strong ? "Glass" : "Tink")?.play()
    }
}
