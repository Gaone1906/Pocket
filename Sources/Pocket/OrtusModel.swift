import Foundation

struct OrtusQuote: Identifiable, Equatable {
    let id: String
    let text: String
    let author: String
    let who: String
    let source: String
    let theme: String
    let moderate: Bool

    init?(_ raw: [String: Any]) {
        guard let id = OrtusLoose.text(raw["id"]), let text = OrtusLoose.text(raw["text"]) else { return nil }
        self.id = id
        self.text = text
        author = OrtusLoose.text(raw["author"]) ?? ""
        who = OrtusLoose.text(raw["who"]) ?? ""
        source = OrtusLoose.text(raw["source"]) ?? ""
        theme = OrtusLoose.text(raw["theme"]) ?? ""
        moderate = OrtusLoose.text(raw["sure"]) == "moderate"
    }

    var credit: String { [who, source].filter { !$0.isEmpty }.joined(separator: " · ") }
}

struct OrtusStory: Identifiable, Equatable {
    let id: String
    let name: String
    let fiction: Bool
    let who: String
    let title: String
    let paras: [String]
    let line: String
    let source: String

    init?(_ raw: [String: Any]) {
        guard let id = OrtusLoose.text(raw["id"]), let title = OrtusLoose.text(raw["title"]) else { return nil }
        self.id = id
        self.title = title
        name = OrtusLoose.text(raw["name"]) ?? ""
        fiction = OrtusLoose.text(raw["kind"]) == "fiction"
        who = OrtusLoose.text(raw["who"]) ?? ""
        paras = (raw["paras"] as? [Any] ?? []).compactMap(OrtusLoose.text)
        line = OrtusLoose.text(raw["line"]) ?? ""
        source = OrtusLoose.text(raw["source"]) ?? ""
    }

    var minutes: Int { max(1, Int((Double(paras.joined(separator: " ").split(whereSeparator: \.isWhitespace).count) / 200).rounded())) }
    var sourceURL: URL? { source.hasPrefix("http") ? URL(string: source) : nil }
}

struct OrtusClip: Identifiable, Equatable {
    let id: String
    let url: String
    let title: String
    let channel: String
    let category: String
    let views: Double
    let start: Int
    let end: Int
    let video: String

    init?(_ raw: [String: Any]) {
        guard let id = OrtusLoose.text(raw["id"]), let url = OrtusLoose.text(raw["url"]), let video = OrtusPick.youtubeId(url) else { return nil }
        self.id = id
        self.url = url
        self.video = video
        title = OrtusPick.cleanTitle(OrtusLoose.text(raw["title"]) ?? "")
        channel = OrtusLoose.text(raw["channel"]) ?? ""
        category = OrtusLoose.text(raw["category"]) ?? ""
        views = OrtusLoose.number(raw["views"]) ?? 0
        start = Int(OrtusLoose.number(raw["start"]) ?? 0)
        end = Int(OrtusLoose.number(raw["end"]) ?? 0)
    }

    var short: Bool { url.contains("/shorts/") }

    var watchURL: URL? {
        if short { return URL(string: "https://www.youtube.com/shorts/\(video)") }
        return URL(string: "https://www.youtube.com/watch?v=\(video)" + (start > 0 ? "&t=\(start)" : ""))
    }

    func embed(autoplay: Bool) -> URL? {
        var parts = ["playsinline=1", "rel=0", "modestbranding=1"]
        if autoplay { parts.append("autoplay=1") }
        if start > 0 { parts.append("start=\(start)") }
        if end > 0 { parts.append("end=\(end)") }
        return URL(string: "https://www.youtube-nocookie.com/embed/\(video)?" + parts.joined(separator: "&"))
    }

