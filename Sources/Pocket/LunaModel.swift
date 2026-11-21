import AppKit
import Combine
import Foundation
import SwiftUI

enum LunaBoard: BoardScope {
    static var theme: BoardTheme { AppThemeStore.shared.theme(for: "sleep") }
    static var tone: Color { theme.id == "lavender" ? Color(hue: 256, saturation: 34, lightness: 46) : theme.accentInk }
    static var soft: Color { theme.isDark ? theme.line : (theme.id == "lavender" ? Color(hue: 258, saturation: 50, lightness: 86) : theme.swatch) }
    static var track: Color { theme.isDark ? theme.line : (theme.id == "lavender" ? Color(hue: 258, saturation: 36, lightness: 88) : theme.line.opacity(0.8)) }
    static let deep = Color(hue: 252, saturation: 42, lightness: 30)
    static let core = Color(hue: 256, saturation: 44, lightness: 56)
    static let rem = Color(hue: 276, saturation: 58, lightness: 74)
    static let awake = Color(hue: 30, saturation: 88, lightness: 74)
    static let good = Color(hue: 152, saturation: 38, lightness: 36)
    static let goodSoft = Color(hue: 152, saturation: 40, lightness: 90)
    static let fix = Color(hue: 26, saturation: 72, lightness: 46)
    static let fixSoft = Color(hue: 28, saturation: 80, lightness: 91)

    static func stage(_ stage: LunaStage) -> Color {
        switch stage {
        case .deep: return deep
        case .core: return core
        case .rem: return rem
        case .awake: return awake
        }
    }

    static func score(_ value: Int?) -> Color {
        guard let value else { return line }
        if value >= 80 { return tone }
        if value >= 70 { return rem }
        return awake
    }
}

enum LunaStage: String, CaseIterable, Identifiable {
    case deep
    case core
    case rem
    case awake

    var id: String { rawValue }
    var label: String {
        switch self {
        case .deep: return "Deep"
        case .core: return "Core"
        case .rem: return "REM"
        case .awake: return "Awake"
        }
    }
    var lane: Int {
        switch self {
        case .awake: return 0
        case .rem: return 1
        case .core: return 2
        case .deep: return 3
        }
    }
}

struct LunaSample: Codable, Equatable {
    var fields: [String: Loose]

    init(fields: [String: Loose]) { self.fields = fields }

    init(from decoder: Decoder) throws {
        fields = try decoder.singleValueContainer().decode([String: Loose].self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(fields)
    }

    var id: String { fields["id"]?.string ?? "" }
}

struct LunaBook: Codable, Equatable {
    var samples: [LunaSample] = []
    var settings: [String: Loose] = [:]

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        samples = try c.decodeIfPresent([LunaSample].self, forKey: .samples) ?? []
        settings = try c.decodeIfPresent([String: Loose].self, forKey: .settings) ?? [:]
    }
}

struct LunaSettings: Equatable {
    var bed = "23:00"
    var wake = "06:30"
    var hours = 8.0
    var deep = 15.0
    var rem = 20.0
    var tolerance = 20.0

    init() {}

    init(_ raw: [String: Loose]) {
        if let text = raw["bed"]?.string, LunaSettings.valid(text) { bed = text }
        if let text = raw["wake"]?.string, LunaSettings.valid(text) { wake = text }
        if let value = raw["hours"]?.number, value > 0 { hours = value }
        if let value = raw["deep"]?.number, value > 0 { deep = value }
        if let value = raw["rem"]?.number, value > 0 { rem = value }
        if let value = raw["tolerance"]?.number, value > 0 { tolerance = value }
    }

    static func valid(_ text: String) -> Bool {
        text.range(of: #"^\d{1,2}:\d{2}$"#, options: .regularExpression) != nil
    }

    static func minutes(_ text: String) -> Int {
        let parts = text.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return 0 }
        return parts[0] * 60 + parts[1]
    }

    var bedMinutes: Int { Self.minutes(bed) }
    var wakeMinutes: Int { Self.minutes(wake) }
}

struct LunaSegment: Equatable {
    let stage: LunaStage
    let start: Int64
    let end: Int64
}

struct LunaNight: Equatable, Identifiable {
    let key: String
    let bed: Int64
    let wake: Int64
    let deep: Int
    let core: Int
    let rem: Int
    let awake: Int
    let asleep: Int
    let inBed: Int
    let segments: [LunaSegment]
    var hr: Int?
    var hrv: Int?
    var deepPct: Double = 0
    var remPct: Double = 0
    var bedDelta = 0
    var wakeDelta = 0
    var score = 0

    var id: String { key }

    func minutes(_ stage: LunaStage) -> Int {
        switch stage {
        case .deep: return deep
        case .core: return core
        case .rem: return rem
        case .awake: return awake
        }
    }
}

struct LunaLine: Equatable, Identifiable {
    let ok: Bool
    let text: String
    var id: String { (ok ? "ok|" : "fix|") + text }
}

struct LunaStages: Equatable {
    var deep: Double = 0
    var core: Double = 0
    var rem: Double = 0
    var awake: Double = 0

    func value(_ stage: LunaStage) -> Double {
        switch stage {
        case .deep: return deep
        case .core: return core
        case .rem: return rem
        case .awake: return awake
        }
    }

    var total: Double { deep + core + rem + awake }
}

struct LunaWeek: Equatable {
    let keys: [String]
    let nights: [LunaNight]
    let avgAsleep: Double?
    let avgScore: Int?
    let spread: Int?
    let over: Int
    let count: Int
    let change: Int?
    let stages: LunaStages
    let comments: [LunaLine]
}

struct LunaMonth: Equatable {
    let keys: [String]
    let nights: [LunaNight]
    let avgAsleep: Double?
    let avgScore: Int?
    let spread: Int?
    let stages: LunaStages
    let comments: [LunaLine]
}

enum LunaDays {
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

    static func key(_ date: Date) -> String {
        keyFormat.timeZone = .current
        return keyFormat.string(from: date)
    }

    static func key(ms: Int64) -> String { key(LunaMath.date(ms)) }

    static func date(_ key: String) -> Date? {
        keyFormat.timeZone = .current
        return keyFormat.date(from: key)
    }

    static func today() -> String { key(Date()) }

    static func shift(_ key: String, by days: Int) -> String {
        guard let date = date(key), let moved = calendar.date(byAdding: .day, value: days, to: date) else { return key }
        return self.key(moved)
    }

    static func weekday(_ key: String) -> Int { date(key).map { calendar.component(.weekday, from: $0) } ?? 1 }

    static func weekStart(_ key: String) -> String { shift(key, by: -((weekday(key) + 5) % 7)) }

    static func week(_ key: String) -> [String] {
        let start = weekStart(key)
        return (0..<7).map { shift(start, by: $0) }
    }

    static func monthStart(_ key: String) -> String { String(key.prefix(8)) + "01" }

    static func month(_ key: String) -> [String] {
        let start = monthStart(key)
        guard let d = date(start), let range = calendar.range(of: .day, in: .month, for: d) else { return [start] }
        return range.map { shift(start, by: $0 - 1) }
    }

    static func monthShift(_ key: String, by months: Int) -> String {
        guard let d = date(monthStart(key)), let moved = calendar.date(byAdding: .month, value: months, to: d) else { return key }
        return self.key(moved)
    }

    static func dayNumber(_ key: String) -> Int { Int(key.suffix(2)) ?? 0 }

    static let monthNames = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
    static let dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    static func monthName(_ key: String) -> String {
        let month = Int(key.dropFirst(5).prefix(2)) ?? 1
        return monthNames[max(0, min(11, month - 1))]
    }

    static func dayName(_ key: String) -> String { dayNames[max(0, min(6, weekday(key) - 1))] }

    static func format(_ key: String, _ template: String) -> String {
        guard let d = date(key) else { return key }
        let format = DateFormatter()
        format.locale = .current
        format.setLocalizedDateFormatFromTemplate(template)
        return format.string(from: d)
    }

    static func long(_ key: String) -> String { format(key, "EEEEdMMM") }
    static func pill(_ key: String) -> String { format(key, "EEEd") }
    static func short(_ key: String) -> String { format(key, "dMMM") }