    var meta: String {
        [channel, views > 0 ? OrtusPick.views(views) + " views" : ""].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

enum OrtusLoose {
    static func text(_ value: Any?) -> String? {
        if let text = value as? String, !text.isEmpty { return text }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }

    static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let text = value as? String { return Double(text) }
        return nil
    }
}

enum OrtusPick {
    static let quoteThemes = ["Courage", "Resilience", "Purpose", "Mindset", "Perseverance", "Excellence", "Discipline", "Failure", "Patience", "Action"]
    static let reelCategories = ["Speeches", "Never give up", "Discipline", "Legends", "Stories", "Sports", "Kindness & humanity", "Life advice"]

    static func dayKey(_ now: Date = Date()) -> String {
        let shifted = now.addingTimeInterval(-4 * 3600)
        let parts = Calendar(identifier: .gregorian).dateComponents(in: TimeZone.current, from: shifted)
        return String(format: "%04d-%02d-%02d", parts.year ?? 1970, parts.month ?? 1, parts.day ?? 1)
    }

    static func hash(_ text: String) -> UInt32 {
        var value: UInt32 = 0x811c9dc5
        for byte in text.utf8 {
            value ^= UInt32(byte)
            value = value &* 0x01000193
        }
        return value
    }

    static func daily<T: Identifiable>(_ items: [T], kind: String, day: String = dayKey()) -> T? where T.ID == String {
        guard !items.isEmpty else { return nil }
        let sorted = items.sorted { $0.id.utf16.lexicographicallyPrecedes($1.id.utf16) }
        return sorted[Int(hash("\(kind)|\(day)") % UInt32(sorted.count))]
    }

    static func shuffled<T: Identifiable>(_ items: [T], seed: String) -> [T] where T.ID == String {
        items.map { (hash(seed + "|" + $0.id), $0) }.sorted { $0.0 < $1.0 }.map(\.1)
    }

    static func ordered<T: Identifiable>(_ items: [T], kind: String, day: String = dayKey()) -> [T] where T.ID == String {
        let first = daily(items, kind: kind, day: day)
        let rest = shuffled(items.filter { $0.id != first?.id }, seed: day + "|" + kind)
        return (first.map { [$0] } ?? []) + rest
    }