    static func range(_ keys: [String]) -> String {
        guard let first = keys.first, let last = keys.last else { return "" }
        if first.prefix(7) == last.prefix(7) { return "\(dayNumber(first)) – \(short(last))" }
        return "\(short(first)) – \(short(last))"
    }

    static func monthTitle(_ key: String) -> String {
        key.prefix(4) == today().prefix(4) ? monthName(key) : "\(monthName(key)) \(key.prefix(4))"
    }
}

enum LunaMath {
    static let minute: Int64 = 60000
    static let gap: Int64 = 90 * 60000
    static let stageValues: Set<String> = ["InBed", "Asleep", "Core", "Deep", "REM", "Awake"]
    static let rank: [String: Int] = ["InBed": 1, "Awake": 2, "Asleep": 3, "Core": 3, "REM": 4, "Deep": 5]
    static let stageOfRank: [LunaStage] = [.awake, .awake, .awake, .core, .rem, .deep]

    struct Reading {
        let s: Int64
        let e: Int64
        let v: String
        let q: Double?
    }

    static func jsRound(_ value: Double) -> Int { Int((value + 0.5).rounded(.down)) }

    static func date(_ ms: Int64) -> Date { Date(timeIntervalSince1970: Double(ms) / 1000) }

    static func normalValue(_ raw: String) -> String {
        let s = raw.lowercased()
        if s.contains("deep") { return "Deep" }
        if s.contains("rem") { return "REM" }
        if s.contains("core") { return "Core" }
        if s.contains("awake") { return "Awake" }
        if s.contains("bed") { return "InBed" }
        if s.contains("hrv") || s.contains("variability") { return "HRV" }
        if s.contains("hr") || s.contains("heart") { return "HR" }
        return "Asleep"
    }

    static func number(_ raw: Loose?) -> Double? {
        guard let raw else { return nil }
        switch raw {
        case .number(let value): return value.isFinite ? value : nil
        case .string(let text):
            guard let range = text.range(of: #"-?\d+(?:[.,]\d+)?"#, options: .regularExpression) else { return nil }
            return Double(text[range].replacingOccurrences(of: ",", with: "."))
        default: return nil
        }
    }

    private static let isoFractional: ISO8601DateFormatter = {
        let format = ISO8601DateFormatter()
        format.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return format
    }()

    private static let isoPlain: ISO8601DateFormatter = {
        let format = ISO8601DateFormatter()
        format.formatOptions = [.withInternetDateTime]
        return format
    }()

    private static let fallbacks: [DateFormatter] = ["yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX", "yyyy-MM-dd'T'HH:mm:ssXXXXX", "yyyy-MM-dd'T'HH:mmXXXXX",
                                                      "yyyy-MM-dd HH:mm:ss XXXXX", "yyyy-MM-dd HH:mm:ssXXXXX", "yyyy-MM-dd'T'HH:mm:ss"].map { (pattern: String) -> DateFormatter in
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.calendar = Calendar(identifier: .gregorian)
        format.dateFormat = pattern
        return format
    }

    static func parse(_ text: String) -> Int64? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let date: Date? = {
            if let date = isoFractional.date(from: trimmed) { return date }
            if let date = isoPlain.date(from: trimmed) { return date }
            let short = trimmed.replacingOccurrences(of: #"\.(\d{3})\d+"#, with: ".$1", options: .regularExpression)
            if let date = isoFractional.date(from: short) { return date }
            for format in fallbacks {
                format.timeZone = .current
                if let date = format.date(from: trimmed) { return date }
            }
            return nil
        }()
        guard let date else { return nil }
        return Int64((date.timeIntervalSince1970 * 1000).rounded())
    }

    static func normalise(_ sample: LunaSample) -> Reading? {
        guard let start = sample.fields["s"]?.string, let end = sample.fields["e"]?.string,
              let s = parse(start), let e = parse(end), e >= s else { return nil }
        let v = normalValue(sample.fields["v"]?.string ?? "")
        return Reading(s: s, e: e, v: v, q: v == "HR" || v == "HRV" ? number(sample.fields["q"]) : nil)
    }

    static func clockMinutes(_ ms: Int64) -> Int {
        let parts = LunaDays.calendar.dateComponents([.hour, .minute], from: date(ms))
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    static func wrap(_ minutes: Int) -> Int { ((((minutes + 720) % 1440) + 1440) % 1440) - 720 }

    private struct Cluster {
        var start: Int64
        var end: Int64
        var items: [Reading]
    }

    private static func clusters(_ stages: [Reading]) -> [Cluster] {
        var out: [Cluster] = []
        for x in stages {
            if var current = out.last, x.s <= current.end + gap {
                current.items.append(x)
                if x.e > current.end { current.end = x.e }
                out[out.count - 1] = current
            } else {
                out.append(Cluster(start: x.s, end: x.e, items: [x]))
            }
        }
        return out
    }

    private static func build(_ cluster: Cluster) -> LunaNight {
        let bed = cluster.start
        let wake = cluster.end
        let n = Int((wake - bed) / minute)
        var ranks = [Int](repeating: 0, count: max(0, n))
        for x in cluster.items {
            let r = rank[x.v] ?? 0
            let a = max(0, Int((Double(x.s - bed) / Double(minute)).rounded(.up)))
            let b = min(n, Int((Double(x.e - bed) / Double(minute)).rounded(.up)))
            if a < b {
                for i in a..<b where ranks[i] < r { ranks[i] = r }
            }
        }
        var counts: [LunaStage: Int] = [.deep: 0, .core: 0, .rem: 0, .awake: 0]
        var spans: [(stage: LunaStage, start: Int, end: Int)] = []
        for i in 0..<max(0, n) {
            let stage = stageOfRank[ranks[i]]
            counts[stage, default: 0] += 1
            if let last = spans.last, last.stage == stage {
                spans[spans.count - 1].end = i + 1
            } else {
                spans.append((stage, i, i + 1))
            }
        }
        let deep = counts[.deep] ?? 0
        let core = counts[.core] ?? 0
        let rem = counts[.rem] ?? 0
        return LunaNight(key: LunaDays.key(ms: wake), bed: bed, wake: wake, deep: deep, core: core, rem: rem, awake: counts[.awake] ?? 0,
                         asleep: deep + core + rem, inBed: max(0, n),
                         segments: spans.map { LunaSegment(stage: $0.stage, start: bed + Int64($0.start) * minute, end: bed + Int64($0.end) * minute) })
    }

    static func mean(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    static func spread(_ values: [Double]) -> Double? {
        guard let m = mean(values) else { return nil }
        return mean(values.map { ($0 - m) * ($0 - m) }).map { $0.squareRoot() }
    }

    static func score(_ night: LunaNight, _ st: LunaSettings) -> Int {
        let deepPct = night.asleep > 0 ? Double(night.deep) / Double(night.asleep) * 100 : 0
        let remPct = night.asleep > 0 ? Double(night.rem) / Double(night.asleep) * 100 : 0
        let a = 40 * min(Double(night.asleep) / (st.hours * 60), 1)
        let b = 20 * min(deepPct / st.deep, 1)
        let c = 20 * min(remPct / st.rem, 1)
        let d = 10 * max(0, 1 - Double(abs(night.bedDelta)) / 90)
        let e = 10 * (night.inBed > 0 ? Double(night.asleep) / Double(night.inBed) : 0)
        return jsRound(a + b + c + d + e)
    }

    static func readings(_ samples: [LunaSample]) -> [Reading] { samples.compactMap(normalise) }

    static func nights(_ all: [Reading], _ st: LunaSettings) -> [LunaNight] {
        let stages = all.filter { stageValues.contains($0.v) }.sorted { $0.s != $1.s ? $0.s < $1.s : $0.e < $1.e }
        let hr = all.filter { $0.v == "HR" && $0.q != nil }
        let hrv = all.filter { $0.v == "HRV" && $0.q != nil }
        var byKey: [String: LunaNight] = [:]
        for cluster in clusters(stages) {
            let night = build(cluster)
            if night.asleep < 60 { continue }
            if let previous = byKey[night.key], night.asleep <= previous.asleep { continue }
            byKey[night.key] = night
        }
        func inside(_ list: [Reading], _ night: LunaNight) -> Int? {
            let values = list.filter { $0.s >= night.bed && $0.s <= night.wake }.compactMap(\.q)
            return mean(values).map(jsRound)
        }
        return byKey.values.sorted { $0.key < $1.key }.map { (found: LunaNight) -> LunaNight in
            var night = found
            night.hr = inside(hr, night)
            night.hrv = inside(hrv, night)
            night.deepPct = night.asleep > 0 ? Double(night.deep) / Double(night.asleep) * 100 : 0
            night.remPct = night.asleep > 0 ? Double(night.rem) / Double(night.asleep) * 100 : 0
            night.bedDelta = wrap(clockMinutes(night.bed) - st.bedMinutes)
            night.wakeDelta = wrap(clockMinutes(night.wake) - st.wakeMinutes)
            night.score = score(night, st)
            return night
        }
    }

    private static func pick(_ lines: [LunaLine], _ most: Int) -> [LunaLine] {
        let fixes = Array(lines.filter { !$0.ok }.prefix(min(2, most)))
        let oks = Array(lines.filter(\.ok).prefix(max(0, most - fixes.count)))
        return oks + fixes
    }

    static func nightComments(_ night: LunaNight, _ st: LunaSettings) -> [LunaLine] {
        let tol = st.tolerance
        var out: [LunaLine] = []
        let asleep = LunaText.duration(Double(night.asleep))
        out.append(Double(night.asleep) >= st.hours * 60 - 30 ? LunaLine(ok: true, text: "\(asleep) asleep")
                   : LunaLine(ok: false, text: "\(asleep), under \(LunaText.hours(st.hours))h"))
        out.append(night.deepPct >= st.deep ? LunaLine(ok: true, text: "Deep \(LunaText.duration(Double(night.deep))), above \(LunaText.number(st.deep))%")
                   : LunaLine(ok: false, text: "Deep \(jsRound(night.deepPct))%, under \(LunaText.number(st.deep))%"))
        out.append(night.remPct >= st.rem ? LunaLine(ok: true, text: "REM \(LunaText.duration(Double(night.rem))), above \(LunaText.number(st.rem))%")
                   : LunaLine(ok: false, text: "REM \(jsRound(night.remPct))%, under \(LunaText.number(st.rem))%"))
        let bed = Double(night.bedDelta)
        if abs(bed) <= tol {
            out.append(LunaLine(ok: true, text: "In bed by \(LunaText.clock(night.bed))"))
        } else if bed > tol {
            out.append(LunaLine(ok: false, text: "Bed \(night.bedDelta) min after \(LunaText.clock(st.bed, suffix: false))"))
        } else {
            out.append(LunaLine(ok: true, text: "Bed \(-night.bedDelta) min early"))
        }
        let wake = Double(night.wakeDelta)
        if abs(wake) <= tol {
            out.append(LunaLine(ok: true, text: "Woke within \(LunaText.number(tol)) min of \(LunaText.clock(st.wake, suffix: false))"))
        } else if wake > tol {
            out.append(LunaLine(ok: false, text: "Woke \(night.wakeDelta) min after \(LunaText.clock(st.wake, suffix: false))"))
        }
        return pick(out, 3)
    }

    private static func inKeys(_ all: [LunaNight], _ keys: [String]) -> [LunaNight] {
        let set = Set(keys)
        return all.filter { set.contains($0.key) }
    }

    private static func stageAverages(_ list: [LunaNight]) -> LunaStages {
        guard !list.isEmpty else { return LunaStages() }
        func avg(_ stage: LunaStage) -> Double { mean(list.map { Double($0.minutes(stage)) }) ?? 0 }
        return LunaStages(deep: avg(.deep), core: avg(.core), rem: avg(.rem), awake: avg(.awake))
    }

    static func week(_ all: [LunaNight], _ key: String, _ st: LunaSettings) -> LunaWeek {
        let keys = LunaDays.week(key)
        let list = inKeys(all, keys)
        let previous = inKeys(all, LunaDays.week(LunaDays.shift(keys[0], by: -7)))
        let avgAsleep = mean(list.map { Double($0.asleep) })
        let prevAsleep = mean(previous.map { Double($0.asleep) })
        let goal = (st.hours - 1) * 60
        let over = list.filter { Double($0.asleep) >= goal }.count
        let bedSpread = spread(list.map { Double($0.bedDelta) })
        var lines: [LunaLine] = []
        if !list.isEmpty {
            let text = "\(over) of \(list.count) nights over \(LunaText.hours(st.hours - 1))h"
            lines.append(LunaLine(ok: Double(over) / Double(list.count) >= 0.7, text: text))
            var late = list[0]
            for night in list.dropFirst() where night.bedDelta > late.bedDelta { late = night }
            if late.bedDelta > 60 { lines.append(LunaLine(ok: false, text: "\(LunaDays.dayName(late.key)) bed \(LunaText.clock(late.bed))")) }
            if let avgAsleep, let prevAsleep {
                let d = avgAsleep - prevAsleep
                if d >= 10 { lines.append(LunaLine(ok: true, text: "\(jsRound(d))m more than last week")) }
                else if d <= -10 { lines.append(LunaLine(ok: false, text: "\(jsRound(-d))m less than last week")) }
            }
        }
        var change: Int?
        if let avgAsleep, let prevAsleep { change = jsRound(avgAsleep - prevAsleep) }
        return LunaWeek(keys: keys, nights: list, avgAsleep: avgAsleep,
                        avgScore: list.isEmpty ? nil : mean(list.map { Double($0.score) }).map(jsRound),
                        spread: bedSpread.map(jsRound), over: over, count: list.count, change: change,
                        stages: stageAverages(list),
                        comments: pick(lines, 3))
    }

    static func month(_ all: [LunaNight], _ key: String, _ st: LunaSettings) -> LunaMonth {
        let keys = LunaDays.month(key)
        let list = inKeys(all, keys)
        let prevKey = LunaDays.monthShift(key, by: -1)
        let previous = inKeys(all, LunaDays.month(prevKey))
        let avgAsleep = mean(list.map { Double($0.asleep) })
        let bedSpread = spread(list.map { Double($0.bedDelta) })
        var lines: [LunaLine] = []
        if !list.isEmpty {
            if !previous.isEmpty, let now = mean(list.map { Double($0.deep) }), let before = mean(previous.map { Double($0.deep) }) {
                let d = now - before
                if d >= 5 { lines.append(LunaLine(ok: true, text: "Deep up \(jsRound(d)) min vs \(LunaDays.monthName(prevKey))")) }
                else if d <= -5 { lines.append(LunaLine(ok: false, text: "Deep down \(jsRound(-d)) min vs \(LunaDays.monthName(prevKey))")) }
            }
            let isWeekend: (LunaNight) -> Bool = { [1, 7].contains(LunaDays.weekday($0.key)) }
            let weekend = list.filter(isWeekend).map { Double($0.bedDelta) }
            let weekdays = list.filter { !isWeekend($0) }.map { Double($0.bedDelta) }
            if let a = mean(weekend), let b = mean(weekdays) {
                let d = a - b
                if d >= 30 { lines.append(LunaLine(ok: false, text: "Weekends \(jsRound(d)) min later")) }
            }
            let sd = jsRound(bedSpread ?? 0)
            lines.append(sd <= 30 ? LunaLine(ok: true, text: "Bedtime within ±\(sd)m") : LunaLine(ok: false, text: "Bedtime varies ±\(sd)m"))
            let avg = avgAsleep ?? 0
            lines.append(avg >= st.hours * 60 - 30 ? LunaLine(ok: true, text: "\(LunaText.duration(avg)) average")
                         : LunaLine(ok: false, text: "\(LunaText.duration(avg)) average, under \(LunaText.hours(st.hours))h"))
        }
        return LunaMonth(keys: keys, nights: list, avgAsleep: avgAsleep,
                         avgScore: list.isEmpty ? nil : mean(list.map { Double($0.score) }).map(jsRound),
                         spread: bedSpread.map(jsRound), stages: stageAverages(list), comments: pick(lines, 2))
    }
}

enum LunaText {
    static func duration(_ minutes: Double) -> String {
        let m = LunaMath.jsRound(minutes)
        if m < 60 { return "\(m)m" }
        return "\(m / 60)h "+ String(format: "%02d", m % 60) + "m"
    }

    static func clock(_ ms: Int64) -> String {
        let parts = LunaDays.calendar.dateComponents([.hour, .minute], from: LunaMath.date(ms))
        let h = parts.hour ?? 0
        let hour = h % 12 == 0 ? 12 : h % 12
        return "\(hour):" + String(format: "%02d", parts.minute ?? 0) + (h < 12 ? " am" : " pm")
    }

    static func clock(_ text: String, suffix: Bool = true) -> String {
        let m = LunaSettings.minutes(text)
        let h = (m / 60) % 24
        let hour = h % 12 == 0 ? 12 : h % 12
        return "\(hour):" + String(format: "%02d", m % 60) + (suffix ? (h < 12 ? " am" : " pm") : "")
    }

    static func number(_ value: Double) -> String {
        if value == value.rounded(), abs(value) < 1e15 { return String(Int64(value)) }
        return String(value)
    }

    static func hours(_ value: Double) -> String {
        if value == value.rounded(), abs(value) < 1e15 { return String(Int64(value)) }
        return number(Double(LunaMath.jsRound(value * 10)) / 10)
    }

    static func span(_ start: Int64, _ end: Int64) -> String { "\(clock(start)) – \(clock(end))" }

    static func day(_ key: String) -> String { "\(LunaDays.dayName(key)) \(LunaDays.dayNumber(key))" }

    static func hourTick(_ ms: Int64, suffix: Bool) -> String {
        let h = LunaDays.calendar.component(.hour, from: LunaMath.date(ms))
        let hour = h % 12 == 0 ? 12 : h % 12
        return suffix ? "\(hour) \(h < 12 ? "am" : "pm")" : "\(hour)"
    }
}

final class LunaStore: ObservableObject {
    static let shared = LunaStore()
    static let name = "sleep"

    @Published private(set) var book = LunaBook()
    @Published private(set) var nights: [LunaNight] = []
    @Published private(set) var settings = LunaSettings()
    @Published private(set) var today = LunaDays.today()
    var onChange: (() -> Void)?
    private var readings: [LunaMath.Reading] = []
    private let file = PocketData.sleep
    private var clock: Timer?

    private static let stamp: ISO8601DateFormatter = {
        let format = ISO8601DateFormatter()
        format.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return format
    }()

    private init() {
        DataVault.shared.register(Self.name) { [weak self] data in self?.merge(data) }
        CloudSync.shared.register(Self.name) { [weak self] data in self?.adopt(data) }
        book = load()
        recompute()
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        clock = timer
    }

    private func load() -> LunaBook {
        let vault = DataVault.shared
        if FileManager.default.fileExists(atPath: file.path) {
            do {
                let loaded = try Self.decode(Data(contentsOf: file))
                note("luna loaded samples=\(loaded.samples.count) settings=\(!loaded.settings.isEmpty) path=\(file.path)")
                return loaded
            } catch {
                note("luna load failed path=\(file.path) error=\(error.localizedDescription)")
                vault.quarantine(file, name: Self.name)
            }
        }
        if let (saved, snap) = vault.recover(Self.name, decode: Self.decode) {
            note("luna recovered from=\(snap.url.path) samples=\(saved.samples.count)")
            write(saved)
            return saved
        }
        note("luna started empty path=\(file.path)")
        return LunaBook()
    }

    static func decode(_ data: Data) throws -> LunaBook {
        try JSONDecoder().decode(LunaBook.self, from: data)
    }

    static func encode(_ book: LunaBook) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(book)
    }

    static func now() -> String { stamp.string(from: Date()) }

    private func recompute() {
        settings = LunaSettings(book.settings)
        readings = LunaMath.readings(book.samples)
        nights = LunaMath.nights(readings, settings)
    }

    func tick() {
        let next = LunaDays.today()
        guard next != today else { return }
        today = next
        note("luna day changed day=\(today)")
        onChange?()
    }

    var latest: LunaNight? { nights.last }

    func night(_ key: String) -> LunaNight? { nights.last { $0.key == key } }

    func recent(_ count: Int) -> [LunaNight] { Array(nights.suffix(count).reversed()) }

    func comments(_ night: LunaNight) -> [LunaLine] { LunaMath.nightComments(night, settings) }

    func week(_ key: String) -> LunaWeek { LunaMath.week(nights, key, settings) }

    func month(_ key: String) -> LunaMonth { LunaMath.month(nights, key, settings) }

    var lastSample: Date? {
        let ends = readings.map(\.e)
        return ends.max().map(LunaMath.date)
    }

    func edit(_ key: String, _ value: Loose) {
        guard book.settings[key] != value else { return }
        let before = settings
        book.settings[key] = value
        book.settings["updated"] = .string(Self.now())
        commit()
        note("luna settings changed key=\(key) bed=\(settings.bed) wake=\(settings.wake) hours=\(settings.hours) deep=\(settings.deep) rem=\(settings.rem) tolerance=\(settings.tolerance) previous=\(before.bed)/\(before.wake)/\(before.hours)")
    }

    func setTime(_ key: String, _ date: Date) {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        edit(key, .string(String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)))
    }

    func setNumber(_ key: String, _ value: Double) {
        guard value > 0 else { return }
        edit(key, .number(value))
    }

    func refresh(source: String) {
        note("luna refresh source=\(source) configured=\(CloudSync.shared.configured) samples=\(book.samples.count)")
        CloudSync.shared.syncNow()
    }

    func snapshots() -> [(snapshot: VaultSnapshot, samples: Int)] {
        DataVault.shared.snapshots(Self.name).map { snap in
            let count = (try? Self.decode(Data(contentsOf: snap.url)))?.samples.count ?? 0
            return (snap, count)
        }
    }

    func restore(_ snap: VaultSnapshot) {
        do {
            let saved = try Self.decode(Data(contentsOf: snap.url))
            if let current = try? Self.encode(book) { DataVault.shared.keepAside(current, name: Self.name, reason: "before-restore") }
            var restored = saved
            let kept = Set(restored.samples.map(\.id))
            let missing = book.samples.filter { !kept.contains($0.id) }
            restored.samples += missing
            book = restored
            commit()
            note("luna restored from=\(snap.url.path) samples=\(saved.samples.count) keptCurrent=\(missing.count)")
        } catch {
            note("luna restore failed from=\(snap.url.path) error=\(error.localizedDescription)")
        }
    }

    func merge(_ data: Data) {
        do {
            let incoming = try Self.decode(data)
            if let current = try? Self.encode(book) { DataVault.shared.keepAside(current, name: Self.name, reason: "before-merge") }
            var known = Set(book.samples.map(\.id))
            var added = 0
            for sample in incoming.samples where !sample.id.isEmpty && !known.contains(sample.id) {
                book.samples.append(sample)
                known.insert(sample.id)
                added += 1
            }
            let mine = book.settings["updated"]?.string ?? ""
            let theirs = incoming.settings["updated"]?.string ?? ""
            if book.settings.isEmpty || (!incoming.settings.isEmpty && theirs > mine) { book.settings = incoming.settings }
            commit()
            note("luna merged added=\(added) samples=\(book.samples.count)")
        } catch {
            note("luna merge failed bytes=\(data.count) error=\(error.localizedDescription)")
        }
    }

    func adopt(_ data: Data) {
        do {
            let incoming = try Self.decode(data)
            guard incoming != book else { return }
            let before = book.samples.count
            let nightsBefore = nights.count
            book = incoming
            write(book)
            recompute()
            onChange?()
            note("luna adopted cloud samples=\(before)->\(book.samples.count) nights=\(nightsBefore)->\(nights.count)")
        } catch {
            note("luna adopt failed bytes=\(data.count) error=\(error.localizedDescription)")
        }
    }

    private func commit() {
        write(book)
        recompute()
        onChange?()
    }

    private func write(_ book: LunaBook) {
        do {
            let data = try Self.encode(book)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: file, options: .atomic)
            DataVault.shared.snapshot(data, name: Self.name, count: book.samples.count)
        } catch {
            note("luna save failed samples=\(book.samples.count) error=\(error.localizedDescription)")
        }
    }
}