    static func youtubeId(_ url: String) -> String? {
        guard let range = url.range(of: #"(?:shorts/|embed/|youtu\.be/|[?&]v=)[A-Za-z0-9_-]{11}"#, options: .regularExpression) else { return nil }
        return String(url[range].suffix(11))
    }

    static func cleanTitle(_ text: String) -> String {
        var out = text.replacingOccurrences(of: #"#[\p{L}\p{N}_]+"#, with: "", options: .regularExpression)
        out = String(String.UnicodeScalarView(out.unicodeScalars.filter { scalar in
            !((scalar.properties.isEmoji && scalar.value > 0xFF) || scalar.value == 0x200D || scalar.value == 0xFE0F)
        }))
        out = out.replacingOccurrences(of: #"\s*\|+\s*$"#, with: "", options: .regularExpression)
        out = out.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func views(_ value: Double) -> String {
        if value >= 1e9 { return String(format: "%.1fB", value / 1e9).replacingOccurrences(of: ".0B", with: "B") }
        if value >= 1e6 { return "\(Int((value / 1e6).rounded()))M" }
        if value >= 1e3 { return "\(Int((value / 1e3).rounded()))K" }
        return "\(Int(value))"
    }
}

final class OrtusStore: ObservableObject {
    static let shared = OrtusStore()
    static let name = "ortus"
    static let verifiedKey = "ortus.verifiedOnly"
    static let collections = ["quotes", "stories", "reels", "videos"]

    @Published private(set) var allQuotes: [OrtusQuote] = []
    @Published private(set) var stories: [OrtusStory] = []
    @Published private(set) var reels: [OrtusClip] = []
    @Published private(set) var videos: [OrtusClip] = []
    @Published var verifiedOnly = UserDefaults.standard.bool(forKey: OrtusStore.verifiedKey) {
        didSet {
            UserDefaults.standard.set(verifiedOnly, forKey: Self.verifiedKey)
            note("ortus setting changed verifiedOnly=\(verifiedOnly)")
        }
    }

    var onChange: (() -> Void)?
    private let file = PocketData.ortus

    private init() {
        let vault = DataVault.shared
        vault.register(Self.name) { [weak self] data in self?.merge(data) }
        CloudSync.shared.register(Self.name) { [weak self] data in self?.adopt(data) }
        if FileManager.default.fileExists(atPath: file.path) {
            do {
                let data = try Data(contentsOf: file)
                try parse(data)
                note("ortus library loaded quotes=\(allQuotes.count) stories=\(stories.count) reels=\(reels.count) videos=\(videos.count)")
                return
            } catch {
                note("ortus library load failed path=\(file.path) error=\(error.localizedDescription)")
                vault.quarantine(file, name: Self.name)
            }
        }
        if let (saved, snap) = vault.recover(Self.name, decode: Self.check) {
            try? parse(saved)
            write(saved)
            note("ortus library recovered from=\(snap.url.path) quotes=\(allQuotes.count)")
            return
        }
        note("ortus library empty path=\(file.path)")
    }

    var quotes: [OrtusQuote] { verifiedOnly ? allQuotes.filter { !$0.moderate } : allQuotes }
    var empty: Bool { allQuotes.isEmpty && stories.isEmpty && reels.isEmpty && videos.isEmpty }

    static func check(_ data: Data) throws -> Data {
        guard try JSONSerialization.jsonObject(with: data) is [String: Any] else {
            throw NSError(domain: "ortus", code: 1, userInfo: [NSLocalizedDescriptionKey: "not an object"])
        }
        return data
    }

    private func parse(_ data: Data) throws {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "ortus", code: 1, userInfo: [NSLocalizedDescriptionKey: "not an object"])
        }
        func list(_ key: String) -> [[String: Any]] { (object[key] as? [Any] ?? []).compactMap { $0 as? [String: Any] } }
        allQuotes = list("quotes").compactMap(OrtusQuote.init)
        stories = list("stories").compactMap(OrtusStory.init).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        reels = list("reels").compactMap(OrtusClip.init)
        videos = list("videos").compactMap(OrtusClip.init)
        onChange?()
    }

    func adopt(_ data: Data) {
        do {
            let before = allQuotes.count + stories.count + reels.count + videos.count
            try parse(data)
            write(data)
            note("ortus library adopted cloud before=\(before) quotes=\(allQuotes.count) stories=\(stories.count) reels=\(reels.count) videos=\(videos.count)")
        } catch {
            note("ortus library adopt failed bytes=\(data.count) error=\(error.localizedDescription)")
        }
    }

    func merge(_ data: Data) {
        do {
            guard let incoming = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            var current = (try? Data(contentsOf: file)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
            if let existing = try? Data(contentsOf: file) { DataVault.shared.keepAside(existing, name: Self.name, reason: "before-merge") }
            var added = 0
            for key in Self.collections {
                var list = current[key] as? [Any] ?? []
                let ids = Set(list.compactMap { ($0 as? [String: Any]).flatMap { OrtusLoose.text($0["id"]) } })
                for item in incoming[key] as? [Any] ?? [] {
                    guard let id = (item as? [String: Any]).flatMap({ OrtusLoose.text($0["id"]) }), !ids.contains(id) else { continue }
                    list.append(item)
                    added += 1
                }
                current[key] = list
            }
            let merged = try JSONSerialization.data(withJSONObject: current, options: [.prettyPrinted, .sortedKeys])
            try parse(merged)
            write(merged)
            note("ortus library merged added=\(added)")
        } catch {
            note("ortus library merge failed bytes=\(data.count) error=\(error.localizedDescription)")
        }
    }

    private func write(_ data: Data) {
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: file, options: .atomic)
            DataVault.shared.snapshot(data, name: Self.name, count: allQuotes.count + stories.count + reels.count + videos.count)
        } catch {
            note("ortus library save failed error=\(error.localizedDescription)")
        }
    }

    func story(_ id: String?) -> OrtusStory? { stories.first { $0.id == id } }
}
